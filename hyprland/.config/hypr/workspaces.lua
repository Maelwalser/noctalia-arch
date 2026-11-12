-- Workspace 1 lives on the laptop panel; 2-10 live on the external monitor.
-- The external monitor's connector name changes with the cable/adapter
-- (DP-2, DP-4, ...), so it is looked up at runtime instead of hardcoded, and
-- the layout is re-applied whenever a monitor is plugged in or removed.

local LAPTOP = "eDP-1"
local LAST_WORKSPACE = 10 -- matches the ALT + [1-0] binds in bindings.lua

-- Virtual outputs made by `hyprctl output create headless` (claude-shot uses
-- one named CLAUDE to screenshot apps off-screen). They never count as the
-- external monitor, or plugging one in would drag workspaces 2-10 onto it.
local function is_headless(name)
    return name:sub(1, 6) == "CLAUDE" or name:sub(1, 9) == "HEADLESS-"
end

local function external_monitor()
    for _, mon in ipairs(hl.get_monitors()) do
        if mon.name ~= LAPTOP and not is_headless(mon.name) then
            return mon.name
        end
    end
    return nil
end

local function target_monitor(id, external)
    if id == 1 or not external then
        return LAPTOP
    end
    return external
end

local function apply_layout()
    local external = external_monitor()

    for id = 1, LAST_WORKSPACE do
        hl.workspace_rule({
            workspace = tostring(id),
            monitor = target_monitor(id, external),
            default = id == 1 or id == 2,
        })
    end

    -- Rules only place workspaces when they are created, so move the ones
    -- that already exist (e.g. after hot-plugging the external monitor).
    -- Named workspaces (claude-shot's "claude", special ones) have no
    -- numeric id and are left where they are.
    for _, ws in ipairs(hl.get_workspaces()) do
        if type(ws.id) == "number" and ws.id >= 1 and ws.id <= LAST_WORKSPACE then
            local target = target_monitor(ws.id, external)
            if ws.monitor and ws.monitor.name ~= target then
                hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(ws.id), monitor = target }))
            end
        end
    end
end

-- A headless output must not lie next to a real one: ALT + H/L at the end of
-- a workspace would cross onto it, and the focus would be on a screen nobody
-- sees (the window just left looks deselected, the next terminal opens out
-- of sight). An output without a monitor rule is placed right beside the
-- laptop panel, and a reload drops the rules made at runtime, which is how
-- claude-shot places its own. So every headless output is given a rule here,
-- on each load and whenever one appears: as it is now, mode and scale
-- included, but far off to the right if it is anywhere near.
local HIDDEN_X = 20000 -- logical px; real outputs end long before
local HIDDEN_PITCH = 6000

local function park_headless()
    local free = HIDDEN_X
    local near = {}
    for _, mon in ipairs(hl.get_monitors()) do
        if is_headless(mon.name) then
            if mon.x >= HIDDEN_X then
                free = math.max(free, mon.x + HIDDEN_PITCH)
                near[#near + 1] = { mon = mon, x = mon.x, y = mon.y }
            else
                near[#near + 1] = { mon = mon }
            end
        end
    end
    for _, slot in ipairs(near) do
        local mon = slot.mon
        if not slot.x then
            slot.x, slot.y = free, 0
            free = free + HIDDEN_PITCH
        end
        hl.monitor({
            output = mon.name,
            mode = string.format("%dx%d@%.2f", mon.width, mon.height, mon.refresh_rate),
            position = string.format("%dx%d", slot.x, slot.y),
            scale = mon.scale,
        })
    end
end

local function on_monitors_changed()
    park_headless()
    apply_layout()
end

park_headless()
apply_layout()
hl.on("monitor.added", on_monitors_changed)
hl.on("monitor.removed", apply_layout)
