-- Run from the plugin directory: lua tests/widget_interaction.lua
local previewId = "alchemistaloha/noctalia-overview:preview"
local overviewId = "alchemistaloha/noctalia-overview:overview"
local watchers, values, open, toggles = {}, {}, {}, {}
local tree
local output = "TEST-1"
local dispatched = {}
local config = { rows = 2, columns = 5, show_hover_preview = true,
  show_empty = true, show_empty_bar = false, show_special = false }
local workspaces = {
  { id = 1, name = "1", monitor = "TEST-1", windows = 1 },
  { id = 2, name = "2", monitor = "TEST-1", windows = 1 },
  { id = 3, name = "3", monitor = "TEST-1", windows = 0 },
  { id = 11, name = "11", monitorID = 1, windows = 1 },
  { id = 16, name = "16", monitor = "TEST-1", windows = 0 },
  { id = -98, name = "special:scratch", monitor = "TEST-1", windows = 1 },
  { id = 4, name = "4", monitor = "OTHER", windows = 1 },
}
local ui = {}
for _, kind in ipairs({ "row", "column", "box", "glyph" }) do
  ui[kind] = function(props, children)
    return { kind = kind, props = props, children = children or {} }
  end
end

local state = {
  get = function(key) return values[key] end,
  watch = function(key, callback) watchers[key] = callback end,
  set = function(key, value)
    values[key] = value
    if watchers[key] then watchers[key](value) end
  end,
}

-- Noctalia's bar binding is only available during synchronous widget callbacks;
-- inside runAsync callbacks outputName() returns nil. Reproduce that here so the
-- widget is forced to capture its output before starting an async query.
local inAsync = false
local noctaliaMock = {
  getConfig = function(key) return config[key] end,
  focusedOutputName = function()
    if inAsync then return nil end
    return "TEST-1"
  end,
  tr = function(key) return key end,
  setUpdateInterval = function() end,
  json = { decode = function(value)
    if value == "monitors" then return {
      { id = 1, name = "TEST-1", activeWorkspace = { id = 1 } },
      { id = 2, name = "OTHER", activeWorkspace = { id = 4 } },
    } end
    if value == "clients" then return {} end
    return workspaces
  end },
  runAsync = function(args, callback)
    assert(args[1] == "hyprctl" and args[2] == "-j", "hyprctl needs the JSON flag before its command")
    inAsync = true
    local ok, err = pcall(callback, { exitCode = 0, stdout = args[3] })
    inAsync = false
    assert(ok, err)
    return true
  end,
  state = state,
  togglePanel = function(id)
    toggles[#toggles + 1] = id
    open[id] = not open[id]
    local isPreview = type(id) == "string"
      and (id == previewId or string.sub(id, 1, #previewId + 1) == previewId .. "-")
    state.set(isPreview and "preview_open" or "overview_open", open[id])
  end,
  openSettings = function() end,
}

-- Reuse the real hypr helpers (fetch/visible/panel pick) with a stub dispatch.
local realHypr = assert(loadfile("lib/hypr.luau", "t",
  setmetatable({ noctalia = noctaliaMock }, { __index = _G })))()
local hyprMock = setmetatable({
  dispatch = function(_, target) dispatched[#dispatched + 1] = target end,
}, { __index = realHypr })

local env = setmetatable({
  ui = ui,
  require = function() return hyprMock end,
  barWidget = {
    isVertical = function() return false end,
    outputName = function()
      if inAsync then return nil end
      return output
    end,
    render = function(value) tree = value end,
    setTooltip = function() end,
  },
  noctalia = noctaliaMock,
}, { __index = _G })

assert(loadfile("widget.luau", "t", env))()
assert(tree.kind == "row", "bar widget should render a single icon row")
assert(tree.children[1].kind == "glyph" and tree.children[1].props.name == "layout-dashboard",
  "bar widget should show the overview icon")
env.update()
assert(tree.children[1].kind == "glyph", "update should keep the icon")

local function isVariant(id, base)
  return id == base or string.sub(id, 1, #base + 1) == base .. "-"
end

env.onHover(true)
assert(isVariant(toggles[#toggles], previewId), "hover should open a preview variant")
local previewOpened = toggles[#toggles]
assert(open[previewOpened] == true)
env.onClick()
assert(open[previewOpened] == false, "click should replace preview with overview")
assert(isVariant(toggles[#toggles], overviewId), "click should open an overview variant")
local overviewOpened = toggles[#toggles]
assert(open[overviewOpened] == true)
local before = #toggles
env.onHover(false)
env.onHover(true)
assert(#toggles == before, "hover re-entry must not reopen preview over overview")
env.onClick()
assert(open[overviewOpened] == false, "second click should close overview")
env.onHover(false)
env.onHover(true)
assert(isVariant(toggles[#toggles], previewId), "a fresh hover should open preview again")
print("widget interaction checks passed")
