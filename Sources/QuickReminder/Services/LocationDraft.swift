import Foundation

/// The in-notch Location section's working state: the field, and what Done / ✓ write. Nothing
/// reaches the reminder until Done (↩, ⌘↩), Clear or ✓; Cancel, Esc and a click above leave it as
/// it was. Stored in Notes as `📍 …` by the save path, exactly like the popover's text.
struct LocationDraft: Equatable {
    /// The reminder's location when the section opened.
    let original: String
    /// The field.
    var text: String

    init(original: String) {
        self.original = original
        self.text = original
    }

    /// The user changed the text since the section opened.
    var isDirty: Bool { text != original }

    /// What Done writes: the trimmed text ("" removes the location).
    var committed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What ✓ (save the reminder) does while the section is open: an edit is applied first, an
    /// untouched field leaves the location as it was.
    enum SaveDecision: Equatable {
        case saveAsIs
        case applyThenSave(String)
    }

    var saveDecision: SaveDecision { isDirty ? .applyThenSave(committed) : .saveAsIs }
}
