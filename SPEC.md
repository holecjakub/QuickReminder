# QuickReminder for macOS — Spec

A native macOS 26 menu bar app that recreates the **iOS 26 “Quick Reminder” overlay** 1:1 and, because this is a Mac, makes it **grow out of the MacBook notch** (boring.notch / NotchNook style). Triggered by a global hotkey, the notch expands into a wide black panel with the iOS layout; the reminder is saved to Apple Reminders via EventKit and the panel collapses back into the notch.

Reference screenshot: `reference/ios26-quickreminder.png` (iPhone 17 Pro Max, 3×, panel 422 pt wide)
Notch research (boring.notch, NotchDrop, DynamicNotchKit): `reference/notch-research.md`

---

## 1. Product behaviour

| Action | Result |
|--------|--------|
| Global hotkey (default `⇧⌘R`, configurable) | Notch expands into the panel, title field takes the keyboard. The frontmost app stays active (no app switch, no menu bar change). |
| Click on the physical notch | Same as the hotkey |
| `open quickreminder://show` / `hide` / `toggle` | Same actions for Shortcuts, Raycast, scripts (`quickreminder:///show` also accepted) |
| Hotkey again, `Esc` (also while typing), click outside the black shape, ⓧ | Collapse without saving; in-progress text discarded |
| Type in “New Reminder” | Save button turns blue |
| Title contains a date/time phrase (EN or CZ: “tomorrow at 2pm”, “zítra ve 14:00”, “v pátek”, “12. března”, “in 2 hours”, “za 30 minut”) | Blue suggestion chip below the input (“Tomorrow, 2:00 PM ⇥”). `Tab` or click applies it (due date set, phrase removed from title); ⓧ dismisses it for that phrase; an un-dismissed suggestion is applied automatically on save, like iOS Reminders. `NaturalDateParser` picks the right-most phrase; day-only phrases default to 9:00. |
| “Notes” line | Optional notes |
| “Reminders ▾” | Popover with all reminder lists; selection persists |
| Calendar icon | Menu: None · Mark as Urgent · Remind Me In 1 Hour · Remind Me Tomorrow · Remind Me Later… (date picker). A blue date chip appears above the bottom bar. |
| Location icon | Popover with a location text; stored in Notes as `📍 …` (icon becomes `location.fill`) |
| Flag icon | Toggles flagged (orange `flag.fill`); stored as **High priority** (EventKit exposes no flag) |
| `⌘↩`, `↩` in a field, or click ✓ | Saves, ✓ bounces, panel collapses |
| Save fails | Panel stays open, red inline message below Notes, Reminders access re-requested |
| Menu bar icon → Settings… | Hotkey recorder (rejects bare keys, Esc/click cancels, warns when the combo is taken) + default list |
| Reopen during the collapse animation | Reverses smoothly from the current shape |
| Reduce Motion enabled | Plain crossfades, no spring / blur / scale |

Non-goals (v1): subtasks, repeats, URLs, attachments.

---

## 2. Architecture

```
Sources/QuickReminder/
├── QuickReminderApp.swift          @main, Settings scene
├── AppDelegate.swift               NSStatusItem, hotkey wiring, URL scheme, creates PanelController at launch
├── Panel/PanelController.swift     owns NotchWindow; show/hide/toggle choreography; global + local event monitors; focus fallback
├── Notch/
│   ├── NotchWindow.swift           borderless, transparent, non-activating NSPanel at .screenSaver level
│   ├── NotchShape.swift            notch silhouette Shape + NotchGeometry (real notch rect from NSScreen)
│   ├── NotchState.swift            ObservableObject (isOpen, contentVisible, sizes) + NotchLayout constants
│   └── NotchContainerView.swift    black silhouette + masked content
├── Views/
│   ├── QuickReminderView.swift     root: notch band → header → input → (error/date chip) → bottom bar
│   ├── HeaderView.swift            “Reminders ▾” + ⓧ
│   ├── InputView.swift             dotted circle + PlaceholderTextField × 2
│   ├── BottomBar.swift             pill (date menu, location, flag) + ✓
│   ├── DashedCircle.swift, Theme.swift, HoverButtonStyle.swift
│   ├── ListPickerMenu.swift, DatePickerPopover.swift
├── Services/
│   ├── RemindersService.swift      EventKit: access, lists (observes EKEventStoreChanged), save
│   ├── NaturalDateParser.swift     EN + CZ date/time phrase detection (regex over a diacritics-folded copy)
│   ├── HotkeyManager.swift         Carbon RegisterEventHotKey (no Accessibility permission) + HotkeyRecorderView
│   └── Preferences.swift
└── Settings/SettingsView.swift
Tests/QuickReminderTests.swift      assertion runner (Scripts/test.sh)
```

Dependencies: AppKit, SwiftUI, EventKit, Carbon. No packages.

**Why AppKit owns the window:** SwiftUI cannot create a non-activating panel above the menu bar. The window frame is always the fully-open size (600 × 214 pt), anchored to the top edge of the built-in display and centred on the notch; everything visible is drawn by SwiftUI, so the window itself is invisible and shadowless like the real notch.

