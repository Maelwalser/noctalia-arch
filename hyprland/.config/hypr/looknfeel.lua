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

-- Both candidates for the geometry animations (windowsIn drives size,
-- windowsMove drives position). Neither overshoots: overshoot on a *size*
-- animation scales the window past the monitor edge on the way to fullscreen,
-- which is what made Alt+Tab look like it was squishing the contents.
hl.curve("snappy", { type = "bezier", points = { { 0.2, 1 }, { 0.3, 1 } } })
hl.curve("springSnappy", { type = "spring", stiffness = 600, dampening = 45, mass = 1 })

-- Which of the two drives the geometry leaves. Swap the commented line to
-- switch profiles; `speed` is required either way, even for a spring.
--   fixed   -- 80ms flat, same duration for a nudge and a fullscreen jump
--   spring  -- physics-derived, near-critical (2*sqrt(k*m) = ~49 at k=600)
local GEOMETRY_ANIM = { enabled = true, speed = 0.8, bezier = "snappy" }
-- local GEOMETRY_ANIM = { enabled = true, speed = 1, spring = "springSnappy" }

local function geometry_anim(leaf)
    local anim = { leaf = leaf }
    for k, v in pairs(GEOMETRY_ANIM) do
        anim[k] = v
    end
    return anim
end

-- speed is in ds (1ds = 100ms), so speed = 3 -> 300ms
-- Opening/closing applications
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "myBezier" })
-- windowsIn governs far more than windows opening: a window's size animation
-- keeps this config for its whole life (only its position is ever switched to
-- windowsMove), so fullscreen toggles and resizes animate here too. Set
-- explicitly rather than inherited from `windows`, which is tuned for opening
-- and would drag its overshoot into every resize.
hl.animation(geometry_anim("windowsIn"))
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default", style = "popin 80%" })
hl.animation(geometry_anim("windowsMove"))

-- Workspace switching
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "default", style = "slide" })

-- Instant focus changes and border colour switches
hl.animation({ leaf = "fade", enabled = false })
hl.animation({ leaf = "border", enabled = false })
