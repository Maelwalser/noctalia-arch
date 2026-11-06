--!nonstrict
-- LED-segment equalizer driven by Noctalia's PipeWire spectrum: acid bars with
-- a hold-and-fall peak cap. Rests as a dim LED grid when nothing plays.
--
-- It sits first in the end lane and widens leftwards until it is `gap` px from
-- the centred workspace row, mirroring the gap left of the row. Lanes size to
-- their content, so the width is computed: output width minus `reserve` (the
-- rest of the end lane plus the bar margin) minus the right half of the row.
-- On wide outputs it stops at `max_width`, the width of the system panel, so
-- it does not stretch across the ultrawide.
local common = require("./common.luau")

local MIN_BARS = 8
local BARS = 12
local SEGS = 6 -- segments per bar
local SEG_H, SEG_GAP, BAR_W, BAR_GAP = 2, 1, 3, 2
local DECAY = 0.82 -- level kept per frame while falling
local PEAK_HOLD = 8 -- frames a peak stays before dropping
local PEAK_FALL = 0.04

local level, peak, hold = {}, {}, {}
local resting = false
-- Leftover width whole bars cannot fill, kept on the right so the gap to the
-- workspace row stays exact.
local pad = 0
local myOutput = barWidget.outputName()

local function resize(n)
  BARS = n
  for i = 1, n do
    level[i], peak[i], hold[i] = 0, 0, 0
  end
end
resize(BARS)

local function outputWidth()
  for _, o in noctalia.outputs() do
    if o.name == myOutput then
      return o.width -- logical px, like the bar layout
    end
  end
  return nil
end

-- Bars that fit between the workspace row (+ gap) and the rest of the end lane.
-- Returns the bar count and the padding that makes up the exact width.
local function fitBars()
  local _, path = common.wsWidthPath(myOutput)
  local ws = tonumber(noctalia.readFile(path) or "")
  local w = outputWidth()
  if not ws or not w then
    return BARS, pad
  end
  local reserve = noctalia.getConfig("reserve") or 362
  local gap = noctalia.getConfig("gap") or 13
  local width = w - reserve - (w / 2 + ws / 2) - gap
  local maxWidth = noctalia.getConfig("max_width") or 286
  if maxWidth > 0 then
    width = math.min(width, maxWidth)
  end
  local n = math.max(MIN_BARS, math.floor((width + BAR_GAP) / (BAR_W + BAR_GAP)))
  return n, math.max(0, math.floor(width - (n * (BAR_W + BAR_GAP) - BAR_GAP)))
end

local function numbers(csv)
  local out = {}
  if csv then
    for part in string.gmatch(csv, "([^,]+)") do
      table.insert(out, tonumber(part) or 0)
    end
  end
  return out
end

local function render()
  local cols = {}
  for i = 1, BARS do
    local lit = math.floor(level[i] * SEGS + 0.5)
    local cap = math.clamp(math.floor(peak[i] * SEGS + 0.5), 1, SEGS)
    local segs = {}
    for s = SEGS, 1, -1 do
      local fill, opacity = "outline_variant", 0.5
      if s <= lit then
        fill, opacity = "primary", 1
      elseif s == cap and peak[i] > 0.02 then
        fill, opacity = "on_surface", 0.9
      end
      table.insert(segs, ui.box({ width = BAR_W, height = SEG_H, fill = fill, opacity = opacity }))
    end
    table.insert(cols, ui.column({ gap = SEG_GAP }, segs))
  end
  local bars = ui.row({ gap = BAR_GAP, align = "center" }, cols)
  if pad > 0 then
    bars = ui.row({ gap = 0, align = "center" }, { bars, ui.box({ width = pad, height = 1 }) })
  end
  barWidget.render(bars)
end

local function rest()
  if resting then
    return
  end
  resting = true
  for i = 1, BARS do
    level[i], peak[i], hold[i] = 0, 0, 0
  end
  render()
end

function onAudioSpectrum(valuesCsv, stateCsv)
  if noctalia.getConfig("audio_spectrum") == false then
    rest()
    return
  end
  local state = numbers(stateCsv)
  local values = numbers(valuesCsv)
  if state[1] ~= 1 or #values == 0 then
    rest()
    return
  end
  resting = false
  -- The top quarter of the spectrum is mostly empty in music: spread the bars
  -- over the lower three quarters, widening the bands towards the top.
  local usable = math.max(BARS, math.floor(#values * 0.75))
  for i = 1, BARS do
    local a = math.floor(usable * ((i - 1) / BARS) ^ 1.6) + 1
    local b = math.max(a, math.floor(usable * (i / BARS) ^ 1.6))
    local sum = 0
    for j = a, b do
      sum += values[j] or 0
    end
    local v = math.clamp(math.sqrt(sum / (b - a + 1)), 0, 1)
    level[i] = math.max(v, level[i] * DECAY)
    if level[i] >= peak[i] then
      peak[i], hold[i] = level[i], PEAK_HOLD
    elseif hold[i] > 0 then
      hold[i] -= 1
    else
      peak[i] = math.max(level[i], peak[i] - PEAK_FALL)
    end
  end
  render()
end

function update()
  -- Cheap poll (one small file) so the width follows the workspace row.
  noctalia.setUpdateInterval(500)
  local n, p = fitBars()
  if n ~= BARS or p ~= pad then
    pad = p
    resize(n)
    resting = false
    rest()
  elseif not resting and level[1] == 0 then
    rest()
  end
end

barWidget.setTooltip("Audio spectrum")
