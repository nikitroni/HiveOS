-- LAB_main.lua
-- Главный исполняемый файл лабораторного терминала (LabOS).
--
-- Инициализирует периферии через lab_config_loader (статичный
-- lab_lib.lua + динамичный labos_config.lua от HeartOS), поднимает
-- rednet, принимает конфиги по протоколу HeartOS (freeze / update_config /
-- unfreeze / status / busy?), сообщает свой статус (free/busy) и рисует
-- экран ожидания (HUD_Lab_Boot.nfp) при заморозке или ожидании конфигов.
--
-- Единый владелец событий - главный цикл (os.pullEvent без фильтра),
-- чтобы rednet-сообщения никогда не терялись; рендер выполняется в этом
-- же цикле по таймеру.

local ConfigLoader = require("lab_config_loader")
local lib = ConfigLoader.load()

local Utils = require("lab_utils")
local HUD = require("lab_hud")
local Buttons = require("lab_buttons")
local Processor = require("lab_processor")
local GeneProduction = require("lab_geneproduction")
local Breeding = require("lab_breeding")
local Boot = require("lab_boot")

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

-- Протокол HeartOS
local currentStatus = "free"
local frozen = false
local waitPrepared = false  -- перерисовка фона ожидания при смене режима
-- Страховка от потерянного unfreeze: если заморозка слишком долго без
-- активной настройки (конфиг не приходит), снимаем её автоматически.
local frozenSince = nil
local FROZEN_MAX_SECONDS = 60
local lastConfigActivity = os.clock()

-- Файл состояния
local STATE_FILE = "lab_state.dat"
local cancelRequested = false

-- Динамический конфиг от HeartOS (сохраняется в labos_config.lua)
local LABOS_CONFIG_FILE = "labos_config.lua"

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
    local okBees, resBees = pcall(Utils.getBeesFromBarrel)
    if okBees then bees = resBees else bees = {} addLogLine("Error reading barrel") end
    local okCounts, resCounts = pcall(Utils.getGeneCountsFromIndexer)
    if okCounts then geneCounts = resCounts else geneCounts = {} addLogLine("Error reading indexer") end
    -- neededCounts считается без чтения периферии, всегда безопасно
    do
        local ok, res = pcall(Utils.calculateNeededGenes, bees)
        if ok then neededCounts = res else neededCounts = {} end
    end
end

-- ==================== ПРОТОКОЛ HEARTOS ====================

-- Отправить HeartOS свой ID и статус
local function sendStatus(status)
    pcall(rednet.broadcast, { type = "status", id = os.getComputerID(), status = status })
end

-- Сохранить динамический конфиг от HeartOS и пересобрать библиотеку
local function saveDynamicConfig(data)
    if type(data) ~= "table" then return false end
    local file = fs.open(LABOS_CONFIG_FILE, "w")
    if not file then return false end
    file.write("return " .. textutils.serialize(data))
    file.close()
    -- Модули кэшируют lab_lib, поэтому перезагружаем их после пересборки
    package.loaded["lab_lib"] = nil
    package.loaded["lab_hud"] = nil
    package.loaded["lab_buttons"] = nil
    package.loaded["lab_processor"] = nil
    package.loaded["lab_utils"] = nil
    package.loaded["lab_breeding"] = nil
    package.loaded["lab_geneproduction"] = nil
    return true
end

-- Обработка одного rednet-сообщения от HeartOS.
-- Возвращает: "config_reloaded" (конфиг принят, нужно обновить UI/периферии),
--   nil (просто ответили).
local function handleConfigMessage(sender, message)
    -- Отладочный вывод в консоль терминала (видно, что происходит)
    if type(message) == "string" then
        addLogLine("Net<- '" .. tostring(message) .. "'")
        if message == "busy?" or message == "status" then
            addLogLine("STATUS? -> " .. tostring(currentStatus))
            rednet.send(sender, currentStatus)
        elseif message == "freeze" then
            if currentStatus == "busy" then
                -- Терминал занят задачей: не замораживаем, Edit не должен открыться
                rednet.send(sender, "wait")
            else
                frozen = true
                frozenSince = os.clock()
                rednet.send(sender, "frozen")
            end
        elseif message == "unfreeze" then
            frozen = false
            frozenSince = nil
            waitPrepared = false
            rednet.send(sender, "running")
        end
        return nil
    end

    if type(message) ~= "table" or type(message.command) ~= "string" then
        return nil
    end

    local command = message.command
    if command == "request_config" then
        addLogLine("Net<- request_config")
        if saveDynamicConfig(message.data) then
            rednet.send(sender, "config_received")
        else
            rednet.send(sender, "config_error")
        end
        return "config_reloaded"
    end

    if command == "update_config" then
        addLogLine("Net<- update_config")
        if currentStatus == "busy" then
            rednet.send(sender, "wait")
            return nil
        end
        lastConfigActivity = os.clock()
        if saveDynamicConfig(message.data) then
            rednet.send(sender, "config_updated")
        else
            rednet.send(sender, "config_error")
        end
        return "config_reloaded"
    end

    return nil
