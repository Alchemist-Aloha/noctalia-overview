--!nonstrict
local OVERVIEW = "alchemistaloha/noctalia-overview:overview"
local hypr = require("./lib/hypr.luau")

shortcut.setLabel(noctalia.tr("panel.title"))
shortcut.setIcon("layout-dashboard", "layout-dashboard")
shortcut.setActive(false)

-- Pick the overview variant that fits every workspace so the control-center
-- shortcut opens the same dynamically sized window the bar widget uses.
local function openOverview()
  noctalia.state.set("overview_output", "")
  local columns = noctalia.getConfig("columns") or 5
  hypr.fetch(function(snapshot)
    local bucket, content = hypr.pickPanel(snapshot, "", noctalia.getConfig("rows") or 2, columns,
      noctalia.getConfig("show_empty"), noctalia.getConfig("show_special"), false)
    noctalia.state.set("overview_content", content)
    local id = hypr.bucketId(OVERVIEW, bucket)
    noctalia.state.set("overview_panel", id)
    noctalia.togglePanel(id)
  end)
end

local function closeOverview()
  local id = noctalia.state.get("overview_panel")
  if type(id) == "string" and id ~= "" then
    noctalia.togglePanel(id)
  end
  noctalia.state.set("overview_panel", "")
end

function onClick()
  if noctalia.state.get("overview_open") == true then
    closeOverview()
    return
  end
  openOverview()
end

function onIpc(event)
  if event == "toggle" or event == "open" then
    onClick()
  end
end
