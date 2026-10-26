# Changelog

All notable changes to QuickReminder. Format: [Keep a Changelog](https://keepachangelog.com), versions follow [SemVer](https://semver.org). Release notes on GitHub are generated from the matching section here.

## Unreleased

## 0.5.0

- Raycast: opening QuickReminder from Raycast (or Spotlight, Finder, the Dock) opens the panel, whether the app is running or not; it used to do nothing while running. Launch at login stays silent. `Scripts/raycast/quick-reminder.sh` adds a “Quick Reminder” Raycast Script Command.
- The pill icons (date, location, flag) are smaller: 18 pt instead of 22 pt, in the same 38 pt hit targets.
- **Set Date in the notch.** New setting Settings → Set Date → Date picker style: *In notch* (default) or *Popover*. In notch, `⌘D`, Custom… or the date chip grow the black panel itself instead of opening a popover: the bottom bar gives way to the Set Date controls restyled for black (type field with live preview, six presets on `⌘1`…`⌘6`, day + typed time with 9/12/15/19 chips, Clear · Cancel · Set), and `⌘K` or the day button grows it further for a month grid (arrow keys move the day). ↩ / ⌘↩ set the date, also from the title or notes; ↩ in the time field just applies the time. Esc steps back: calendar first, then the section, then the panel. A click on the header, title or notes cancels like a click outside the popover. On short screens or at large text sizes the panel stops above the Dock and the controls scroll. Reduce Motion: a plain height change and fades.
- Set Date labels read as one format in every locale: day and time are composed instead of joined by the language's “at” (English UI with a Czech region read “24. 10. 2026 at 9:00” and “Sat 09:00” next to chips saying “9:00”). The preview reads “Saturday 24. 10. 9:00”, presets and Set “Sat 9:00”, “1. 11. 9:00”; calendar-menu details follow (“Nov 1 9:00 AM”).
- When two presets land on the same time (Tomorrow and This Weekend on a Friday) only one card is highlighted: the one you picked, otherwise the first.
- The Set button and the selected time chip / day stay readable on light list colours: their label turns dark when white would fall below 4.5:1 (orange, yellow, the default blue, purple).
- Dev: one Set Date model for both styles (`ScheduleDraft`); the panel height model covers the grown states and the screen clamp (`NotchLayout.openSize(notchBandHeight:schedule:maxHeight:)`, `ScheduleMetrics`) and the state machine a schedule event, all unit-tested. `Scripts/e2e.sh --picker-style popover|notch` (default `notch`, passed to the test instance in the argument domain); new In-notch scenarios `schedule_notch_expand`, `schedule_notch_return_sets`, `schedule_notch_click_cancels`, `schedule_notch_time_return`.

## 0.4.0

- **No more analog clock.** Remind Me Later… opened a graphical picker whose time had to be set by dragging clock hands. It is replaced by a Set Date popover (`⌘D`, Custom… in the calendar menu, or a click on the date chip): type a date (“zítra 14:00”, “fri 2pm”, “14”, “1430”, “+2h”), pick one of six presets (`⌘1`…`⌘6`, one click), or set the day and type the time (9/12/15/19 chips, a date-only calendar behind `⌘K`). Nothing changes until Set; Esc or a click outside cancels and leaves the panel open. The title's live date suggestion is prefilled.
- The calendar menu shows what each row resolves to (“This Weekend  so 9:00”) and gains This Evening, This Weekend and Next Week; rows keep their positions (labels adapt, e.g. “Tomorrow Evening” after 18:30).
- **Behaviour change:** a day-only date for today after 9:00 (“today”, “dnes”) now lands on the next :00 or :30 at least 15 minutes ahead instead of the next full hour. Tab, typing and presets share this rule (`ScheduleDefaults`).
- Dev: `QR_NOW=2026-10-23T10:00` pins the app's clock for screenshots and E2E; four new E2E scenarios (`date_menu_preset`, `schedule_popover_typed`, `schedule_popover_preset_shortcut`, `schedule_popover_esc`).
- Set Date review fixes: preset details and the Set button show the date from a week out (“Nov 1 at 9:00 AM”; Next Month on a Saturday read “Sun 9:00”, like Tomorrow); the title's date phrase is stripped whenever a date opened from it is set, also after editing the text, using the controls or a preset (it used to stay in the title); `15.11` / `24.12` / `1.12` are dates, not 15:11 or “Not a date”; VoiceOver announces the typed preview and names the calendar and time chips; closing the calendar with `⌘K` returns focus to the field; 12/24-hour changes apply without a relaunch; the invalid hint suggests an English example in English (“tomorrow 2pm”) and the placeholder fits the field.
- Esc while a popover (list picker, Set Date, location) is open now closes just the popover; it used to close the whole panel, because the non-activating panel stays the key window and received the Esc.

## 0.3.0

- Settings… now opens a window (it silently did nothing: the SwiftUI `Settings` scene has no responder in an accessory app driven by AppKit); the app is a plain `NSApplication` entry point and the settings form lives in its own window.
- New setting: Launch at login (`SMAppService`, with the System Settings approval hint).
- Quit in the status-bar menu was greyed out (its target could not perform `terminate:`); fixed.

## 0.2.0

- The open panel is exactly as tall as its content: the ✓ button now sits 20 pt from the bottom edge, the same as from the right edge (the stack used to overflow an undersized 214 pt frame and was centred-and-clipped by 13 pt at both ends). `NotchLayout.contentHeight` sums the vertical rhythm and is pinned by a unit test.
- `NOTICE.md`: trademark notice and acknowledgements of the notch projects whose published geometry the silhouette follows (DynamicNotchKit, NotchDrop, boring.notch); README and SPEC say “inspired by” the iOS overlay instead of “recreates 1:1”; `reference/` ignores images so no third-party screenshot can be committed again.
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
