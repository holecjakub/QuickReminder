#!/bin/bash
# QuickReminder local end-to-end smoke suite.
#
# Drives the real, built app on this machine with osascript keystrokes and a
# small CGEvent click helper, and asserts on screenshot pixels. See
# docs/testing.md for what this can and cannot cover and how the pixel
# thresholds below were chosen.
#
# Usage:
#   Scripts/e2e.sh                 build, run every scenario, restore the app
#   Scripts/e2e.sh --no-build       reuse the existing build/QuickReminder.app
#   Scripts/e2e.sh --keep           leave the E2E test instance running (skip
#                                    the final pkill + relaunch of the app)
#   Scripts/e2e.sh --only NAME      run a single scenario by name
#   Scripts/e2e.sh --with-save      also run save_choreography (creates a
#                                    real reminder in the user's Reminders --
#                                    off by default)
#   Scripts/e2e.sh --no-catcher      skip the disposable TextEdit window that
#                                    catches stray clicks / keystrokes (below)
#   Scripts/e2e.sh --picker-style popover|notch
#                                   Set Date style for the test instance
#                                    (argument domain, nothing persisted);
#                                    default: notch (Settings are ignored)
#
# Prints "PASS name" / "FAIL name (reason)" / "SKIP name (reason)" per
# scenario and a summary line. Exit code = number of failures.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="$ROOT/Scripts/e2e"
CLICK="$ROOT/build/tools/click"
APP_BUNDLE="$ROOT/build/QuickReminder.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/QuickReminder"

NO_BUILD=0
KEEP=0
ONLY=""
WITH_SAVE=0
PICKER_STYLE=""
CATCHER=1
CATCHER_DOC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) NO_BUILD=1; shift ;;
        --keep) KEEP=1; shift ;;
        --only) ONLY="$2"; shift 2 ;;
        --with-save) WITH_SAVE=1; shift ;;
        --picker-style) PICKER_STYLE="$2"; shift 2 ;;
        --no-catcher) CATCHER=0; shift ;;
        -h|--help)
            sed -n '2,24p' "$0"
            exit 0
            ;;
        *)
            echo "error: unknown option $1" >&2
            exit 1
            ;;
    esac
done

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$ROOT/build/e2e/$TIMESTAMP"
SHOT_DIR="$RUN_DIR"
LOG_DIR="$RUN_DIR/logs"
# Retention: keep the five most recent run directories (each is ~10 MB of screenshots).
# Path-safe (the repo path contains a space) and symlink-safe: only real directories
# directly under build/e2e are ever removed.
while IFS= read -r d; do
    [[ "$d" == "$ROOT/build/e2e/"* && -d "${d%/}" && ! -L "${d%/}" ]] || continue
    rm -rf -- "$d"
done < <(ls -1dt "$ROOT"/build/e2e/*/ 2>/dev/null | tail -n +6)
mkdir -p "$SHOT_DIR" "$LOG_DIR"

# shellcheck source=Scripts/e2e/lib.sh
source "$LIB_DIR/lib.sh"

FAILURES=0
HAS_NOTCH_DISPLAY=1
CLEANED_UP=0
PREVIOUS_BUNDLE=""

# ---------------------------------------------------------------- preconditions

precondition_display() {
    init_geometry
    if [[ "$HAS_NOTCH_DISPLAY" -ne 1 ]]; then
        echo "note: no notched built-in display -- hover/notch scenarios will SKIP" >&2
    else
        echo "Display: notch at x=$NOTCH_X, height ${NOTCH_H}pt; panel region $PANEL_REGION" >&2
    fi
    python3 -c 'import PIL' 2>/dev/null || { echo "error: Pillow is required (pip3 install Pillow)" >&2; exit 2; }
}

precondition_app() {
    # Skip the (~5 s, non-incremental) rebuild when the bundle is newer than every source.
    if [[ "$NO_BUILD" -eq 0 && -x "$APP_BIN" ]] \
        && [[ -z "$(find "$ROOT/Sources" "$ROOT/Resources" "$ROOT/build.sh" -newer "$APP_BIN" -print -quit 2>/dev/null)" ]]; then
        echo "Build is up to date, skipping ./build.sh." >&2
        NO_BUILD=1
    fi
    if [[ "$NO_BUILD" -eq 0 ]]; then
        echo "Building QuickReminder.app..." >&2
        (cd "$ROOT" && ./build.sh) >"$LOG_DIR/build.log" 2>&1 || {
            echo "error: build failed, see $LOG_DIR/build.log" >&2
            exit 2
        }
    fi
    if [[ ! -x "$APP_BIN" ]]; then
        echo "error: app binary not found at $APP_BIN (run without --no-build first)" >&2
        exit 2
    fi
}

precondition_osascript() {
    if ! osascript -e 'tell application "System Events" to keystroke ""' >/dev/null 2>&1; then
        cat >&2 <<'EOF'
error: osascript cannot send keystrokes via System Events.
Grant Terminal (or whatever runs this script) Accessibility access:
  System Settings > Privacy & Security > Accessibility > enable your terminal app.
EOF
        exit 2
    fi
}

precondition_click_tool() {
    mkdir -p "$ROOT/build/tools"
    if [[ ! -x "$CLICK" || "$ROOT/Scripts/click.swift" -nt "$CLICK" ]]; then
        echo "Compiling Scripts/click.swift..." >&2
        local swiftc_bin="swiftc"
        local xcode_swiftc="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        local sdk="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        if [[ -x "$xcode_swiftc" && -d "$sdk" ]]; then
            "$xcode_swiftc" -sdk "$sdk" "$ROOT/Scripts/click.swift" -o "$CLICK"
        elif command -v swiftc >/dev/null 2>&1; then
            "$swiftc_bin" "$ROOT/Scripts/click.swift" -o "$CLICK"
        else
            echo "error: no swiftc found to compile Scripts/click.swift" >&2
            exit 2
        fi
    fi
}

# ---------------------------------------------------------------- app lifecycle

launch_test_instance() {
    # Remember which bundle was running so cleanup relaunches that one, not necessarily build/.
    local running; running=$(ps -o comm= -p "$(pgrep -x QuickReminder | head -1)" 2>/dev/null || true)
    if [[ "$running" == */Contents/MacOS/QuickReminder ]]; then
        PREVIOUS_BUNDLE="${running%/Contents/MacOS/QuickReminder}"
    fi
    pkill -x QuickReminder 2>/dev/null || true
    sleep 0.4
    # The dev build shares UserDefaults with the installed app; force the default ⇧⌘R hotkey
    # through the argument domain (a non-Data value makes HotkeyManager fall back to .default).
    # Nothing is persisted by this: the argument domain lives in memory only. (Recording a new
    # hotkey in the *test* instance's Settings would write to the shared persistent domain.)
    # QR_NOW (if set in the caller's environment) is inherited: it pins the app's clock so date
    # labels in screenshots are deterministic, e.g. QR_NOW=2026-10-23T10:00 Scripts/e2e.sh.
    # The Set Date style goes the same way (argument domain), always: a plain run must not pick up
    # whatever the user chose in Settings (the notch-only scenarios would fail against a popover).
    QR_CAPTURE_PARKED=1 "$APP_BIN" -hotkey e2e-default -datePickerStyle "${PICKER_STYLE:-notch}" >"$LOG_DIR/app.log" 2>&1 &
    disown
    sleep 1.2
    if ! pgrep -x QuickReminder >/dev/null; then
        echo "error: the test instance did not start (see $LOG_DIR/app.log); aborting before any keystroke is sent" >&2
        exit 2
    fi
}

