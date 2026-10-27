import Foundation

/// The in-notch Location section's working state: the field, and what Done / ✓ / a switch to Set
/// Date write. Nothing reaches the reminder until one of those or Clear; Cancel, Esc and a click
/// above leave it as it was. The text is written as typed, like the popover's; the save path
/// (`RemindersService.buildNotes`) trims it and stores it in Notes as `📍 …`.
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

    /// What Done writes: the field as typed (the save path trims; blank removes the location).
    var committed: String { text }

    /// What ✓ (save the reminder) does while the section is open: an edit is applied first, an
    /// untouched field leaves the location as it was.
    enum SaveDecision: Equatable {
        case saveAsIs
        case applyThenSave(String)
    }

    var saveDecision: SaveDecision { isDirty ? .applyThenSave(committed) : .saveAsIs }

    /// Switching to Set Date while Location is open keeps what was typed: an edit is written (like
    /// Done), an untouched field writes nothing. nil = nothing to write.
    var textToKeepOnSwitch: String? { isDirty ? committed : nil }
}
