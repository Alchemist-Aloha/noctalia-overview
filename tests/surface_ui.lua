-- Run from the plugin directory: lua tests/surface_ui.lua
local function node(kind, props, children)
  return { kind = kind, props = props or {}, children = children or {} }
end

local ui = {}
for _, kind in ipairs({ "row", "column", "scroll", "button", "label", "glyph", "image", "dragSource", "dropZone" }) do
  ui[kind] = function(props, children) return node(kind, props, children) end
end

local visible = {}
for id = 1, 10 do
  local clients = { { address = "0x" .. string.format("%x", id), class = "test", title = "Window " .. id,
    at = { 0, 0 }, size = { 1920, 1080 } } }
  if id == 1 then
    -- Master on the left, two stacked windows on the right.
    clients[1].at, clients[1].size = { 0, 0 }, { 960, 1080 }
    clients[2] = { address = "0x21", class = "test", title = "Second", at = { 960, 0 }, size = { 960, 540 } }
    clients[3] = { address = "0x22", class = "test", title = "Third", at = { 960, 540 }, size = { 960, 540 } }
  elseif id == 2 then
    -- Two windows stacked top/bottom.
    clients[1].at, clients[1].size = { 0, 0 }, { 1920, 540 }
    clients[2] = { address = "0x32", class = "test", title = "Below", at = { 0, 540 }, size = { 1920, 540 } }
  end
  visible[id] = { id = id, name = tostring(id), active = id == 1, clients = clients, monitor = "TEST-1" }
end

local config = { rows = 2, columns = 5, show_empty = true, show_special = false,
  max_captures = 20, capture_interval_ms = 1200 }
local rendered
local captured = {}
-- Reuse the real (pure) layout helpers so the test exercises the shared math.
local realHypr = assert(loadfile("lib/hypr.luau", "t", setmetatable({}, { __index = _G })))()
local hypr = setmetatable({
  fetch = function(callback) callback({ monitors = { {} }, clients = {}, workspaces = {} }) end,
  visible = function() return visible end,
  dispatch = function() end,
  newCaptureManager = function(_, onImage)
    return {
      path = function(_, client) return captured[client.address] end,
      update = function(_, clients)
        captured = {}
        for _, client in ipairs(clients) do captured[client.address] = "/tmp/mock.png" end
        onImage()
      end,
      clear = function() captured = {} end,
    }
  end,
}, { __index = realHypr })

local env = setmetatable({
  ui = ui,
  require = function() return hypr end,
  noctalia = {
    getConfig = function(key) return config[key] end,
    tr = function(key) return key end,
    appIconPath = function() return nil end,
    state = { get = function() return "" end, set = function() end },
    setUpdateInterval = function() end,
  },
  panel = { render = function(tree) rendered = tree end, close = function() end },
}, { __index = _G })

local surface = assert(loadfile("lib/surface.luau", "t", env))().new(false)
surface:open("")
assert(rendered.kind == "column", "panel header and footer should stay outside scroll")
assert(rendered.children[2].kind == "scroll", "workspace grid should scroll independently")
assert(#rendered.children[2].children == 2, "ten configured columns should reflow to five per row")
assert(rendered.children[2].children[1].children[1].props.fill == "primary/0.18", "active workspace should stand out")
assert(rendered.children[2].children[1].children[1].props.borderWidth == 2, "keyboard selection should have a border")
local firstWindow = rendered.children[2].children[1].children[1].children[2].children[1].children[1]
firstWindow.props.onHover(true)
firstWindow = rendered.children[2].children[1].children[1].children[2].children[1].children[1]
assert(firstWindow.props.border == "primary/0.7", "hovered window should be highlighted")
assert(#firstWindow.children == 1, "window tiles should not add a title caption")
local layout = rendered.children[2].children[1].children[1].children[2]
assert(layout.kind == "row", "master and stack should split into columns")
assert(layout.children[2].kind == "column", "stacked windows should split into rows")
local stackedLayout = rendered.children[2].children[1].children[2].children[2]
assert(stackedLayout.kind == "column", "top/bottom windows should split into rows")
local captureCount = 0
for _ in pairs(captured) do captureCount = captureCount + 1 end
assert(captureCount == 13, "capture budget should cover every window shown in a workspace")
surface:key("Down", true)
assert(rendered.children[2].children[2].children[1].props.borderWidth == 2, "keyboard movement should match displayed columns")
surface:key("Escape", true)

local preview = assert(loadfile("lib/surface.luau", "t", env))().new(true)
preview:open("")
assert(#rendered.children[2].children == 2, "hover preview should reflow to five cards per row")
assert(rendered.children[2].children[1].children[1].props.height == 116, "preview cards should be 30% smaller than the overview")

-- Fewer workspaces than configured columns should widen the cards to fill the row.
visible = { visible[1], visible[2] }
local adaptive = assert(loadfile("lib/surface.luau", "t", env))().new(false)
adaptive:open("")
assert(#rendered.children[2].children == 1 and #rendered.children[2].children[1].children == 2,
  "two workspaces should lay out as two columns")
assert(rendered.children[2].children[1].children[1].props.width > 205,
  "fewer workspaces should get larger cards")
print("surface UI checks passed")
