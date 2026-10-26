import SwiftUI

struct SettingsView: View {
    @ObservedObject private var remindersService = RemindersService.shared
    @ObservedObject private var loginItem = LoginItem.shared
    @AppStorage("selectedListId") private var selectedListId: String = ""
    @AppStorage(DatePickerStyle.defaultsKey) private var datePickerStyle: DatePickerStyle = .defaultStyle

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
                if loginItem.requiresApproval {
                    HStack {
                        Text("Approve QuickReminder under Login Items to finish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Hotkey") {
                LabeledContent("Show Quick Reminder:") {
                    HotkeyRecorderView()
                }
            }

            Section("Set Date") {
                Picker("Date picker style", selection: $datePickerStyle) {
                    ForEach(DatePickerStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
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
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loginItem.refresh()
            if remindersService.accessGranted {
                remindersService.loadCalendars()
            }
        }
    }
}