---

## 3. Notch choreography

| Item | Value | Source |
|------|-------|--------|
| Real notch (14" MBP) | 221 × 38 pt, from `safeAreaInsets.top` and `auxiliaryTop{Left,Right}Area` | NotchDrop / DynamicNotchKit |
| Closed silhouette | notch width + 2 × 6 pt top fillets + 2 pt bleed, 39 pt tall | boring.notch (+4 bleed) |
| Radii closed / open | top 6 / 19 pt, bottom 14 / 32 pt | boring.notch, iOS reference (bottom) |
| Open size | 600 × 214 pt (first 38 pt = notch band, dead zone) | — |
| Open animation | `spring(response 0.42, damping 0.78)` on the shape; content `easeOut 0.20` delayed 0.16 s, blur 8 → 0, scale 0.94 → 1 from top, masked to the live silhouette | DynamicNotchKit transition |
| Close animation | `spring(response 0.30, damping 0.92)`; content `easeOut 0.12`; window ordered out after 0.36 s | — |
| No-notch display | virtual pill 200 pt × menu-bar height at top centre | NotchDrop fallback |
| Window | `.borderless, .nonactivatingPanel`, `.screenSaver`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `hasShadow = false`, `canBecomeKey = true` | boring.notch |
| Dismissal | global monitor (clicks outside the app) + local monitor (Esc, clicks inside the window but outside the silhouette) | — |

---

## 4. Visual spec (measured from the iOS reference, applied 1:1)

| Element | Value |
|---------|-------|
| Background | pure black (merges with the notch); iOS uses #1C1C1E glass |
| Horizontal padding | 20 pt from the visible edge (+19 pt top fillet inset) |
| Header | “Reminders” SF Pro 22 pt bold, #0A84FF; chevron 13 pt bold, 7 pt gap |
| Close ⓧ | 24 pt circle #59595D, `xmark` 11 pt bold white, 36 pt hit area |
| Dotted circle | 21 pt, 1.5 pt stroke, #59595D, round dots |
| Title | 19 pt regular, white; placeholder #59595D |
| Notes | 15 pt regular; placeholder #59595D |
| Pill | 44 pt tall capsule, fill white 3 %, 1 pt stroke #3D3D3F; icons `calendar.badge.clock` 24 pt, `location` 22 pt, `flag` 22 pt, 38 pt hit areas, 55 pt centre spacing |
| Save ✓ | 48 pt circle, #474749 disabled / #0A84FF enabled, `checkmark` 22 pt semibold |
| Active states | date → blue icon + chip; location → `location.fill` blue; flag → `flag.fill` orange (1.0, 0.62, 0.04) |
| Pointer | hand cursor, 1.06× hover, 0.94× press on every control |
| Vertical rhythm | notch band 38 → 8 → header → 10 → input → ≥ 14 → bottom bar → 22 bottom |

---

## 5. Signing, privacy, entitlements

- **Intentionally unsandboxed, hardened runtime on.** With `com.apple.security.app-sandbox` the EventKit XPC connection fails on this machine (macOS 26.6 / Xcode 27: `NSMachErrorDomain 4099`, no TCC prompt) regardless of signing identity; see `PRs/2026-09-18-notch-review.md` finding 1. Without the sandbox the reminders entitlement is inert, so none is declared.
- `build.sh` signs with the “Apple Development” identity when present (TCC grant survives rebuilds), otherwise ad-hoc, always with `--options runtime`, and fails the build if the signature or the runtime flag does not stick.
- Info.plist: `LSUIElement`, `NSRemindersFullAccessUsageDescription`, `CFBundleURLTypes` (`quickreminder`), `LSMinimumSystemVersion 26.0`.
- Known accepted risk: any app or web page can open the panel via `quickreminder://show`; the panel is a 600 pt black card at the top of the screen, so it is not covert.

---

## 6. Build & test

- `./build.sh` / `./build.sh run` — direct `swiftc` whole-module build + hand-assembled bundle (works without accepting the Xcode license); `xcodegen generate` keeps the `.xcodeproj` in sync.
- `Scripts/test.sh` — compiles sources + `Tests/` into a runner: NotchShape geometry, NotchGeometry, NotchLayout, Shortcut encoding.
- `Scripts/shot.sh <name> [-R x,y,w,h | --full]` — screenshots into `build/shots/` (override with `QR_SHOT_DIR`).

---

## 7. Acceptance criteria

1. `⇧⌘R` from any app makes the notch expand into the panel without switching apps; typing goes into the title field.
2. Closed state is invisible (only the real notch); mid-animation no content leaks outside the black shape.
3. Panel matches the iOS reference side by side in typography, colours, spacing and control sizes (§4).
4. `⌘↩` creates a reminder in the chosen list; Esc / click outside / hotkey collapse it.
5. List picker, date menu, location popover and flag work and are reflected in the saved reminder.
6. `Scripts/test.sh` passes; `./build.sh` produces a hardened-runtime-signed bundle.
