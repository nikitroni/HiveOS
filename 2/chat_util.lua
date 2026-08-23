-- chat_util.lua
-- Module for sending chat messages via chat_box peripheral
-- and receiving chat messages via "chat" / "chat_signed" events.
-- Used for interactive communication with the player.

local ChatUtil = {}

-- Reference to the wrapped chat_box
local chatBox = nil
-- Name of the chat_box peripheral
local chatBoxName = nil
-- Player name under which chat_box sends messages (for echo filtering)
local chatBoxPlayerName = nil
-- Last sent message (for echo filtering)
local lastSentMessage = nil

-- Delay between messages in seconds.
-- Minecraft client needs time to display messages from chat_box.
-- Without delay, messages sent in rapid succession may be lost.
local SEND_DELAY = 0.25

-- Prefixes for different message types
local PREFIXES = {
    info = "[INFO] ",
    success = "[OK] ",
    error = "[ERROR] ",
    step = ">>> ",
    highlight = "** ",
}

-- Prefix that chat_box adds to its own messages (echo)
local CHATBOX_TAG = "[AP]"

--- Try to get the player name under which chat_box operates.
--- HyperBox ChatBox: getName() / getOwner() / getPlayerName()
local function tryGetChatBoxPlayerName(box)
    local candidates = {"getName", "getOwner", "getPlayerName", "getUsername"}
    for _, method in ipairs(candidates) do
        if type(box[method]) == "function" then
            local ok, result = pcall(function()
                return box[method]()
            end)
            if ok and type(result) == "string" and result ~= "" then
                return result
            end
        end
    end
    return nil
end

--- Initialize the module. Look for chat_box by name or find the first available.
--- @param name string|nil Name of chat_box peripheral (e.g. "chat_box_0"). If nil, search for any.
--- @return boolean true if chat_box found and connected
function ChatUtil.init(name)
    if name and name ~= "" then
        chatBox = peripheral.wrap(name)
        if chatBox then
            chatBoxName = name
            chatBoxPlayerName = tryGetChatBoxPlayerName(chatBox)
            return true
        end
    end

    -- Search for any chat_box by checking for sendMessage method
    local allNames = peripheral.getNames()
    for _, pName in ipairs(allNames) do
        local methods = peripheral.getMethods(pName)
        for _, method in ipairs(methods) do
            if method == "sendMessage" then
                local wrapped = peripheral.wrap(pName)
                if wrapped then
                    chatBox = wrapped
                    chatBoxName = pName
                    chatBoxPlayerName = tryGetChatBoxPlayerName(chatBox)
                    return true
                end
            end
        end
    end

    return false
end

--- Check if chat_box is available
--- @return boolean
function ChatUtil.isAvailable()
    return chatBox ~= nil
end

--- Get the name of the connected chat_box
--- @return string|nil
function ChatUtil.getDeviceName()
    return chatBoxName
end

--- Send a raw message to chat
--- @param message string Message text
--- @return boolean true if sent successfully
function ChatUtil.send(message)
    if not chatBox then
        return false
    end

    local success, err = pcall(function()
        if chatBox.sendMessage then
            chatBox.sendMessage(message)
        elseif chatBox.send then
            chatBox.send(message)
        elseif chatBox.say then
            chatBox.say(message)
        elseif chatBox.print then
            chatBox.print(message)
        else
            return false, "No send method found"
        end
    end)

    -- Remember last sent message to filter echo
    if success then
        lastSentMessage = message
    end

    -- Pause after sending so Minecraft client can display the message.
    -- Without delay, messages sent in rapid succession may be lost.
    os.sleep(SEND_DELAY)

    return success
end

--- Send an info message (white text)
function ChatUtil.sendInfo(message)
    return ChatUtil.send(PREFIXES.info .. message)
end

--- Send a success message (green text)
function ChatUtil.sendSuccess(message)
    return ChatUtil.send(PREFIXES.success .. message)
end

--- Send an error message (red text)
function ChatUtil.sendError(message)
    return ChatUtil.send(PREFIXES.error .. message)
end

--- Send a step instruction message (highlighted text)
function ChatUtil.sendStep(message)
    return ChatUtil.send(PREFIXES.step .. message)
