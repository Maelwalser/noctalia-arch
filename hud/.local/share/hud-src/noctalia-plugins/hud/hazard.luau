--!nonstrict
-- Crawling hazard tape: hud-build renders the stripe pattern shifted by one step
-- per frame; cycling them makes the tape scroll slowly.
local common = require("./common.luau")

local frame = 0
local frames = common.countFrames("hazard")

function update()
  local animate = noctalia.getConfig("animate") ~= false
  local length = noctalia.getConfig("length") or 56
  if frames == 0 then
    -- hud-build may not have run yet when the bar starts: keep checking.
    frames = common.countFrames("hazard")
    if frames == 0 then
      common.missing()
      noctalia.setUpdateInterval(5000)
      return
    end
  end
  noctalia.setUpdateInterval(animate and 140 or 60000)
  if animate then
    frame = (frame + 1) % frames
  end
  -- A rebuild swaps the frame directory: skip a tick rather than render a gap.
  if not noctalia.fileExists(common.framePath("hazard", frame)) then
    return
  end
  barWidget.render(ui.image({
    path = common.framePath("hazard", frame),
    width = length,
    height = 10,
    fit = "stretch",
  }))
end
