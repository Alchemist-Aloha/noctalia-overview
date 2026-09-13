--!nonstrict
local surface = require("./lib/surface.luau").new(true)

function onOpen(context)
  noctalia.state.set("preview_open", true)
  surface:open(context)
end
function onClose()
  noctalia.state.set("preview_open", false)
  surface:close()
end
function update() surface:update() end
function onExit() surface:close() end
function onIpc(event)
  if event == "close" then panel.close()
  elseif event == "refresh" then surface:update() end
end