end

-- ==================== ОБРАБОТЧИКИ КНОПОК ====================
local function setBusy(busy)
    processing = busy
    if busy then
        currentStatus = "busy"
    else
        currentStatus = "free"
        sendStatus("free")
    end
end

function onBeeOut()
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
    -- Возврат пчёл выполняется в taskWorker (не блокирует rednet)
    setBusy(true)
    runTask(function()
        addLogLine("Returning bees...")
        local hive = peripheral.wrap(targetHiveBlock)
        if not hive then
            addLogLine("!ERROR: Hive not found: " .. targetHiveBlock)
            return
        end

        -- Возвращаем пчёл из бочки в улей
        local barrel = peripheral.wrap(lib.peripherals.lab_chest)
        if not barrel then
            addLogLine("!ERROR: Lab chest not found: " .. tostring(lib.peripherals.lab_chest))
            return
        end
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
        local cageChest = peripheral.wrap(lib.peripherals.cage_chest)
        if cageChest then
            for slot = 3, 11 do
                local item = hive.getItemDetail(slot)
                if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
                    local m = hive.pushItems(lib.peripherals.cage_chest, slot)
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
    end)
end

-- ==================== ЗАДАЧИ (ВЫПОЛНЯЮТСЯ В ОТДЕЛЬНОМ ПОТОКЕ) ====================
-- ВАЖНО: долгие задачи (производство генов / апгрейд / размножение) НЕ должны
-- блокировать eventLoop, иначе sleep() внутри них съест rednet-сообщения
-- (busy?/freeze) из-за фильтра, и HeartOS не получит ответ. Поэтому задачи
-- кладутся в очередь и выполняются третьим потоком taskWorker, а eventLoop
-- остаётся свободным для rednet и кнопок.
local taskQueue = {}
local function runTask(taskFn)
    table.insert(taskQueue, taskFn)
end

-- Выполняет задачи из очереди (с гарантированным сбросом busy).
-- Работает, пока есть задачи; иначе крутится на pullEvent (не блокируя rednet).
local function taskWorker()
    while running do
        if #taskQueue > 0 then
            local taskFn = table.remove(taskQueue, 1)
            local ok, err = pcall(function()
                taskFn()
            end)
            if not ok then
                print("LAB task error: " .. tostring(err))
                if type(err) == "table" then
                    print(textutils.serialize(err))
                end
                addLogLine("!ERROR: " .. tostring(err))
            end
            setBusy(false)
        else
            os.pullEvent()
        end
    end
end

local function onGeneUpgrade()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Start upgrade.")
        mode = "log"
        local successCount, totalCount = Processor.processAllBees(function(msg) addLogLine(msg) end)
        if successCount == totalCount then
            mode = "win"
        else
            addLogLine(string.format("Incomplete: %d/%d ok", successCount, totalCount))
            mode = "log"
        end
    end)
end

local function onBeeProduce()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Start gene prod.")
        mode = "log"
        GeneProduction.runProduction(function(msg) addLogLine("" .. msg) end)
    end)
end

-- onBreed:
local function onBreed()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Starting breeding...")
        mode = "log"
        Breeding.run(function(msg) addLogLine(msg) end)
        mode = "wait"
    end)
end

-- Устанавливаем колбэки кнопок (переустанавливаются после перезагрузки
-- модулей при приёме нового конфига)
local function setupButtonCallbacks()
    Buttons.setCallbacks({
        onBeeOut = onBeeOut,
        onGeneUpgrade = onGeneUpgrade,
        onBeeProduce = onBeeProduce,
        onBreed = onBreed,
    })
end

-- ==================== ОТКРЫТИЕ REDNET ====================
local function openRednet()
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

        local channel = lib.rednet_channel
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
end

