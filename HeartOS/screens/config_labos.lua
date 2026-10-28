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
local PocketBridge = require("pocket_bridge")

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
        ChatUtil.sendError("LabOS config could not be read on HeartOS.")
        if frozen then ConfigManager.unfreezeTerminal(protocol) end
        os.sleep(2)
        return false
    end

    local ok, msg
    local releaseError = nil
    if frozen then
        ok, msg = ConfigManager.sendUpdateConfig(protocol, config)
        local released, reason = ConfigManager.unfreezeTerminal(protocol)
        if not released then
            released, reason = ConfigManager.unfreezeTerminal(protocol)
        end
        if not released then releaseError = reason end
    else
        ok, msg = ConfigManager.sendInitialConfig(protocol, config)
    end
    if ok and not releaseError then
        ChatUtil.sendSuccess("LabOS confirmed the new config and resumed.")
        MonitorUtil.drawText(mon, 2, startY, "LabOS confirmed new config.", COLORS.success)
    else
        local failure = releaseError and ("LabOS did not confirm unfreeze: " .. tostring(releaseError))
            or ("LabOS did not confirm config: " .. tostring(msg))
        ChatUtil.sendError("Saved on HeartOS. " .. failure)
        MonitorUtil.drawText(mon, 2, startY, "LabOS did not confirm. Check PocketOS.", COLORS.error)
    end
    os.sleep(2)
    return ok and not releaseError
end

--- Freeze LabOS before editing.
--- Protection against editing a busy terminal is built into freeze:
--- if the terminal is busy with a task, it will reply "wait" (not "frozen") and the wizard
--- will not open. With a free terminal - freeze succeeds.
--- Returns protocol, ok.
local function freezeForEdit(heartConfig)
    if not ChatUtil.isPocketReady() then
        ChatUtil.sendError("Open and pair PocketOS before starting the wizard.")
        return nil, false
    end
    local protocol = ConfigManager.PROTOCOL.labos

    local ok, err = ConfigManager.freezeTerminal(protocol)
    if not ok then
        ChatUtil.sendError("LabOS " .. tostring(err))
        return nil, false
    end
    return protocol, true
end

--- View config with paginated monitor display.
--- A missing/incomplete config shows a required-blocks checklist instead of
--- a red "NOT FOUND" error.
local function viewLabOSConfig(mon, heartConfig)
    local config = ConfigManager.loadFromFile(CONFIG_FILE)

    local deviceTypes = {}
    for _, dt in ipairs(DeviceTypes) do
        if dt.group == "labos" then
            table.insert(deviceTypes, dt)
        end
    end

    local peripherals = (config and config.peripherals) or {}
    local filledCount = 0
    local items = {}
    for _, dt in ipairs(deviceTypes) do
        local value = peripherals[dt.key]
        local filled = value ~= nil and value ~= ""
            and not (type(value) == "table" and #value == 0)
        if filled then
            filledCount = filledCount + 1
        end
        local display = filled and value or "(missing)"
        table.insert(items, {
            key = (filled and "[x] " or "[ ] ") .. dt.label,
            value = display,
            color = filled and colors.green or colors.orange,
        })
    end

    table.insert(items, 1, {
        key = "Configured",
        value = tostring(filledCount) .. "/" .. tostring(#deviceTypes),
        color = filledCount == #deviceTypes and colors.green or colors.yellow,
    })
    MonitorUtil.paginatedView(mon, "===   View LabOS Config  ===", items,
        heartConfig.main_monitor, nil, true, "labos")
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
            local saved, saveError = ConfigManager.saveConfig(newConfig, CONFIG_FILE)
            if not saved then
                ChatUtil.sendError("LabOS config was not saved: " .. tostring(saveError))
                if frozen then ConfigManager.unfreezeTerminal(protocol) end
                os.sleep(2)
                return false
            end
            ChatUtil.sendSuccess("LabOS config updated!")
            return trySendConfig(mon, heartConfig, 10, protocol, frozen)
        end
    )

    if result == nil then
        ChatUtil.sendError("Edit cancelled.")
        if frozen then
            ConfigManager.unfreezeTerminal(protocol)
        end
    end
    PocketBridge.endWizard()
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
            local config = ConfigManager.createConfig(devices, deviceTypes)
            local saved, saveError = ConfigManager.saveConfig(config, CONFIG_FILE)
            if not saved then
                ChatUtil.sendError("LabOS config was not saved: " .. tostring(saveError))
                if frozen then ConfigManager.unfreezeTerminal(protocol) end
                os.sleep(2)
                return false
            end
            ChatUtil.sendSuccess("LabOS config saved!")
            return trySendConfig(mon, heartConfig, 10, protocol, frozen)
        end
    )

    if result == nil then
        ChatUtil.sendError("Configuration cancelled.")
        if frozen then
            ConfigManager.unfreezeTerminal(protocol)
        end
        PocketBridge.endWizard()
        return
    end
    PocketBridge.endWizard()
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

function ConfigLabOS.runPocket(mon, heartConfig, action)
    if action == "create" then
        createLabOSConfig(mon, heartConfig)
    elseif action == "edit" then
        editLabOSConfig(mon, heartConfig)
    end
end

return ConfigLabOS
