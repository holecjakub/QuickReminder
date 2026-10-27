import Foundation

/// Lets the open in-notch section keep its edit when the panel switches to the other section
/// (Location ↔ Set Date): the section registers `commitBeforeSwitch` while shown; the root view
/// calls it before switching and switches only when it returns true (Set Date returns false for
/// a typed text that is not a date, after a beep). A plain reference box, not observed: nothing
/// renders from it.
@MainActor
final class SectionHandoff {
    private(set) var commitBeforeSwitch: (() -> Bool)?
    private var owner: UUID?

    /// The shown section registers on appear. During a switch the new section may appear before
    /// the old one disappears, so only the current owner can unregister.
    func register(_ owner: UUID, _ commit: @escaping () -> Bool) {
        self.owner = owner
        commitBeforeSwitch = commit
    }

    func unregister(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        commitBeforeSwitch = nil
    }

    /// Keep the open section's edit; true = go ahead and switch.
    func commitForSwitch() -> Bool { commitBeforeSwitch?() ?? true }
}
