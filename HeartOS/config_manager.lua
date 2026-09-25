-- config_manager.lua
-- Config management module: saving, loading, validation, rednet protocol
-- Used by HeartOS to manage BeeOS and LabOS configs
--
-- ATTENTION: device types live in device_types.lua (single source of truth).
-- The device list for creating a config is taken from there by group.
-- The config contains ONLY peripherals (block names). All other settings
-- (slots, coordinates, logic) are hard-coded in the BeeOS/LabOS scripts themselves.

local ChatUtil = require("chat_util")
local RednetProtocol = require("rednet_protocol")

local ConfigManager = {}

-- ==================== REDNET PROTOCOLS ====================

-- Single source of protocol names for screens and the resolver below.
ConfigManager.PROTOCOL = { heartos = "heartos", beeos = "beeos", labos = "labos" }

--- Resolve a terminal ID by its rednet protocol (dynamic lookup).
--- @param protocol string
--- @return number|nil
function ConfigManager.resolve(protocol)
    return RednetProtocol.lookup(protocol, "main")
end

-- ==================== CORE FUNCTIONS ====================

--- Save a table to a file as a Lua script with return
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

--- Load a table from a file (executes it as a Lua script)
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

--- Create a backup copy of the file
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
    -- Delete the old backup if any (fs.copy does not overwrite)
    if fs.exists(backupPath) then
        fs.delete(backupPath)
    end
    fs.copy(path, backupPath)
    return true, backupPath
end

-- ==================== VALIDATION ====================

--- Check whether a peripheral with the given name exists
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

--- Check whether the peripheral is used in the config (recursively)
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

--- Check whether the device is already used in existing configs
function ConfigManager.isDeviceAlreadyUsed(peripheralName, existingConfigs)
    for _, config in ipairs(existingConfigs) do
        if isPeripheralUsedIn(peripheralName, config) then
            return true
        end
    end
    return false
end

-- ==================== CONFIG CREATION (result from ConfigWizard) ====================

--- Create a config from a config_wizard result.
--- Input format (from ConfigWizard): { tech_monitor = "name", info_monitors = {"name1", ...}, ... }
--- The keys already match device_types.lua, we group them into the `peripherals` table.
--- @param devices table
--- @return table
function ConfigManager.createConfig(devices)
    -- Peripherals from the wizard. All keys are from device_types.lua.
    local config = {
        peripherals = devices,
    }
    return config
end

--- Create a hive map from a hive_wizard result.
--- Each entry - one hive with 3 peripherals:
---   hive   = the hive peripheral itself (beehive/cage, inventory methods)
---   reader = reader block (getBlockData)
---   relay  = redstone relay (setBundledOutput / setAnalogOutput)
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

--- Find a hive entry by id (for other scripts)
--- @param map table map from createHivesMap
--- @param id number hive id
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

--- Save the config with auto-backup
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

--- Send a rednet message and wait for a reply ONLY from targetId.
--- We accept only STRING replies (free/frozen/config_updated/running/...).
--- Table messages are ignored and we keep waiting - guarantees that busy?
--- does not catch someone else's.
--- @param targetId number resolved terminal id
--- @param protocol string protocol label used as the rednet message tag
--- @param command string
--- @param data table|nil
--- @param timeout number
--- @return boolean, any
function ConfigManager.rednetCall(targetId, protocol, command, data, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    local msg
    if data ~= nil then
        msg = { command = command, data = data }
    else
        msg = command
    end

    rednet.send(targetId, msg, protocol)
    local deadline = os.clock() + timeout
    while true do
        local sender, response = rednet.receive(1)
        if sender == targetId and type(response) == "string" then
            return true, response
        end
        -- Otherwise (foreign or table/status messages) ignore and keep waiting
        if os.clock() >= deadline then
            return false, "No response (timeout " .. timeout .. "s)"
        end
    end
end

-- ==================== REDNET CONFIG PROTOCOL ====================

--- Check whether the terminal is free (rarely used; the main protection against
--- editing a busy terminal is in freezeTerminal, which gets
--- "wait"/not-"frozen" if the terminal is busy).
function ConfigManager.checkTerminalBusy(protocol, timeout)
    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end
    local ok, response = ConfigManager.rednetCall(id, protocol, "busy?", nil, timeout or 3)
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

--- Send a config to the terminal with the freeze protocol
function ConfigManager.sendConfigToTerminal(protocol, configData, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end

    local ok, msg = ConfigManager.checkTerminalBusy(protocol, 3)
    if not ok then
        return false, msg
    end

    ok, msg = ConfigManager.rednetCall(id, protocol, "freeze", nil, 5)
    if not ok then
        return false, "Freeze failed: " .. msg
    end
    if msg ~= "frozen" then
        return false, "Terminal rejected freeze (response: " .. tostring(msg) .. ")"
    end

    ok, msg = ConfigManager.rednetCall(id, protocol, "update_config", configData, timeout)
    if not ok then
        return false, "Config send failed: " .. msg
    end
    if msg ~= "config_updated" then
        return false, "Terminal rejected config (response: " .. tostring(msg) .. ")"
    end

    ok, msg = ConfigManager.rednetCall(id, protocol, "unfreeze", nil, 3)
    if not ok then
        return false, "Unfreeze failed: " .. msg
    end
    if msg ~= "running" then
        return false, "Terminal rejected unfreeze (response: " .. tostring(msg) .. ")"
    end

    return true, "Config sent and applied"
end

--- Send the initial config to the terminal (without freezing)
function ConfigManager.sendInitialConfig(protocol, configData, timeout)
    timeout = timeout or DEFAULT_TIMEOUT

    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end

    rednet.send(id, { command = "request_config", data = configData }, protocol)
    local sender, response = rednet.receive(timeout)
    if not sender then
        return false, "No response (timeout " .. timeout .. "s)"
    end
    if sender ~= id then
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
function ConfigManager.freezeTerminal(protocol, timeout)
    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end
    local ok, response = ConfigManager.rednetCall(id, protocol, "freeze", nil, timeout or 3)
    if not ok then
        return false, "Freeze failed: " .. tostring(response)
    end
    if response ~= "frozen" then
        return false, "Terminal rejected freeze (response: " .. tostring(response) .. ")"
    end
    return true, response
end

--- Send a config to an already frozen terminal. Expects "config_updated".
function ConfigManager.sendUpdateConfig(protocol, configData, timeout)
    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end
    local ok, response = ConfigManager.rednetCall(id, protocol, "update_config", configData, timeout or 5)
    if not ok then
        return false, "Config send failed: " .. tostring(response)
    end
    if response ~= "config_updated" then
        return false, "Terminal rejected config (response: " .. tostring(response) .. ")"
    end
    return true, response
end

--- Unfreeze a terminal. Expects "running".
function ConfigManager.unfreezeTerminal(protocol, timeout)
    local id = ConfigManager.resolve(protocol)
    if not id then
        return false, "Terminal not found: " .. protocol
    end
    local ok, response = ConfigManager.rednetCall(id, protocol, "unfreeze", nil, timeout or 3)
    if not ok then
        return false, "Unfreeze failed: " .. tostring(response)
    end
    if response ~= "running" then
        return false, "Terminal rejected unfreeze (response: " .. tostring(response) .. ")"
    end
    return true, response
end

return ConfigManager