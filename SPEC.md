# QuickReminder for macOS — Spec

A native macOS 26 menu bar app inspired by the **iOS 26 “Quick Reminder” overlay** (matched to its measured metrics) and, because this is a Mac, makes it **grow out of the MacBook notch** (boring.notch / NotchNook style). Triggered by a global hotkey, the notch expands into a wide black panel with the iOS layout; the reminder is saved to Apple Reminders via EventKit and the panel collapses back into the notch.

Design reference: Apple's iOS 26 quick-reminder overlay (measured on an iPhone 17 Pro Max at 3×; panel 422 pt wide). No Apple artwork is kept in the repository; the measurements live in §4.
Notch research (boring.notch, NotchDrop, DynamicNotchKit): `reference/notch-research.md`

---

## 1. Product behaviour

| Action | Result |
|--------|--------|
| Global hotkey (default `⇧⌘R`, configurable) | Notch expands into the panel, title field takes the keyboard. The frontmost app stays active (no app switch, no menu bar change). |
| Pointer over the physical notch | After a 90 ms dwell (a pointer merely crossing the notch does nothing) the closed silhouette swells by 22 × 5 pt with a lively spring (`response 0.32, damping 0.55`) and the trackpad taps once (`NSHapticFeedbackManager` `.levelChange`); settles back when the pointer leaves. Arming is decided from the pointer position when the notch parks: still on it → wait for it to leave first. Reduce Motion: no swell, haptic only. While parked the window is excluded from screenshots and screen sharing (`sharingType = .none`; `QR_CAPTURE_PARKED=1` for dev captures). |
| Click on the physical notch | Same as the hotkey |
| `open quickreminder://show` / `hide` / `toggle` | Same actions for Shortcuts, Raycast, scripts (`quickreminder:///show` also accepted) |
| Open the app from Raycast, Spotlight, Finder or the Dock | Opens the panel: a reopen of the running app (`applicationShouldHandleReopen`) or a hand launch (plain `kAEOpenApplication` event, read in `applicationWillFinishLaunching`). Login-item launches (`keyAELaunchedAsLogInItem` or no launch event) and URL-scheme launches stay silent. `Scripts/raycast/quick-reminder.sh` is a Raycast Script Command titled “Quick Reminder”. |
| Hotkey again, `Esc` (also while typing), click outside the black shape, ⓧ | Collapse without saving; in-progress text discarded |
| Type in “New Reminder” | Save button turns blue |
| Title contains a date/time phrase (EN or CZ: “tomorrow at 2pm”, “zítra ve 14:00”, “v pátek”, “12. března”, “in 2 hours”, “za 30 minut”) | Blue suggestion chip below the input (“Tomorrow, 2:00 PM ⇥”). `Tab` or click applies it (due date set, phrase removed from title); ⓧ dismisses it for that phrase; an un-dismissed suggestion is applied automatically on save, like iOS Reminders. `NaturalDateParser` picks the right-most phrase; day-only phrases default to 9:00 (`ScheduleDefaults.resolveDayOnly`). |
| “Notes” line | Optional notes |
| “Reminders ▾” | Popover with all reminder lists; selection persists. The list's colour becomes the panel accent: header, chevron, ✓, date chips, caret, active icons and the saved badge (iOS blue when EventKit has no colour). |
| Calendar icon | Native menu with fixed row positions (labels adapt, rows never hide), each showing the time it resolves to: None · Mark as Urgent (flag + 1 h) · Remind Me In 1 Hour · This Evening (19:00; “Tomorrow Evening” from 18:30) · Remind Me Tomorrow (9:00) · This Weekend (Sat 9:00; “Next Weekend” on Sat/Sun) · Next Week (Mon 9:00) · Custom… ⌘D. An accent date chip appears above the bottom bar; clicking it reopens Set Date on that date, ⓧ clears it. |
| `⌘D` (title or notes), Custom…, date chip | **Set Date popover**, no clock face: type field (EN/CZ phrases as in the title, plus picker-only `14`, `1430`, `14.30`, `+90m`/`+2h`/`+3d`, `fri 2pm`; a dotted pair with a second part 10–12 is a Czech day.month (`15.11`, `24.12`, `1.12`), other dotted pairs and anything with `:` are times; the whole input must be a date, “tomorrow please” is rejected) prefilled from the title's live suggestion (once opened from it, any Set or preset strips the phrase from the title, even after editing the text or using the controls; Cancel and Clear keep it — calendar-menu presets strip a live phrase the same way); live preview (“Tomorrow, 14:00 · in 28 h”, “In the past” warning); 2 × 3 preset cards (In 1 Hour, Evening, Tomorrow, Weekend, Next Week, Next Month; `⌘1`…`⌘6`, one click commits); day label + typed time field + 9:00/12:00/15:00/19:00 chips; collapsible date-only calendar (`⌘K`); Clear · Cancel · “Set · Fri 9:00”. Opens on the current date, else the suggestion, else tomorrow 9:00. `↩`/`⌘↩` set (an invalid entry beeps), `Esc` or a click outside cancels without writing and leaves the panel open. Day-only dates everywhere (Tab, typing, presets) go through one rule: 9:00, or for “today” after 9:00 the next :00/:30 at least 15 min ahead. Labels follow the locale (`j:mm` templates: 19:00 in Czech, 7:00 PM in en_US) and the date's distance: time only today, weekday + time for the next six days, day + month + time from a week out (“1. 11. 9:00”, “Nov 1 at 9:00 AM”), so Tomorrow and Next Month never read alike; formatters are rebuilt when the locale, 12/24-hour setting or time zone changes. Keyboard: focus opens in the type field; `⌘1`…`⌘6` presets, `⌘K` calendar (closing it hands focus back to the field), `↩`/`⌘↩` Set, `Esc` Cancel. Without Full Keyboard Access (the macOS default) Tab visits only the text controls: type field → time field → calendar; with it, buttons join in view order (field → presets → calendar toggle → time field → time chips → footer). The chips are shortcuts for typing a time, which the field and the time field already cover. VoiceOver: the parsed preview is announced ~400 ms after typing pauses (“Not a date” included) and is the field's hint; chips read “Set time to 9:00”; the calendar toggle says whether it shows or hides. |
| Location icon | Popover with a location text; stored in Notes as `📍 …` (icon becomes `location.fill`) |
| Flag icon | Toggles flagged (orange `flag.fill`); stored as **High priority** (EventKit exposes no flag) |
| `⌘↩`, `↩` in a field, or click ✓ | Saves, then the “saved” choreography: content fades, the panel collapses to notch height but stays 72 pt wider on each side, the ✓ flies into the right-hand extension (matched geometry), draws itself in and pops, and after 1.0 s the notch returns to normal. Reduce Motion: plain collapse. |
| Save fails | Panel stays open, red inline message below Notes, Reminders access re-requested |
| Menu bar icon → Settings… | Own AppKit window hosting the SwiftUI form: Launch at login (`SMAppService`), hotkey recorder (rejects bare keys, Esc/click cancels, warns when the combo is taken), default list |
| Reopen during the collapse animation | Reverses smoothly from the current shape |
| Reduce Motion enabled | Plain crossfades, no spring / blur / scale |