# Key / click catcher: a disposable, never-saved TextEdit document covering the area under and
# around the panel, made frontmost before the run. Clicks the suite sends outside the panel (which
# the open panel now passes through to whatever is below) and any keystroke that misses the panel
# land in it instead of the user's apps; whatever it collected is reported as a leak at the end.
setup_key_catcher() {
    [[ "$CATCHER" -eq 1 ]] || return 0
    CATCHER_DOC=$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "TextEdit"
    activate
    set catcherDoc to make new document with properties {text:""}
    set bounds of front window to {250, 60, 1100, 900}
    return name of catcherDoc
end tell
APPLESCRIPT
)
    if [[ -z "$CATCHER_DOC" ]]; then
        echo "error: could not open the TextEdit key catcher (use --no-catcher to run without it)" >&2
        exit 2
    fi
    sleep 0.6
    echo "Key catcher: TextEdit document \"$CATCHER_DOC\" (closed unsaved at the end)" >&2
}

# Prints the number of characters that leaked into the catcher, then closes it without saving.
teardown_key_catcher() {
    [[ -n "$CATCHER_DOC" ]] || return 0
    local leaked
    leaked=$(osascript -e "tell application \"TextEdit\" to get text of document \"$CATCHER_DOC\"" 2>/dev/null || true)
    osascript -e "tell application \"TextEdit\" to close document \"$CATCHER_DOC\" saving no" >/dev/null 2>&1 || true
    CATCHER_DOC=""
    if [[ -n "${leaked//[[:space:]]/}" ]]; then
        echo "LEAK: ${#leaked} characters reached the key catcher instead of the panel: $(printf '%q' "$leaked")"
        return 1
    fi
    echo "Key catcher: nothing leaked"
}

cleanup() {
    if [[ "$CLEANED_UP" -eq 1 ]]; then return; fi
    CLEANED_UP=1
    teardown_key_catcher || true
    if [[ "$KEEP" -eq 1 ]]; then
        echo "note: --keep set, leaving the E2E test instance running" >&2
        return
    fi
    pkill -x QuickReminder 2>/dev/null || true
    sleep 0.3
    local target="${PREVIOUS_BUNDLE:-$APP_BUNDLE}"
    [[ -d "$target" ]] || target="$APP_BUNDLE"
    # launchd occasionally refuses a spawn immediately after pkill; retry once.
    if ! open "$target" 2>/dev/null; then
        sleep 0.5
        open "$target" 2>/dev/null || echo "warning: failed to relaunch $target -- launch it manually" >&2
    fi
    true
}
trap cleanup EXIT

# ---------------------------------------------------------------- scenario helpers

reset_to_closed() {
    # Esc goes to the frontmost app when the panel is closed, so only send it when a quick
    # dark-region check says the panel (or its collapse) is on screen.
    local png; png=$(shot "reset_probe")
    local n; n=$(dark_count "$png" 0 0 "$PANEL_W" "$PANEL_H" 20)
    if [[ "$n" -ge "$DARK_CLOSED_MAX" ]]; then
        press_escape
    fi
    move_to 500 500
    sleep 0.4
}

