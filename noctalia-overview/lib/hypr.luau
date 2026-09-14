--!nonstrict

-- Hyprland helpers shared by the v5 overview entries.
-- Requires plugin_api = 24 for noctalia.runAsync(argv, ...).

local Hypr = {}

local function asString(value)
    if value == nil then
        return nil
    end
    return tostring(value)
end

local function numberOr(value, fallback)
    return type(value) == "number" and value or fallback
end

local function workspaceId(value)
    if type(value) == "table" then
        return value.id or value.name
    end
    return value
end

local function monitorId(value)
    if type(value) == "table" then
        return value.id or value.name
    end
    return value
end

local function clientWorkspace(client)
    return client and client.workspace or nil
end

local function clientMonitor(client)
    if not client then
        return nil
    end
    return client.monitorID or client.monitorId or client.monitor or client.monitorName
end

local function key(value, fallback)
    local stringValue = asString(value)
    if stringValue == nil or stringValue == "" then
        return fallback
    end
    return stringValue
end

local function safeFilePart(value)
    local result = tostring(value):gsub("[^%w%._%-]", "_")
    if result == "" then
        return "unknown"
    end
    return result
end

local function report(callback, ...)
    if callback then
        callback(...)
    end
end

-- Workspace-card grid metrics. The panel renderer and the bar widget both use
-- these so the preview adapts to whatever the panel's configured size is.
local LAYOUT = {
    -- Fallback grid width when the panel size cannot be read.
    gridWidth = 784,
    gridGap = 6,
    cardPad = 6,
    cardGap = 4,
    -- Breathing room between the window thumbnails and the card's bottom edge.
    cardSpacer = 12,
    -- Fixed aspect ratio (width / height) of every workspace preview, so cards
    -- are never stretched just to fill leftover panel space.
    previewAspect = 16 / 9,
    -- Previews kept on the screen at once; the chevrons scroll this window.
    previewCount = 3,
    -- Narrowest card worth showing; the window clamps here instead of shrinking
    -- the previews further.
    minCardWidth = 120,
    -- The card heading is an `sm` button (32px), so it sets the heading row's
    -- height - a smaller estimate would clip the previews inside the card.
    headingHeight = 32,
    maxTiles = 9,
    bodyPad = 8,
    -- Chrome around the grid: `headerHeight` is the `sm` button in the header,
    -- `footerHeight` the taller (`md` buttons) footer shown once a window is
    -- selected. The scroll container absorbs whatever is left over.
    headerHeight = 32,
    scrollGap = 8,
    footerHeight = 38,
    -- Inset the shell applies around a decorated panel (Style::panelPadding);
    -- the panel's configured size minus this on both sides is ours to lay out.
    panelPadding = 14,
    -- Slack kept between the preview row and the scroll's clip edge. The shell
    -- rounds the panel and content sizes to whole pixels, so a row sized to the
    -- exact content width can still lose its last card to the clip.
    fitSlack = 6,
}

Hypr.LAYOUT = LAYOUT

-- Bounding box of { x, y, w, h } rectangles; nil when the list is empty.
function Hypr.bboxOf(items)
    local minX, minY, maxX, maxY
    for _, item in ipairs(items) do
        local x1, y1 = item.x, item.y
        local x2, y2 = x1 + item.w, y1 + item.h
        minX = minX == nil and x1 or math.min(minX, x1)
        minY = minY == nil and y1 or math.min(minY, y1)
        maxX = maxX == nil and x2 or math.max(maxX, x2)
        maxY = maxY == nil and y2 or math.max(maxY, y2)
    end
    return minX, minY, maxX, maxY
end