Non-goals (v1): subtasks, repeats, URLs, attachments.

---

## 2. Architecture

```
Sources/QuickReminder/
├── QuickReminderApp.swift          @main: NSApplication + AppDelegate (no SwiftUI scenes)
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
│   ├── ListPickerMenu.swift, PopUpMenu.swift (native NSMenu with a detail column)
│   ├── SchedulePopover.swift       Set Date: type field, presets, day + time, date-only calendar
├── Services/
│   ├── RemindersService.swift      EventKit: access, lists (observes EKEventStoreChanged), save
│   ├── NaturalDateParser.swift     EN + CZ date/time phrase detection (regex over a diacritics-folded copy)
│   ├── ScheduleDefaults.swift      day-only rule (9:00 / next :00–:30 slot), DST-safe compose, DayPart hours, AppClock (QR_NOW)
│   ├── DatePresets.swift           DatePreset: the shared preset set (dates, adaptive titles, locale details)
│   ├── ScheduleInput.swift         whole-input reading of the popover's type field + picker-only shorthands
│   ├── HotkeyManager.swift         Carbon RegisterEventHotKey (no Accessibility permission) + HotkeyRecorderView
│   └── Preferences.swift
└── Settings/SettingsView.swift, SettingsWindowController.swift, LoginItem.swift
Tests/QuickReminderCoreTests/       Swift Testing suite (swift test / Scripts/test.sh)
```

