#!/bin/bash
# Shared helpers for Scripts/e2e.sh. Sourced, not executed directly.
#
# Conventions:
#  - All screen coordinates are top-left GLOBAL points (screencapture -R /
#    CGEvent space). The built-in display is at global origin (0,0) and is
#    1800x1169pt; the notch is centred at x=901; the open panel spans
#    x 601-1201 / y 0-214 within it.
#  - The main capture region used by almost every assertion is
#    "601,0,600,214" (600x214pt -> 1200x428px on this 2x Retina display),
#    aliased below as $PANEL_REGION.
#  - $CLICK is the path to the compiled click helper (Scripts/click.swift).
#  - $PIXELS is `python3 Scripts/e2e/pixels.py`.

PANEL_REGION="601,0,600,214"

# Thresholds calibrated by hand against this machine's build (see
# docs/testing.md for how they were derived). They have generous margin:
# a fully open panel measures ~459k dark px in the full 600x214 region;
# closed (even hover-swollen) measures ~35k-45k.
DARK_OPEN_MIN=150000
DARK_CLOSED_MAX=100000

log_step() {
    echo "    ... $*" >&2
}

shot() {
    # shot <name> [region] -- writes into $SHOT_DIR/<name>.png, returns path on stdout.
    local name="$1"
    local region="${2:-$PANEL_REGION}"
    QR_SHOT_DIR="$SHOT_DIR" "$ROOT/Scripts/shot.sh" -R "$region" "$name" >/dev/null
    echo "$SHOT_DIR/$name.png"
}

dark_count() {
    # dark_count <png> <x> <y> <w> <h> [max_channel]
    python3 "$LIB_DIR/pixels.py" dark_count "$@"
}

bright_count() {
    python3 "$LIB_DIR/pixels.py" bright_count "$@"
}

color_count() {
    python3 "$LIB_DIR/pixels.py" color_count "$@"
}

silhouette_width() {
    python3 "$LIB_DIR/pixels.py" silhouette_width "$@"
}

# assert_open <shot-name> -- panel must be visibly open (dark region large).
assert_open() {
    local label="$1"
    local png; png=$(shot "$label")
    local n; n=$(dark_count "$png" 0 0 600 214 20)
    if [[ "$n" -lt "$DARK_OPEN_MIN" ]]; then
        echo "expected open (dark=$n < $DARK_OPEN_MIN) at $label"
        return 1
    fi
    # A plain black surface under the notch (dark terminal, video) must never pass as "open":
    # the accent-blue "Reminders ▾" header is the panel's own signature. Nothing is typed
    # unless this passes.
    local blue; blue=$(color_count "$png" 30 40 300 50 0A84FF 70)
    if [[ "$blue" -lt 400 ]]; then
        echo "expected the blue Reminders header (blue=$blue < 400) at $label"
        return 1
    fi
    log_step "assert_open $label: dark=$n blue=$blue"
    return 0
}

# assert_closed <shot-name> -- panel must be closed (parked pill or gone).
assert_closed() {
    local label="$1"
    local png; png=$(shot "$label")
    local n; n=$(dark_count "$png" 0 0 600 214 20)
    if [[ "$n" -gt "$DARK_CLOSED_MAX" ]]; then
        echo "expected closed (dark=$n > $DARK_CLOSED_MAX) at $label"
        return 1
    fi
    log_step "assert_closed $label: dark=$n"
    return 0
}

# measure_width <shot-name> -- silhouette width in points at y=20pt; prints it.
measure_width() {
    local label="$1"
    local png; png=$(shot "$label")
    silhouette_width "$png" 20
}

hotkey_toggle() {
    osascript -e 'tell application "System Events" to keystroke "r" using {shift down, command down}'
}

press_escape() {
    osascript -e 'tell application "System Events" to key code 53'
}

press_cmd_return() {
    osascript -e 'tell application "System Events" to keystroke return using {command down}'
}

press_tab() {
    osascript -e 'tell application "System Events" to key code 48'
}

type_text() {
    # type_text "some text" -- osascript keystroke; quotes/backslashes are
    # escaped for AppleScript string literals.
    local text="$1"
    local escaped="${text//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    osascript -e "tell application \"System Events\" to keystroke \"$escaped\""
}

click_at() {
    "$CLICK" "$1" "$2"
}

move_to() {
    "$CLICK" move "$1" "$2"
}
