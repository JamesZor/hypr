#!/bin/bash

# Get the focused window's PID
FOCUSED_PID=$(hyprctl activewindow -j | jq '.pid')

# Get the working directory of the focused process
FOCUSED_PWD=$(readlink /proc/$FOCUSED_PID/cwd)

# Launch Alacritty in the same directory
alacritty --working-directory "$FOCUSED_PWD"
