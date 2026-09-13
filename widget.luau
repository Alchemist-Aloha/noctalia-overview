--!nonstrict
local PREVIEW = "alchemistaloha/noctalia-overview:preview"
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"
local hypr = require("./lib/hypr.luau")
local busy = false
local snapshot = nil
local previewPanel = nil
local overviewPanel = nil
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

-- Choose the panel variant that fits the workspaces on this monitor, using the
-- same metrics the panel renderer uses.
local function pickPanel(base, wantPreview)
  local snap = snapshot
  if snap == nil then return base end
  local columns = noctalia.getConfig("columns") or 5
  local bucket, content = hypr.pickPanel(snap, currentOutput(), noctalia.getConfig("rows") or 2, columns,
    noctalia.getConfig("show_empty"), noctalia.getConfig("show_special"), wantPreview)
  noctalia.state.set(wantPreview and "preview_content" or "overview_content", content)
  return hypr.bucketId(base, bucket)
end

local function render()
  barWidget.render(ui.row({ gap = 5, paddingH = 3, align = "center" }, {
    ui.glyph({ name = "layout-dashboard", size = 16, color = "on_surface" }),
  }))
end

function update()
  if busy then return end
  busy = true
  hypr.fetch(function(result)
    busy = false
    snapshot = result
  end)
end

local function closePanel(localId, stateKey)
  local id = localId
  if type(id) ~= "string" or id == "" then
    local stored = noctalia.state.get(stateKey)
    if type(stored) == "string" and stored ~= "" then id = stored end
  end
  if type(id) == "string" and id ~= "" then
    noctalia.togglePanel(id)
  end
  noctalia.state.set(stateKey, "")
  return nil
end

local function openPreviewPanel()
  noctalia.state.set("hover_output", currentOutput() or "")
  local id = pickPanel(PREVIEW, true)
  noctalia.state.set("preview_panel", id)
  hoverOpen = true
  noctalia.togglePanel(id)
end

local function openOverviewPanel()
  noctalia.state.set("overview_output", currentOutput() or "")
  local id = pickPanel(OVERVIEW, false)
  noctalia.state.set("overview_panel", id)
  overviewRequested = true
  suppressHover = true
  noctalia.togglePanel(id)
end

function onHover(entered)
  pointerInside = entered == true
  if not pointerInside then
    if hoverOpen then
      hoverOpen = false
      previewPanel = closePanel(previewPanel, "preview_panel")
    end
    if not overviewOpen and not overviewRequested then suppressHover = false end
    return
  end
  if suppressHover or overviewOpen or overviewRequested or not noctalia.getConfig("show_hover_preview") then return end
  if not hoverOpen then
    openPreviewPanel()
  end
end

function onClick()
  if overviewOpen then
    overviewPanel = closePanel(overviewPanel, "overview_panel")
    return
  end
  if hoverOpen then
    hoverOpen = false
    previewPanel = closePanel(previewPanel, "preview_panel")
  end
  openOverviewPanel()
end

function onRightClick()
  noctalia.openSettings()
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    if overviewOpen then
      overviewPanel = closePanel(overviewPanel, "overview_panel")
      return
    end
    if hoverOpen then
      hoverOpen = false
      previewPanel = closePanel(previewPanel, "preview_panel")
    end
    openOverviewPanel()
  elseif event == "preview" then
    if noctalia.state.get("preview_open") == true then
      previewPanel = closePanel(previewPanel, "preview_panel")
    else
      openPreviewPanel()
    end
  end
end

render()
