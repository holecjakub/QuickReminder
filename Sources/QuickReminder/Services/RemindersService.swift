import EventKit
import Foundation

@MainActor
final class RemindersService: ObservableObject {
    static let shared = RemindersService()

    private let store = EKEventStore()

    @Published var calendars: [EKCalendar] = []
    @Published var accessGranted = false
    @Published var accessDenied = false

    private init() {}

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            accessGranted = granted
            accessDenied = !granted
            if granted {
                loadCalendars()
            }
        } catch {
            accessDenied = true
        }
    }

    func loadCalendars() {
        calendars = store.calendars(for: .reminder)
    }

    func calendar(for id: String?) -> EKCalendar? {
        guard let id else { return store.defaultCalendarForNewReminders() }
        return calendars.first { $0.calendarIdentifier == id } ?? store.defaultCalendarForNewReminders()
    }

    func save(
        title: String,
        notes: String,
        calendarID: String?,
        dueDate: Date?,
        flagged: Bool,
        location: String?
    ) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = buildNotes(notes: notes, location: location)
        reminder.calendar = calendar(for: calendarID)

        if let date = dueDate {
            var comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            comps.timeZone = TimeZone.current
            reminder.dueDateComponents = comps
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }

        if flagged {
            reminder.priority = Int(EKReminderPriority.high.rawValue)
        }

        try store.save(reminder, commit: true)
    }

    private func buildNotes(notes: String, location: String?) -> String? {
        var parts: [String] = []
        if !notes.isEmpty { parts.append(notes) }
        if let loc = location, !loc.isEmpty { parts.append("📍 \(loc)") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
