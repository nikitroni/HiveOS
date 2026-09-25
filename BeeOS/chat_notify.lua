-- chat_notify.lua
-- Send messages to the chat box for BeeOS, following HeartOS chat_util.lua:
--   - MOTD colors via UTF-8 section sign (C2 A7 = real "§")
--   - prefix "[BeeOS]" via sendMessage options { prefix = "BeeOS", utf8 = true }
--     (new AP 0.8+), with format autodetection (new/legacy/plain).
--   - sendError -> red, sendInfo -> white, sendSuccess -> green.

local ChatNotify = {}

-- UTF-8 section sign (byte sequence C2 A7), identical to chat_util.lua
local SECTION_SIGN = "\194\167"
local MOTD = {
    white  = SECTION_SIGN .. "f",
    green  = SECTION_SIGN .. "a",
    red    = SECTION_SIGN .. "c",
    cyan   = SECTION_SIGN .. "b",
    darkGreen = SECTION_SIGN .. "2",
}

-- Terminal tag in brackets before the message: "[BeeOS] message"
local TERMINAL_TAG = "BeeOS"

--- @type table
local chatBox
local sendFormat = nil

--- Find and wrap the chat box (by name from beeos_config or by search).
--- @return boolean
function ChatNotify.init()
    local cfg = nil
    if fs.exists("beeos_config.lua") then
        local handler = loadfile("beeos_config.lua")
        if handler then
            local ok, res = pcall(handler)
            if ok and type(res) == "table" then cfg = res end
        end
    end

    local chatName = cfg and cfg.peripherals and cfg.peripherals.chat_box
    if type(chatName) ~= "string" or chatName == "" then
        chatName = "chat_box_0"
    end

    local wrapped = peripheral.wrap(chatName)
    if wrapped then
        chatBox = wrapped
        return true
    end

    -- Search for any peripheral with sendMessage
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name)
        for _, m in ipairs(methods or {}) do
            if m == "sendMessage" then
                chatBox = peripheral.wrap(name)
                return true
            end
        end
    end
    return false
end

--- Internal send with autodetection of the chat box API format.
local function send(message)
    if not chatBox then
        if not ChatNotify.init() then return false end
    end

    if sendFormat == "legacy" then
        return pcall(function()
            chatBox.sendMessage(message, TERMINAL_TAG, nil, nil, nil, true)
        end)
    elseif sendFormat == "plain" then
        return pcall(function()
            chatBox.sendMessage(message)
        end)
    else
        -- Try the new format (AP 0.8+): options-map with prefix and utf8.
        -- prefixColor is not supported by all builds - on failure try without it.
        local okNew, errNew = pcall(function()
            chatBox.sendMessage(message, { prefix = TERMINAL_TAG, prefixColor = "yellow", utf8 = true })
        end)
        if not okNew then
            okNew, errNew = pcall(function()
                chatBox.sendMessage(message, { prefix = TERMINAL_TAG, utf8 = true })
            end)
        end
        if okNew then
            sendFormat = "new"
            return true
        end
        -- legacy 6-arg
        local okLegacy, errLegacy = pcall(function()
            chatBox.sendMessage(message, TERMINAL_TAG, nil, nil, nil, true)
        end)
        if okLegacy then
            sendFormat = "legacy"
            return true
        end
        -- plain
        sendFormat = "plain"
        return pcall(function()
            chatBox.sendMessage(message)
        end)
    end
end

--- White informational text
function ChatNotify.sendInfo(message)
    send(MOTD.white .. message)
end

--- Green success text
function ChatNotify.sendSuccess(message)
    send(MOTD.green .. message)
end

--- Red error text
function ChatNotify.sendError(message)
    send(MOTD.red .. message)
end

return ChatNotify