fail() {
    echo "$1"
    return 1
}

# Grey/blue save button (not wallpaper): the ✓ circle spans y 173-221 (39 + 134 + 48) and
# x 532-580 of the 601,0-anchored panel region; sample its left-centre 40x40.
assert_save_button_present() {
    local png="$1"
    local n; n=$(dark_count "$png" 530 177 40 40 150)
    if [[ "$n" -lt 3000 ]]; then
        fail "save button region looks like wallpaper (n=$n)"
        return 1
    fi
    # The ✓ itself, not just something dark (the black Set Date section would pass the check above):
    # the white checkmark inside the circle. Wider box so a narrower panel (smaller text) still hits.
    local tick; tick=$(bright_count "$png" 500 165 90 65 200)
    if [[ "$tick" -lt 60 ]]; then
        fail "no white checkmark in the save button region (bright=$tick)"
        return 1
    fi
    log_step "save button present: n=$n tick=$tick"
}

# ---------------------------------------------------------------- scenarios

hotkey_open_close() {
    hotkey_toggle
    sleep 0.8
    assert_open "hotkey_open_close_open" || return 1
    press_escape
    sleep 0.6
    assert_closed "hotkey_open_close_closed" || return 1
}

type_suggestion_tab() {
    hotkey_toggle
    sleep 0.8
    assert_open "type_suggestion_tab_open" || return 1
    type_text "Buy milk tomorrow at 2pm"
    sleep 0.5
    local png_before; png_before=$(shot "type_suggestion_tab_typed")
    local chip; chip=$(saturated_count "$png_before" 20 130 260 40)
    if [[ "$chip" -lt 200 ]]; then
        fail "expected a suggestion chip (saturated=$chip)"
        return 1
    fi
    log_step "chip present: saturated=$chip"
    local title_before; title_before=$(bright_count "$png_before" 60 75 550 40 200)
    press_tab
    sleep 0.4
    local png_after; png_after=$(shot "type_suggestion_tab_tabbed")
    local title_after; title_after=$(bright_count "$png_after" 60 75 550 40 200)
    log_step "title bright px: before=$title_before after=$title_after"
    # Applying the suggestion shortens the title text -- fewer bright
    # (white text) pixels in the title row. Coarse: at least a 10% drop.
    if [[ "$title_after" -ge $(( title_before * 90 / 100 )) ]]; then
        fail "expected title to shrink after Tab (before=$title_before after=$title_after)"
        return 1
    fi
    press_escape
    sleep 0.6
    assert_closed "type_suggestion_tab_closed" || return 1
}

czech_suggestion() {
    hotkey_toggle
    sleep 0.8
    assert_open "czech_suggestion_open" || return 1
    sleep 0.3   # focus retries run at +0.12 s / +0.30 s after open
    type_text "Zavolat mámě zítra ve 14:00"
    sleep 0.5
    local png; png=$(shot "czech_suggestion_typed")
    local chip; chip=$(saturated_count "$png" 20 130 260 40)
    if [[ "$chip" -lt 200 ]]; then
        fail "expected a suggestion chip for Czech input (saturated=$chip)"
        return 1
    fi
    log_step "chip present: saturated=$chip"
    press_escape
    sleep 0.6
    assert_closed "czech_suggestion_closed" || return 1
}

click_notch_opens() {
    if [[ "$HAS_NOTCH_DISPLAY" -eq 0 ]]; then
        fail "SKIP:no built-in notch display"
        return 2
    fi
    move_to "$NOTCH_X" 15
    sleep 0.8
    click_at "$NOTCH_X" 15
    sleep 0.6
    # No retry on purpose: the click is handled by NotchWindow.sendEvent on mouse-down
    # (the earlier SwiftUI gesture could miss mid hover-swell); a miss here is a regression.
    assert_open "click_notch_opens_open" || return 1
    press_escape
    sleep 0.6
    move_to 500 500
    assert_closed "click_notch_opens_closed" || return 1
}

hover_swell() {
    if [[ "$HAS_NOTCH_DISPLAY" -eq 0 ]]; then
        fail "SKIP:no built-in notch display"
        return 2
    fi
    move_to 500 500
    sleep 0.3
    local baseline; baseline=$(measure_width "hover_swell_baseline")
    move_to "$(( NOTCH_X - 10 ))" 10
    move_to "$NOTCH_X" 15
    sleep 0.5
    local hovered; hovered=$(measure_width "hover_swell_hovered")
    log_step "width baseline=$baseline hovered=$hovered"
    local delta
    delta=$(python3 -c "print(1 if ($hovered - $baseline) >= 15 else 0)")
    if [[ "$delta" -ne 1 ]]; then
        fail "expected hover swell of >=15pt (baseline=$baseline hovered=$hovered)"
        return 1
    fi
    move_to 500 500
    sleep 0.6
    local settled; settled=$(measure_width "hover_swell_settled")
    log_step "width settled=$settled"
    local back
    back=$(python3 -c "print(1 if abs($settled - $baseline) <= 3 else 0)")
    if [[ "$back" -ne 1 ]]; then
        fail "expected width to return to baseline within 0.7s (baseline=$baseline settled=$settled)"
        return 1
    fi
}

