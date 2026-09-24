-- main_menu.lua
-- HeartOS main menu with BeeOS/LabOS/Hive Map buttons.
-- Layout (title, hint, buttons) is driven by hud.main_menu in heart_config.lua.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")

local MainMenu = {}

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
    openRednet(heartConfig)

    while true do
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "main_menu")
        HudUtil.drawLabel(mon, "main_menu", "title")

        local hudMenu = HudUtil.get("main_menu")
        local buttons = {}

        for _, cfgBtn in ipairs(hudMenu.buttons or {}) do
            local btn = HudUtil.createButton(mon, "main_menu", cfgBtn.id)
            if btn then
                table.insert(buttons, btn)
                MonitorUtil.drawButton(mon, btn, false)
            end
        end

        HudUtil.drawLabel(mon, "main_menu", "hint")

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
                    local HiveMenu = require("screens/hive_menu")
                    HiveMenu.run(mon, heartConfig)
                elseif pressed.action == "library" then
                    local LibraryMenu = require("screens/library_menu")
                    LibraryMenu.run(mon, heartConfig)
                end
            end
        end
    end
end

return MainMenu