-- heart_main.lua
-- Точка входа HeartOS (центральный терминал управления)
-- Загружает конфиг, подключает монитор и запускает главное меню

local heartConfig = require("heart_config")
local ChatUtil = require("chat_util")

-- ==================== ПОДКЛЮЧЕНИЕ МОНИТОРА ====================

local function getMainMonitor()
    local side = heartConfig.main_monitor
    local mon = peripheral.wrap(side)
    if not mon then
        if not ChatUtil.isAvailable() then
            ChatUtil.init(nil)
        end
        ChatUtil.sendError("HeartOS: Monitor not found on side '" .. side .. "'.\n" ..
              "Please check heart_config.lua and connect a monitor.")
        error("HeartOS: Monitor not found on side '" .. side .. "'.\n" ..
              "Please check heart_config.lua and connect a monitor.")
    end
    return mon
end

local mainMon = getMainMonitor()

-- ==================== REDNET ====================

local function setupRednet()
    local modem = peripheral.find("modem")
    if modem then
        local modemSide = type(modem) == "string" and modem or "back"
        if not rednet.isOpen(modemSide) then
            pcall(rednet.open, modemSide, heartConfig.rednet_channel)
        end
    end
end

setupRednet()

-- ==================== ЗАПУСК ИНТЕРФЕЙСА ====================

mainMon.setTextScale(1)

local MainMenu = require("screens/main_menu")
MainMenu.show(mainMon, heartConfig)