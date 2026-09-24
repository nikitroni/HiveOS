-- hive_menu.lua
-- Submenu for "Configure Hive" (HeartOS main menu).
-- Three columns (Create / Edit / Hive Map) driven by hud.hive config,
-- visually matching the menu_1 background.
-- Actions: Create/Edit -> HiveWizard, Hive Map -> hive_map_view placeholder.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ChatUtil = require("chat_util")
local HiveWizard = require("hive_wizard")

local HiveMenu = {}

-- ==================== ACTIONS ====================

local function onCreate(mon, heartConfig)
    HiveWizard.create(mon, heartConfig)
end

local function onEdit(mon, heartConfig)
    HiveWizard.edit(mon, heartConfig)
end

local function onHiveMap(mon, heartConfig)
    local HiveMapView = require("screens/hive_map_view")
    HiveMapView.run(mon, heartConfig)
end

-- ==================== MAIN ENTRY ====================

function HiveMenu.run(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "hive")
        HudUtil.drawLabel(mon, "hive", "title")

        local hive = HudUtil.get("hive")
        local buttons = {}

        for _, col in ipairs(hive.columns or {}) do
            HudUtil.drawColumn(mon, "hive", col)
            local btn = HudUtil.createButton(mon, "hive", col.id)
            if btn then
                table.insert(buttons, btn)
                MonitorUtil.drawButton(mon, btn, false)
            end
        end

        local backBtn = HudUtil.createButton(mon, "hive", "back")
        if backBtn then
            table.insert(buttons, backBtn)
            MonitorUtil.drawButton(mon, backBtn, false)
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "create" then
                    onCreate(mon, heartConfig)
                elseif pressed.action == "edit" then
                    onEdit(mon, heartConfig)
                elseif pressed.action == "hivemap" then
                    onHiveMap(mon, heartConfig)
                elseif pressed.action == "back" then
                    return
                end
            end
        end
    end
end

return HiveMenu