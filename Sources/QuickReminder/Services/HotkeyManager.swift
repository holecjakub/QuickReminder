import AppKit
import Carbon
import SwiftUI

/// A zero-dependency global hotkey manager built directly on the Carbon
/// `RegisterEventHotKey` / `InstallEventHandler` APIs. Replaces the
/// `KeyboardShortcuts` SPM package.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// A single global keyboard shortcut, persisted in `UserDefaults`.
    struct Shortcut: Codable, Equatable {
        var keyCode: UInt32
        /// Carbon modifier flags: `cmdKey`, `shiftKey`, `optionKey`, `controlKey` (bitwise OR'd).
        var modifiers: UInt32

        /// Default shortcut: ⇧⌘R (keyCode 15 = R).
        static let `default` = Shortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))

        var displayString: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            result += Self.keyCodeToString(keyCode)
            return result
        }

        /// Best-effort mapping from a virtual keyCode to a human-readable label.
        static func keyCodeToString(_ keyCode: UInt32) -> String {
            let map: [UInt32: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
                11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
                20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
                29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
                39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
                50: "`", 65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "Enter", 78: "-",
                81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
                91: "8", 92: "9", 36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
                123: "←", 124: "→", 125: "↓", 126: "↑",
            ]
            return map[keyCode] ?? "Key\(keyCode)"
        }
    }

    private static let defaultsKey = "hotkey"

    var onPressed: (() -> Void)?

    var shortcut: Shortcut {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
                let decoded = try? JSONDecoder().decode(Shortcut.self, from: data)
            {
                return decoded
            }
            return .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            // Always (re)register: the previous registration may have failed
            // because the old combo was taken by another app.
            register()
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static let hotKeySignature: FourCharCode = {
        // "QRHK" packed into a FourCharCode.
        let chars: [Character] = ["Q", "R", "H", "K"]
        var result: FourCharCode = 0
        for char in chars {
            result = (result << 8) + FourCharCode(char.asciiValue ?? 0)
        }
        return result
    }()
    private static let hotKeyID: UInt32 = 1

    private init() {}

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == HotkeyManager.hotKeyID else { return noErr }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else { return }

        let current = shortcut
        var hotKeyRefLocal: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            current.keyCode,
            current.modifiers,
            EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID),
            GetApplicationEventTarget(),
            0,
            &hotKeyRefLocal
        )

        if registerStatus == noErr {
            hotKeyRef = hotKeyRefLocal
            registrationFailed = false
        } else {
            // Typically the combination is already owned by another app.
            registrationFailed = true
        }
    }

    /// True when the current shortcut could not be registered system-wide.
    private(set) var registrationFailed = false

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

/// A small SwiftUI control that shows the current global shortcut and lets
/// the user record a new one by pressing a key combination.
struct HotkeyRecorderView: View {
    @State private var shortcut: HotkeyManager.Shortcut = HotkeyManager.shared.shortcut
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var registrationFailed = HotkeyManager.shared.registrationFailed

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: startRecording) {
                Text(isRecording ? "Press a key combination…" : shortcut.displayString)
                    .frame(minWidth: 120)
            }
            if registrationFailed {
                Text("\(shortcut.displayString) is in use by another app.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }

            var modifiers: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }

            // Esc cancels; a bare key (no modifier) would hijack that key system-wide.
            if event.keyCode == 53 { return nil }
            guard modifiers != 0 else { return event }

            let newShortcut = HotkeyManager.Shortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers
            )
            shortcut = newShortcut
            HotkeyManager.shared.shortcut = newShortcut
            registrationFailed = HotkeyManager.shared.registrationFailed
            return nil
        }
        // Clicking anywhere else cancels recording so the monitor never eats a stray key.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            stopRecording()
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}
