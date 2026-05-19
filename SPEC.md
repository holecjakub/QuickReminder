# QuickReminder for macOS — Spec

A native macOS 26 menu bar app that replicates the **iOS 26 Reminders quick-add overlay** 1:1. Triggered by a global hotkey, shows a floating glassy panel for entering a reminder with optional date/location/flag, saves to Apple Reminders via EventKit, then disappears.

Reference screenshot: `reference/ios26-quickreminder.png`

---

## 1. Product behavior

| Action | Result |
|--------|--------|
| Press global hotkey (default `⇧⌘R`) | Overlay panel appears, centered on the screen with the mouse, slightly above center (Spotlight-style); text field is focused; app does **not** activate / steal focus from the frontmost app |
| Press hotkey again, or `Esc`, or click outside | Panel dismisses; any in-progress text is discarded |
| Click "Reminders ▾" header | Popover/menu lists all user reminder lists; selection changes target list and persists across launches |
| Click `×` button (top-right) | Same as Esc — dismiss |
| Type into "New Reminder" field | Save button becomes enabled (blue) |
| Type into "Notes" field below | Optional second-line notes |
| Click calendar+clock pill icon | Opens a small date/time picker popover; selected date shown as a chip |
| Click location pill icon | (v1) Opens a text field popover for location string; saved as part of notes or via EKStructuredLocation if simple |
| Click flag pill icon | Toggles flagged state (icon turns orange/filled when on) |
| Press `⌘↩` or click `✓` button | Saves reminder via EventKit, plays subtle sound or visual confirm, dismisses panel |
| Menu bar icon → Settings | Configure hotkey via `KeyboardShortcuts.Recorder`, choose default list |
| Menu bar icon → Quit | Exits app |

**Non-goals (v1):** subtasks, repeats, reminder URL, image attachments, full natural-language parsing (only basic "today/tomorrow at 3pm" if trivial — defer if it adds scope).

---

## 2. Architecture

```
QuickReminder/
├── QuickReminderApp.swift          // @main, App lifecycle, AppDelegate adapter
├── AppDelegate.swift               // NSStatusItem (menu bar), hotkey registration, panel lifecycle
├── Panel/
│   ├── QuickReminderPanel.swift    // NSPanel subclass (.nonactivatingPanel)
│   └── PanelController.swift       // singleton that owns the panel, shows/hides, centers on active screen
├── Views/
│   ├── QuickReminderView.swift     // root SwiftUI view rendered inside panel
│   ├── HeaderView.swift            // "Reminders ▾" + close button
│   ├── InputView.swift             // dashed checkbox + title TextField + notes TextField
│   ├── BottomBar.swift             // pill with 3 icons + save button
│   ├── DashedCircle.swift          // custom SwiftUI shape for empty checkbox
│   ├── ListPickerMenu.swift        // popover/menu listing EKCalendars
│   └── DatePickerPopover.swift     // small date/time picker
├── Services/
│   ├── RemindersService.swift      // EventKit wrapper: requestAccess, listCalendars, save
│   └── Preferences.swift           // @AppStorage wrapper for selected list ID, hotkey
├── Settings/
│   └── SettingsView.swift          // SwiftUI settings scene
├── Resources/
│   ├── Assets.xcassets             // app icon, menu bar template icon
│   └── Info.plist                  // LSUIElement, usage descriptions
└── QuickReminder.entitlements      // sandbox + reminders entitlement
```

**Module dependencies:** SwiftUI, AppKit, EventKit, `KeyboardShortcuts` (SPM).

**Why this structure:** AppKit owns the window because SwiftUI's `WindowGroup` doesn't give us `.nonactivatingPanel` + custom level. The panel hosts a SwiftUI tree via `NSHostingView` wrapped inside `NSGlassEffectView` for the Liquid Glass material.

---

## 3. Visual spec (1:1 with iOS reference)

| Element | Spec |
|---------|------|
| **Panel size** | 380×260 pt (initial), grows if notes wrap (max ~360 pt tall) |
| **Corner radius** | 28 pt |
| **Background** | `NSGlassEffectView` (macOS 26 Liquid Glass). Fallback for < 26: `NSVisualEffectView` `.hudWindow` `.active`. No solid fill on top. |
| **Padding** | 24 pt horizontal, 20 pt vertical inside panel |
| **Header "Reminders"** | SF Pro Display, weight `.bold`, size `28 pt`, color `Color.accentColor` (system blue). Chevron: `Image(systemName: "chevron.down")`, weight `.bold`, same color, ~22 pt, baseline-aligned to title with small leading gap (8 pt) |
| **Close button** | `Image(systemName: "xmark.circle.fill")`, font size 28 pt, `.symbolRenderingMode(.hierarchical)`, foreground white. Hit area 36×36 pt. |
| **Dashed checkbox** | Custom `Shape` — `Circle` stroked with `StrokeStyle(lineWidth: 1.5, dash: [3.5, 3])`. Size 24×24 pt. Color: `Color.secondary.opacity(0.6)`. |
| **Title TextField** | Placeholder "New Reminder", SF Pro Display 22 pt regular. Placeholder color `Color.secondary.opacity(0.55)`. Cursor: system blue. Plain style, no border, no background. |
| **Notes TextField** | Placeholder "Notes", SF Pro Display 17 pt regular. Placeholder color `Color.secondary.opacity(0.4)`. |
| **Spacing** | Header → input: 18 pt. Title → notes: 6 pt. Notes → bottom bar: 36 pt (flexible spacer to keep total height ~260). Checkbox → title text: 12 pt. |
| **Bottom pill** | Capsule shape, height 52 pt, padded inset 18 pt horizontal. Background: `Color.white.opacity(0.08)` over the glass; subtle 1 pt stroke `Color.white.opacity(0.06)`. Width: hugs content. |
| **Pill icons** | All white, font size 22 pt, weight `.regular`. Icons (left→right): `calendar.badge.clock`, `location.fill`, `flag` (outlined). Spacing between icons: 28 pt. Tap area 36×36 pt each. |
| **Save button** | Circle, 56×56 pt. Fill `Color.white.opacity(0.12)` when disabled (empty input), `Color.accentColor` when enabled. Inside: `Image(systemName: "checkmark")`, font 22 pt, weight `.semibold`, white. |
| **Bottom row layout** | HStack: pill on the left, `Spacer()`, save button on the right. Both vertically aligned. |
| **Toggle states** | Flag icon: filled `flag.fill` with orange tint when active. Date icon: shows blue tint when a date is set, with a small date label chip appearing below the icon row. |

