-- hive_map.lua
-- Сканирование ульев через chat-интерфейс
-- Использует тот же принцип, что config_wizard.lua: ждём подключения block reader'а,
-- проверяем метод getBlockData, предлагаем добавить в карту.

local MonitorUtil = require("screens/monitor_util")
local ConfigManager = require("config_manager")
local ChatUtil = require("chat_util")

local HiveMap = {}

local COLORS = MonitorUtil.COLORS

local HIVES_FILE = "hives_map.lua"

--- Сравнить два списка периферии: найти добавленные и удалённые
local function compareLists(oldList, newList)
    local oldSet = {}
    local newSet = {}
    for _, name in ipairs(oldList) do oldSet[name] = true end
    for _, name in ipairs(newList) do newSet[name] = true end

    local added = {}
    local removed = {}
    for _, name in ipairs(newList) do if not oldSet[name] then table.insert(added, name) end end
    for _, name in ipairs(oldList) do if not newSet[name] then table.insert(removed, name) end end
    return added, removed
end

--- Chat shortcuts
local function chat(msg) ChatUtil.send(msg) end
local function chatInfo(msg) ChatUtil.sendInfo(msg) end
local function chatSuccess(msg) ChatUtil.sendSuccess(msg) end
local function chatError(msg) ChatUtil.sendError(msg) end
local function chatStep(msg) ChatUtil.sendStep(msg) end
local function chatHighlight(msg) ChatUtil.sendHighlight(msg) end
local function chatSeparator() ChatUtil.sendSeparator() end

--- Сканирование одного улья (ожидание подключения block reader'а)
--- @return string|nil имя найденного ридера, или nil при таймауте/отмене
local function scanSingleHive()
    local timeout = 120
    local elapsed = 0
    local prevList = {}
    local names = peripheral.getNames()
    table.sort(names)
    for _, n in ipairs(names) do table.insert(prevList, n) end

    chatSeparator()
    chatStep("Connect a block reader for the hive (timeout " .. timeout .. " sec)...")

    while elapsed < timeout do
        os.sleep(0.5)
        elapsed = elapsed + 0.5

        local currentList = {}
        local curNames = peripheral.getNames()
        table.sort(curNames)
        for _, n in ipairs(curNames) do table.insert(currentList, n) end

        local added, removed = compareLists(prevList, currentList)

        local name = nil
        if #added == 1 and #removed == 0 then
            name = added[1]
        elseif #removed == 1 and #added == 1 and removed[1] == added[1] then
            name = added[1]
        elseif #added > 0 or #removed > 0 then
            prevList = currentList
        end

        if name then
            local methods = peripheral.getMethods(name)
            local hasGetBlockData = false
            for _, m in ipairs(methods) do
                if m == "getBlockData" then
                    hasGetBlockData = true
                    break
                end
            end
            if hasGetBlockData then
                return name
            else
                chatError(name .. " does not have getBlockData method (not a block reader)")
                prevList = currentList
            end
        end
    end

    return nil
end

--- Основной цикл: сканирование ульев
function HiveMap.run(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    local w, h = mon.getSize()
    MonitorUtil.clearScreen(mon)
    MonitorUtil.drawTitle(mon, "=== Hive Map Scanner ===", 2)
    MonitorUtil.drawText(mon, 2, 4, "Follow instructions in CHAT.", COLORS.highlight)
    MonitorUtil.drawText(mon, 2, 5, "All responses go through in-game chat.", COLORS.text)
    os.sleep(3)

    chatSeparator()
    chatHighlight("=== Hive Map Scanner ===")
    chatInfo("Scan block readers for each hive.")
    chatInfo("Answer Y or N in game chat.")

    local hives = {}
    local addMore = true

    while addMore do
        chatSeparator()
        chatInfo("Hive #" .. (#hives + 1))

        local found = scanSingleHive()

        if found then
            local reader = peripheral.wrap(found)
            local hiveBlock = "unknown"
            if reader then
                local ok, data = pcall(reader.getBlockData)
                if ok and data and data.name then
                    hiveBlock = data.name
                end
            end

            chatSuccess("Block reader detected: " .. found)
            chatInfo("Hive: " .. hiveBlock)
            chatInfo("Add this hive? (Y/N)")

            local confirmed = ChatUtil.waitForYesNo(120)
            if confirmed == true then
                table.insert(hives, { reader = found, hive = hiveBlock })
                chatSuccess("Hive #" .. #hives .. " added: " .. found .. " -> " .. hiveBlock)

                chatInfo("Add another hive? (Y/N)")
                local addMore2 = ChatUtil.waitForYesNo(120)
                if addMore2 ~= true then
                    addMore = false
                end
            else
                chatInfo("Reader declined. You can try another one.")
            end
        else
            chatError("Timeout. No block reader detected.")
            chatInfo("Add another hive? (Y/N)")
            local addMore2 = ChatUtil.waitForYesNo(120)
            if addMore2 ~= true then
                addMore = false
            end
        end
    end

    -- Save & send
    if #hives > 0 then
        local hivesMap = ConfigManager.createHivesMap(hives)
        local ok, path = ConfigManager.saveConfig(hivesMap, HIVES_FILE)
        if ok then
            chatSuccess("Hives map saved to " .. path .. " (" .. #hives .. " hives)!")
        else
            chatError("Failed to save hives map: " .. path)
        end

        local targetId = heartConfig.beeos_id or 1
        local ok2, msg2 = ConfigManager.sendInitialConfig(targetId, { command = "hives_map", data = hivesMap })
        if ok2 then
            chatSuccess("Hives map sent to BeeOS!")
        else
            chatError("Failed to send hives map: " .. tostring(msg2))
        end
    else
        chatError("No hives were added. Hives map not saved.")
    end

    MonitorUtil.clearScreen(mon)
    MonitorUtil.drawTitle(mon, "=== Hive Map Scanner ===", 2)
    MonitorUtil.drawText(mon, 2, 4, "Hives scanned: " .. #hives, #hives > 0 and COLORS.success or COLORS.error)
    MonitorUtil.drawText(mon, 2, h - 1, "Tap to return...", COLORS.darkGray)
    pcall(os.pullEvent, "monitor_touch")
end

return HiveMap