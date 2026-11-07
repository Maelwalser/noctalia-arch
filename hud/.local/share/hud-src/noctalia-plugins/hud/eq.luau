--!nonstrict
-- Oscilloscope-style equalizer driven by Noctalia's PipeWire spectrum: a few
-- overlaid sine traces whose amplitude follows the band levels along the width
-- (bass left, treble right), so the lines bulge where the music is and settle
-- into a calm ripple when nothing plays, framed by a bracket at each end.
--
-- Noctalia has no overlay node: the layers are ui.graph nodes (two series each)
-- in a column with a negative gap, so they draw on top of one another.
--
-- It sits first in the end lane and widens leftwards until it is `gap` px from
-- the centred workspace row, mirroring the gap left of the row. Lanes size to
-- their content, so the width is computed: output width minus `reserve` (the
-- rest of the end lane plus the bar margin) minus the right half of the row.
-- On wide outputs it stops at `max_width`, the width of the system panel, so
-- it does not stretch across the ultrawide.
local common = require("./common.luau")

local H = 20 -- trace height (the rail is 32)
local MIN_WIDTH = 60
local FRAME_W = 5 -- bracket arm length

-- The spectrum comes at 60 Hz; every bar redraw also costs the compositor a
-- glass contour rebuild, so draw every other frame.
local SKIP = 2
local DECAY = 0.86 -- band level kept per drawn frame while falling
local IDLE_AMP = 0.1 -- ripple with nothing playing
local GAIN = 0.42 -- extra amplitude at full band level
local IDLE_MS = 160 -- idle ripple rate (each redraw also costs a glass contour rebuild)

-- One sine trace per entry: `k` cycles across the width, `speed` cycles per
-- drawn frame, `amp` scales the envelope, `shift` offsets the band window so the
-- lines do not all bulge at the same place.
local TRACES = {
  { color = "primary", k = 3.0, speed = 0.011, amp = 1.0, shift = 0 },
  { color = "secondary/0.8", k = 2.4, speed = -0.008, amp = 0.9, shift = 0.08 },
  { color = "on_surface_variant/0.45", k = 3.7, speed = 0.014, amp = 0.55, shift = -0.06 },
  { color = "primary/0.35", k = 1.8, speed = -0.006, amp = 0.8, shift = 0.14 },
  { color = "secondary/0.3", k = 4.6, speed = 0.017, amp = 0.4, shift = -0.12 },
  { color = "on_surface/0.18", k = 2.0, speed = 0.005, amp = 0.6, shift = 0.04 },
}
local LINE_W = { 1.5, 1.2, 1, 1, 1, 1 }

local myOutput = barWidget.outputName()
local width = 200
local level = {} -- smoothed band levels, bass first
local phase = {}
local frames = 0
local active = false -- spectrum frames carry sound
local lastFrame = 0 -- frames counter at the last audible spectrum frame

for i, _ in TRACES do
  phase[i] = i * 0.37
end

local function outputWidth()
  for _, o in noctalia.outputs() do
    if o.name == myOutput then
      return o.width -- logical px, like the bar layout
    end
  end
  return nil
end

-- Width between the workspace row (+ gap) and the rest of the end lane.
local function fitWidth()
  local _, path = common.wsWidthPath(myOutput)
  local ws = tonumber(noctalia.readFile(path) or "")
  local w = outputWidth()
  if not ws or not w then
    return width
  end
  local reserve = noctalia.getConfig("reserve") or 362
  local gap = noctalia.getConfig("gap") or 13
  local wd = w - reserve - (w / 2 + ws / 2) - gap
  local maxWidth = noctalia.getConfig("max_width") or 286
  if maxWidth > 0 then
    wd = math.min(wd, maxWidth)
  end
  return math.max(MIN_WIDTH, math.floor(wd))
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

-- Band level at fractional position x (0 = bass, 1 = treble), cosine-smoothed
-- between bands. The top quarter of the spectrum is mostly empty in music, so
-- x covers the lower three quarters, widening the bands towards the top.
local function envelope(x)
  local n = #level
  if n == 0 then
    return 0
  end
  local pos = (n * 0.75 - 1) * math.clamp(x, 0, 1) ^ 1.6
  local j = math.floor(pos)
  local t = pos - j
  t = (1 - math.cos(t * math.pi)) / 2
  local a = level[j + 1] or 0
  local b = level[j + 2] or a
  return a * (1 - t) + b * t
end

local function trace(n, tr, ph)
  local out = table.create(n)
  for i = 0, n - 1 do
    local x = i / (n - 1)
    local amp = (IDLE_AMP + GAIN * envelope(x + tr.shift)) * tr.amp
    out[i + 1] = 0.5 + amp * math.sin(2 * math.pi * (tr.k * x + ph))
  end
  return out
end

-- Matching brackets at both ends, in the accent.
local function frame()
  local function arm()
    return ui.box({ width = FRAME_W, height = 1, fill = "primary" })
  end
  local function arms()
    return ui.column({ width = FRAME_W, height = H, justify = "space_between" }, { arm(), arm() })
  end
  local function bar()
    return ui.box({ width = 1, height = H, fill = "primary" })
  end
  return ui.row({ width = width, height = H, justify = "space_between" }, {
    ui.row({ height = H, align = "stretch" }, { bar(), arms() }),
    ui.row({ height = H, align = "stretch" }, { arms(), bar() }),
  })
end

local function render()
  local energy = 0
  for _, v in level do
    energy = math.max(energy, v)
  end
  local n = math.floor(width / 2) + 1
  local layers = {}
  for g = 1, #TRACES, 2 do
    local a, b = TRACES[g], TRACES[g + 1]
    phase[g] += a.speed * (1 + 2 * energy)
    local props = {
      width = width,
      height = H,
      values = trace(n, a, phase[g]),
      color = a.color,
      lineWidth = LINE_W[g],
      fillOpacity = 0,
    }
    if b then
      phase[g + 1] += b.speed * (1 + 2 * energy)
      props.values2 = trace(n, b, phase[g + 1])
      props.color2 = b.color
    end
    table.insert(layers, ui.graph(props))
  end
  table.insert(layers, frame())
  barWidget.render(ui.column({ gap = -H, width = width, height = H }, layers))
end

local function decay()
  for i, v in level do
    level[i] = v * DECAY
  end
end

function onAudioSpectrum(valuesCsv, stateCsv)
  frames += 1
  if noctalia.getConfig("audio_spectrum") == false then
    active = false
    return
  end
  local state = numbers(stateCsv)
  local values = numbers(valuesCsv)
  if state[1] ~= 1 or #values == 0 then
    active = false
    return
  end
  local loud = false
  for i, v in values do
    local l = math.clamp(math.sqrt(math.max(v, 0)), 0, 1)
    level[i] = math.max(l, (level[i] or 0) * DECAY)
    loud = loud or level[i] > 0.02
  end
  if loud then
    lastFrame = frames
  end
  -- The stream keeps sending zero frames after the sound ends: hand the idle
  -- ripple back to update() instead of redrawing at spectrum rate.
  active = frames - lastFrame < 90
  if not active then
    return
  end
  noctalia.setUpdateInterval(1000)
  if frames % SKIP == 0 then
    render()
  end
end

function update()
  -- Idle: a slow ripple, plus a cheap poll (one small file) so the width
  -- follows the workspace row.
  local w = fitWidth()
  if w ~= width then
    width = w
  end
  if active then
    noctalia.setUpdateInterval(1000)
    return
  end
  noctalia.setUpdateInterval(IDLE_MS)
  decay()
  render()
end

barWidget.setTooltip("Audio spectrum")
