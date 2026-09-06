-- config_manager.lua
-- Модуль управления конфигами: сохранение, загрузка, валидация, rednet-протокол
-- Используется HeartOS для управления конфигами BeeOS и LabOS
--
-- ВНИМАНИЕ: типы устройств живут в device_types.lua (единый источник правды).
-- Список устройств для создания конфига берётся оттуда по group.
-- Конфиг содержит ТОЛЬКО периферию (имена блоков). Все остальные настройки
-- (слоты, координаты, логика) — жёстко зашиты в самих скриптах BeeOS/LabOS.

local ChatUtil = require("chat_util")

local ConfigManager = {}

-- ==================== CORE FUNCTIONS ====================

--- Сохранить таблицу в файл как Lua-скрипт с return
--- @param data table
--- @param filePath string
--- @return boolean, string
function ConfigManager.saveToFile(data, filePath)
    local path = fs.combine(shell.dir(), filePath)
    local file = fs.open(path, "w")
    if not file then
        return false, "Cannot open file for writing: " .. path
    end
    file.write("return " .. textutils.serialize(data))
    file.close()
    return true, path
end

--- Загрузить таблицу из файла (выполняет как Lua-скрипт)
--- @param filePath string
--- @return table|nil, string|nil
function ConfigManager.loadFromFile(filePath)
    local path = fs.combine(shell.dir(), filePath)
    if not fs.exists(path) then
        return nil, "File not found: " .. path
    end
    local fn, err = loadfile(path)
    if not fn then
        return nil, "Invalid config format in " .. path .. ": " .. tostring(err)
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "table" then
        return result, nil
    else
        return nil, "Invalid config format in " .. path
    end
end

--- Создать резервную копию файла
--- @param filePath string
--- @return boolean, string
function ConfigManager.backupFile(filePath)
    local path = fs.combine(shell.dir(), filePath)
    if not fs.exists(path) then
        return false, "No file to backup"
    end
    local backupDir = fs.combine(shell.dir(), "backups")
    if not fs.exists(backupDir) then
        fs.makeDir(backupDir)
    end
    local fileName = fs.getName(path)
    local backupName = fileName:gsub("%.([^%.]+)$", "_backup.%1")
    if backupName == fileName then
        backupName = fileName .. "_backup"
    end
    local backupPath = fs.combine(backupDir, backupName)
    -- Удаляем старый бекап, если есть (fs.copy не перезаписывает)
    if fs.exists(backupPath) then
        fs.delete(backupPath)
    end
    fs.copy(path, backupPath)
    return true, backupPath
end

-- ==================== VALIDATION ====================

--- Проверить, существует ли периферия с данным именем
--- @param name string
--- @return boolean
function ConfigManager.checkPeripheralExists(name)
    local all = peripheral.getNames()
    for _, n in ipairs(all) do
        if n == name then
            return true
        end
    end
    return false
end

--- Проверить, используется ли периферия в конфиге (рекурсивно)
local function isPeripheralUsedIn(peripheralName, config, excludeKey)
    if not config then return false end
    for key, value in pairs(config) do
        if key ~= (excludeKey or "") then
            if type(value) == "string" and value == peripheralName then
                return true
            elseif type(value) == "table" then
                for _, v in ipairs(value) do
                    if v == peripheralName then return true end
                end
            end
        end
    end
    return false
end

--- Проверить, не используется ли устройство в существующих конфигах
function ConfigManager.isDeviceAlreadyUsed(peripheralName, existingConfigs)
    for _, config in ipairs(existingConfigs) do
        if isPeripheralUsedIn(peripheralName, config) then
            return true
        end
    end
    return false
end

-- ==================== CONFIG CREATION (результат из ConfigWizard) ====================

--- Создать конфиг из результата config_wizard.
--- Входной формат (из ConfigWizard): { tech_monitor = "name", info_monitors = {"name1", ...}, ... }
--- Ключи уже соответствуют device_types.lua, группируем их в таблицу `peripherals`.
--- @param devices table
--- @return table
function ConfigManager.createConfig(devices)
    -- Периферия из wizard'а. Все ключи — из device_types.lua.
    local config = {
        peripherals = devices,
    }
    return config
end

--- Создать карту ульев из результата hive_wizard.
--- Каждая запись — один улей с 3 перифериями:
---   hive   = периферия самого улья (beehive/cage, методы инвентаря)
---   reader = блок-ридер (getBlockData)
---   relay  = редстоун-реле (setBundledOutput / setAnalogOutput)
--- @param hives table array of { hive, reader, relay }
--- @return table array of { id, hive, reader, relay }
function ConfigManager.createHivesMap(hives)
    local map = {}
    for i, hive in ipairs(hives) do
        table.insert(map, {
            id = i,
            hive = hive.hive,
            reader = hive.reader,
            relay = hive.relay,
        })
    end
    return map
end

--- Найти запись улья по id (для других скриптов)
--- @param map table карта из createHivesMap
--- @param id number id улья
--- @return table|nil { id, hive, reader, relay }
function ConfigManager.findHiveById(map, id)
    if type(map) ~= "table" then return nil end
    for _, hive in ipairs(map) do
        if hive.id == id then
            return hive
        end
    end
    return nil
end

-- ==================== SAVE WITH BACKUP ====================

