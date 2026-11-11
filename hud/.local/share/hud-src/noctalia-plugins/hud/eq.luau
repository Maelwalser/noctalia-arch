--!nonstrict
-- Neon light bars driven by Noctalia's PipeWire spectrum: two glowing bars in
-- the accent colours that lie straight and parallel while nothing plays and
-- bend to the music (bass left, treble right).
--
-- A bar is the same curve stroked three times: a glow that hugs it, the
-- coloured light and a white-hot core, closed by a round cap at each end.
-- Nothing is drawn behind or between the bars, so the bar's glass shows
-- through. Noctalia has no overlay node: the strokes are ui.graph nodes (one
-- series per bar) in a column with a negative gap, so they draw on top of one
-- another.
--
-- It sits first in the end lane and widens leftwards until it is `gap` px from
-- the centred workspace row, mirroring the gap left of the row. Lanes size to
-- their content, so the width is computed: output width minus `reserve` (the
-- rest of the end lane plus the bar margin) minus the right half of the row.
-- On wide outputs it stops at `max_width`, the width of the system panel, so
-- it does not stretch across the ultrawide.
local common = require("./common.luau")

local H = 28 -- drawing height (the rail is 32): room for the bars to bend
local MIN_WIDTH = 60

-- The spectrum comes at 60 Hz; every bar redraw also costs the compositor a
-- glass contour rebuild, so draw every other frame.
local SKIP = 2
local DECAY = 0.86 -- band level kept per drawn frame while falling
local GAIN = 4.2 -- bend at full band level, px
local SETTLE_MS = 50 -- redraw rate while the tubes swing back to rest
local REST = 0.004 -- band level below which the sign counts as still
-- One bar per entry: `rest` is its resting height in px above the centre line,
-- `k` the bends across the width, `speed` cycles per drawn frame, `shift`
-- offsets the band window so the two do not bulge at the same place.
local TUBES = {
  { color = "primary", rest = 3.2, k = 1.7, speed = 0.012, shift = 0 },
  { color = "tertiary", rest = -3.2, k = 2.3, speed = -0.009, shift = 0.07 },
}

-- How ui.graph places a line (measured on Noctalia 5.4.1): the stroke is drawn
-- FEATHER px wider than lineWidth and kept whole inside the node less PLOT_PAD
-- px top and bottom, so the same value lands at a different height for each
-- line width. Heights are therefore computed in px and converted per stroke.
local PLOT_PAD = 2.4
local FEATHER = 1
local function travel(w) -- px between value 0 and value 1 for a line of width w
  return H - 2 * PLOT_PAD - w - FEATHER
end

local LIGHT_W = 3 -- thickness of the coloured light
local GLOW_W = 4.8
local REACH = travel(GLOW_W) / 2 -- furthest a bar may leave the centre line
local CLEAR = "on_surface/0.00" -- spacer fill: a box without one is drawn black
-- The graph node cuts its line off square, so the light stops `CAP_AT` px
-- short of each end and a round dot of its thickness closes it there.
local CAP_AT = 2.4

-- Strokes of one bar, bottom first. `alpha` is the opacity at rest, `pulse`
-- what the bass adds; `color` overrides the bar colour (the core). `inset` is
-- the px left out at each end. The glow stays narrower than the gap between
-- the resting bars: wider, the two glows merge into a slab behind them.
local STROKES = {
  { w = GLOW_W, alpha = 0.22, pulse = 0.2, inset = CAP_AT - 0.4 },
  { w = LIGHT_W, alpha = 1, pulse = 0, inset = CAP_AT },
  { w = 1, alpha = 0.8, pulse = 0.2, inset = CAP_AT, color = "on_surface" },
}

local myOutput = barWidget.outputName()
local width = 200
local level = {} -- smoothed band levels, bass first
local phase = {}
local frames = 0
local active = false -- spectrum frames carry sound
local lastFrame = 0 -- frames counter at the last audible spectrum frame
local still = false -- drawn at rest: nothing to redraw until sound or a resize

for i, _ in TUBES do
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

-- Heights of one bar in px above the centre line: its rest line plus a bend
-- that follows the band levels. The second, faster term keeps the curve from
-- reading as a plain sine. `inset` is the share of the width left out at each
-- end.
local function tube(n, tb, ph, inset)
  local out = table.create(n)
  for i = 0, n - 1 do
    local x = inset + (1 - 2 * inset) * i / math.max(1, n - 1)
    local a = 2 * math.pi * (tb.k * x + ph)
    local bend = math.sin(a) + 0.3 * math.sin(2.3 * a + 1.1)
    out[i + 1] = math.clamp(tb.rest + GAIN * envelope(x + tb.shift) * bend, -REACH, REACH)
  end
  return out
end

-- Graph values for a line of width w.
local function plot(px, w)
  local t = travel(w)
  for i, v in px do
    px[i] = 0.5 + v / t
  end
  return px
end

local function render()
  local energy, bass = 0, 0
  for i, v in level do
    energy = math.max(energy, v)
    if i <= 3 then
      bass = math.max(bass, v)
    end
  end
  still = energy < REST
  for i, tb in TUBES do
    if not still then
      phase[i] += tb.speed * (1 + 2 * energy)
    end
  end
  local layers = {}
  for _, st in STROKES do
    local w = width - 2 * st.inset
    local n = math.floor(w / 2) + 1
    local alpha = math.min(1, st.alpha + st.pulse * bass)
    local function paint(tb)
      return string.format("%s/%.2f", st.color or tb.color, alpha)
    end
    local graph = ui.graph({
      width = w,
      height = H,
      values = plot(tube(n, TUBES[1], phase[1], st.inset / width), st.w),
      color = paint(TUBES[1]),
      values2 = plot(tube(n, TUBES[2], phase[2], st.inset / width), st.w),
      color2 = paint(TUBES[2]),
      lineWidth = st.w,
      fillOpacity = 0,
    })
    table.insert(layers, ui.row({ width = width, height = H, justify = "center" }, { graph }))
  end
  -- Round caps: one layer per bar, a dot at each end sitting on the curve.
  for i, tb in TUBES do
    local ends = tube(2, tb, phase[i], CAP_AT / width)
    local d = LIGHT_W + FEATHER / 2
    local function cap(px, left)
      local dot = ui.column({ width = d, height = H }, {
        ui.box({ width = d, height = H / 2 - px - d / 2, fill = CLEAR }),
        ui.box({ width = d, height = d, radius = d / 2, fill = tb.color }),
      })
      local pad = ui.box({ width = CAP_AT - d / 2, height = H, fill = CLEAR })
      return ui.row({ height = H }, if left then { pad, dot } else { dot, pad })
    end
    table.insert(
      layers,
      2 + i,
      ui.row({ width = width, height = H, justify = "space_between" }, { cap(ends[1], true), cap(ends[2], false) })
    )
  end
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
  -- A cheap poll (one small file) so the width follows the workspace row.
  -- At rest the sign is a still image: nothing is redrawn until sound returns.
  local w = fitWidth()
  local resized = w ~= width
  width = w
  if active then
    noctalia.setUpdateInterval(1000)
    return
  end
  if still and not resized then
    noctalia.setUpdateInterval(1000)
    return
  end
  noctalia.setUpdateInterval(SETTLE_MS)
  decay()
  render()
end

barWidget.setTooltip("Audio spectrum")
