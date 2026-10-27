import SwiftUI

/// Location in the Popover style: the field edits the reminder's location live (as before), with
/// Apple Maps suggestions below it (↑ / ↓, ↩ or a click picks; ↩ with no row highlighted closes),
/// Arriving / Leaving, and Done. The list's room is reserved, so the popover never resizes while
/// typing.
struct LocationPopover: View {
    @Binding var location: ReminderLocation
    @Binding var isPresented: Bool
    let accent: Color

    @State private var search = PlaceSearchModel()
    @FocusState private var fieldFocused: Bool

    private typealias M = NotchLayout.LocationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location").font(.headline)
            TextField("Search Apple Maps or enter location", text: $location.text)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { search.moveHighlight(by: 1) ? .handled : .ignored }
                .onKeyPress(.upArrow) { search.moveHighlight(by: -1) ? .handled : .ignored }
                .accessibilityValue(location.place.map { "\($0.name), picked from Apple Maps" } ?? location.text)
                .accessibilityHint("Type to search Apple Maps; down arrow moves to the suggestions. Return picks the highlighted place.")
            PlaceSuggestionList(search: search, location: location, accent: accent, style: .popover, onPick: pick)
                .frame(height: M.listHeight(textScale: NotchLayout.cachedTextScale))
            HStack {
                Picker("Remind me", selection: $location.proximity) {
                    ForEach(LocationProximity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .opacity(location.place == nil ? 0.6 : 1)
                .accessibilityLabel("Remind me")
                .accessibilityHint(location.place == nil ? "Applies once a place from Apple Maps is picked" : "")
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 300)
        .padding(14)
        .onChange(of: location.text) { _, text in search.textChanged(text, pickedName: location.place?.name) }
        .onAppear {
            search.textChanged(location.text, pickedName: location.place?.name)
            // One runloop later: the popover window is not key yet.
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onDisappear { search.cancel() }
    }

    private func submit() {
        if let suggestion = search.highlightedSuggestion { pick(suggestion) } else { isPresented = false }
    }

    private func pick(_ suggestion: PlaceSuggestion) {
        Task { @MainActor in
            switch await search.pick(suggestion) {
            case .place(let place)?: location.pick(place)
            case .unresolved(let title)?: location.text = title
            case nil: break
            }
        }
    }
}
