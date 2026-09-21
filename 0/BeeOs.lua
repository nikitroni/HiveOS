-- BeeOs.lua
local Boot = require("boot/boot_start")
local info_screen = require("info/info_start")
local tech_screen = require("tech/tech_start")
local HiveReader = require("hive_reader")
local infoConfig = require("info.HUD_info_config")
local Logger = require("logger")
local LabManager = require("lab_manager")

-- ==================== SCREENS ====================

-- Все мониторы BeeOS из конфига (tech_monitor + info_monitors)
local function getConfigMonitors(beeCfg)
    local names = {}
    local function add(entry)
        if type(entry) == "string" then
            names[#names + 1] = entry
        elseif type(entry) == "table" then
            for _, name in ipairs(entry) do
                names[#names + 1] = name
            end
        end
    end
    local p = beeCfg and beeCfg.peripherals
    if p then
        add(p.tech_monitor)
        add(p.info_monitors)
    end

    local mons = {}
    for _, name in ipairs(names) do
        local mon = peripheral.wrap(name)
        if mon then
            mons[#mons + 1] = mon
        end
    end
    return mons
end

-- ==================== INFO (собственный поток) ====================

-- Отдельный независимый поток для info-мониторов. Имеет свой os.pullEvent,
-- свой таймер перелистывания страниц. Тех-цикл НЕ дёргает infoTick —
-- каждый живёт сам. Если getBlockData/чтение зависло — info жив, tech жив.
local function runInfo(infoMons)
    if #infoMons == 0 then
        while true do os.pullEvent() end
    end

    local page, lastDraw = 1, 0
    local CYCLE = 8
    local flipTimer = os.startTimer(CYCLE)

    while true do
        local ok, err = pcall(function()
            local event, p1 = os.pullEvent()
            local now = os.clock()

            if event == "timer" and p1 == flipTimer then
                flipTimer = os.startTimer(CYCLE)
                local total = math.ceil(HiveReader.count() / infoConfig.grid.hives_per_page)
                if total > 1 then page = page % total + 1 end
            end

            -- Рисуем не чаще 0.25с, с кэш-проверкой в info_screen.run.
            -- Обновление данных ведёт tech-цикл (processTick), здесь только
            -- перелистывание страниц — второй источник чтения не нужен.
            if now - lastDraw >= 0.25 then
                lastDraw = now
                local hives = HiveReader.getHives()
                local total = math.max(1, math.ceil(#hives / infoConfig.grid.hives_per_page))
                if page > total then page = 1 end
                for _, mon in ipairs(infoMons) do
                    info_screen.run(mon, page, total, hives)
                end
            end
        end)
        if not ok then
            Logger.log("INFO: loop error: " .. tostring(err))
        end
    end
end

-- ==================== SCREENS ====================

-- Запуск рабочих экранов: tech + info + неблокирующая отправка пчёл в лабу.
-- Возвращает результат tech-цикла ("reload"/"freeze"), или nil при ошибке.
local function runScreens(beeCfg)
    local techNames = beeCfg.peripherals.tech_monitor
    local infoNames = beeCfg.peripherals.info_monitors
    if type(techNames) == "string" then techNames = { techNames } end
    if type(infoNames) == "string" then infoNames = { infoNames } end
    techNames = techNames or {}
    infoNames = infoNames or {}

    local techMon = nil
    for _, name in ipairs(techNames) do
        local mon = peripheral.wrap(name)
        if mon then techMon = mon break end
    end
    if not techMon then
        Logger.log("BeeOS: Tech monitor not found")
        return nil
    end

    local infoMons = {}
    for _, name in ipairs(infoNames) do
        local mon = peripheral.wrap(name)
        if mon then infoMons[#infoMons + 1] = mon end
    end

    HiveReader.connectAll()

    -- Перезагрузка экранов: сбрасываем кэш/буферы info (объекты-мониторы
    -- после peripheral.wrap могут быть новыми) и сообщаем HeartOS статус.
    info_screen.reset()
    Boot.setCurrentStatus("free")

    local techOpts = {
        rednetHandler = function(sender, message)
            return Boot.handleConfigMessage(sender, message)
        end,
        sendToLab = LabManager.startSend,
        boot = Boot,
    }

    -- Каждая подсистема в своём параллельном потоке: если один завис,
    -- остальные продолжают. Tech возвращает результат при reload/freeze.
    -- info+send+read — бесконечные циклы, их завершает parallel при выходе tech.
    local techResult = nil
    local parOk, parErr = pcall(parallel.waitForAny,
        function() techResult = tech_screen.run(techMon, techOpts); return techResult end,
        function() runInfo(infoMons) end,
        LabManager.sendWorker,
        HiveReader.worker
    )
    if not parOk then
        Logger.log("BeeOS: parallel error: " .. tostring(parErr))
        return nil
    end
    Logger.log("BeeOS: tech finished with result: " .. tostring(techResult))
    return techResult
end

-- ==================== MAIN LOOP ====================

-- Печатает в терминал компьютера текущее состояние двух конфигов.
-- Мониторы при этом не используются.
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

    print("BeeOS: waiting for HeartOS configs")
    print("")
    line("beeos_config.lua", Boot.loadConfigTable("beeos_config.lua") ~= nil)
    line("hives_map.lua",    Boot.loadConfigTable("hives_map.lua") ~= nil)
    print("")
    print("Configs are sent from the HeartOS")
    print("terminal (Configure / Hive Map).")

    term.redirect(old)
end

local function isConfigReady()
    return Boot.loadConfigTable("beeos_config.lua") ~= nil
        and Boot.loadConfigTable("hives_map.lua") ~= nil
end

-- Условие выхода из экрана ожидания при заморозке: разморозка
local function isUnfrozen()
    return not Boot.isFrozen()
end

-- Заглушка перехватывает rednet-сообщения, которые иначе потерялись бы в
-- waitForConfig (он слушает все rednet_message). lab_complete снимает
-- lab_lock.dat, даже если BeeOS в этот момент заморожен.
local function handleStubMessage(sender, message)
    if type(message) == "table" and message.type == "lab_complete" then
        pcall(LabManager.returnBeesToHive, message.hive_id, message.bee_count or 0)
    end
end

local function run()
    while true do
        Boot.openRednet()

        local beeCfg = Boot.loadConfigTable("beeos_config.lua")
        HiveReader.loadHiveMap()
        local mapExists = Boot.loadConfigTable("hives_map.lua") ~= nil

        if not beeCfg or not mapExists then
            -- Конфигов нет: не занимаем чужие мониторы, ждём HeartOS.
            -- Мониторы будут использоваться только после приёма конфигов.
            printConfigStatus()
            Boot.waitForConfig({}, isConfigReady, printConfigStatus, handleStubMessage)

            beeCfg = Boot.loadConfigTable("beeos_config.lua")
            HiveReader.loadHiveMap()
            if not beeCfg or not Boot.loadConfigTable("hives_map.lua") then
                -- Конфиги так и не пришли — продолжаем ждать
                os.sleep(1)
            end
        else
            local result = runScreens(beeCfg)

            if result == "freeze" then
                -- HeartOS заморозил терминал: показываем заглушку на ВСЕХ
                -- мониторах BeeOS (tech + info) и ждём разморозки. Конфиг,
                -- пришедший во время заглушки, сохраняется, а полная
                -- переинициализация идёт после unfreeze (в начале цикла).
                local monitors = getConfigMonitors(beeCfg)
                Boot.waitForConfig(monitors, isUnfrozen, nil, handleStubMessage)
            elseif result ~= "reload" then
                os.sleep(1)
            end
        end
    end
end

run()