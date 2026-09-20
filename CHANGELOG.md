# Changelog

All notable changes to QuickReminder. Format: [Keep a Changelog](https://keepachangelog.com), versions follow [SemVer](https://semver.org). Release notes on GitHub are generated from the matching section here.

## Unreleased

- The panel takes the selected reminder list's colour (header, ✓, chips, caret, saved badge).
- Hover feedback follows macOS HIG: a soft highlight behind controls instead of scaling; the date menu is a native popup from a plain button, so the pill row no longer shifts on hover.

- Pill icons (calendar, location, flag) are optically the same size: rendered through AppKit's symbol configuration instead of SwiftUI's symbol image, which drew the badge symbol much smaller.
- The panel respects the system text size (Accessibility → Display → Text size): fonts, controls and the panel height scale with it.
- Panel state machine extracted into a pure `NotchMachine` reducer with exhaustive sequence tests; unit tests moved to Swift Testing (`swift test`, SwiftPM `QuickReminderCore` target).

- Hovering the notch swells the closed silhouette with a small spring and taps the trackpad; click and hover now come from the always-on notch window instead of global mouse monitoring.
- E2E: local end-to-end smoke suite (`Scripts/e2e.sh`) drives the real built app with `osascript` keystrokes and a CGEvent click helper, asserting on screenshot pixels — hotkey/click/Esc open-close, EN/CZ suggestion chips, hover swell vs. quick crossing, outside/margin click to close, reopen-during-close, and a guarded save choreography check. See `docs/testing.md`.

## 0.1.0

First public build.

- Quick-reminder panel that grows out of the MacBook notch (boring.notch-style silhouette, spring choreography, Reduce Motion fallback); virtual notch pill on displays without one.
- Layout and colours matched 1:1 to the iOS 26 quick-reminder overlay: list picker, title and notes, date / location / flag pill, save button.
- Natural-language dates in the title, English and Czech (“tomorrow at 2pm”, “zítra ve 14:00”, “v pátek”, “12. března”, “in 2 hours”, “za 30 minut”) with a suggestion chip, Tab/click to apply, auto-apply on save.
- “Saved” choreography: the panel collapses to a wide notch pill, the checkmark flies in and ticks, the notch returns.
- Global hotkey (⇧⌘R, configurable, Carbon, no Accessibility permission), click on the notch, menu-bar item, `quickreminder://show|hide|toggle` URL scheme (rate-limited, ignored during Secure Event Input).
- Saves to Apple Reminders via EventKit; inline error when access is missing.
- Signed with Developer ID, hardened runtime, notarized. Intentionally unsandboxed (see SPEC §5).