--- Сохранить конфиг с авто-бекапом
--- @param data table
--- @param filePath string
--- @return boolean, string
function ConfigManager.saveConfig(data, filePath)
    if fs.exists(fs.combine(shell.dir(), filePath)) then
        ConfigManager.backupFile(filePath)
    end
    local ok, result = ConfigManager.saveToFile(data, filePath)
    if not ok then
        return false, "Save failed: " .. (result or "unknown error")
    end
    return true, "Saved to " .. result
end

-- ==================== REDNET HELPER ====================

local DEFAULT_TIMEOUT = 5

--- Отправить rednet-сообщение и ждать ответа ТОЛЬКО от targetId.
--- Принимаем только СТРОКОВЫЕ ответы (free/frozen/config_updated/running/...).
--- Табличные сообщения (broadcast-статусы терминалов {type="status",...})
--- игнорируются и ждём дальше - гарантирует, что busy? не словит чужое.
--- @param targetId number
--- @param command string
--- @param data table|nil
--- @param timeout number
--- @return boolean, any
function ConfigManager.rednetCall(targetId, command, data, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    local msg
    if data ~= nil then
        msg = { command = command, data = data }
    else
        msg = command
    end

    rednet.send(targetId, msg)
    local deadline = os.clock() + timeout
    while true do
        local sender, response = rednet.receive(1)
        if sender == targetId and type(response) == "string" then
            return true, response
        end
        -- Иначе (чужие или табличные/статус-сообщения) игнорируем и ждём
        if os.clock() >= deadline then
            return false, "No response (timeout " .. timeout .. "s)"
        end
    end
end

-- ==================== REDNET CONFIG PROTOCOL ====================

--- Проверить, свободен ли терминал (используется редко; основная защита от
--- редактирования занятого терминала - в freezeTerminal, который получает
--- "wait"/не-"frozen" если терминал занят).
function ConfigManager.checkTerminalBusy(targetId, timeout)
    local ok, response = ConfigManager.rednetCall(targetId, "busy?", nil, timeout or 3)
    if not ok then
        return false, "Terminal offline"
    end
    if response == "free" then
        return true, "free"
    elseif response == "busy" then
        return false, "Terminal is busy"
    end
    return false, "Unknown response: " .. tostring(response)
end

--- Отправить конфиг терминалу с протоколом заморозки
function ConfigManager.sendConfigToTerminal(targetId, configData, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    local ok, msg = ConfigManager.checkTerminalBusy(targetId, 3)
    if not ok then
        return false, msg
    end

    ok, msg = ConfigManager.rednetCall(targetId, "freeze", nil, 5)
    if not ok then
        return false, "Freeze failed: " .. msg
    end
    if msg ~= "frozen" then
        return false, "Terminal rejected freeze (response: " .. tostring(msg) .. ")"
    end

    ok, msg = ConfigManager.rednetCall(targetId, "update_config", configData, timeout)
    if not ok then
        return false, "Config send failed: " .. msg
    end
    if msg ~= "config_updated" then
        return false, "Terminal rejected config (response: " .. tostring(msg) .. ")"
    end

    ok, msg = ConfigManager.rednetCall(targetId, "unfreeze", nil, 3)
    if not ok then
        return false, "Unfreeze failed: " .. msg
    end
    if msg ~= "running" then
        return false, "Terminal rejected unfreeze (response: " .. tostring(msg) .. ")"
    end

    return true, "Config sent and applied"
end

--- Отправить начальный конфиг терминалу (без заморозки)
function ConfigManager.sendInitialConfig(targetId, configData, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    rednet.send(targetId, { command = "request_config", data = configData })
    local sender, response = rednet.receive(timeout)
    if not sender then
        return false, "No response (timeout " .. timeout .. "s)"
    end
    if sender ~= targetId then
        return false, "Response from wrong terminal"
    end
    if response ~= "config_received" then
        return false, "Terminal rejected config (response: " .. tostring(response) .. ")"
    end
    return true, "Initial config sent"
end

-- ==================== FREEZE PROTOCOL (for interactive editing) ====================
-- Used while the user edits a config on HeartOS: the terminal is frozen
-- (waits with the boot screen), configured, then unfrozen.

--- Freeze a terminal. Expects "frozen".
function ConfigManager.freezeTerminal(targetId, timeout)
    local ok, response = ConfigManager.rednetCall(targetId, "freeze", nil, timeout or 3)
    if not ok then
        return false, "Freeze failed: " .. tostring(response)
    end
    if response ~= "frozen" then
        return false, "Terminal rejected freeze (response: " .. tostring(response) .. ")"
    end
    return true, response
end

--- Send a config to an already frozen terminal. Expects "config_updated".
function ConfigManager.sendUpdateConfig(targetId, configData, timeout)
    local ok, response = ConfigManager.rednetCall(targetId, "update_config", configData, timeout or 5)
    if not ok then
        return false, "Config send failed: " .. tostring(response)
    end
    if response ~= "config_updated" then
        return false, "Terminal rejected config (response: " .. tostring(response) .. ")"
    end
    return true, response
end

--- Unfreeze a terminal. Expects "running".
function ConfigManager.unfreezeTerminal(targetId, timeout)
    local ok, response = ConfigManager.rednetCall(targetId, "unfreeze", nil, timeout or 3)
    if not ok then
        return false, "Unfreeze failed: " .. tostring(response)
    end
    if response ~= "running" then
        return false, "Terminal rejected unfreeze (response: " .. tostring(response) .. ")"
    end
    return true, response
end

return ConfigManager