#!/bin/bash
# Screenshot helper for QuickReminder development.
#
# Usage:
#   Scripts/shot.sh <name>              capture the notch-area region (default)
#   Scripts/shot.sh -R X,Y,W,H <name>   capture a custom region
#   Scripts/shot.sh --full <name>       capture the whole built-in display
#
# The built-in display is the main display at global origin (0,0); its
# 1800x1169pt notch area defaults to x=500,y=0,w=800,h=360 in top-left
# global coordinates, which is what `screencapture -R` expects.

set -euo pipefail

OUT_DIR="${QR_SHOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)/build/shots}"
REGION="500,0,800,360"
FULL=0
NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -R)
            REGION="$2"
            shift 2
            ;;
        --full)
            FULL=1
            shift
            ;;
        -*)
            echo "error: unknown option $1" >&2
            exit 1
            ;;
        *)
            NAME="$1"
            shift
            ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "usage: $(basename "$0") [-R X,Y,W,H | --full] <name>" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
OUT_PATH="$OUT_DIR/$NAME.png"

if [[ "$FULL" -eq 1 ]]; then
    screencapture -x -D 1 "$OUT_PATH"
else
    screencapture -x -R "$REGION" "$OUT_PATH"
fi

echo "$OUT_PATH"
