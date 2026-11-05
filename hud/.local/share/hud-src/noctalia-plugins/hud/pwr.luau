--!nonstrict
-- Battery cell drawn from boxes: four charge segments that chase upwards while
-- charging, red at or below 15 %. Hidden on machines without a battery.
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

local function read()
  cap = tonumber(noctalia.readFile(bat .. "/capacity") or "")
  -- Trim only the ends: the kernel reports "Not charging" with a space.
  status = string.match(noctalia.readFile(bat .. "/status") or "", "^%s*(.-)%s*$")
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
  local low = cap <= 15 and not charging
  local color = if low then "error" else "primary"
  local lit = math.clamp(math.ceil(cap / 25), 1, 4)
  if charging then
    -- Chase from the current level up to full, then restart.
    tick = (tick + 1) % (5 - lit + 1)
    lit = math.min(4, lit + tick)
  end
  local segs = {}
  for i = 1, 4 do
    table.insert(segs, ui.box({ width = 3, height = 8, fill = if i <= lit then color else "outline_variant", opacity = if i <= lit then 1 else 0.45 }))
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.row({ gap = 0, align = "center" }, {
      ui.row({ gap = 1, padding = 2, border = if low then "error" else "on_surface_variant", borderWidth = 1, radius = 0 }, segs),
      ui.box({ width = 2, height = 5, fill = if low then "error" else "on_surface_variant" }),
    }),
    common.readout(string.format("%03d", cap), if low then "error" else "on_surface"),
  }))
  local states = { Charging = "charging", Discharging = "on battery", Full = "full", ["Not charging"] = "plugged in" }
  barWidget.setTooltip(string.format("Battery: %d%% (%s)", cap, states[status] or string.lower(status)))
end
