import Foundation
import Testing

@testable import QuickReminderCore

/// Stands in for Apple Maps: records queries, reports what the test pushes, and resolves either at
/// once or when the test lets it.
@MainActor
final class FakePlaceSearch: PlaceSearchService {
    var onUpdate: ((PlaceSearchUpdate) -> Void)?
    var searched: [String] = []
    var cancels = 0
    var resolveResult: Result<PickedPlace, Error> = .success(slavia)
    /// When set, `resolve` waits for the test to resume it.
    var holdResolve = false
    var pendingResolve: CheckedContinuation<PickedPlace, Error>?

    struct Failure: Error {}

    func search(_ query: String) { searched.append(query) }
    func cancel() { cancels += 1 }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> PickedPlace {
        if holdResolve {
            return try await withCheckedThrowingContinuation { pendingResolve = $0 }
        }
        return try resolveResult.get()
    }

    func send(_ query: String, _ titles: [String]) {
        onUpdate?(.results(query: query, titles.enumerated().map {
            PlaceSuggestion(id: $0.offset + 1, title: $0.element, subtitle: "Praha")
        }))
    }
}

@MainActor
struct PlaceSearchModelTests {
    let fake = FakePlaceSearch()
    let spoken = SpokenLog()

    @MainActor final class SpokenLog { var lines: [String] = [] }

    func makeModel() -> PlaceSearchModel {
        let fake = fake, spoken = spoken
        return PlaceSearchModel(makeService: { fake }, debounce: .zero, sleep: { _ in },
                                announce: { spoken.lines.append($0) })
    }

    /// Types `text` and lets the debounce run.
    func type(_ text: String, into model: PlaceSearchModel, picked: String? = nil) async {
        model.textChanged(text, pickedName: picked)
        await model.debounceTask?.value
    }

    // MARK: Typing / debounce

    @Test func shortQueriesDoNotSearch() async {
        let model = makeModel()
        await type("C", into: model)
        #expect(model.phase == .idle)
        #expect(fake.searched.isEmpty)
        #expect(PlaceSearchModel.statusText(phase: model.phase, query: model.query, hasRows: false) == "Search Apple Maps, or type any place.")
    }

    /// Keystrokes inside the debounce collapse into one query: only the last one is sent.
    @Test func debounceSendsOnlyTheLastQuery() async {
        let model = makeModel()
        model.textChanged("Ca", pickedName: nil)
        model.textChanged("Caf", pickedName: nil)
        model.textChanged("Café ", pickedName: nil)
        #expect(model.phase == .searching)
        await model.debounceTask?.value
        #expect(fake.searched == ["Café"], "trimmed, once")
    }

    @Test func aTrailingSpaceDoesNotAskAgain() async {
        let model = makeModel()
        await type("Café", into: model)
        fake.send("Café", ["Café Slavia", "Café Louvre"])
        model.moveHighlight(by: 1)
        await type("Café ", into: model)
        #expect(fake.searched == ["Café"])
        #expect(model.highlighted == 0, "the highlight survives")
    }

    @Test func resultsAreCappedAndAnnounced() async {
        let model = makeModel()
        await type("Café", into: model)
        fake.send("Café", ["1", "2", "3", "4", "5", "6", "7"])
        #expect(model.phase == .results)
        #expect(model.suggestions.map(\.title) == ["1", "2", "3", "4", "5"])
        #expect(spoken.lines.last == "5 places found. Down arrow to choose.")
        #expect(PlaceSearchModel.statusText(phase: model.phase, query: model.query, hasRows: true) == nil)
    }

    /// Results for an older query arrive late: dropped, the rows on screen stay.
    @Test func staleResultsAreIgnored() async {
        let model = makeModel()
        await type("Caf", into: model)
        fake.send("Caf", ["Café Louvre"])
        await type("Café S", into: model)
        fake.send("Caf", ["Old", "Older"])
        #expect(model.phase == .searching)
        #expect(model.suggestions.map(\.title) == ["Café Louvre"], "previous rows stay (dimmed) while searching")
        #expect(PlaceSearchModel.statusText(phase: model.phase, query: model.query, hasRows: true) == nil, "no jump to a status line")
        fake.send("Café S", ["Café Slavia"])
        #expect(model.suggestions.map(\.title) == ["Café Slavia"])
    }

    @Test func emptyAndFailedStates() async {
        let model = makeModel()
        await type("zzzz", into: model)
        fake.send("zzzz", [])
        #expect(model.phase == .empty)
        #expect(spoken.lines.last == "No places found")
        #expect(PlaceSearchModel.statusText(phase: .empty, query: "zzzz", hasRows: false) == "No places found. Done keeps “zzzz” as a note.")
        await type("zzzzy", into: model)
        fake.onUpdate?(.failed(query: "zzzzy"))
        #expect(model.phase == .failed)
        #expect(model.suggestions.isEmpty)
        #expect(PlaceSearchModel.statusText(phase: .failed, query: "zzzzy", hasRows: false) != nil)
    }

