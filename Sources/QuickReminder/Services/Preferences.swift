import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("selectedListId") var selectedListId: String = ""

    private init() {}
}

/// A/B switch for Set Date (Settings → Date picker style). Stored in UserDefaults under
/// `datePickerStyle`; `-datePickerStyle popover` on the command line overrides it for a run
/// (argument domain, nothing persisted), which is how the E2E suite exercises both paths.
enum DatePickerStyle: String, CaseIterable, Identifiable, Sendable {
    /// The Set Date popover anchored to the calendar icon.
    case popover
    /// The black panel itself grows and shows the scheduling controls (no glass, no popover).
    case notch

    static let defaultsKey = "datePickerStyle"
    static let defaultStyle: DatePickerStyle = .notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popover: return "Popover"
        case .notch: return "In notch"
        }
    }

    /// Unknown or missing values fall back to the default.
    static func resolve(_ raw: String?) -> DatePickerStyle {
        raw.flatMap(DatePickerStyle.init(rawValue:)) ?? defaultStyle
    }
}
