--!nonstrict
local PREVIEW = "alchemistaloha/noctalia-overview:preview"
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"
local hypr = require("./lib/hypr.luau")
local active = 1
local activeOutput = nil
local windows = {}
local workspaces = {}
local displayedIds = {}
local monitorNames = {}
local busy = false
local hoverOpen = noctalia.state.get("preview_open") == true
local overviewOpen = noctalia.state.get("overview_open") == true
local overviewRequested = false
local pointerInside = false
local suppressHover = overviewOpen

noctalia.setUpdateInterval(1500)
barWidget.setTooltip(noctalia.tr("widget.tooltip"))
noctalia.state.watch("preview_open", function(value)
  if value == false then hoverOpen = false end
end)
noctalia.state.watch("overview_open", function(value)
  overviewOpen = value == true
  if overviewOpen then
    suppressHover = true
  else
    overviewRequested = false
    if not pointerInside then suppressHover = false end
  end
end)

local function currentOutput()
  local name = barWidget.outputName()
  if type(name) == "string" and name ~= "" then return name end
  return noctalia.focusedOutputName()
end

local function render()
  local columns = noctalia.getConfig("columns") or 5
  local children = {}
  local ids = {}
  local seen = {}
  local otherOutputIds = {}
  local output = currentOutput()
  local showSpecial = noctalia.getConfig("show_special") == true
  local showExtraEmpty = noctalia.getConfig("show_empty_bar") == true
  local anchor = active > 0 and output == activeOutput and active or nil
  local function add(id)
    if not seen[id] then ids[#ids + 1] = id; seen[id] = true end
  end
  for _, ws in ipairs(workspaces) do
    local id = tonumber(ws.id)
    local special = (id and id < 0) or (type(ws.name) == "string" and string.sub(ws.name, 1, 8) == "special:")
    local monitor = ws.monitor
    if type(monitor) == "number" then monitor = monitorNames[monitor] end
    if monitor == nil or monitor == "" then monitor = monitorNames[tonumber(ws.monitorID)] end
    local onOutput = output ~= nil and monitor == output
    if id and monitor and output and monitor ~= output then otherOutputIds[id] = true end
    if onOutput and id then
      if special and showSpecial then
        add(id)
      elseif not special then
        if not anchor then anchor = id end
        if showExtraEmpty or (tonumber(ws.windows) or 0) > 0 or id == active then add(id) end
      end
    end
  end
  -- Hyprland lists created workspaces, not the inactive slots shown by the
  -- native bar. Keep one compact row of slots around this monitor's active ID.
  if output and anchor and anchor > 0 then
    local first = math.floor((anchor - 1) / columns) * columns + 1
    for id = first, first + columns - 1 do
      if not otherOutputIds[id] or (id == active and output == activeOutput) then add(id) end
    end
  end
  table.sort(ids, function(a, b)
    if (a < 0) ~= (b < 0) then return a >= 0 end
    return a < b
  end)
  displayedIds = ids
  for _, id in ipairs(ids) do
    local occupied = windows[id] and windows[id] > 0
    local selected = id == active

    -- Match the built-in unlabeled pill style: the active slot is 2.5x wider.
    table.insert(children, ui.box({
      key = "ws-" .. id,
      width = selected and 40 or 16,
      height = 16,
      radius = 8,
      fill = selected and "primary" or (occupied and "secondary" or "on_surface_variant/0.35"),
    }))
  end
  if barWidget.isVertical() then
    local columnsChildren = {}
    for row = 0, math.ceil(#children / columns) - 1 do
      local rowChildren = {}
      for column = 0, columns - 1 do
        local child = children[row * columns + column + 1]
        if child then table.insert(rowChildren, child) end
      end
      table.insert(columnsChildren, ui.row({ gap = 4, align = "center" }, rowChildren))
    end
    barWidget.render(ui.column({ gap = 4, padding = 4, align = "center", radius = 999,
      fill = "on_primary" }, columnsChildren))
  else
    barWidget.render(ui.row({ gap = 4, padding = 4, align = "center", radius = 999,
      fill = "on_primary" }, children))
  end
end

function update()
  if busy then return end
  busy = true
  local accepted = noctalia.runAsync({ "hyprctl", "-j", "monitors" }, function(result)
    if result.exitCode == 0 then
      local monitors = noctalia.json.decode(result.stdout) or {}
      local name = currentOutput()
      local nextMonitorNames = {}
      activeOutput = nil
      for _, monitor in ipairs(monitors) do
        if monitor.id ~= nil then nextMonitorNames[tonumber(monitor.id)] = monitor.name end
        if name ~= nil and monitor.name == name then
          active = tonumber(monitor.activeWorkspace and monitor.activeWorkspace.id) or active
          activeOutput = name
        end
      end
      monitorNames = nextMonitorNames
    end
    busy = false
    render()
  end)
  if not accepted then busy = false end
  noctalia.runAsync({ "hyprctl", "-j", "workspaces" }, function(result)
    if result.exitCode ~= 0 then return end
    local list = noctalia.json.decode(result.stdout) or {}
    local nextWindows = {}
    for _, workspace in ipairs(list) do
      local id = tonumber(workspace.id)
      if id then nextWindows[id] = tonumber(workspace.windows) or 0 end
    end
    workspaces = list
    windows = nextWindows
    render()
  end)
end

function onHover(entered)
  pointerInside = entered == true
  if not pointerInside then
    if hoverOpen then
      hoverOpen = false
      noctalia.togglePanel(PREVIEW)
    end
    if not overviewOpen and not overviewRequested then suppressHover = false end
    return
  end
  if suppressHover or overviewOpen or overviewRequested or not noctalia.getConfig("show_hover_preview") then return end
  if not hoverOpen then
    noctalia.state.set("hover_output", currentOutput() or "")
    hoverOpen = true
    noctalia.togglePanel(PREVIEW)
  end
end

function onClick()
  overviewRequested = true
  suppressHover = true
  if hoverOpen then
    hoverOpen = false
    noctalia.togglePanel(PREVIEW)
  end
  noctalia.state.set("overview_output", currentOutput() or "")
  noctalia.togglePanel(OVERVIEW)
end

function onRightClick()
  noctalia.openSettings()
end

function onScroll(axis, steps)
  if axis ~= "vertical" or steps == 0 or #displayedIds == 0 then return end
  local index = nil
  for position, id in ipairs(displayedIds) do
    if id == active then index = position; break end
  end
  local direction = steps < 0 and 1 or -1
  if index == nil then index = direction > 0 and #displayedIds or 1 end
  local targetIndex = ((index - 1 + direction + #displayedIds) % #displayedIds) + 1
  local target = displayedIds[targetIndex]
  if target < 0 then
    for _, ws in ipairs(workspaces) do
      if tonumber(ws.id) == target then
        hypr.dispatch("togglespecialworkspace", string.gsub(tostring(ws.name or "special"), "^special:", ""))
        return
      end
    end
  else
    hypr.dispatch("workspace", tostring(target))
  end
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    overviewRequested = true
    suppressHover = true
    if hoverOpen then
      hoverOpen = false
      noctalia.togglePanel(PREVIEW)
    end
    noctalia.state.set("overview_output", currentOutput() or "")
    noctalia.togglePanel(OVERVIEW)
  elseif event == "preview" then
    noctalia.togglePanel(PREVIEW)
  end
end

render()
