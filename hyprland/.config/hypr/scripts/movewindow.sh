#!/bin/bash
# Move the active floating window by (dx, dy) while clamping to monitor bounds.
# Usage: movewindow.sh <dx> <dy>

dx=$1
dy=$2
direction=${3:-}

# Single batch call to get all state
win=$(hyprctl activewindow -j)

# If tiled, move window in the layout (preserves size)
if [ "$(echo "$win" | jq -r '.floating')" != "true" ]; then
    [ -n "$direction" ] && hyprctl dispatch movewindow "$direction"
    exit 0
fi

read -r wx wy ww wh addr monitor <<< "$(echo "$win" | jq -r '[.at[0], .at[1], .size[0], .size[1], .address, .monitor] | @tsv')"

mon=$(hyprctl monitors -j | jq ".[] | select(.id == $monitor)")
read -r mx my mw_raw mh_raw scale <<< "$(echo "$mon" | jq -r '[.x, .y, .width, .height, .scale] | @tsv')"
read -r res_left res_top res_right res_bottom <<< "$(echo "$mon" | jq -r '.reserved | @tsv')"

mw=$(awk "BEGIN{printf \"%d\", $mw_raw/$scale}")
mh=$(awk "BEGIN{printf \"%d\", $mh_raw/$scale}")

min_x=$((mx + res_left))
min_y=$((my + res_top))
max_x=$((mx + mw - res_right))
max_y=$((my + mh - res_bottom))

newx=$((wx + dx))
newy=$((wy + dy))

[ "$newx" -lt "$min_x" ] && newx=$min_x
[ "$newy" -lt "$min_y" ] && newy=$min_y
[ $((newx + ww)) -gt "$max_x" ] && newx=$((max_x - ww))
[ $((newy + wh)) -gt "$max_y" ] && newy=$((max_y - wh))

hyprctl dispatch movewindowpixel "exact $newx $newy,address:$addr"