end

--- Send a highlighted message (bold marker)
function ChatUtil.sendHighlight(message)
    return ChatUtil.send(PREFIXES.highlight .. message)
end

--- Send a separator (empty line with dashes)
function ChatUtil.sendSeparator()
    return ChatUtil.send("----------------------------------------")
end

--- Send a multi-line message (each line separately)
function ChatUtil.sendMultiline(lines)
    for _, line in ipairs(lines) do
        ChatUtil.send(line)
    end
end

-- ==================== CHAT RECEIVE ====================

--- Check if the message is an echo of our own chat_box (hearing ourselves)
--- @param message string message
--- @param player string|nil sender
--- @return boolean
local function isOwnEcho(message, player)
    if not message or message == "" then
        return true
    end

    -- Normalize message: remove [AP] prefix if present
    local normalized = message
    if normalized:sub(1, #CHATBOX_TAG) == CHATBOX_TAG then
        normalized = normalized:sub(#CHATBOX_TAG + 2)  -- +2 for space after tag
    end
    normalized = normalized:match("^%s*(.-)%s*$")  -- trim

    -- If message exactly matches our last sent message — it's echo
    if lastSentMessage and (message == lastSentMessage or normalized == lastSentMessage) then
        return true
    end

    -- If message starts with one of our prefixes — it's echo
    for _, prefix in ipairs({PREFIXES.info, PREFIXES.success, PREFIXES.error, PREFIXES.step, PREFIXES.highlight}) do
        if normalized:sub(1, #prefix) == prefix then
            return true
        end
        -- Also check with [AP] prefix
        if message:sub(1, #CHATBOX_TAG + #prefix + 1) == CHATBOX_TAG .. " " .. prefix then
            return true
        end
    end
    -- Separately: separator line of dashes.
    -- NOTE: after stripping [AP] prefix, the remaining dashes may be short.
    -- Any string consisting ONLY of dashes is considered echo.
    if message:match("^-+$") and #message >= 3 then
        return true
    end
    if normalized:match("^-+$") and #normalized >= 3 then
        return true
    end

    -- Message sent by someone else (not echo)
    return false
end

-- Export isOwnEcho for external use (e.g. config_wizard non-blocking skip check)
ChatUtil.isOwnEcho = isOwnEcho

--- Flush accumulated echo events after sending.
--- Called before waiting for player response to avoid catching own echo.
local function flushEchoEvents()
    -- Wait a bit for echo to arrive
    os.sleep(0.3)
    -- Flush all accumulated chat/chat_signed events that are echo
    local flushed = 0
    while true do
        local eventData = {os.pullEventRaw(0.05)}
        if not eventData[1] then
            break  -- timeout — no more events
        end
        local event = eventData[1]
        if event == "chat" or event == "chat_signed" then
            local message = eventData[2]
            local player = eventData[3]
            if isOwnEcho(message, player) then
                flushed = flushed + 1
                -- Ignore — this is echo
            else
                -- This is not echo, shouldn't have received it, but can't return it.
                -- CC:Tweaked has no way to return an event, so just ignore.
                -- In practice this shouldn't happen since flush is called before waiting.
            end
        end
    end
end

--- Drain: flush all accumulated events from the queue.
--- Wait for a 0.2s timer, ignoring all intermediate events.
--- Echo from chat_box arrives within ~0.15s — 0.2s is enough.
local function drainEvents()
    local drainId = os.startTimer(0.2)
    while true do
        local e = {os.pullEventRaw()}
        if e[1] == "timer" and e[2] == drainId then
            break
        end
        -- All other events (chat, chat_signed, etc.) are ignored
    end
end

--- Wait for a chat response from the player.
--- Filtering rules:
---   - chat_signed: generated ONLY by real players.
---     chat_box does NOT generate chat_signed events — no echo filter needed.
---   - chat: can be from player or chat_box (echo).
---     In ATM10 CC:Tweaked, eventData[2] = player name, eventData[3] = message.
---     Filter via isOwnEcho.
--- Before waiting, drain 0.7s to flush
--- all accumulated events (echo from chat_box).
--- @param timeout number|nil max wait time in seconds (nil = infinite)
--- @return string|nil, string|nil message text, player name; nil if timeout
function ChatUtil.waitForChat(timeout)
    -- Force drain queue — 0.7s ignore all events
    drainEvents()

    -- Main loop waiting for player response
    local timerId = nil
    if timeout then
        timerId = os.startTimer(timeout)
    end

    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]

        if event == "timer" and timerId and eventData[2] == timerId then
            return nil
        end

        if event == "chat_signed" then
            -- chat_signed: eventData[2] = player name, eventData[3] = message (CC:Tweaked 1.112+)
            local player = eventData[2]
            local message = eventData[3]
            if message and message ~= "" then
                return message, player
            end
        elseif event == "chat" then
            -- chat: eventData[2] = player name, eventData[3] = message (ATM10 CC:Tweaked)
            local player = eventData[2]
            local message = eventData[3]
            if message and message ~= "" and not isOwnEcho(message, player) then
                return message, player
            end
        end
    end
end

--- Trim whitespace from both ends of a string
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Wait for Y/N response from chat. Accepts "y", "yes", "n", "no" in any case.
--- @param timeout number|nil timeout
--- @return boolean|nil true=Y, false=N, nil=timeout
function ChatUtil.waitForYesNo(timeout)
    while true do
        local msg = ChatUtil.waitForChat(timeout)
        if msg == nil then
            return nil  -- timeout
        end

        local lower = trim(msg):lower()
        if lower == "y" or lower == "yes" then
            return true
        elseif lower == "n" or lower == "no" then
            return false
        else
            ChatUtil.sendError("Expected Y or N. Please answer Y or N.")
        end
    end
end

--- Wait for ANY chat message (including empty) with timeout.
--- Unlike waitForChat, preserves the drain/filter loop
--- but has a configurable timeout and does not reject any input.
--- @param timeout number|nil timeout in seconds
--- @return string|nil message text, or nil on timeout
function ChatUtil.waitForAnyMessage(timeout)
    drainEvents()

    local timerId = nil
    if timeout then
        timerId = os.startTimer(timeout)
    end

    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]

        if event == "timer" and timerId and eventData[2] == timerId then
            return nil
        end

        if event == "chat_signed" then
            local player = eventData[2]
            local message = eventData[3]
            if message and message ~= "" then
                return message
            end
        elseif event == "chat" then
            local player = eventData[2]
            local message = eventData[3]
            if message and message ~= "" and not isOwnEcho(message, player) then
                return message
            end
        end
    end
end

--- Wait for a chat response that matches one of the expected options.
--- @param expected table array of strings (lowercase)
--- @param timeout number|nil timeout
--- @return string|nil selected option (in original case) or nil
function ChatUtil.waitForChoice(expected, timeout)
    -- Convert expected to lowercase for comparison
    local expectedLower = {}
    for _, v in ipairs(expected) do
        expectedLower[v:lower()] = v
    end

    while true do
        local msg = ChatUtil.waitForChat(timeout)
        if msg == nil then
            return nil
        end

        local lower = trim(msg):lower()
        if expectedLower[lower] then
            return expectedLower[lower]
        else
            ChatUtil.sendError("Invalid input. Expected: " .. table.concat(expected, ", "))
        end
    end
end

--- Drain all accumulated events from the queue (0.2s timer).
--- Exported for external use: call BEFORE entering a raw pullEventRaw loop
--- that also listens for monitor touches, so accumulated chat_box echo
--- events do not instantly trigger an unexpected branch.
function ChatUtil.drainQueue()
    drainEvents()
end

-- ==================== MONITOR INTEGRATION ====================

local monRef = nil

--- Set a monitor for duplicating messages
function ChatUtil.setMonitor(mon)
    monRef = mon
end

--- Send a message to both chat and monitor (if set)
function ChatUtil.sendBoth(mon, message, color)
    ChatUtil.send(message)
    if monRef then
        monRef.setCursorPos(1, monRef.getCursorPos())
        monRef.setTextColor(color or colors.white)
        monRef.write(message)
    end
end

return ChatUtil