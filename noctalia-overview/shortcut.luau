--!nonstrict
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"

shortcut.setLabel(noctalia.tr("panel.title"))
shortcut.setIcon("layout-dashboard", "layout-dashboard")
shortcut.setActive(false)

function onClick()
  noctalia.state.set("overview_output", "")
  noctalia.togglePanel(OVERVIEW)
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    onClick()
  end
end
