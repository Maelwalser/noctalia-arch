-- Application bindings
local terminal = "ghostty"
local browser = "vivaldi-stable --new-window"

-- --- Workspace management ---
-- Bind Alt + [Number] to switch to workspace (1-10)
-- Bind Alt + Shift + [Number] to move active window to workspace (1-10)
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("ALT + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind("ALT + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- --- Resizing Windows ---
hl.bind("ALT + U", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + I", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })
hl.bind("ALT + O", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
hl.bind("ALT + P", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })

-- --- Window management ---
-- Maximize window (within tiling)
hl.bind("ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- Toggle between master-stack and dwindle layout.
-- The layoutmsg has to be deferred: dispatching it inline still hits the old
-- (dwindle) layout, which rejects `swapwithmaster`.
hl.bind("ALT + SHIFT + F", function()
    if hl.get_config("general.layout") == "master" then
        hl.config({ general = { layout = "dwindle" } })
    else
        hl.config({ general = { layout = "master" } })
        hl.timer(function()
            hl.dispatch(hl.dsp.layout("swapwithmaster"))
        end, { timeout = 10, type = "oneshot" })
    end
end, { description = "Toggle master/dwindle layout" })

-- Tiling windows
hl.bind("ALT + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + T", hl.dsp.group.toggle())
hl.bind("ALT + SHIFT + T", hl.dsp.window.float({ action = "disable" }))

-- Center window to the middle of the screen, when tiled
hl.bind("ALT + C", hl.dsp.window.center())

-- --- Window Cycling ---
-- Cycle forward and bring the active window to the top of the Z-order
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- Cycle backward using Shift
hl.bind("ALT + SHIFT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- --- Window Navigation (Vim-style) ---
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))

-- Close window
hl.bind("ALT + SHIFT + q", hl.dsp.window.close())

-- Lock screen
hl.bind("SUPER + l", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call lockScreen lock"))

-- --- Window Movement (Vim-style) ---
-- Tiled windows swap places in the layout. Floating windows step by
-- FLOAT_STEP px, clamped to their monitor's usable area so they can't be
-- pushed under a bar or off the screen — Hyprland's move dispatcher does no
-- clamping of its own.
local FLOAT_STEP = 60

local function clamp(value, low, high)
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

local function move_window(dx, dy, direction)
    local win = hl.get_active_window()
    if not win then
        return
    end

    -- Tiled: let the layout handle it, which preserves the window's size.
    if not win.floating then
        hl.dispatch(hl.dsp.window.move({ direction = direction }))
        return
    end

    local mon = win.monitor
    if not mon then
        return
    end

    -- mon.width/height are the mode in physical pixels; everything else
    -- (position, reserved areas, window geometry) is in logical pixels.
    local reserved = mon.reserved
    local min_x = mon.x + reserved.left
    local min_y = mon.y + reserved.top
    local max_x = mon.x + mon.width / mon.scale - reserved.right - win.size.x
    local max_y = mon.y + mon.height / mon.scale - reserved.bottom - win.size.y

    -- math.max guards windows larger than the monitor: pin the top-left
    -- corner inside the usable area rather than letting it drift off-screen.
    local target_x = clamp(win.at.x + dx, min_x, math.max(min_x, max_x))
    local target_y = clamp(win.at.y + dy, min_y, math.max(min_y, max_y))

    -- Relative, so this stays correct regardless of which monitor it's on.
    hl.dispatch(hl.dsp.window.move({
        x = math.floor(target_x - win.at.x),
        y = math.floor(target_y - win.at.y),
        relative = true,
    }))
end

hl.bind("ALT + SHIFT + h", function() move_window(-FLOAT_STEP, 0, "l") end, { repeating = true })
hl.bind("ALT + SHIFT + l", function() move_window(FLOAT_STEP, 0, "r") end, { repeating = true })
hl.bind("ALT + SHIFT + k", function() move_window(0, -FLOAT_STEP, "u") end, { repeating = true })
hl.bind("ALT + SHIFT + j", function() move_window(0, FLOAT_STEP, "d") end, { repeating = true })

-- Move focus with ALT + HJKL
hl.bind("ALT + h", hl.dsp.focus({ direction = "l" }))
hl.bind("ALT + l", hl.dsp.focus({ direction = "r" }))
hl.bind("ALT + k", hl.dsp.focus({ direction = "u" }))
hl.bind("ALT + j", hl.dsp.focus({ direction = "d" }))

-- --- Application shortcuts ---
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd(terminal .. " -e btop"), { description = "Activity" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call controlCenter toggle"))
hl.bind("ALT + SHIFT + O", hl.dsp.exec_cmd("obsidian"), { description = "Obsidian" })
hl.bind("ALT + SHIFT + B", hl.dsp.exec_cmd(browser), { description = "Browser" })
hl.bind("ALT + RETURN", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind("ALT + SHIFT + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"), { description = "Docker" })

hl.bind("SUPER + W", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call wallpaper toggle"))
hl.bind("ALT + SPACE", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher toggle"), { description = "Launch apps" })

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
