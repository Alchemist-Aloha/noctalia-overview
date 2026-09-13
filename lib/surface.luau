--!nonstrict
local hypr = require("./hypr.luau")
local M = {}

local function short(text, limit)
  local value = tostring(text or "")
  if #value > limit then return string.sub(value, 1, limit - 1) .. "…" end
  return value
end

-- Read one panel's width/height from the plugin manifest so the preview fills
-- whatever size is set there. Matches the `id`, then the next width/height in
-- the same `[[panel]]` block.
local function parsePanelSize(text, panelId)
  local width, height, matched = nil, nil, false
  for line in text:gmatch("[^\n]+") do
    if line:match("^%s*%[%[") then
      matched = false
    else
      local id = line:match('^%s*id%s*=%s*"([^"]+)"')
      if id then matched = (id == panelId) end
      if matched then
        local w = line:match("^%s*width%s*=%s*(%d+)")
        local h = line:match("^%s*height%s*=%s*(%d+)")
        if w then width = tonumber(w) end
        if h then height = tonumber(h) end
      end
    end
  end
  return width, height
end

-- Bounding box of a set of window rectangles ({ x, y, w, h }).
local function bboxOf(items)
  local minX, minY, maxX, maxY = hypr.bboxOf(items)
  return minX or 0, minY or 0, maxX or 0, maxY or 0
end

