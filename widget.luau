--!nonstrict
local PREVIEW = "alchemistaloha/noctalia-overview:preview"
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"
local hypr = require("./lib/hypr.luau")
local active = 1
local windows = {}
local busy = false
local hoverOpen = false

noctalia.setUpdateInterval(1500)
noctalia.state.watch("preview_open", function(value)
  if value == false then hoverOpen = false end
end)

local function render()
  local rows = noctalia.getConfig("rows") or 2
  local columns = noctalia.getConfig("columns") or 5
  local count = rows * columns
  local start = math.floor((math.max(active, 1) - 1) / count) * count + 1
  local children = {}
  for i = 0, count - 1 do
    local id = start + i
    if not barWidget.isVertical() or i < columns then
      local occupied = windows[id] and windows[id] > 0
      table.insert(children, ui.label({
        key = "ws-" .. id,
        text = tostring(id) .. (occupied and "•" or ""),
        color = id == active and "primary" or "on_surface",
        fontWeight = id == active and "bold" or "medium",
      }))
    end
  end
  if barWidget.isVertical() then
    barWidget.render(ui.column({ gap = 3, padding = 4, align = "center" }, children))
  else
    barWidget.render(ui.row({ gap = 8, paddingH = 8, align = "center" }, children))
  end
end

function update()
  if busy then return end
  busy = true
  local accepted = noctalia.runAsync({ "hyprctl", "monitors", "-j" }, function(result)
    if result.exitCode == 0 then
      local monitors = noctalia.json.decode(result.stdout) or {}
      local name = barWidget.outputName()
      for _, monitor in ipairs(monitors) do
        if name == nil or monitor.name == name then
          active = (monitor.activeWorkspace and monitor.activeWorkspace.id) or active
          break
        end
      end
    end
    busy = false
    render()
  end)
  if not accepted then busy = false end
  noctalia.runAsync({ "hyprctl", "workspaces", "-j" }, function(result)
    if result.exitCode ~= 0 then return end
    local list = noctalia.json.decode(result.stdout) or {}
    local nextWindows = {}
    for _, workspace in ipairs(list) do
      nextWindows[workspace.id] = workspace.windows or 0
    end
    windows = nextWindows
    render()
  end)
end

function onHover(entered)
  if not noctalia.getConfig("show_hover_preview") then return end
  if entered and not hoverOpen then
    noctalia.state.set("hover_output", barWidget.outputName() or "")
    hoverOpen = true
    noctalia.togglePanel(PREVIEW)
  elseif not entered and hoverOpen then
    hoverOpen = false
    noctalia.togglePanel(PREVIEW)
  end
end

function onClick()
  if hoverOpen then
    hoverOpen = false
    noctalia.togglePanel(PREVIEW)
  end
  noctalia.state.set("overview_output", barWidget.outputName() or "")
  noctalia.togglePanel(OVERVIEW)
end

function onRightClick()
  noctalia.openSettings()
end

function onScroll(axis, steps)
  if axis ~= "vertical" or steps == 0 then return end
  local target = math.max(1, active + (steps < 0 and 1 or -1))
  hypr.dispatch("workspace", tostring(target))
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    noctalia.togglePanel(OVERVIEW)
  elseif event == "preview" then
    noctalia.togglePanel(PREVIEW)
  end
end

render()
