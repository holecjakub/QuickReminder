# Testing

Three layers, from fastest/narrowest to slowest/widest.

## 1. Unit tests — `swift test`

State-machine and pure-logic coverage: `NotchMachineTests`, `NotchStateTests`,
`NotchShapeTests`, `NaturalDateParserTests`, `SuggestionDateFormatterTests`,
`HotkeyShortcutTests` (see `Tests/QuickReminderCoreTests/`). These run
headless, no app window, no Accessibility permission, and are what CI runs on
every push/PR via `swift test --parallel` (`.github/workflows/ci.yml`).

Run locally:

```
swift test
```

or `Scripts/test.sh`, a thin wrapper that runs `swift test` from the repo root and
passes flags through (`Scripts/test.sh --filter NaturalDateParserTests`):

```
Scripts/test.sh
```

This is the layer to extend when adding logic to the notch state machine, the
natural-language date parser, or anything else that does not need a live
window or real input events.

## 2. E2E smoke suite — `Scripts/e2e.sh`

Drives the actual built app on this Mac: real `osascript` keystrokes for the
hotkey/typing/Esc, a small CGEvent helper (`Scripts/click.swift`, compiled on
demand into `build/tools/click`) for notch clicks and hover moves, and
`screencapture` + Pillow pixel checks (`Scripts/e2e/pixels.py`) to assert on
what actually rendered — panel open/closed, the blue suggestion chip, the
hover swell, the save choreography, and so on.

```
Scripts/e2e.sh                # build, run every scenario, restore the app
Scripts/e2e.sh --no-build      # reuse the existing build/QuickReminder.app
Scripts/e2e.sh --only NAME     # run a single scenario
Scripts/e2e.sh --keep          # leave the test instance running afterwards
Scripts/e2e.sh --with-save     # also run save_choreography (creates a REAL
                                # reminder in your Reminders app — off by
                                # default, run deliberately)
```

Output is `PASS name` / `FAIL name (reason)` / `SKIP name (reason)` per
scenario plus a summary; the exit code is the failure count. Every step's
screenshot and a per-scenario log land under `build/e2e/<timestamp>/`, so a
`FAIL` can be diagnosed after the fact without rerunning.

Scenarios: `hotkey_open_close`, `type_suggestion_tab`, `czech_suggestion`,
`click_notch_opens`, `hover_swell`, `quick_crossing_no_swell`,
`click_outside_closes`, `margin_click_closes`, `reopen_during_close`, and
(only with `--with-save`) `save_choreography`.

**Requirements to run this at all:**
- macOS, with the terminal that launches it granted Accessibility access
  (`System Settings > Privacy & Security > Accessibility`) — `osascript`
  keystrokes need it. The script probes this up front and exits 2 with a
  hint if it's missing.
- The built-in display's exact geometry is baked into the coordinates (this
  machine: 1800×1169 pt, notch centred at x≈901, open panel at x 601–1201 /
  y 0–214). If `system_profiler SPDisplaysDataType` shows no built-in Retina
  display, the hover/click-on-notch scenarios (`click_notch_opens`,
  `hover_swell`, `quick_crossing_no_swell`) are reported `SKIP` rather than
  failing outright; the rest still run against the virtual notch pill.
- Pixel thresholds (a fully open panel measures ~459k dark px in the capture
  region; closed, even hover-swollen, measures ~35k–45k) were calibrated by
  hand against this machine's Retina (2×) backing scale factor — see
  `Scripts/e2e/pixels.py` and the `DARK_OPEN_MIN`/`DARK_CLOSED_MAX` constants
  in `Scripts/e2e/lib.sh` if you need to retune them for a different display.

**Timing that turned out to matter** (see inline comments in
`Scripts/e2e.sh` for the specifics):
- A click on the closed notch needs the pointer to sit there for a while
  (~0.8s) before the click, not just a quick move-then-click — the SwiftUI
  tap gesture on the notch silhouette can miss if it lands mid hover-swell
  animation. The suite retries the click once before failing on this.
- The app's hover dwell is 90ms (`NotchLayout.hoverDwell`): a crossing needs
  to be faster than that to test "no swell", so `quick_crossing_no_swell`
  chains two bare `click move` calls with no sleep between them rather than
  relying on wall-clock sleeps.
- Every "closed" assertion tolerates the hover-swollen pill too (dark pixel
  count stays well under the open threshold either way), since where the
  mouse happens to be sitting after a previous step isn't always predictable.

**What this cannot do in CI:** GitHub-hosted macOS runners have no physical
notch, no logged-in Aqua session with Accessibility granted for `osascript`,
and no guaranteed screen geometry — so this suite is local-only by design and
is not wired into `ci.yml`. A future XCUITest or snapshot-testing layer would
close that gap by driving the app's accessibility tree directly (works
headless/CI, survives layout coordinate changes, can assert on view
hierarchy/labels instead of raw pixels) rather than emulating a human with
global keystrokes and screenshots; it would be a better fit for exact-text
and VoiceOver assertions, while this suite stays useful for “does it
actually look and animate right on a real notch” checks that a
view-hierarchy-based test can't see.

## 3. Manual screenshot poking — `Scripts/shot.sh`

For ad-hoc visual checks while developing (not a test suite): captures a
region of the built-in display to `build/shots/<name>.png`. See the
`Scripts/e2e/pixels.py` module if you want to script an assertion against
one of these directly.

## E2E: what to know before running it

- The runner **kills any running QuickReminder** (including a notarized copy from
  /Applications) and drives a fresh instance of `build/QuickReminder.app` launched with
  `QR_CAPTURE_PARKED=1`; at the end it relaunches whichever bundle was running before.
- It sends **real keystrokes and clicks** system-wide. Nothing is typed unless the panel is
  verified open by two independent pixel checks (large dark region *and* the blue
  "Reminders ▾" header), and the run aborts if the test instance did not start. The suite
  assumes the default `⇧⌘R` hotkey and default list: the dev build shares `UserDefaults`
  with the installed app, so a changed hotkey makes the hotkey scenarios fail (safely).
- `--with-save` creates a real reminder titled "E2E test reminder" in your default list and
  does not delete it.
- Screenshots under `build/e2e/<timestamp>/` cover a 600 × 214 pt strip at the top centre of
  the built-in display and may contain whatever sits there (menu bar, tab titles). The
  folder is gitignored; clear it before attaching logs to a bug report. `screencapture`
  needs Screen Recording permission for your terminal.
- Coordinates are calibrated for a 14" MacBook Pro (1800 × 1169 pt, notch at x ≈ 901);
  other notched Macs need the constants in `Scripts/e2e/lib.sh` adjusted.
