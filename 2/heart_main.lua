-- heart_main.lua
-- Точка входа HeartOS (центральный терминал управления)
-- Загружает конфиг, подключает монитор и запускает главное меню

local heartConfig = require("heart_config")
local ChatUtil = require("chat_util")
local RednetProtocol = require("rednet_protocol")

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
            pcall(rednet.open, modemSide)
        end
    end
end

setupRednet()

-- Register as the heartos host so BeeOS/LabOS can find us via rednet.lookup.
local hostOk, hostErr = RednetProtocol.host("heartos", "main")
if not hostOk then
    ChatUtil.sendError("HeartOS: rednet host failed: " .. tostring(hostErr))
end

-- ==================== ЗАПУСК ИНТЕРФЕЙСА ====================

local textScale = (heartConfig.hud and heartConfig.hud.text_scale) or 1
mainMon.setTextScale(textScale)

local MainMenu = require("screens/main_menu")
MainMenu.show(mainMon, heartConfig)