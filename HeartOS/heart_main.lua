-- heart_main.lua
-- HeartOS entry point (central control terminal)
-- Loads the config, connects the monitor and starts the main menu

local heartConfig = require("heart_config")
local ChatUtil = require("chat_util")
local RednetProtocol = require("rednet_protocol")
local PocketBridge = require("pocket_bridge")

local args = { ... }
local owner = settings.get("hiveos.owner")
if args[1] == "--owner" or type(owner) ~= "string" or owner == "" then
  term.clear()
  term.setCursorPos(1, 1)
  print("HiveOS private notifications")
  print("Enter the apiary owner's exact Minecraft username.")
  repeat
    write("Owner: ")
    owner = read():match("^%s*(.-)%s*$")
    if owner == "" or not owner:match("^[%w_]+$") then
      print("Use a non-empty username containing letters, digits or underscores.")
      owner = nil
    end
  until owner
  settings.set("hiveos.owner", owner)
  if not settings.save() then
    error("Cannot save the apiary owner. Check free disk space.")
  end
end
ChatUtil.setOwner(owner)
ChatUtil.init(nil)
PocketBridge.setFallback(ChatUtil.sendPrivateOnly)
if args[1] == "--pair" and not PocketBridge.resetPairing() then
  error("Cannot reset PocketOS pairing")
end

-- ==================== MONITOR CONNECTION ====================

local SIDES = { "back", "top", "bottom", "left", "right", "front" }

--- Find the main monitor regardless of the side it is attached to.
--- @return table|nil, string|nil wrapped peripheral and its name/side
local function findMonitor()
    local mon = peripheral.find("monitor")
    if mon then
        local name = peripheral.getName(mon)
        if name then
            return mon, name
        end
    end
    for _, side in ipairs(SIDES) do
        if peripheral.getType(side) == "monitor" then
            local wrapped = peripheral.wrap(side)
            if wrapped then
                return wrapped, side
            end
        end
    end
    return nil, nil
end

--- Auto-detect the monitor, waiting for the user to connect one if needed.
local function getMainMonitor()
    local mon, side = findMonitor()
    while not mon do
        term.clear()
        term.setCursorPos(1, 1)
        print("No monitor found. Connect a monitor to any side and press any key to retry.")
        os.pullEvent("key")
        mon, side = findMonitor()
    end
    -- Publish the detected side so every screen can filter monitor_touch events.
    heartConfig.main_monitor = side
    return mon
end

local mainMon = getMainMonitor()

-- ==================== REDNET ====================

local function setupRednet()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and not rednet.isOpen(name) then
      pcall(rednet.open, name)
    end
  end
end

setupRednet()

-- Register as the heartos host so BeeOS/LabOS can find us via rednet.lookup.
local hostOk, hostErr = RednetProtocol.host("heartos", "main")
if not hostOk then
    ChatUtil.sendError("HeartOS: rednet host failed: " .. tostring(hostErr))
end

-- Existing installations receive the owner without repeating device setup.
local ConfigManager = require("config_manager")
for _, role in ipairs({ "beeos", "labos" }) do
  local path = role .. "_config.lua"
  local config = ConfigManager.loadFromFile(path)
  if config and config.peripherals and config.owner ~= owner then
    print("Syncing private notification owner to " .. role .. "...")
    local ok, reason = ConfigManager.sendConfigToTerminal(role, config)
    if ok then
      config.owner = owner
      local saved, saveError = ConfigManager.saveToFile(config, path)
      if not saved then print(tostring(saveError)) end
    else
      print("Owner sync pending for " .. role .. ": " .. tostring(reason))
      print("Start the idle terminal, then restart HeartOS to retry.")
    end
  end
end

-- ==================== UI STARTUP ====================

local textScale = (heartConfig.hud and heartConfig.hud.text_scale) or 1
mainMon.setTextScale(textScale)

local MainMenu = require("screens/main_menu")
parallel.waitForAny(
  function() MainMenu.show(mainMon, heartConfig) end,
  PocketBridge.run
)
