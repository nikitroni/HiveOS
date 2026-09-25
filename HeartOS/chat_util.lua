-- chat_util.lua
-- Module for sending chat messages via chat_box peripheral
-- and receiving chat messages via "chat" / "chat_signed" events.
-- Used for interactive communication with the player.

local ChatUtil = {}

-- Diagnostic logger (logs/error.log) — used to trace which send branch runs.
local LogUtil = require("log_util")

-- Reference to the wrapped chat_box
--- @type table
local chatBox
-- Name of the chat_box peripheral
local chatBoxName = nil
-- Player name under which chat_box sends messages (for echo filtering)
local chatBoxPlayerName = nil
-- Last sent message (for echo filtering)
local lastSentMessage = nil
-- Send format detected for the connected chat box:
--   "new"    = AP 0.8+: sendMessage(text, {prefix=...})            (options map)
--   "legacy" = AP 0.7/1.21: sendMessage(text, prefix, brackets, color, range, utf8)
--   "plain"  = 1-arg sendMessage(text) (last resort)
-- nil until the first successful send chooses a format.
local sendFormat = nil

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

-- MOTD color codes (project color scheme).
-- The section sign is built in code as its real UTF-8 two bytes "\194\167" (U+00A7).
-- This is byte-for-byte identical to the literal "§" used in the working in-game
-- test script (color_test.lua) — the Chat Box parses MOTD codes only as UTF-8 "§".
-- A single byte "\167" (0xA7) is NOT valid UTF-8 and shows as an unrecognized
-- character instead of a color code.
-- Writing "\194\167" (not a raw "§") keeps the file pure ASCII: an editor saving
-- it as cp1251 would otherwise produce a lone 0xA7 (the exact bug we avoided).
local SECTION_SIGN = "\194\167"
local MOTD = {
    white = SECTION_SIGN .. "f",      -- plain text
    green = SECTION_SIGN .. "a",      -- peripherals, blocks, deviceType names
    red = SECTION_SIGN .. "c",        -- errors, Failed, not added, cancelled
    darkGreen = SECTION_SIGN .. "2",  -- titles, highlights (chatHighlight)
    cyan = SECTION_SIGN .. "b",       -- Y/N answers and user questions
    yellow = SECTION_SIGN .. "e",     -- warnings (overwrite/destructive notices)
}

--- Build a MOTD color code by its letter (e.g. code("c") -> "§c").
--- @param letter string one of f,a,c,2,b,...
--- @return string
function ChatUtil.code(letter)
    return SECTION_SIGN .. tostring(letter)
end

-- Terminal tag displayed in brackets before each message.
-- Passed as the `prefix` argument of chatBox.sendMessage() so the box shows
-- "[HeartOS] message". Also matched by isOwnEcho for echo filtering.
local CHATBOX_TAG = "[HeartOS]"
local TERMINAL_TAG = "HeartOS"

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
            LogUtil.warn("ChatUtil.init: wrapped named peripheral '" .. chatBoxName .. "', player='" .. (chatBoxPlayerName or "?") .. "'")
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
                    LogUtil.warn("ChatUtil.init: wrapped '" .. chatBoxName .. "' (methods: " .. table.concat(methods, ",") .. ")")
                    return true
                end
            end
        end
    end

    LogUtil.warn("ChatUtil.init: NO peripheral with sendMessage found. Names: " .. table.concat(allNames, ","))
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

local sendImpl  -- forward declaration; the real definition is below

--- Send a raw message to chat (with the standard SEND_DELAY pause).
--- @param message string Message text
--- @return boolean true if sent successfully
function ChatUtil.send(message)
    return sendImpl(message, true)
end

--- Send a raw message to chat WITHOUT the blocking os.sleep pause.
--- Use only from within event loops / handlers: a sleep there would swallow
--- in-flight events (e.g. the relay phase timers of the hive signal cycle).
--- @param message string Message text
--- @return boolean true if sent successfully
function ChatUtil.sendImmediate(message)
    return sendImpl(message, false)
end

