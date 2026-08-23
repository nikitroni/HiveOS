-- main_menu.lua
-- Главное меню HeartOS с кнопками настройки BeeOS, LabOS и Hive Map

local MonitorUtil = require("screens/monitor_util")

local MainMenu = {}

local COLORS = MonitorUtil.COLORS

-- ID терминалов (будут установлены из heartConfig)
local BEEOS_ID = 1
local LABOS_ID = 2

local function openRednet(heartConfig)
    local modem = peripheral.find("modem")
    if modem then
        local modemSide = type(modem) == "string" and modem or "back"
        if not rednet.isOpen(modemSide) then
            pcall(rednet.open, modemSide)
        end
    end
end

function MainMenu.show(mon, heartConfig)
    BEEOS_ID = heartConfig.beeos_id or 1
    LABOS_ID = heartConfig.labos_id or 2
    openRednet(heartConfig)

    local w, h = mon.getSize()

    -- Три центральные кнопки
    local btnY = math.floor(h / 2) - 3
    local btnWidth = 28
    local btnX = math.floor((w - btnWidth) / 2) + 1

    while true do
        MonitorUtil.clearScreen(mon)

        -- Заголовок
        MonitorUtil.drawTitle(mon, "=== HeartOS Control Center ===", 2)

        -- Create buttons
        local buttons = {
            MonitorUtil.createButton(btnX, btnY, btnWidth, " Configure BeeOS  ", "beeos", colors.blue),
            MonitorUtil.createButton(btnX, btnY + 3, btnWidth, " Configure LabOS  ", "labos", colors.blue),
            MonitorUtil.createButton(btnX, btnY + 6, btnWidth, " Hive Map  ", "hivemap", colors.purple),
        }

        -- Рисуем кнопки
        for _, btn in ipairs(buttons) do
            MonitorUtil.drawButton(mon, btn, false)
        end

        -- Подсказки
        MonitorUtil.drawText(mon, 2, h - 1, "Select an option above", colors.darkGray)

        -- Обработка нажатий
        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "beeos" then
                    local ConfigBeeOS = require("screens/config_beeos")
                    ConfigBeeOS.run(mon, heartConfig)
                elseif pressed.action == "labos" then
                    local ConfigLabOS = require("screens/config_labos")
                    ConfigLabOS.run(mon, heartConfig)
                elseif pressed.action == "hivemap" then
                    local HiveMap = require("screens/hive_map")
                    HiveMap.run(mon, heartConfig)
                end
            end
        end
    end
end

return MainMenu