import AppKit
import SwiftUI

/// Bottom row: outlined pill with date / location / flag on the left, round ✓ save button on the right.
struct BottomBar: View {
    @Binding var dueDate: Date?
    @Binding var flagged: Bool
    @Binding var locationText: String
    let canSave: Bool
    let onSave: () -> Void

    @Binding var showLocationField: Bool
    @Binding var showCustomDatePicker: Bool
    /// The title's live, undismissed date phrase: prefilled into the Set Date popover.
    let suggestionText: String?
    /// Strips that phrase from the title once the popover commits it.
    let onConsumeSuggestion: () -> Void
    let saveNamespace: Namespace.ID
    let saveButtonYielded: Bool
    @Environment(\.listAccent) private var accent

    private let iconSize: CGFloat = 22
    private let hitSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            pillView
            Spacer(minLength: 16)
            saveButton
        }
    }

    // MARK: Pill

    private var pillView: some View {
        HStack(spacing: 17) {
            dateMenu
            locationButton
            flagButton
        }
        .padding(.horizontal, Theme.s(11))
        .frame(height: Theme.s(44))
        .background(
            Capsule()
                .fill(Theme.pillFill)
                .overlay(Capsule().strokeBorder(Theme.pillStroke, lineWidth: 1))
        )
    }

    /// Pill glyphs are rendered through AppKit's symbol configuration rather than SwiftUI's
    /// `Image(systemName:)`: at one point size AppKit draws the three symbols optically balanced
    /// (measured at 22 pt: calendar.badge.clock 25.5 × 21.5, location 21 × 20, flag 20.5 × 20.5),
    /// whereas the SwiftUI symbol image draws the badge symbol markedly smaller. Template images
    /// take the foreground style, so active colours keep working.
    /// Only the badge symbol needs the AppKit path; `flag` / `location` stay SwiftUI symbols so
    /// `.contentTransition(.symbolEffect(.replace))` keeps animating their fill toggle.
    @ViewBuilder
    private func icon(_ name: String, active: Bool, activeColor: Color? = nil) -> some View {
        Group {
            if name.contains(".badge.") {
                Image(nsImage: Self.symbolImage(name, pointSize: Theme.s(iconSize)))
                    .renderingMode(.template)
            } else {
                Image(systemName: name)
                    .font(.system(size: Theme.s(iconSize), weight: .regular))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .foregroundStyle(active ? (activeColor ?? accent) : .white)
        .frame(width: Theme.s(hitSize), height: Theme.s(hitSize))
        .contentShape(Rectangle())
    }

    /// Cached per name + size: a fresh NSImage per body would re-rasterise on every render
    /// (~160 µs each), and a stable object lets `Image(nsImage:)` skip the redraw entirely.
    @MainActor private static var symbolCache: [String: NSImage] = [:]

    @MainActor private static func symbolImage(_ name: String, pointSize: CGFloat) -> NSImage {
        let key = "\(name)@\(pointSize)"
        if let cached = symbolCache[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        symbolCache[key] = image
        return image
    }

    @State private var dateMenuPresenter = PopUpMenu()

    /// Rows keep fixed positions (labels adapt, nothing hides), each showing the time it resolves
    /// to, computed when the menu opens.
    private var dateMenu: some View {
        Button {
            let now = AppClock.now
            let presets: [PopUpMenu.Item] = [DatePreset.inOneHour, .evening, .tomorrow, .weekend, .nextWeek].map { preset in
                let date = DatePreset.date(for: preset, now: now)
                return .action(DatePreset.menuTitle(for: preset, now: now),
                               systemImage: DatePreset.systemImage(for: preset),
                               detail: Self.dateFormatter.presetDetail(date, now: now)) {
                    dueDate = DatePreset.date(for: preset, now: AppClock.now)
                    consumeLiveSuggestion()
                }
            }
            dateMenuPresenter.show([
                .action("None", systemImage: "calendar.badge.minus") { dueDate = nil },
                .separator,
                .action("Mark as Urgent", systemImage: "alarm") {
                    flagged = true
                    dueDate = AppClock.now.addingTimeInterval(60 * 60)
                    consumeLiveSuggestion()
                },
            ] + presets + [
                .separator,
                .action("Custom…", systemImage: "calendar.badge.clock", keyEquivalentHint: "d") { showCustomDatePicker = true },
            ], belowPanelAt: NSEvent.mouseLocation.x - 12)
        } label: {
            icon("calendar.badge.clock", active: dueDate != nil)
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .accessibilityLabel("Set date and time")
        .popover(isPresented: $showCustomDatePicker, arrowEdge: .bottom) {
            SchedulePopover(
                selectedDate: $dueDate,
                isPresented: $showCustomDatePicker,
                accent: accent,
                initialText: dueDate == nil ? suggestionText : nil,
                onConsumeSuggestion: onConsumeSuggestion
            )
        }
    }

    private static let dateFormatter = SuggestionDateFormatter()

    /// A menu date replaces whatever the title's live phrase said, so the phrase goes (same rule
    /// as the Set Date popover, `ScheduleCommit.consumesSuggestion`).
    private func consumeLiveSuggestion() {
        if ScheduleCommit.consumesSuggestion(initialText: suggestionText, action: .preset) { onConsumeSuggestion() }
    }

    private var locationButton: some View {
        Button { showLocationField = true } label: {
            icon(locationText.isEmpty ? "location" : "location.fill", active: !locationText.isEmpty)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .accessibilityLabel("Add location")
        .popover(isPresented: $showLocationField, arrowEdge: .bottom) {
            locationPopover
        }
    }

    private var flagButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { flagged.toggle() }
        } label: {
            icon(flagged ? "flag.fill" : "flag", active: flagged, activeColor: Theme.flagOrange)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .accessibilityLabel("Toggle flag")
    }

    // MARK: Save

    private var saveButton: some View {
        Group {
            if saveButtonYielded {
                // The badge in NotchContainerView owns the geometry now; keep the slot.
                Color.clear.frame(width: Theme.s(48), height: Theme.s(48))
            } else {
                Button(action: handleSave) {
                    ZStack {
                        Circle()
                            .fill(canSave ? accent : Theme.grayCircleDisabled)
                        Image(systemName: "checkmark")
                            .font(.system(size: Theme.s(22), weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: Theme.s(48), height: Theme.s(48))
                    .contentShape(Circle())
                }
                .buttonStyle(HoverButtonStyle())
                .matchedGeometryEffect(id: "save", in: saveNamespace)
                .disabled(!canSave)
                .animation(.easeInOut(duration: 0.18), value: canSave)
                .accessibilityLabel("Save reminder")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var locationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location").font(.headline)
            TextField("Enter location", text: $locationText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { showLocationField = false }
            HStack {
                Spacer()
                Button("Done") { showLocationField = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private func handleSave() {
        guard canSave else { return }
        onSave()
    }
}
