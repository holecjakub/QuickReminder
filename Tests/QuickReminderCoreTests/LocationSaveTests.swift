import CoreLocation
import EventKit
import Foundation
import Testing

@testable import QuickReminderCore

/// Note line vs real Reminders location: what a save writes for a location.
struct LocationSavePlanTests {
    @Test func noLocation() {
        #expect(LocationSavePlan.plan(for: nil) == .none)
        #expect(LocationSavePlan.plan(for: ReminderLocation()) == .none)
        #expect(LocationSavePlan.plan(for: ReminderLocation(text: " \n")) == .none)
    }

    /// Free text has no coordinates, so it stays the 📍 note line (trimmed).
    @Test func freeTextIsANoteLine() {
        #expect(LocationSavePlan.plan(for: ReminderLocation(text: " Office ")) == .noteLine("Office"))
        #expect(LocationSavePlan.plan(for: ReminderLocation(text: "Office", proximity: .leaving)) == .noteLine("Office"))
    }

    @Test func aPickedPlaceIsAStructuredLocation() {
        var l = ReminderLocation()
        l.pick(slavia)
        let plan = LocationSavePlan.plan(for: l)
        #expect(plan == .structured(LocationAlarmSpec(title: "Café Slavia, Smetanovo nábřeží 1012/2, Praha",
                                                      latitude: 50.0815, longitude: 14.4136,
                                                      radius: 100, proximity: .arriving)))
        #expect(plan.noteLineText == nil, "no 📍 line next to a real location")
        l.proximity = .leaving
        guard case .structured(let spec) = LocationSavePlan.plan(for: l) else { Issue.record("expected structured"); return }
        #expect(spec.proximity == .leaving)
    }

    /// Edited after picking: back to the note line.
    @Test func editedPickFallsBackToTheNoteLine() {
        var l = ReminderLocation()
        l.pick(slavia)
        l.text += " (upstairs)"
        #expect(LocationSavePlan.plan(for: l) == .noteLine("Café Slavia (upstairs)"))
    }

    @Test func titleSkipsARepeatedName() {
        let address = PickedPlace(name: "Dukelských hrdinů 47", address: "Dukelských hrdinů 47, Praha 7", latitude: 0, longitude: 0)
        #expect(LocationSavePlan.title(for: address) == "Dukelských hrdinů 47, Praha 7")
        let bare = PickedPlace(name: "Letná", address: nil, latitude: 0, longitude: 0)
        #expect(LocationSavePlan.title(for: bare) == "Letná")
        let blank = PickedPlace(name: "Letná", address: "  ", latitude: 0, longitude: 0)
        #expect(LocationSavePlan.title(for: blank) == "Letná")
    }
}

/// `RemindersService.fill` against a fake reminder: notes, due date and alarms side by side.
struct ReminderFillTests {
    final class FakeReminder: ReminderAlarmTarget {
        var notes: String?
        var dueDateComponents: DateComponents?
        var alarms: [EKAlarm] = []
        func addAlarm(_ alarm: EKAlarm) { alarms.append(alarm) }
    }

    private let due = Date(timeIntervalSince1970: 1_793_000_000)
    private let prague = TimeZone(identifier: "Europe/Prague")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = prague
        return c
    }

    private func picked(_ proximity: LocationProximity) -> ReminderLocation {
        var l = ReminderLocation(proximity: proximity)
        l.pick(slavia)
        return l
    }

    @Test func dueDateAndLocationAlarmsCoexist() throws {
        let r = FakeReminder()
        RemindersService.fill(r, notes: "Bring cake", dueDate: due, location: picked(.arriving),
                              timeZone: prague, calendar: calendar)
        #expect(r.notes == "Bring cake", "no 📍 line for a picked place")
        #expect(r.dueDateComponents?.timeZone == prague)
        #expect(r.alarms.count == 2)
        let time = try #require(r.alarms.first { $0.structuredLocation == nil })
        #expect(time.absoluteDate == due)
        let place = try #require(r.alarms.first { $0.structuredLocation != nil })
        #expect(place.proximity == .enter)
        #expect(place.absoluteDate == nil)
        let location = try #require(place.structuredLocation)
        #expect(location.title == "Café Slavia, Smetanovo nábřeží 1012/2, Praha")
        #expect(location.radius == 100)
        #expect(abs((location.geoLocation?.coordinate.latitude ?? 0) - 50.0815) < 1e-9)
        #expect(abs((location.geoLocation?.coordinate.longitude ?? 0) - 14.4136) < 1e-9)
    }

    @Test func leavingIsALeaveAlarm() throws {
        let r = FakeReminder()
        RemindersService.fill(r, notes: "", dueDate: nil, location: picked(.leaving))
        #expect(r.notes == nil)
        #expect(r.dueDateComponents == nil)
        #expect(r.alarms.count == 1)
        #expect(r.alarms.first?.proximity == .leave)
    }

    @Test func freeTextKeepsTheNoteLineAndAddsNoLocationAlarm() {
        let r = FakeReminder()
        RemindersService.fill(r, notes: "Bring cake", dueDate: due, location: ReminderLocation(text: " Office "),
                              timeZone: prague, calendar: calendar)
        #expect(r.notes == "Bring cake\n📍 Office")
        #expect(r.alarms.count == 1)
        #expect(r.alarms.first?.structuredLocation == nil)
        #expect(r.alarms.first?.proximity == EKAlarmProximity.none)
    }

    @Test func nothingSetWritesNothing() {
        let r = FakeReminder()
        RemindersService.fill(r, notes: "", dueDate: nil, location: nil)
        #expect(r.notes == nil && r.dueDateComponents == nil && r.alarms.isEmpty)
    }
}
