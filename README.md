# QuickReminder

A macOS 26 menu bar app that recreates the **iOS 26 “Quick Reminder” overlay** 1:1 — and, because we are on a Mac, the panel animates **out of the MacBook notch** (boring.notch / NotchNook style): the black notch grows into a wide panel, you type, hit `⌘↩`, the checkmark flies into the notch, and it collapses back.

> Not affiliated with, endorsed by or sponsored by Apple Inc. Apple, macOS, iOS, Xcode, SF Symbols and Reminders are trademarks of Apple Inc. QuickReminder is an independent, from-scratch implementation using only public Apple frameworks; it contains no Apple source code or assets and uses no private APIs. It reads and writes your reminders through the public EventKit framework.

Design reference: the iOS 26 quick-reminder overlay, measured metrics in `SPEC.md` §4 · Notch research: `reference/notch-research.md`

## Install

Download `QuickReminder-x.y.z.dmg` (or the `.zip`) from the [latest release](https://github.com/holecjakub/QuickReminder/releases/latest), drag the app to Applications and launch it. Builds are signed with a Developer ID and notarized by Apple, so Gatekeeper opens them without warnings. On first launch macOS asks for Reminders access.

## Build

`xcodebuild` / `xcrun` need the Xcode 27 license accepted (`sudo xcodebuild -license accept`). Until then the build script drives the toolchain's `swiftc` directly and assembles the `.app` bundle by hand — no Xcode needed:

```bash
./build.sh        # build  → build/QuickReminder.app
./build.sh run    # build, kill the running instance, launch
```

The app is signed with your “Apple Development” identity when one is in the keychain (so the Reminders permission survives rebuilds), otherwise ad-hoc — always with hardened runtime, intentionally **not** sandboxed (sandboxing breaks the EventKit connection on macOS 26.6, see `SPEC.md` §5). `xcodegen generate` keeps `QuickReminder.xcodeproj` in sync for when you want to open it in Xcode.

```bash
swift test         # Swift Testing suite (Tests/QuickReminderCoreTests)
Scripts/test.sh    # same, with a one-line pass/fail summary; passes extra args through, e.g. --filter
```

## Use

| Action | Result |
|--------|--------|
| Hover the notch | It swells slightly with a spring and the trackpad taps |
| Larger system text | Fonts, controls and the panel scale with Accessibility → Display → Text size |
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

## Release

Releases are tagged `vX.Y.Z` and published on GitHub with a notarized `.dmg` and `.zip`.

- **From this Mac:** `Scripts/release.sh 1.0.0` builds Release, signs with the Developer ID certificate in the keychain (timestamped, hardened runtime), packages, notarizes and staples both artifacts, tags, and creates the GitHub release with notes from `CHANGELOG.md`. `--dry-run` stops before tagging; `--pre` marks a pre-release. Notarization credentials come from `~/.config/quickreminder/notary.env` (written by `Scripts/setup-release-secrets.sh`).
- **From GitHub Actions:** pushing a `v*` tag runs `.github/workflows/release.yml`, which does the same on a `macos-26` runner using the repository secrets set by `Scripts/setup-release-secrets.sh`. `ci.yml` builds and runs the checks on every PR.

## License

MIT — see `LICENSE`.
