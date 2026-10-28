import Foundation
import Observation
import SwiftUI

/// One Apple Maps completion row: "Café Slavia" / "Smetanovo nábřeží 2, Praha".
struct PlaceSuggestion: Identifiable, Equatable, Sendable {
    /// Assigned by the service; resolves back to its completion.
    let id: Int
    let title: String
    let subtitle: String
}

/// The service's id → completion table. A new query does not empty it: the previous rows stay on
/// screen (dimmed) and pickable until the new results arrive, which then replace the table.
struct SuggestionTable<Handle> {
    private var handles: [Int: Handle] = [:]
    private var nextID = 0

    /// New rows for the current results; rows of earlier results can no longer be resolved.
    mutating func publish(_ entries: [(title: String, subtitle: String, handle: Handle)]) -> [PlaceSuggestion] {
        handles.removeAll(keepingCapacity: true)
        return entries.map { entry in
            nextID += 1
            handles[nextID] = entry.handle
            return PlaceSuggestion(id: nextID, title: entry.title, subtitle: entry.subtitle)
        }
    }

    func handle(for suggestion: PlaceSuggestion) -> Handle? { handles[suggestion.id] }
}

/// What the search service reports for a query.
enum PlaceSearchUpdate: Equatable, Sendable {
    case results(query: String, [PlaceSuggestion])
    case failed(query: String)
}

/// The Apple Maps calls behind the Location field (`MapsPlaceSearch`; fakes in the tests).
/// Completions arrive through `onUpdate`, tagged with the query they belong to.
@MainActor
protocol PlaceSearchService: AnyObject {
    var onUpdate: ((PlaceSearchUpdate) -> Void)? { get set }
    /// Starts (or replaces) the completion search for `query`.
    func search(_ query: String)
    /// Stops the completion search; nothing more is reported for the old query.
    func cancel()
    /// Turns a completion into a place with coordinates (`MKLocalSearch`).
    func resolve(_ suggestion: PlaceSuggestion) async throws -> PickedPlace
}

/// The Location field's place search, shared by both styles: debounced Apple Maps completions,
/// stale results dropped, a highlighted row for ↑ / ↓ / ↩, and picking (resolving a completion).
///
/// Typing without picking stays free text: ↩ with no row highlighted is Done.
@MainActor
@Observable
final class PlaceSearchModel {
    enum Phase: Equatable {
        /// Fewer than `minQueryLength` characters: the hint shows.
        case idle
        /// A query is pending or running; the previous rows stay (dimmed) so nothing jumps.
        case searching
        case results
        /// Apple Maps found nothing for the query.
        case empty
        /// Apple Maps could not be reached / answered with an error.
        case failed
        /// A row was picked and its coordinates are loading.
        case resolving
        /// The field holds a picked place.
        case picked
        /// The picked row could not be resolved; its title stays as free text.
        case unresolved
    }

    /// Rows shown at most; the in-notch list reserves room for exactly this many.
    nonisolated static let maxRows = 5
    /// Shorter queries are not sent (single letters return noise).
    nonisolated static let minQueryLength = 2
    /// Pause after the last keystroke before Apple Maps is asked.
    nonisolated static let debounce: Duration = .milliseconds(250)

    private(set) var phase: Phase = .idle
    private(set) var suggestions: [PlaceSuggestion] = []
    /// The row ↩ picks; nil = ↩ is Done with the typed text.
    private(set) var highlighted: Int?
    /// The row being resolved after a pick.
    private(set) var resolvingID: Int?
    /// The trimmed query the shown / pending results belong to.
    private(set) var query: String = ""

    @ObservationIgnored private let makeService: @MainActor () -> PlaceSearchService
    @ObservationIgnored private var service: PlaceSearchService?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    /// Bumped by every text change, pick and cancel: anything started before is stale.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private(set) var debounceTask: Task<Void, Never>?
    /// The title a failed pick left in the field: it is free text now, not a new query.
    @ObservationIgnored private var unresolvedText: String?
    /// What was last announced for results (query, row count): refinements of the same query with
    /// the same count stay quiet.
    @ObservationIgnored private var lastResultsAnnouncement: (query: String, count: Int)?
    /// The query whose failure was announced (once per query).
    @ObservationIgnored private var failureAnnouncedFor: String?
    /// "Down arrow to choose" is said once per field session, then only the count.
    @ObservationIgnored private var toldHowToChoose = false

