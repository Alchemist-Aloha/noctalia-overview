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

local config = { show_empty = true, show_special = false,
  max_captures = 20, capture_interval_ms = 1200 }
local rendered
local captured = {}
-- Reuse the real (pure) layout helpers so the test exercises the shared math.
local realHypr = assert(loadfile("lib/hypr.luau", "t", setmetatable({}, { __index = _G })))()

local hypr = setmetatable({
  fetch = function(callback) callback({ monitors = { {} }, clients = {}, workspaces = {} }) end,
  -- Hand the synthetic workspaces to the real window slicer.
  workspaces = function() return visible end,
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
assert(#rendered.children[2].children == 1, "workspaces must stay on a single row")
assert(#rendered.children[2].children[1].children == realHypr.LAYOUT.previewCount,
  "the window should always show the fixed number of previews")
local windowMetrics = realHypr.panelLayout({ visible[1], visible[2], visible[3] }, 312, 850)
assert(rendered.children[2].children[1].children[1].props.width == windowMetrics.cardWidth,
  "previews should be sized from the panel, not the number of workspaces")
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
assert(captureCount == 6, "capture budget should cover every window shown on screen")
surface:key("Down", true)
assert(rendered.children[2].children[1].children[1].props.borderWidth == 2, "scrolling should keep the keyboard selection")
assert(rendered.children[2].children[1].children[1].children[1].children[1].props.text == "2",
  "Down should scroll the window by one workspace")
surface:key("Escape", true)

-- The content column fills the panel's box exactly, so no space is left over
-- below the footer; the scroll centers the row in the slack the fixed-aspect
-- cards leave inside that box.
assert(rendered.props.height == 312, "the panel content should fill its box")
local threeCards = realHypr.panelLayout({ visible[1], visible[2], visible[3] }, 312, 850)
assert(threeCards.cardWidth * 3 + 2 * realHypr.LAYOUT.gridGap <= 850,
  "the fixed row must fit the panel's inner width")
assert(threeCards.cardWidth == realHypr.panelLayout(visible, 312, 850).cardWidth,
  "every card should get one fixed size")
assert(rendered.children[2].props.justify == "center", "the preview row should stay centered")

-- The monitor's active workspace is the default highlight, centered when it can be.
visible[1].active = false
visible[4].active = true
local focused = assert(loadfile("lib/surface.luau", "t", env))().new()
focused:open("")
local page = rendered.children[2].children[1].children
assert(#page == realHypr.LAYOUT.previewCount, "the active workspace should keep the preview window full")
local selectedCard
for _, card in ipairs(page) do
  if card.props.borderWidth == 2 then selectedCard = card end
end
assert(selectedCard ~= nil, "the active workspace should be highlighted by default")
assert(selectedCard.children[1].children[1].props.text == "4",
  "the active workspace should be the default highlight")
assert(page[2] == selectedCard, "the active workspace should open in the middle of the window")
visible[1].active = true
visible[4].active = false

-- A taller panel is still filled, but cannot widen the cards past the row.
local tall = assert(loadfile("lib/surface.luau", "t", env))().new()
tall.panelHeight = 600
tall:open("")
assert(rendered.props.height == 572, "a taller panel should be filled too")
assert(#rendered.children[2].children[1].children == realHypr.LAYOUT.previewCount,
  "a taller panel should still show the same number of previews")
local tallMetrics = realHypr.panelLayout({ visible[1], visible[2], visible[3] }, 572, 850)
assert(tallMetrics.cardWidth * 3 + 2 * realHypr.LAYOUT.gridGap <= 850,
  "a taller panel must still fit the cards inside the row")

-- Fewer workspaces than the window should show what exists, still on one row.
visible = { visible[1], visible[2] }
local adaptive = assert(loadfile("lib/surface.luau", "t", env))().new()
adaptive:open("")
assert(#rendered.children[2].children == 1 and #rendered.children[2].children[1].children == 2,
  "two workspaces should lay out as two cards on one row")
local wideMetrics = realHypr.panelLayout({ visible[1], visible[2] }, 312, 850)
assert(rendered.children[2].children[1].children[1].props.width == wideMetrics.cardWidth,
  "previews should keep the panel's card width")
assert(wideMetrics.cardWidth == windowMetrics.cardWidth,
  "fewer workspaces should not resize the preview sections")
assert(wideMetrics.cards[1].previewHeight == wideMetrics.cards[2].previewHeight,
  "previews should share one fixed aspect ratio")
assert(math.abs((wideMetrics.cardWidth - 12) - wideMetrics.previewHeight * 16 / 9) < 2,
  "previews should keep the fixed 16:9 aspect ratio")

-- Hypr.workspaces must not include another monitor's workspaces.
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
local withoutEmpty = realHypr.workspaces(wsSnapshot, "TEST-1", false, false)
assert(#withoutEmpty == 2, "show_empty=false should hide the monitor's empty workspace")
local withEmpty = realHypr.workspaces(wsSnapshot, "TEST-1", true, false)
assert(#withEmpty == 3, "show_empty should add only the monitor's own existing workspaces")
assert(withEmpty[1].id == 4 and withEmpty[3].id == 6, "only this monitor's workspaces should appear")

-- The preview window slices the list and clamps at both ends.
local records = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }
assert(realHypr.window(records, 3, 0)[1].id == 1, "the first window should start at the first workspace")
assert(realHypr.window(records, 3, 5)[1].id == 2, "the window should clamp to the end")
assert(#realHypr.window(records, 3, 5) == 3, "the clamped window should stay full")

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
}, 312, 850)
assert(mixed.cards[1].previewHeight == mixed.cards[2].previewHeight,
  "empty workspaces should match the preview height of occupied ones")
print("surface UI checks passed")
