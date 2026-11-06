--!nonstrict
-- Hyprland workspaces as slanted HUD tiles rendered by hud-build (bar/ws):
-- empty, occupied (acid tick), visible on another monitor, urgent, and the
-- focused tile, which glitches for two frames when it takes focus. Follows
-- Hyprland's event socket; the tile images carry the numbers.
local common = require("./common.luau")

local WS_DIR = common.dir .. "/ws"
local MAX_ID = 10 -- hud-build renders tiles 1..10

local workspaces = {} -- id -> window count
local activeOn = {} -- monitor name -> active workspace id
local urgent = {} -- id -> true
local myOutput = barWidget.outputName()
local shownActive = nil
local glitch = -1 -- glitch frame index, -1 when idle
local rendered = false
local publishedWidth = nil

-- Row geometry, kept in step with the image sizes below.
local CAP_W, TILE_W, ACTIVE_W, GAP = 12, 26, 38, 2

local function publishWidth(tiles, hasActive)
  local width = 2 * CAP_W + (tiles - (if hasActive then 1 else 0)) * TILE_W
    + (if hasActive then ACTIVE_W else 0) + (tiles + 1) * GAP
  if width ~= publishedWidth then
    local dir, path = common.wsWidthPath(myOutput)
    noctalia.mkdirAll(dir)
    if noctalia.writeFile(path, tostring(width)) then
      publishedWidth = width
    end
  end
end

local function tilePath(state, id)
  return string.format("%s/%s-%d.png", WS_DIR, state, id)
end

local function focus(id)
  noctalia.runAsync({ "hyprctl", "dispatch", string.format("hl.dsp.focus({ workspace = %d })", id) })
end

local function myActive()
  if myOutput and activeOn[myOutput] then
    return activeOn[myOutput]
  end
  -- Unknown output: fall back to any monitor's active workspace.
  for _, id in activeOn do
    return id
  end
  return nil
end

-- Only workspaces that hold windows, plus this monitor's focused one even when
-- empty, so the row always shows where you are.
local function shownIds()
  local mine = myActive()
  local ids = {}
  for id, count in workspaces do
    if id <= MAX_ID and (count > 0 or id == mine) then
      table.insert(ids, id)
    end
  end
  if mine and mine <= MAX_ID and workspaces[mine] == nil then
    table.insert(ids, mine)
  end
  table.sort(ids)
  return ids
end

local function render()
  if not noctalia.fileExists(tilePath("active", 1)) then
    -- hud-build swaps the tile directory in; keep the last row through that.
    if not rendered then
      common.missing()
    end
    return
  end
  rendered = true
  local mine = myActive()
  local visible = {}
  for out, id in activeOn do
    if out ~= myOutput then
      visible[id] = true
    end
  end
  local tiles = { ui.image({ path = WS_DIR .. "/cap-l.png", width = CAP_W, height = 20, fit = "contain" }) }
  local ids = shownIds()
  for _, id in ids do
    local state, width = "empty", TILE_W
    if id == mine then
      state, width = "active", ACTIVE_W
      if glitch >= 0 then
        state = "glitch" .. glitch
      end
    elseif urgent[id] then
      state = "urgent"
    elseif visible[id] then
      state = "visible"
    elseif (workspaces[id] or 0) > 0 then
      state = "occupied"
    end
    local count = workspaces[id] or 0
    table.insert(tiles, ui.image({
      key = "ws" .. id,
      path = tilePath(state, id),
      width = width,
      height = 20,
      fit = "stretch",
      onClick = function()
        focus(id)
      end,
      tooltip = string.format("Workspace %d · %d window%s", id, count, if count == 1 then "" else "s"),
    }))
  end
  table.insert(tiles, ui.image({ path = WS_DIR .. "/cap-r.png", width = CAP_W, height = 20, fit = "contain" }))
  barWidget.render(ui.row({ gap = GAP, align = "center" }, tiles))
  publishWidth(#ids, mine ~= nil and table.find(ids, mine) ~= nil)
end

local refresh = common.coalesced({ "sh", "-c", "hyprctl -j workspaces && echo @@ && hyprctl -j monitors" }, function(r)
  if r.exitCode ~= 0 then
    return
  end
  local a, b = string.match(r.stdout, "^(.*)\n@@\n(.*)$")
  local ws = a and noctalia.json.decode(a)
  local mons = b and noctalia.json.decode(b)
  if type(ws) ~= "table" or type(mons) ~= "table" then
    return
  end
  workspaces = {}
  for _, w in ws do
    if type(w.id) == "number" and w.id > 0 then
      workspaces[w.id] = w.windows or 0
    end
  end
  activeOn = {}
  for _, m in mons do
    if m.name and m.activeWorkspace and type(m.activeWorkspace.id) == "number" then
      activeOn[m.name] = m.activeWorkspace.id
    end
  end
  local mine = myActive()
  if mine then
    urgent[mine] = nil
  end
  for id in urgent do
    if workspaces[id] == nil then
      urgent[id] = nil -- the workspace (and its urgent window) is gone
    end
  end
  if shownActive ~= nil and mine ~= shownActive then
    glitch = 0
    noctalia.setUpdateInterval(70)
  end
  shownActive = mine
  render()
end)

-- urgent>>ADDRESS names a window; map it to its workspace.
local function markUrgent(addr)
  noctalia.runAsync({ "hyprctl", "-j", "clients" }, function(r)
    local clients = r.exitCode == 0 and noctalia.json.decode(r.stdout)
    if type(clients) ~= "table" then
      return
    end
    for _, c in clients do
      if c.address == "0x" .. addr and c.workspace and type(c.workspace.id) == "number" then
        if c.workspace.id ~= myActive() then
          urgent[c.workspace.id] = true
          render()
        end
        return
      end
    end
  end, 3000)
end

local EVENTS = {
  workspace = true, workspacev2 = true, focusedmon = true, focusedmonv2 = true,
  createworkspace = true, createworkspacev2 = true, destroyworkspace = true, destroyworkspacev2 = true,
  moveworkspace = true, moveworkspacev2 = true, openwindow = true, closewindow = true,
  movewindow = true, movewindowv2 = true, monitoradded = true, monitorremoved = true,
}

local sig = noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")
local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
if sig and runtime and noctalia.commandExists("ncat") then
  local sock = string.format("%s/hypr/%s/.socket2.sock", runtime, sig)
  -- The path comes from the environment: quote it for sh.
  noctalia.runStream("exec ncat -U '" .. string.gsub(sock, "'", "'\\''") .. "'", function(line)
    local ev, data = string.match(line, "^([%w]+)>>(.*)$")
    if ev == "urgent" then
      markUrgent(data)
    elseif ev and EVENTS[ev] then
      refresh()
    end
  end)
end

function onScroll(axis, steps)
  local cur = myActive()
  if axis ~= "vertical" or not cur or steps == 0 then
    return
  end
  local ids = shownIds()
  local at = table.find(ids, cur)
  if at == nil then
    return
  end
  local target = ids[math.clamp(at + (if steps > 0 then 1 else -1), 1, #ids)]
  if target ~= cur then
    focus(target)
  end
end

function update()
  if glitch >= 0 then
    glitch += 1
    if glitch > 1 then
      glitch = -1
      noctalia.setUpdateInterval(5000)
    end
    render()
    return
  end
  -- Events drive the widget; the poll only catches a dropped socket.
  noctalia.setUpdateInterval(5000)
  refresh()
end
