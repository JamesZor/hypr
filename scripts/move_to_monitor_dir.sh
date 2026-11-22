#!/bin/bash
DIR=$1
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

if [ -n "$ADDR" ]; then
    # Same as the old `movewindow mon:<dir>`: put the window on the active workspace
    # of the monitor in that direction (focus follows), then focus it again
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$ADDR' }))"
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ monitor = '$DIR', window = 'address:$ADDR' }))"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$ADDR' }))"
fi

# Clean up overlay
~/.config/hypr/scripts/kill_monitor_overlay.sh
