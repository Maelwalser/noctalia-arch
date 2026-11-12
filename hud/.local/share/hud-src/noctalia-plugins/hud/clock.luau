--!nonstrict
-- Clock panel: the acid tag and the time in one pill; the time glows on hover
-- (common.glow; the built-in clock can only take the bar's background
-- highlight). The click is a manifest action.
local common = require("./common.luau")

local hovered = false
local drawn = nil -- "<time>|<hovered>" of the last render

local function render()
  local time = noctalia.formatTime(noctalia.getConfig("format") or "{:%H:%M}")
  local key = time .. "|" .. tostring(hovered)
  if key == drawn then
    return
  end
  drawn = key
  barWidget.render(common.pill({
    common.glow(hovered, function()
      return ui.label({ text = time, fontFamily = common.monoFont(), fontSize = 14, color = "on_surface", baseline = "inkCentered" })
    end),
  }, true))
  common.tip(noctalia.formatTime(noctalia.getConfig("tooltip_format") or "{:%A %d %B %Y}"))
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end

function update()
  -- Cheap enough to check every second; only a new minute redraws.
  noctalia.setUpdateInterval(1000)
  render()
end