quick_crossing_no_swell() {
    if [[ "$HAS_NOTCH_DISPLAY" -eq 0 ]]; then
        fail "SKIP:no built-in notch display"
        return 2
    fi
    move_to 500 500
    sleep 0.3
    local baseline; baseline=$(measure_width "quick_crossing_baseline")
    # Two moves back-to-back with no intervening sleep: the HID enter/leave
    # gap lands well under the app's 90ms hover dwell, so no swell should
    # ever be armed.
    move_to "$NOTCH_X" 15
    move_to 500 500
    sleep 0.3
    local after; after=$(measure_width "quick_crossing_after")
    log_step "width baseline=$baseline after=$after"
    local grew
    grew=$(python3 -c "print(1 if ($after - $baseline) > 5 else 0)")
    if [[ "$grew" -eq 1 ]]; then
        fail "expected no swell from a quick crossing (baseline=$baseline after=$after)"
        return 1
    fi
}

click_outside_closes() {
    hotkey_toggle
    sleep 0.8
    assert_open "click_outside_closes_open" || return 1
    click_at 300 700
    sleep 0.6
    assert_closed "click_outside_closes_closed" || return 1
}

margin_click_closes() {
    hotkey_toggle
    sleep 0.8
    assert_open "margin_click_closes_open" || return 1
    click_at "$(( PANEL_LEFT + 9 ))" 120
    sleep 0.6
    assert_closed "margin_click_closes_closed" || return 1
}

reopen_during_close() {
    hotkey_toggle
    sleep 0.8
    assert_open "reopen_during_close_open1" || return 1
    press_escape
    sleep 0.15
    hotkey_toggle
    sleep 0.8
    local png; png=$(shot "reopen_during_close_open2")
    local n; n=$(dark_count "$png" 0 0 "$PANEL_W" "$PANEL_H" 20)
    if [[ "$n" -lt "$DARK_OPEN_MIN" ]]; then
        fail "expected panel open again after interrupting the close (dark=$n)"
        return 1
    fi
    assert_save_button_present "$png" || return 1
    press_escape
    sleep 0.6
    assert_closed "reopen_during_close_closed" || return 1
}

save_choreography() {
    hotkey_toggle
    sleep 0.8
    assert_open "save_choreography_open" || return 1
    type_text "E2E test reminder"
    sleep 0.3
    press_cmd_return
    sleep 0.5
    local png; png=$(shot "save_choreography_pill")
    local top; top=$(silhouette_width "$png" 20)
    local mid; mid=$(silhouette_width "$png" 100)
    log_step "widths top(y=20)=$top mid(y=100)=$mid"
    if [[ "$(python3 -c "print(1 if $top == 0 else 0)")" -eq 1 ]]; then
        fail "expected a wide low pill right after save (top width=$top)"
        return 1
    fi
    if [[ "$(python3 -c "print(1 if $mid == 0 else 0)")" -eq 0 ]]; then
        fail "expected the saved pill to stay low, not a tall panel (mid width=$mid)"
        return 1
    fi
    sleep 1.3
    assert_closed "save_choreography_closed" || return 1
}

# The date chip sits in the same slot as the suggestion chip and takes the list colour.
assert_date_chip() {
    local label="$1"
    local png; png=$(shot "$label")
    local chip; chip=$(saturated_count "$png" 20 130 260 40)
    if [[ "$chip" -lt 200 ]]; then
        fail "expected an accent date chip (saturated=$chip) at $label"
        return 1
    fi
    log_step "date chip present: saturated=$chip"
}

# Calendar menu -> "This Weekend" by keyboard. Rows never move (labels adapt instead), so the
# sixth item is always the weekend preset: None, Mark as Urgent, In 1 Hour, Evening, Tomorrow,
# Weekend.
date_menu_preset() {
    # The native menu is the popover style's entry point; in notch the button opens Set Date.
    if [[ "${PICKER_STYLE:-notch}" != "popover" ]]; then
        echo "SKIP:the calendar menu exists only in the popover style"
        return 2
    fi
    hotkey_toggle
    sleep 0.8
    assert_open "date_menu_preset_open" || return 1
    # Calendar icon: 20 pt inset + 19 pt fillet + 11 pt pill padding + half a 38 pt hit area;
    # bottom bar centre 20 + 24 pt above the panel's bottom edge.
    click_at "$(( PANEL_LEFT + 69 ))" 197
    sleep 0.6
    shot "date_menu_preset_menu" "$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),520" >/dev/null
    for _ in 1 2 3 4 5 6; do press_down; sleep 0.08; done
    press_return
    sleep 0.6
    assert_date_chip "date_menu_preset_chip" || return 1
    press_escape
    sleep 0.6
    assert_closed "date_menu_preset_closed" || return 1
}

# ⌘D -> type a Czech phrase -> Return sets the date with no pointer use.
schedule_popover_typed() {
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_popover_typed_open" || return 1
    sleep 0.3
    press_cmd d
    sleep 0.7
    type_text "zítra 14:00"
    sleep 0.4
    shot "schedule_popover_typed_popover" "$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),720" >/dev/null
    press_return
    sleep 0.6
    assert_open "schedule_popover_typed_back" || return 1
    assert_date_chip "schedule_popover_typed_chip" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_popover_typed_closed" || return 1
}

