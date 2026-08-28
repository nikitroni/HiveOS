-- config_wizard.lua
-- Universal config creation/editing wizard via chat.
-- Monitor only shows summary; all interaction goes through in-game chat.

local MonitorUtil = require("screens/monitor_util")
local ChatUtil = require("chat_util")
local LogUtil = require("log_util")

local ConfigWizard = {}

-- ==================== HELPERS ====================

--- Get sorted list of all peripheral names
local function getPeripheralList()
    local names = peripheral.getNames()
    table.sort(names)
    return names
end

--- Compare two peripheral lists: find added and removed
local function compareLists(oldList, newList)
    local oldSet = {}
    local newSet = {}
    for _, name in ipairs(oldList) do
        oldSet[name] = true
    end
    for _, name in ipairs(newList) do
        newSet[name] = true
    end

    local added = {}
    local removed = {}
    for _, name in ipairs(newList) do
        if not oldSet[name] then
            table.insert(added, name)
        end
    end
    for _, name in ipairs(oldList) do
        if not newSet[name] then
            table.insert(removed, name)
        end
    end
    return added, removed
end

--- Check if device is in global list (known devices)
local function isInGlobalList(deviceName, globalAllDevices)
    for _, name in ipairs(globalAllDevices) do
        if name == deviceName then
            return true
        end
    end
    return false
end

--- Check if device has all required methods
local function matchesMethods(name, checkMethods)
    local methods = peripheral.getMethods(name)
    for _, required in ipairs(checkMethods) do
        local found = false
        for _, m in ipairs(methods) do
            if m == required then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

--- Chat shortcuts
local function chat(msg) ChatUtil.send(msg) end
local function chatInfo(msg) ChatUtil.sendInfo(msg) end
local function chatSuccess(msg) ChatUtil.sendSuccess(msg) end
local function chatError(msg) ChatUtil.sendError(msg) end
local function chatStep(msg) ChatUtil.sendStep(msg) end
local function chatHighlight(msg) ChatUtil.sendHighlight(msg) end
local function chatQuestion(msg) ChatUtil.sendQuestion(msg) end
local function chatSeparator() ChatUtil.sendSeparator() end

--- Build a comma-joined list of device/peripheral names, each colored green.
local function deviceList(list, sep)
  local parts = {}
  local s = sep or ", "
  for _, n in ipairs(list) do
    table.insert(parts, ChatUtil.device(n))
  end
  return table.concat(parts, s)
end

-- ==================== SCAN A SINGLE DEVICE TYPE ====================

--- Scan a single device type.
--- Supports 2 scenarios:
---   Scenario 1: Connect a NEW device (appears in list, not in globalAllDevices)
---   Scenario 2: DISCONNECT and RECONNECT an already known device
---
--- @param deviceType table element from device_types.lua
--- @param globalAllDevices table list of all ever-seen devices
--- @return table list of found device names for this type
function ConfigWizard.scanDeviceType(deviceType, globalAllDevices)
    local foundDevices = {}
    local maxCount = deviceType.max or 999
    local label = deviceType.label
    local checkMethods = deviceType.checkMethods

    chatSeparator()
    chatHighlight("=== " .. ChatUtil.device(label) .. " ===")
    chatInfo("Required: " .. (maxCount == 999 and "unlimited" or tostring(maxCount)))

    local adding = true
    local skipRequestedThisType = false
    while adding and not skipRequestedThisType do
        local deviceFound = false
        local detectedName = nil

        while not deviceFound and not skipRequestedThisType do
            chatSeparator()
            chatStep("Connect device [" .. ChatUtil.device(label) .. "] (new/reconnect/skip)")

            local prevList = getPeripheralList()

            local timeout = 120
            local elapsed = 0
            local scanning = true

            local scanTimerId = os.startTimer(0.5)

            while scanning and elapsed < timeout do
                local rawEvent = {os.pullEventRaw()}
                local event = rawEvent[1]

                if event == "timer" and rawEvent[2] == scanTimerId then
                    elapsed = elapsed + 0.5

                    local currentList = getPeripheralList()
                    local added, removed = compareLists(prevList, currentList)

                    if #added == 1 and #removed == 0 then
                        local name = added[1]
                        if matchesMethods(name, checkMethods) then
                            detectedName = name
                            deviceFound = true
                            scanning = false
                        else
                            chatError("Detected: " .. ChatUtil.device(name, ChatUtil.code("c")) .. " (does not match required methods)")
                            if not isInGlobalList(name, globalAllDevices) then
                                table.insert(globalAllDevices, name)
                            end
                            prevList = currentList
                            chatInfo("Try a different device.")
                        end
                    elseif #removed == 1 and #added == 1 then
                        local removedName = removed[1]
                        local addedName = added[1]
                        if removedName == addedName and isInGlobalList(addedName, globalAllDevices) then
                            if matchesMethods(addedName, checkMethods) then
                                detectedName = addedName
                                deviceFound = true
                                scanning = false
                            end
                        end
                        if not deviceFound then
                            prevList = currentList
                        end
                    elseif #added > 0 or #removed > 0 then
                        if not deviceFound then
                            local detail = "Multiple changes detected"
                            if #added > 0 then detail = detail .. ", added: " .. deviceList(added) end
                            if #removed > 0 then detail = detail .. ", removed: " .. deviceList(removed) end
                            chatInfo(detail)
                            chatInfo("Work with one device at a time.")
                            for _, name in ipairs(added) do
                                if not isInGlobalList(name, globalAllDevices) then
                                    table.insert(globalAllDevices, name)
                                end
                            end
                            prevList = currentList
                        end
                    end

                    if scanning then
                        scanTimerId = os.startTimer(0.5)
                    end

                elseif event == "chat_signed" or event == "chat" then
                    local msg = rawEvent[3] or ""
                    local player = rawEvent[2]
                    if msg ~= "" then
                        local isEcho = (event == "chat" and ChatUtil.isOwnEcho and ChatUtil.isOwnEcho(msg, player))
                        if not isEcho and string.lower(msg) == "skip" then
                            chatHighlight("Skipping device type: " .. ChatUtil.device(label))
                            skipRequestedThisType = true
                            scanning = false
                        end
                    end
                end
            end

