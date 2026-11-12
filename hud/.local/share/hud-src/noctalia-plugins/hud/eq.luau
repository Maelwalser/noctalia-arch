--!nonstrict
-- Neon light bars driven by Noctalia's PipeWire spectrum: two glowing bars in
-- the accent colours that lie straight and parallel while nothing plays and
-- bend to the music (bass left, treble right). Each band moves with its own
-- rise and fall rather than its loudness, and every kick drum throws the bars
-- apart, flares them and pushes the wave along. The bars are held at both
-- ends, like strings: they swing between two fixed round caps.
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
local DECAY = 0.80 -- band level kept per settle tick while the bars swing back to rest
local GAIN = 5.2 -- bend at full band level, px
local BULGE = 1.4 -- px a full band pushes its stretch of both bars outwards
local SPREAD = 1.6 -- px a kick throws the bars apart
local SURGE = 2.5 -- how much faster the wave runs during a kick

-- Noctalia hands out a spectrum that is already smoothed and compressed: while
-- a track plays a band only hovers in a narrow range (bass 0.75..0.88 under a
-- 150 BPM kick, treble 0.05..0.15), so drawn as it comes the bars hold one
-- shape and only the wave drifts. Each band is therefore measured against
-- itself: how far it stands above its running average, in units of its own
-- usual swing. (Stretching a band over its recent extremes instead left the
-- treble half lying flat: a few hi-hat spikes set the range and everything
-- between them came out near zero.)
local AVG = 0.03 -- share of a frame taken into a band's running average
local DEV = 0.02 -- and into its usual swing (mean distance from the average)
local SWING = 4.4 -- usual swings from no level to full level
local BIAS = 0.35 -- level of a band sitting on its average
-- Least swing a band is measured by, absolute and as a share of its average:
-- a steady tone or noise floor stays calm instead of being blown up.
local DEV_MIN = 0.004
local DEV_SHARE = 0.03
local PRESENCE = 0.02 -- raw level below which a band is faded out
local SILENT = 0.0004 -- raw level that counts as no sound at all
-- Share of the way a drawn level moves to its target per spectrum frame.
-- Rising is not instant: a level that jumps puts a kink in the bar.
local RISE = 0.45
local FALL = 0.16
-- Bands the bars show, bass first: music leaves the ones above nearly empty.
local SHOWN = 12
local BLEND = 0.85 -- reach of a band along the bar, in bands (Gaussian sigma)
local EDGE = 0.08 -- share of the width over which a bar leaves its fixed end
-- A band below its average adds nothing, and at any moment that is true of
-- whole stretches of the spectrum: bent by the bands alone, a third of a bar
-- would lie flat while the rest dances. So while anything plays the wave runs
-- the full length at BASE of its height and the bands add the rest.
local BASE = 0.38
local AUDIBLE = 0.05 -- loudest raw band at which the base wave is fully up
local SOUND_RISE = 0.2 -- share of the way the base wave comes up per spectrum frame
local SOUND_FALL = 0.06 -- and dies down

-- Kick detection on the mean of the lowest BASS_BANDS bands: a fast average
-- rising above a slow one by more than its usual swing is a beat. It has to
-- fall back to half of that before the next one counts, so a held bass note is
-- one beat.
local BASS_BANDS = 4
local BEAT_RISE = 1.4 -- times the usual swing
local BEAT_MIN = 0.012 -- least rise that counts, so near silence stays calm
local BEAT_GAP = 11 -- spectrum frames before the next beat may land
local KICK_DECAY = 0.86 -- kick kept per spectrum frame (per settle tick at rest)
local KICK_RISE = 0.6 -- share of the way the drawn kick moves to a fresh one per frame
local SETTLE_MS = 50 -- redraw rate while the tubes swing back to rest
local REST = 0.004 -- band level below which the sign counts as still
local REST_Y = 3.2 -- px from the centre line to a resting bar
-- One bar per entry: `rest` is its resting height in px above the centre line,
-- `k` the bends across the width, `speed` cycles per drawn frame, `shift`
-- offsets the band window so the two do not bulge at the same place.
local TUBES = {
  { color = "primary", rest = REST_Y, k = 1.7, speed = 0.012, shift = 0 },
  { color = "tertiary", rest = -REST_Y, k = 2.3, speed = -0.009, shift = 0.07 },
}

