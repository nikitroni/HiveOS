-- chat_notify.lua
-- Отправка сообщений в чат-бокс для BeeOS, по образцу HeartOS chat_util.lua:
--   - MOTD-цвета через UTF-8 section sign (C2 A7 = real "§")
--   - префикс "[BeeOS]" через опции sendMessage { prefix = "BeeOS", utf8 = true }
--     (новый AP 0.8+), с автодетектом формата (new/legacy/plain).
--   - sendError -> красный, sendInfo -> белый, sendSuccess -> зелёный.

local ChatNotify = {}

-- UTF-8 section sign (byte sequence C2 A7), идентично chat_util.lua
local SECTION_SIGN = "\194\167"
local MOTD = {
    white  = SECTION_SIGN .. "f",
    green  = SECTION_SIGN .. "a",
    red    = SECTION_SIGN .. "c",
    cyan   = SECTION_SIGN .. "b",
    darkGreen = SECTION_SIGN .. "2",
}

-- Терминальный тег в скобках перед сообщением: "[BeeOS] сообщение"
local TERMINAL_TAG = "BeeOS"

local chatBox = nil
local sendFormat = nil

--- Найти и обернуть чат-бокс (по имени из beeos_config или поиском).
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

    -- Поиск любого периферийского с sendMessage
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

--- Внутренняя отправка с автодетектом формата API чат-бокса.
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
        -- Пробуем новый формат (AP 0.8+): options-map с prefix и utf8.
        -- prefixColor поддерживается не всеми сборками - при неудаче пробуем без него.
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

--- Белый информационный текст
function ChatNotify.sendInfo(message)
    send(MOTD.white .. message)
end

--- Зелёный текст успеха
function ChatNotify.sendSuccess(message)
    send(MOTD.green .. message)
end

--- Красный текст ошибки
function ChatNotify.sendError(message)
    send(MOTD.red .. message)
end

return ChatNotify