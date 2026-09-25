-- config_labos.lua
-- LabOS configuration screen: Create / Edit / View
-- All scanning logic is in config_wizard.lua (chat interface)
-- Monitor only shows menu and summary

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ConfigManager = require("config_manager")
local ConfigWizard = require("config_wizard")
local DeviceTypes = require("device_types")
local ChatUtil = require("chat_util")

local ConfigLabOS = {}

local COLORS = MonitorUtil.COLORS

local CONFIG_FILE = "labos_config.lua"

--- Send config to LabOS via rednet. If the terminal was frozen (frozen=true) -
--- use update_config + unfreeze. Otherwise - the old request_config.
local function trySendConfig(mon, heartConfig, startY, protocol, frozen)
    protocol = protocol or ConfigManager.PROTOCOL.labos
    local config, _ = ConfigManager.loadFromFile(CONFIG_FILE)

    if not config then
        MonitorUtil.drawText(mon, 2, startY, "No config to send!", COLORS.error)
        return
    end

    local ok, msg
    if frozen then
        ok, msg = ConfigManager.sendUpdateConfig(protocol, config)
        ConfigManager.unfreezeTerminal(protocol)  -- best effort: unfreeze in any case
        if ok then
            ChatUtil.sendSuccess("Config sent to LabOS!")
            MonitorUtil.drawText(mon, 2, startY, "Sent to LabOS!", COLORS.success)
        else
            ChatUtil.sendError("Send failed: " .. msg)
            MonitorUtil.drawText(mon, 2, startY, "Send failed. Saved locally.", COLORS.error)
        end
    else
        ok, msg = ConfigManager.sendInitialConfig(protocol, config)
        if ok then
            ChatUtil.sendSuccess("Config sent to LabOS!")
            MonitorUtil.drawText(mon, 2, startY, "Sent to LabOS!", COLORS.success)
        else
            ChatUtil.sendError("Send failed: " .. msg)
            MonitorUtil.drawText(mon, 2, startY, "Send failed. Saved locally.", COLORS.error)
        end
    end
end

--- Freeze LabOS before editing.
--- Protection against editing a busy terminal is built into freeze:
--- if the terminal is busy with a task, it will reply "wait" (not "frozen") and the wizard
--- will not open. With a free terminal - freeze succeeds.
--- Returns protocol, ok.
local function freezeForEdit(heartConfig)
    local protocol = ConfigManager.PROTOCOL.labos

    local ok, err = ConfigManager.freezeTerminal(protocol)
    if not ok then
        ChatUtil.sendError("LabOS " .. tostring(err))
        return nil, false
    end
    return protocol, true
end

--- Get the color for a group by index (cyclically)
local function getGroupColor(index)
    local colors = { colors.orange, colors.green, colors.blue, colors.purple, colors.yellow, colors.cyan, colors.pink, colors.red }
    return colors[((index - 1) % #colors) + 1]
end

--- View config with paginated monitor display
local function viewLabOSConfig(mon, heartConfig)
    local config, err = ConfigManager.loadFromFile(CONFIG_FILE)

    if not config then
        local w, h = mon.getSize()
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "create_edit")
        MonitorUtil.drawTitle(mon, "===   View LabOS Config  ===", 2)
        MonitorUtil.drawText(mon, 2, 4, "LabOS config: NOT FOUND", COLORS.error)
        MonitorUtil.drawText(mon, 2, 5, tostring(err), COLORS.error)
        MonitorUtil.drawText(mon, 2, h - 1, "Tap to return...", COLORS.darkGray)
        pcall(os.pullEvent, "monitor_touch")
        return
    end

    -- Build ordered items list matching device_types order
    local items = {}
    local idx = 0
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "labos" then
            idx = idx + 1
            local value = (config.peripherals or {})[dt.key]
            table.insert(items, {
                key = dt.key,
                value = value,
                color = getGroupColor(idx),
            })
        end
    end

    MonitorUtil.paginatedView(mon, "===   View LabOS Config  ===", items, heartConfig.main_monitor, nil, nil, "labos")
end

--- Edit: select groups to replace via editByKeys
local function editLabOSConfig(mon, heartConfig)
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
        if dt.group == "labos" then
            table.insert(deviceTypes, dt)
        end
    end

    -- Freeze LabOS during editing
    -- (if the terminal is busy - freezeForEdit returns nil and we don't start the wizard)
    local protocol, frozen = freezeForEdit(heartConfig)
    if not protocol then
        return
    end

    local result = ConfigWizard.editByKeys(
        deviceTypes,
        mon,
        heartConfig.main_monitor,
        "LabOS",
        config.peripherals or {},
        function(updatedDevices)
            local newConfig = {}
            for k, v in pairs(config) do
                newConfig[k] = v
            end
            newConfig.peripherals = updatedDevices
            ConfigManager.saveConfig(newConfig, CONFIG_FILE)
            ChatUtil.sendSuccess("LabOS config updated!")
            trySendConfig(mon, heartConfig, 10, protocol, frozen)
        end
    )

    if result == nil then
        ChatUtil.sendError("Edit cancelled.")
        if frozen then
            ConfigManager.unfreezeTerminal(protocol)
        end
    end
end

--- Create new config (devices only).
--- Sequential wizard: walks LabOS device types in order via createByTypes,
--- asking to connect each device; saves once after the final summary confirm.
local function createLabOSConfig(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    local deviceTypes = {}
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "labos" then
            table.insert(deviceTypes, dt)
        end
    end

    -- Freeze LabOS while creating the config
    -- (if the terminal is busy - freezeForEdit returns nil and we don't start the wizard)
    local protocol, frozen = freezeForEdit(heartConfig)
    if not protocol then
        return
    end

    local result = ConfigWizard.createByTypes(
        deviceTypes,
        mon,
        heartConfig.main_monitor,
        "LabOS (Create)",
        function(devices)
            local config = ConfigManager.createConfig(devices)
            ConfigManager.saveConfig(config, CONFIG_FILE)
            ChatUtil.sendSuccess("LabOS config saved!")
            trySendConfig(mon, heartConfig, 10, protocol, frozen)
        end
    )

    if result == nil then
        ChatUtil.sendError("Configuration cancelled.")
        if frozen then
            ConfigManager.unfreezeTerminal(protocol)
        end
        return
    end
end

-- ==================== MAIN ENTRY ====================

function ConfigLabOS.run(mon, heartConfig)
    if not ChatUtil.isAvailable() then
        ChatUtil.init(nil)
    end

    while true do
        MonitorUtil.clearScreen(mon)
        HudUtil.drawBackground(mon, "labos")
        HudUtil.drawLabel(mon, "labos", "title")

        local labos = HudUtil.get("labos")
        local buttons = {}

        for _, col in ipairs(labos.columns or {}) do
            HudUtil.drawColumn(mon, "labos", col)
            local btn = HudUtil.createButton(mon, "labos", col.id)
            if btn then
                table.insert(buttons, btn)
                MonitorUtil.drawButton(mon, btn, false)
            end
        end

        local backBtn = HudUtil.createButton(mon, "labos", "back")
        if backBtn then
            table.insert(buttons, backBtn)
            MonitorUtil.drawButton(mon, backBtn, false)
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "create" then
                    createLabOSConfig(mon, heartConfig)
                elseif pressed.action == "edit" then
                    editLabOSConfig(mon, heartConfig)
                elseif pressed.action == "view" then
                    viewLabOSConfig(mon, heartConfig)
                elseif pressed.action == "back" then
                    return
                end
            end
        end
    end
end

return ConfigLabOS