    /// The service is created on the first query, so building the model (a view's `@State`) costs
    /// nothing until someone types.
    init(makeService: @escaping @MainActor () -> PlaceSearchService = { MapsPlaceSearch() },
         debounce: Duration = PlaceSearchModel.debounce,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }) {
        self.makeService = makeService
        self.debounce = debounce
        self.sleep = sleep
        self.announce = announce
    }

    private func ensureService() -> PlaceSearchService {
        if let service { return service }
        let made = makeService()
        made.onUpdate = { [weak self] update in self?.receive(update) }
        service = made
        return made
    }

    // MARK: Typing

    /// The field as it is when the section / popover opens: a picked place shows as picked, any
    /// other text waits for an edit (reopening never re-sends text to Apple Maps by itself).
    func show(_ text: String, pickedName: String?) {
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        resolvingID = nil
        setHighlight(nil, announce: false)
        stopSearching(phase: pickedName != nil && pickedName == text ? .picked : .idle)
    }

    /// The field changed (also when a pick wrote the place's name: `pickedName` is the location's
    /// picked place, if any).
    func textChanged(_ text: String, pickedName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A trailing space does not ask again (and keeps a pending query and the highlight).
        if pickedName != text, unresolvedText != text, trimmed.count >= Self.minQueryLength, trimmed == query,
           phase == .results || phase == .empty || phase == .searching {
            return
        }
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        resolvingID = nil
        setHighlight(nil, announce: false)
        if let pickedName, pickedName == text {
            stopSearching(phase: .picked)
            return
        }
        if let unresolvedText, unresolvedText == text {
            stopSearching(phase: .unresolved)
            return
        }
        unresolvedText = nil
        guard trimmed.count >= Self.minQueryLength else {
            stopSearching(phase: .idle)
            return
        }
        query = trimmed
        phase = .searching
        let delay = debounce
        let sleep = sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self, self.query == trimmed, self.phase == .searching else { return }
            self.ensureService().search(trimmed)
        }
    }

    private func stopSearching(phase newPhase: Phase) {
        service?.cancel()
        query = ""
        suggestions = []
        phase = newPhase
    }

    /// The section / popover went away: nothing pending survives it.
    func cancel() {
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        service?.cancel()
        resolvingID = nil
        if phase == .searching || phase == .resolving { phase = suggestions.isEmpty ? .idle : .results }
    }

    private func receive(_ update: PlaceSearchUpdate) {
        // Only the query on screen counts, and not once a pick or a newer query took over.
        guard phase == .searching || phase == .results || phase == .empty || phase == .failed else { return }
        switch update {
        case .results(let q, let items):
            guard q == query else { return }
            let rows = Array(items.prefix(Self.maxRows))
            // Refinements of the same query come with fresh ids: the highlight follows the row the
            // user saw (same label), so ↩ still picks it; it is dropped only when that row is gone.
            let highlightedLabel = highlightedSuggestion.map(Self.rowLabel)
            suggestions = rows
            phase = rows.isEmpty ? .empty : .results
            setHighlight(highlightedLabel.flatMap { label in rows.firstIndex { Self.rowLabel($0) == label } },
                         announce: false)
            // Spoken only when the query or the count changed, not for every refinement.
            if lastResultsAnnouncement?.query != q || lastResultsAnnouncement?.count != rows.count {
                lastResultsAnnouncement = (q, rows.count)
                announce(Self.resultsAnnouncement(count: rows.count, withHint: !toldHowToChoose))
                if !rows.isEmpty { toldHowToChoose = true }
            }
        case .failed(let q):
            guard q == query else { return }
            suggestions = []
            phase = .failed
            setHighlight(nil, announce: false)
            if failureAnnouncedFor != q {
                failureAnnouncedFor = q
                announce(Self.failedAnnouncement)
            }
        }
    }

    // MARK: Keyboard

    /// ↓ / ↑ in the field: ↓ from the field enters the list, ↑ from the first row returns to the
    /// field; the ends do not wrap. false = not handled (no rows: the field keeps the key).
    @discardableResult
    func moveHighlight(by delta: Int) -> Bool {
        guard phase == .results, !suggestions.isEmpty else { return false }
        let next: Int?
        switch highlighted {
        case nil: next = delta > 0 ? 0 : nil
        case let i?:
            let moved = i + delta
            next = moved < 0 ? nil : min(moved, suggestions.count - 1)
        }
        if next == nil && highlighted == nil { return false }
        setHighlight(next, announce: true)
        return true
    }

    /// Esc with a row highlighted (combobox style): back to the field, the section stays open.
    /// false = nothing was highlighted; the Esc closes the section / popover as usual.
    @discardableResult
    func clearHighlight() -> Bool {
        guard highlighted != nil else { return false }
        setHighlight(nil, announce: true)
        return true
    }

    private func setHighlight(_ index: Int?, announce shouldAnnounce: Bool) {
        guard highlighted != index else { return }
        highlighted = index
        guard shouldAnnounce else { return }
        if let index, suggestions.indices.contains(index) {
            announce(Self.highlightAnnouncement(suggestions[index], position: index + 1, of: suggestions.count))
        } else {
            announce("Location field")
        }
    }

    // MARK: Picking

    enum PickOutcome: Equatable {
        case place(PickedPlace)
        /// Apple Maps could not resolve it: the title is kept as free text.
        case unresolved(String)
    }

    /// The highlighted row (↩), if any.
    var highlightedSuggestion: PlaceSuggestion? {
        highlighted.flatMap { suggestions.indices.contains($0) ? suggestions[$0] : nil }
    }

    /// Resolves a row to a place. nil = stale (the user typed, picked again or closed meanwhile) or
    /// not a current row; the caller writes nothing then.
    func pick(_ suggestion: PlaceSuggestion) async -> PickOutcome? {
        guard suggestions.contains(suggestion), phase != .resolving else { return nil }
        generation += 1
        let token = generation
        debounceTask?.cancel()
        phase = .resolving
        resolvingID = suggestion.id
        let outcome: PickOutcome
        do {
            outcome = .place(try await ensureService().resolve(suggestion))
        } catch {
            outcome = .unresolved(suggestion.title)
        }
        guard token == generation else { return nil }
        resolvingID = nil
        switch outcome {
        case .place(let place):
            stopSearching(phase: .picked)
            announce(Self.pickAnnouncement(place))
        case .unresolved(let title):
            unresolvedText = title
            stopSearching(phase: .unresolved)
            announce("Could not load \(title) from Apple Maps. Kept as text.")
        }
        return outcome
    }

    // MARK: VoiceOver

    static func resultsAnnouncement(count: Int, withHint: Bool = true) -> String {
        let hint = withHint ? " Down arrow to choose." : ""
        switch count {
        case 0: return "No places found"
        case 1: return "1 place found.\(hint)"
        default: return "\(count) places found.\(hint)"
        }
    }

    static let failedAnnouncement = "Apple Maps is unavailable. Done keeps the text as a note."

    static func highlightAnnouncement(_ s: PlaceSuggestion, position: Int, of count: Int) -> String {
        let name = s.subtitle.isEmpty ? s.title : "\(s.title), \(s.subtitle)"
        return "\(name), \(position) of \(count)"
    }

    static func pickAnnouncement(_ place: PickedPlace) -> String {
        "Picked \(place.name)"
    }

    /// The row's spoken label (also the list's rows in the accessibility tree).
    static func rowLabel(_ s: PlaceSuggestion) -> String {
        s.subtitle.isEmpty ? s.title : "\(s.title), \(s.subtitle)"
    }

    // MARK: Status line

    /// The line shown in the list area when there are no rows to show (nil = rows are shown), so
    /// the empty, error and hint states take the same reserved space.
    static func statusText(phase: Phase, query: String, hasRows: Bool) -> String? {
        switch phase {
        case .idle: return "Search Apple Maps, or type any place."
        case .searching: return hasRows ? nil : "Searching Apple Maps…"
        case .results, .resolving, .picked: return nil
        case .empty: return "No places found. Done keeps “\(query)” as a note."
        case .failed: return "Apple Maps is unavailable. Done keeps the text as a note."
        case .unresolved: return "Couldn’t load that place. Done keeps the text as a note."
        }
    }
}
