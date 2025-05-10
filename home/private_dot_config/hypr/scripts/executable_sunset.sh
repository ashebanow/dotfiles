#!/bin/sh

# Get the current hour (in 24-hour format)
current_hour=$(date +%H)

# If it’s 6pm to 7am user lower color temparature
if [ $current_hour -ge 18 ] || [ $current_hour -le 6 ]; then
  echo "Changing to nighttime hyprsunset"
  hyprctl hyprsunset temperature 4000
else
  echo "Changing to default hyprsunset"
  hyprctl hyprsunset temperature 6500
fi