-- How ui.graph places a line (measured on Noctalia 5.4.1, and its fragment
-- shader, `strings /usr/bin/noctalia`, agrees): the stroke is drawn FEATHER px
-- wider than lineWidth and kept whole inside the node less PLOT_PAD px top and
-- bottom, the margin staying between 6 % and 18 % of the height, so the same
-- value lands at a different height for each line width. Heights are therefore
-- computed in px and converted per stroke.
-- Across the width the node draws its values from the third one on (the first
-- two are the run-in of a scrolling graph), as a smooth curve through them.
local PLOT_PAD = 2.4
local FEATHER = 1
local LEAD = 2 -- values the graph keeps off its left edge
local function travel(w) -- px between value 0 and value 1 for a line of width w
  local pad = math.clamp((PLOT_PAD + (w + FEATHER) / 2) / H, 0.06, 0.18)
  return H * (1 - 2 * pad)
end

local LIGHT_W = 3 -- thickness of the coloured light
local GLOW_W = 4.8
local REACH = travel(GLOW_W) / 2 - REST_Y -- furthest a bar may swing outwards from rest
local KNEE = 0.7 * REACH -- swing up to which a bar moves freely
local CLEAR = "on_surface/0.00" -- spacer fill: a box without one is drawn black
-- The graph node cuts its line off square, so the light stops `CAP_AT` px
-- short of each end and a round dot of its thickness closes it there.
local CAP_AT = 2.4

-- Strokes of one bar, bottom first. `alpha` is the opacity at rest, `pulse`
-- what a kick adds; `color` overrides the bar colour (the core). The glow
-- stays narrower than the gap between the resting bars: wider, the two glows
-- merge into a slab behind them.
local STROKES = {
  { w = GLOW_W, alpha = 0.22, pulse = 0.33 },
  { w = LIGHT_W, alpha = 1, pulse = 0 },
  { w = 1, alpha = 0.8, pulse = 0.2, color = "on_surface" },
}
-- Points along a bar, whatever its width (2 px apart at the widest). The
-- count must never go down: a graph node handed fewer values than before keeps
-- drawing the old number of them, the new ones squeezed into the left of the
-- node and the last frame's leftovers frozen on the right (Noctalia 5.4.1;
-- seen when the widget narrowed, and after a reload with fewer points).
local POINTS = 144

local myOutput = barWidget.outputName()
local width = 200
local level = {} -- band levels as drawn, bass first
local avg, dev = {}, {} -- per band: running average and usual swing
local bassFast, bassSlow, swing = 0, 0, 0.02
local kick = 0 -- 1 on a beat, fading
local flare = 0 -- the kick as drawn: it follows `kick` up over a few frames
local sound = 0 -- 1 while something plays, eased: the height of the base wave
local armed = true
local sinceBeat = 0
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

-- Target level of band i for raw value x: how far x stands above the band's
-- average, in its own usual swings.
local function track(i, x)
  -- A silent band keeps what it has learnt: averaged down to nothing over a
  -- pause, every band would read as far above its average when the music
  -- returns and the bars would stand at full bend for a second.
  if x <= SILENT then
    return 0
  end
  local a = avg[i]
  if not a then
    a, dev[i] = x, 0
  end
  a += (x - a) * AVG
  avg[i] = a
  dev[i] += (math.abs(x - a) - dev[i]) * DEV
  local usual = math.max(dev[i], DEV_MIN + DEV_SHARE * a)
  local t = math.clamp(BIAS + (x - a) / (SWING * usual), 0, 1)
  return math.min(1, x / PRESENCE) * t
end

