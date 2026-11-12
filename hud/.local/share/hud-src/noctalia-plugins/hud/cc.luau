--!nonstrict
-- Control-centre button: the corner-brackets glyph (hud-build) in its own pill.
-- Replaces the built-in button, which can only take the bar's background
-- highlight: this one glows on hover like the readouts. Clicks are manifest
-- actions.
local common = require("./common.luau")

local path = common.dir .. "/control-center.png"
local hovered = false

local function render()
  if not noctalia.fileExists(path) then
    common.missing()
    return
  end
  barWidget.render(common.pill({
    common.glow(hovered, function()
      return ui.image({ path = path, width = 16, height = 16, fit = "contain" })
    end),
  }, false))
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end

function update()
  -- hud-build may not have run yet when the bar starts: keep checking.
  noctalia.setUpdateInterval(if noctalia.fileExists(path) then 600000 else 5000)
  render()
end

common.tip("Control centre")
