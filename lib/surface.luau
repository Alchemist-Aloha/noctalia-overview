--!nonstrict
local hypr = require("./hypr.luau")
local M = {}

local function short(text, limit)
  local value = tostring(text or "")
  if #value > limit then return string.sub(value, 1, limit - 1) .. "…" end
  return value
end

function M.new(preview)
  local self = {
    preview = preview,
    opened = false,
    snapshot = { clients = {}, monitors = {}, workspaces = {} },
    output = "",
    visible = {},
    page = 0,
    selected = 1,
    selectedWindow = nil,
    fetching = false,
    iconCache = {},
    generation = 0,
  }

  local render
  self.capture = hypr.newCaptureManager(preview and "hover" or "overview", function()
    if self.opened then render() end
  end)

  local function workspaceName(ws)
    local name = tostring(ws.name or ws.id or "")
    if string.sub(name, 1, 8) == "special:" then
      return noctalia.tr("panel.special") .. " " .. string.sub(name, 9)
    end
    if name ~= tostring(ws.id) and name ~= "" then
      return tostring(ws.id) .. " · " .. short(name, 18)
    end
    return tostring(ws.id)
  end

  local function activateWorkspace(ws)
    if ws.id and ws.id < 0 then
      local name = tostring(ws.name or "special")
      hypr.dispatch("togglespecialworkspace", string.gsub(name, "^special:", ""))
    else
      hypr.dispatch("workspace", tostring(ws.id))
    end
    panel.close()
  end

  local function windowNode(client, width, featured)
    local address = tostring(client.address or "")
    local title = short(client.title or client.class or address, preview and 20 or 34)
    local image = self.capture:path(client)
    local children = {}
    if image and featured then
      table.insert(children, ui.image({
        key = "image-" .. address,
        path = image,
        width = width - 16,
        height = preview and 62 or 104,
        fit = "contain",
        radius = 5,
        border = "outline/0.25",
        borderWidth = 1,
      }))
    elseif featured then
      local appId = tostring(client.class or "")
      local appIcon = self.iconCache[appId]
      if appIcon == nil then
        appIcon = noctalia.appIconPath(appId, 32) or false
        self.iconCache[appId] = appIcon
      end
      if appIcon then
        table.insert(children, ui.image({ path = appIcon, width = 28, height = 28, fit = "contain" }))
      else
        table.insert(children, ui.glyph({ name = "app-window", size = 24, color = "on_surface_variant" }))
      end
    end
    if noctalia.getConfig("show_titles") then
      table.insert(children, ui.label({ text = title, maxLines = 1, maxWidth = width - 16, fontSize = 11 }))
      local flags = (client.floating and " ◇" or "") .. (((tonumber(client.fullscreen) or 0) ~= 0) and " ⛶" or "") .. (client.urgent and " !" or "")
      if flags ~= "" then
        table.insert(children, ui.label({ text = flags, color = "secondary", fontSize = 10 }))
      end
    elseif not featured then
      table.insert(children, ui.label({ text = short(client.class or address, 22), fontSize = 11, color = "on_surface_variant" }))
    end
    local body = ui.column({
      key = "window-" .. address,
      gap = 3,
      padding = 4,
      fill = self.selectedWindow == address and "primary/0.18" or "surface_variant/0.45",
      radius = 5,
      onClick = function()
        self.selectedWindow = address
        if preview then
          hypr.dispatch("focuswindow", "address:" .. address)
          panel.close()
        else
          render()
        end
      end,
    }, children)
    if preview then return body end
    return ui.dragSource({
      key = "drag-" .. address,
      dragType = "hypr-window",
      payload = address,
      tooltip = noctalia.tr("panel.drag"),
      previewAncestor = 0,
    }, { body })
  end

  local function workspaceCard(ws, index, width)
    local targetWorkspace = ws.special and tostring(ws.name or "special") or tostring(ws.id)
    local heading = ui.button({
      key = "switch-" .. tostring(ws.id),
      text = workspaceName(ws),
      variant = "ghost", selected = ws.active == true, controlSize = "sm",
      tooltip = noctalia.tr("panel.switch"),
      onClick = function() activateWorkspace(ws) end,
    })
    local children = { ui.row({ align = "center", gap = 5 }, {
      heading,
      ui.label({ text = tostring(#(ws.clients or {})), fontSize = 11, color = "secondary" }),
    }) }
    if ws.active then
      table.insert(children, ui.label({ text = noctalia.tr("panel.active"), fontSize = 10, color = "primary" }))
    end
    if ws.monitor and ws.monitor ~= "" and not preview then
      table.insert(children, ui.label({ text = short(ws.monitor, 20), fontSize = 10, color = "on_surface_variant" }))
    end
    local shown = 0
    for _, client in ipairs(ws.clients or {}) do
      if shown >= (preview and 2 or 3) then break end
      table.insert(children, windowNode(client, width, shown == 0))
      shown = shown + 1
    end
    if shown == 0 then
      table.insert(children, ui.label({ text = noctalia.tr("panel.empty"), color = "on_surface_variant", fontSize = 11 }))
    elseif #(ws.clients or {}) > shown then
      table.insert(children, ui.label({ text = "+" .. tostring(#ws.clients - shown), fontSize = 11, color = "secondary" }))
    end
    if preview then
      return ui.column({
        key = "workspace-" .. tostring(ws.id), width = width, height = 166,
        gap = 5, padding = 7, radius = 7,
        fill = ws.active and "primary/0.18" or "surface_variant/0.7",
        border = "outline/0.25", borderWidth = 1,
      }, children)
    end
    return ui.dropZone({
      key = "workspace-" .. tostring(ws.id),
      accepts = { "hypr-window" }, value = targetWorkspace,
      onDrop = function(address, target)
        if not string.match(address or "", "^0x%x+$") then return end
        hypr.dispatch("movetoworkspace", target .. ",address:" .. address)
        self:update()
      end,
      direction = "column", width = width, height = 250,
      gap = 5, padding = 8, radius = 8,
      fill = ws.active and "primary/0.18" or "surface_variant/0.7",
      border = index == self.selected and "primary" or "outline/0.25",
      borderWidth = index == self.selected and 2 or 1,
    }, children)
  end

  render = function()
    if not self.opened then return end
    local configuredColumns = noctalia.getConfig("columns") or 5
    local columns = math.min(configuredColumns, preview and 4 or 5)
    local cardWidth = math.floor((preview and 660 or 1050) / columns)
    local grid = {}
    for row = 1, math.ceil(#self.visible / columns) do
      local cards = {}
      for column = 1, columns do
        local index = (row - 1) * columns + column
        local ws = self.visible[index]
        if ws then table.insert(cards, workspaceCard(ws, index, cardWidth)) end
      end
      if #cards > 0 then
        table.insert(grid, ui.row({ key = "row-" .. row, gap = 8, align = "start" }, cards))
      end
    end
    if #grid == 0 then
      local message = #(self.snapshot.monitors or {}) == 0 and "panel.no_hyprland" or "panel.empty"
      table.insert(grid, ui.label({ text = noctalia.tr(message), color = "on_surface_variant" }))
    end
    local capacity = (noctalia.getConfig("rows") or 2) * configuredColumns
    local firstId = self.page * capacity + 1
    local header = ui.row({ align = "center", gap = 6 }, {
      ui.glyph({ name = "layout-dashboard", size = 20, color = "primary" }),
      ui.label({ text = noctalia.tr(preview and "panel.preview_title" or "panel.title"), fontWeight = "bold", fontSize = 17, color = "on_surface", flexGrow = 1 }),
      ui.label({ text = tostring(firstId) .. "–" .. tostring(firstId + capacity - 1), fontSize = 11, color = "on_surface_variant" }),
      ui.button({ glyph = "chevron-left", controlSize = "sm", enabled = self.page > 0, tooltip = noctalia.tr("panel.previous"), onClick = function() self.page = math.max(0, self.page - 1); self:update() end }),
      ui.button({ glyph = "chevron-right", controlSize = "sm", tooltip = noctalia.tr("panel.next"), onClick = function() self.page = self.page + 1; self:update() end }),
      ui.button({ glyph = "refresh", controlSize = "sm", tooltip = noctalia.tr("panel.refresh"), onClick = function() self:update() end }),
      ui.button({ glyph = "close", controlSize = "sm", tooltip = noctalia.tr("panel.close"), onClick = function() panel.close() end }),
    })
    local content = { header, ui.scroll({ key = "workspace-grid", flexGrow = 1, gap = 8 }, grid) }
    if not preview and self.selectedWindow then
      table.insert(content, ui.row({ gap = 8 }, {
        ui.button({ text = noctalia.tr("panel.focus"), glyph = "focus", onClick = function()
          hypr.dispatch("focuswindow", "address:" .. self.selectedWindow)
          panel.close()
        end }),
        ui.button({ text = noctalia.tr("panel.float"), glyph = "square", onClick = function()
          hypr.dispatch("togglefloating", "address:" .. self.selectedWindow)
          self:update()
        end }),
      }))
    end
    if not preview and not self.selectedWindow then
      table.insert(content, ui.label({ text = noctalia.tr("panel.keyboard_hint"), fontSize = 11, color = "on_surface_variant" }))
    end
    panel.render(ui.column({ gap = 10, padding = 12 }, content))
  end

  function self:update()
    if not self.opened or self.fetching then return end
    self.fetching = true
    local generation = self.generation
    hypr.fetch(function(snapshot)
      if not self.opened or generation ~= self.generation then return end
      self.fetching = false
      self.snapshot = snapshot
      self.visible = hypr.visible(snapshot, self.output, noctalia.getConfig("rows") or 2,
        noctalia.getConfig("columns") or 5, noctalia.getConfig("show_empty"),
        noctalia.getConfig("show_special"), self.page)
      if self.selected > #self.visible then self.selected = math.max(1, #self.visible) end
      render()
      local remaining = noctalia.getConfig("max_captures") or 12
      local captures = {}
      for _, ws in ipairs(self.visible) do
        for _, client in ipairs(ws.clients or {}) do
          if remaining <= 0 then break end
          captures[#captures + 1] = client
          remaining = remaining - 1
        end
        if remaining <= 0 then break end
      end
      self.capture:update(captures, true)
    end)
  end

  function self:open(context)
    self.generation = self.generation + 1
    self.opened = true
    self.fetching = false
    self.output = tostring(noctalia.state.get(preview and "hover_output" or "overview_output") or "")
    if context and context ~= "" then self.output = context end
    self.page = 0
    self.selected = 1
    self.selectedWindow = nil
    render()
    self:update()
    noctalia.setUpdateInterval(noctalia.getConfig("capture_interval_ms") or 1200)
  end

  function self:close()
    self.generation = self.generation + 1
    self.opened = false
    self.capture:clear()
  end

  function self:key(chord, pressed)
    if preview or not pressed or #self.visible == 0 then return end
    local columns = noctalia.getConfig("columns") or 5
    if chord == "Left" or chord == "h" then
      self.selected = math.max(1, self.selected - 1)
    elseif chord == "Right" or chord == "l" then
      self.selected = math.min(#self.visible, self.selected + 1)
    elseif chord == "Up" or chord == "k" then
      self.selected = math.max(1, self.selected - columns)
    elseif chord == "Down" or chord == "j" then
      self.selected = math.min(#self.visible, self.selected + columns)
    elseif chord == "Return" then
      activateWorkspace(self.visible[self.selected])
      return
    else
      local number = tonumber(chord)
      if number == 0 then number = 10 end
      if number and self.visible[number] then
        activateWorkspace(self.visible[number])
        return
      end
    end
    render()
  end

  return self
end

return M
