import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("selectedListId") var selectedListId: String = ""

    private init() {}
}

/// A/B switch for Set Date (Settings → Date picker style). Named `SetDateStyle` so it does not
/// shadow SwiftUI's `DatePickerStyle`; stored in UserDefaults under `datePickerStyle` (the raw
/// values are the stored values); `-datePickerStyle popover` on the command line overrides it for a run
/// (argument domain, nothing persisted), which is how the E2E suite exercises both paths.
enum SetDateStyle: String, CaseIterable, Identifiable, Sendable {
    /// The Set Date popover anchored to the calendar icon.
    case popover
    /// The black panel itself grows and shows the scheduling controls (no glass, no popover).
    case notch

    static let defaultsKey = "datePickerStyle"
    static let defaultStyle: SetDateStyle = .notch

    var id: String { rawValue }

    /// The stored style (`-datePickerStyle` in the argument domain overrides it for a run).
    static var current: SetDateStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SetDateStyle.init(rawValue:)) ?? defaultStyle
    }

    var title: String {
        switch self {
        case .popover: return "Popover"
        case .notch: return "In notch"
        }
    }
}
