-- Workspace 1 lives on the laptop panel; 2-10 live on the external monitor.
-- The external monitor's connector name changes with the cable/adapter
-- (DP-2, DP-4, ...), so it is looked up at runtime instead of hardcoded, and
-- the layout is re-applied whenever a monitor is plugged in or removed.

local LAPTOP = "eDP-1"
local LAST_WORKSPACE = 10 -- matches the ALT + [1-0] binds in bindings.lua

local function external_monitor()
    for _, mon in ipairs(hl.get_monitors()) do
        if mon.name ~= LAPTOP then
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
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id >= 1 and ws.id <= LAST_WORKSPACE then
            local target = target_monitor(ws.id, external)
            if ws.monitor and ws.monitor.name ~= target then
                hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(ws.id), monitor = target }))
            end
        end
    end
end

apply_layout()
hl.on("monitor.added", apply_layout)
hl.on("monitor.removed", apply_layout)
