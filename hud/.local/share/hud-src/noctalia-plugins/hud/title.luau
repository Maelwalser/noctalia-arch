--!nonstrict
-- Title of the focused window, as wide as the start lane has room for.
--
-- Noctalia's own active_window widget takes one fixed max_length, but the room
-- differs per output and changes while running: the lane ends at the centred
-- workspace row (which grows with every workspace) and the media readout before
-- this widget comes and goes. So the width is computed like the equalizer's:
-- half the output minus half the row, minus `gap`, minus `reserve` (everything
-- left of the title) and, while an MPRIS player exists, `media_reserve`.
--
-- Plugins get no window or media API here (plugin_api 32), so the title comes
-- from Hyprland's event socket and the player check from the session bus.
local common = require("./common.luau")

-- Below about twelve characters an ellipsized stub ("Con…") says nothing:
-- draw nothing.
local MIN_WIDTH = 96

local myOutput = barWidget.outputName()
local title = ""
local activeAddr = nil
local media = false
local maxWidth = 0
local drawn = nil -- "<maxWidth>|<title>" of the last render

local function outputWidth()
  for _, o in noctalia.outputs() do
    if o.name == myOutput then
      return o.width -- logical px, like the bar layout
    end
  end
  return nil
end

local function fitWidth()
  local _, path = common.wsWidthPath(myOutput)
  local ws = tonumber(noctalia.readFile(path) or "")
  local w = outputWidth()
  if not ws or not w then
    return maxWidth
  end
  local room = w / 2 - ws / 2 - (noctalia.getConfig("gap") or 13) - (noctalia.getConfig("reserve") or 510)
  if media then
    room -= noctalia.getConfig("media_reserve") or 180
  end
  return math.max(0, math.floor(room))
end

local function render()
  local key = string.format("%d|%s", maxWidth, title)
  if key == drawn then
    return
  end
  drawn = key
  if title == "" or maxWidth < MIN_WIDTH then
    common.tip("")
    barWidget.render(ui.box({ width = 0, height = 0, fill = "on_surface/0.00" }))
    return
  end
  common.tip(title)
  barWidget.render(ui.label({ text = title, color = "on_surface_variant", maxWidth = maxWidth, maxLines = 1 }))
end

local function setTitle(t)
  title = t or ""
  render()
end

-- Hyprland socket2 lines are `event>>data`; only the first comma separates
-- fields, a title may hold more.
local function onEvent(line)
  local event, data = string.match(line, "^(%w+)>>(.*)$")
  if event == "activewindow" then
    setTitle(string.match(data, "^[^,]*,(.*)$"))
  elseif event == "activewindowv2" then
    activeAddr = data
  elseif event == "windowtitlev2" then
    local addr, t = string.match(data, "^([^,]*),(.*)$")
    if addr and addr == activeAddr then
      setTitle(t)
    end
  end
end

local function syncTitle()
  noctalia.runAsync({ "hyprctl", "-j", "activewindow" }, function(r)
    local win = r.exitCode == 0 and noctalia.json.decode(r.stdout)
    if type(win) == "table" then
      activeAddr = if type(win.address) == "string" then string.gsub(win.address, "^0x", "") else nil
      setTitle(if type(win.title) == "string" then win.title else "")
    end
  end, 3000)
end

-- The media readout hides without a player, so a player on the bus is what
-- costs the title its room.
local function syncMedia()
  noctalia.runAsync("busctl --user list --no-legend | grep -c '^org\\.mpris\\.MediaPlayer2\\.'", function(r)
    local shown = (tonumber(r.stdout) or 0) > 0
    if shown ~= media then
      media = shown
      maxWidth = fitWidth()
      render()
    end
  end, 3000)
end

function update()
  -- A cheap poll (one small file) so the width follows the workspace row.
  noctalia.setUpdateInterval(1000)
  maxWidth = fitWidth()
  render()
end

noctalia.runStream(
  'exec nc -U "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"',
  onEvent
)
noctalia.runStream(
  "exec dbus-monitor --session \"type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',arg0namespace='org.mpris.MediaPlayer2'\"",
  function(line)
    if string.find(line, "org.mpris.MediaPlayer2", 1, true) then
      syncMedia()
    end
  end
)
syncTitle()
syncMedia()

function onHover(inside)
  common.hover(inside)
end
