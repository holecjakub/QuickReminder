# Changelog

All notable changes to QuickReminder. Format: [Keep a Changelog](https://keepachangelog.com), versions follow [SemVer](https://semver.org). Release notes on GitHub are generated from the matching section here.

## Unreleased

## 0.1.0

First public build.

- Quick-reminder panel that grows out of the MacBook notch (boring.notch-style silhouette, spring choreography, Reduce Motion fallback); virtual notch pill on displays without one.
- Layout and colours matched 1:1 to the iOS 26 quick-reminder overlay: list picker, title and notes, date / location / flag pill, save button.
- Natural-language dates in the title, English and Czech (“tomorrow at 2pm”, “zítra ve 14:00”, “v pátek”, “12. března”, “in 2 hours”, “za 30 minut”) with a suggestion chip, Tab/click to apply, auto-apply on save.
- “Saved” choreography: the panel collapses to a wide notch pill, the checkmark flies in and ticks, the notch returns.
- Global hotkey (⇧⌘R, configurable, Carbon, no Accessibility permission), click on the notch, menu-bar item, `quickreminder://show|hide|toggle` URL scheme (rate-limited, ignored during Secure Event Input).
- Saves to Apple Reminders via EventKit; inline error when access is missing.
- Signed with Developer ID, hardened runtime, notarized. Intentionally unsandboxed (see SPEC §5).
