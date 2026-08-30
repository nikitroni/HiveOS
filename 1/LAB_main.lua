-- lab_main.lua
-- Главный исполняемый файл лабораторного терминала.
-- Инициализирует периферии, запускает два параллельных потока:
--   - Отрисовка основного монитора и кнопок (по таймеру)
--   - Обработка событий (нажатия кнопок, rednet)

local config = require("lab_config")
local Utils = require("lab_utils")
local HUD = require("lab_hud")
local Buttons = require("lab_buttons")
local Processor = require("lab_processor")
local GeneProduction = require("lab_geneproduction")
local Breeding = require("lab_breeding")

-- ==================== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ====================
local running = true
local frame = 0
local mode = "wait"
local logBuffer = {}
local bees = {}
local geneCounts = {}
local neededCounts = {}

local targetHive = nil
local targetHiveBlock = nil
local lastSenderId = nil
local processing = false

-- Файл состояния
local STATE_FILE = "lab_state.dat"
local cancelRequested = false

-- ==================== ФУНКЦИИ ДЛЯ РАБОТЫ С ЛОГОМ ====================
local function addLogLine(line)
    line = line:gsub("§.", "")
    table.insert(logBuffer, line)
    if #logBuffer > 9 then
        table.remove(logBuffer, 1)
    end
end

-- ==================== ЗАГРУЗКА И СОХРАНЕНИЕ СОСТОЯНИЯ ====================
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local content = file.readAll()
        file.close()
        local ok, state = pcall(textutils.unserialize, content)
        if ok and state then
            targetHive = state.hive_id
            targetHiveBlock = state.hive_block
            lastSenderId = state.sender_id
            addLogLine("Loaded previous state from " .. STATE_FILE)
        else
            print("Failed to load state, ignoring.")
        end
    end
end

local function saveState()
    local state = {
        hive_id = targetHive,
        hive_block = targetHiveBlock,
        sender_id = lastSenderId,
    }
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

local function clearState()
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end
    targetHive = nil
    targetHiveBlock = nil
    lastSenderId = nil
end

-- ==================== ОБНОВЛЕНИЕ ДАННЫХ ====================
local function refreshData()
    bees = Utils.getBeesFromBarrel()
    geneCounts = Utils.getGeneCountsFromIndexer()
    neededCounts = Utils.calculateNeededGenes(bees)
end

-- ==================== ПОТОК ОТРИСОВКИ ====================
local function renderLoop()
    local timer = os.startTimer(0.1)
    while running do
        local event, id = os.pullEvent()
        if event == "timer" and id == timer then
            frame = frame + 1
            if frame % 20 == 0 then
                refreshData()
            end
            HUD.drawAll(bees, geneCounts, neededCounts, mode, logBuffer, frame)
            Buttons.drawAll(frame)
            timer = os.startTimer(0.1)
        end
    end
end

-- ==================== ОБРАБОТЧИКИ КНОПОК ====================
local function onBeeOut()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    if not targetHiveBlock then
        addLogLine("!ERROR: No target hive remembered.")
        return
    end
    if not lastSenderId then
        addLogLine("!ERROR: No sender ID.")
        return
    end
    processing = true
    addLogLine("Returning bees...")
    local hive = peripheral.wrap(targetHiveBlock)
    if not hive then
        addLogLine("!ERROR: Hive not found: " .. targetHiveBlock)
        processing = false
        return
    end

    -- Возвращаем пчёл из бочки в улей
    local barrel = peripheral.wrap(config.peripherals.lab_chest)
    local moved = 0
    for slot = 1, barrel.size() do
        local item = barrel.getItemDetail(slot)
        if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
            local m = barrel.pushItems(targetHiveBlock, slot)
            if m > 0 then
                moved = moved + m
            end
        end
    end

    -- Возвращаем пустые клетки из улья в хранилище
    local cageChest = peripheral.wrap(config.peripherals.cage_chest)
    if cageChest then
        for slot = 3, 11 do
            local item = hive.getItemDetail(slot)
            if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
                local m = hive.pushItems(config.peripherals.cage_chest, slot)
                if m > 0 then
                    addLogLine(string.format("Returned empty cage from slot %d", slot))
                end
            end
        end
    end

    addLogLine(string.format("Returned %d bees to hive.", moved))
    rednet.send(lastSenderId, { type = "lab_complete", hive_id = targetHive, bee_count = moved })
    clearState()
    mode = "wait"
    processing = false
end

local function onGeneUpgrade()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    processing = true
    addLogLine("Start upgrade.")
    mode = "log"
    local successCount, totalCount = Processor.processAllBees(function(msg) addLogLine(msg) end)
    if successCount == totalCount then
        mode = "win"
    else
        addLogLine(string.format("Incomplete: %d/%d ok", successCount, totalCount))
        mode = "log"
    end
    processing = false
end

local function onBeeProduce()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    processing = true
    addLogLine("Start gene prod.")
    mode = "log"
    GeneProduction.runProduction(function(msg) addLogLine("" .. msg) end)
    processing = false
end

-- onBreed:
local function onBreed()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    processing = true
    addLogLine("Starting breeding...")
    mode = "log"
    Breeding.run(function(msg) addLogLine(msg) end)
    mode = "wait"
    processing = false
end

Buttons.setCallbacks({
    onBeeOut = onBeeOut,
    onGeneUpgrade = onGeneUpgrade,
    onBeeProduce = onBeeProduce,
    onBreed = onBreed,   
})

-- ==================== ПОТОК ОБРАБОТКИ СОБЫТИЙ ====================
local function eventLoop()
    -- Открытие rednet
    local modemSide = peripheral.find("modem")
    if not modemSide then
        print("No modem found, trying side 'back'")
        modemSide = "back"
    end

    if modemSide then
        if type(modemSide) ~= "string" then
            print("Warning: modemSide is not a string, it's a " .. type(modemSide))
            modemSide = "back"
        end

        local channel = config.peripherals.rednet_channel
        print("Opening rednet on " .. modemSide .. " channel " .. tostring(channel))

        if rednet.isOpen(modemSide) then
            print("Rednet already open on " .. modemSide)
        else
            local success, err = pcall(rednet.open, modemSide, channel)
            if success then
                print("Rednet opened on " .. modemSide)
            else
                print("Failed to open rednet: " .. tostring(err))
            end
        end
    else
        print("No modem available. Rednet disabled.")
    end

    print("Laboratory terminal ready.")

    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            Buttons.handleTouch(p1, p2, p3)
        elseif event == "rednet_message" then
            local senderId, message = p1, p2
            if message and message.type == "lab_request" then
                targetHive = message.hive_id
                targetHiveBlock = message.hive_block
                lastSenderId = senderId
                saveState()
                addLogLine(string.format("Received bees from hive %d.", targetHive))
                mode = "wait"
            end
        end
    end
end

-- ==================== ЗАПУСК ====================
print("Starting laboratory terminal...")
refreshData()
loadState()   -- восстановить состояние после перезапуска
-- Если в бочке нет пчёл, сбросить состояние
if #bees == 0 then
    clearState()
end

parallel.waitForAny(renderLoop, eventLoop)