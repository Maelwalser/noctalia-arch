hl.config({
    input = {
        kb_layout = "ch",

        kb_options = "compose:caps", -- ,grp:shifts_toggle

        -- Change speed of keyboard repeat
        repeat_rate = 40,
        repeat_delay = 250,

        -- Start with numlock on by default
        numlock_by_default = true,

        -- Increase sensitivity for mouse/trackpad (default: 0)
        -- sensitivity = 0.35,

        follow_mouse = 2,

        touchpad = {
            -- Use natural (inverse) scrolling
            natural_scroll = true,
            disable_while_typing = true,
            -- Use two-finger clicks for right-click instead of lower-right corner
            -- clickfinger_behavior = true,

            -- Control the speed of your scrolling
            scroll_factor = 0.2,
        },
    },
})

-- Moving and resizing windows with the mouse (the binds are in bindings.lua).
hl.config({
    general = {
        -- Drag a border, or the gap beside it, to resize: no modifier needed.
        resize_on_border = true,
        -- How far outside the border that grab reaches. 10 = the whole gap
        -- between two tiled windows (2 x gaps_in) without reaching into the
        -- neighbour, where it would swallow clicks meant for that window.
        extend_border_grab_area = 10,
        -- The cursor turns into a resize arrow wherever a drag would resize.
        hover_icon_on_border = true,

        -- A floating window being moved or resized sticks to screen edges and
        -- to other windows once it is within 12px, leaving the same gaps the
        -- tiling layout uses, so hand-placed windows line up with tiled ones.
        snap = {
            enabled = true,
            window_gap = 12,
            monitor_gap = 12,
            respect_gaps = true,
        },
    },

    dwindle = {
        -- A dragged tiled window lands on the side of the target the cursor
        -- is over, instead of wherever the split direction happens to put it.
        precise_mouse_move = true,
    },

    misc = {
        -- The window is glued to the cursor: no easing between the pointer
        -- and the window, which would read as lag. (Both are the defaults,
        -- pinned here because the geometry animations in looknfeel.lua would
        -- otherwise apply.)
        animate_mouse_windowdragging = false,
        animate_manual_resizes = false,
    },
})

-- Scroll nicely in the terminal
hl.window_rule({ match = { class = "com.mitchellh.ghostty" }, scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
