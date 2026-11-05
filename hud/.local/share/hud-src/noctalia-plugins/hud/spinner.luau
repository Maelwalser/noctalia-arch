--!nonstrict
-- Rotating HUD ring; a click toggles the Quickshell desktop overlay (manifest action).
local common = require("./common.luau")

local frame = 0
local frames = common.countFrames("spinner")

function update()
  local animate = noctalia.getConfig("animate") ~= false
  if frames == 0 then
    -- hud-build may not have run yet when the bar starts: keep checking.
    frames = common.countFrames("spinner")
    if frames == 0 then
      common.missing()
      noctalia.setUpdateInterval(5000)
      return
    end
  end
  noctalia.setUpdateInterval(animate and 120 or 60000)
  if animate then
    frame = (frame + 1) % frames
  end
  -- A rebuild swaps the frame directory: skip a tick rather than render a gap.
  if not noctalia.fileExists(common.framePath("spinner", frame)) then
    return
  end
  barWidget.render(ui.image({
    path = common.framePath("spinner", frame),
    width = 18,
    height = 18,
    fit = "contain",
  }))
end

barWidget.setTooltip("HUD overlay · click to toggle")
