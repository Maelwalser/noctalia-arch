--!nonstrict
-- Hyprland workspaces as slanted HUD tiles rendered by hud-build (bar/ws):
-- empty, occupied (acid tick), visible on another monitor, urgent, and the
-- focused tile, which glitches for two frames when it takes focus. Follows
-- Hyprland's event socket; the tile images carry the numbers.
--
-- On the scrolling layout the workspaces lie above each other (ALT + J/K,
-- hyprland/bindings.lua) and left to right is the order of the columns, so a
-- row of numbers would say the wrong thing. There the widget is a drum: the
-- focused tile alone between the brackets, with the edge of a tile above and
-- below it when there is something that way, and a change of workspace rolls
-- the drum the way the screen slides.
local common = require("./common.luau")

local MAX_ID = 10 -- hud-build renders tiles 1..10

local workspaces = {} -- id -> window count
local activeOn = {} -- monitor name -> active workspace id
local scaleOn = {} -- monitor name -> device scale
local monitorOf = {} -- id -> monitor name, for workspaces that exist
local ruleMonitor = {} -- id -> monitor a workspace rule binds it to
local layoutOf = {} -- id -> tiled layout
local urgent = {} -- id -> true
local myOutput = barWidget.outputName()
local shownActive = nil
local glitch = -1 -- glitch frame index, -1 when idle
local rollFrom = nil -- the workspace the drum rolls away from during those frames
local rendered = false
local publishedWidth = nil

-- Row geometry, kept in step with the image sizes below.
local CAP_W, TILE_W, ACTIVE_W, GAP = 12, 26, 38, 2
-- The drum's canvas (hud-build WS_DRUM_*): the focused tile with DRUM_PAD of
-- clear room on each side, which the brackets are drawn into.
local DRUM_H, DRUM_PAD = 28, 7
-- roll<j>-<id>.png has the tile at rest for j = 2 and further up for a lower
-- j. Per frame of a roll down the stack: where the tile that leaves is and
-- where the one that comes; a roll up mirrors both (4 - j).
local ROLL_REST = 2
local ROLL_DOWN = { { from = 1, to = 4 }, { from = 0, to = 3 } }

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

-- hud-build finishes the tiles at device resolution, one set per output scale.
local function wsDir()
  return common.scaledDir("ws", myOutput and scaleOn[myOutput], "active-1.png")
end

local function tilePath(state, id)
  return string.format("%s/%s-%d.png", wsDir(), state, id)
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

-- Whether ALT + J/K can land on `id` from this output: a workspace that
-- exists is where it is, one that does not opens where its rule puts it.
local function reachable(id)
  if id < 1 or id > MAX_ID then
    return false
  end
  local mon = monitorOf[id] or ruleMonitor[id]
  return mon == nil or myOutput == nil or mon == myOutput
end

-- What lies above (step -1) or below (step 1) `mine` on this output: the ids
-- that hold windows, and the look of the edge that stands for them. An empty
-- edge is the free strip next door.
local function beyond(mine, step)
  local ids, state = {}, nil
  local id = mine + step
  while id >= 1 and id <= MAX_ID do
    if reachable(id) then
      if urgent[id] then
        state = "urgent"
      end
      if (workspaces[id] or 0) > 0 then
        table.insert(ids, id)
        state = state or "occupied"
      end
    end
    id += step
  end
  if state == nil and reachable(mine + step) then
    state = "empty"
  end
  return ids, state
end

local function drumImage(path, handlers)
  local node = { path = path, width = ACTIVE_W + 2 * DRUM_PAD, height = DRUM_H, fit = "stretch" }
  if handlers then
    node.onClick = handlers.onClick
    node.onHover = handlers.onHover
  end
  return ui.image(node)
end