-- Find the cleanest way to bisect a tiled layout: the axis and split index
-- whose two groups do not overlap. Returns nil when nothing separates cleanly
-- (for example overlapping floating windows).
local function findSplit(items)
  local best = nil
  for _, axis in ipairs({ "x", "y" }) do
    local sorted = {}
    for _, item in ipairs(items) do sorted[#sorted + 1] = item end
    table.sort(sorted, function(a, b)
      local aMin = axis == "x" and a.x or a.y
      local bMin = axis == "x" and b.x or b.y
      if aMin ~= bMin then return aMin < bMin end
      local aOther = axis == "x" and a.y or a.x
      local bOther = axis == "x" and b.y or b.x
      return aOther < bOther
    end)
    local ends = {}
    local running = -math.huge
    for index, item in ipairs(sorted) do
      local edge = axis == "x" and (item.x + item.w) or (item.y + item.h)
      if edge > running then running = edge end
      ends[index] = running
    end
    local starts = {}
    local runningStart = math.huge
    for index = #sorted, 1, -1 do
      local start = axis == "x" and sorted[index].x or sorted[index].y
      if start < runningStart then runningStart = start end
      starts[index] = runningStart
    end
    for index = 1, #sorted - 1 do
      local gap = starts[index + 1] - ends[index]
      if gap >= -1 and (best == nil or gap > best.gap) then
        best = { axis = axis, index = index, gap = gap, sorted = sorted }
      end
    end
  end
  return best
end

function M.new()
  local tileGap = 3
  local self = {
    opened = false,
    snapshot = { clients = {}, monitors = {}, workspaces = {} },
    output = "",
    visible = {},
    offset = 0,
    maxOffset = 0,
    selected = 1,
    selectedWindow = nil,
    hoveredWindow = nil,
    fetching = false,
    iconCache = {},
    generation = 0,
  }

  local render
  self.capture = hypr.newCaptureManager("overview", function()
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

  local function clientIcon(client, size)
    local appId = tostring(client.class or "")
    local appIcon = self.iconCache[appId]
    if appIcon == nil then
      appIcon = noctalia.appIconPath(appId, size) or false
      self.iconCache[appId] = appIcon
    end
    if appIcon then
      return ui.image({ path = appIcon, width = size, height = size, fit = "contain" })
    end
    return ui.glyph({ name = "app-window", size = size, color = "on_surface_variant" })
  end

  -- One window tile: a live thumbnail that fills its slot in the workspace
  -- layout. Window titles are exposed as tooltips, not caption strips, so the
  -- thumbnail gets the whole slot.
  local function windowTile(client, width, height)
    local address = tostring(client.address or "")
    local image = self.capture:path(client)
    local children = {}
    if image then
      table.insert(children, ui.image({
        key = "image-" .. address,
        path = image,
        width = width,
        height = height,
        fit = "stretch",
        radius = 3,
      }))
    else
      table.insert(children, ui.row({
        width = width, height = height,
        fill = "surface_variant/0.6", radius = 3,
        align = "center", justify = "center",
      }, { clientIcon(client, math.max(10, math.min(20, height))) }))
    end
    local body = ui.column({
      key = "window-" .. address,
      width = width, height = height,
      gap = 0,
      radius = 3,
      fill = self.selectedWindow == address and "primary/0.35" or "surface_variant/0.5",
      border = self.selectedWindow == address and "primary"
        or (self.hoveredWindow == address and "primary/0.7" or "outline/0.25"),
      borderWidth = self.selectedWindow == address and 2 or 1,
      onHover = function(entered)
        local inside = entered == true or entered == "true"
        if not inside and self.hoveredWindow ~= address then return end
        local nextHovered = inside and address or nil
        if self.hoveredWindow ~= nextHovered then
          self.hoveredWindow = nextHovered
          render()
        end
      end,
      onClick = function()
        self.selectedWindow = address
        render()
      end,
    }, children)
    return ui.dragSource({
      key = "drag-" .. address,
      dragType = "hypr-window",
      payload = address,
      tooltip = short(client.title or client.class or address, 48),
      previewAncestor = 0,
    }, { body })
  end

  -- Fallback for overlapping windows (floating/fullscreen): a simple grid.
  local function gridLayout(items, areaWidth, areaHeight)
    local count = #items
    local columns = math.max(1, math.ceil(math.sqrt(count)))
    local rows = math.ceil(count / columns)
    local tileWidth = math.max(8, math.floor((areaWidth - tileGap * (columns - 1)) / columns))
    local tileHeight = math.max(8, math.floor((areaHeight - tileGap * (rows - 1)) / rows))
    local rowNodes = {}
    for row = 0, rows - 1 do
      local tiles = {}
      for column = 1, columns do
        local item = items[row * columns + column]
        if item then table.insert(tiles, windowTile(item.client, tileWidth, tileHeight)) end
      end
      if #tiles > 0 then table.insert(rowNodes, ui.row({ gap = tileGap, align = "start" }, tiles)) end
    end
    return ui.column({ gap = tileGap, align = "start" }, rowNodes)
  end

  -- Recursively slice the available area so tiles mirror the real workspace
  -- tiling, using each window's Hyprland geometry (at/size).
  local function buildLayout(items, areaWidth, areaHeight, depth)
    depth = (depth or 0) + 1
    if #items <= 1 or depth > 10 then
      if #items == 1 then return windowTile(items[1].client, areaWidth, areaHeight) end
      return gridLayout(items, areaWidth, areaHeight)
    end
    local minX, minY, maxX, maxY = bboxOf(items)
    local boxWidth, boxHeight = maxX - minX, maxY - minY
    if boxWidth <= 0 or boxHeight <= 0 then return gridLayout(items, areaWidth, areaHeight) end
    local split = findSplit(items)
    if not split then return gridLayout(items, areaWidth, areaHeight) end
    local groupA, groupB = {}, {}
    for position, item in ipairs(split.sorted) do
      if position <= split.index then groupA[#groupA + 1] = item else groupB[#groupB + 1] = item end
    end
    if split.axis == "x" then
      local aMinX, _, aMaxX = bboxOf(groupA)
      local bMinX = bboxOf(groupB)
      local boundary = (aMaxX + bMinX) / 2
      local fraction = math.max(0.08, math.min(0.92, (boundary - minX) / boxWidth))
      local available = math.max(16, areaWidth - tileGap)
      local widthA = math.max(8, math.floor(available * fraction))
      return ui.row({ gap = tileGap, align = "start" }, {
        buildLayout(groupA, widthA, areaHeight, depth),
        buildLayout(groupB, available - widthA, areaHeight, depth),
      })
    end
    local _, aMinY, _, aMaxY = bboxOf(groupA)
    local bMinY = select(2, bboxOf(groupB))
    local boundary = (aMaxY + bMinY) / 2
    local fraction = math.max(0.08, math.min(0.92, (boundary - minY) / boxHeight))
    local available = math.max(16, areaHeight - tileGap)
    local heightA = math.max(8, math.floor(available * fraction))
    return ui.column({ gap = tileGap, align = "start" }, {
      buildLayout(groupA, areaWidth, heightA, depth),
      buildLayout(groupB, areaWidth, available - heightA, depth),
    })
  end

  local function workspaceCard(ws, index, width, metrics)
    local targetWorkspace = ws.special and tostring(ws.name or "special") or tostring(ws.id)
    local heading = ui.button({
      key = "switch-" .. tostring(ws.id),
      text = workspaceName(ws),
      variant = "ghost", selected = ws.active == true, controlSize = "sm",
      tooltip = noctalia.tr("panel.switch"),
      onClick = function() activateWorkspace(ws) end,
    })
    -- Keep the heading, window count and monitor on one compact line.
    local headingRow = {
      heading,
      ui.label({ text = tostring(#(ws.clients or {})), fontSize = 10,
        color = #(ws.clients or {}) > 0 and "secondary" or "on_surface_variant" }),
    }
    if ws.monitor and ws.monitor ~= "" then
      table.insert(headingRow, ui.label({ text = short(ws.monitor, 14), fontSize = 9, color = "on_surface_variant" }))
    end
    -- The "+N" badge rides in the heading row so a card with hidden windows is
    -- exactly as tall as every other card, keeping the previews one fixed size.
    if metrics and metrics.extra then
      table.insert(headingRow, ui.label({ text = "+" .. tostring(#(ws.clients or {}) - hypr.LAYOUT.maxTiles),
        fontSize = 10, color = "secondary" }))
    end
    local children = { ui.row({ align = "center", gap = 4 }, headingRow) }
    -- Arrange every window by its real geometry so the card mirrors the
    -- workspace tiling (side-by-side, stacked, master/stack, ...).
    local pad = hypr.LAYOUT.cardPad
    local cardGap = hypr.LAYOUT.cardGap
    local items = hypr.windowItems(ws)
    local previewHeight = metrics and metrics.previewHeight or 16
    local interiorWidth = math.max(24, width - pad * 2)
    if #items > 0 then
      table.insert(children, buildLayout(items, interiorWidth, previewHeight, 0))
    else
      -- Keep the empty workspace's preview area the same size as the others.
      table.insert(children, ui.row({ height = previewHeight, align = "center", justify = "center" }, {
        ui.label({ text = noctalia.tr("panel.empty"), color = "on_surface_variant", fontSize = 11 }),
      }))
    end
    -- Spacer so the thumbnails do not sit flush against the card's bottom edge.
    table.insert(children, ui.spacer({ height = hypr.LAYOUT.cardSpacer }))
    -- No fixed minimum: the card is exactly as tall as its contents.
    local cardHeight = pad * 2 + hypr.LAYOUT.headingHeight + previewHeight + hypr.LAYOUT.cardSpacer + cardGap * (#children - 1)
    return ui.dropZone({
      key = "workspace-" .. tostring(ws.id),
      accepts = { "hypr-window" }, value = targetWorkspace,
      onDrop = function(address, target)
        if not string.match(address or "", "^0x%x+$") then return end
        hypr.dispatch("movetoworkspace", target .. ",address:" .. address)
        self:update()
      end,
      direction = "column", width = width, height = cardHeight,
      gap = cardGap, padding = pad, radius = 8,
      fill = ws.active and "primary/0.18" or "surface_variant/0.7",
      border = index == self.selected and "primary" or "outline/0.25",
      borderWidth = index == self.selected and 2 or 1,
    }, children), cardHeight
  end

  -- Usable panel content area: the shell insets the configured panel size by
  -- Style::panelPadding, then the rendered column adds bodyPad on every side.
  -- The preview row must fit inside that inner box or the scroll clips it.
  local function panelArea()
    local inset = hypr.LAYOUT.panelPadding * 2
    local targetContent = self.panelHeight and math.max(0, self.panelHeight - inset) or nil
    local gridWidth = self.panelWidth
      and math.max(64, self.panelWidth - inset - hypr.LAYOUT.bodyPad * 2) or nil
    return targetContent, gridWidth
  end

  -- Workspace records for the preview window, sized to the panel.
  local function refreshVisible()
    self.workspaces = hypr.workspaces(self.snapshot, self.output,
      noctalia.getConfig("show_empty"), noctalia.getConfig("show_special"))
    self.maxOffset = math.max(0, #self.workspaces - hypr.LAYOUT.previewCount)
    if self.offset > self.maxOffset then self.offset = self.maxOffset end
    self.visible = hypr.window(self.workspaces, hypr.LAYOUT.previewCount, self.offset)
    if self.selected > #self.visible then self.selected = math.max(1, #self.visible) end
  end

  -- Keep thumbnails flowing for exactly the workspaces on screen.
  local function refreshCaptures()
    local remaining = noctalia.getConfig("max_captures") or 12
    local captures = {}
    for _, ws in ipairs(self.visible) do
      if remaining <= 0 then break end
      local shown = 0
      for _, client in ipairs(ws.clients or {}) do
        if shown >= 9 or remaining <= 0 then break end
        -- Floating windows are not drawn, so skip capturing them.
        if client.floating ~= true then
          captures[#captures + 1] = client
          shown = shown + 1
          remaining = remaining - 1
        end
      end
    end
    self.capture:update(captures, true)
  end

  -- Scroll the preview window by one workspace; no refetch needed.
  local function scrollBy(delta)
    local nextOffset = math.max(0, math.min(self.maxOffset or 0, self.offset + delta))
    if nextOffset == self.offset then return end
    self.offset = nextOffset
    refreshVisible()
    render()
    refreshCaptures()
  end

  render = function()
    if not self.opened then return end
    local targetContent, gridWidth = panelArea()
    -- One row, capped at the preview count; the chevrons scroll the window.
    local metrics = hypr.panelLayout(self.visible, targetContent, gridWidth)
    local gridGap = hypr.LAYOUT.gridGap
    local cards = {}
    for index, ws in ipairs(self.visible) do
      cards[#cards + 1] = workspaceCard(ws, index, metrics.cardWidth, metrics.cards[index])
    end
    local grid = {}
    if #cards > 0 then
      table.insert(grid, ui.row({ key = "workspace-row", gap = gridGap, align = "start", justify = "center" }, cards))
    else
      local message = #(self.snapshot.monitors or {}) == 0 and "panel.no_hyprland" or "panel.empty"
      table.insert(grid, ui.label({ text = noctalia.tr(message), color = "on_surface_variant" }))
    end
    -- Show the workspace ids actually on screen, not the raw window slots.
    local rangeFirst, rangeLast
    for _, ws in ipairs(self.visible) do
      local id = tonumber(ws.id)
      if id and id > 0 then
        rangeFirst = rangeFirst and math.min(rangeFirst, id) or id
        rangeLast = rangeLast and math.max(rangeLast, id) or id
      end
    end
    local rangeText
    if rangeFirst then
      rangeText = tostring(rangeFirst) .. "–" .. tostring(rangeLast)
    else
      local first = self.offset + 1
      rangeText = tostring(first) .. "–" .. tostring(first + math.max(0, #self.visible - 1))
    end
    local header = ui.row({ align = "center", gap = 6 }, {
      ui.glyph({ name = "layout-dashboard", size = 20, color = "primary" }),
      ui.label({ text = noctalia.tr("panel.title"), fontWeight = "bold", fontSize = 17, color = "on_surface", flexGrow = 1 }),
      ui.label({ text = rangeText, fontSize = 11, color = "on_surface_variant" }),
      ui.button({ glyph = "chevron-left", controlSize = "sm", enabled = self.offset > 0, tooltip = noctalia.tr("panel.previous"), onClick = function() scrollBy(-1) end }),
      ui.button({ glyph = "chevron-right", controlSize = "sm", enabled = self.offset < (self.maxOffset or 0), tooltip = noctalia.tr("panel.next"), onClick = function() scrollBy(1) end }),
      ui.button({ glyph = "refresh", controlSize = "sm", tooltip = noctalia.tr("panel.refresh"), onClick = function() self:update() end }),
      ui.button({ glyph = "close", controlSize = "sm", tooltip = noctalia.tr("panel.close"), onClick = function() panel.close() end }),
    })
    local content = {
      -- The row is centered in whatever the fixed-aspect cards leave over, so
      -- the footer stays pinned to the panel's bottom edge.
      header,
      ui.scroll({ key = "workspace-grid", flexGrow = 1, gap = gridGap, justify = "center" }, grid),
    }
    -- Reserve the same footer height in both states so the computed content
    -- height stays valid when a window gets selected.
    if self.selectedWindow then
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
    else
      table.insert(content, ui.row({ align = "center" }, {
        ui.label({ text = noctalia.tr("panel.keyboard_hint"), fontSize = 11, color = "on_surface_variant" }),
      }))
    end
    -- Fill the panel's content box exactly: the scroll container absorbs the
    -- difference between the fixed-aspect cards and the space available.
    panel.render(ui.column({ height = targetContent, gap = 8, padding = hypr.LAYOUT.bodyPad }, content))
  end

  function self:update()
    if not self.opened or self.fetching then return end
    self.fetching = true
    local generation = self.generation
    hypr.fetch(function(snapshot)
      if not self.opened or generation ~= self.generation then return end
      self.fetching = false
      self.snapshot = snapshot
      refreshVisible()
      render()
      refreshCaptures()
    end)
  end

  function self:open(context)
    self.generation = self.generation + 1
    self.opened = true
    self.fetching = false
    self.output = tostring(noctalia.state.get("overview_output") or "")
    if context and context ~= "" then self.output = context end
    self.offset = 0
    self.selected = 1
    self.selectedWindow = nil
    self.hoveredWindow = nil
    render()
    self:update()
    noctalia.setUpdateInterval(noctalia.getConfig("capture_interval_ms") or 1200)
  end

  function self:close()
    self.generation = self.generation + 1
    self.opened = false
    self.hoveredWindow = nil
    self.capture:clear()
  end

  function self:key(chord, pressed)
    if not pressed then return end
    if chord == "Escape" then panel.close(); return end
    if #self.visible == 0 then return end
    if chord == "Left" or chord == "h" then
      self.selected = math.max(1, self.selected - 1)
    elseif chord == "Right" or chord == "l" then
      self.selected = math.min(#self.visible, self.selected + 1)
    elseif chord == "Up" or chord == "k" then
      -- Scroll the preview window back one workspace.
      scrollBy(-1)
      return
    elseif chord == "Down" or chord == "j" then
      scrollBy(1)
      return
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

  -- Defaults until the manifest is read; mirrors plugin.toml's overview panel.
  self.panelWidth = 900
  self.panelHeight = 360
  local directory = noctalia.pluginDir()
  if type(directory) == "string" and directory ~= "" then
    noctalia.runAsync({ "cat", directory .. "/plugin.toml" }, function(result)
      if result.exitCode ~= 0 or type(result.stdout) ~= "string" then return end
      local width, height = parsePanelSize(result.stdout, "overview")
      if width then self.panelWidth = width end
      if height then self.panelHeight = height end
      if self.opened then refreshVisible(); render() end
    end)
  end

  return self
end

return M