Dependencies: AppKit, SwiftUI, EventKit, Carbon. No packages.

**Why AppKit owns the window:** SwiftUI cannot create a non-activating panel above the menu bar. The window frame is always the fully-open size (600 × 241 pt at 100 % text size), anchored to the top edge of the built-in display and centred on the notch; everything visible is drawn by SwiftUI, so the window itself is invisible and shadowless like the real notch.

---

## 3. Notch choreography

| Item | Value | Source |
|------|-------|--------|
| Real notch (14" MBP) | 221 × 38 pt, from `safeAreaInsets.top` and `auxiliaryTop{Left,Right}Area` | NotchDrop / DynamicNotchKit |
| Closed silhouette | notch width + 2 × 6 pt top fillets + 2 pt bleed, 39 pt tall | boring.notch (+4 bleed) |
| Radii closed / open | top 6 / 19 pt, bottom 14 / 32 pt | boring.notch, iOS reference (bottom) |
| Open size | 600 × 241 pt at 100 % text size (first 38 pt + 1 pt bleed = notch band, dead zone; 202 pt of content below); the height is the notch band plus the vertical rhythm below, computed in `NotchLayout.contentHeight` | — |
| Open animation | `spring(response 0.42, damping 0.78)` on the shape; content `easeOut 0.20` delayed 0.16 s, blur 8 → 0, scale 0.94 → 1 from top, masked to the live silhouette | DynamicNotchKit transition |
| Close animation | `spring(response 0.30, damping 0.92)`; content `easeOut 0.12`; window ordered out after 0.36 s | — |
| Saved choreography | shape → `closedSize + 2×72 pt` wide at notch height with `spring(0.45, 0.82)`; ✓ badge 24 pt lands in the right extension via `matchedGeometryEffect`; tick trims in over 0.28 s after 0.32 s, bounce 1.18× at 0.55 s; hold 1.0 s, then `hide()` | Dynamic Island “done” states |
| No-notch display | virtual pill 200 pt × menu-bar height at top centre | NotchDrop fallback |
| Window | `.borderless, .nonactivatingPanel`, `.screenSaver`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `hasShadow = false`, `canBecomeKey = true`. On a notched display it stays ordered in permanently: closed = a small window hugging the notch (hover size + 16 × 8 pt margin, so it only intercepts clicks on the notch itself, and SwiftUI `onHover`/tap on the silhouette give hover and click without system-wide mouse polling); open = the full 648 × 238 pt canvas. Displays without a notch keep the order-out behaviour. | boring.notch |
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
| Pill | 44 pt tall capsule, fill white 3 %, 1 pt stroke #3D3D3F; icons `calendar.badge.clock`, `location`, `flag` rendered through AppKit's `NSImage.SymbolConfiguration` at 22 pt (optically balanced: 26 × 21.5 / 21 × 20 / 19 × 21 pt visible — SwiftUI's `Image(systemName:)` draws the badge symbol markedly smaller), 38 pt hit areas, 55 pt centre spacing |
| Save ✓ | 48 pt circle, #474749 disabled / #0A84FF enabled, `checkmark` 22 pt semibold |
| Active states | date → blue icon + chip; location → `location.fill` blue; flag → `flag.fill` orange (1.0, 0.62, 0.04) |
| Pointer | hand cursor. Pill icons (calendar, location, flag): macOS HIG hover feedback, a circular highlight (white 10 %, 18 % pressed, 0.12 s fade), no scaling so the row never shifts. Round controls (ⓧ, ✓, header, chips): 1.06× hover / 0.94× press spring, hit-tested on the layout frame. The date options open as a native `NSMenu` from a plain button (a SwiftUI `Menu` with the borderless style brought its own AppKit hover chrome and resized on hover). |
| Vertical rhythm | notch band 38 → 8 → header → 10 → input → flexible → fixed 26 pt slot for the date chip / suggestion / error → 8 → bottom bar → 20 bottom (equal to the 20 pt side inset, so the ✓ sits the same distance from the right and bottom edges). The slot is always reserved, so the bar never moves when a chip appears. |
| Text size | Every font and control metric is multiplied by `NotchLayout.textScale` = system body size ÷ 13 (System Settings → Accessibility → Display → Text size, incl. per-app), clamped 0.85–1.6; the open panel height scales with it (notch band + `NotchLayout.contentHeight(textScale:)`), width up to 1.3×. Display scaling (Displays → resolution) needs nothing: all geometry is in points and the notch is read live from `NSScreen`. `QR_TEXT_SCALE=1.3` forces a scale for layout checks. |

---

## 5. Signing, privacy, entitlements

- **Intentionally unsandboxed, hardened runtime on.** Experiment on macOS 26.6 / Xcode 27: with `com.apple.security.app-sandbox` + the reminders entitlement, `requestFullAccessToReminders()` fails with `NSMachErrorDomain 4099` and no TCC prompt appears, for an Apple Development identity and ad-hoc, with and without hardened runtime, and after deleting the app's container. Unsandboxed, the same build works. Without the sandbox the reminders entitlement is inert, so none is declared. Re-test on a newer macOS before shipping sandboxed.
- **URL scheme hardening:** commands are ignored while Secure Event Input is active (password fields), debounced to one per second and capped at five per minute.
- `build.sh` signs with the “Apple Development” identity when present (TCC grant survives rebuilds), otherwise ad-hoc, always with `--options runtime`, and fails the build if the signature or the runtime flag does not stick.
- Info.plist: `LSUIElement`, `NSRemindersFullAccessUsageDescription`, `CFBundleURLTypes` (`quickreminder`), `LSMinimumSystemVersion 26.0`.
- Residual accepted risk: any app or web page can open the panel via `quickreminder://show` (browsers ask before opening a custom scheme); the panel is a 600 pt black card at the top of the screen, so it is not covert, and typed text goes nowhere but Reminders.

---

## 6. Build & test

- `./build.sh` / `./build.sh run` — direct `swiftc` build (Release: `-O -wmo -dead_strip`; `CONFIGURATION=Debug` for `-Onone -g`) + hand-assembled bundle (works without accepting the Xcode license); `xcodegen generate` keeps the `.xcodeproj` in sync. Unaffected by the SwiftPM package below (it still compiles `Sources/` directly with `swiftc`).
- `swift test` / `Scripts/test.sh` — Swift Testing suite in `Tests/QuickReminderCoreTests`, run against the `QuickReminderCore` SwiftPM library target (`Package.swift`) that wraps `Sources/QuickReminder` (minus the `@main` app file): NotchShape/NotchGeometry geometry and hit-testing, NotchState size precedence, NaturalDateParser (~240 cases), HotkeyManager.Shortcut, SuggestionDateFormatter, ScheduleDefaults / DatePreset / ScheduleInput (fixed `now`, Europe/Prague calendar incl. DST days, cs_CZ / en_US), PopUpMenu. `Scripts/test.sh` passes extra arguments through (e.g. `--filter`) and prints a one-line summary.
- `Scripts/shot.sh <name> [-R x,y,w,h | --full]` — screenshots into `build/shots/` (override with `QR_SHOT_DIR`).

---

## 7. Acceptance criteria

1. `⇧⌘R` from any app makes the notch expand into the panel without switching apps; typing goes into the title field.
2. Closed state is invisible (only the real notch); mid-animation no content leaks outside the black shape.
3. Panel matches the iOS reference side by side in typography, colours, spacing and control sizes (§4).
4. `⌘↩` creates a reminder in the chosen list; Esc / click outside / hotkey collapse it.
5. List picker, date menu, location popover and flag work and are reflected in the saved reminder.
6. `Scripts/test.sh` passes; `./build.sh` produces a hardened-runtime-signed bundle.
