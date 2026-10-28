-- main_menu.lua
-- HeartOS main menu with BeeOS/LabOS/Hive Map buttons.
-- Layout (title, hint, buttons) is driven by hud.main_menu in heart_config.lua.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local PocketBridge = require("pocket_bridge")
local ChatUtil = require("chat_util")

local MainMenu = {}

local function centeredText(mon, y, message, color)
    local width = select(1, mon.getSize())
    local text = tostring(message):sub(1, math.max(1, width - 4))
    MonitorUtil.drawText(mon, math.max(1, math.floor((width - #text) / 2) + 1),
        y, text, color, colors.black)
end

local function centeredButton(mon, y, label, action, color)
    local width = math.min(28, select(1, mon.getSize()) - 4)
    local x = math.floor((select(1, mon.getSize()) - width) / 2) + 1
    local padding = math.max(0, math.floor((width - #label) / 2))
    return MonitorUtil.createButton(x, y, width,
        "\n" .. string.rep(" ", padding) .. label, action, color, 3)
end

local function pocketMenu(mon, heartConfig)
    local _, height = mon.getSize()
    local back = MonitorUtil.createButton(3, height - 3, 10, "\n  Back", "back", colors.red, 2)
    local replace = centeredButton(mon, 11, "Pair another PocketOS", "replace", colors.orange)
    local confirm = centeredButton(mon, 15, "Confirm replacement", "confirm", colors.red)
    local sendCode = centeredButton(mon, 11, "Send code to private chat", "send_code", colors.blue)
    local testPrivate = centeredButton(mon, 15, "Test private message", "test_private", colors.cyan)
    local confirming = false
    local note = nil
    local noteColor = colors.white
    local displayedState = nil
    local buttons = { back }
    local refreshTimer = os.startTimer(1)

    while true do
        local id = PocketBridge.getPocketId()
        local online = PocketBridge.isOnline()
        local state = table.concat({ tostring(id), tostring(online),
            tostring(confirming), tostring(note), tostring(noteColor) }, ":")
        if state ~= displayedState then
            displayedState = state
            MonitorUtil.clearScreen(mon)
            centeredText(mon, 2, "PocketOS", colors.yellow)
            if id then
                centeredText(mon, 5, "Paired computer #" .. tostring(id), colors.white)
                centeredText(mon, 7, online and "CONNECTED" or "OFFLINE",
                    online and colors.lime or colors.orange)
            else
                centeredText(mon, 5, "No PocketOS paired", colors.orange)
                centeredText(mon, 7, "Code goes to owner's private chat", colors.white)
            end
            buttons = { back }
            if id then
                if confirming then
                    centeredText(mon, 10, "Old PocketOS will lose access", colors.yellow)
                    MonitorUtil.drawButton(mon, confirm, false)
                    buttons[#buttons + 1] = confirm
                else
                    centeredText(mon, 10, "Lost or replacing the device?", colors.lightGray)
                    MonitorUtil.drawButton(mon, replace, false)
                    buttons[#buttons + 1] = replace
                    MonitorUtil.drawButton(mon, testPrivate, false)
                    buttons[#buttons + 1] = testPrivate
                end
            else
                MonitorUtil.drawButton(mon, sendCode, false)
                buttons[#buttons + 1] = sendCode
                MonitorUtil.drawButton(mon, testPrivate, false)
                buttons[#buttons + 1] = testPrivate
            end
            if note then centeredText(mon, 19, note, noteColor) end
            MonitorUtil.drawButton(mon, back, false)
        end

        local event, side, x, y = os.pullEvent()
        if event == "timer" and side == refreshTimer then
            refreshTimer = os.startTimer(1)
        elseif event == "monitor_touch" and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, x, y)
            if pressed then
                if pressed.action == "back" then return end
                if pressed.action == "test_private" then
                    local delivered = ChatUtil.sendPrivateOnly("PocketOS private message test")
                    note = delivered and "Test sent to " .. tostring(ChatUtil.getOwner())
                        or "Private send failed; check chat box"
                    noteColor = delivered and colors.lime or colors.red
                elseif pressed.action == "send_code" then
                    local delivered = PocketBridge.sendPairCode(ChatUtil.sendPrivateOnly)
                    note = delivered and "Code sent to private chat" or "Private send failed; check chat box"
                    noteColor = delivered and colors.lime or colors.red
                elseif pressed.action == "replace" then
                    confirming = true
                elseif pressed.action == "confirm" then
                    if PocketBridge.resetPairing(ChatUtil.sendPrivateOnly) then
                        confirming = false
                        note = "New code sent to private chat"
                        noteColor = colors.lime
                    else
                        note = "Send or save failed; pairing kept"
                        noteColor = colors.red
                    end
                end
            end
        end
    end
end

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
    local buttons = {}
    local needsFullDraw = true
    local shownPocketText = nil
    local refreshTimer = os.startTimer(1)
    local width = select(1, mon.getSize())
    local badgeWidth = math.min(36, width - 2)
    local badgeX = math.max(1, math.floor((width - badgeWidth) / 2) + 1)

    while true do
        if needsFullDraw then
            MonitorUtil.clearScreen(mon)
            HudUtil.drawBackground(mon, "main_menu")
            HudUtil.drawLabel(mon, "main_menu", "title")
            buttons = {}
            local hudMenu = HudUtil.get("main_menu")
            for _, cfgBtn in ipairs(hudMenu.buttons or {}) do
                local btn = HudUtil.createButton(mon, "main_menu", cfgBtn.id)
                if btn then
                    table.insert(buttons, btn)
                    MonitorUtil.drawButton(mon, btn, false)
                end
            end
            HudUtil.drawLabel(mon, "main_menu", "hint")
            shownPocketText = nil
            needsFullDraw = false
        end

        local pocketText
        local pocketColor
        if PocketBridge.getPairCode() then
            pocketText = "PAIR POCKET [OPEN]"
            pocketColor = colors.orange
        else
            pocketText = PocketBridge.isOnline()
                and "POCKETOS CONNECTED [OPEN]" or "POCKETOS OFFLINE [OPEN]"
            pocketColor = PocketBridge.isOnline() and colors.green or colors.orange
        end
        if pocketText ~= shownPocketText then
            local left = math.max(0, math.floor((badgeWidth - #pocketText) / 2))
            local badge = string.rep(" ", left) .. pocketText
            badge = badge .. string.rep(" ", math.max(0, badgeWidth - #badge))
            MonitorUtil.drawText(mon, badgeX, 4, badge, colors.black, pocketColor)
            shownPocketText = pocketText
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent)
        if ok and event == "timer" and side == refreshTimer then
            refreshTimer = os.startTimer(1)
        elseif ok and event == "monitor_touch" and side == heartConfig.main_monitor then
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
                needsFullDraw = true
                refreshTimer = os.startTimer(1)
            elseif ty == 4 and tx >= badgeX and tx < badgeX + badgeWidth then
                pocketMenu(mon, heartConfig)
                needsFullDraw = true
                refreshTimer = os.startTimer(1)
            end
        end
    end
end

return MainMenu
