--!nonstrict
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"
local overviewOpen = noctalia.state.get("overview_open") == true

barWidget.setTooltip(noctalia.tr("widget.tooltip"))
noctalia.state.watch("overview_open", function(value)
  overviewOpen = value == true
end)

local function currentOutput()
  local name = barWidget.outputName()
  if type(name) == "string" and name ~= "" then return name end
  return noctalia.focusedOutputName()
end

local function render()
  barWidget.render(ui.row({ gap = 5, paddingH = 3, align = "center" }, {
    ui.glyph({ name = "layout-dashboard", size = 16, color = "on_surface" }),
  }))
end

function onClick()
  if not overviewOpen then
    noctalia.state.set("overview_output", currentOutput() or "")
  end
  noctalia.togglePanel(OVERVIEW)
end

function onRightClick()
  noctalia.openSettings()
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    onClick()
  end
end

render()
