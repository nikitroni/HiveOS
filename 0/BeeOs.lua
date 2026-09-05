-- BeeOs.lua
local Boot = require("boot/boot_start")
local info_screen = require("info/info_start")
local tech_screen = require("tech/tech_start")
local HiveReader = require("hive_reader")
local infoConfig = require("info.HUD_info_config")
local Logger = require("logger")

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

-- Драйвер info-экранов. Вызывается из tech-цикла по таймеру (0.2с);
-- сам событий НЕ тянет, поэтому rednet-события не теряются.
-- Обновление данных и смена страницы — ОДНО синхронное событие:
-- происходит ровно когда таймер доходит до 0 (принудительный forceUpdate,
-- без внутреннего 10с-регулятора HiveReader, который рассинхронизировал).
local function makeInfoDriver(infoMons)
    local timings = { data_update = 8, page_flip = 8, tick = 0.25 }
    local cycle = timings.page_flip

    local state = {
        page = 1,
        nextEvent = os.clock() + cycle,
        lastTick = 0,
    }

    return function(now)
        -- Не чаще, чем раз в tick
        if now - state.lastTick < timings.tick then return end
        state.lastTick = now

        local totalPages = math.ceil(HiveReader.count() / infoConfig.grid.hives_per_page)
        if totalPages < 1 then totalPages = 1 end

        -- Синхронная смена: таймер истёк -> свежие данные + смена страницы
        if now >= state.nextEvent then
            HiveReader.forceUpdate()
            if totalPages > 1 then
                state.page = state.page + 1
                if state.page > totalPages then state.page = 1 end
            end
            state.nextEvent = now + cycle
        end

        -- Отсчёт до следующей синхронной смены (данные+страница)
        local remaining = math.ceil(state.nextEvent - now)
        if remaining < 0 then remaining = 0 end

        local hives = HiveReader.getHives()
        for _, mon in ipairs(infoMons) do
            info_screen.run(mon, state.page, totalPages, hives, remaining)
        end
    end
end

local function runScreens(beeCfg, skipBoot)
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

    -- Загрузка (пропускается при перезапуске экранов после нового конфига)
    if not skipBoot then
        local allMons = { techMon }
        for _, mon in ipairs(infoMons) do allMons[#allMons + 1] = mon end
        local bootThreads = {}
        for _, mon in ipairs(allMons) do
            table.insert(bootThreads, function() Boot.show(mon, 2) end)
        end
        parallel.waitForAll(table.unpack(bootThreads))
    end

    HiveReader.connectAll()

    -- Сообщаем HeartOS свой статус
    Boot.sendStatus("free")

    local opts = {
        rednetHandler = function(sender, message)
            return Boot.handleConfigMessage(sender, message)
        end,
        infoTick = makeInfoDriver(infoMons),
    }

    -- Единственный владелец событий — tech-цикл (os.pullEvent без фильтра):
    -- rednet_message ВСЕГДА доходит до обработчика конфигов.
    -- info-экран рисуется тиком.
    local ok, res = pcall(tech_screen.run, techMon, opts)
    if ok then
        return res
    end
    Logger.log("TECH error: " .. tostring(res))
    os.sleep(5)
    return nil
end

-- ==================== MAIN LOOP ====================

local hasBooted = false

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
            Boot.waitForConfig({}, isConfigReady, printConfigStatus)

            beeCfg = Boot.loadConfigTable("beeos_config.lua")
            HiveReader.loadHiveMap()
            if not beeCfg or not Boot.loadConfigTable("hives_map.lua") then
                -- Конфиги так и не пришли — продолжаем ждать
                os.sleep(1)
            end
        else
            local skipBoot = hasBooted
            hasBooted = true
            local result = runScreens(beeCfg, skipBoot)

            if result == "freeze" then
                -- HeartOS заморозил терминал: показываем плавный экран
                -- ожидания на ВСЕХ мониторах BeeOS (tech + info) и ждём
                -- конфига или разморозки. Анимация — как при старте.
                local monitors = getConfigMonitors(beeCfg)
                Boot.waitForConfig(monitors, isUnfrozen)
            elseif result ~= "reload" then
                os.sleep(1)
            end
        end
    end
end

run()