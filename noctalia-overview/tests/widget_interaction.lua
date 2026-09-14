-- Run from the plugin directory: lua tests/widget_interaction.lua
local overviewId = "alchemistaloha/noctalia-overview:overview"
local watchers, values, open, toggles = {}, {}, {}, {}
local tree
local output = "TEST-1"

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

local env = setmetatable({
  ui = ui,
  require = function() return {} end,
  barWidget = {
    isVertical = function() return false end,
    outputName = function() return output end,
    render = function(value) tree = value end,
    setTooltip = function() end,
  },
  noctalia = {
    getConfig = function() return nil end,
    focusedOutputName = function() return "TEST-1" end,
    tr = function(key) return key end,
    state = state,
    togglePanel = function(id)
      toggles[#toggles + 1] = id
      open[id] = not open[id]
      state.set("overview_open", open[id])
    end,
    openSettings = function() end,
  },
}, { __index = _G })

assert(loadfile("widget.luau", "t", env))()
assert(tree.kind == "row", "bar widget should render a single icon row")
assert(tree.children[1].kind == "glyph" and tree.children[1].props.name == "layout-dashboard",
  "bar widget should show the overview icon")

env.onClick()
assert(toggles[#toggles] == overviewId and open[overviewId] == true, "click should open the overview")
env.onClick()
assert(open[overviewId] == false, "second click should close the overview")
print("widget interaction checks passed")