--- Internal send implementation.
--- @param message string Message text
--- @param withDelay boolean whether to os.sleep(SEND_DELAY) after sending
--- @return boolean true if sent successfully
sendImpl = function(message, withDelay)
    if not chatBox then
        return false
    end

    -- The Chat Box API changed between AP versions (ATM10 ships 0.8+):
    --   - Legacy (works in older AP): sendMessage(text, "HeartOS", nil, nil, nil, true)
    --   - New (AP 0.8+): the 2nd argument must be an OPTIONS TABLE:
    --       sendMessage(text, { prefix = "HeartOS", brackets = "[]" })
    --   Passing a string as 2nd arg in the new API throws:
    --     "bad argument #2 (map expected, got string)"
    --   and then the 1-arg fallback silently drops prefix + MOTD colors —
    --   exactly the reported bug (no [HeartOS] tag, literal § symbol).
    -- We auto-detect the format on the first successful send and reuse it.
    local sendOk = false
    local sendErr = nil

    if sendFormat == "legacy" then
        sendOk, sendErr = pcall(function()
            chatBox.sendMessage(message, TERMINAL_TAG, nil, nil, nil, true)
        end)
    elseif sendFormat == "plain" then
        sendOk, sendErr = pcall(function()
            chatBox.sendMessage(message)
        end)
    else
        -- Not detected yet or using the new options-table format.
        -- Try the NEW (AP 0.8+) signature first:
        --   sendMessage(text, { prefix = ..., utf8 = ... })
        -- The box renders "[prefix] text"; brackets default to "[]".
        -- NOTE: utf8 = true is REQUIRED — it converts the § bytes (C2 A7) we
        -- embed into a proper UTF-8 char so the client renders MOTD colors.
        local okNew, errNew = pcall(function()
            chatBox.sendMessage(message, { prefix = TERMINAL_TAG, utf8 = true })
        end)
        if okNew then
            if sendFormat == nil then
                sendFormat = "new"
                LogUtil.warn("ChatUtil.send: detected NEW chart box API (options map). Prefix: [" .. TERMINAL_TAG .. "]")
            end
            sendOk, sendErr = true, nil
        elseif sendFormat == "new" then
            sendOk, sendErr = false, errNew
        else
            -- New-format call failed (API might still be legacy). Try legacy 6-arg.
            local okLegacy, errLegacy = pcall(function()
                chatBox.sendMessage(message, TERMINAL_TAG, nil, nil, nil, true)
            end)
            if okLegacy then
                sendFormat = "legacy"
                LogUtil.warn("ChatUtil.send: detected LEGACY chart box API (positional prefix).")
                sendOk, sendErr = true, nil
            else
                -- Last-resort: plain 1-arg call (no prefix, no MOTD).
                sendFormat = "plain"
                LogUtil.warn("ChatUtil.send: both new and legacy signatures FAILED, using 1-arg fallback. Errors: "
                    .. tostring(errNew) .. " | " .. tostring(errLegacy))
                sendOk, sendErr = pcall(function()
                    chatBox.sendMessage(message)
                end)
            end
        end
    end

    if not sendOk then
        -- Keep logging the error so a broken chat box remains visible.
        LogUtil.warn("ChatUtil.send: send FAILED: " .. tostring(sendErr))
        return false
    end

    -- Remember last sent message to filter echo
    lastSentMessage = message

    -- Pause after sending so Minecraft client can display the message.
    -- Without delay, messages sent in rapid succession may be lost.
    -- Skipped by sendImmediate() so event handlers stay non-blocking.
    if withDelay then
        os.sleep(SEND_DELAY)
    end

    return true
end

--- Strip MOTD color codes (§ + 1 char) from a string.
--- Handles both encodings of the section sign:
---   UTF-8 "§" (\194\167) as produced by the MOTD table
---   and single-byte 0xA7 (legacy "\167" form).
--- @param s string
--- @return string|nil
local function stripMOTD(s)
    if not s then return s end
    s = s:gsub("\194\167.", "")
    s = s:gsub("\167.", "")
    return s
end

--- Send an info message (white text)
function ChatUtil.sendInfo(message)
    return ChatUtil.send(MOTD.white .. PREFIXES.info .. message)
end

--- Send an info message WITHOUT the blocking pause (event-loop safe).
--- @param message string
function ChatUtil.sendInfoImmediate(message)
    return sendImpl(MOTD.white .. PREFIXES.info .. message, false)
end

--- Send a success message (green text)
function ChatUtil.sendSuccess(message)
    return ChatUtil.send(MOTD.green .. PREFIXES.success .. message)
end

--- Send a success message WITHOUT the blocking pause (event-loop safe).
--- @param message string
function ChatUtil.sendSuccessImmediate(message)
    return sendImpl(MOTD.green .. PREFIXES.success .. message, false)
end

--- Send an error message (red text)
function ChatUtil.sendError(message)
    return ChatUtil.send(MOTD.red .. PREFIXES.error .. message)
end

--- Send an error message WITHOUT the blocking pause (event-loop safe).
--- @param message string
function ChatUtil.sendErrorImmediate(message)
    return sendImpl(MOTD.red .. PREFIXES.error .. message, false)
