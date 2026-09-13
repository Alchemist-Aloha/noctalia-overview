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
  local clients = { { address = "0x" .. string.format("%x", id), class = "test", title = "Window " .. id } }
  if id == 1 then
    clients[2] = { address = "0x21", class = "test", title = "Second" }
    clients[3] = { address = "0x22", class = "test", title = "Third" }
  end
  visible[id] = { id = id, name = tostring(id), active = id == 1, clients = clients, monitor = "TEST-1" }
end

local config = { rows = 2, columns = 10, show_empty = true, show_special = false,
  show_titles = true, max_captures = 12, capture_interval_ms = 1200 }
local rendered
local captured = {}
local hypr = {
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
}

local env = setmetatable({
  ui = ui,
  require = function() return hypr end,
  noctalia = {
    getConfig = function(key) return config[key] end,
    tr = function(key) return key end,
    appIconPath = function() return nil end,
    state = { get = function() return "" end },
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
local featured = rendered.children[2].children[1].children[1].children[4].children[1]
featured.props.onHover(true)
featured = rendered.children[2].children[1].children[1].children[4].children[1]
assert(featured.props.fill == "primary/0.10", "hovered window should be highlighted")
local captureCount = 0
for _ in pairs(captured) do captureCount = captureCount + 1 end
assert(captureCount == 10, "capture budget should cover one featured window per workspace")
surface:key("Down", true)
assert(rendered.children[2].children[2].children[1].props.borderWidth == 2, "keyboard movement should match displayed columns")
surface:key("Escape", true)

local preview = assert(loadfile("lib/surface.luau", "t", env))().new(true)
preview:open("")
assert(#rendered.children[2].children == 3, "hover preview should reflow to four cards per row")
assert(rendered.children[2].children[1].children[1].props.height == 166, "preview cards should fit compact contents")
print("surface UI checks passed")
