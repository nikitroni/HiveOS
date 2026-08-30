-- hive_map_view.lua
-- Placeholder screen for the visual hive map.
-- This screen will later render the actual hive layout map.
-- For now it only shows a Signal action button, a placeholder button
-- and a Back button. Background and button positions come from
-- hud.hive_map in heart_config.lua.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ChatUtil = require("chat_util")

local HiveMapView = {}

function HiveMapView.run(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "hive_map")
        HudUtil.drawLabel(mon, "hive_map", "title")
        MonitorUtil.drawText(mon, 2, 4, "Visual hive map (TODO)", colors.darkGray)
        MonitorUtil.drawText(mon, 2, 5, "Layout rendering not implemented yet.", colors.darkGray)

        local buttons = {}

        local signalBtn = HudUtil.createButton(mon, "hive_map", "signal")
        if signalBtn then
            table.insert(buttons, signalBtn)
            MonitorUtil.drawButton(mon, signalBtn, false)
        end

        local slotBtn = HudUtil.createButton(mon, "hive_map", "slot")
        if slotBtn then
            table.insert(buttons, slotBtn)
            MonitorUtil.drawButton(mon, slotBtn, false)
        end

        local backBtn = HudUtil.createButton(mon, "hive_map", "back")
        if backBtn then
            table.insert(buttons, backBtn)
            MonitorUtil.drawButton(mon, backBtn, false)
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "signal" then
                    ChatUtil.sendSuccess("Signal pressed (action stub).")
                elseif pressed.action == "back" then
                    return
                end
                -- slot / future actions: no-op for now
            end
        end
    end
end

return HiveMapView