if not deviceFound and not skipRequestedThisType then
                    chatError("Timeout! Device [" .. ChatUtil.device(label, ChatUtil.code("c")) .. "] not detected.")
                    chatInfo("Check connection and try again, or type 'skip'.")

                local skipNow = ChatUtil.waitForAnyMessage(10)
                if skipNow and string.lower(skipNow) == "skip" then
                    chatHighlight("Skipping device type: " .. ChatUtil.device(label))
                    skipRequestedThisType = true
                end
            end

            if skipRequestedThisType then
                break
            end
        end

        if deviceFound and detectedName then
            local name = detectedName

            if not isInGlobalList(name, globalAllDevices) then
                table.insert(globalAllDevices, name)
            end

            local alreadyAdded = false
            for _, existing in ipairs(foundDevices) do
                if existing == name then
                    alreadyAdded = true
                    break
                end
            end

            if alreadyAdded then
                chatError("Device " .. ChatUtil.device(name, ChatUtil.code("c")) .. " already added to this section!")
                chatInfo("Connect a different device.")
                deviceFound = false
            else
                chatSeparator()
                chatSuccess("Device detected: " .. ChatUtil.device(name))
                chatInfo("Found device matches type [" .. ChatUtil.device(label) .. "]")
                chatQuestion("Add it to config? (Y/N)")

                local confirmed = ChatUtil.waitForYesNo(120)

                if confirmed == nil then
                    chatError("Response timeout. Try again.")
                elseif confirmed then
                    -- Переместить уже добавленные найденные первыми?
                    table.insert(foundDevices, name)
                    chatSuccess("Added: " .. ChatUtil.device(name) .. " -> " .. ChatUtil.device(label))

                    if #foundDevices >= maxCount then
                        adding = false
                    else
                        chatQuestion("Add another [" .. ChatUtil.device(label, ChatUtil.code("b")) .. "]? (Y/N)")
                        local addMore = ChatUtil.waitForYesNo(120)

                        if addMore == nil then
                            chatError("Timeout. Moving to next type.")
                            adding = false
                        elseif not addMore then
                            adding = false
                        end
                    end
                else
                    chatInfo("Device declined. Connect a different device.")
                    deviceFound = false
                end
            end
        end
    end

    return foundDevices
end

-- ==================== PAGE DISPLAY FUNCTIONS ====================

