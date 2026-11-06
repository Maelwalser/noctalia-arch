--!nonstrict
-- Rotating HUD ring; a click toggles the Quickshell desktop overlay (manifest action).
-- hud-build renders the frames at device resolution per output scale
-- (bar/spinner/<scale>), so the set is picked once this output's scale is known.
local common = require("./common.luau")

local dir = nil -- this output's frame set, resolved asynchronously
local frames = 0
local frame = 0
local resolving = false

local function resolve()
  if resolving then
    return
  end
  resolving = true
  common.outputScale(function(sc)
    dir = common.scaledDir("spinner", sc, "00.png")
    frames = common.countFramesIn(dir)
    resolving = false
  end)
end

function update()
  local animate = noctalia.getConfig("animate") ~= false
  if frames == 0 then
    resolve()
    if dir == nil then
      noctalia.setUpdateInterval(250) -- the scale lookup is still running
    else
      -- hud-build may not have run yet when the bar starts: keep checking.
      common.missing()
      noctalia.setUpdateInterval(5000)
    end
    return
  end
  noctalia.setUpdateInterval(animate and 120 or 60000)
  if animate then
    frame = (frame + 1) % frames
  end
  -- A rebuild swaps the frame directory: skip a tick rather than render a gap.
  if not noctalia.fileExists(common.frameIn(dir, frame)) then
    return
  end
  barWidget.render(ui.image({
    path = common.frameIn(dir, frame),
    width = 18,
    height = 18,
    fit = "contain",
  }))
end

barWidget.setTooltip("HUD overlay · click to toggle")
