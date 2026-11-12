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
-- (ALT + F, maximize, is with the scrolling layout below: the strip needs a
-- say in it.)

-- Layout changes show a toast naming the new layout: with one or two windows
-- open the three tile them alike and the change cannot be seen. It is a plain
-- desktop notification (Noctalia's "brief" filter: 3.5 s, never sticky).
local LAYOUT_NAMES = { dwindle = "Dwindle", master = "Master stack", scrolling = "Scrolling strip" }

local function set_layout(name)
    hl.config({ general = { layout = name } })
    -- The strip pans, the other layouts snap: windows and workspaces move
    -- differently on it (motion.lua).
    require("motion").apply(name)
    -- Nothing on the event socket says the layout changed: tell the bar's
    -- workspace widget, which is a drum on the strip and a row elsewhere.
    hl.dispatch(hl.dsp.event("layout"))
    hl.exec_cmd("gdbus call --session --dest org.freedesktop.Notifications"
        .. " --object-path /org/freedesktop/Notifications"
        .. " --method org.freedesktop.Notifications.Notify"
        .. " hypr-layout 0 '' 'Layout' '" .. LAYOUT_NAMES[name] .. "' '[]' \"{'transient': <true>}\" 2000")
end

-- Toggle between master-stack and dwindle layout.
-- The layoutmsg has to be deferred: dispatching it inline still hits the old
-- layout, which rejects `swapwithmaster`.
hl.bind("ALT + SHIFT + F", function()
    if hl.get_config("general.layout") == "master" then
        set_layout("dwindle")
    else
        set_layout("master")
        hl.timer(function()
            hl.dispatch(hl.dsp.layout("swapwithmaster"))
        end, { timeout = 10, type = "oneshot" })
    end
end, { description = "Toggle master/dwindle layout" })

-- The scrolling strip has a key of its own, on and off (off is dwindle).
hl.bind("SUPER + S", function()
    set_layout(hl.get_config("general.layout") == "scrolling" and "dwindle" or "scrolling")
end, { description = "Toggle scrolling layout" })

-- --- Scrolling layout ---
-- Windows are columns on a strip that runs off the screen once they no
-- longer fit: at half a screen each (looknfeel.lua), from the third window
-- on. The focus and move binds below work on it as they are, and the strip
-- follows the focus. These add what only a strip has; each message is sent only on
-- a scrolling workspace, as the other layouts reject it.
--   ALT + wheel     slide the strip a column at a time
--   SUPER + R       next column width (a third, half, two thirds, full)
--   SUPER + J       stack the window under the column before it, or lift a
--                   stacked window out into a column of its own
--                   (in dwindle: flip the split, as before)
--   ALT + C         centre the column (a floating window: centre it, as before)
--   ALT + J / K     past the bottom or top of a column: the workspace below
--                   or above, so the workspaces are strips stacked on each
--                   other (with SHIFT the window is taken along)
--   SUPER + A       overview: squeeze every column onto the screen at once
--   SUPER + SHIFT + A   back from it: every column half a screen again
local function on_strip()
    local ws = hl.get_active_workspace()
    return ws ~= nil and ws.tiled_layout == "scrolling"
end

local function strip(msg, otherwise)
    return function()
        if on_strip() then
            hl.dispatch(hl.dsp.layout(msg))
        elseif otherwise then
            hl.dispatch(otherwise)
        end
    end
end

-- Whether a tiled window sits above/below `win` in its column.
local function column_neighbour(win, down)
    for _, other in ipairs(hl.get_workspace_windows(hl.get_active_workspace().id)) do
        if other.address ~= win.address and not other.hidden and not other.floating
            and other.at.x < win.at.x + win.size.x and win.at.x < other.at.x + other.size.x then
            if down and other.at.y > win.at.y or not down and other.at.y < win.at.y then
                return true
            end
        end
    end
    return false
end

-- True when a vertical step from the focused window leaves the strip: it is
-- tiled (or there is none) and nothing is above/below it in its column.
local function leaves_strip(down)
    if not on_strip() then
        return false
    end
    local win = hl.get_active_window()
    return not win or (not win.floating and not column_neighbour(win, down))
end

-- r+1 / r-1: the next workspace on this monitor, empty ones included, so
-- there is always a free strip below the last one.
local function stack_workspace(down)
    return down and "r+1" or "r-1"
end

-- Maximize window (within tiling).
-- On the strip a maximized window is a column the width of the screen, and
-- the strip is slid so that it starts at the left edge. Shrinking it again
-- leaves it there, which is where a left-hand column came from; a column
-- that sat further right would end up on the wrong side with a hole beside
-- it. So the place it was maximized from is kept and the strip slid back to
-- it, in the same step as the resize: the edge it grew from is the one that
-- comes back in.
local maximized_from = {} -- window address -> x it was maximized from

hl.bind("ALT + F", function()
    local toggle = hl.dsp.window.fullscreen({ mode = "maximized" })
    local win = hl.get_active_window()
    if not win or win.floating or not on_strip() then
        hl.dispatch(toggle)
        return
    end
    if win.fullscreen == 0 then
        maximized_from[win.address] = win.at.x
        hl.dispatch(toggle)
        return
    end
    local from = maximized_from[win.address]
    maximized_from[win.address] = nil
    hl.dispatch(toggle)
    -- `at` is already the place the window is heading for.
    win = hl.get_active_window()
    if from and win and win.fullscreen == 0 and from > win.at.x then
        hl.dispatch(hl.dsp.layout("move +" .. math.floor(from - win.at.x)))
        -- A pixel move hands the focus to the column in the middle.
        hl.dispatch(hl.dsp.focus({ window = win }))
    end
end, { description = "Maximize window" })

-- The strip against the screen: whether it runs off it on the side `forward`
-- names (a tiled window is cut off by that edge or lies beyond it), whether
-- any column is on screen, and its last window on that side.
local function strip_extent(forward)
    local ws = hl.get_active_workspace()
    local mon = ws and ws.monitor
    if not mon then
        return false, true, nil
    end
    -- mon.width is the mode in physical pixels, window geometry is logical.
    local left, right = mon.x, mon.x + mon.width / mon.scale
    local beyond, on_screen, last = false, false, nil
    for _, win in ipairs(hl.get_workspace_windows(ws.id)) do
        if not win.hidden and not win.floating then
            if forward and win.at.x + win.size.x > right or not forward and win.at.x < left then
                beyond = true
            end
            -- By half its width at least: the gap of a column that is out of
            -- sight reaches a pixel into the screen.
            local shown = math.min(win.at.x + win.size.x, right) - math.max(win.at.x, left)
            if shown * 2 >= math.min(win.size.x, right - left) then
                on_screen = true
            end
            if not last or forward and win.at.x > last.at.x or not forward and win.at.x < last.at.x then
                last = win
            end
        end
    end
    return beyond, on_screen, last
end

-- The layout slides the strip a column whether or not one is there: past the
-- last column the screen is left empty and nothing has the focus. So the
-- strip only slides towards columns that are out of sight, and should a
-- slide carry every column off the screen all the same (the step is counted
-- from the focused column, not from the screen), the last column is focused,
-- which brings the strip back to it.
local function slide_strip(forward)
    return function()
        if not on_strip() or not strip_extent(forward) then
            return
        end
        hl.dispatch(hl.dsp.layout(forward and "move +col" or "move -col"))
        local _, on_screen, last = strip_extent(forward)
        if not on_screen and last then
            hl.dispatch(hl.dsp.focus({ window = last }))
        end
    end
end

hl.bind("ALT + mouse_down", slide_strip(true), { description = "Scroll the window strip forward" })
hl.bind("ALT + mouse_up", slide_strip(false), { description = "Scroll the window strip back" })
hl.bind("SUPER + R", strip("colresize +conf"), { description = "Cycle column width" })
hl.bind("SUPER + A", strip("fit all"), { description = "Fit all columns on screen" })
hl.bind("SUPER + SHIFT + A", strip("colresize all 0.5"), { description = "Reset column widths" })

-- Tiling windows
hl.bind("ALT + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + T", hl.dsp.group.toggle())
hl.bind("ALT + SHIFT + T", hl.dsp.window.float({ action = "disable" }))

-- Center window to the middle of the screen, when tiled
hl.bind("ALT + C", function()
    local win = hl.get_active_window()
    if win and not win.floating and on_strip() then
        hl.dispatch(hl.dsp.layout("center"))
    else
        hl.dispatch(hl.dsp.window.center())
    end
end)

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

-- The HUD's stack overview (quickshell hud, Overview.qml).
local OVERVIEW_NAMESPACE = "hud-overview"

local function overview_open()
    return #hl.get_layers({ namespace = OVERVIEW_NAMESPACE }) > 0
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

-- ALT + Tab is the HUD's stack overview, on every layout: the view draws
-- back from the window that has the focus, which stays in the middle and in
-- use, to show what is around it, the rest of its workspace and the
-- workspaces above and below. It follows the focus; the same key goes back
-- in. Noctalia's carousel of every window when the HUD is not running
-- (classic theme).
hl.bind("ALT + Tab", hl.dsp.exec_cmd("qs -c hud ipc call overview toggle || noctalia msg window-switcher all"), { description = "Overview of workspaces and windows" })

hl.bind("ALT + SHIFT + Tab", function()
    if not switcher_open() then
        switch_window(false)
    end
end, { non_consuming = true })

-- --- Window Navigation (Vim-style) ---
hl.bind("SUPER + J", function()
    if on_strip() then
        hl.dispatch(hl.dsp.layout("consume_or_expel prev"))
    elseif hl.get_config("general.layout") == "dwindle" then
        hl.dispatch(hl.dsp.layout("togglesplit"))
    end
end)

-- Close window
hl.bind("ALT + SHIFT + q", hl.dsp.window.close())

-- Lock screen: the HUD closes its glass doors over the desktop first, then
-- locks (hud/.local/bin/hud-lock; a plain `noctalia msg session lock` skips the animation)
hl.bind("SUPER + l", hl.dsp.exec_cmd("$HOME/.local/bin/hud-lock"))  -- Hyprland's PATH has no ~/.local/bin

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
        -- On the strip a sideways move would drop the window into the column
        -- next to it. Swap the two columns instead: stacking is SUPER + J's.
        if dy == 0 and on_strip() then
            hl.dispatch(hl.dsp.layout("swapcol " .. direction))
            return
        end
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
local function move_vertical(down)
    if hl.get_active_window() and leaves_strip(down) then
        hl.dispatch(hl.dsp.window.move({ workspace = stack_workspace(down) }))
    else
        move_window(0, down and FLOAT_STEP or -FLOAT_STEP, down and "d" or "u")
    end
end

hl.bind("ALT + SHIFT + k", function() move_vertical(false) end, { repeating = true })
hl.bind("ALT + SHIFT + j", function() move_vertical(true) end, { repeating = true })

-- --- Mouse: move and resize ---
-- SUPER rather than ALT, the keyboard's window modifier: apps use Alt+click
-- themselves (ghostty moves the prompt cursor, Vivaldi saves links), nothing
-- uses Super+click. Works anywhere on the window, no need to aim for an edge.
--   SUPER + left drag    move (a tiled window is re-tiled where it is dropped)
--   SUPER + right drag   resize from the corner nearest the cursor
--   SUPER + SHIFT + left drag   resize too: a right-button drag is awkward on
--                               the touchpad
-- Without a modifier, dragging a window border or the gap next to it resizes
-- (general.resize_on_border in input.lua).
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })
hl.bind("ALT + SHIFT + mouse:272", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Move focus with ALT + HJKL
-- Next to a maximized window the plain focus dispatcher does nothing: it
-- only looks for a neighbour on screen, and the window covers the screen.
-- The strip's own message knows the columns beside it, so sideways steps
-- keep scrolling the strip, past the maximized column like any other.
local function focus_sideways(direction)
    local ws = hl.get_active_workspace()
    local win = hl.get_active_window()
    if on_strip() and ws.has_fullscreen and win and not win.floating then
        hl.dispatch(hl.dsp.layout("focus " .. direction))
    else
        hl.dispatch(hl.dsp.focus({ direction = direction }))
    end
end

hl.bind("ALT + h", function() focus_sideways("l") end)
hl.bind("ALT + l", function() focus_sideways("r") end)
-- The stack overview (ALT + Tab) shows the workspaces that have windows as
-- rows above each other, whatever their layout. While it is up, ALT + J/K
-- past the bottom or top window goes to the row below or above on every
-- layout, not only on a strip, and skips the empty workspaces between,
-- which have no row.
local function overview_row(down)
    local ws = hl.get_active_workspace()
    if not ws or not ws.monitor then
        return nil
    end
    local best
    for _, other in ipairs(hl.get_workspaces()) do
        if other.id > 0 and other.windows > 0 and other.monitor and other.monitor.name == ws.monitor.name then
            if down and other.id > ws.id and (not best or other.id < best)
                or not down and other.id < ws.id and (not best or other.id > best) then
                best = other.id
            end
        end
    end
    return best
end

local function focus_vertical(down)
    local win = hl.get_active_window()
    if overview_open() and (not win or (not win.floating and not column_neighbour(win, down))) then
        local row = overview_row(down)
        if row then
            hl.dispatch(hl.dsp.focus({ workspace = tostring(row) }))
        end
        return
    end
    if leaves_strip(down) then
        hl.dispatch(hl.dsp.focus({ workspace = stack_workspace(down) }))
    else
        hl.dispatch(hl.dsp.focus({ direction = down and "d" or "u" }))
    end
end

hl.bind("ALT + k", function() focus_vertical(false) end)
hl.bind("ALT + j", function() focus_vertical(true) end)

-- --- Application shortcuts ---
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd(terminal .. " -e btop"), { description = "Activity" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"))
hl.bind("ALT + SHIFT + O", hl.dsp.exec_cmd("obsidian"), { description = "Obsidian" })
hl.bind("ALT + SHIFT + B", hl.dsp.exec_cmd(browser), { description = "Browser" })
hl.bind("ALT + RETURN", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind("ALT + SHIFT + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"), { description = "Docker" })
hl.bind("ALT + SHIFT + P", hl.dsp.exec_cmd("sioyek"), { description = "PDF reader" })

hl.bind("SUPER + W", hl.dsp.exec_cmd("noctalia msg panel-toggle wallpaper"))
hl.bind("SUPER + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"), { description = "Clipboard history" })
-- The HUD's glass pill launcher (quickshell hud, Launcher.qml); Noctalia's own
-- when the HUD is not running (classic theme).
hl.bind("ALT + SPACE", hl.dsp.exec_cmd("qs -c hud ipc call launcher toggle || noctalia msg panel-toggle launcher"), { description = "Launch apps" })

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))

-- --- Media keys ---
-- hud-osd changes the level and shows a toast for it; Noctalia's own
-- volume/brightness OSDs are off so the control-center sliders stay quiet.
-- All of these also work on the lock screen.
local osd = "$HOME/.local/bin/hud-osd " -- Hyprland's PATH has no ~/.local/bin
local held = { repeating = true, locked = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(osd .. "vol up"), held)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(osd .. "vol down"), held)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(osd .. "vol mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(osd .. "mic mute"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(osd .. "lum up"), held)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(osd .. "lum down"), held)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("noctalia msg media toggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("noctalia msg media next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("noctalia msg media previous"), { locked = true })
