import CoreLocation
import EventKit
import Foundation
import SwiftUI

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
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    private var reloadTask: Task<Void, Never>?

    /// EKEventStoreChanged arrives in bursts (and after our own saves); coalesce into one reload.
    private func scheduleReload() {
        guard accessGranted else { return }
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.loadCalendars()
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
        let fresh = store.calendars(for: .reminder)
        // Avoid re-rendering the whole panel when nothing changed (ids, titles or colours).
        let signature = { (cals: [EKCalendar]) in cals.map { "\($0.calendarIdentifier)|\($0.title)|\($0.cgColor.map { "\($0.components ?? [])" } ?? "-")" } }
        if signature(fresh) != signature(calendars) {
            calendars = fresh
        }
        let defaultColor = store.defaultCalendarForNewReminders()?.cgColor.map { Color(cgColor: $0) }
        if defaultColor != defaultListColor { defaultListColor = defaultColor }
    }

    /// Colour of the default list, resolved in `loadCalendars()` so SwiftUI bodies never call
    /// `defaultCalendarForNewReminders()` (an XPC round trip) themselves.
    @Published private(set) var defaultListColor: Color?

    /// The list's colour as a SwiftUI colour: the stored id's list, or the default list when no
    /// id is stored; nil (→ the iOS blue) when the id is stale or EventKit provides no colour.
    func color(for id: String?) -> Color? {
        guard let id else { return defaultListColor }
        guard let cal = calendars.first(where: { $0.calendarIdentifier == id }), let cg = cal.cgColor else { return nil }
        return Color(cgColor: cg)
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
        location: ReminderLocation?
    ) throws {
        guard hasAccess else { throw SaveError.noAccess }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar(for: calendarID)
        Self.fill(reminder, notes: notes, dueDate: dueDate, location: location)

        if flagged {
            reminder.priority = Int(EKReminderPriority.high.rawValue)
        }

        try store.save(reminder, commit: true)
    }

    /// Notes, due date and alarms, the part of a save that needs no store (unit-tested with a fake
    /// target). The due date gets its time alarm; a picked place gets a location alarm next to it
    /// (`LocationSavePlan.structured`: an `EKStructuredLocation` with coordinates and a radius,
    /// `.enter` for Arriving, `.leave` for Leaving), the way Reminders' own "When arriving / When
    /// leaving" works, and no `📍` note line. Free text has no coordinates and stays a note line.
    nonisolated static func fill(_ target: some ReminderAlarmTarget, notes: String, dueDate: Date?,
                                 location: ReminderLocation?, timeZone: TimeZone = .current,
                                 calendar: Calendar = .current) {
        let plan = LocationSavePlan.plan(for: location)
        target.notes = buildNotes(notes: notes, location: plan.noteLineText)

        if let date = dueDate {
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            comps.timeZone = timeZone
            target.dueDateComponents = comps
            target.addAlarm(EKAlarm(absoluteDate: date))
        }

        if case .structured(let spec) = plan {
            target.addAlarm(locationAlarm(spec))
        }
    }

    /// A Reminders location alarm: the structured location (title, coordinate, radius) and the
    /// proximity that triggers it.
    nonisolated static func locationAlarm(_ spec: LocationAlarmSpec) -> EKAlarm {
        let place = EKStructuredLocation(title: spec.title)
        place.geoLocation = CLLocation(latitude: spec.latitude, longitude: spec.longitude)
        place.radius = spec.radius
        let alarm = EKAlarm()
        alarm.structuredLocation = place
        alarm.proximity = spec.proximity == .arriving ? .enter : .leave
        return alarm
    }

    enum SaveError: LocalizedError {
        case noAccess
        var errorDescription: String? {
            switch self {
            case .noAccess: "Allow Reminders access in System Settings → Privacy & Security."
            }
        }
    }

    /// Notes as saved: the notes, then a free-text location as `📍 …` (`LocationSavePlan.noteLine`;
    /// a picked place is a real location instead). The location is trimmed here too, so the
    /// popover and the in-notch Location section store exactly the same text (whitespace-only means
    /// no location).
    nonisolated static func buildNotes(notes: String, location: String?) -> String? {
        var parts: [String] = []
        if !notes.isEmpty { parts.append(notes) }
        if let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty { parts.append("📍 \(loc)") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// The part of `EKReminder` a save fills in besides title, list and priority, so the mapping can
/// be tested without an event store.
protocol ReminderAlarmTarget: AnyObject {
    var notes: String? { get set }
    var dueDateComponents: DateComponents? { get set }
    func addAlarm(_ alarm: EKAlarm)
}

extension EKReminder: ReminderAlarmTarget {}
