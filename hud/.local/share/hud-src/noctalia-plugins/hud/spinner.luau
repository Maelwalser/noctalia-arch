--!nonstrict
-- Rotating HUD ring, glowing on hover; a click toggles the Quickshell desktop overlay (manifest action).
-- hud-build renders the frames at device resolution per output scale
-- (bar/spinner/<scale>), so the set is picked once this output's scale is known.
local common = require("./common.luau")

local dir = nil -- this output's frame set, resolved asynchronously
local frames = 0
local frame = 0
local drawn = nil -- "<frame>|<hovered>" on screen
local hovered = false

local function key()
  return frame .. "|" .. tostring(hovered)
end

local function draw()
  -- A rebuild swaps the frame directory: skip a tick rather than render a gap.
  if frames == 0 or not noctalia.fileExists(common.frameIn(dir, frame)) then
    return
  end
  local path = common.frameIn(dir, frame)
  barWidget.render(common.bare({
    common.glow(hovered, function()
      return ui.image({ path = path, width = 18, height = 18, fit = "contain" })
    end),
  }))
  drawn = key()
end
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
  if not animate then
    noctalia.setUpdateInterval(60000)
  elseif common.overlayOn() then
    noctalia.setUpdateInterval(120)
    frame = (frame + 1) % frames
  else
    -- Overlay off: the ring rests where it stopped. The state is one small
    -- file, so keep looking often enough that a click starts it promptly.
    noctalia.setUpdateInterval(250)
    if drawn == key() then
      return
    end
  end
  draw()
end

common.tip("HUD overlay · click to toggle")

function onHover(inside)
  hovered = inside
  common.hover(inside)
  draw()
end
