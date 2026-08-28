-- hive_menu.lua
-- Submenu for "Configure Hive" (HeartOS main menu).
-- Screen divided into 4 equal quadrants:
--   top-left      -> Create (start HiveWizard, full create)
--   top-right     -> Edit (select hive id to replace its blocks or add a new hive)
--   bottom half    -> Hive Map (opens the visual map screen placeholder)
-- Back button is always in the same place (bottom-left).

local MonitorUtil = require("screens/monitor_util")
local ChatUtil = require("chat_util")
local HiveWizard = require("hive_wizard")

local HiveMenu = {}

local COLORS = MonitorUtil.COLORS

-- ==================== SECTIONS ====================

--- Compute 4 equal quadrants
local function getQuadrants(w, h)
    local midX = math.floor(w / 2)
    local midY = math.floor(h / 2)
    return {
        tl = { x = 2,       y = 4, w = midX - 2,       h = midY - 5 },  -- top-left
        tr = { x = midX + 1, y = 4, w = w - midX - 2,   h = midY - 5 },  -- top-right
        bot = { x = 2,       y = midY + 1, w = w - 3,   h = h - midY - 2 }, -- bottom
    }
end

local function drawSection(mon, quad, title, descLines, color)
    MonitorUtil.drawText(mon, quad.x, quad.y, "[" .. title .. "]", color)
    local ly = quad.y + 1
    for _, line in ipairs(descLines) do
        MonitorUtil.drawText(mon, quad.x, ly, line, COLORS.text)
        ly = ly + 1
    end
end

local function drawButton(mon, x, y, width, label, action, color)
    local btn = MonitorUtil.createButton(x, y, width, label, action, color)
    MonitorUtil.drawButton(mon, btn, false)
    return btn
end

-- ==================== CREATE ====================

local function onCreate(mon, heartConfig)
    HiveWizard.create(mon, heartConfig)
end

-- ==================== EDIT ====================

local function onEdit(mon, heartConfig)
    HiveWizard.edit(mon, heartConfig)
end

-- ==================== HIVE MAP (placeholder) ====================

local function onHiveMap(mon, heartConfig)
    local HiveMapView = require("screens/hive_map_view")
    HiveMapView.run(mon, heartConfig)
end

-- ==================== MAIN ENTRY ====================

function HiveMenu.run(mon, heartConfig)
    local w, h = mon.getSize()

    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        MonitorUtil.drawTitle(mon, "=== Configure Hive ===", 2)

        local q = getQuadrants(w, h)
        local buttons = {}

        -- Top-left: Create
        drawSection(mon, q.tl, "Create", {
            "Start a NEW hive map",
            "configuration.",
            "All current settings",
            "will be overwritten.",
        }, colors.green)
        table.insert(buttons, drawButton(mon, q.tl.x + 1, q.tl.y + 7, q.tl.w - 2, " [  Start  ] ", "create", colors.gray))

        -- Top-right: Edit
        drawSection(mon, q.tr, "Edit", {
            "Select a hive id (e.g. id01)",
            "to replace its blocks",
            "or add a NEW hive.",
        }, colors.orange)
        table.insert(buttons, drawButton(mon, q.tr.x + 1, q.tr.y + 7, q.tr.w - 2, " [  Start  ] ", "edit", colors.gray))

        -- Bottom: Hive Map
        drawSection(mon, q.bot, "Hive Map", {
            "Open the visual hive map",
            "with Signal button and",
            "placeholder actions.",
        }, colors.purple)
        table.insert(buttons, drawButton(mon, q.bot.x + 1, q.bot.y + 7, q.bot.w - 4, " [  Open  ] ", "hivemap", colors.gray))

        -- Back button: always bottom-left, same position/size
        local backBtn = MonitorUtil.createButton(2, h - 1, 10, " [  Back  ] ", "back", colors.red)
        MonitorUtil.drawButton(mon, backBtn, false)
        table.insert(buttons, backBtn)

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