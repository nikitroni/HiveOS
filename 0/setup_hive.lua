-- ==================================================
-- HIVE CONFIGURATOR (FULL VERSION)
-- ==================================================

local CONFIG_FILE = "hives.cfg"
local CHAT_PERIPHERAL = "chat_box_0" 

local hives_data = {} 
local current_hive_id = 1 
local mode = "idle" 
local running = true

local chat = peripheral.wrap(CHAT_PERIPHERAL)

-- Функция отправки сообщений (чат + терминал + задержка)
local function send(text)
    print("[LOG] " .. text)
    if chat then chat.sendMessage(text) end
    os.sleep(0.6) 
end

-- Показ доступных команд
local function showHelp()
    send("Commands:")
    send("- 'start hive': New config from Hive 1")
    send("- 'update hive': Update specific ID")
    send("- 'check': Diagnostic")
    send("- 'save': Save and exit")
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
    -- Сортируем таблицу по полю id перед сохранением
    table.sort(hives_data, function(a, b) return a.id < b.id end)
    
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize(hives_data))
    file.close()
    send("Config saved! Total hives: " .. #hives_data)
end

-- Проверка периферии
local function checkSystem()
    loadConfig()
    if #hives_data == 0 then
        send("System: Config is empty.")
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
    showHelp()
end

-- Скан новых блоков
local function scanLoop()
    local names = peripheral.getNames()
    local found_h, found_r = nil, nil

    for _, name in ipairs(names) do
        local used = false
        for _, hive in ipairs(hives_data) do
            if hive.hive_block == name or hive.reader_block == name then used = true end
        end

        if not used then
            local t = peripheral.getType(name)
            if t and string.find(t, "advanced_hive") then found_h = name
            elseif t and string.find(t, "block_reader") then found_r = name end
        end
    end

    if found_h and found_r then
        -- Проверяем, нет ли уже такого ID (при обновлении)
        for i, hive in ipairs(hives_data) do
            if hive.id == current_hive_id then
                table.remove(hives_data, i) -- Удаляем старую запись перед заменой
                break
            end
        end

        table.insert(hives_data, {
            id = current_hive_id,
            hive_block = found_h,
            reader_block = found_r
        })
        
        send("Success! Added HIVE " .. current_hive_id)
        
        -- Если мы просто создавали список, идем к следующему
        if mode == "creating" then
            current_hive_id = current_hive_id + 1
            send("Next: Connect Hive " .. current_hive_id)
        else
            -- Если мы обновляли один улей, выходим в режим ожидания
            mode = "idle"
            send("Update complete. Type 'save' or 'update hive' for more.")
        end
    end
end

-- ГЛАВНЫЙ ЦИКЛ
term.clear()
term.setCursorPos(1,1)
print("HIVE CONFIGURATOR v1.2")
checkSystem()

while running do
    local event, a1, a2, a3 = os.pullEvent()

    if event == "chat" then
        local msg = tostring(a2):lower()
        
        -- Команда START
        if msg == "start hive" then
            hives_data = {}
            current_hive_id = 1
            mode = "creating"
            send("MODE: NEW CONFIG. Connect Hive 1.")

        -- Команда UPDATE
        elseif msg == "update hive" then
            send("Which ID to update? Type 'hive [number]'")
            mode = "awaiting_id"

        -- Логика выбора ID для обновления
        elseif mode == "awaiting_id" and string.find(msg, "hive") then
            local id = tonumber(string.match(msg, "%d+"))
            if id then
                current_hive_id = id
                mode = "updating" -- Режим обновления ОДНОГО улья
                send("Ready to update Hive " .. id .. ". Connect modems.")
            else
                send("Error: Please specify ID (e.g. 'hive 2')")
            end

        -- Остальные команды
        elseif msg == "check" then
            checkSystem()
        elseif msg == "save" or msg == "stop" then
            saveConfig()
            running = false
        end
    end

    -- Запуск сканирования в режимах создания или обновления
    if mode == "creating" or mode == "updating" then
        scanLoop()
        os.startTimer(1)
    end
end