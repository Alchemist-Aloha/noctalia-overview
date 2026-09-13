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
for _, kind in ipairs({ "row", "column", "box" }) do
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
  require = function() return { dispatch = function(_, target) dispatched[#dispatched + 1] = target end } end,
  barWidget = {
    isVertical = function() return false end,
    outputName = function() return output end,
    render = function(value) tree = value end,
    setTooltip = function() end,
  },
  noctalia = {
    getConfig = function(key) return config[key] end,
    focusedOutputName = function() return "TEST-1" end,
    tr = function(key) return key end,
    setUpdateInterval = function() end,
    json = { decode = function(value)
      if value == "monitors" then return {
        { id = 1, name = "TEST-1", activeWorkspace = { id = 1 } },
        { id = 2, name = "OTHER", activeWorkspace = { id = 4 } },
      } end
      return workspaces
    end },
    runAsync = function(args, callback)
      assert(args[1] == "hyprctl" and args[2] == "-j", "hyprctl needs the JSON flag before its command")
      callback({ exitCode = 0, stdout = args[3] })
      return true
    end,
    state = state,
    togglePanel = function(id)
      toggles[#toggles + 1] = id
      open[id] = not open[id]
      state.set(id == previewId and "preview_open" or "overview_open", open[id])
    end,
    openSettings = function() end,
  },
}, { __index = _G })

assert(loadfile("widget.luau", "t", env))()
env.update()
assert(tree.kind == "row" and #tree.children == 5, "bar should show a compact local group plus real workspaces beyond it")
assert(tree.children[1].kind == "box" and tree.children[1].props.width == 40, "active workspace should be a long pill")
assert(tree.children[2].props.width == 16, "inactive workspaces should be compact pills")
assert(tree.children[5].props.key == "ws-11", "a same-monitor workspace outside the numbered page should appear")
config.show_empty_bar = true
env.update()
assert(#tree.children == 6, "show_empty_bar should include additional real empty workspaces")
config.show_special = true
env.update()
assert(#tree.children == 7, "special workspace should appear only when opted in")
config.show_special = false
config.show_empty_bar = false
output = "OTHER"
env.update()
assert(#tree.children == 2 and tree.children[1].props.key == "ws-4", "second bar must exclude known workspaces from the first monitor")
output = nil
env.update()
assert(#tree.children == 5, "unknown bar output should use focused monitor, not merge all monitors")
output = "TEST-1"
env.update()
env.onScroll("vertical", -1)
assert(dispatched[#dispatched] == "2", "bar scroll should stay within this monitor's workspace list")

env.onHover(true)
assert(open[previewId] == true, "hover should open preview")
env.onClick()
assert(open[previewId] == false and open[overviewId] == true, "click should replace preview with overview")
local before = #toggles
env.onHover(false)
env.onHover(true)
assert(#toggles == before, "hover re-entry must not reopen preview over overview")
env.onClick()
assert(open[overviewId] == false, "second click should close overview")
env.onHover(false)
env.onHover(true)
assert(open[previewId] == true, "a fresh hover should open preview again")
workspaces = {}
env.update()
assert(#tree.children == 5 and tree.children[1].props.key == "ws-1", "active and nearby slots should survive an empty workspace response")
print("widget interaction checks passed")