-- Window geometry for one workspace, trimmed to the tiles the card can show.
function Hypr.windowItems(record)
    local items = {}
    for _, client in ipairs(record.clients or {}) do
        -- Floating windows overlap the tiling; leave them out of the preview
        -- layout so it mirrors the workspace's tiles.
        if client.floating ~= true then
            local at = client.at or { 0, 0 }
            local size = client.size or { 1280, 720 }
            items[#items + 1] = {
                client = client,
                x = tonumber(at[1]) or 0,
                y = tonumber(at[2]) or 0,
                w = math.max(1, tonumber(size[1]) or 1280),
                h = math.max(1, tonumber(size[2]) or 720),
            }
        end
    end
    if #items > LAYOUT.maxTiles then
        table.sort(items, function(a, b) return a.w * a.h > b.w * b.h end)
        for index = #items, LAYOUT.maxTiles + 1, -1 do items[index] = nil end
    end
    return items
end

-- Height the panel gives the preview row: everything below the panel size
-- minus the body padding, header, row gaps and footer.
local function gridHeightAvailable(targetContent)
    if not targetContent then
        return nil
    end
    return targetContent - LAYOUT.bodyPad * 2 - LAYOUT.headerHeight
        - LAYOUT.scrollGap * 2 - LAYOUT.footerHeight
end

-- Chrome inside a card around its preview area (padding, heading, bottom
-- spacer and the gaps between them). Every card gets the same chrome, so the
-- preview sections stay one fixed size.
local function cardChrome()
    return LAYOUT.cardPad * 2 + LAYOUT.headingHeight + LAYOUT.cardSpacer + LAYOUT.cardGap * 2
end

-- Widest card whose fixed-aspect preview still fits the panel height.
local function maxCardWidth(targetContent)
    local gridHeight = gridHeightAvailable(targetContent)
    if not gridHeight then
        return LAYOUT.gridWidth
    end
    local previewHeight = math.max(1, gridHeight - cardChrome())
    return math.max(LAYOUT.minCardWidth,
        math.floor(previewHeight * LAYOUT.previewAspect) + LAYOUT.cardPad * 2)
end

-- One-row metrics for the workspaces on screen: one card size for the whole
-- overview and the shared preview height. The panel renders its own content
-- height, so the scroll container absorbs whatever the fixed-aspect cards do
-- not use.
function Hypr.panelLayout(visible, targetContent, gridWidth)
    visible = visible or {}
    gridWidth = math.max(64, numberOr(gridWidth, LAYOUT.gridWidth))
    local gap = LAYOUT.gridGap
    local pad = LAYOUT.cardPad
    -- Fixed card size: the row is laid out for the full preview count, so a
    -- monitor with one or two workspaces keeps the same size instead of
    -- stretching its cards, and it still fits the panel width.
    local slots = math.max(1, LAYOUT.previewCount)
    local available = math.max(16, gridWidth - gap * (slots - 1))
    local cardWidth = math.floor(available / slots)
    cardWidth = math.max(LAYOUT.minCardWidth,
        math.min(cardWidth, maxCardWidth(targetContent)))
    local previewHeight = math.max(8, math.floor((cardWidth - pad * 2) / LAYOUT.previewAspect))
    local cards = {}
    for index, record in ipairs(visible) do
        cards[index] = {
            previewHeight = previewHeight,
            extra = #(record.clients or {}) > LAYOUT.maxTiles,
        }
    end
    return {
        cardWidth = cardWidth,
        previewHeight = previewHeight,
        cards = cards,
    }
end