-- ==================== ЭКРАН ОЖИДАНИЯ ====================
-- Ожидание при заморозке рисуется в таймерной ветке главного цикла через
-- Boot.drawWaitFrame (плавная полоса); выйти из ожидания можно только
-- командой unfreeze (или приёмом конфига, что пересобирает экраны).

-- ==================== ОБНОВЛЕНИЕ ПЕРИФЕРИЙ ПОСЛЕ КОНФИГА ====================
-- После приёма конфига все модули перезагружены; главная программа должна
-- получить свежий конфиг и свежие обёртки периферии.
local function reinitAfterConfig()
    lib = require("lab_config_loader").reload()
    Utils = require("lab_utils")
    HUD = require("lab_hud")
    Buttons = require("lab_buttons")
    Processor = require("lab_processor")
    GeneProduction = require("lab_geneproduction")
    Breeding = require("lab_breeding")
    setupButtonCallbacks()   -- новый Buttons модуль имеет пустые callbacks
    refreshData()
end

-- ==================== ГЛАВНЫЙ ЦИКЛ ====================

-- Проверка: настроена ли периферия (пришёл labos_config.lua от HeartOS)
local function hasPeripheralConfig()
    local ok, res = pcall(ConfigLoader.load)
    if ok and res and res.peripherals and res.peripherals.main_monitor then
        return true
    end
    return false
end

-- Печатает в терминал компьютера текущее состояние конфига периферии.
-- Мониторы не используются (как в BeeOS).
local function printConfigStatus()
    local native = term.native()
    local old = term.current()
    term.redirect(native)
    term.clear()
    term.setCursorPos(1, 1)

    local function line(label, present)
        term.write("[")
        term.setTextColor(present and colors.green or colors.red)
        term.write(present and " OK " or " -- ")
        term.setTextColor(colors.white)
        term.write("] ")
        print(label)
    end

    print("LabOS: waiting for HeartOS config")
    print("")
    line("labos_config.lua (peripherals)", hasPeripheralConfig())
    print("")
    print("Config is sent from the HeartOS")
    print("terminal (Configure LabOS).")

    term.redirect(old)
end

-- Однократное ожидание сообщения от HeartOS.
-- Возвращает true, когда пришёл и обработан конфиг (config_reloaded).
local function waitForConfigMessage()
    while true do
        -- pcall возвращает (ok, eventName, p1, p2, ...); для rednet_message:
        -- p1 = senderId, p2 = message
        local okPull, evt, senderId, msg = pcall(os.pullEvent, "rednet_message")
        if okPull and evt == "rednet_message" then
            local action = handleConfigMessage(senderId, msg)
            if action == "config_reloaded" then
                return true
            end
        end
    end
end

print("Starting laboratory terminal...")
openRednet()

-- Гейт ожидания конфига (как BeeOS): пока периферия не настроена -
-- мигаем статусом в консоли; мониторы не занимаем.
local waiting = false
while not hasPeripheralConfig() do
    if not waiting then
        printConfigStatus()
        waiting = true
    end
    waitForConfigMessage()
    reinitAfterConfig()
    if hasPeripheralConfig() then
        break
    else
        printConfigStatus()
        os.sleep(1)
    end
end

-- Конфиг получен. Важно: HeartOS при отправке шлёт freeze -> update_config ->
-- unfreeze. freeze приходит в гейте (frozen=true), а unfreeze может прийти
-- в окно между выходом из гейта и стартом потоков и потеряться. Поэтому
-- после успешного получения конфига гарантированно начинаем работу:
-- сбрасываем frozen (unfreeze, если придёт позже, не повредит).
frozen = false
waitPrepared = false

-- Конфиг получен - показываем обновлённый статус (зелёный [ OK ])
printConfigStatus()

refreshData()
loadState()   -- восстановить состояние после перезапуска
-- Если в бочке нет пчёл, сбросить состояние
if #bees == 0 then
    clearState()
end

setupButtonCallbacks()
sendStatus("free")

