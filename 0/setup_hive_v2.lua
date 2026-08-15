-- ==================================================
-- HIVE CONFIGURATOR - WITH IGNORED READERS
-- ==================================================

local CONFIG_FILE = "hives.cfg"
local CHAT_PERIPHERAL = "chat_box_0"

-- ===== СПИСОК ИГНОРИРУЕМЫХ РИДЕРОВ =====
-- Добавьте сюда имена ридеров, которые НЕ должны участвовать в настройке ульев
local IGNORED_READERS = {
    "block_reader_19",
    "block_reader_20",
    "block_reader_21",
    -- добавьте свои
}

local hives_data = {}
local current_hive_id = 1
local mode = "idle"
local running = true

local chat = peripheral.wrap(CHAT_PERIPHERAL)

-- Функция отправки сообщений
local function send(text)
    print("[Hive] " .. text)
    if chat then
        chat.sendMessage("[Hive] " .. text)
    end
    os.sleep(0.1)
end

-- Показ доступных команд
local function showHelp()
    send("=== HIVE CONFIGURATOR ===")
    send("Available commands:")
    send("'start hive' - Create new configuration from Hive 1")
    send("'update hive N' - Update specific hive (e.g.: update hive 2)")
    send("'check' - System diagnostic")
    send("'list' - Show all configured hives")
    send("'save' - Save configuration and exit")
    send("'help' - Show this help message")
end

-- Загрузка файла
local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return false end
    local file = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()

    if type(data) == "table" then
        hives_data = data
        return true
    end
    return false
end

-- Сохранение с сортировкой по ID
local function saveConfig()
    table.sort(hives_data, function(a, b) return a.id < b.id end)

    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize(hives_data))
    file.close()
    send("Configuration saved! Total hives: " .. #hives_data)
    return true
end

-- Проверка системы
local function checkSystem()
    if #hives_data == 0 then
        send("System: Configuration is empty.")
    else
        local all_ok = true
        for _, hive in ipairs(hives_data) do
            if not peripheral.isPresent(hive.hive_block) or not peripheral.isPresent(hive.reader_block) then
                send("OFFLINE: Hive " .. hive.id)
                all_ok = false
            end
        end
        if all_ok then send("SYSTEM OK. All hives online.") end
    end
end

-- Список ульев
local function listHives()
    if #hives_data == 0 then
        send("No hives configured.")
        return
    end

    send("=== CONFIGURED HIVES ===")
    for _, hive in ipairs(hives_data) do
        local hive_status = peripheral.isPresent(hive.hive_block) and "ONLINE" or "OFFLINE"
        local reader_status = peripheral.isPresent(hive.reader_block) and "ONLINE" or "OFFLINE"
        send("Hive " .. hive.id .. ": " .. hive_status .. " " .. hive.hive_block .. " + " .. reader_status .. " " .. hive.reader_block)
    end
end

-- Проверка, игнорируется ли ридер
local function isReaderIgnored(name)
    for _, ignored in ipairs(IGNORED_READERS) do
        if name == ignored then
            return true
        end
    end
    return false
end

-- Скан новых блоков (с учётом игнорируемых ридеров)
local function scanLoop()
    local names = peripheral.getNames()
    local found_h, found_r = nil, nil

    for _, name in ipairs(names) do
        -- Пропускаем уже используемые устройства
        local used = false
        for _, hive in ipairs(hives_data) do
            if hive.hive_block == name or hive.reader_block == name then
                used = true
                break
            end
        end
        if used then goto continue end

        -- Проверяем тип
        local t = peripheral.getType(name)
        if t and string.find(t, "advanced_hive") then
            found_h = name
        elseif t and string.find(t, "block_reader") then
            -- Если ридер в игнорируемом списке, пропускаем его
            if not isReaderIgnored(name) then
                found_r = name
            end
        end

        ::continue::
    end

    if found_h and found_r then
        -- Удаляем старую запись с таким же ID (при обновлении)
        for i, hive in ipairs(hives_data) do
            if hive.id == current_hive_id then
                table.remove(hives_data, i)
                break
            end
        end

        table.insert(hives_data, {
            id = current_hive_id,
            hive_block = found_h,
            reader_block = found_r
        })

        send("Hive " .. current_hive_id .. " configured: " .. found_h .. " + " .. found_r)

        if mode == "creating" then
            current_hive_id = current_hive_id + 1
            send("Connect Hive " .. current_hive_id .. " or type 'save'")
        else
            mode = "idle"
            send("Update complete! Type 'save' to save changes.")
        end

        return true
    end

    return false
end

-- ГЛАВНЫЙ ЦИКЛ
term.clear()
term.setCursorPos(1,1)
print("=== HIVE CONFIGURATOR ===")
loadConfig()
showHelp()

os.startTimer(1)

while running do
    local event, a1, a2, a3 = os.pullEvent()

    if event == "chat" then
        local msg = tostring(a2):lower()

        if msg == "start hive" then
            hives_data = {}
            current_hive_id = 1
            mode = "creating"
            send("Creating new configuration. Connect Hive 1...")
            scanLoop()

        elseif msg == "update hive" then
            send("Which hive to update? Type 'update hive [number]'")

        elseif string.find(msg, "update hive") then
            local id = tonumber(string.match(msg, "%d+"))
            if id then
                current_hive_id = id
                mode = "updating"
                send("Ready to update Hive " .. id .. ". Disconnect old devices and connect new ones.")
                scanLoop()
            else
                send("Please specify ID (e.g. 'update hive 2')")
            end

        elseif msg == "check" then
            checkSystem()
        elseif msg == "list" then
            listHives()
        elseif msg == "save" then
            if saveConfig() then
                running = false
            end
        elseif msg == "help" then
            showHelp()
        end

    elseif event == "peripheral" then
        if mode == "creating" or mode == "updating" then
            os.sleep(0.5)
            scanLoop()
        end

    elseif event == "timer" then
        if mode == "creating" then
            scanLoop()
        end
        os.startTimer(1)
    end
end

send("Program stopped.")