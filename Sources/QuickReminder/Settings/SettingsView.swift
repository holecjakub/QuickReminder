import SwiftUI

struct SettingsView: View {
    @ObservedObject private var remindersService = RemindersService.shared
    @AppStorage("selectedListId") private var selectedListId: String = ""

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Show Quick Reminder:") {
                    HotkeyRecorderView()
                }
            }

            Section("Default List") {
                if remindersService.calendars.isEmpty {
                    Text("No reminder lists found")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("List", selection: $selectedListId) {
                        Text("Default").tag("")
                        ForEach(remindersService.calendars, id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle()
                                    .fill(cal.cgColor.map(Color.init(cgColor:)) ?? .gray)
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                            .tag(cal.calendarIdentifier)
                        }
                    }
                }
            }

            if remindersService.accessDenied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminders access is required.")
                            .foregroundStyle(.red)
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .navigationTitle("QuickReminder Settings")
        .onAppear {
            if remindersService.accessGranted {
                remindersService.loadCalendars()
            }
        }
    }
}
