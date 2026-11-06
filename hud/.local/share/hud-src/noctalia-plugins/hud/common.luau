--!nonstrict
-- Shared helpers for the HUD bar widgets.
local M = {}

M.dir = "~/.local/share/hud/bar"

-- Frame files are named 00.png, 01.png, ... by hud-build.
function M.framePath(set, i)
  return string.format("%s/%s/%02d.png", M.dir, set, i)
end

function M.countFrames(set)
  local n = 0
  while noctalia.fileExists(M.framePath(set, n)) do
    n += 1
  end
  return n
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

-- Pixel icons rendered by hud-build (bar/icons/<name>.png).
function M.icon(name)
  return string.format("%s/icons/%s.png", M.dir, name)
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
