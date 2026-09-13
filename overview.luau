--!nonstrict
local surface = require("./lib/surface.luau").new(false)

function onOpen(context)
  noctalia.state.set("overview_open", true)
  surface:open(context)
end
function onClose()
  noctalia.state.set("overview_open", false)
  surface:close()
end
function update() surface:update() end
function onKey(chord, pressed) surface:key(chord, pressed) end
function onExit()
  noctalia.state.set("overview_open", false)
  surface:close()
end
function onIpc(event)
  if event == "close" then panel.close()
  elseif event == "refresh" then surface:update() end
end
