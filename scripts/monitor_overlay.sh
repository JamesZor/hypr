#!/bin/bash
# Kill any existing overlay
pkill -f "kitty --class hypr-monitor-overlay"

# Safely get the currently focused window (or most recently focused non-overlay window with focusHistoryID >= 0)
ADDR=$(hyprctl activewindow -j | jq -r 'select(.class != "hypr-monitor-overlay") | .address // empty')
if [ -z "$ADDR" ] || [ "$ADDR" = "null" ]; then
    ADDR=$(hyprctl clients -j | jq -r 'map(select(.class != "hypr-monitor-overlay" and .focusHistoryID >= 0)) | sort_by(.focusHistoryID) | .[0].address // empty')
fi
if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
    # Private runtime dir, never the shared /tmp; the movers validate what they read back
    echo "$ADDR" > "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr-move-window"
fi

# Dynamically map monitors based on x position to ensure 1 is left, 2 is middle, 3 is right
mapfile -t monitor_names < <(hyprctl monitors -j | jq -r 'sort_by(.x) | .[].name')

# Register explicit windowrules per monitor title so parallel kitty spawns never race on exec [rules]
lua_rules=""
counter=1
for name in "${monitor_names[@]}"; do
    lua_rules+="hl.window_rule({ match = { class = 'hypr-monitor-overlay', title = '^(Monitor $counter)\$' }, monitor = '$name' }) "
    ((counter++))
done
[ -n "$lua_rules" ] && hyprctl eval "$lua_rules" >/dev/null

# Launch kitty as an overlay on each monitor
counter=1
for name in "${monitor_names[@]}"; do
    kitty --class hypr-monitor-overlay -T "Monitor $counter" -e sh -c "printf '\n\n\n\033[1;32m       MONITOR %s\033[0m\n' '$counter'; sleep 10" >/dev/null 2>&1 &
    ((counter++))
done
