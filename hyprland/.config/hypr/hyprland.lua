-- Hyprland configuration (Lua format, Hyprland >= 0.55).
-- The old hyprlang `.conf` format is deprecated; everything here mirrors what
-- used to live in hyprland.conf and the files it sourced.

-- Hardware cursors: let the display engine draw the cursor instead of
-- re-compositing the whole framebuffer on every mouse move. Critical for
-- the 5120x2160 ultrawide (DP-4) driven by the Intel iGPU — software
-- cursors made the desktop feel laggy. The old NVIDIA mixed-scaling glitch
-- this used to work around no longer applies (the ultrawide is on Intel,
-- and the dGPU drives no display). Re-enable software cursors only if
-- cursor artifacts return.
hl.config({
    cursor = {
        no_hardware_cursors = false,
    },
})

hl.config({
    xwayland = {
        -- Tells XWayland apps to handle their own scaling
        -- This can make them sharp, but some may be tiny.
        force_zero_scaling = true,
    },
})

-- Each require() gets its own Lua scope, so an error in one file does not
-- abort the others.
require("monitors")
require("input")
require("bindings")
require("envs")
require("looknfeel")
require("autostart")

-- Palette written by noctalia-shell. Must come last so it wins over the
-- colours set above.
require("noctalia")
