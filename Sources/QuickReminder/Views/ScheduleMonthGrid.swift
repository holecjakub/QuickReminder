import SwiftUI

/// Compact month grid for black (in-notch Set Date): always six weeks (`MonthGrid`), today in the
/// accent, the picked day in an accent disc, the past dimmed and disabled.
///
/// Keyboard: the grid is a single focus stop (the section makes it focusable and handles the
/// arrows); the day buttons stay out of the Tab loop even with Full Keyboard Access. The ring is on
/// the picked day, or around the whole grid when ‹ › paged away from it (the next arrow lands in
/// the visible month). VoiceOver reads each day by its full name, "Today" as the value.
struct ScheduleMonthGrid: View {
    let draft: Date
    @Binding var month: Date
    let accent: Color
    /// The grid has the keyboard.
    let keyboardFocused: Bool
    let onPick: (Date) -> Void

    private typealias M = NotchLayout.ScheduleMetrics
    private static let formatter = SuggestionDateFormatter()

    private var draftOnPage: Bool { MonthGrid.startOfMonth(draft) == MonthGrid.startOfMonth(month) }

    var body: some View {
        let now = AppClock.now
        let calendar = Calendar.current
        let dayLabel = AccentContrast.label(on: accent)
        VStack(spacing: 0) {
            header(now: now)
                .frame(height: Theme.s(M.monthHeader))
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: Theme.s(10), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Theme.s(M.weekdayRow))
            .accessibilityHidden(true)   // each day's label carries its weekday
            let cells = MonthGrid.cells(for: month)
            VStack(spacing: M.dayRowSpacing) {
                ForEach(0..<MonthGrid.weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            dayCell(cells[week * 7 + column], now: now, calendar: calendar, selectedLabel: dayLabel)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: Theme.s(M.dayCell))
                }
            }
        }
        // Focus indicator while the picked day is on another page.
        .overlay(
            RoundedRectangle(cornerRadius: M.controlRadius, style: .continuous)
                .strokeBorder(.white.opacity(keyboardFocused && !draftOnPage ? 0.6 : 0), lineWidth: 1.5)
                .padding(-4)
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar, \(Self.formatter.string(from: month, template: "MMMM y"))")
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 2) {
            Text(Self.formatter.string(from: month, template: "LLLL y"))
                .font(.system(size: Theme.s(13), weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            pageButton("chevron.left", label: "Previous month", enabled: MonthGrid.canGoBack(from: month, now: now)) { page(-1) }
            pageButton("chevron.right", label: "Next month", enabled: true) { page(1) }
        }
    }

    private func pageButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Theme.s(11), weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.75 : 0.2))
                .frame(width: Theme.s(26), height: Theme.s(26))
                .contentShape(Circle())
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, now: Date, calendar: Calendar, selectedLabel: Color) -> some View {
        if let day {
            let selectable = MonthGrid.isSelectable(day, now: now, calendar: calendar)
            let selected = calendar.isDate(day, inSameDayAs: draft)
            let today = calendar.isDate(day, inSameDayAs: now)
            Button { onPick(day) } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: Theme.s(13), weight: selected || today ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(foreground(selected: selected, today: today, selectable: selectable, selectedLabel: selectedLabel))
                    .frame(width: Theme.s(M.dayCell), height: Theme.s(M.dayCell))
                    .background(Circle().fill(selected ? accent : .clear))
                    .overlay(Circle().strokeBorder(.white.opacity(selected && keyboardFocused ? 0.85 : 0), lineWidth: 1.5).padding(-3))
                    // The whole cell clicks (≈ 74 × 30 pt), not just the 28 pt disc.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DayCellStyle(selected: selected))
            .focusable(false)   // one Tab stop for the whole grid, arrows inside
            .disabled(!selectable)
            .accessibilityLabel(Self.formatter.string(from: day, template: "EEEE d MMMM"))
            .accessibilityValue(today ? "Today" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private func foreground(selected: Bool, today: Bool, selectable: Bool, selectedLabel: Color) -> Color {
        if selected { return selectedLabel }
        if !selectable { return .white.opacity(0.25) }   // disabled (exempt from text contrast)
        if today { return accent }
        return .white.opacity(0.85)
    }

    private func page(_ months: Int) {
        guard months > 0 || MonthGrid.canGoBack(from: month, now: AppClock.now) else { return }
        withAnimation(.easeOut(duration: 0.15)) { month = MonthGrid.shiftMonth(month, by: months) }
    }
}

/// Day cell: a soft white disc on hover, nothing else (the picked day carries the accent disc).
private struct DayCellStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(!selected && isEnabled && (hovering || configuration.isPressed)
                                              ? (configuration.isPressed ? 0.16 : 0.09) : 0))
            )
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isEnabled, isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }
}