end

--- Send a warning message (yellow text) -- used for destructive/overwrite notices.
function ChatUtil.sendWarning(message)
    return ChatUtil.send(MOTD.yellow .. "[!] " .. message)
end

--- Send a step instruction message (cyan text — user prompt)
function ChatUtil.sendStep(message)
    return ChatUtil.send(MOTD.cyan .. PREFIXES.step .. message)
end

--- Send a highlighted message (dark green — titles/highlights)
function ChatUtil.sendHighlight(message)
    return ChatUtil.send(MOTD.darkGreen .. PREFIXES.highlight .. message)
end

--- Send a question/prompt to the user (cyan text)
function ChatUtil.sendQuestion(message)
    return ChatUtil.send(MOTD.cyan .. message)
end

--- Wrap a device/peripheral/block name in green (§a).
--- After the name the color resets to `resetColor` (default: white).
--- @param name string
--- @param resetColor string|nil MOTD code to restore after the name
--- @return string
function ChatUtil.device(name, resetColor)
    return MOTD.green .. tostring(name) .. (resetColor or MOTD.white)
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

    -- Normalize message: strip leading bracket tag (e.g. "[HeartOS]" or "[AP]").
    local normalized = message
    normalized = normalized:gsub("^%[[^%]]+%]%s*", "")
    normalized = normalized:match("^%s*(.-)%s*$")  -- trim
    -- Also drop the terminal tag token when the box shows "[AP] HeartOS ...".
    local tagLower = TERMINAL_TAG:lower()
    if normalized:lower():sub(1, #tagLower) == tagLower then
        normalized = normalized:sub(#tagLower + 1)
        normalized = normalized:match("^%s*(.-)%s*$")
    end

    -- Plain text without MOTD color codes (echo may keep or strip them)
    local plain = stripMOTD(normalized)

    -- If message exactly matches our last sent message — it's echo
    if lastSentMessage and (stripMOTD(message) == stripMOTD(lastSentMessage) or plain == stripMOTD(lastSentMessage)) then
        return true
    end

    -- If message starts with one of our prefixes — it's echo
    for _, prefix in ipairs({PREFIXES.info, PREFIXES.success, PREFIXES.error, PREFIXES.step, PREFIXES.highlight}) do
        if plain:sub(1, #prefix) == prefix then
            return true
        end
    end
    -- Separately: separator line of dashes.
    -- NOTE: after stripping [AP] prefix, the remaining dashes may be short.
    -- Any string consisting ONLY of dashes is considered echo.
    if stripMOTD(message):match("^-+$") and #message >= 3 then
        return true
    end
    if plain:match("^-+$") and #plain >= 3 then
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
            local message, player
            if event == "chat" then
                player, message = ChatUtil.extractChat(eventData)
            else
                player, message = eventData[2], eventData[3]
            end
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
---
--- IMPORTANT (AP 0.8+): the chat_box now queues events in a NEW layout:
---   old: chat, playerName, message,        uuid,    hidden,  byteString
---   new: chat, senderId,    playerName, message,  hidden,  byteString
--- So the message index shifted from 3 to 4, and player name from 2 to 3.
--- We detect the layout by checking whether arg[3] looks like a player name.
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
            local player, message = ChatUtil.extractChat(eventData)
            if message and message ~= "" and not isOwnEcho(message, player) then
                return message, player
            end
        end
    end
end

--- Extract (player, message) from a "chat" event.
--- Handles both AP chat_box event layouts:
---   legacy (AP <0.8): chat, playerName, message, uuid,  hidden, bs
---   new    (AP 0.8+): chat, senderId,  playerName, message, hidden, bs
--- Discriminators:
---   - senderId (new, index 2) is a UUID string or nil.
---   - In the legacy layout index 2 is a plain player name.
--- @param eventData table raw event arguments (event at index 1)
--- @return string|nil player
--- @return string|nil message
function ChatUtil.extractChat(eventData)
    local senderId = eventData[2]
    local playerName = eventData[3]
    local message = eventData[4]

    -- New AP 0.8+ layout (senderId first). UUID format: 8-4-4-4-12 hex.
    if type(senderId) == "string" and senderId:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
        return playerName, message
    end
    -- New layout without senderId (chat_box-generated, senderId = nil).
    if senderId == nil and type(playerName) == "string" and type(message) == "string" then
        return playerName, message
    end

    -- Legacy layout: chat, playerName, message, ...
    return eventData[2], eventData[3]
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
            local player, message = ChatUtil.extractChat(eventData)
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