-- heart_main.lua
-- HeartOS entry point (central control terminal)
-- Loads the config, connects the monitor and starts the main menu

local heartConfig = require("heart_config")
local ChatUtil = require("chat_util")
local RednetProtocol = require("rednet_protocol")

-- ==================== MONITOR CONNECTION ====================

local SIDES = { "back", "top", "bottom", "left", "right", "front" }

--- Find the main monitor regardless of the side it is attached to.
--- @return table|nil, string|nil wrapped peripheral and its name/side
local function findMonitor()
    local mon = peripheral.find("monitor")
    if mon then
        local name = peripheral.getName(mon)
        if name then
            return mon, name
        end
    end
    for _, side in ipairs(SIDES) do
        if peripheral.getType(side) == "monitor" then
            local wrapped = peripheral.wrap(side)
            if wrapped then
                return wrapped, side
            end
        end
    end
    return nil, nil
end

--- Auto-detect the monitor, waiting for the user to connect one if needed.
local function getMainMonitor()
    local mon, side = findMonitor()
    while not mon do
        term.clear()
        term.setCursorPos(1, 1)
        print("No monitor found. Connect a monitor to any side and press any key to retry.")
        os.pullEvent("key")
        mon, side = findMonitor()
    end
    -- Publish the detected side so every screen can filter monitor_touch events.
    heartConfig.main_monitor = side
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

-- ==================== UI STARTUP ====================

local textScale = (heartConfig.hud and heartConfig.hud.text_scale) or 1
mainMon.setTextScale(textScale)

local MainMenu = require("screens/main_menu")
MainMenu.show(mainMon, heartConfig)