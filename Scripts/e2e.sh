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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) NO_BUILD=1; shift ;;
        --keep) KEEP=1; shift ;;
        --only) ONLY="$2"; shift 2 ;;
        --with-save) WITH_SAVE=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0"
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
mkdir -p "$SHOT_DIR" "$LOG_DIR"

# shellcheck source=Scripts/e2e/lib.sh
source "$LIB_DIR/lib.sh"

FAILURES=0
HAS_NOTCH_DISPLAY=1
CLEANED_UP=0

# ---------------------------------------------------------------- preconditions

precondition_display() {
    if ! system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "built-in.*retina\|retina.*built-in"; then
        HAS_NOTCH_DISPLAY=0
        echo "note: no built-in Retina display detected -- hover/notch scenarios will SKIP" >&2
    fi
}

precondition_app() {
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
    pkill -x QuickReminder 2>/dev/null || true
    sleep 0.4
    QR_CAPTURE_PARKED=1 "$APP_BIN" >"$LOG_DIR/app.log" 2>&1 &
    disown
    sleep 1.2
}

cleanup() {
    if [[ "$CLEANED_UP" -eq 1 ]]; then return; fi
    CLEANED_UP=1
    if [[ "$KEEP" -eq 1 ]]; then
        echo "note: --keep set, leaving the E2E test instance running" >&2
        return
    fi
    pkill -x QuickReminder 2>/dev/null || true
    sleep 0.3
    # launchd occasionally refuses a spawn immediately after pkill; retry once.
    if ! open "$APP_BUNDLE" 2>/dev/null; then
        sleep 0.5
        open "$APP_BUNDLE" 2>/dev/null || echo "warning: failed to relaunch $APP_BUNDLE -- launch it manually" >&2
    fi
    true
}
trap cleanup EXIT

# ---------------------------------------------------------------- scenario helpers

reset_to_closed() {
    press_escape
    move_to 500 500
    sleep 0.4
}

fail() {
    echo "$1"
    return 1
}

# Grey/blue save button (not wallpaper) around global (1138,170), i.e. local
# (537,150)-(577,190) in the 601,0-anchored panel region.
assert_save_button_present() {
    local png="$1"
    local n; n=$(dark_count "$png" 517 150 40 40 150)
    if [[ "$n" -lt 3000 ]]; then
        fail "save button region looks like wallpaper (n=$n)"
        return 1
    fi
    log_step "save button present: n=$n"
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
    local chip; chip=$(color_count "$png_before" 20 125 260 30 0A84FF 60)
    if [[ "$chip" -lt 200 ]]; then
        fail "expected a blue suggestion chip (color_count=$chip)"
        return 1
    fi
    log_step "chip present: color_count=$chip"
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
    type_text "Zavolat mámě zítra ve 14:00"
    sleep 0.5
    local png; png=$(shot "czech_suggestion_typed")
    local chip; chip=$(color_count "$png" 20 125 260 30 0A84FF 60)
    if [[ "$chip" -lt 200 ]]; then
        fail "expected a blue suggestion chip for Czech input (color_count=$chip)"
        return 1
    fi
    log_step "chip present: color_count=$chip"
    press_escape
    sleep 0.6
    assert_closed "czech_suggestion_closed" || return 1
}

click_notch_opens() {
    if [[ "$HAS_NOTCH_DISPLAY" -eq 0 ]]; then
        fail "SKIP:no built-in notch display"
        return 2
    fi
    move_to 901 15
    sleep 0.8
    click_at 901 15
    sleep 0.6
    if ! assert_open "click_notch_opens_open"; then
        # The tap gesture occasionally misses if it lands mid hover-swell
        # animation; one retry clears this without masking a real failure.
        log_step "retrying click on notch once"
        click_at 901 15
        sleep 0.6
        assert_open "click_notch_opens_retry" || return 1
    fi
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
    move_to 890 10
    move_to 900 15
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
    move_to 900 15
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
    click_at 610 120
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
    local n; n=$(dark_count "$png" 0 0 600 214 20)
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

precondition_display
precondition_app
precondition_osascript
precondition_click_tool
launch_test_instance

echo "Screenshots + logs: $RUN_DIR" >&2

for scenario in "${ALL_SCENARIOS[@]}"; do
    run_scenario "$scenario"
done

# Leave things closed and tidy before handing back / relaunching.
press_escape 2>/dev/null || true
move_to 500 500 2>/dev/null || true

echo "----"
echo "Failures: $FAILURES"
exit "$FAILURES"