**Animations:**
- **Show:** fade-in + scale from 0.96 → 1.0 over 0.18 s, easing `.spring(response: 0.35, dampingFraction: 0.78)`
- **Hide:** fade-out + scale 1.0 → 0.96 over 0.12 s ease-out
- **Save success:** quick scale bounce of the checkmark (1.0 → 1.15 → 1.0 over 0.2 s), then hide

---

## 4. Technical details

### Panel
```swift
final class QuickReminderPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        hasShadow = true
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { PanelController.shared.hide() }
}
```

Wrap SwiftUI in `NSGlassEffectView` (macOS 26):
```swift
let glass = NSGlassEffectView()
glass.cornerRadius = 28
glass.contentView = NSHostingView(rootView: QuickReminderView())
panel.contentView = glass
```

### Hotkey
```swift
extension KeyboardShortcuts.Name {
    static let showQuickReminder = Self("showQuickReminder",
        default: .init(.r, modifiers: [.command, .shift]))
}
// In AppDelegate.applicationDidFinishLaunching:
KeyboardShortcuts.onKeyDown(for: .showQuickReminder) {
    PanelController.shared.toggle()
}
```

### EventKit
- Call `try await store.requestFullAccessToReminders()` on first launch; if denied, show a small banner with a "Open Settings" button.
- `store.calendars(for: .reminder)` for list picker.
- Selected list ID persisted in UserDefaults (`@AppStorage("selectedListId")`).
- Save:
  ```swift
  let r = EKReminder(eventStore: store)
  r.title = title
  r.notes = notes.isEmpty ? nil : notes
  r.calendar = selectedCalendar
  if let date { r.dueDateComponents = ...; r.addAlarm(.init(absoluteDate: date)) }
  if flagged { r.priority = EKReminderPriority.high.rawValue }
  try store.save(r, commit: true)
  ```

### Click-outside dismiss
```swift
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
    PanelController.shared.hide()
}
```
Attach when showing, invalidate when hiding.

### Centering
```swift
func screenWithMouse() -> NSScreen {
    NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        ?? NSScreen.main ?? NSScreen.screens[0]
}
// Place at midX, midY + 10% above center (visibleFrame)
```

---

## 5. Entitlements & Info.plist

**Info.plist additions:**
```xml
<key>LSUIElement</key><true/>
<key>NSRemindersFullAccessUsageDescription</key>
<string>QuickReminder needs access to Reminders so you can quickly capture tasks from the floating overlay.</string>
<key>NSRemindersUsageDescription</key>
<string>QuickReminder needs access to Reminders so you can quickly capture tasks from the floating overlay.</string>
```

**Entitlements:**
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.personal-information.reminders</key><true/>
```

---

## 6. Build & run

- **Target:** macOS 26.0 minimum (Tahoe), arm64 + x86_64 universal
- **Tooling:** Xcode 26.5, Swift 6.3.2
- **Scaffold approach:** Use `xcodegen` (install via brew if missing) + `project.yml` for reproducible project generation. The implementation agent should:
  1. `brew install xcodegen` if not present
  2. Author `project.yml`, `Info.plist`, `.entitlements` files
  3. Run `xcodegen generate` to produce `.xcodeproj`
  4. `xcodebuild -scheme QuickReminder -configuration Debug build` to verify it compiles
  5. The compiled `.app` lives under `~/Library/Developer/Xcode/DerivedData/...` — copy to project `build/` for easy testing
- **Code signing:** Sign with the developer's Apple ID team via automatic signing in `project.yml`. For first run, the user will need to approve in System Settings → Privacy & Security → Reminders.

---

## 7. Acceptance criteria

The build is "1:1 with iOS" when:

1. Pressing `⇧⌘R` from any app reveals the panel centered on the active screen without switching apps.
2. The panel's appearance — corner radius, glass material, header typography/color, dashed checkbox shape, pill capsule, save button — matches the reference screenshot side-by-side (manual visual diff by reviewer agent).
3. Typing a title and pressing `⌘↩` (or clicking ✓) creates a real reminder in Apple Reminders.app in the selected list.
4. Pressing Esc, clicking outside, or pressing the hotkey again dismisses the panel.
5. Clicking "Reminders ▾" shows all of the user's reminder lists and selection persists.
6. Flag, date, and location buttons toggle/open their popovers and the saved reminder reflects the chosen values.
7. The app is sandboxed and notarization-ready (entitlements correct, Info.plist correct).
