-- Run from the plugin directory: lua tests/surface_ui.lua
local function node(kind, props, children)
  return { kind = kind, props = props or {}, children = children or {} }
end

local ui = {}
for _, kind in ipairs({ "row", "column", "scroll", "button", "label", "glyph", "image", "dragSource", "dropZone", "spacer" }) do
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
    pluginDir = function() return nil end,
  },
  panel = { render = function(tree) rendered = tree end, close = function() end },
}, { __index = _G })

local surface = assert(loadfile("lib/surface.luau", "t", env))().new()
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

-- Fewer workspaces than configured columns should widen the cards to fill the row.
visible = { visible[1], visible[2] }
local adaptive = assert(loadfile("lib/surface.luau", "t", env))().new()
adaptive:open("")
assert(#rendered.children[2].children == 1 and #rendered.children[2].children[1].children == 2,
  "two workspaces should lay out as two columns")
assert(rendered.children[2].children[1].children[1].props.width > 205,
  "fewer workspaces should get larger cards")

-- Hypr.visible must not invent workspace slots for other monitors.
local wsSnapshot = {
  monitors = {
    { id = 0, name = "TEST-1", activeWorkspace = { id = 4 } },
    { id = 1, name = "OTHER", activeWorkspace = { id = 1 } },
  },
  workspaces = {
    { id = 1, name = "1", monitor = "OTHER", monitorID = 1, windows = 1 },
    { id = 4, name = "4", monitor = "TEST-1", monitorID = 0, windows = 1 },
    { id = 5, name = "5", monitor = "TEST-1", monitorID = 0, windows = 1 },
    { id = 6, name = "6", monitor = "TEST-1", monitorID = 0, windows = 0 },
  },
  clients = {
    { address = "0x1", workspace = { id = 4, name = "4" }, monitor = 0 },
    { address = "0x2", workspace = { id = 5, name = "5" }, monitor = 0 },
    { address = "0x3", workspace = { id = 1, name = "1" }, monitor = 1 },
  },
}
local withoutEmpty = realHypr.visible(wsSnapshot, "TEST-1", 2, 5, false, false, 0)
assert(#withoutEmpty == 2, "show_empty=false should hide the monitor's empty workspace")
local withEmpty = realHypr.visible(wsSnapshot, "TEST-1", 2, 5, true, false, 0)
assert(#withEmpty == 3, "show_empty should add only the monitor's own existing workspaces")
assert(withEmpty[1].id == 4 and withEmpty[3].id == 6, "only this monitor's workspaces should appear")

-- Floating windows are ignored by the preview layout.
local floatItems = realHypr.windowItems({ clients = {
  { address = "0xt1", floating = false, at = { 0, 0 }, size = { 960, 1080 } },
  { address = "0xt2", floating = true, at = { 100, 100 }, size = { 800, 600 } },
} })
assert(#floatItems == 1 and floatItems[1].client.address == "0xt1", "floating windows should be ignored")

-- Empty workspaces should get the same preview height as occupied ones.
local mixed = realHypr.panelLayout({
  { id = 1, clients = { { address = "0xm1", floating = false, at = { 0, 0 }, size = { 1920, 1080 } } } },
  { id = 2, clients = {} },
}, 5, false)
assert(mixed.cards[1].thumbHeight == mixed.cards[2].thumbHeight,
  "empty workspaces should match the preview height of occupied ones")
print("surface UI checks passed")
