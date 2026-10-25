-- main_menu.lua
-- HeartOS main menu with BeeOS/LabOS/Hive Map buttons.
-- Layout (title, hint, buttons) is driven by hud.main_menu in heart_config.lua.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local PocketBridge = require("pocket_bridge")

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

        local pairCode = PocketBridge.getPairCode()
        if pairCode then
            MonitorUtil.drawText(mon, 2, 4, "PocketOS pair code: " .. pairCode, colors.yellow)
        else
            local status = PocketBridge.isOnline() and "connected" or "offline"
            MonitorUtil.drawText(mon, 2, 4, "PocketOS " .. status, colors.yellow)
        end

        -- Touch handling
        local ok, event, side, tx, ty = pcall(os.pullEvent)
        if ok and event == "pocket_action" then
            local action = side
            if action == "beeos_create" or action == "beeos_edit" then
                local ConfigBeeOS = require("screens/config_beeos")
                ConfigBeeOS.runPocket(mon, heartConfig, action == "beeos_create" and "create" or "edit")
            elseif action == "labos_create" or action == "labos_edit" then
                local ConfigLabOS = require("screens/config_labos")
                ConfigLabOS.runPocket(mon, heartConfig, action == "labos_create" and "create" or "edit")
            elseif action == "hive_create" or action == "hive_edit" then
                local HiveWizard = require("hive_wizard")
                if action == "hive_create" then HiveWizard.create(mon, heartConfig)
                else HiveWizard.edit(mon, heartConfig) end
            end
            PocketBridge.setWizardBusy(false)
        elseif ok and event == "monitor_touch" and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                PocketBridge.setWizardBusy(true)
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
                PocketBridge.setWizardBusy(false)
            end
        end
    end
end

return MainMenu