    @Test func clearingTheFieldStopsTheSearch() async {
        let model = makeModel()
        await type("Café", into: model)
        fake.send("Café", ["Café Slavia"])
        await type("", into: model)
        #expect(model.phase == .idle)
        #expect(model.suggestions.isEmpty)
        #expect(fake.cancels >= 1)
    }

    /// Closing the section mid-debounce: the query is never sent.
    @Test func cancelDropsAPendingQuery() async {
        let fake = fake
        let model = PlaceSearchModel(makeService: { fake }, debounce: .zero,
                                     sleep: { _ in try await Task.sleep(for: .seconds(60)) }, announce: { _ in })
        model.textChanged("Café", pickedName: nil)
        model.cancel()
        await model.debounceTask?.value
        #expect(fake.searched.isEmpty)
    }

    // MARK: Keyboard

    @Test func arrowsMoveTheHighlight() async {
        let model = makeModel()
        #expect(!model.moveHighlight(by: 1), "no rows: the field keeps ↓")
        await type("Café", into: model)
        fake.send("Café", ["A", "B", "C"])
        #expect(!model.moveHighlight(by: -1), "↑ from the field is the field's")
        #expect(model.moveHighlight(by: 1))
        #expect(model.highlighted == 0)
        #expect(model.highlightedSuggestion?.title == "A")
        #expect(spoken.lines.last == "A, Praha, 1 of 3")
        model.moveHighlight(by: 1)
        model.moveHighlight(by: 1)
        model.moveHighlight(by: 1)
        #expect(model.highlighted == 2, "no wrap at the end")
        model.moveHighlight(by: -1)
        model.moveHighlight(by: -1)
        model.moveHighlight(by: -1)
        #expect(model.highlighted == nil, "↑ from the first row returns to the field")
        #expect(model.highlightedSuggestion == nil, "↩ is Done again")
    }

    @Test func newResultsResetTheHighlight() async {
        let model = makeModel()
        await type("Café", into: model)
        fake.send("Café", ["A", "B"])
        model.moveHighlight(by: 1)
        await type("Café S", into: model)
        #expect(model.highlighted == nil)
        fake.send("Café S", ["C"])
        #expect(model.highlighted == nil)
    }

    // MARK: Picking

    @Test func pickingResolvesThePlace() async {
        let model = makeModel()
        await type("slav", into: model)
        fake.send("slav", ["Café Slavia"])
        let outcome = await model.pick(model.suggestions[0])
        #expect(outcome == .place(slavia))
        #expect(model.phase == .picked)
        #expect(model.suggestions.isEmpty)
        #expect(spoken.lines.last == "Picked Café Slavia")
        // The pick writes the name into the field: no new search.
        await type("Café Slavia", into: model, picked: "Café Slavia")
        #expect(model.phase == .picked)
        #expect(fake.searched == ["slav"])
        // Typing over it searches again.
        await type("Café Slavia 2", into: model, picked: nil)
        #expect(model.phase == .searching)
        #expect(fake.searched == ["slav", "Café Slavia 2"])
    }

    @Test func aFailedPickKeepsTheTitleAsText() async {
        fake.resolveResult = .failure(FakePlaceSearch.Failure())
        let model = makeModel()
        await type("slav", into: model)
        fake.send("slav", ["Café Slavia"])
        let outcome = await model.pick(model.suggestions[0])
        #expect(outcome == .unresolved("Café Slavia"))
        #expect(model.phase == .unresolved)
        await type("Café Slavia", into: model)
        #expect(model.phase == .unresolved, "the kept title is not a new query")
        #expect(fake.searched == ["slav"])
        #expect(PlaceSearchModel.statusText(phase: .unresolved, query: "", hasRows: false) != nil)
    }

    /// The user typed while the pick was resolving: the answer is dropped.
    @Test func aStalePickWritesNothing() async {
        fake.holdResolve = true
        let model = makeModel()
        await type("slav", into: model)
        fake.send("slav", ["Café Slavia"])
        let suggestion = model.suggestions[0]
        let pick = Task { await model.pick(suggestion) }
        while fake.pendingResolve == nil { await Task.yield() }
        #expect(model.phase == .resolving)
        #expect(model.resolvingID == suggestion.id)
        await type("Louvre", into: model)
        fake.pendingResolve?.resume(returning: slavia)
        #expect(await pick.value == nil)
        #expect(model.phase == .searching)
    }

    @Test func onlyCurrentRowsCanBePicked() async {
        let model = makeModel()
        let stranger = PlaceSuggestion(id: 99, title: "X", subtitle: "")
        #expect(await model.pick(stranger) == nil)
    }

    @Test func rowLabels() {
        #expect(PlaceSearchModel.rowLabel(PlaceSuggestion(id: 1, title: "Letná", subtitle: "")) == "Letná")
        #expect(PlaceSearchModel.rowLabel(PlaceSuggestion(id: 1, title: "Letná", subtitle: "Praha 7")) == "Letná, Praha 7")
        #expect(PlaceSearchModel.resultsAnnouncement(count: 1) == "1 place found. Down arrow to choose.")
    }
}
