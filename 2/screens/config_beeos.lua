-- config_beeos.lua
-- BeeOS configuration screen: Create / Edit / View.
-- All scanning logic is in config_wizard.lua (chat interface).
-- Hive map has its own dedicated screen and button on the main menu.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ConfigManager = require("config_manager")
local ConfigWizard = require("config_wizard")
local DeviceTypes = require("device_types")
local ChatUtil = require("chat_util")

local ConfigBeeOS = {}

local COLORS = MonitorUtil.COLORS

local CONFIG_FILE = "beeos_config.lua"

--- Send config to BeeOS via rednet
local function trySendConfig(mon, heartConfig, startY)
    local targetId = heartConfig.beeos_id or 1
    local config, _ = ConfigManager.loadFromFile(CONFIG_FILE)

    if not config then
        MonitorUtil.drawText(mon, 2, startY, "No config to send!", COLORS.error)
        return
    end

    local ok, msg = ConfigManager.sendInitialConfig(targetId, config)
    if ok then
        ChatUtil.sendSuccess("Config sent to BeeOS!")
        MonitorUtil.drawText(mon, 2, startY, "Sent to BeeOS!", COLORS.success)
    else
        ChatUtil.sendError("Send failed: " .. msg)
        MonitorUtil.drawText(mon, 2, startY, "Send failed. Saved locally.", COLORS.error)
    end
end

--- Получить цвет для группы по индексу (циклически)
local function getGroupColor(index)
    local colors = { colors.orange, colors.green, colors.blue, colors.purple, colors.yellow, colors.cyan, colors.pink, colors.lightGray }
    return colors[((index - 1) % #colors) + 1]
end

--- View config (devices only, no hives map) with paginated monitor display
local function viewBeeOSConfig(mon, heartConfig)
    local config, err = ConfigManager.loadFromFile(CONFIG_FILE)

    if not config then
        local w, h = mon.getSize()
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "create_edit")
        MonitorUtil.drawTitle(mon, "===   View BeeOS Config  ===", 2)
        MonitorUtil.drawText(mon, 2, 4, "Config: NOT FOUND", COLORS.error)
        MonitorUtil.drawText(mon, 2, 5, tostring(err), COLORS.error)
        MonitorUtil.drawText(mon, 2, h - 1, "Tap to return...", COLORS.darkGray)
        pcall(os.pullEvent, "monitor_touch")
        return
    end

    -- Build ordered items list matching device_types order
    local items = {}
    local idx = 0
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "beeos" then
            idx = idx + 1
            local value = (config.peripherals or {})[dt.key]
            table.insert(items, {
                key = dt.key,
                value = value,
                color = getGroupColor(idx),
            })
        end
    end

    MonitorUtil.paginatedView(mon, "===   View BeeOS Config  ===", items, heartConfig.main_monitor, nil, nil, "beeos")
end

--- Edit: select groups to replace via editByKeys
local function editBeeOSConfig(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    local config, err = ConfigManager.loadFromFile(CONFIG_FILE)
    if not config then
        ChatUtil.sendError("No config to edit! Create one first: " .. tostring(err))
        MonitorUtil.drawText(mon, 2, 10, "No config to edit!", COLORS.error)
        os.sleep(2)
        return
    end

    local deviceTypes = {}
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "beeos" then
            table.insert(deviceTypes, dt)
        end
    end

    local result = ConfigWizard.editByKeys(
        deviceTypes,
        mon,
        heartConfig.main_monitor,
        "BeeOS",
        config.peripherals or {},
        function(updatedDevices)
            local newConfig = {}
            -- Копируем остальные поля (ключа, метаданные), обновляем peripherals
            for k, v in pairs(config) do
                newConfig[k] = v
            end
            newConfig.peripherals = updatedDevices
            ConfigManager.saveConfig(newConfig, CONFIG_FILE)
            ChatUtil.sendSuccess("BeeOS config updated!")
            trySendConfig(mon, heartConfig, 10)
        end
    )

    if result == nil then
        ChatUtil.sendError("Edit cancelled.")
    end
end

--- Create new config (devices only, no hive map)
local function createBeeOSConfig(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    local deviceTypes = {}
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "beeos" then
            table.insert(deviceTypes, dt)
        end
    end

    local result = ConfigWizard.runWizard(deviceTypes, mon, heartConfig.main_monitor, "BeeOS", function(devices)
        local config = ConfigManager.createConfig(devices)
        ConfigManager.saveConfig(config, CONFIG_FILE)
        ChatUtil.sendSuccess("BeeOS config saved!")
        trySendConfig(mon, heartConfig, 10)
    end)

    if result == nil then
        ChatUtil.sendError("Configuration cancelled.")
    end
end

-- ==================== MAIN ENTRY ====================

function ConfigBeeOS.run(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "beeos")
        HudUtil.drawLabel(mon, "beeos", "title")

        local beeos = HudUtil.get("beeos")
        local buttons = {}

        for _, col in ipairs(beeos.columns or {}) do
            HudUtil.drawColumn(mon, "beeos", col)
            local btn = HudUtil.createButton(mon, "beeos", col.id)
            if btn then
                table.insert(buttons, btn)
                MonitorUtil.drawButton(mon, btn, false)
            end
        end

        local backBtn = HudUtil.createButton(mon, "beeos", "back")
        if backBtn then
            table.insert(buttons, backBtn)
            MonitorUtil.drawButton(mon, backBtn, false)
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "create" then
                    createBeeOSConfig(mon, heartConfig)
                elseif pressed.action == "edit" then
                    editBeeOSConfig(mon, heartConfig)
                elseif pressed.action == "view" then
                    viewBeeOSConfig(mon, heartConfig)
                elseif pressed.action == "back" then
                    return
                end
            end
        end
    end
end

return ConfigBeeOS