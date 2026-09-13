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
-- these so the widget can pick a panel variant that fits before it opens.
-- 784/389 = the previous overview grid scaled by 0.7, so the click panel now
-- matches the hover preview layout.
local LAYOUT = {
    gridWidth = 784,
    gridGap = 6,
    maxCardWidth = 389,
    cardPad = 6,
    cardGap = 4,
    minThumbHeight = 52,
    maxThumbHeight = 300,
    headingHeight = 22,
    maxTiles = 9,
    bodyPad = 8,
    -- Conservative chrome estimates: the rendered header/footer rows are a few
    -- pixels taller than the raw font sizes, which would otherwise make the
    -- grid overflow and show a scroll bar.
    headerHeight = 40,
    scrollGap = 8,
    footerHeight = 32,
    minContentHeight = 180,
    -- Slack left when growing the cards to fill a panel bucket, covering the
    -- difference between the estimated chrome and the rendered header/footer.
    fillInset = 16,
}

Hypr.LAYOUT = LAYOUT

-- Panel size buckets (manifest heights, +10% vertical room). The widget picks
-- the smallest bucket that fits the computed content so the window hugs the
-- workspace previews without clipping them.
Hypr.PANEL_BUCKETS = { 220, 265, 320, 375, 475 }
Hypr.BASE_PANEL_HEIGHT = 475

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
    if #items > LAYOUT.maxTiles then
        table.sort(items, function(a, b) return a.w * a.h > b.w * b.h end)
        for index = #items, LAYOUT.maxTiles + 1, -1 do items[index] = nil end
    end
    return items
end

-- Thumbnail area height for a workspace, scaled from its window bounding box.
function Hypr.thumbHeight(record, interiorWidth)
    local items = Hypr.windowItems(record)
    local minX, minY, maxX, maxY = Hypr.bboxOf(items)
    if minX == nil then
        return nil
    end
    local boxWidth = math.max(1, maxX - minX)
    local boxHeight = math.max(1, maxY - minY)
    local height = math.floor(interiorWidth * boxHeight / boxWidth)
    return math.max(LAYOUT.minThumbHeight, math.min(LAYOUT.maxThumbHeight, height))
end

-- Grid metrics for a set of visible workspace records: column count, card
-- width, per-card thumbnail heights and the content height needed to host
-- everything without scrolling.
function Hypr.panelLayout(visible, configuredColumns, preview, targetContent)
    visible = visible or {}
    local count = #visible
    local columns = math.min(math.max(1, numberOr(configuredColumns, 5)), math.max(1, count))
    local available = math.max(16, LAYOUT.gridWidth - LAYOUT.gridGap * (columns - 1))
    local cardWidth = math.min(LAYOUT.maxCardWidth, math.floor(available / columns))
    local interiorWidth = math.max(24, cardWidth - LAYOUT.cardPad * 2)
    local cards = {}
    local maxCardHeight = 0
    for index, record in ipairs(visible) do
        local thumb = Hypr.thumbHeight(record, interiorWidth)
        local extra = #(record.clients or {}) > LAYOUT.maxTiles
        if thumb == nil then thumb = 16 end
        if extra then thumb = thumb + 16 end
        local children = extra and 3 or 2
        local cardHeight = LAYOUT.cardPad * 2 + LAYOUT.headingHeight + thumb + LAYOUT.cardGap * (children - 1)
        cards[index] = {
            thumbHeight = thumb - (extra and 16 or 0),
            extra = extra,
        }
        if cardHeight > maxCardHeight then maxCardHeight = cardHeight end
    end
    local rows = math.ceil(math.max(1, count) / columns)
    local gridHeight = count > 0 and (rows * maxCardHeight + (rows - 1) * LAYOUT.gridGap) or 0
    local footer = preview and 0 or LAYOUT.footerHeight
    local contentHeight = LAYOUT.bodyPad * 2 + LAYOUT.headerHeight + gridHeight
        + (gridHeight > 0 and LAYOUT.scrollGap or 0)
        + (footer > 0 and (LAYOUT.scrollGap + footer) or 0)
    -- `targetContent` is the panel bucket the widget selected. Grow the
    -- thumbnail area (not the bottom margin) to fill that height so the
    -- previews use the whole window.
    if targetContent and targetContent > contentHeight and count > 0 then
        local extra = targetContent - contentHeight - LAYOUT.fillInset
        if extra > 0 then
            local extraPerRow = extra / rows
            for _, card in ipairs(cards) do
                card.thumbHeight = card.thumbHeight + extraPerRow
            end
        end
        contentHeight = targetContent
    end
    return {
        columns = columns,
        cardWidth = cardWidth,
        rows = rows,
        cards = cards,
        contentHeight = math.max(LAYOUT.minContentHeight, contentHeight),
    }
