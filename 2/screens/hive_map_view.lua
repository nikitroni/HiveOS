-- hive_map_view.lua
-- Placeholder screen for the visual hive map.
-- This screen will later render the actual hive layout map.
-- For now it only shows a Signal action button, a placeholder button
-- and a Back button (always bottom-left, same position/size everywhere).

local MonitorUtil = require("screens/monitor_util")
local ChatUtil = require("chat_util")

local HiveMapView = {}

function HiveMapView.run(mon, heartConfig)
    local w, h = mon.getSize()

    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        MonitorUtil.drawTitle(mon, "=== Hive Map ===", 2)
        MonitorUtil.drawText(mon, 2, 4, "Visual hive map (TODO)", colors.darkGray)
        MonitorUtil.drawText(mon, 2, 5, "Layout rendering not implemented yet.", colors.darkGray)

        local buttons = {}
        table.insert(buttons, MonitorUtil.createButton(3, 8, 14, " [ Signal ] ", "signal", colors.green))
        table.insert(buttons, MonitorUtil.createButton(3, 11, 14, " [  Slot  ] ", "slot", colors.lightGray))

        for _, btn in ipairs(buttons) do
            MonitorUtil.drawButton(mon, btn, false)
        end

        local backBtn = MonitorUtil.createButton(2, h - 1, 10, " [  Back  ] ", "back", colors.red)
        MonitorUtil.drawButton(mon, backBtn, false)

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local allButtons = {}
            for _, b in ipairs(buttons) do table.insert(allButtons, b) end
            table.insert(allButtons, backBtn)
            local pressed = MonitorUtil.getPressedButton(allButtons, tx, ty)
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