-- The animations that depend on the layout: how windows travel to a new
-- place and size, and how workspaces change. looknfeel.lua applies the
-- profile for the layout the session starts in, bindings.lua (set_layout)
-- the other one whenever the layout is switched.
--
--   tiled  (dwindle, master)  windows snap, workspaces cross-fade over a
--                             short sideways slide: nothing is far away, so
--                             the motion only has to confirm the change
--   strip  (scrolling)        windows and workspaces are one surface that is
--                             panned, sideways along the strip and vertically
--                             between the strips stacked under each other
local M = {}

-- speed is in ds (1ds = 100ms), so speed = 3 -> 300ms. A spring takes its
-- duration from its physics; `speed` is required all the same.

local function tiled()
    -- Neither geometry candidate overshoots: overshoot on a *size* animation
    -- scales the window past the monitor edge on the way to fullscreen, which
    -- is what made Alt+Tab look like it was squishing the contents.
    hl.curve("snappy", { type = "bezier", points = { { 0.2, 1 }, { 0.3, 1 } } })
    hl.curve("springSnappy", { type = "spring", stiffness = 600, dampening = 45, mass = 1 })

    -- Which of the two drives the geometry leaves. Swap the commented line to
    -- switch profiles.
    --   fixed   -- 80ms flat, same duration for a nudge and a fullscreen jump
    --   spring  -- physics-derived, near-critical (2*sqrt(k*m) = ~49 at k=600)
    local geometry = { enabled = true, speed = 0.8, bezier = "snappy" }
    -- local geometry = { enabled = true, speed = 1, spring = "springSnappy" }

    -- Workspace switching.
    --
    -- `slidefade N%` cross-fades the two workspaces while they travel only N%
    -- of the monitor width, instead of the full screen-width push that `slide`
    -- does. Short travel is what buys the speed: the switch reads as a fast
    -- settle rather than a strip of desktop being dragged past, so it can run
    -- at ~130ms without looking like frames were dropped.
    --
    -- workspacesIn and workspacesOut share `speed` and `bezier` deliberately.
    -- The style's alpha and offset both run on that curve, so identical timing
    -- makes the two alphas sum to 1 at every frame -- a clean cross-fade with
    -- no bright double-exposure in the middle and no flash of empty
    -- background. Only the travel distance differs: the incoming workspace
    -- slides a short way in while the outgoing one is pushed further out,
    -- which is what gives the switch its sense of depth.
    local workspace = { enabled = true, speed = M.WORKSPACE_SPEED, bezier = "wsSlide" }

    return geometry, workspace, "slidefade 12%", "slidefade 20%"
end

local function strip()
    -- One spring moves everything on the strip, so both axes feel like the
    -- same surface. Why a spring and not a curve:
    --   * its duration follows the distance: a nudge settles at once, a jump
    --     across the strip gets the time to be followed by eye;
    --   * it keeps its velocity when the target changes mid-flight, so wheel
    --     ticks and repeated ALT + H/L become one continuous glide instead of
    --     a row of restarts, and a reversed workspace switch turns around
    --     instead of jumping;
    --   * it starts from rest, where the 80ms tiled curve covers most of the
    --     way in its first frame -- right for a tile, a jump cut for a pan of
    --     half a screen.
    -- Damping ratio 0.9 (critical is 2*sqrt(k*m) = ~63): a column step takes
    -- ~200ms and overshoots by a single pixel. At exactly critical the last
    -- few pixels crawl in for another 150ms, which smears text.
    hl.curve("stripGlide", { type = "spring", stiffness = 1000, dampening = 57, mass = 1 })

    local glide = { enabled = true, speed = 1, spring = "stripGlide" }

    -- Plain `slidevert`, no fade and the full height for both: the two
    -- workspaces stay glued edge to edge and move as a stack, the same way
    -- the columns do sideways.
    return glide, glide, "slidevert", "slidevert"
end

local function animate(leaf, base, style)
    local anim = { leaf = leaf, style = style }
    for k, v in pairs(base) do
        anim[k] = v
    end
    hl.animation(anim)
end

M.WORKSPACE_SPEED = 1.3 -- ds, so 130ms (was 200ms with the old `slide`)

function M.apply(layout)
    -- easeOutExpo: ~85% of the distance is covered in the first third of the
    -- duration, so the motion is over almost before the eye tracks it and the
    -- tail is just the settle. Defined for both profiles: specialWorkspace
    -- (looknfeel.lua) uses it too.
    hl.curve("wsSlide", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })

    local geometry, workspace, style_in, style_out = (layout == "scrolling" and strip or tiled)()

    -- windowsIn governs far more than windows opening: a window's size
    -- animation keeps this config for its whole life (only its position is
    -- ever switched to windowsMove), so fullscreen toggles and resizes animate
    -- here too. Set explicitly rather than inherited from `windows`, which is
    -- tuned for opening and would drag its overshoot into every resize. Both
    -- leaves always get the same motion, or a resized column and the
    -- neighbours it pushes aside would arrive at different times.
    animate("windowsIn", geometry)
    animate("windowsMove", geometry)
    animate("workspacesIn", workspace, style_in)
    animate("workspacesOut", workspace, style_out)
end

return M
