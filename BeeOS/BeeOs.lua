-- BeeOs.lua
local Boot = require("boot/boot_start")
local info_screen = require("info/info_start")
local tech_screen = require("tech/tech_start")
local HiveReader = require("hive_reader")
local infoConfig = require("info.HUD_info_config")
local Logger = require("logger")
local LabManager = require("lab_manager")

-- ==================== SCREENS ====================

-- All BeeOS monitors from the config (tech_monitor + info_monitors)
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
        --- @type table
        local mon = peripheral.wrap(name)
        if mon then
            mons[#mons + 1] = mon
        end
    end
    return mons
end

-- ==================== INFO (own thread) ====================

-- Separate independent thread for info monitors. Has its own os.pullEvent,
-- its own page-flip timer. The tech loop does NOT call infoTick -
-- each lives on its own. If getBlockData/reading hangs - info is alive, tech is alive.
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

            -- Draw no more often than every 0.25s, with a cache check in info_screen.run.
            -- Data updates are driven by the tech loop (processTick), here only
            -- page flipping - a second data source is not needed.
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

-- Start the working screens: tech + info + non-blocking bee sending to the lab.
-- Returns the tech loop result ("reload"/"freeze"), or nil on error.
local function runScreens(beeCfg)
    local techNames = beeCfg.peripherals.tech_monitor
    local infoNames = beeCfg.peripherals.info_monitors
    if type(techNames) == "string" then techNames = { techNames } end
    if type(infoNames) == "string" then infoNames = { infoNames } end
    techNames = techNames or {}
    infoNames = infoNames or {}

    local techMon = nil
    for _, name in ipairs(techNames) do
        --- @type table
        local mon = peripheral.wrap(name)
        if mon then techMon = mon break end
    end
    if not techMon then
        Logger.log("BeeOS: Tech monitor not found")
        return nil
    end

    local infoMons = {}
    for _, name in ipairs(infoNames) do
        --- @type table
        local mon = peripheral.wrap(name)
        if mon then infoMons[#infoMons + 1] = mon end
    end

    HiveReader.connectAll()

    -- Screen reload: reset the info cache/buffers (monitor objects
    -- after peripheral.wrap may be new) and report status to HeartOS.
    info_screen.reset()
    Boot.setCurrentStatus("free")

    local techOpts = {
        rednetHandler = function(sender, message)
            return Boot.handleConfigMessage(sender, message)
        end,
        sendToLab = LabManager.startSend,
        boot = Boot,
    }

    -- Each subsystem in its own parallel thread: if one hangs,
    -- the others continue. Tech returns a result on reload/freeze.
    -- info+send+read are infinite loops, terminated by parallel when tech exits.
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

-- Prints the current state of the two configs to the computer terminal.
-- Monitors are not used here.
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

-- Exit condition of the wait screen during freeze: unfreeze
local function isUnfrozen()
    return not Boot.isFrozen()
end

-- The stub intercepts rednet messages that would otherwise be lost in
-- waitForConfig (which listens to all rednet_message). lab_complete clears
-- lab_lock.dat even if BeeOS is frozen at that moment.
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
            -- No configs: don't take over others' monitors, wait for HeartOS.
            -- Monitors will only be used after configs are received.
            printConfigStatus()
            Boot.waitForConfig({}, isConfigReady, printConfigStatus, handleStubMessage)

            beeCfg = Boot.loadConfigTable("beeos_config.lua")
            HiveReader.loadHiveMap()
            if not beeCfg or not Boot.loadConfigTable("hives_map.lua") then
                -- Configs never arrived - keep waiting
                os.sleep(1)
            end
        else
            local result = runScreens(beeCfg)

            if result == "freeze" then
                -- HeartOS froze the terminal: show the stub on ALL
                -- BeeOS monitors (tech + info) and wait for unfreeze. A config
                -- arrived during the stub is saved, and full
                -- reinitialization happens after unfreeze (at the start of the loop).
                local monitors = getConfigMonitors(beeCfg)
                Boot.waitForConfig(monitors, isUnfrozen, nil, handleStubMessage)
            elseif result ~= "reload" then
                os.sleep(1)
            end
        end
    end
end

run()