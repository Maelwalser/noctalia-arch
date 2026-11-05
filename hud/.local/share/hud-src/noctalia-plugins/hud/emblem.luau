--!nonstrict
local common = require("./common.luau")

-- "<USER>//HUD": the login name, upper-cased, as on the wallpaper and lockscreen.
local tag = string.upper(noctalia.getenv("USER") or "user") .. "//HUD"

local function render()
  local path = common.dir .. "/emblem.png"
  if not noctalia.fileExists(path) then
    common.missing()
    return
  end
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.image({ path = path, width = 16, height = 14, fit = "contain" }),
    ui.label({ text = tag, color = "primary", fontFamily = common.monoFont(), fontSize = 13, baseline = "inkCentered" }),
  }))
  barWidget.setTooltip(tag .. " · click: launcher")
end

function update()
  noctalia.setUpdateInterval(60000)
  render()
end
