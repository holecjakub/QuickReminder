import SwiftUI

/// The Apple Maps suggestions under the Location field, in both styles: up to five rows (title +
/// subtitle), the highlighted one (↑ / ↓) filled with the accent, a click or ↩ picks. When there is
/// nothing to list it shows the picked place, or one status line (hint, searching, no places,
/// error) in the same reserved space, so the layout never jumps. VoiceOver reads the rows as a
/// list; the model announces results, the highlighted row and the pick.
struct PlaceSuggestionList: View {
    enum Style { case notch, popover }

    let search: PlaceSearchModel
    let location: ReminderLocation
    let accent: Color
    let style: Style
    let onPick: (PlaceSuggestion) -> Void

    @State private var hoveredID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias M = NotchLayout.LocationMetrics

    var body: some View {
        Group {
            if let place = location.place {
                pickedCard(place)
            } else if let status = PlaceSearchModel.statusText(phase: search.phase, query: search.query,
                                                               hasRows: !search.suggestions.isEmpty) {
                statusLine(status)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: search.suggestions)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: search.phase)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(search.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                row(suggestion, highlighted: search.highlighted == index)
            }
        }
        .accessibilityRepresentation {
            List(search.suggestions) { suggestion in
                Button(PlaceSearchModel.rowLabel(suggestion)) { onPick(suggestion) }
                    .accessibilityAddTraits(search.highlightedSuggestion == suggestion ? .isSelected : [])
            }
            .accessibilityLabel("Places from Apple Maps")
        }
    }

    private func row(_ s: PlaceSuggestion, highlighted: Bool) -> some View {
        let hovered = hoveredID == s.id
        return Button { onPick(s) } label: {
            HStack(spacing: 8) {
                ZStack {
                    if search.resolvingID == s.id {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: Theme.s(14)))
                            .foregroundStyle(highlighted ? accent : secondary)
                            .opacity(dimmed ? 0.75 : 1)
                    }
                }
                .frame(width: Theme.s(18))
                VStack(alignment: .leading, spacing: 1) {
                    // Rows still on screen while a newer query runs are dimmed, not removed (no
                    // jump), and stay pickable: only the title softens, so both lines keep 4.5:1.
                    Text(s.title)
                        .font(.system(size: Theme.s(13), weight: .medium))
                        .foregroundStyle(primary.opacity(dimmed ? 0.75 : 1))
                    if !s.subtitle.isEmpty {
                        Text(s.subtitle)
                            .font(.system(size: Theme.s(11)))
                            .foregroundStyle(secondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                if highlighted {
                    Text("↩")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.s(M.row))
            .background(
                RoundedRectangle(cornerRadius: M.rowRadius, style: .continuous)
                    .fill(highlighted ? accent.opacity(0.22) : (hovered ? hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Arrows in the field move through the rows; with Full Keyboard Access they stay out of
        // the Tab loop (like the month grid's days).
        .focusable(false)
        .help(PlaceSearchModel.rowLabel(s))
        .onHover { inside in
            if inside { hoveredID = s.id } else if hoveredID == s.id { hoveredID = nil }
            HoverMotion.updateCursor(hovering: inside)
        }
    }

    // MARK: Picked place / status

    private func pickedCard(_ place: PickedPlace) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: Theme.s(14)))
                .foregroundStyle(accent)
                .frame(width: Theme.s(18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(primary)
                if let address = Self.shownAddress(place) {
                    Text(address)
                        .font(.system(size: Theme.s(11)))
                        .foregroundStyle(secondary)
                }
                Text("Reminds you \(location.proximity.phrase) · Apple Maps place")
                    .font(.system(size: Theme.s(11)))
                    .foregroundStyle(secondary)
                    .padding(.top, 2)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Picked place: \(place.name)\(Self.shownAddress(place).map { ", \($0)" } ?? "")")
        .accessibilityValue("Reminds you \(location.proximity.phrase)")
        .help(Self.shownAddress(place).map { "\(place.name), \($0)" } ?? place.name)
    }

    /// The address line under a picked name: none when it is empty or just repeats the name.
    static func shownAddress(_ place: PickedPlace) -> String? {
        guard let address = place.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty, address != place.name else { return nil }
        return address
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.s(12)))
            .foregroundStyle(secondary)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            // Read when it changes, but not on every keystroke: the model announces results.
            .accessibilityLabel(text)
    }

    // MARK: Colours

    private var dimmed: Bool { search.phase == .searching }
    private var primary: Color { style == .notch ? .white : .primary }
    /// At least 50 % white on black (secondary text that carries information, SPEC §1).
    private var secondary: Color { style == .notch ? .white.opacity(0.55) : .secondary }
    private var hoverFill: Color { style == .notch ? .white.opacity(0.06) : .primary.opacity(0.06) }
}

/// Arriving / Leaving on black: two capsule segments in a capsule track, the chosen one in the
/// accent (`NotchFillButtonStyle` language). Dimmed while no place is picked (it applies only to a
/// picked place), but still settable.
struct ProximityPicker: View {
    @Binding var proximity: LocationProximity
    let accent: Color
    let enabledLook: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LocationProximity.allCases, id: \.self) { option in
                let selected = option == proximity
                Button { proximity = option } label: {
                    Text(option.title)
                        .font(.system(size: Theme.s(12), weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .frame(height: height - 4)
                }
                .buttonStyle(NotchFillButtonStyle(kind: selected ? .selected : .neutral, accent: accent, radius: nil))
                .accessibilityLabel("When \(option.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(enabledLook ? "" : Self.notApplicableHint)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        // Dimmed, not disabled: unselected labels stay above 4.5:1 (70 % × 80 % white).
        .opacity(enabledLook ? 1 : 0.8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remind me")
    }

    static let notApplicableHint = "Applies once a place from Apple Maps is picked"
}
