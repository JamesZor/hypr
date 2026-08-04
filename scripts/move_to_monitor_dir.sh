#!/bin/bash
DIR=$1
ADDR=$(cat /tmp/hypr_move_window.txt)

if [ -n "$ADDR" ]; then
    hyprctl dispatch movewindow "$DIR,address:$ADDR"
    hyprctl dispatch focuswindow "address:$ADDR"
fi

# Clean up overlay
~/.config/hypr/scripts/kill_monitor_overlay.sh