# ⌘D -> ⌘3 commits the Tomorrow preset in one keystroke.
schedule_popover_preset_shortcut() {
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_popover_preset_shortcut_open" || return 1
    sleep 0.3
    press_cmd d
    sleep 0.7
    press_cmd 3
    sleep 0.6
    assert_date_chip "schedule_popover_preset_shortcut_chip" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_popover_preset_shortcut_closed" || return 1
}

# Esc in the popover closes only the popover; the second Esc closes the panel.
schedule_popover_esc() {
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_popover_esc_open" || return 1
    sleep 0.3
    press_cmd d
    sleep 0.7
    shot "schedule_popover_esc_popover" "$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),720" >/dev/null
    press_escape
    sleep 0.6
    assert_open "schedule_popover_esc_still_open" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_popover_esc_closed" || return 1
}

# In-notch Set Date: ⌘D grows the black panel itself, ⌘K grows it further for the month grid,
# Esc settles it back to the normal open height (panel stays open), a second Esc closes.
# Growth is measured as the gain in dark pixels in bands across the panel's inner 500 pt (inside
# the panel at any text size) below its normal bottom edge, relative to the plain open panel.
SCHEDULE_REGION_H=800   # the calendar blob + overshoot is ~775 pt at 100 %
schedule_band_dark() {
    # schedule_band_dark <png> <y> -- dark px in a 500 x 80 pt band centred in the capture.
    dark_count "$1" $(( (PANEL_W + 100) / 2 - 250 )) "$2" 500 80 20
}

schedule_notch_expand() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    # Bands (points from the top): y 300 lies below the ~240 pt plain panel and inside the ~520 pt
    # schedule blob; y 540 only inside the ~750 pt calendar blob (Set Date sits below the bar).
    local area=$(( 500 * 80 * 4 ))   # at 2x
    local gain=$(( area * 2 / 5 ))   # the blob must darken at least 40 % of the band
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_expand_open" || return 1
    local png; png=$(shot "schedule_notch_expand_before" "$region")
    local before; before=$(schedule_band_dark "$png" 300)
    local before_cal; before_cal=$(schedule_band_dark "$png" 540)
    log_step "bands before: controls=$before calendar=$before_cal (of $area)"
    if [[ "$before" -gt $(( area - gain )) || "$before_cal" -gt $(( area - gain )) ]]; then
        echo "SKIP:the desktop below the panel is too dark to measure the growth"
        return 2
    fi
    sleep 0.3
    press_cmd d
    # Mid-morph frame for eyeballing the spring (timing varies with osascript latency; no assertion).
    sleep 0.05
    shot "schedule_notch_expand_morph" "$region" >/dev/null
    sleep 0.75
    png=$(shot "schedule_notch_expand_controls" "$region")
    local grown; grown=$(schedule_band_dark "$png" 300)
    local grown_cal; grown_cal=$(schedule_band_dark "$png" 540)
    log_step "after ⌘D: controls=$grown calendar=$grown_cal"
    [[ "$grown" -ge $(( before + gain )) ]] || { fail "expected ⌘D to grow the blob (dark=$grown, before=$before)"; return 1; }
    [[ "$grown_cal" -lt $(( before_cal + gain )) ]] || { fail "the blob grew to calendar height without ⌘K (dark=$grown_cal)"; return 1; }
    assert_open "schedule_notch_expand_controls_open" || return 1
    # The plain panel stays as it is: the bottom bar with ✓ is still there above the section.
    assert_save_button_present "$SHOT_DIR/schedule_notch_expand_controls_open.png" || return 1
    press_cmd k
    sleep 0.8
    png=$(shot "schedule_notch_expand_calendar" "$region")
    local cal; cal=$(schedule_band_dark "$png" 540)
    log_step "after ⌘K: calendar=$cal"
    [[ "$cal" -ge $(( before_cal + gain )) ]] || { fail "expected ⌘K to grow the blob further (dark=$cal, before=$before_cal)"; return 1; }
    press_cmd k
    sleep 0.8
    png=$(shot "schedule_notch_expand_calendar_closed" "$region")
    cal=$(schedule_band_dark "$png" 540)
    log_step "after second ⌘K: calendar=$cal"
    [[ "$cal" -lt $(( before_cal + gain )) ]] || { fail "expected the second ⌘K to shrink the blob (dark=$cal)"; return 1; }
    # Esc steps back one level: with the calendar open, the first Esc closes only the calendar.
    press_cmd k
    sleep 0.8
    press_escape
    sleep 0.9
    png=$(shot "schedule_notch_expand_esc_calendar" "$region")
    cal=$(schedule_band_dark "$png" 540)
    grown=$(schedule_band_dark "$png" 300)
    log_step "after Esc in the calendar: calendar=$cal controls=$grown"
    [[ "$cal" -lt $(( before_cal + gain )) ]] || { fail "expected Esc to close the calendar first (dark=$cal)"; return 1; }
    [[ "$grown" -ge $(( before + gain )) ]] || { fail "expected the controls to stay after the first Esc (dark=$grown)"; return 1; }
    press_escape
    sleep 0.9
    png=$(shot "schedule_notch_expand_back" "$region")
    local back; back=$(schedule_band_dark "$png" 300)
    log_step "after Esc: controls=$back"
    [[ "$back" -lt $(( before + gain / 4 )) ]] || { fail "expected Esc to settle the blob back (dark=$back, before=$before)"; return 1; }
    assert_open "schedule_notch_expand_still_open" || return 1
    # The keyboard is back in the title: typed text shows up white where the grey placeholder was.
    # (Nothing is saved: the next Esc discards the draft.)
    type_text "ok"
    sleep 0.4
    png=$(shot "schedule_notch_expand_title_focus")
    local typed; typed=$(bright_count "$png" 60 80 240 32 200)
    log_step "typed into the title after Esc: bright=$typed"
    [[ "$typed" -ge 40 ]] || { fail "expected the title to have the keyboard after Esc (bright=$typed)"; return 1; }
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_expand_closed" || return 1
}

