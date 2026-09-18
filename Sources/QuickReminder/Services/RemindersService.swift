import EventKit
import Foundation

@MainActor
final class RemindersService: ObservableObject {
    static let shared = RemindersService()

    private let store = EKEventStore()

    @Published var calendars: [EKCalendar] = []
    @Published var accessGranted = false
    @Published var accessDenied = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.accessGranted else { return }
                self.loadCalendars()
            }
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async {
        NSLog("QuickReminder: reminders authorization status before request = %d", EKEventStore.authorizationStatus(for: .reminder).rawValue)
        do {
            let granted = try await store.requestFullAccessToReminders()
            NSLog("QuickReminder: requestFullAccessToReminders granted=%d status=%d", granted ? 1 : 0, EKEventStore.authorizationStatus(for: .reminder).rawValue)
            accessGranted = granted
            accessDenied = !granted
            if granted {
                loadCalendars()
            }
        } catch {
            NSLog("QuickReminder: requestFullAccessToReminders failed: %@", String(describing: error))
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
        guard hasAccess else { throw SaveError.noAccess }
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

    enum SaveError: LocalizedError {
        case noAccess
        var errorDescription: String? {
            switch self {
            case .noAccess: "Allow Reminders access in System Settings → Privacy & Security."
            }
        }
    }

    private func buildNotes(notes: String, location: String?) -> String? {
        var parts: [String] = []
        if !notes.isEmpty { parts.append(notes) }
        if let loc = location, !loc.isEmpty { parts.append("📍 \(loc)") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