local function beat(bass)
  bassFast += (bass - bassFast) * 0.5
  bassSlow += (bass - bassSlow) * 0.06
  local rise = bassFast - bassSlow
  -- Capped per frame: the jump from silence to sound would otherwise raise
  -- the bar for seconds and swallow the first beats.
  swing += (math.min(math.abs(rise), 2 * swing + 0.01) - swing) * 0.02
  sinceBeat += 1
  kick *= KICK_DECAY
  flare += (kick - flare) * (if kick > flare then KICK_RISE else 1)
  local need = math.max(BEAT_MIN, BEAT_RISE * swing)
  if rise < need / 2 then
    armed = true
  end
  if armed and rise > need and sinceBeat > BEAT_GAP and bass > 0.05 then
    kick = math.min(1, 0.55 + 0.45 * rise / (4 * swing))
    sinceBeat = 0
    armed = false
  end
end

local function smoothstep(t)
  t = math.clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
end

-- Band levels along the bar, as a lattice over x = 0 (bass) .. LATTICE_SPAN
-- (treble; past 1 for the shifted bar): every band spreads over its
-- neighbours as a Gaussian, so the level has no corners or flat steps for the
-- bars to show. The weights only depend on the band count; the lattice is
-- filled once a frame.
local LATTICE = 64
local LATTICE_SPAN = 1.1
local weights = {}
local lattice = table.create(LATTICE + 1, 0)

local function buildWeights(n)
  weights = {}
  for k = 0, LATTICE do
    -- A slight curve gives the bass, which carries the beat, more of the bar.
    local pos = (n - 1) * math.min(1, k / LATTICE * LATTICE_SPAN) ^ 1.25
    local row, sum = table.create(n), 0
    for j = 1, n do
      local d = (pos - (j - 1)) / BLEND
      row[j] = math.exp(-d * d / 2)
      sum += row[j]
    end
    for j = 1, n do
      row[j] /= sum
    end
    weights[k + 1] = row
  end
end