-- Run `hyprctl -j ...` and decode its stdout asynchronously.
-- callback(data, error, commandResult) is called exactly once when accepted.
function Hypr.queryJson(args, callback, timeoutMs)
    if type(args) ~= "table" then
        report(callback, nil, "hyprctl arguments must be an array", nil)
        return false
    end

    local argv = { "hyprctl", "-j" }
    for _, argument in ipairs(args) do
        if argument == nil then
            report(callback, nil, "hyprctl arguments cannot contain nil", nil)
            return false
        end
        argv[#argv + 1] = tostring(argument)
    end

    return noctalia.runAsync(argv, function(result)
        if result.exitCode ~= 0 or result.timedOut then
            local detail = result.stderr or "hyprctl failed"
            if result.timedOut then
                detail = "hyprctl timed out: " .. detail
            end
            report(callback, nil, detail, result)
            return
        end

        local value, decodeError = noctalia.json.decode(result.stdout or "")
        if decodeError ~= nil then
            report(callback, nil, "invalid hyprctl JSON: " .. tostring(decodeError), result)
            return
        end
        report(callback, value, nil, result)
    end, timeoutMs)
end

Hypr.hyprctlJson = Hypr.queryJson
Hypr.query = Hypr.queryJson

-- Fetch the three lists needed by the overview in parallel.  A failed query is
-- represented by an empty list so one transient compositor error cannot strand
-- the refresh callback.
function Hypr.fetch(callback)
    local snapshot = { clients = {}, monitors = {}, workspaces = {} }
    local pending = 3
    local finished = false

    local function done(field, value)
        if finished then
            return
        end
        snapshot[field] = type(value) == "table" and value or {}
        pending = pending - 1
        if pending == 0 then
            finished = true
            report(callback, snapshot)
        end
    end

    local acceptedClients = Hypr.queryJson({ "clients" }, function(value)
        done("clients", value)
    end)
    local acceptedMonitors = Hypr.queryJson({ "monitors" }, function(value)
        done("monitors", value)
    end)
    local acceptedWorkspaces = Hypr.queryJson({ "workspaces" }, function(value)
        done("workspaces", value)
    end)
    local acceptedCursor = Hypr.queryJson({ "cursorpos" }, function(value)
        done("cursor", value)
    end)

    -- runAsync can reject before installing a callback.  Complete those legs
    -- asynchronously through the same accounting path without changing the
    -- public callback contract.
    if not acceptedClients then done("clients", {}) end
    if not acceptedMonitors then done("monitors", {}) end
    if not acceptedWorkspaces then done("workspaces", {}) end
    if not acceptedCursor then done("cursor", {}) end
    return acceptedClients and acceptedMonitors and acceptedWorkspaces and acceptedCursor
end

-- Output under the pointer, falling back to the focused monitor. Panel scripts
-- get no output from the host snapshot, and the panel is placed on the monitor
-- the pointer is on, so this is the output an open overview belongs to.
function Hypr.activeOutput(snapshot)
    local monitors = (snapshot and snapshot.monitors) or {}
    local cursor = snapshot and snapshot.cursor
    local x, y = tonumber(cursor and cursor.x), tonumber(cursor and cursor.y)
    if x and y then
        for _, monitor in ipairs(monitors) do
            local mx, my = tonumber(monitor.x), tonumber(monitor.y)
            local mw, mh = tonumber(monitor.width), tonumber(monitor.height)
            if mx and my and mw and mh and x >= mx and x < mx + mw and y >= my and y < my + mh then
                return monitor.name
            end
        end
    end
    for _, monitor in ipairs(monitors) do
        if monitor.focused then
            return monitor.name
        end
    end
    return nil
end

-- Hyprland 0.55 evaluates Lua dispatchers; older releases use hyprctl dispatch.
-- Try the Lua form first and fall back when the compositor does not support it.
local function luaDispatch(dispatcher, argument)
    local quoted = string.format("%q", argument or "")
    if dispatcher == "workspace" then
        return "hl.dispatch(hl.dsp.focus({ workspace = " .. quoted .. " }))"
    elseif dispatcher == "focuswindow" then
        return "hl.dispatch(hl.dsp.focus({ window = " .. quoted .. " }))"
    elseif dispatcher == "togglespecialworkspace" then
        return "hl.dispatch(hl.dsp.workspace.toggle_special(" .. quoted .. "))"
    elseif dispatcher == "togglefloating" then
        return "hl.dispatch(hl.dsp.window.float({ window = " .. quoted .. " }))"
    elseif dispatcher == "movetoworkspace" then
        local workspace, window = string.match(argument or "", "^(.-),(.+)$")
        if workspace and window then
            return "hl.dispatch(hl.dsp.window.move({ workspace = " .. string.format("%q", workspace)
                .. ", window = " .. string.format("%q", window) .. ", follow = true }))"
        end
    end
    return nil
end

-- Dispatch a compositor command without interpolating values into a shell.
function Hypr.dispatch(dispatcher, arguments, callback, timeoutMs)
    local argv = { "hyprctl", "dispatch", tostring(dispatcher) }
    if type(arguments) == "function" then
        timeoutMs = callback
        callback = arguments
        arguments = nil
    end
    if arguments ~= nil and type(arguments) ~= "table" then
        argv[#argv + 1] = tostring(arguments)
    else
        for _, argument in ipairs(arguments or {}) do
            argv[#argv + 1] = tostring(argument)
        end
    end
    local argument = type(arguments) == "table" and table.concat(arguments, " ") or tostring(arguments or "")
    local expression = luaDispatch(dispatcher, argument)
    if not expression then return noctalia.runAsync(argv, callback, timeoutMs) end
    local function legacy()
        return noctalia.runAsync(argv, callback, timeoutMs)
    end
    local accepted = noctalia.runAsync({ "hyprctl", "eval", expression }, function(result)
        if result.exitCode == 0 and not result.timedOut then
            report(callback, result)
        else
            legacy()
        end
    end, timeoutMs)
    if not accepted then return legacy() end
    return true
end

local function ensureMonitor(monitorsByKey, monitors, monitor)
    local id = key(monitorId(monitor), "unknown")
    local entry = monitorsByKey[id]
    if not entry and type(monitor) ~= "table" then
        for _, candidate in ipairs(monitors) do
            if tostring(candidate.id) == tostring(monitor) or tostring(candidate.name) == tostring(monitor) then
                entry = candidate
                monitorsByKey[id] = candidate
                break
            end
        end
    end
    if entry then
        return entry
    end
    -- A workspace can reference a monitor the compositor did not list (a failed
    -- `monitors` query, a monitor just unplugged): keep the entry usable and
    -- nameless instead of indexing the raw reference.
    local rawMonitor = type(monitor) == "table" and monitor or nil
    entry = {
        id = monitorId(monitor),
        name = rawMonitor and rawMonitor.name or nil,
        monitor = rawMonitor,
        workspaces = {},
        clients = {},
    }
    monitorsByKey[id] = entry
    monitors[#monitors + 1] = entry
    return entry
end

-- Normalize Hyprland's independent monitor/workspace/client lists into one tree.
-- The returned object also contains lookup maps for callers that need fast access.
function Hypr.groupState(monitors, workspaces, clients)
    local state = {
        monitors = {},
        workspaces = {},
        clients = {},
        monitorById = {},
        workspaceById = {},
        clientById = {},
    }

    for _, monitor in ipairs(monitors or {}) do
        ensureMonitor(state.monitorById, state.monitors, monitor)
    end

    for _, workspace in ipairs(workspaces or {}) do
        local id = workspaceId(workspace)
        local workspaceEntry = {
            id = id,
            name = workspace.name,
            workspace = workspace,
            clients = {},
            monitor = nil,
        }
        local workspaceKey = key(id, "workspace_" .. tostring(#state.workspaces + 1))
        state.workspaceById[workspaceKey] = workspaceEntry
        state.workspaces[#state.workspaces + 1] = workspaceEntry

        local monitor = ensureMonitor(state.monitorById, state.monitors, workspace.monitorID or workspace.monitor)
        workspaceEntry.monitor = monitor
        monitor.workspaces[#monitor.workspaces + 1] = workspaceEntry
    end

    for index, client in ipairs(clients or {}) do
        local clientId = key(client.address or client.stableId or client.id, "client_" .. tostring(index))
        local clientEntry = {
            id = clientId,
            client = client,
            workspace = nil,
            monitor = nil,
        }
        state.clientById[clientId] = clientEntry
        state.clients[#state.clients + 1] = clientEntry

        local monitor = ensureMonitor(state.monitorById, state.monitors, clientMonitor(client))
        clientEntry.monitor = monitor
        monitor.clients[#monitor.clients + 1] = clientEntry

        local wsKey = key(workspaceId(clientWorkspace(client)), "")
        local workspaceEntry = state.workspaceById[wsKey]
        if not workspaceEntry then
            local workspaceValue = clientWorkspace(client) or {}
            workspaceEntry = {
                id = workspaceId(workspaceValue),
                name = workspaceValue.name,
                workspace = workspaceValue,
                clients = {},
                monitor = monitor,
            }
            state.workspaceById[wsKey] = workspaceEntry
            state.workspaces[#state.workspaces + 1] = workspaceEntry
            monitor.workspaces[#monitor.workspaces + 1] = workspaceEntry
        end
        clientEntry.workspace = workspaceEntry
        workspaceEntry.clients[#workspaceEntry.clients + 1] = clientEntry
        if workspaceEntry.monitor == nil then
            workspaceEntry.monitor = monitor
        end
    end

    return state
end

Hypr.group = Hypr.groupState

-- Every workspace record the overview can show on one output, sorted by id
-- (special workspaces last). This is the whole list the preview window scrolls
-- through; `Hypr.window` picks the records on screen.
function Hypr.workspaces(snapshot, outputName, showEmpty, showSpecial)
    snapshot = snapshot or {}
    local state = Hypr.groupState(snapshot.monitors, snapshot.workspaces, snapshot.clients)
    local outputKey = outputName and tostring(outputName) or nil
    if outputKey == "" then
        outputKey = nil
    end
    local candidates = {}

    for _, workspace in ipairs(state.workspaces) do
        local monitor = workspace.monitor
        local monitorName = monitor and (monitor.name or monitor.id) or nil
        local raw = workspace.workspace or {}
        local id = workspace.id
        local special = (type(id) == "number" and id < 0) or (type(raw.name) == "string" and raw.name:match("^special:"))
        local matchesOutput = outputKey == nil or tostring(monitorName) == outputKey
        local activeWorkspace = monitor and monitor.monitor and monitor.monitor.activeWorkspace
        local isActive = activeWorkspace and (tostring(workspaceId(activeWorkspace)) == tostring(id)
            or (special and tostring(activeWorkspace.name or "") == tostring(workspace.name or "")))
        if matchesOutput and (showSpecial or not special) and (showEmpty or #workspace.clients > 0 or isActive) then
            local record = {
                id = id,
                name = workspace.name or raw.name or tostring(id or ""),
                monitor = monitor and (monitor.name or monitor.id) or nil,
                clients = {},
                active = false,
                special = special,
                workspace = raw,
            }
            for _, clientEntry in ipairs(workspace.clients) do
                record.clients[#record.clients + 1] = clientEntry.client
            end
            record.active = isActive == true
            candidates[#candidates + 1] = record
        end
    end

    table.sort(candidates, function(left, right)
        local leftSpecial = left.special and 1 or 0
        local rightSpecial = right.special and 1 or 0
        if leftSpecial ~= rightSpecial then
            return leftSpecial < rightSpecial
        end
        local leftId = type(left.id) == "number" and left.id or math.huge
        local rightId = type(right.id) == "number" and right.id or math.huge
        if leftId ~= rightId then
            return leftId < rightId
        end
        return tostring(left.name) < tostring(right.name)
    end)

    return candidates
end

-- The preview window: `count` records starting at `offset`, clamped so it never
-- runs past the end (the last window stays full when enough workspaces exist).
function Hypr.window(records, count, offset)
    records = records or {}
    count = math.max(1, numberOr(count, 1))
    offset = math.max(0, numberOr(offset, 0))
    local first = math.min(offset + 1, math.max(1, #records - count + 1))
    local result = {}
    for index = first, math.min(first + count - 1, #records) do
        result[#result + 1] = records[index]
    end
    return result
end

-- Create a live, per-window screenshot cache. `update(windows)` starts one capture
-- for each new window and removes images for windows no longer present.
function Hypr.newCaptureManager(prefix, onImage)
    local options = type(prefix) == "table" and prefix or {}
    local requestedPrefix = type(prefix) == "string" and prefix or options.prefix
    requestedPrefix = requestedPrefix or "window"
    local pluginDataDirectory = noctalia.pluginDataDir()
    if not pluginDataDirectory then
        pluginDataDirectory = noctalia.expandPath("~/.local/state/noctalia/plugin-data")
    end
    local filePrefix = pluginDataDirectory .. "/" .. safeFilePart(requestedPrefix) .. "-"
    onImage = type(prefix) == "table" and options.onImage or onImage
    local directory = options.directory
    local entries = {}
    local serial = 0
    local manager = {}

    local function pathFor(stableId)
        serial = serial + 1
        return filePrefix .. safeFilePart(stableId) .. "_" .. tostring(serial) .. ".png"
    end

    local function removeEntry(entry)
        if entry.path then
            noctalia.removeFile(entry.path)
        end
        entries[entry.id] = nil
    end

    local function stableIdOf(window)
        if type(window) ~= "table" then
            return nil
        end
        return key(window.stableId or window.address or window.id or window.pid, nil)
    end

    function manager:request(window, force)
        local stableId = stableIdOf(window)
        if not stableId then
            return false
        end
        local old = entries[stableId]
        if old and old.inFlight then
            return true
        end
        if old and old.path and force ~= true then
            return true
        end
        -- Keep the last good frame visible until the replacement is ready.
        local entry = { id = stableId, path = old and old.path or nil, nextPath = pathFor(stableId), inFlight = true }
        entries[stableId] = entry
        local captureDirectory = directory or pluginDataDirectory
        local ok, mkdirError = true, nil
        if captureDirectory then
            ok, mkdirError = noctalia.mkdirAll(captureDirectory)
        end
        if not ok then
            entries[stableId] = nil
            report(onImage, stableId, nil, "could not create screenshot directory: " .. tostring(mkdirError))
            return false
        end

        local path = entry.nextPath
        local accepted = noctalia.runAsync({ "grim", "-T", stableId, path }, function(result)
            local current = entries[stableId]
            if current ~= entry then
                noctalia.removeFile(path)
                return
            end
            entry.inFlight = false
            if result.exitCode ~= 0 or result.timedOut then
                entries[stableId] = old
                noctalia.removeFile(path)
                report(onImage, stableId, nil, result.stderr or "grim failed", result)
                return
            end
            if entry.path then noctalia.removeFile(entry.path) end
            entry.path = path
            entry.nextPath = nil
            report(onImage, stableId, path, nil, result)
        end, options.timeoutMs)
        if not accepted then
            entries[stableId] = old
            noctalia.removeFile(path)
            report(onImage, stableId, nil, "grim request was rejected", nil)
        end
        return accepted
    end

    manager.capture = manager.request

    function manager:update(windows, force)
        local seen = {}
        for _, window in ipairs(windows or {}) do
            local stableId = stableIdOf(window)
            if stableId then
                seen[stableId] = true
                manager:request(window, force ~= false)
            end
        end
        for id, entry in pairs(entries) do
            if not seen[id] then
                removeEntry(entry)
            end
        end
    end

    function manager:path(client)
        local stableId = stableIdOf(client) or asString(client)
        local entry = entries[stableId]
        return entry and entry.path or nil
    end

    function manager:remove(stableId)
        local entry = entries[asString(stableId)]
        if entry then
            removeEntry(entry)
        end
    end

    function manager:clear()
        for _, entry in pairs(entries) do
            if entry.path then
                noctalia.removeFile(entry.path)
            end
            if entry.nextPath then
                noctalia.removeFile(entry.nextPath)
            end
        end
        entries = {}
    end

    manager.getPath = manager.path
    return manager
end

Hypr.newScreenshotManager = Hypr.newCaptureManager
Hypr.CaptureManager = Hypr.newCaptureManager

return Hypr
