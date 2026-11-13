local acid = require("dotfiles_theme") == "acid"
local motion = require("motion")

-- https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in = motion.GAPS_IN,
        gaps_out = motion.GAPS_OUT, -- narrower at the sides on the strip (motion.lua)
    },

    decoration = {
        -- ACID//HUD: near-square corners; classic: round ones.
        rounding = acid and 18 or 20, -- acid: the liquid-glass toast radius (noctalia/themes/acid.toml corner_radius_scale)
        rounding_power = 2,

        -- Unfocused windows sit back a little, so the focused one reads first.
        dim_inactive = true,
        dim_strength = 0.12,

        -- ACID//HUD: wide soft shadow; hyprland.lua tints the active one acid
        -- for a glow. Classic: a tight dark one.
        shadow = acid and {
            enabled = true,
            range = 18,
            render_power = 3,
            color = "rgba(000000aa)",
            color_inactive = "rgba(00000088)",
        } or {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },

        blur = {
            enabled = true,
            size = 3,
            passes = 2,
            vibrancy = 0.1696,
            -- Context menus and popovers are blurred like the windows they
            -- open from, instead of flat rectangles over the glass.
            popups = true,
        },
    },

    misc = {
        -- Plain black until Noctalia has drawn: without this the stock Hyprland
        -- wallpaper and splash line flash between the boot splash and the lock.
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(000000)",
        -- ACID//HUD: keep rendering the desktop under the (opaque) lock surface,
        -- so the hud-unlock layer beneath it keeps getting frame callbacks and
        -- its copy of the lock screen stays fresh until the unlock frame.
        session_lock_xray = acid,
        -- Keeps the "fullscreen" state when switching focus
        on_focus_under_fullscreen = true,
    },

    -- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
    dwindle = {
        -- Preserves the layout structure when moving/opening windows
        preserve_split = true,
    },

    master = {
        mfact = 0.65,
    },

    -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
    scrolling = {
        -- Two columns to a screen; SUPER + R steps through the other widths.
        column_width = 0.5,
        -- The strip has two ends: focus and column swaps stop there instead
        -- of jumping to the other end.
        wrap_focus = false,
        wrap_swapcol = false,
    },

    animations = {
        enabled = true,
    },
})

hl.layer_rule({
    name = "noctalia",
    match = {
        namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
    },
    -- Noctalia animates its own surfaces; Hyprland's would fight them.
    no_anim = true,
    ignore_alpha = 0.5,
    blur = true,
    blur_popups = true,
})

-- ACID//HUD desktop overlay (quickshell/.config/quickshell/hud): it animates
-- itself and must stay crisp, so no layer animation and no blur behind it.
hl.layer_rule({
    name = "hud-overlay",
    match = { namespace = "^hud-overlay$" },
    no_anim = true,
    blur = false,
})
-- Its glass panes are a second layer that hyprglass renders (plugins.lua),
-- kept under the content whatever the map order: it unmaps whenever the
-- desktop is covered and would otherwise come back on top. (order = 1 puts
-- it below hud-overlay's default 0; -1 left it on top.)
hl.layer_rule({
    name = "hud-glass",
    match = { namespace = "^hud-glass$" },
    no_anim = true,
    blur = false,
    order = 1,
})
-- The HUD's launcher (quickshell hud, Launcher.qml): the glass shapes on one
-- layer, the text and icons on another, kept above it.
hl.layer_rule({
    name = "hud-launcher",
    match = { namespace = "^hud-launcher$" },
    no_anim = true,
    blur = false,
})
hl.layer_rule({
    name = "hud-launcher-glass",
    match = { namespace = "^hud-launcher-glass$" },
    no_anim = true,
    blur = false,
    order = 1,
})
-- The HUD's stack overview (quickshell hud, Overview.qml): it animates
-- itself, and lies under the bar (order = 1, as for hud-glass), which stays
-- where it is while the windows draw back.
hl.layer_rule({
    name = "hud-overview",
    match = { namespace = "^hud-overview$" },
    no_anim = true,
    blur = false,
    order = 1,
})
-- The HUD's bar tooltips (quickshell hud, Tip.qml): glass, so no blur of
-- Hyprland's own, and they appear in place.
hl.layer_rule({
    name = "hud-tooltip",
    match = { namespace = "^hud-tooltip$" },
    no_anim = true,
    blur = false,
})
-- The unlock reveal (overlay layer, mapped only while locked and for the fold):
-- it animates itself, and hyprglass blurs behind it (plugins.lua).
hl.layer_rule({
    name = "hud-unlock",
    match = { namespace = "^hud-unlock$" },
    no_anim = true,
    blur = false,
})
-- The lock's live readouts (clock, date, reticle), drawn by the HUD over
-- Noctalia's lock surface so the doors carry them both ways.
hl.layer_rule({
    name = "hud-lockwidgets",
    match = { namespace = "^hud-lockwidgets$" },
    no_anim = true,
    blur = false,
    above_lock = true,
})

-- Custom "snappy" curve. Format: name, { type, points = { {x0, y0}, {x1, y1} } }
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

-- speed is in ds (1ds = 100ms), so speed = 3 -> 300ms
-- Opening/closing applications
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default", style = "popin 80%" })

-- The layout chosen with SUPER + S / ALT + SHIFT + F (bindings.lua) is not in
-- this config, so a reload, which every save of a file here causes, would
-- drop it for the default. It is kept in a file for the session and set
-- again here.
do
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-layout", "r")
    local kept = f and f:read("l")
    if f then
        f:close()
    end
    if kept == "dwindle" or kept == "master" or kept == "scrolling" then
        hl.config({ general = { layout = kept } })
    end
end

-- How windows travel and resize (windowsIn, windowsMove) and how workspaces
-- change depends on the layout: motion.lua has both profiles.
motion.apply(hl.get_config("general.layout"))

-- motion.lua overrides `workspacesIn`/`workspacesOut` only, so
-- `specialWorkspace` no longer inherits their timing -- without this it would
-- fall through to the 800ms global default. Nothing binds a scratchpad today;
-- this just keeps it from being unusably slow the day something does. Left on
-- the plain full-width slide it always used, only the timing is matched.
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = motion.WORKSPACE_SPEED, bezier = "wsSlide" })

-- Slide 5 -> 1 forwards instead of racing backwards across four workspaces.
-- Only affects the direction the animation picks, not which workspace is
-- focused.
hl.config({ animations = { workspace_wraparound = true } })

-- Instant focus changes and border colour switches
hl.animation({ leaf = "fade", enabled = false })
hl.animation({ leaf = "border", enabled = false })

-- The active border's gradient could slowly circle the window (one turn per
-- 10 s), but `loop` redraws the active window every frame: on the 5120x2160
-- ultrawide that alone kept the iGPU about 70 % busy at idle, which heats the
-- laptop into its power cap and delays typing. Off.
local HUD_BORDER_LOOP = false
hl.curve("hudLinear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.animation({ leaf = "borderangle", enabled = HUD_BORDER_LOOP, speed = 100, bezier = "hudLinear", style = "loop" })
