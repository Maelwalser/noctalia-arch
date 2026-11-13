-- Application bindings
local terminal = "ghostty"
local browser = "vivaldi-stable --new-window"

-- --- Workspace management ---
-- Bind Alt + [Number] to switch to workspace (1-10)
-- Bind Alt + Shift + [Number] to move active window to workspace (1-10)
local take_to -- the move, with the widths looked after (defined with the strip binds below)
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("ALT + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind("ALT + SHIFT + " .. key, function() take_to(i) end)
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
    -- Kept for the next config reload, which would otherwise fall back to
    -- the default layout (looknfeel.lua reads it).
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-layout", "w")
    if f then
        f:write(name)
        f:close()
    end
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
--   ALT + C         centre the column (a floating window: centre it, as before);
--                   in the work view: keep the focused window mid-screen, or not
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
-- On the strip that is a column the width of the screen, not Hyprland's
-- maximize: maximize takes the window out of the strip and hides the columns
-- beside it until one of them is focused, so in the zoomed-out view
-- (ALT + Tab) they were gone. A full-width column stays in the strip and
-- pushes its neighbours out to the sides, where the view shows them.
-- The strip is slid so that the wide column starts at the left edge.
-- Shrinking it again leaves it there, which is where a left-hand column came
-- from; a column that sat further right would end up on the wrong side with
-- a hole beside it. So the place it was widened from is kept and the strip
-- slid back to it, in the same step as the resize: the edge it grew from is
-- the one that comes back in.
local widened_from = {} -- window address -> { x = where it was, width = share of the screen it had }
local COLUMN_WIDTHS = { 1 / 3, 0.5, 2 / 3 } -- the widths SUPER + R steps through, less the full one

-- (fills_screen, further down, also counts a maximized window.)
local function column_share(win)
    local mon = hl.get_active_workspace().monitor
    return mon and win.size.x / (mon.width / mon.scale) or 0.5
end

local function nearest_width(share)
    local best = COLUMN_WIDTHS[1]
    for _, width in ipairs(COLUMN_WIDTHS) do
        if math.abs(width - share) < math.abs(best - share) then
            best = width
        end
    end
    return best
end

hl.bind("ALT + F", function()
    local win = hl.get_active_window()
    -- A window that is maximized already (from another layout) is let go the same way.
    if not win or win.floating or not on_strip() or win.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" }))
        return
    end
    if column_share(win) <= 0.9 then
        widened_from[win.address] = { x = win.at.x, width = nearest_width(column_share(win)) }
        hl.dispatch(hl.dsp.layout("colresize 1.0"))
        return
    end
    local from = widened_from[win.address]
    widened_from[win.address] = nil
    hl.dispatch(hl.dsp.layout("colresize " .. (from and from.width or 0.5)))
    -- `at` is already the place the window is heading for.
    win = hl.get_active_window()
    if from and win and from.x > win.at.x then
        hl.dispatch(hl.dsp.layout("move +" .. math.floor(from.x - win.at.x)))
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

-- Center window to the middle of the screen, when tiled. In the zoomed-out
-- work view (ALT + Tab) it switches the view's centred mode instead: the
-- camera keeps the focused window in the middle of the screen, and on the
-- same key goes back to showing as much of the rows as it can.
hl.bind("ALT + C", function()
    local view = hl.plugin.stackzoom
    if view and view.centred and view.active() then
        view.centred()
        return
    end
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

-- ALT + Tab on the scrolling layout zooms out: the stackzoom plugin
-- (plugins.lua) draws every workspace of the monitor as a row at half size,
-- the rows centred over one another. They are the real windows and take the
-- mouse and the keyboard as ever; nothing is resized and the bar stays as it
-- is. The same key goes back. Where the plugin cannot (not built for this
-- Hyprland, a window in real fullscreen) it is the HUD's stack overview
-- (quickshell hud, Overview.qml): pictures of every workspace of the monitor
-- in rows, to look around and jump with. ALT + CTRL + Tab is that overview
-- always. Noctalia's carousel of every window when the HUD is not running
-- (classic theme).
--
-- On the other layouts a workspace is one screen and there are no strips to
-- look along: there ALT + Tab is Noctalia's carousel of the windows of this
-- workspace, held open with ALT and stepped through with Tab, and only when
-- some of them cover others.
local OVERVIEW_CMD = "qs -c hud ipc call overview toggle || noctalia msg window-switcher all"

hl.bind("ALT + Tab", function()
    local view = hl.plugin.stackzoom
    if not on_strip() then
        -- One left open from the strip has no rows to show here.
        if view and view.active() then
            view.close()
        end
        -- Only where there is something out of sight to switch to: windows
        -- lying over each other (two maximized ones, say). Tiled side by
        -- side they are all on the screen already. Sent on every Tab: the
        -- first opens the carousel, each further one while ALT is held
        -- steps it (the bind swallows the key, so the overlay never sees
        -- Tab itself).
        local ws = hl.get_active_workspace()
        if ws and ws.windows > 1 and (ws.has_fullscreen or has_overlapping_windows(ws)) then
            hl.exec_cmd("noctalia msg window-switcher hold workspace")
        end
        return
    end
    if overview_open() or not (view and view.toggle()) then
        hl.exec_cmd(OVERVIEW_CMD)
    end
end, { description = "Strips: zoom out to every workspace, and back. Elsewhere: carousel of this workspace's windows" })
hl.bind("ALT + CTRL + Tab", hl.dsp.exec_cmd(OVERVIEW_CMD), { description = "Overview of workspaces and windows" })

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
-- A window that fills the screen (maximized, a column of the full width, or
-- the only window of its strip) and is taken to another strip stays that
-- size. Left to itself the strip gives a newcomer the default width, so it
-- would arrive as half a screen beside one of the windows already there, and
-- puts it at the end. It is also set between them, as many columns on its left as on its right, so
-- that what was there goes out to both sides and the strip stays centred on
-- the screen.
local function fills_screen(win)
    local mon = hl.get_active_workspace().monitor
    return win.fullscreen ~= 0 or (mon ~= nil and win.size.x > 0.9 * mon.width / mon.scale)
end

-- Every tiled window of the monitor's workspaces that fills the screen now,
-- by address. A window that is alone on its strip does (looknfeel.lua,
-- fullscreen_on_one_column) without having been given that width, so the
-- strip takes it back to half a screen the moment a second window arrives.
local function filling_windows()
    local ws = hl.get_active_workspace()
    local filling = {}
    if not ws or not ws.monitor then
        return filling
    end
    for _, other in ipairs(hl.get_workspaces()) do
        if (other.id or 0) > 0 and other.monitor and other.monitor.name == ws.monitor.name then
            for _, win in ipairs(hl.get_workspace_windows(other.id)) do
                if not win.hidden and not win.floating and fills_screen(win) then
                    filling[win.address] = true
                end
            end
        end
    end
    return filling
end

-- After a window has been taken to another strip: whatever filled the screen
-- before, the newcomer or the windows it joins, still does. Nothing is cut
-- down to half a screen by an arrival; the wide columns lie side by side and
-- the strip runs on past the edge.
local function settle_arrival(address, filling)
    local win = hl.get_active_window()
    if not win or win.address ~= address or win.floating or not on_strip() then
        return
    end
    -- A column is resized through the focus: each one in turn, then back.
    local visited = false
    for _, other in ipairs(hl.get_workspace_windows(hl.get_active_workspace().id)) do
        if other.address ~= address and filling[other.address] and not other.hidden
            and not other.floating and not fills_screen(other) then
            hl.dispatch(hl.dsp.focus({ window = other }))
            hl.dispatch(hl.dsp.layout("colresize 1.0"))
            visited = true
        end
    end
    if visited then
        hl.dispatch(hl.dsp.focus({ window = win }))
        win = hl.get_active_window()
        if not win or win.address ~= address then
            return
        end
    end
    if not filling[address] then
        return
    end
    if not fills_screen(win) then
        hl.dispatch(hl.dsp.layout("colresize 1.0"))
        -- `at` and `size` are already where the windows are heading.
        win = hl.get_active_window()
    end
    local left, right = {}, {}
    for _, other in ipairs(hl.get_workspace_windows(hl.get_active_workspace().id)) do
        if other.address ~= win.address and not other.hidden and not other.floating then
            if other.at.x < win.at.x then
                left[other.at.x] = true
            elseif other.at.x > win.at.x then
                right[other.at.x] = true
            end
        end
    end
    local balance = 0
    for _ in pairs(left) do balance = balance + 1 end
    for _ in pairs(right) do balance = balance - 1 end
    local direction = balance > 0 and "l" or "r"
    for _ = 1, math.floor(math.abs(balance) / 2) do
        hl.dispatch(hl.dsp.layout("swapcol " .. direction))
    end
end

-- Takes the focused window to another workspace (a number, or r+1 / r-1).
take_to = function(workspace)
    local win = hl.get_active_window()
    if not win then
        return
    end
    local filling = on_strip() and filling_windows() or {}
    hl.dispatch(hl.dsp.window.move({ workspace = workspace }))
    settle_arrival(win.address, filling)
end

-- The same for a window that opens while the zoomed-out view (ALT + Tab) is
-- up: there the strips are laid out to be looked at, a browser the width of
-- the screen with the terminals beside or under it, and a new terminal must
-- not cut the browser down to half. (At the desktop a second window still
-- shares the screen with the first, as ever.)
-- `window.open_early` comes before the layout has taken the newcomer in, so
-- the windows of its workspace still have the sizes they are to keep.
local opening = {} -- address of a window being opened -> what filled the screen on its workspace
hl.on("window.open_early", function(win)
    local ws = win.workspace
    local mon = ws and ws.monitor
    local view = hl.plugin.stackzoom
    if not mon or not (view and view.active(mon.name)) then
        return
    end
    local filling = {}
    for _, other in ipairs(hl.get_workspace_windows(ws.id)) do
        if not other.hidden and not other.floating and other.size.x > 0.9 * mon.width / mon.scale then
            filling[other.address] = true
        end
    end
    opening[win.address] = filling
end)
hl.on("window.open", function(win)
    local filling = opening[win.address]
    opening[win.address] = nil
    if filling and next(filling) then
        settle_arrival(win.address, filling)
    end
end)
hl.on("window.destroy", function(win)
    opening[win.address] = nil -- one that never got as far as opening
end)

-- Hyprland's "Application Not Responding" dialog: what the client that
-- stopped answering was doing is written down while it still hangs
-- (~/.cache/hypr-anr/), since afterwards there is nothing left to ask.
hl.on("window.open", function(win)
    if win.class == "hyprland-dialog" then
        hl.exec_cmd("$HOME/.local/bin/hypr-anr-dump")
    end
end)

local function move_vertical(down)
    if hl.get_active_window() and leaves_strip(down) then
        take_to(stack_workspace(down))
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
-- Next to a window that fills the screen (a full-width column, or a
-- maximized one) the plain focus dispatcher does nothing: it only looks for
-- a neighbour on screen, and the window covers the screen.
-- The strip's own message knows the columns beside it, so sideways steps
-- keep scrolling the strip, past the maximized column like any other.
local function focus_sideways(direction)
    local ws = hl.get_active_workspace()
    local win = hl.get_active_window()
    if on_strip() and win and not win.floating and (ws.has_fullscreen or column_share(win) > 0.9) then
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
        if (other.id or 0) > 0 and other.windows > 0 and other.monitor and other.monitor.name == ws.monitor.name then
            if down and other.id > ws.id and (not best or other.id < best)
                or not down and other.id < ws.id and (not best or other.id > best) then
                best = other.id
            end
        end
    end
    return best
end

-- Whether a step up or down from `win` finds a window on its own workspace.
-- A tiled one looks along its column. A floating one has no column: any
-- window that lies further that way counts. A maximized one covers the rest,
-- floating or not, so there is nothing to step to.
local function vertical_neighbour(win, down)
    if win.fullscreen ~= 0 then
        return false
    end
    if not win.floating then
        return column_neighbour(win, down)
    end
    local mid = win.at.y + win.size.y / 2
    for _, other in ipairs(hl.get_workspace_windows(hl.get_active_workspace().id)) do
        if other.address ~= win.address and not other.hidden then
            local other_mid = other.at.y + other.size.y / 2
            if down and other_mid > mid or not down and other_mid < mid then
                return true
            end
        end
    end
    return false
end

-- How far a strip is shifted sideways for its columns to be centred on the
-- screen, which is how the strips lie over one another (stackzoom's rows).
local function strip_shift(windows, mon)
    local left, right
    for _, win in ipairs(windows) do
        if not win.hidden and not win.floating and win.fullscreen == 0 then
            left = math.min(left or win.at.x, win.at.x)
            right = math.max(right or win.at.x + win.size.x, win.at.x + win.size.x)
        end
    end
    if not left then
        return 0
    end
    return mon.x + mon.width / mon.scale / 2 - (left + right) / 2
end

-- The window of workspace `id` that lies straight below (or above) `win`:
-- the nearest sideways, and of those the first one met going that way.
--
-- Centred strips often leave no single answer: a window of a strip of two
-- sits exactly over the gap between two windows of a strip of three, as far
-- from the one as from the other. Windows within a gap's width of the
-- nearest count as equally near, and of those it is the one the last step
-- came from (so up and down again ends where it started), else the one
-- that had the focus most recently.
local LEVEL = 2 * (require("motion").GAPS_IN + 4) -- the gap between two columns, borders included
local last_step = {} -- from = address the last step across left, to = address it landed on

local function window_across(win, id, down)
    local mon = hl.get_active_workspace().monitor
    if not mon then
        return nil
    end
    local mid = mon.x + mon.width / mon.scale / 2
    if win then
        mid = win.at.x + win.size.x / 2 + strip_shift(hl.get_workspace_windows(hl.get_active_workspace().id), mon)
    end
    local there = hl.get_workspace_windows(id)
    local shift = strip_shift(there, mon)
    local candidates, other_off, nearest = {}, {}, nil
    for _, other in ipairs(there) do
        if not other.hidden then
            -- One that covers the others is the only one to land on.
            if other.fullscreen ~= 0 then
                return other
            end
            local l, r = other.at.x + shift, other.at.x + other.size.x + shift
            other_off[other.address] = mid < l and l - mid or mid > r and mid - r or 0
            nearest = math.min(nearest or other_off[other.address], other_off[other.address])
            candidates[#candidates + 1] = other
        end
    end
    local back = win and last_step.to == win.address and last_step.from
    local best, best_rank
    for _, other in ipairs(candidates) do
        if other_off[other.address] <= nearest + LEVEL then
            -- The way back first, then the latest focus, then the first met going that way.
            local rank = (other.address == back and 0 or 1) * 1e9
                + (other.focus_history_id or 0) * 1e4
                + (down and other.at.y or -(other.at.y + other.size.y))
            if not best or rank < best_rank then
                best, best_rank = other, rank
            end
        end
    end
    return best
end

-- With nothing further that way on the workspace the step goes to the next
-- one. That holds for a floating window too: one that was alone on its
-- workspace (a maximized browser, say) used to be a dead end, the direction
-- focus finding nothing and the workspace step being left to tiled windows.
local function focus_vertical(down)
    local win = hl.get_active_window()
    local leaves = not win or not vertical_neighbour(win, down)
    if overview_open() and leaves then
        local row = overview_row(down)
        if row then
            hl.dispatch(hl.dsp.focus({ workspace = tostring(row) }))
        end
        return
    end
    if leaves and on_strip() then
        -- The strips lie centred over one another (the zoomed-out view,
        -- ALT + Tab, shows them so): the step lands on the window straight
        -- above or below, not on the one that workspace had focused last.
        -- Past the last strip with windows it is the free one beyond.
        local row = overview_row(down)
        local across = row and window_across(win, row, down)
        if across then
            last_step = { from = win and win.address, to = across.address }
            hl.dispatch(hl.dsp.focus({ window = across }))
        else
            hl.dispatch(hl.dsp.focus({ workspace = stack_workspace(down) }))
        end
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

-- Region screenshot to the clipboard: hud-shot (hud/.local/bin) gives slurp
-- the palette's colours and confirms the copy with a toast.
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("$HOME/.local/bin/hud-shot"), { description = "Screenshot region" })

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
