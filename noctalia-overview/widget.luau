--!nonstrict
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"

barWidget.setTooltip(noctalia.tr("widget.tooltip"))

local function render()
  barWidget.render(ui.row({ gap = 5, paddingH = 3, align = "center" }, {
    ui.glyph({ name = "layout-dashboard", size = 16, color = "on_surface" }),
  }))
end

function onClick()
  -- The panel follows the focused output on open, so a click on this bar lands
  -- on this bar's monitor without recording anything.
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
