--!nonstrict
local common = require("./common.luau")

-- "<USER>//HUD": the login name, upper-cased, as on the wallpaper and lockscreen.
local tag = string.upper(noctalia.getenv("USER") or "user") .. "//HUD"

local hovered = false

local function render()
  local path = common.dir .. "/emblem.png"
  if not noctalia.fileExists(path) then
    common.missing()
    return
  end
  barWidget.render(common.bare({
    common.glow(hovered, function()
      -- The 1 px under the image keeps it on the pixel row it had beside the
      -- label before the glow layers centred it by themselves.
      return ui.column({}, {
        ui.image({ path = path, width = 16, height = 14, fit = "contain" }),
        common.space(1, 1),
      })
    end),
    common.glow(hovered, function()
      return ui.label({ text = tag, color = "primary", fontFamily = common.monoFont(), fontSize = 13, baseline = "inkCentered" })
    end),
  }, 6))
  common.tip(tag .. " · click: launcher")
end

function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end
