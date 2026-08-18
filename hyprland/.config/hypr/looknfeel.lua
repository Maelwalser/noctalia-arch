-- https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 8,
    },

    decoration = {
        -- Use round window corners
        rounding = 20,
        rounding_power = 2,

        shadow = {
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
        },
    },

    misc = {
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

    animations = {
        enabled = true,
    },
})

hl.layer_rule({
    name = "noctalia",
    match = { namespace = "noctalia-background-.*$" },
    ignore_alpha = 0.5,
    blur = true,
    blur_popups = true,
})

-- Custom "snappy" curve. Format: name, { type, points = { {x0, y0}, {x1, y1} } }
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

-- speed is in ds (1ds = 100ms), so speed = 3 -> 300ms
-- Opening/closing applications
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "myBezier" })

-- Workspace switching
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "default", style = "slide" })

-- Instant focus changes and border colour switches
hl.animation({ leaf = "fade", enabled = false })
hl.animation({ leaf = "border", enabled = false })
