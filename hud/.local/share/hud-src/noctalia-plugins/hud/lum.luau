--!nonstrict
-- Backlight readout: outlined sun (hud-build icon) and level, read from sysfs. Hidden on
-- machines without a backlight. Scroll/click are manifest actions.
local common = require("./common.luau")

local function device()
  local entries = noctalia.listDir("/sys/class/backlight")
  if entries and #entries > 0 then
    table.sort(entries)
    return "/sys/class/backlight/" .. entries[1]
  end
  return nil
end

local dev = device()
local last = -1

-- Re-render with this output's icon set once its scale is known.
common.resolveIcons(function()
  last = -1
end)

function update()
  noctalia.setUpdateInterval(1000)
  if not common.hasAssets() then
    common.missing()
    return
  end
  if dev == nil then
    barWidget.setVisible(false)
    noctalia.setUpdateInterval(60000)
    return
  end
  local cur = tonumber(noctalia.readFile(dev .. "/brightness") or "")
  local max = tonumber(noctalia.readFile(dev .. "/max_brightness") or "")
  if not cur or not max or max <= 0 then
    return
  end
  local pct = math.floor(cur / max * 100 + 0.5)
  if pct == last then
    return
  end
  last = pct
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.image({ path = common.icon("lum"), width = 18, height = 18, fit = "contain" }),
    common.readout(string.format("%03d", pct), "on_surface"),
  }))
  barWidget.setTooltip(string.format("Brightness: %d%%", pct))
end