end

-- Smallest panel bucket that can host the given content height.
function Hypr.pickBucket(contentHeight)
    for _, bucket in ipairs(Hypr.PANEL_BUCKETS) do
        if contentHeight <= bucket - 24 then
            return bucket
        end
    end
    return Hypr.PANEL_BUCKETS[#Hypr.PANEL_BUCKETS]
end

-- Visible workspaces on one output plus the panel bucket that fits them and
-- the content height the bucket provides.
function Hypr.pickPanel(snapshot, output, rows, columns, showEmpty, showSpecial, preview)
    local visible = Hypr.visible(snapshot, output, rows, columns, showEmpty, showSpecial, 0)
    local metrics = Hypr.panelLayout(visible, columns, preview)
    local bucket = Hypr.pickBucket(metrics.contentHeight)
    return bucket, bucket - 24
end

-- Map a bucket to a panel entry id; the largest bucket uses the base id.
function Hypr.bucketId(base, bucket)
    if bucket == Hypr.BASE_PANEL_HEIGHT then
        return base
    end
    return base .. "-" .. tostring(bucket)
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

    -- runAsync can reject before installing a callback.  Complete those legs
    -- asynchronously through the same accounting path without changing the
    -- public callback contract.
    if not acceptedClients then done("clients", {}) end
    if not acceptedMonitors then done("monitors", {}) end
    if not acceptedWorkspaces then done("workspaces", {}) end
    return acceptedClients and acceptedMonitors and acceptedWorkspaces
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
    entry = {
        id = monitorId(monitor),
        name = monitor and monitor.name or nil,
        monitor = monitor,
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

-- Return the workspace records shown on one output and page.  Empty normal
-- workspaces can be included, while special workspaces are opt-in.  `pageOffset`
-- is a zero-based page number; negative values are clamped to zero.
function Hypr.visible(snapshot, outputName, rows, columns, showEmpty, showSpecial, pageOffset)
    snapshot = snapshot or {}
    rows = math.max(1, numberOr(rows, 1))
    columns = math.max(1, numberOr(columns, 1))
    pageOffset = math.max(0, numberOr(pageOffset, 0))
    local capacity = rows * columns
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

    local first = pageOffset * capacity + 1
    local last = first + capacity - 1
    local byId = {}
    local specials = {}
    for _, record in ipairs(candidates) do
        if record.special then
            specials[#specials + 1] = record
        elseif type(record.id) == "number" and record.id >= first and record.id <= last then
            byId[record.id] = record
        end
    end
    local result = {}
    for id = first, last do
        local record = byId[id]
        if record then
            result[#result + 1] = record
        elseif showEmpty then
            result[#result + 1] = {
                id = id, name = tostring(id), monitor = outputKey,
                clients = {}, active = false, special = false, workspace = nil,
            }
        end
    end
    if showSpecial then
        local reserved = math.min(#specials, math.max(0, capacity - 1))
        for index = 1, reserved do
            if #result >= capacity then table.remove(result) end
            result[#result + 1] = specials[index]
        end
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
