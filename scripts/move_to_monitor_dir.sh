#!/bin/bash
DIR=$1
ADDR=$(cat /tmp/hypr_move_window.txt)

if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
    hyprctl dispatch focuswindow "address:$ADDR"
    hyprctl dispatch movewindow "mon:$DIR"
    hyprctl dispatch focuswindow "address:$ADDR"
fi

# Clean up overlay
~/.config/hypr/scripts/kill_monitor_overlay.sh
