#!/usr/bin/env bash
# Wrapper: detect GPU mode, generate gpu.conf, then launch Hyprland.

"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/gpu-setup.sh"
exec /usr/bin/start-hyprland "$@"