local function renderDrum(mine)
  local dir = wsDir()
  local above, aboveState = beyond(mine, -1)
  local below, belowState = beyond(mine, 1)
  local count = workspaces[mine] or 0
  local tip = string.format("Workspace %d · %d window%s", mine, count, if count == 1 then "" else "s")
  if #above > 0 then
    table.sort(above)
    tip ..= " · above " .. table.concat(above, " ")
  end
  if #below > 0 then
    tip ..= " · below " .. table.concat(below, " ")
  end
  -- The top layer takes the pointer for the whole drum.
  local handlers = {
    onClick = function()
      noctalia.runAsync({ "qs", "-c", "hud", "ipc", "call", "overview", "toggle" })
    end,
    onHover = function(state)
      if state == "true" then
        common.tip(tip)
      end
      common.hover(state == "true")
    end,
  }
  local layers = {}
  local frame = if glitch >= 0 and rollFrom then ROLL_DOWN[glitch + 1] else nil
  if frame then
    local up = mine < rollFrom
    local function at(j)
      return if up then 2 * ROLL_REST - j else j
    end
    table.insert(layers, drumImage(string.format("%s/roll%d-%d.png", dir, at(frame.from), rollFrom)))
    table.insert(layers, drumImage(string.format("%s/roll%d-%d.png", dir, at(frame.to), mine), handlers))
  else
    if aboveState then
      table.insert(layers, drumImage(string.format("%s/sliver-up-%s.png", dir, aboveState)))
    end
    if belowState then
      table.insert(layers, drumImage(string.format("%s/sliver-down-%s.png", dir, belowState)))
    end
    table.insert(layers, drumImage(string.format("%s/roll%d-%d.png", dir, ROLL_REST, mine), handlers))
  end
  -- Layers lie over each other through the negative gap, and so do the
  -- brackets and the canvas's clear sides.
  barWidget.render(ui.row({ gap = GAP - DRUM_PAD, align = "center" }, {
    ui.image({ path = dir .. "/cap-l.png", width = CAP_W, height = 20, fit = "contain" }),
    ui.column({ gap = -DRUM_H, height = DRUM_H }, layers),
    ui.image({ path = dir .. "/cap-r.png", width = CAP_W, height = 20, fit = "contain" }),
  }))
  publishWidth(1, true)
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
  -- Tiles from before the drum have no canvases for it: the row serves.
  if mine and mine <= MAX_ID and layoutOf[mine] == "scrolling"
    and noctalia.fileExists(string.format("%s/roll%d-1.png", wsDir(), ROLL_REST)) then
    renderDrum(mine)
    return
  end
  local visible = {}
  for out, id in activeOn do
    if out ~= myOutput then
      visible[id] = true
    end
  end
  local dir = wsDir()
  local tiles = { ui.image({ path = dir .. "/cap-l.png", width = CAP_W, height = 20, fit = "contain" }) }
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
    local tip = string.format("Workspace %d · %d window%s", id, count, if count == 1 then "" else "s")
    table.insert(tiles, ui.image({
      key = "ws" .. id,
      path = tilePath(state, id),
      width = width,
      height = 20,
      fit = "stretch",
      onClick = function()
        focus(id)
      end,
      -- The glass tooltip (common.tip) instead of the node's own `tooltip`.
      onHover = function(state)
        if state == "true" then
          common.tip(tip)
        end
        common.hover(state == "true")
      end,
    }))
  end
  table.insert(tiles, ui.image({ path = dir .. "/cap-r.png", width = CAP_W, height = 20, fit = "contain" }))
  barWidget.render(ui.row({ gap = GAP, align = "center" }, tiles))
  publishWidth(#ids, mine ~= nil and table.find(ids, mine) ~= nil)
end

-- The rules only refine the drum's edges: without them the rest still shows.
--
-- Noctalia stops a callback that runs past its CPU budget and, after a few of
-- those, disables the widget for good: it then keeps its last picture, drum
-- or row, whatever happens. On a throttled CPU decoding everything hyprctl
-- says (every mode of every monitor) did run past it, so jq cuts the answers
-- down to the fields read here before they reach the script.
local QUERY = [[
pick() { if command -v jq >/dev/null 2>&1; then jq -c "$1"; else cat; fi; }
hyprctl -j workspaces | pick '[.[] | {id, windows, monitor, tiledLayout}]' && echo @@ &&
hyprctl -j monitors | pick '[.[] | {name, scale, activeWorkspace: {id: .activeWorkspace.id}}]' && echo @@ &&
{ hyprctl -j workspacerules 2>/dev/null || echo '[]'; } | pick '[.[] | {workspaceString, monitor}]'
]]

-- The three answers of QUERY. Plain finds: a pattern with three greedy
-- captures backtracks through the whole output.
local function split(out)
  local SEP = "\n@@\n"
  local a0, a1 = string.find(out, SEP, 1, true)
  if not a0 then
    return nil
  end
  local b0, b1 = string.find(out, SEP, a1 + 1, true)
  if not b0 then
    return nil
  end
  return string.sub(out, 1, a0 - 1), string.sub(out, a1 + 1, b0 - 1), string.sub(out, b1 + 1)
end

local refresh = common.coalesced({ "sh", "-c", QUERY }, function(r)
  if r.exitCode ~= 0 then
    return
  end
  local a, b, c = split(r.stdout)
  local ws = a and noctalia.json.decode(a)
  local mons = b and noctalia.json.decode(b)
  local rules = c and noctalia.json.decode(c)
  if type(ws) ~= "table" or type(mons) ~= "table" then
    return
  end
  workspaces, monitorOf, layoutOf = {}, {}, {}
  for _, w in ws do
    if type(w.id) == "number" and w.id > 0 then
      workspaces[w.id] = w.windows or 0
      monitorOf[w.id] = w.monitor
      layoutOf[w.id] = w.tiledLayout
    end
  end
  ruleMonitor = {}
  if type(rules) == "table" then
    for _, rule in rules do
      local id = tonumber(rule.workspaceString)
      if id and type(rule.monitor) == "string" then
        ruleMonitor[id] = rule.monitor
      end
    end
  end
  activeOn = {}
  for _, m in mons do
    if m.name and m.activeWorkspace and type(m.activeWorkspace.id) == "number" then
      activeOn[m.name] = m.activeWorkspace.id
    end
    if m.name and type(m.scale) == "number" then
      scaleOn[m.name] = m.scale
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
    rollFrom = if mine and shownActive <= MAX_ID then shownActive else nil
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
  custom = true, -- bindings.lua set_layout: a layout change has no event of its own
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
