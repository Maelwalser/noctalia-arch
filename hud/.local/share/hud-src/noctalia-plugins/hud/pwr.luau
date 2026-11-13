--!nonstrict
-- Battery cell drawn from boxes: four charge segments that chase upwards while
-- charging, amber at or below 30 % and red at or below 15 % on battery. Hidden on machines without a battery.
local common = require("./common.luau")

local function battery()
  local entries = noctalia.listDir("/sys/class/power_supply") or {}
  table.sort(entries)
  for _, e in entries do
    if string.sub(e, 1, 3) == "BAT" then
      return "/sys/class/power_supply/" .. e
    end
  end
  return nil
end

local bat = battery()
local tick, nextRead = 0, 0
local cap, status = nil, ""
local lit = 0 -- charge segments shown; update() advances it while charging
local hovered = false

local function read()
  cap = tonumber(noctalia.readFile(bat .. "/capacity") or "")
  -- Trim only the ends: the kernel reports "Not charging" with a space.
  status = string.match(noctalia.readFile(bat .. "/status") or "", "^%s*(.-)%s*$")
end

local function render()
  if cap == nil then
    return
  end
  local low = cap <= 15 and status ~= "Charging"
  local warn = not low and cap <= 30 and status ~= "Charging"
  local color = if low then "error" elseif warn then "tertiary" else "primary"
  local function cell()
    local segs = {}
    for i = 1, 4 do
      table.insert(segs, ui.box({ width = 3, height = 8, fill = if i <= lit then color else "outline_variant", opacity = if i <= lit then 1 else 0.45 }))
    end
    return ui.row({ gap = 0, align = "center" }, {
      ui.row({ gap = 1, padding = 2, border = if low then "error" else "on_surface_variant", borderWidth = 1, radius = 0 }, segs),
      ui.box({ width = 2, height = 5, fill = if low then "error" else "on_surface_variant" }),
    })
  end
  barWidget.render(common.chip({
    common.glow(hovered, cell),
    common.glow(hovered, function()
      return common.readout(string.format("%03d", cap), if low then "error" elseif warn then "tertiary" else "on_surface")
    end),
  }, noctalia.getConfig("tag") == true))
  local states = { Charging = "charging", Discharging = "on battery", Full = "full", ["Not charging"] = "plugged in" }
  common.tip(string.format("Battery: %d%% (%s)", cap, states[status] or string.lower(status)))
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end

function update()
  if bat == nil then
    barWidget.setVisible(false)
    noctalia.setUpdateInterval(60000)
    return
  end
  local now = noctalia.nowMs()
  if now >= nextRead then
    read()
    nextRead = now + 10000
  end
  if cap == nil then
    noctalia.setUpdateInterval(10000)
    return
  end
  local charging = status == "Charging"
  noctalia.setUpdateInterval(if charging then 450 else 10000)
  lit = math.clamp(math.ceil(cap / 25), 1, 4)
  if charging then
    -- Chase from the current level up to full, then restart.
    tick = (tick + 1) % (5 - lit + 1)
    lit = math.min(4, lit + tick)
  end
  render()
end