local function fillLattice()
  local n = math.min(#level, SHOWN)
  if n == 0 then
    return
  end
  if not weights[1] or #weights[1] ~= n then
    buildWeights(n)
  end
  for k, row in weights do
    local e = 0
    for j = 1, n do
      e += row[j] * level[j]
    end
    lattice[k] = e
  end
end

-- What stays the same along a bar from frame to frame, per point: how far the
-- fixed ends let it move, its angle along the wave and where it reads the
-- lattice. Rebuilt when the widget's width changes; the per-frame loop over
-- the points has to stay cheap (Noctalia cuts a callback off that runs long).
local points = { n = 0, inset = 0 }

local function buildPoints(n, inset)
  points = { n = n, inset = inset }
  for b, tb in TUBES do
    local held, turn, cell, mix = table.create(n), table.create(n), table.create(n), table.create(n)
    for i = 0, n - 1 do
      local u = i / math.max(1, n - 1)
      local x = inset + (1 - 2 * inset) * u
      held[i + 1] = smoothstep(u / EDGE) * smoothstep((1 - u) / EDGE)
      turn[i + 1] = 2 * math.pi * tb.k * x
      local pos = math.clamp((x + tb.shift) / LATTICE_SPAN, 0, 1) * LATTICE
      local k = math.min(math.floor(pos), LATTICE - 1)
      cell[i + 1] = k + 1
      mix[i + 1] = pos - k
    end
    points[b] = { held = held, turn = turn, cell = cell, mix = mix }
  end
end

-- Heights of bar b in px above the centre line, at n points from end to end:
-- its rest line, and between the fixed ends the throw of a kick plus what the
-- base wave and the band levels add along the width: a push outwards and a
-- bend. The second, faster term keeps the bend from reading as a plain sine.
-- `inset` is the share of the widget's width left out at each end.
local function tube(n, b, ph, inset)
  if points.n ~= n or points.inset ~= inset then
    buildPoints(n, inset)
  end
  local tb, pt = TUBES[b], points[b]
  local held, turn, cell, mix = pt.held, pt.turn, pt.cell, pt.mix
  local out = table.create(n)
  local side = math.sign(tb.rest)
  local rest, throw, floor, share = tb.rest, side * SPREAD * flare, BASE * sound, 1 - BASE
  local push, room, turned = side * BULGE, REACH - KNEE, 2 * math.pi * ph
  for i = 1, n do
    local a = turn[i] + turned
    local k, t = cell[i], mix[i]
    local amp = floor + share * (lattice[k] * (1 - t) + lattice[k + 1] * t)
    local v = throw + amp * (push + GAIN * (math.sin(a) + 0.2 * math.sin(2.3 * a + 1.1)))
    -- Beyond the knee a bar eases into REACH instead of going flat.
    if v > KNEE then
      v = KNEE + room * math.tanh((v - KNEE) / room)
    elseif v < -KNEE then
      v = -KNEE - room * math.tanh((-v - KNEE) / room)
    end
    out[i] = rest + held[i] * v
  end
  return out
end

-- Graph values for a line of width w through the heights px, behind the
-- run-in the node does not draw.
local function plot(px, w)
  local t = travel(w)
  local out = table.create(#px + LEAD)
  for i = 1, LEAD do
    out[i] = 0.5 + px[1] / t
  end
  for i, v in px do
    out[i + LEAD] = 0.5 + v / t
  end
  return out
end

local function render()
  local energy, peak = 0, 0
  local shown = math.min(#level, SHOWN)
  for i = 1, shown do
    energy += level[i] / shown
    peak = math.max(peak, level[i])
  end
  still = peak < REST and flare < 0.01 and sound < 0.01
  for i, tb in TUBES do
    if not still then
      phase[i] += tb.speed * (0.5 + 2.5 * energy + SURGE * flare)
    end
  end
  fillLattice()
  -- One curve per bar, stroked three times.
  local w = width - 2 * CAP_AT
  local n = POINTS
  local upper = tube(n, 1, phase[1], CAP_AT / width)
  local lower = tube(n, 2, phase[2], CAP_AT / width)
  local layers = {}
  for _, st in STROKES do
    local alpha = math.min(1, st.alpha + st.pulse * flare)
    local function paint(tb)
      return string.format("%s/%.2f", st.color or tb.color, alpha)
    end
    local graph = ui.graph({
      width = w,
      height = H,
      values = plot(upper, st.w),
      color = paint(TUBES[1]),
      values2 = plot(lower, st.w),
      color2 = paint(TUBES[2]),
      lineWidth = st.w,
      fillOpacity = 0,
    })
    table.insert(layers, ui.row({ width = width, height = H, justify = "center" }, { graph }))
  end
  -- Round caps: one layer per bar, a dot at each end. The bars are held at
  -- their ends, so the dots never move: laid out per frame they sat a pixel
  -- off the line more often than on it.
  for i, tb in TUBES do
    local d = LIGHT_W + FEATHER / 2
    local function cap(left)
      local dot = ui.column({ width = d, height = H }, {
        ui.box({ width = d, height = H / 2 - tb.rest - d / 2, fill = CLEAR }),
        ui.box({ width = d, height = d, radius = d / 2, fill = tb.color }),
      })
      local pad = ui.box({ width = CAP_AT - d / 2, height = H, fill = CLEAR })
      return ui.row({ height = H }, if left then { pad, dot } else { dot, pad })
    end
    table.insert(
      layers,
      2 + i,
      ui.row({ width = width, height = H, justify = "space_between" }, { cap(true), cap(false) })
    )
  end
  barWidget.render(ui.column({ gap = -H, width = width, height = H }, layers))
end

local function decay()
  for i, v in level do
    level[i] = v * DECAY
  end
  kick *= KICK_DECAY
  flare = math.min(flare, kick)
  sound *= DECAY
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
  local loudest = 0
  local bass, bassBands = 0, math.min(BASS_BANDS, #values)
  for i, v in values do
    local x = math.clamp(v, 0, 1)
    local target, now = track(i, x), level[i] or 0
    level[i] = now + (target - now) * (if target > now then RISE else FALL)
    loud = loud or x > SILENT
    loudest = math.max(loudest, x)
    if i <= bassBands then
      bass += x / bassBands
    end
  end
  beat(bass)
  local heard = math.min(1, loudest / AUDIBLE)
  sound += (heard - sound) * (if heard > sound then SOUND_RISE else SOUND_FALL)
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

common.tip("Audio spectrum")

function onHover(inside)
  common.hover(inside)
end
