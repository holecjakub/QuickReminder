# QuickReminder

A macOS 26 menu bar app that recreates the **iOS 26 “Quick Reminder” overlay** 1:1 — and, because we are on a Mac, the panel animates **out of the MacBook notch** (boring.notch / NotchNook style): the black notch grows into a wide panel, you type, hit `⌘↩`, and it collapses back.

Reference: `reference/ios26-quickreminder.png` · Notch research: `reference/notch-research.md`

## Build

`xcodebuild` / `xcrun` need the Xcode 27 license accepted (`sudo xcodebuild -license accept`). Until then the build script drives the toolchain's `swiftc` directly and assembles the `.app` bundle by hand — no Xcode needed:

```bash
./build.sh        # build  → build/QuickReminder.app
./build.sh run    # build, kill the running instance, launch
```

The app is signed with your “Apple Development” identity when one is in the keychain (so the Reminders permission survives rebuilds), otherwise ad-hoc — always with hardened runtime, intentionally **not** sandboxed (sandboxing breaks the EventKit connection on macOS 26.6, see `SPEC.md` §5). `xcodegen generate` keeps `QuickReminder.xcodeproj` in sync for when you want to open it in Xcode.

```bash
Scripts/test.sh   # geometry / shortcut unit checks, no Xcode project needed
```

## Use

| Action | Result |
|--------|--------|
| `⇧⌘R` (configurable) or click the notch | Panel expands out of the notch and takes the keyboard; the frontmost app stays active (no app switch) |
| Type a date in the title (“buy milk tomorrow at 2pm”, “zavolat mámě zítra ve 14:00”) | A blue suggestion chip appears; `Tab` or click applies it and strips the phrase from the title; on save it is applied automatically. English and Czech. |
| Type, `⌘↩` / `↩` / click ✓ | Saves to Apple Reminders; the panel shrinks to a wide notch pill, the ✓ flies in and ticks, then the notch returns to normal |
| `Esc`, click outside, hotkey again, ⓧ | Collapses without saving |
| “Reminders ▾” | Pick the target list (persists) |
| Calendar icon | Remind me in 1 hour / tomorrow / pick a date… |
| Location icon | Add a location note (appended to Notes as 📍 …) |
| Flag icon | Toggle flagged (orange) — stored as High priority, EventKit exposes no flag |
| `open quickreminder://show` (`hide`, `toggle`) | Same actions from Shortcuts, Raycast, scripts |

Menu bar icon → **Settings…** to change the hotkey (needs ⌘, ⌃ or ⌥) or the default list. The app asks for Reminders access on first launch (System Settings → Privacy & Security → Reminders if you need to re-enable it).

## Screenshots while developing

```bash
Scripts/shot.sh open            # notch region of the built-in display → build/shots/
Scripts/shot.sh --full desktop  # whole built-in display (QR_SHOT_DIR overrides the folder)
```

## Requirements

macOS 26 Tahoe, Apple silicon. Works on displays without a notch too (a virtual notch pill is drawn at the top-centre of the screen).
