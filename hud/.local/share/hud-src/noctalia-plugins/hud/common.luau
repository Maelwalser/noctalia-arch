--!nonstrict
-- Shared helpers for the HUD bar widgets.
local M = {}

M.dir = "~/.local/share/hud/bar"

-- Frame files are named 00.png, 01.png, ... by hud-build.
function M.frameIn(dir, i)
  return string.format("%s/%02d.png", dir, i)
end

function M.framePath(set, i)
  return M.frameIn(M.dir .. "/" .. set, i)
end

function M.countFramesIn(dir)
  local n = 0
  while noctalia.fileExists(M.frameIn(dir, n)) do
    n += 1
  end
  return n
end

function M.countFrames(set)
  return M.countFramesIn(M.dir .. "/" .. set)
end

-- Assets finished at device resolution live in bar/<set>/<scale>/ (hud-build
-- renders one set per connected output's scale, 1x always); `probe` is a file
-- every set has. The 1x set stands in for a scale that has no set.
function M.scaledDir(set, sc, probe)
  local dir = string.format("%s/%s/%s", M.dir, set, if sc then string.format("%g", sc) else "1")
  if noctalia.fileExists(dir .. "/" .. probe) then
    return dir
  end
  return string.format("%s/%s/1", M.dir, set)
end

-- This widget's output scale as Hyprland reports it (noctalia.outputs() rounds
-- it: 2 on a 1.5x panel); cb(nil) when the output is not found.
function M.outputScale(cb)
  local name = barWidget.outputName()
  noctalia.runAsync({ "hyprctl", "-j", "monitors" }, function(r)
    local mons = r.exitCode == 0 and noctalia.json.decode(r.stdout)
    if type(mons) == "table" then
      for _, m in mons do
        if m.name == name and type(m.scale) == "number" then
          cb(m.scale)
          return
        end
      end
    end
    cb(nil)
  end, 3000)
end

-- Visible fallback instead of an empty slot when hud-build has not run yet.
function M.missing()
  barWidget.setGlyph("alert-triangle")
  barWidget.setTooltip("ACID//HUD: run hud-build to render the bar assets")
end

-- Where the workspaces widget publishes its row width (logical px) for the
-- equalizer on the same output, which sizes itself to mirror the gap on the
-- other side of the row. Widget runtimes share nothing else.
function M.wsWidthPath(output)
  local dir = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mael-hud"
  return dir, string.format("%s/ws-%s", dir, output or "default")
end

-- Readout icons rendered by hud-build at device resolution (bar/icons/<scale>/
-- <name>.png). The 1x set serves until resolveIcons has learnt the scale.
local iconDir = nil

function M.icon(name)
  return string.format("%s/%s.png", iconDir or M.scaledDir("icons", nil, "vol.png"), name)
end

-- Look the output's scale up once; onReady re-renders with the right set.
function M.resolveIcons(onReady)
  M.outputScale(function(sc)
    iconDir = M.scaledDir("icons", sc, "vol.png")
    onReady()
  end)
end

function M.hasAssets()
  return noctalia.fileExists(M.icon("vol"))
end

-- Readout face: Departure Mono when installed, else the bar font.
local monoFamily = nil
function M.monoFont()
  if monoFamily == nil then
    monoFamily = noctalia.loadFont("/usr/share/fonts/OTF/DepartureMono-Regular.otf") or false
  end
  return monoFamily or nil
end

-- Three-digit readout value, e.g. 074.
function M.readout(text, color)
  return ui.label({
    text = text,
    fontFamily = M.monoFont(),
    fontSize = 12,
    color = color,
    baseline = "inkCentered",
  })
end

-- Run an argv once at a time; a request made meanwhile reruns it on completion,
-- so a burst of events costs at most two calls.
function M.coalesced(argv, onResult)
  local busy, again = false, false
  local function go()
    if busy then
      again = true
      return
    end
    busy = true
    local launched = noctalia.runAsync(argv, function(r)
      busy = false
      -- A throwing handler must not stop the follow-up run.
      local ok, err = pcall(onResult, r)
      if not ok then
        noctalia.log("mael/hud: " .. tostring(err))
      end
      if again then
        again = false
        go()
      end
    end, 3000)
    if not launched then
      -- No callback will come: stay retryable instead of wedging busy.
      busy = false
    end
  end
  return go
end

return M
