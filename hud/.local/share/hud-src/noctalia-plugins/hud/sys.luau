--!nonstrict
-- System panel: CPU load, CPU temperature and memory as plain readouts in one
-- pill. All three open the same panel (manifest action), so the pill is one
-- target and all of its text glows on hover.
local common = require("./common.luau")

local hovered = false
local drawn = nil

local function hairline()
  return ui.box({ width = 1, height = 12, fill = "outline_variant" })
end

-- Fixed-width fields (Departure Mono is monospaced), so the pill keeps its
-- width while the values change.
local function field(fmt, blank, value)
  return if value then string.format(fmt, math.floor(value + 0.5)) else blank
end

-- A value turns amber at `warn` and red at `crit`: the two palette roles the
-- bar otherwise keeps for highlights and faults.
local function level(value, warn, crit)
  if not value then
    return "on_surface"
  end
  return if value >= crit then "error" elseif value >= warn then "tertiary" else "on_surface"
end

local function render()
  local s = noctalia.systemStats() -- nil while [system.monitor] is off
  local cpu = field("%3d%%", " --%", s and s.cpu.usagePercent)
  local tmp = field("%2d°C", "--°C", s and s.cpu.tempC)
  local mem = field("%3d%%", " --%", s and s.ram.usagePercent)
  local tmpColor = level(s and s.cpu.tempC, 85, 95)
  local memColor = level(s and s.ram.usagePercent, 80, 92)
  local key = table.concat({ cpu, tmp, mem, tmpColor, memColor, tostring(hovered) }, "|")
  if key == drawn then
    return
  end
  drawn = key
  local function text(value, color)
    return common.glow(hovered, function()
      return common.readout(value, color)
    end)
  end
  -- Label and value 6 px apart, 8 px to each hairline. The pill's row already
  -- puts 6 px between the ink of neighbouring glow() nodes; around a hairline
  -- (no glow padding of its own) that leaves 6 - GLOW, the spacers add the rest.
  local function divider()
    local pad = common.space(8 - 6 + common.GLOW, 1)
    return ui.row({ gap = 0, align = "center" }, { pad, hairline(), pad })
  end
  barWidget.render(common.pill({
    text("CPU", "primary"), text(cpu, "on_surface"), divider(),
    text("TMP", "primary"), text(tmp, tmpColor), divider(),
    text("MEM", "primary"), text(mem, memColor),
  }, true, 6))
  if s then
    local trim = function(v)
      return (string.gsub(v, "^%s+", ""))
    end
    common.tip(string.format("CPU %s · %s\nMemory %s (%.1f / %.1f GB)", trim(cpu), tmp, trim(mem), s.ram.usedMb / 1024, s.ram.totalMb / 1024))
  else
    common.tip("System monitor is off")
  end
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end

function update()
  noctalia.setUpdateInterval(2000) -- the host samples the CPU every 2 s
  render()
end
