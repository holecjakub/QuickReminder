import AppKit
import SwiftUI

/// Location inside the black notch panel (notch style): the location button grows the panel
/// downward and this short section is appended below the bottom bar, like Set Date. Same function
/// as the popover (the text ends up in Notes as `📍 …`), styled like Set Date: a field and a
/// Clear · Cancel · Done footer. Heights come from `NotchLayout.LocationMetrics`.
///
/// Nothing reaches `locationText` until Done (↩ in the field, ↩ / ⌘↩ in the title, ⌘↩), Clear or
/// ✓ (`LocationDraft.saveDecision`); Cancel, Esc, the location button and a click above close it
/// without writing.
struct LocationNotchSection: View {
    @Binding var locationText: String
    let accent: Color
    /// Cancel or any commit: the panel settles back to its plain height.
    let onClose: () -> Void
    /// ✓ in the bottom bar while the section is open, once the section has applied an edit.
    let onSaveReminder: () -> Void

    private typealias M = NotchLayout.LocationMetrics

    @State private var draft: LocationDraft
    @State private var appeared = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(locationText: Binding<String>, accent: Color, onClose: @escaping () -> Void,
         onSaveReminder: @escaping () -> Void) {
        _locationText = locationText
        self.accent = accent
        self.onClose = onClose
        self.onSaveReminder = onSaveReminder
        _draft = State(initialValue: LocationDraft(original: locationText.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            footer
                .padding(.top, M.footerGap)
                .staggered(1, appeared: appeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(accent)
        .background(commandReturnTwin)
        .onReceive(NotificationCenter.default.publisher(for: .sectionCommitRequested)) { _ in done() }
        .onReceive(NotificationCenter.default.publisher(for: .sectionSaveRequested)) { _ in saveFromBar() }
        .onAppear {
            appeared = true
            DispatchQueue.main.async { fieldFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location")
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "location")
                .font(.system(size: Theme.s(12), weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            TextField("", text: $draft.text, prompt: Text("Enter location").foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(14)))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit(done)
                .accessibilityLabel("Location")
                .accessibilityHint("Added to the notes with a pin. Return applies it.")
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
            if !locationText.isEmpty {
                Button("Clear") {
                    locationText = ""
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
            .accessibilityLabel(draft.committed.isEmpty ? "Done, no location" : "Done, \(draft.committed)")
        }
        .frame(height: Theme.s(M.footer))
    }

    /// ⌘↩ is Done too (the bottom bar's ✓ gives up its ⌘↩ while a section is open).
    private var commandReturnTwin: some View {
        Button("", action: done)
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func done() {
        locationText = draft.committed
        onClose()
    }

    /// ✓ while the section is open: an edit is applied, then the reminder saves.
    private func saveFromBar() {
        switch draft.saveDecision {
        case .saveAsIs:
            onClose()
        case .applyThenSave(let text):
            locationText = text
            onClose()
        }
        onSaveReminder()
    }
}