--- Quick page display with auto-continue.
--- Draws page, waits 3 seconds or any touch (except Back/Prev/Next) — then exits.
--- Used for non-blocking updates (Updated, Summary).
--- @param items table array of {key=, value=, color=}
--- @param title string
--- @param mon table monitor
--- @param monSide string monitor side
--- @return "dismissed"
function ConfigWizard.displayPage(mon, monSide, title, items, linesPerPage)
    local w, h = mon.getSize()
    linesPerPage = linesPerPage or (h - 5)
    if linesPerPage < 1 then linesPerPage = 1 end

    -- Pre-compute item lines (same as editPageLoop)
    local itemLines = {}
    for _, item in ipairs(items) do
        local prefix = item.key .. ": "
        local prefixLen = #prefix
        local display = type(item.value) == "table" and table.concat(item.value, ", ") or tostring(item.value)
        local lines = {}

        local oneLine = prefix .. display
        if #oneLine <= w - 4 then
            table.insert(lines, {prefix = prefix, display = display, prefixLen = prefixLen, color = item.color})
        else
            local remaining = display
            local canFit = w - 4 - prefixLen
            if canFit > 0 then
                local take = canFit
                if take > #remaining then take = #remaining end
                local sub = remaining:sub(1, take)
                local lastSpace = sub:match("^.*%s")
                if lastSpace then take = #lastSpace - 1 end
                if take < 1 then take = canFit end
                table.insert(lines, {prefix = prefix, display = remaining:sub(1, take), prefixLen = prefixLen, color = item.color})
                remaining = remaining:sub(take + 1)
                remaining = remaining:match("^%s*(.*)") or remaining
            else
                table.insert(lines, {prefix = prefix, display = "", prefixLen = prefixLen, color = item.color})
            end
            local lineWidth = w - 4
            if lineWidth < 2 then lineWidth = 2 end
            while #remaining > 0 do
                if #remaining <= lineWidth then
                    table.insert(lines, {prefix = "", display = remaining, prefixLen = 0, color = item.color})
                    remaining = ""
                else
                    local take = lineWidth
                    local sub = remaining:sub(1, take)
                    local lastSpace = sub:match("^.*%s")
                    if lastSpace then take = #lastSpace - 1 end
                    if take < 1 then take = lineWidth end
                    table.insert(lines, {prefix = "", display = remaining:sub(1, take), prefixLen = 0, color = item.color})
                    remaining = remaining:sub(take + 1)
                    remaining = remaining:match("^%s*(.*)") or remaining
                end
            end
        end
        table.insert(itemLines, lines)
    end

    local totalLines = 0
    for _, lines in ipairs(itemLines) do totalLines = totalLines + #lines end
    local totalPages = math.max(1, math.ceil(totalLines / linesPerPage))

    MonitorUtil.clearScreen(mon)
    MonitorUtil.drawTitle(mon, title, 2)

    if totalLines == 0 then
        MonitorUtil.drawText(mon, 4, 4, "(no data to display)", MonitorUtil.COLORS.text)
    else
        local startLine = 1
        local endLine = math.min(startLine + linesPerPage - 1, totalLines)
        local lineIdx = 1
        local drawnY = 4
        for _, lines in ipairs(itemLines) do
            for _, line in ipairs(lines) do
                if lineIdx >= startLine and lineIdx <= endLine then
                    if line.prefix ~= "" then
                        MonitorUtil.drawText(mon, 4, drawnY, line.prefix, line.color)
                    end
                    if line.display ~= "" then
                        MonitorUtil.drawText(mon, 4 + line.prefixLen, drawnY, line.display, MonitorUtil.COLORS.text)
                    end
                    drawnY = drawnY + 1
                end
                lineIdx = lineIdx + 1
            end
        end
    end

    if totalPages > 1 then
        local pageText = "Page 1/" .. totalPages
        local pageX = math.floor((w - #pageText) / 2) + 1
        if pageX < 12 then pageX = 12 end
        MonitorUtil.drawText(mon, pageX, h - 1, pageText, MonitorUtil.COLORS.highlight)
    end

    local timerId = os.startTimer(3)
    while true do
        local rawEvent = {os.pullEventRaw()}
        local event = rawEvent[1]
        if event == "timer" and rawEvent[2] == timerId then
            break
        elseif event == "monitor_touch" then
            break
        end
    end
    return "dismissed"
end

--- Draws a config page and loop-waits for touch/chat/timeout.
---   touch on Prev/Next — redraw and wait again.
---   touch on Back — return "back", nil
---   timeout 30s — return "timeout", nil
---   chat/chat_signed — return "chat", message text
function ConfigWizard.editPageLoop(mon, monSide, title, items, linesPerPage)
    local w, h = mon.getSize()
    linesPerPage = linesPerPage or (h - 5)
    if linesPerPage < 1 then linesPerPage = 1 end

    local currentPage = 0
    -- Pre-compute item lines (same as in paginatedView)
    local itemLines = {}
    for _, item in ipairs(items) do
        local prefix = item.key .. ": "
        local prefixLen = #prefix
        local display = type(item.value) == "table" and table.concat(item.value, ", ") or tostring(item.value)
        local lines = {}

        local oneLine = prefix .. display
        if #oneLine <= w - 4 then
            table.insert(lines, {prefix = prefix, display = display, prefixLen = prefixLen, color = item.color})
        else
            local remaining = display
            local canFit = w - 4 - prefixLen
            if canFit > 0 then
                local take = canFit
                if take > #remaining then take = #remaining end
                local sub = remaining:sub(1, take)
                local lastSpace = sub:match("^.*%s")
                if lastSpace then take = #lastSpace - 1 end
                if take < 1 then take = canFit end
                table.insert(lines, {prefix = prefix, display = remaining:sub(1, take), prefixLen = prefixLen, color = item.color})
                remaining = remaining:sub(take + 1)
                remaining = remaining:match("^%s*(.*)") or remaining
            else
                table.insert(lines, {prefix = prefix, display = "", prefixLen = prefixLen, color = item.color})
            end
            local lineWidth = w - 4
            if lineWidth < 2 then lineWidth = 2 end
            while #remaining > 0 do
                if #remaining <= lineWidth then
                    table.insert(lines, {prefix = "", display = remaining, prefixLen = 0, color = item.color})
                    remaining = ""
                else
                    local take = lineWidth
                    local sub = remaining:sub(1, take)
                    local lastSpace = sub:match("^.*%s")
                    if lastSpace then take = #lastSpace - 1 end
                    if take < 1 then take = lineWidth end
                    table.insert(lines, {prefix = "", display = remaining:sub(1, take), prefixLen = 0, color = item.color})
                    remaining = remaining:sub(take + 1)
                    remaining = remaining:match("^%s*(.*)") or remaining
                end
            end
        end
        table.insert(itemLines, lines)
    end

    local backBtn = MonitorUtil.createButton(2, h - 1, 9, " [Back]", "back", colors.red)

    -- Drain accumulated chat_box echo events before waiting.
    if ChatUtil.drainQueue then
        ChatUtil.drainQueue()
    end

    local totalLines = 0
    for _, lines in ipairs(itemLines) do totalLines = totalLines + #lines end
    local totalPages = math.max(1, math.ceil(totalLines / linesPerPage))

    if totalLines == 0 then
        MonitorUtil.clearScreen(mon)
        MonitorUtil.drawTitle(mon, title, 2)
        MonitorUtil.drawText(mon, 4, 4, "(no data to display)", MonitorUtil.COLORS.text)
        MonitorUtil.drawButton(mon, backBtn, false)
        local timeoutId = os.startTimer(30)
        while true do
            local rawEvent = {os.pullEventRaw()}
            local event = rawEvent[1]
            if event == "timer" and rawEvent[2] == timeoutId then
                return "timeout", nil
            elseif event == "monitor_touch" and rawEvent[2] == monSide then
                local tx, ty = rawEvent[3], rawEvent[4]
                local pressed = MonitorUtil.getPressedButton({backBtn}, tx, ty)
                if pressed then return "back", nil end
            elseif event == "chat_signed" or event == "chat" then
                local msg = (rawEvent[3] or ""):match("^%s*(.-)%s*$") or ""
                local player = rawEvent[2]
                if event == "chat" and ChatUtil.isOwnEcho and ChatUtil.isOwnEcho(msg, player) then
                    -- own echo — skip
                else
                    return "chat", msg
                end
            end
        end
    end

    while true do
        MonitorUtil.clearScreen(mon)
        MonitorUtil.drawTitle(mon, title, 2)

        local startLine = currentPage * linesPerPage + 1
        local endLine = math.min(startLine + linesPerPage - 1, totalLines)
        local lineIdx = 1
        local drawnY = 4
        for _, lines in ipairs(itemLines) do
            for _, line in ipairs(lines) do
                if lineIdx >= startLine and lineIdx <= endLine then
                    if line.prefix ~= "" then
                        MonitorUtil.drawText(mon, 4, drawnY, line.prefix, line.color)
                    end
                    if line.display ~= "" then
                        MonitorUtil.drawText(mon, 4 + line.prefixLen, drawnY, line.display, MonitorUtil.COLORS.text)
                    end
                    drawnY = drawnY + 1
                end
                lineIdx = lineIdx + 1
            end
        end

        local pageText = "Page " .. (currentPage + 1) .. "/" .. totalPages
        local pageX = math.floor((w - #pageText) / 2) + 1
        if pageX < 1 then pageX = 1 end
        local prevStart = w - 19
        if pageX + #pageText >= prevStart then
            pageX = prevStart - #pageText - 2
        end
        if pageX < 12 then pageX = 12 end
        MonitorUtil.drawText(mon, pageX, h - 1, pageText, MonitorUtil.COLORS.highlight)

        local prevBtn, nextBtn
        if currentPage > 0 then
            prevBtn = MonitorUtil.createButton(w - 19, h - 1, 7, " [<Prev]", "prev", colors.blue)
            MonitorUtil.drawButton(mon, prevBtn, false)
        end
        if currentPage < totalPages - 1 then
            nextBtn = MonitorUtil.createButton(w - 11, h - 1, 7, " [Next>]", "next", colors.blue)
            MonitorUtil.drawButton(mon, nextBtn, false)
        end
        MonitorUtil.drawButton(mon, backBtn, false)

        local timeoutId = os.startTimer(30)
        local waiting = true
        local result = nil
        local capturedMessage = nil

        while waiting do
            local rawEvent = {os.pullEventRaw()}
            local event = rawEvent[1]

            if event == "timer" and rawEvent[2] == timeoutId then
                result = "timeout"
                waiting = false

            elseif event == "monitor_touch" then
                local touchSide = rawEvent[2]
                local tx, ty = rawEvent[3], rawEvent[4]
                if touchSide ~= monSide then
                    LogUtil.warn("Touch on " .. tostring(touchSide) .. ", expecting " .. tostring(monSide))
                else
                    local allButtons = { backBtn }
                    if prevBtn then table.insert(allButtons, prevBtn) end
                    if nextBtn then table.insert(allButtons, nextBtn) end

                    local pressed = MonitorUtil.getPressedButton(allButtons, tx, ty)
                    if pressed then
                        if pressed.action == "prev" then
                            currentPage = currentPage - 1
                            result = "page_changed"
                            waiting = false
                        elseif pressed.action == "next" then
                            currentPage = currentPage + 1
                            result = "page_changed"
                            waiting = false
                        elseif pressed.action == "back" then
                            result = "back"
                            waiting = false
                        end
                    end
                end

            elseif event == "chat_signed" or event == "chat" then
                local msg = (rawEvent[3] or ""):match("^%s*(.-)%s*$") or ""
                local player = rawEvent[2]
                if event == "chat" and ChatUtil.isOwnEcho and ChatUtil.isOwnEcho(msg, player) then
                    -- own echo — skip
                else
                    result = "chat"
                    capturedMessage = msg
                    waiting = false
                end
            end
        end

        if result ~= "page_changed" then
            return result, capturedMessage
        end
    end
end

-- ==================== WAIT YES/NO WITH MONITOR NAVIGATION ====================

--- Wait for a Y/N chat response while allowing the player to browse pages
--- on the monitor with Prev/Next/Back buttons.
--- @param mon table monitor
--- @param monSide string monitor side
--- @param title string page title
--- @param items table[] {key=, value=, color=}
--- @param promptText string to send to chat first
--- @param timeout number|nil seconds (default 120)
--- @return boolean|nil true=Y, false=N/Back, nil=timeout
function ConfigWizard.waitYesNoNav(mon, monSide, title, items, promptText, timeout)
    local w, h = mon.getSize()
    local linesPerPage = h - 5
    if linesPerPage < 1 then linesPerPage = 1 end
    local currentPage = 0

    -- Pre-compute wrapped items
    local itemLines = {}
    for _, item in ipairs(items) do
        local prefix = item.key .. ": "
        local prefixLen = #prefix
        local display = type(item.value) == "table" and table.concat(item.value, ", ") or tostring(item.value)
        local lines = {}

        local oneLine = prefix .. display
        if #oneLine <= w - 4 then
            table.insert(lines, {prefix = prefix, display = display, prefixLen = prefixLen, color = item.color})
        else
            local remaining = display
            local canFit = w - 4 - prefixLen
            if canFit > 0 then
                local take = canFit
                if take > #remaining then take = #remaining end
                local sub = remaining:sub(1, take)
                local lastSpace = sub:match("^.*%s")
                if lastSpace then take = #lastSpace - 1 end
                if take < 1 then take = canFit end
                table.insert(lines, { prefix = prefix, display = remaining:sub(1, take), prefixLen = prefixLen, color = item.color })
                remaining = remaining:sub(take + 1)
                remaining = remaining:match("^%s*(.*)") or remaining
            else
                table.insert(lines, { prefix = prefix, display = "", prefixLen = prefixLen, color = item.color })
            end
            local lineWidth = w - 4
            if lineWidth < 2 then lineWidth = 2 end
            while #remaining > 0 do
                if #remaining <= lineWidth then
                    table.insert(lines, { prefix = "", display = remaining, prefixLen = 0, color = item.color })
                    remaining = ""
                else
                    local take = lineWidth
                    local sub = remaining:sub(1, take)
                    local lastSpace = sub:match("^.*%s")
                    if lastSpace then take = #lastSpace - 1 end
                    if take < 1 then take = lineWidth end
                    table.insert(lines, { prefix = "", display = remaining:sub(1, take), prefixLen = 0, color = item.color })
                    remaining = remaining:sub(take + 1)
                    remaining = remaining:match("^%s*(.*)") or remaining
                end
            end
        end
        table.insert(itemLines, lines)
    end

    local totalLines = 0
    for _, lines in ipairs(itemLines) do totalLines = totalLines + #lines end
    local totalPages = math.max(1, math.ceil(totalLines / linesPerPage))

    -- Send prompt to chat
    if promptText and promptText ~= "" then
        chatSeparator()
        chatQuestion(promptText)
    end

    while true do
        -- Draw page
        MonitorUtil.clearScreen(mon)
        MonitorUtil.drawTitle(mon, title, 2)

        local startLine = currentPage * linesPerPage + 1
        local endLine = math.min(startLine + linesPerPage - 1, totalLines)
        local lineIdx = 1
        local drawnY = 4
        for _, lines in ipairs(itemLines) do
            for _, line in ipairs(lines) do
                if lineIdx >= startLine and lineIdx <= endLine then
                    if line.prefix ~= "" then
                        MonitorUtil.drawText(mon, 4, drawnY, line.prefix, line.color)
                    end
                    if line.display ~= "" then
                        MonitorUtil.drawText(mon, 4 + line.prefixLen, drawnY, line.display, MonitorUtil.COLORS.text)
                    end
                    drawnY = drawnY + 1
                end
                lineIdx = lineIdx + 1
            end
        end

        if totalPages > 1 then
            local pageText = "Page " .. (currentPage + 1) .. "/" .. totalPages
            local pageX = math.floor((w - #pageText) / 2) + 1
            if pageX < 12 then pageX = 12 end
            MonitorUtil.drawText(mon, pageX, h - 1, pageText, MonitorUtil.COLORS.highlight)
        end

        local prevBtn, nextBtn
        if currentPage > 0 and totalPages > 1 then
            prevBtn = MonitorUtil.createButton(w - 19, h - 1, 7, " [<Prev]", "prev", colors.blue)
            MonitorUtil.drawButton(mon, prevBtn, false)
        end
        if currentPage < totalPages - 1 then
            nextBtn = MonitorUtil.createButton(w - 11, h - 1, 7, " [Next>]", "next", colors.blue)
            MonitorUtil.drawButton(mon, nextBtn, false)
        end
        local backBtn = MonitorUtil.createButton(2, h - 1, 9, " [Back]", "back", colors.red)
        MonitorUtil.drawButton(mon, backBtn, false)

        local timeoutId = os.startTimer(timeout or 120)
        local waiting = true
        while waiting do
            local rawEvent = {os.pullEventRaw()}
            local event = rawEvent[1]

            if event == "timer" and rawEvent[2] == timeoutId then
                return nil

            elseif event == "monitor_touch" and rawEvent[2] == monSide then
                local tx, ty = rawEvent[3], rawEvent[4]
                local allButtons = {backBtn}
                if prevBtn then table.insert(allButtons, prevBtn) end
                if nextBtn then table.insert(allButtons, nextBtn) end
                local pressed = MonitorUtil.getPressedButton(allButtons, tx, ty)
                if pressed then
                    if pressed.action == "prev" then
                        currentPage = currentPage - 1
                        waiting = false
                    elseif pressed.action == "next" then
                        currentPage = currentPage + 1
                        waiting = false
                    elseif pressed.action == "back" then
                        return false
                    end
                end

            elseif event == "chat_signed" or event == "chat" then
                local msg = (rawEvent[3] or ""):match("^%s*(.-)%s*$") or ""
                local player = rawEvent[2]
                if event == "chat" and ChatUtil.isOwnEcho and ChatUtil.isOwnEcho(msg, player) then
                    -- own echo — skip
                else
                    local lower = string.lower(msg or "")
                    if lower == "y" or lower == "yes" then
                        return true
                    elseif lower == "n" or lower == "no" then
                        return false
                    else
                        ChatUtil.sendError("Expected Y or N. Please answer Y or N.")
                    end
                end
            end
        end
        -- If navigation (prev/next) occurred, redraw loop
    end
end

-- ==================== EDIT BY KEYS ====================

--- Edit specific sections of an existing config.
--- Shows current config, asks user which group (key) to replace,
--- runs scanDeviceType for that group, replaces only that group.
--- @param deviceTypes table array of device types (filtered by group)
--- @param mon table monitor
--- @param monSide string monitor side
--- @param configLabel string config name (e.g. "BeeOS")
--- @param existingConfig table existing config (result format: { key = value, ... })
--- @param onSave function(updatedConfig) callback on save
--- @return table|nil updated config, or nil on cancel
function ConfigWizard.editByKeys(deviceTypes, mon, monSide, configLabel, existingConfig, onSave)
    local w, h = mon.getSize()
    local globalAllDevices = {}

    -- Collect all known peripheral names from existing config
    for _, dt in ipairs(deviceTypes) do
        local val = existingConfig[dt.key]
        if type(val) == "string" and val ~= "" then
            table.insert(globalAllDevices, val)
        elseif type(val) == "table" then
            for _, v in ipairs(val) do
                if v ~= "" then
                    table.insert(globalAllDevices, v)
                end
            end
        end
    end

    MonitorUtil.clearScreen(mon)
    MonitorUtil.drawTitle(mon, "=== Edit " .. configLabel .. " ===", 2)
    MonitorUtil.drawText(mon, 2, 4, "Follow instructions in CHAT.", MonitorUtil.COLORS.highlight)
    MonitorUtil.drawText(mon, 2, 5, "All responses go through in-game chat.", MonitorUtil.COLORS.text)

    chatSeparator()
    chatHighlight("=== Editing " .. configLabel .. " ===")
    chatInfo("Follow chat instructions. Answer Y or N in game chat.")
    chatSeparator()
    chatInfo("HOW IT WORKS:")
    chatInfo("Scenario 1: Connect a NEW device (it appears in peripheral list)")
    chatInfo("Scenario 2: Disconnect and RECONNECT an already known device")
    chatInfo("Work with ONE device at a time. Multiple changes may confuse the scanner.")
    chatSeparator()
    os.sleep(1)

    local updatedConfig = {}
    for k, v in pairs(existingConfig) do
        updatedConfig[k] = v
    end

    local groupColors = { colors.orange, colors.green, colors.blue, colors.purple, colors.yellow, colors.cyan, colors.pink, colors.lightGray }

    local fullListShown = false

    local editing = true
    while editing do
        -- Show current config as interactive paginated view
        local currentItems = {}
        local idx = 0
        for _, dt in ipairs(deviceTypes) do
            idx = idx + 1
            local val = existingConfig[dt.key]
            table.insert(currentItems, {
                key = dt.label,
                value = val,
                color = groupColors[((idx - 1) % #groupColors) + 1],
            })
        end

        -- Prompt in chat BEFORE drawing page
        if not fullListShown then
            chatSeparator()
            chatHighlight("=== Current " .. configLabel .. " Config ===")
            for _, dt in ipairs(deviceTypes) do
                local val = existingConfig[dt.key]
                local display = type(val) == "table" and table.concat(val, ", ") or tostring(val)
                if display == "" then
                    display = ChatUtil.code("8") .. "<none>"
                else
                    display = ChatUtil.device(display)
                end
                chatInfo("  [" .. ChatUtil.device(dt.key) .. "] " .. ChatUtil.device(dt.label) .. " -> " .. display)
            end
            fullListShown = true
        end

        chatSeparator()
        chatQuestion("Enter device key to edit (e.g. 'tech_monitor'), or 'done' to finish:")

        local pageResult, capturedMsg = ConfigWizard.editPageLoop(mon, monSide, "=== " .. configLabel .. " Current ===", currentItems)

        if pageResult == "back" or pageResult == "timeout" then
            if pageResult == "back" then
                chatInfo("Edit cancelled by user.")
            else
                chatError("Timeout. Edit cancelled.")
            end
            return nil
        end

        local chosenKey = capturedMsg or ""

        local validKeys = {"done"}
        for _, dt in ipairs(deviceTypes) do
            table.insert(validKeys, dt.key)
        end

        local isValid = false
        for _, vk in ipairs(validKeys) do
            if vk == chosenKey then
                isValid = true
                break
            end
        end

        if not isValid then
            chatError("Invalid key: '" .. ChatUtil.device(chosenKey, ChatUtil.code("c")) .. "'. Valid keys: " .. deviceList(validKeys, ", "))
            os.sleep(1)
        else
            if chosenKey == "done" then
                editing = false
                break
            end

            local chosenType = nil
            for _, dt in ipairs(deviceTypes) do
                if dt.key == chosenKey then
                    chosenType = dt
                    break
                end
            end

            if not chosenType then
                chatError("Internal error: key " .. ChatUtil.device(chosenKey, ChatUtil.code("c")) .. " not found.")
                os.sleep(1)
            else
                chatSuccess("Editing section: " .. ChatUtil.device(chosenType.label))
                local found = ConfigWizard.scanDeviceType(chosenType, globalAllDevices)
                if #found > 0 then
                    if chosenType.max == 1 then
                        updatedConfig[chosenType.key] = found[1]
                    else
                        updatedConfig[chosenType.key] = found
                    end
                    chatSuccess("Section updated: " .. ChatUtil.device(chosenType.label))
                else
                    chatError("No devices found for " .. ChatUtil.device(chosenType.label, ChatUtil.code("c")) .. ". Keeping old value.")
                end

                -- Show updated list and wait for Y/N while allowing nav
                local updatedItems = {}
                local uidx = 1
                for _, dt in ipairs(deviceTypes) do
                    local val = updatedConfig[dt.key]
                    table.insert(updatedItems, {
                        key = dt.label,
                        value = val,
                        color = groupColors[((uidx - 1) % #groupColors) + 1],
                    })
                    uidx = uidx + 1
                end

                local again = ConfigWizard.waitYesNoNav(
                    mon, monSide,
                    "=== " .. configLabel .. " Updated ===",
                    updatedItems,
                    "Edit another section? (Y/N)",
                    120
                )
                if again == nil then
                    chatError("Timeout. Saving changes.")
                    editing = false
                elseif again == false then
                    editing = false
                end
            end
        end
    end

    -- === FINAL CONFIRMATION ===
    local summaryItems = {}
    local sidx = 1
    for _, dt in ipairs(deviceTypes) do
        local val = updatedConfig[dt.key]
        table.insert(summaryItems, {
            key = dt.label,
            value = val,
            color = groupColors[((sidx - 1) % #groupColors) + 1],
        })
        sidx = sidx + 1
    end

    chatSeparator()
    chatHighlight("=== " .. configLabel .. " edit complete ===")
    chatInfo("Check the summary on the monitor.")
    chatQuestion("Save changes? (Y/N)")

    local confirmed = ConfigWizard.waitYesNoNav(
        mon, monSide,
        "=== " .. configLabel .. " Summary ===",
        summaryItems,
        "Save changes? (Y/N)",
        120
    )
    if confirmed == nil then
        chatError("Timeout. Edit cancelled.")
        return nil
    elseif confirmed == false then
        chatError("Edit cancelled by user.")
        return nil
    end

    -- SAVE
    chatSeparator()
    chatSuccess(configLabel .. " configuration updated!")
    MonitorUtil.clearScreen(mon)
    MonitorUtil.drawTitle(mon, "=== Saving " .. configLabel .. " ===", 2)
    MonitorUtil.drawText(mon, 2, 4, "Configuration updated!", MonitorUtil.COLORS.success)

    if onSave then
        onSave(updatedConfig)
    end

    return updatedConfig
end

return ConfigWizard