# In-notch: ⌘↩ (and ↩ in the title / notes) is Set while the section is open — the blob settles
# back with the accent date chip and the panel stays open. The title is left empty on purpose:
# even a broken routing could not save a reminder then (it would just leave the section open).
# Shift-Tab ×2 moves the keyboard from the type field back towards the text rows first; when it
# lands in the notes or title, the ↩ exercises their routing, otherwise the field's own ↩.
schedule_notch_return_sets() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local area=$(( 500 * 80 * 4 )) gain=$(( 500 * 80 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_return_open" || return 1
    local png; png=$(shot "schedule_notch_return_before" "$region")
    local before; before=$(schedule_band_dark "$png" 300)
    sleep 0.3
    press_cmd d
    sleep 0.8
    press_cmd_return
    sleep 0.9
    png=$(shot "schedule_notch_return_cmd" "$region")
    local band; band=$(schedule_band_dark "$png" 300)
    log_step "after ⌘D ⌘↩: band=$band (before $before)"
    [[ "$band" -lt $(( before + gain / 4 )) ]] || { fail "expected ⌘↩ to Set and settle the blob (dark=$band)"; return 1; }
    assert_open "schedule_notch_return_cmd_open" || return 1
    assert_date_chip "schedule_notch_return_cmd_chip" || return 1
    # Again from a text row. Shift-Tab walks back from the type field; a typed "n" must visibly land
    # in the NOTES row (white text there) before ↩ is pressed, so the ↩ really is the text row's.
    # The title stays empty: even a broken routing could not save. If the letter lands in the title
    # it is deleted and the step SKIPs; anywhere else (the field) it is deleted and we try again.
    press_cmd d
    sleep 0.8
    local reached="" tries
    for tries in 1 2 3; do
        osascript -e 'tell application "System Events" to key code 48 using {shift down}'
        sleep 0.25
        type_text "n"
        sleep 0.3
        png=$(shot "schedule_notch_return_probe_$tries")
        local in_title in_notes
        in_title=$(bright_count "$png" 60 $(( NOTCH_H + 50 )) 300 22 200)
        in_notes=$(bright_count "$png" 60 $(( NOTCH_H + 76 )) 300 22 200)
        log_step "shift-tab #$tries: title=$in_title notes=$in_notes"
        if [[ "$in_title" -ge 30 && "$in_title" -gt "$in_notes" ]]; then
            osascript -e 'tell application "System Events" to key code 51'   # delete the "n"
            echo "SKIP:Shift-Tab reached the title, not the notes; not pressing ↩ with a non-empty title"
            return 2
        fi
        if [[ "$in_notes" -ge 30 ]]; then reached=notes; break; fi
        osascript -e 'tell application "System Events" to key code 51'
        sleep 0.2
    done
    if [[ -z "$reached" ]]; then
        echo "SKIP:Shift-Tab did not reach the notes row; the text-row ↩ is covered by TextRowSubmitTests"
        return 2
    fi
    press_return
    sleep 0.9
    png=$(shot "schedule_notch_return_text_row" "$region")
    band=$(schedule_band_dark "$png" 300)
    log_step "after ↩ in the notes: band=$band"
    [[ "$band" -lt $(( before + gain / 4 )) ]] || { fail "expected ↩ in the notes to Set (dark=$band)"; return 1; }
    assert_open "schedule_notch_return_text_row_open" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_return_closed" || return 1
}

# In-notch: a click inside the section keeps it; a click on the title row (inside the panel,
# above the bottom bar) cancels scheduling — no date written — and the panel stays open.
schedule_notch_click_cancels() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local gain=$(( 500 * 80 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_click_open" || return 1
    local png; png=$(shot "schedule_notch_click_before" "$region")
    local before; before=$(schedule_band_dark "$png" 300)
    sleep 0.3
    press_cmd d
    sleep 0.8
    # The section's type field (first row below the bottom bar; a click just focuses it), centred.
    click_at "$NOTCH_X" "$(( NOTCH_H + 205 ))"
    sleep 0.6
    png=$(shot "schedule_notch_click_inside" "$region")
    local band; band=$(schedule_band_dark "$png" 300)
    log_step "after a click inside the section: band=$band"
    [[ "$band" -ge $(( before + gain )) ]] || { fail "a click inside the section closed it (dark=$band)"; return 1; }
    # The title row ("New Reminder"), inside the panel above the section.
    click_at "$(( PANEL_LEFT + 200 ))" "$(( NOTCH_H + 62 ))"
    sleep 0.9
    png=$(shot "schedule_notch_click_title" "$region")
    band=$(schedule_band_dark "$png" 300)
    log_step "after a click on the title: band=$band"
    [[ "$band" -lt $(( before + gain / 4 )) ]] || { fail "expected a click on the title to cancel scheduling (dark=$band)"; return 1; }
    assert_open "schedule_notch_click_still_open" || return 1
    png=$(shot "schedule_notch_click_no_chip")
    local chip; chip=$(saturated_count "$png" 20 130 260 40)
    log_step "chip slot after cancel: saturated=$chip"
    [[ "$chip" -lt 200 ]] || { fail "cancel wrote a date (saturated=$chip)"; return 1; }
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_click_closed" || return 1
}

# In-notch: ↩ in the time field applies the typed time and keeps the section open (only the
# type field, the title / notes and ⌘↩ mean Set). Tab moves from the type field to the time field.
schedule_notch_time_return() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local gain=$(( 500 * 80 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_time_open" || return 1
    local png; png=$(shot "schedule_notch_time_before" "$region")
    local before; before=$(schedule_band_dark "$png" 300)
    sleep 0.3
    press_cmd d
    sleep 0.8
    press_tab
    sleep 0.3
    type_text "15"
    sleep 0.2
    press_return
    sleep 0.8
    png=$(shot "schedule_notch_time_applied" "$region")
    local band; band=$(schedule_band_dark "$png" 300)
    log_step "after ⇥ 15 ↩ in the time field: band=$band"
    [[ "$band" -ge $(( before + gain )) ]] || { fail "↩ in the time field closed the section (dark=$band)"; return 1; }
    press_cmd_return
    sleep 0.9
    assert_open "schedule_notch_time_set_open" || return 1
    assert_date_chip "schedule_notch_time_chip" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_time_closed" || return 1
}

# In-notch: the calendar button in the bottom bar toggles Set Date below the bar — the bar (and ✓)
# stays visible while it is open, a second click closes it without writing a date.
schedule_notch_pill_toggles() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local gain=$(( 500 * 80 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_pill_open" || return 1
    local png; png=$(shot "schedule_notch_pill_before" "$region")
    local before; before=$(schedule_band_dark "$png" 300)
    # Calendar icon, same spot as date_menu_preset uses in the popover style.
    click_at "$(( PANEL_LEFT + 69 ))" 197
    sleep 0.8
    png=$(shot "schedule_notch_pill_opened" "$region")
    local band; band=$(schedule_band_dark "$png" 300)
    log_step "after the calendar button: band=$band"
    [[ "$band" -ge $(( before + gain )) ]] || { fail "expected the calendar button to open Set Date below the bar (dark=$band)"; return 1; }
    png=$(shot "schedule_notch_pill_bar")
    assert_save_button_present "$png" || return 1
    click_at "$(( PANEL_LEFT + 69 ))" 197
    sleep 0.9
    png=$(shot "schedule_notch_pill_closed_again" "$region")
    band=$(schedule_band_dark "$png" 300)
    log_step "after the second click: band=$band"
    [[ "$band" -lt $(( before + gain / 4 )) ]] || { fail "expected a second click to close Set Date (dark=$band)"; return 1; }
    assert_open "schedule_notch_pill_still_open" || return 1
    png=$(shot "schedule_notch_pill_no_chip")
    local chip; chip=$(saturated_count "$png" 20 130 260 40)
    [[ "$chip" -lt 200 ]] || { fail "closing with the calendar button wrote a date (saturated=$chip)"; return 1; }
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_pill_closed" || return 1
}

# In-notch Location: the location button grows a short Location section below the bar (the bar
# and ✓ stay), Esc closes only the section, a second Esc the panel. The band checked sits right
# below the plain panel (y 250-290), inside the ~350 pt Location blob.
section_band_dark() {
    # section_band_dark <png> <y> <h> -- dark px in a 500 pt wide band centred in the capture.
    dark_count "$1" $(( (PANEL_W + 100) / 2 - 250 )) "$2" 500 "$3" 20
}
LOCATION_X_OFFSET=124   # calendar icon at +69, pill icons 55 pt apart

schedule_notch_location() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local area=$(( 500 * 40 * 4 )) gain=$(( 500 * 40 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_location_open" || return 1
    local png; png=$(shot "schedule_notch_location_before" "$region")
    local before; before=$(section_band_dark "$png" 250 40)
    local deep0; deep0=$(schedule_band_dark "$png" 420)   # baseline, like schedule_notch_section_switch
    [[ "$before" -le $(( area - gain )) ]] || { echo "SKIP:the desktop below the panel is too dark"; return 2; }
    click_at "$(( PANEL_LEFT + LOCATION_X_OFFSET ))" 197
    sleep 0.8
    png=$(shot "schedule_notch_location_shown" "$region")
    local band; band=$(section_band_dark "$png" 250 40)
    local deep; deep=$(schedule_band_dark "$png" 420)
    log_step "after the location button: band=$band (before $before), deeper=$deep"
    [[ "$band" -ge $(( before + gain )) ]] || { fail "expected the location button to grow Location below the bar (dark=$band)"; return 1; }
    [[ "$deep" -lt $(( deep0 + 500 * 80 * 4 * 2 / 5 / 4 )) ]] || { fail "Location grew as tall as Set Date (dark=$deep, before $deep0)"; return 1; }
    png=$(shot "schedule_notch_location_bar")
    assert_save_button_present "$png" || return 1
    press_escape
    sleep 0.9
    png=$(shot "schedule_notch_location_esc" "$region")
    band=$(section_band_dark "$png" 250 40)
    log_step "after Esc: band=$band"
    [[ "$band" -lt $(( before + gain / 4 )) ]] || { fail "expected Esc to close Location (dark=$band)"; return 1; }
    assert_open "schedule_notch_location_still_open" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_location_closed" || return 1
}

# In-notch: one section at a time. ⌘D opens Set Date, the location button switches to Location (the
# blob shrinks to it), ⌘D switches back.
schedule_notch_section_switch() {
    if [[ "${PICKER_STYLE:-notch}" == "popover" ]]; then
        echo "SKIP:picker style is popover"
        return 2
    fi
    local region="$(( PANEL_LEFT - 50 )),0,$(( PANEL_W + 100 )),$SCHEDULE_REGION_H"
    local gain80=$(( 500 * 80 * 4 * 2 / 5 )) gain40=$(( 500 * 40 * 4 * 2 / 5 ))
    hotkey_toggle
    sleep 0.8
    assert_open "schedule_notch_switch_open" || return 1
    local png; png=$(shot "schedule_notch_switch_before" "$region")
    local deep0; deep0=$(schedule_band_dark "$png" 420)
    local near0; near0=$(section_band_dark "$png" 250 40)
    sleep 0.3
    press_cmd d
    sleep 0.8
    png=$(shot "schedule_notch_switch_setdate" "$region")
    local deep; deep=$(schedule_band_dark "$png" 420)
    log_step "Set Date: deep=$deep (before $deep0)"
    [[ "$deep" -ge $(( deep0 + gain80 )) ]] || { fail "expected Set Date to be open (dark=$deep)"; return 1; }
    click_at "$(( PANEL_LEFT + LOCATION_X_OFFSET ))" 197
    sleep 0.9
    png=$(shot "schedule_notch_switch_location" "$region")
    deep=$(schedule_band_dark "$png" 420)
    local near; near=$(section_band_dark "$png" 250 40)
    log_step "Location: deep=$deep near=$near"
    [[ "$deep" -lt $(( deep0 + gain80 / 4 )) ]] || { fail "expected Set Date to give way to the shorter Location (dark=$deep)"; return 1; }
    [[ "$near" -ge $(( near0 + gain40 )) ]] || { fail "expected Location to be open (dark=$near)"; return 1; }
    press_cmd d
    sleep 0.9
    png=$(shot "schedule_notch_switch_back" "$region")
    deep=$(schedule_band_dark "$png" 420)
    log_step "back to Set Date: deep=$deep"
    [[ "$deep" -ge $(( deep0 + gain80 )) ]] || { fail "expected ⌘D to switch back to Set Date (dark=$deep)"; return 1; }
    press_escape
    sleep 0.9
    assert_open "schedule_notch_switch_still_open" || return 1
    press_escape
    sleep 0.6
    assert_closed "schedule_notch_switch_closed" || return 1
}

# ---------------------------------------------------------------- runner

ALL_SCENARIOS=(
    hotkey_open_close
    type_suggestion_tab
    czech_suggestion
    click_notch_opens
    hover_swell
    quick_crossing_no_swell
    click_outside_closes
    margin_click_closes
    reopen_during_close
    date_menu_preset
    schedule_popover_typed
    schedule_popover_preset_shortcut
    schedule_popover_esc
    schedule_notch_expand
    schedule_notch_return_sets
    schedule_notch_click_cancels
    schedule_notch_time_return
    schedule_notch_pill_toggles
    schedule_notch_location
    schedule_notch_section_switch
)
if [[ "$WITH_SAVE" -eq 1 ]]; then
    ALL_SCENARIOS+=(save_choreography)
fi

if [[ -n "$ONLY" ]]; then
    known=0
    for s in "${ALL_SCENARIOS[@]}"; do
        [[ "$s" == "$ONLY" ]] && known=1
    done
    if [[ "$known" -eq 0 ]]; then
        echo "error: unknown scenario '$ONLY' (see Scripts/e2e.sh --help)" >&2
        exit 1
    fi
fi

run_scenario() {
    local name="$1"
    if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
        return
    fi
    local log="$LOG_DIR/$name.log"
    {
        echo "=== $name ==="
        reset_to_closed
    } >"$log" 2>&1 || true
    set +e
    "$name" >>"$log" 2>&1
    local rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "PASS $name"
    elif [[ $rc -eq 2 ]]; then
        local reason; reason=$(tail -n1 "$log" | sed 's/^SKIP://')
        echo "SKIP $name ($reason)"
    else
        local reason; reason=$(tail -n1 "$log")
        echo "FAIL $name ($reason) [log: $log]"
        FAILURES=$((FAILURES + 1))
    fi
}

precondition_app
precondition_osascript
precondition_click_tool
precondition_display
launch_test_instance
setup_key_catcher
measure_baseline

echo "Screenshots + logs: $RUN_DIR" >&2

for scenario in "${ALL_SCENARIOS[@]}"; do
    run_scenario "$scenario"
done

# Leave things closed and tidy before handing back / relaunching.
reset_to_closed 2>/dev/null || true
move_to 500 500 2>/dev/null || true

if ! teardown_key_catcher; then
    FAILURES=$((FAILURES + 1))
fi

echo "----"
echo "Failures: $FAILURES"
exit "$FAILURES"
