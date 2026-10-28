import Foundation

/// The in-notch Location section's working state: the field, a place picked from Apple Maps and
/// Arriving / Leaving, and what Done / ✓ / a switch to Set Date write. Nothing reaches the reminder
/// until one of those or Clear; Cancel, Esc and a click above leave it as it was. The text is
/// written as typed, like the popover's; the save path (`LocationSavePlan`) trims it.
struct LocationDraft: Equatable {
    /// The reminder's location when the section opened.
    let original: ReminderLocation
    /// The field, the pick and the proximity choice.
    var location: ReminderLocation

    init(original: ReminderLocation) {
        self.original = original
        self.location = original
    }

    /// The user changed something (text, pick or Arriving / Leaving) since the section opened.
    var isDirty: Bool { location != original }

    /// What Done writes: the location as edited (the save path trims; blank removes it).
    var committed: ReminderLocation { location }

    /// What ✓ (save the reminder) does while the section is open: an edit is applied first, an
    /// untouched section leaves the location as it was.
    enum SaveDecision: Equatable {
        case saveAsIs
        case applyThenSave(ReminderLocation)
    }

    var saveDecision: SaveDecision { isDirty ? .applyThenSave(committed) : .saveAsIs }

    /// Switching to Set Date while Location is open keeps what was edited (like Done); an untouched
    /// section writes nothing. nil = nothing to write.
    var locationToKeepOnSwitch: ReminderLocation? { isDirty ? committed : nil }
}
