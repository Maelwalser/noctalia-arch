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

-- --- Window Switcher ---
-- In fullscreen, Alt+Tab opens Noctalia's switcher overlay (style/MRU in
-- noctalia config.toml). "hold" keeps it open while Alt is down; each
-- further Tab advances and releasing Alt focuses the selection. Noctalia
-- has no reverse "hold", so going backwards inside the overlay is left to
-- the overlay itself: Alt+Shift+Tab is non-consuming and steps aside while
-- the overlay is open, so the key reaches it.
--
-- With misc.on_focus_under_fullscreen = 1 ("take_over"), switching while a
-- window is fullscreen moves the fullscreen state onto the newly focused
-- window, so its geometry travels from its tiled slot out to the whole
-- monitor. Two leaves drive that, which is not obvious: windowsMove for the
-- position, and windowsIn for the *size* -- a window's size animation keeps
-- the config it was mapped with and is never reassigned. Both are tuned for
-- this transition in looknfeel.lua.
local SWITCHER_NAMESPACE = "noctalia-window-switcher"

local function overlaps(a, b)
    return a.at.x < b.at.x + b.size.x and b.at.x < a.at.x + a.size.x
        and a.at.y < b.at.y + b.size.y and b.at.y < a.at.y + a.size.y
end

local function has_overlapping_windows(ws)
    local visible = {}
    for _, win in ipairs(hl.get_workspace_windows(ws.id)) do
        if not win.hidden then
            for _, other in ipairs(visible) do
                if overlaps(win, other) then
                    return true
                end
            end
            visible[#visible + 1] = win
        end
    end
    return false
end

local function switcher_open()
    return #hl.get_layers({ namespace = SWITCHER_NAMESPACE }) > 0
end

-- Fullscreen or maximized: the other windows are out of sight, so show the
-- carousel. Windows stacked in front of each other: just focus the next
-- one and raise it. Tiled side by side: everything is already on screen,
-- so do nothing.
local function switch_window(forward)
    local ws = hl.get_active_workspace()
    if not ws or ws.windows < 2 then
        return
    end
    if ws.has_fullscreen then
        hl.exec_cmd("noctalia msg window-switcher hold")
    elseif has_overlapping_windows(ws) then
        hl.dispatch(hl.dsp.window.cycle_next({ next = forward }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end
end

hl.bind("ALT + Tab", function()
    switch_window(true)
end)

hl.bind("ALT + SHIFT + Tab", function()
    if not switcher_open() then
        switch_window(false)
    end
end, { non_consuming = true })

-- --- Window Navigation (Vim-style) ---
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))

-- Close window
hl.bind("ALT + SHIFT + q", hl.dsp.window.close())

-- Lock screen
hl.bind("SUPER + l", hl.dsp.exec_cmd("noctalia msg session lock"))

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
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"))
hl.bind("ALT + SHIFT + O", hl.dsp.exec_cmd("obsidian"), { description = "Obsidian" })
hl.bind("ALT + SHIFT + B", hl.dsp.exec_cmd(browser), { description = "Browser" })
hl.bind("ALT + RETURN", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind("ALT + SHIFT + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"), { description = "Docker" })

hl.bind("SUPER + W", hl.dsp.exec_cmd("noctalia msg panel-toggle wallpaper"))
hl.bind("SUPER + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"), { description = "Clipboard history" })
hl.bind("ALT + SPACE", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Launch apps" })

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
