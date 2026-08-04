#!/bin/bash
# Kill any existing overlay
pkill -f "hypr-monitor-overlay"

# Safely get the most recently focused window that is NOT the overlay popup
ADDR=$(hyprctl clients -j | jq -r 'map(select(.class != "hypr-monitor-overlay")) | sort_by(.focusHistoryID) | .[0].address')
if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
    echo "$ADDR" > /tmp/hypr_move_window.txt
fi


monitors=$(hyprctl monitors -j)
counter=1

# Dynamically map monitors based on x position to ensure 1 is left, 2 is middle, 3 is right
# (Or just sort by ID, but sorting by x is better for physical layout)
echo "$monitors" | jq -c 'sort_by(.x) | .[]' | while read -r monitor; do
    id=$(echo "$monitor" | jq -r '.id')
    name=$(echo "$monitor" | jq -r '.name')
    
    # Launch kitty as an overlay on each monitor
    # It will display the number centered and close automatically if not killed
    hyprctl dispatch exec "[float; nofocus; noanim; center; size 250 150; monitor $name] kitty --class hypr-monitor-overlay -T 'Monitor $counter' -e sh -c 'printf \"\n\n\n\033[1;32m       MONITOR %s\033[0m\n\" \"$counter\"; sleep 10'"
    
    ((counter++))
done
