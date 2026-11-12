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
  M.tip("ACID//HUD: run hud-build to render the bar assets")
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

-- Panel tag: the acid notch that opens a bar panel, echoing the overlay's
-- section headers. Drawn by the panel's first readout, so the pill's start is
-- part of that readout's hover target.
function M.tag()
  return ui.box({ width = 3, height = 14, fill = "primary" })
end

-- Hover feedback is drawn here rather than by the bar (hover_highlight = false
-- in plugin.toml): the bar's own highlight is a slab behind the widget, which on
-- a bare ornament makes hyprglass trace a whole new pill and in a grouped pill
-- does not line up with it. Instead the hovered readout's text and icon glow.
--
-- The UI has no blur or shadow, so the glow is the node itself drawn again at
-- low opacity on three rings around its place (the old stacked-copies trick;
-- at this size it reads as a soft bloom in the node's own colours). `make`
-- builds a fresh copy of the node. Layers are stacked with a negative gap and
-- each is padded by GLOW on every side, so a copy can shift without moving
-- the layout: glow() is always GLOW px larger all round than its node, lit or
-- not, and the rows below subtract that from their gaps.
local GLOW = 3
local LAYER_H = 24 -- the pill's height; every layer is centred in it
local CLEAR = "on_surface/0.00" -- a box without a fill paints black
local RINGS = { { r = 1, a = 0.08 }, { r = 2, a = 0.05 }, { r = 3, a = 0.03 } }

local function space(w, h)
  return ui.box({ width = w, height = h, fill = CLEAR })
end

local function layer(node, dx, dy, opacity)
  return ui.row({ height = LAYER_H, align = "center", opacity = opacity }, {
    space(GLOW + dx, 1),
    ui.column({ align = "center" }, { space(1, GLOW + dy), node, space(1, GLOW - dy) }),
    space(GLOW - dx, 1),
  })
end

function M.glow(lit, make)
  local layers = {}
  if lit then
    for _, ring in RINGS do
      for k = 0, 7 do
        local a = k * math.pi / 4
        table.insert(layers, layer(make(), ring.r * math.cos(a), ring.r * math.sin(a), ring.a))
      end
    end
  end
  table.insert(layers, layer(make(), 0, 0, 1))
  return ui.column({ gap = -LAYER_H, height = LAYER_H }, layers)
end

-- Clear spacer for rows that set their own distances between glow() nodes.
M.space = space

-- A readout: nodes side by side with the panel's tag in front when it is the
-- first one in its pill. `gap` is the distance wanted between the nodes' ink;
-- they are expected to be glow() nodes, whose padding is taken off here.
local function readout(nodes, tagged, gap)
  local row = ui.row({ gap = (gap or 5) - 2 * GLOW, align = "center" }, nodes)
  if tagged then
    return { M.tag(), row }
  end
  return { row }
end

-- One action among several in a shared pill (capsule group padding 2): 6 px
-- inside + that 2 keeps the readout 8 px from the pill's end or the divider.
function M.chip(nodes, tagged)
  return ui.row({ gap = 8 - GLOW, align = "center", height = LAYER_H, paddingH = 6 - GLOW }, readout(nodes, tagged))
end

-- A pill with a single action (capsule_padding 0, so this row is the pill and
-- the whole pill is the hover target).
function M.pill(nodes, tagged, gap)
  return ui.row({ gap = 8 - GLOW, align = "center", height = LAYER_H, paddingH = 8 - GLOW }, readout(nodes, tagged, gap))
end

M.GLOW = GLOW

-- Tooltips. Noctalia's own are opaque popups that cannot be made glass, so a
-- widget hands its text to the HUD overlay (quickshell hud, Tip.qml), which
-- shows it as a glass pill under the bar: tip(text) sets what this widget
-- says, hover(inside) reports the pointer (call it from the script's onHover).
-- Without the overlay (`qs` fails: not running, or another theme) the text
-- goes to Noctalia's tooltip for that hover; the next hover tries again.
local tipOutput = barWidget.outputName() -- not reliable inside async callbacks
local tipId = string.format("%s/%d/%d", tostring(tipOutput), noctalia.nowMs() % 100000000, math.random(1000000))
local tipText, tipOver = "", false
local tipSent = nil -- what the overlay shows for this widget, nil = nothing
local tipBusy, tipNative = false, false
-- A tooltip set by an earlier load of the script survives a hot reload on the
-- widget itself: clear it, or Noctalia's popup shows next to the glass one.
barWidget.setTooltip("")

-- One `qs` at a time, then whatever is wanted by then: an enter and a leave
-- in quick succession would otherwise race and could leave the tooltip up.
local function tipSync()
  if tipBusy or tipNative then
    return
  end
  local want = if tipOver and tipText ~= "" then tipText else nil
  if want == tipSent then
    return
  end
  local argv = { "qs", "-c", "hud", "ipc", "call", "tip" }
  if want then
    table.move({ "put", tipId, tipOutput, want }, 1, 4, #argv + 1, argv)
  else
    table.move({ "drop", tipId }, 1, 2, #argv + 1, argv)
  end
  tipBusy = true
  local launched = noctalia.runAsync(argv, function(r)
    tipBusy = false
    if r.exitCode ~= 0 then
      tipNative = true
      barWidget.setTooltip(tipText)
      return
    end
    tipSent = want
    barWidget.setTooltip("") -- the overlay answered: no popup of Noctalia's beside it
    tipSync()
  end, 3000)
  if not launched then
    tipBusy, tipNative = false, true
    barWidget.setTooltip(tipText)
  end
end

function M.tip(text)
  tipText = text or ""
  if tipNative then
    barWidget.setTooltip(tipText)
  else
    tipSync()
  end
end

function M.hover(inside)
  tipOver = inside
  if inside and tipNative then
    -- The overlay may be back (it was restarting, say): ask it again.
    tipNative, tipSent = false, nil
  end
  tipSync()
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