-- ==================== ОБРАБОТКА REDNET (общая для обоих потоков) ====================
-- Вызывается из renderLoop И eventLoop, т.к. rednet-сообщение может уйти
-- в любой поток. Обработка неблокирующая (флаги, конфиг, lab_request),
-- поэтому безопасна в renderLoop. Событие достаётся ровно одному потоку,
-- значит обработается один раз (нет потери unfreeze/freeze/конфига).
local function handleRednet(senderId, message)
    if message and message.type == "lab_request" then
        targetHive = message.hive_id
        targetHiveBlock = message.hive_block
        lastSenderId = senderId
        saveState()
        addLogLine(string.format("Received bees from hive %d.", targetHive))
        mode = "wait"
    else
        local action = handleConfigMessage(senderId, message)
        if action == "config_reloaded" then
            -- Конфиг принят от HeartOS - настройка закончена. Снимаем
            -- заморозку самостоятельно (unfreeze мог потеряться в гонке
            -- с отрисовкой/загрузкой), иначе экран ожидания останется
            -- висеть навсегда.
            frozen = false
            waitPrepared = false
            pcall(function()
                reinitAfterConfig()
                -- показываем короткую загрузку после обновления
                local mainMon = peripheral.wrap(lib.peripherals.main_monitor)
                if mainMon then
                    Boot.prepareScreen(mainMon)
                    Boot.show(mainMon, 2)
                end
            end)
        end
    end
end

-- ==================== ПОТОК ОТРИСОВКИ ====================
-- Рисует каждые 0.1с. ВАЖНО: не обрабатывает monitor_touch (иначе долгая
-- задача из кнопки заблокирует поток отрисовки и анимации замирают).
-- rednet_message ОБРАБАТЫВАЕТСЯ ЗДЕСЬ (неблокирующе) - иначе eventLoop
-- может не получить unfreeze, если событие уйдёт в этот поток.
-- Ошибки отрисовки ловятся pcall, чтобы терминал не падал.
local function renderLoop()
    local timer = os.startTimer(0.1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == timer then
            local ok, err = pcall(function()
                frame = frame + 1

                -- Страховка: если заморозка висит дольше FROZEN_MAX_SECONDS
                -- и конфигов давно не было - снимаем (потерянный unfreeze).
                if frozen and frozenSince and
                   (os.clock() - frozenSince > FROZEN_MAX_SECONDS) and
                   (os.clock() - lastConfigActivity > FROZEN_MAX_SECONDS) then
                    frozen = false
                    frozenSince = nil
                    waitPrepared = false
                    print("LAB: auto-unfroze after " .. FROZEN_MAX_SECONDS .. "s (lost unfreeze)")
                end

                if frozen then
                    -- Заморозка: плавный экран ожидания (HUD_Lab_Boot.nfp + полоса)
                    local mainMon = peripheral.wrap(lib.peripherals.main_monitor)
                    if mainMon then
                        if not waitPrepared then
                            Boot.prepareScreen(mainMon)
                            waitPrepared = true
                        end
                        Boot.drawWaitFrame(mainMon)
                    end
                else
                    if waitPrepared then
                        waitPrepared = false
                    end
                    if frame % 20 == 0 then
                        refreshData()
                    end
                    HUD.drawAll(bees, geneCounts, neededCounts, mode, logBuffer, frame, currentStatus)
                    Buttons.drawAll(frame)
                end
            end)

            if not ok then
                print("LAB render error: " .. tostring(err))
                addLogLine("!RENDER ERROR: " .. tostring(err))
            end

            timer = os.startTimer(0.1)
        elseif event == "rednet_message" then
            -- Не блокирует (флаги/состояние) - обрабатываем здесь.
            -- Обязательно pcall: ошибка не должна убить поток отрисовки
            -- (иначе терминал замрёт на полосе ожидания навсегда).
            local okR, errR = pcall(handleRednet, p1, p2)
            if not okR then
                print("LAB rednet error: " .. tostring(errR))
                addLogLine("!REDNET ERROR: " .. tostring(errR))
            end
        end
        -- monitor_touch здесь игнорируется (его обработает eventLoop)
    end
end

-- ==================== ПОТОК ОБРАБОТКИ СОБЫТИЙ ====================
-- Обрабатывает касания и rednet. Ошибки ловятся pcall - терминал не падает.
local function eventLoop()
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        local ok, err = pcall(function()
            if event == "monitor_touch" then
                if not frozen then
                    Buttons.handleTouch(p1, p2, p3)
                end

            elseif event == "rednet_message" then
                handleRednet(p1, p2)
            end
        end)

        if not ok then
            -- Ошибка: выводим в консоль и в лог, но продолжаем работу
            print("LAB error: " .. tostring(err))
            if type(err) == "table" then
                print(textutils.serialize(err))
            end
            addLogLine("!ERROR: " .. tostring(err))
        end
    end
end

parallel.waitForAny(renderLoop, eventLoop, taskWorker)