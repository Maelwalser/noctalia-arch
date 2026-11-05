--!nonstrict
-- Speaker readout: pixel icon, level and meter. Follows PipeWire through
-- `pactl subscribe`; clicks and scrolling are manifest actions (Noctalia IPC).
local common = require("./common.luau")

local level, muted = nil, false

local function render()
  if not common.hasAssets() then
    common.missing()
    return
  end
  if level == nil then
    return
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.image({ path = common.icon(if muted then "mute" else "vol"), width = 18, height = 18, fit = "contain" }),
    common.readout(if muted then "MUT" else string.format("%03d", level), if muted then "error" else "on_surface"),
    common.meter(if muted then 0 else level / 100, "primary"),
  }))
  barWidget.setTooltip(if muted then "Volume: muted" else string.format("Volume: %d%%", level))
end

local refresh = common.coalesced({ "wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@" }, function(r)
  if r.exitCode ~= 0 then
    return
  end
  local v = tonumber(string.match(r.stdout, "Volume:%s*([%d%.]+)"))
  if v then
    level = math.floor(v * 100 + 0.5)
    muted = string.find(r.stdout, "MUTED", 1, true) ~= nil
    render()
  end
end)

if noctalia.commandExists("pactl") then
  noctalia.runStream("pactl subscribe", function(line)
    if string.find(line, "sink", 1, true) or string.find(line, "server", 1, true) then
      refresh()
    end
  end)
end

function update()
  -- The event stream does the work; this is a slow safety net.
  noctalia.setUpdateInterval(30000)
  refresh()
end
