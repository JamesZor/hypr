#!/bin/bash
TARGET_NUM=$1
# Get monitors sorted by x position and select the target one (0-indexed)
INDEX=$((TARGET_NUM - 1))
MONITOR_NAME=$(hyprctl monitors -j | jq -r "sort_by(.x) | .[$INDEX].name")
# Saved window from monitor_overlay.sh: read at most 64 characters of the private runtime
# file and accept it only if the whole value is one line of the form 0x<hex>
SAVED="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr-move-window"
ADDR=""
RAW=""
if [ -f "$SAVED" ] && ! IFS= read -r -d '' -n 64 RAW 2>/dev/null < "$SAVED"; then
    # read failed = hit end of file before any NUL byte or the length limit
    RAW=${RAW%$'\n'}
    if [[ $RAW =~ ^0x[0123456789abcdefABCDEF]+$ ]]; then
        ADDR=$RAW
    fi
fi

if [ -n "$MONITOR_NAME" ] && [ "$MONITOR_NAME" != "null" ] && [ -n "$ADDR" ]; then
    # Move the specifically saved window to the target monitor's active workspace (silently)
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ monitor = '$MONITOR_NAME', window = 'address:$ADDR', follow = false }))"
    # Ensure it's focused after moving
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$ADDR' }))"
fi

# Clean up overlay
~/.config/hypr/scripts/kill_monitor_overlay.sh
