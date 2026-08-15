-- BeeOs.lua
local boot = require("boot/boot_start")
local info_screen = require("info/info_start")
local tech_screen = require("tech/tech_start")
local HiveReader = require("hive_reader")
local infoConfig = require("info.HUD_info_config")
local Logger = require("logger")
local labConfig = require("lab_config") 

local DEBUG = false

local target_mons = {
    tech = "monitor_4",
    info = { "monitor_0", "monitor_1", "monitor_2", "monitor_5" }
}

local function getMonitor(name)
    local mon = peripheral.wrap(name)
    if not mon then error("Monitor not found: " .. name) end
    return mon
end

local tech_mon = getMonitor(target_mons.tech)
local info_mon_objects = {}
for _, name in ipairs(target_mons.info) do
    table.insert(info_mon_objects, getMonitor(name))
end

-- Загрузка (длительность 2 секунды для отладки)
local BOOT_DURATION = 2
local boot_threads = {}
table.insert(boot_threads, function() boot.show(tech_mon, BOOT_DURATION) end)
for _, mon in ipairs(info_mon_objects) do
    table.insert(boot_threads, function() boot.show(mon, BOOT_DURATION) end)
end
parallel.waitForAll(table.unpack(boot_threads))

-- Инициализация данных ульев
if not HiveReader.loadConfig("hives.cfg") then
    error("hives.cfg error")
end
HiveReader.connectAll()

-- Открытие Rednet с каналом из конфига
local modemSide = peripheral.find("modem")
if modemSide and type(modemSide) == "string" then
    if rednet.isOpen(modemSide) then
        Logger.log("Rednet already open on " .. modemSide)
    else
        local success, err = pcall(rednet.open, modemSide, labConfig.rednet_channel)
        if success then
            Logger.log("Rednet opened on " .. modemSide .. " with channel " .. labConfig.rednet_channel)
        else
            Logger.log("Failed to open rednet on " .. modemSide .. ": " .. tostring(err))
        end
    end
else
    Logger.log("No modem found. Trying side 'back'")
    local success, err = pcall(rednet.open, "back", labConfig.rednet_channel)
    if success then
        Logger.log("Rednet opened on back with channel " .. labConfig.rednet_channel)
    else
        Logger.log("Failed to open rednet on back: " .. tostring(err))
    end
end
-- Запуск рабочих экранов
parallel.waitForAny(
    function() tech_screen.run(tech_mon) end,
    function()
        local page = 1
        local totalPages = math.ceil(HiveReader.count() / infoConfig.grid.hives_per_page)
        if totalPages < 1 then totalPages = 1 end

        local lastDataUpdate = 0
        local lastPageFlip = os.clock()
        local timings = { data_update = 8, page_flip = 8 }

        Logger.log("Info loop started. Total hives: " .. HiveReader.count() .. ", pages: " .. totalPages)

        local updateTimer = os.startTimer(0.3)

        while true do
            local event, p1 = os.pullEvent()

            if event == "timer" and p1 == updateTimer then
                local now = os.clock()

                totalPages = math.ceil(HiveReader.count() / infoConfig.grid.hives_per_page)
                if totalPages < 1 then totalPages = 1 end

                if now - lastDataUpdate >= timings.data_update then
                    HiveReader.updateIfNeeded()
                    lastDataUpdate = now
                end

                if now - lastPageFlip >= timings.page_flip and totalPages > 1 then
                    page = page + 1
                    if page > totalPages then page = 1 end
                    lastPageFlip = now
                end

                local remaining = math.ceil(lastPageFlip + timings.page_flip - now)
                if remaining < 0 then remaining = 0 end

                local hives = HiveReader.getHives()
                for _, mon in ipairs(info_mon_objects) do
                    info_screen.run(mon, page, totalPages, hives, remaining)
                end

                updateTimer = os.startTimer(0.3)
            end
        end
    end
)