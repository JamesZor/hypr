#!/bin/bash
TARGET_NUM=$1
# Get monitors sorted by x position and select the target one (0-indexed)
INDEX=$((TARGET_NUM - 1))
MONITOR_NAME=$(hyprctl monitors -j | jq -r "sort_by(.x) | .[$INDEX].name")
ADDR=$(cat /tmp/hypr_move_window.txt)

if [ -n "$MONITOR_NAME" ] && [ "$MONITOR_NAME" != "null" ] && [ -n "$ADDR" ]; then
    TARGET_WORKSPACE=$(hyprctl monitors -j | jq -r ".[] | select(.name==\"$MONITOR_NAME\").activeWorkspace.id")
    # Move the specifically saved window to the target monitor's active workspace
    hyprctl dispatch movetoworkspacesilent "$TARGET_WORKSPACE,address:$ADDR"
    # Ensure it's focused after moving
    hyprctl dispatch focuswindow "address:$ADDR"
fi

# Clean up overlay
~/.config/hypr/scripts/kill_monitor_overlay.sh
