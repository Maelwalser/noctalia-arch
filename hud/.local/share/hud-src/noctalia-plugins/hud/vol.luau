--!nonstrict
-- Speaker readout: outlined speaker (hud-build icon) and level. Follows PipeWire through
-- `pactl subscribe`; clicks and scrolling are manifest actions (Noctalia IPC).
local common = require("./common.luau")

local level, muted = nil, false
local hovered = false

local function render()
  if not common.hasAssets() then
    common.missing()
    return
  end
  if level == nil then
    return
  end
  -- 0 % shows the muted speaker in the normal colour; red is kept for a real mute.
  local icon = if muted then "mute" elseif level == 0 then "silent" else "vol"
  barWidget.render(common.chip({
    common.glow(hovered, function()
      return ui.image({ path = common.icon(icon), width = 18, height = 18, fit = "contain" })
    end),
    common.glow(hovered, function()
      return common.readout(if muted then "MUT" else string.format("%03d", level), if muted then "error" else "on_surface")
    end),
  }, noctalia.getConfig("tag") == true))
  common.tip(if muted then "Volume: muted" else string.format("Volume: %d%%", level))
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

function onHover(inside)
  hovered = inside
  common.hover(inside)
  render()
end

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

-- Swap in this output's icon set once its scale is known.
common.resolveIcons(render)
