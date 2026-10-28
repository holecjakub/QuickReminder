import AppKit
import SwiftUI

/// Location inside the black notch panel (notch style): the location button grows the panel
/// downward and this section is appended below the bottom bar, like Set Date. Same function as the
/// popover, styled like Set Date: a field with Apple Maps suggestions below it (↑ / ↓, ↩ or a click
/// picks), then Arriving / Leaving · Clear · Cancel · Done. A picked place is saved as a real
/// Reminders location with a proximity alarm; free text as `📍 …` in Notes (`LocationSavePlan`).
/// Heights come from `NotchLayout.LocationMetrics` (the list's room is always reserved).
///
/// Nothing reaches `location` until Done (↩ in the field with no row highlighted, ↩ / ⌘↩ in the
/// title, ⌘↩), Clear or ✓ (`LocationDraft.saveDecision`); Cancel, Esc, the location button and a
/// click above close it without writing.
struct LocationNotchSection: View {
    @Binding var location: ReminderLocation
    let accent: Color
    /// Cancel or any commit: the panel settles back to its plain height.
    let onClose: () -> Void
    /// ✓ in the bottom bar while the section is open, once the section has applied an edit.
    let onSaveReminder: () -> Void
    /// Switching to Set Date keeps what was edited here (`LocationDraft.locationToKeepOnSwitch`).
    let handoff: SectionHandoff
    @State private var handoffToken = UUID()

    private typealias M = NotchLayout.LocationMetrics

    @State private var draft: LocationDraft
    @State private var search = PlaceSearchModel()
    @State private var appeared = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(location: Binding<ReminderLocation>, accent: Color, onClose: @escaping () -> Void,
         onSaveReminder: @escaping () -> Void, handoff: SectionHandoff) {
        _location = location
        self.accent = accent
        self.onClose = onClose
        self.onSaveReminder = onSaveReminder
        self.handoff = handoff
        _draft = State(initialValue: LocationDraft(original: location.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            PlaceSuggestionList(search: search, location: draft.location, accent: accent, style: .notch,
                                onPick: pick)
                // The reserved room (`LocationMetrics.listHeight`); it gives way only when the
                // screen clamps the panel.
                .frame(minHeight: 0, idealHeight: listHeight, maxHeight: listHeight, alignment: .top)
                .padding(.top, M.listGap)
                .staggered(1, appeared: appeared, reduceMotion: reduceMotion)
            footer
                .padding(.top, M.footerGap)
                .staggered(2, appeared: appeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(accent)
        .background(CommandReturnTwin(action: done))
        .onReceive(NotificationCenter.default.publisher(for: .sectionCommitRequested)) { _ in done() }
        .onReceive(NotificationCenter.default.publisher(for: .sectionSaveRequested)) { _ in saveFromBar() }
        .onChange(of: draft.location.text) { _, text in
            search.textChanged(text, pickedName: draft.location.place?.name)
        }
        .onAppear {
            appeared = true
            handoff.register(handoffToken) {
                if let kept = draft.locationToKeepOnSwitch { location = kept }
                return true
            }
            handoff.registerEscape(handoffToken) { search.clearHighlight() }
            // Nothing is sent to Apple Maps until the text is edited.
            search.show(draft.location.text, pickedName: draft.location.place?.name)
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onDisappear {
            search.cancel()
            handoff.unregister(handoffToken)
            handoff.unregisterEscape(handoffToken)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location")
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: draft.location.place == nil ? "location" : "location.fill")
                .font(.system(size: Theme.s(12), weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            TextField("", text: $draft.location.text,
                      prompt: Text("Search Apple Maps or enter location").foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(14)))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { search.moveHighlight(by: 1) ? .handled : .ignored }
                .onKeyPress(.upArrow) { search.moveHighlight(by: -1) ? .handled : .ignored }
                .accessibilityLabel("Location")
                .accessibilityValue(draft.location.place.map { "\($0.name), picked from Apple Maps" } ?? draft.location.text)
                .accessibilityHint("Type to search Apple Maps; down arrow moves to the suggestions. Return picks the highlighted place, otherwise applies the text.")
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.s(M.field))
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.ScheduleMetrics.controlRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchLayout.ScheduleMetrics.controlRadius, style: .continuous)
                .strokeBorder(fieldFocused ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: fieldFocused)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ProximityPicker(proximity: $draft.location.proximity, accent: accent,
                            enabledLook: draft.location.place != nil, height: Theme.s(M.footer))
            if !location.isEmpty {
                Button("Clear") {
                    location.clear()
                    onClose()
                }
                .buttonStyle(NotchTextButtonStyle())
                .accessibilityHint("Removes the location from the reminder")
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("Cancel")
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .frame(height: Theme.s(M.footer))
            }
            .buttonStyle(NotchFillButtonStyle(kind: .neutral, accent: accent, radius: NotchLayout.ScheduleMetrics.controlRadius))
            Button(action: done) {
                Text("Done")
                    .font(.system(size: Theme.s(13), weight: .semibold))
                    .foregroundStyle(AccentContrast.label(on: accent))
                    .padding(.horizontal, 18)
                    .frame(height: Theme.s(M.footer))
            }
            .buttonStyle(NotchFillButtonStyle(kind: .prominent, accent: accent, radius: NotchLayout.ScheduleMetrics.controlRadius))
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(doneLabel)
        }
        .frame(height: Theme.s(M.footer))
    }


    private var listHeight: CGFloat { M.listHeight(textScale: NotchLayout.cachedTextScale) }

    private var doneLabel: String {
        let committed = draft.committed
        if committed.isEmpty { return "Done, no location" }
        if let place = committed.place { return "Done, \(place.name), \(committed.proximity.phrase)" }
        return "Done, \(committed.text)"
    }

    /// ↩ in the field: picks the highlighted suggestion, otherwise Done with the text as typed.
    private func submit() {
        if let suggestion = search.highlightedSuggestion { pick(suggestion) } else { done() }
    }

    /// Resolves the row with Apple Maps, then writes the place (name in the field) into the draft;
    /// a failed resolve keeps the row's title as free text. Nothing reaches the reminder until Done.
    private func pick(_ suggestion: PlaceSuggestion) {
        Task { @MainActor in
            switch await search.pick(suggestion) {
            case .place(let place)?: draft.location.pick(place)
            case .unresolved(let title)?: draft.location.text = title
            case nil: break
            }
            fieldFocused = true
        }
    }

    private func done() {
        location = draft.committed
        onClose()
    }

    /// ✓ while the section is open: an edit is applied, then the reminder saves.
    private func saveFromBar() {
        switch draft.saveDecision {
        case .saveAsIs:
            onClose()
        case .applyThenSave(let edited):
            location = edited
            onClose()
        }
        onSaveReminder()
    }
}
