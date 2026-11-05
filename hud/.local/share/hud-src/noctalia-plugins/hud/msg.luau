--!nonstrict
-- Notification readout: pixel bell, dimmed with a red DND tag while Do Not
-- Disturb is on. Left click opens the history (manifest); right click toggles DND.
local common = require("./common.luau")

local dnd = nil

local function render()
  if not common.hasAssets() then
    common.missing()
    return
  end
  if dnd == nil then
    return
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.image({ path = common.icon(if dnd then "bell-off" else "bell"), width = 18, height = 18, fit = "contain" }),
    common.readout(if dnd then "DND" else "MSG", if dnd then "error" else "on_surface"),
  }))
  barWidget.setTooltip(if dnd then "Do Not Disturb · right click: off" else "Notifications · right click: Do Not Disturb")
end

local refresh = common.coalesced({ "noctalia", "msg", "notification-dnd-status" }, function(r)
  if r.exitCode == 0 then
    dnd = string.match(r.stdout, "^%s*on%f[%W]") ~= nil
    render()
  end
end)

function onRightClick()
  noctalia.runAsync({ "noctalia", "msg", "notification-dnd-toggle" }, function()
    refresh()
  end, 3000)
end

function update()
  -- No IPC event for DND changes made elsewhere, so poll gently.
  noctalia.setUpdateInterval(5000)
  refresh()
end
