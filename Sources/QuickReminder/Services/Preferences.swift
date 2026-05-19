import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("selectedListId") var selectedListId: String = ""

    private init() {}
}
