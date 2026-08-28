-- hive_wizard.lua
-- Wizard for scanning the hives map via in-game chat.
-- For each hive it scans and groups 3 connected peripherals:
--   hive_block   -> the hive block itself (beehive, inventory access)
--   reader_block -> block reader (getBlockData)
--   relay_block  -> redstone relay (setBundledOutput / setAnalogOutput)
-- The result is saved to hives_map.lua and sent to BeeOS via rednet.

local MonitorUtil = require("screens/monitor_util")
local ChatUtil = require("chat_util")
local ConfigWizard = require("config_wizard")
local ConfigManager = require("config_manager")
local DeviceTypes = require("device_types")

local HiveWizard = {}

local COLORS = MonitorUtil.COLORS

local HIVES_FILE = "hives_map.lua"

-- Slot keys inside a hive map entry
local HIVE_SLOTS = { "hive", "reader", "relay" }

-- ==================== CHAT SHORTCUTS ====================

local function chatInfo(msg) ChatUtil.sendInfo(msg) end
local function chatSuccess(msg) ChatUtil.sendSuccess(msg) end
local function chatError(msg) ChatUtil.sendError(msg) end
local function chatStep(msg) ChatUtil.sendStep(msg) end
local function chatHighlight(msg) ChatUtil.sendHighlight(msg) end
local function chatQuestion(msg) ChatUtil.sendQuestion(msg) end
local function chatSeparator() ChatUtil.sendSeparator() end

-- ==================== DEVICE TYPES ====================

-- Extract the three hive device types from device_types.lua (group = "hives")
local HIVE_TYPES = {}
for _, dt in ipairs(DeviceTypes) do
  if dt.group == "hives" then
    HIVE_TYPES[dt.key] = dt
  end
end

-- ==================== HELPERS ====================

--- Trim a list back to a snapshot length (used to roll back partially
--- scanned hives so the same hive can be re-scanned cleanly).
--- @param list table
--- @param snapshot number
local function rollback(list, snapshot)
  while #list > snapshot do
    table.remove(list)
  end
end

--- Scan a single device type, forcing max = 1 (exactly one peripheral).
--- @param key string one of "hive_block" | "reader_block" | "relay_block"
--- @param globalAllDevices table list of all ever-seen peripherals
--- @return string|nil found peripheral name, or nil if skipped/timeout
local function scanOne(key, globalAllDevices)
  local base = HIVE_TYPES[key]
  if not base then
    chatError("Internal error: hive type '" .. key .. "' not found.")
    return nil
  end

  -- Copy with max=1 so scanDeviceType stops after the first confirmed match.
  local singleType = {
    key = base.key,
    label = base.label,
    checkMethods = base.checkMethods,
    max = 1,
    group = base.group,
  }

  local found = ConfigWizard.scanDeviceType(singleType, globalAllDevices)
  if #found > 0 then
    return found[1]
  end
  return nil
end

-- ==================== SEED KNOWN DEVICES ====================

--- Collect peripherals already registered in the existing hives map.
--- Used to prevent adding a hive whose blocks are already mapped.
--- The scope is ONLY the hives map config (single config), as required.
--- @return table, table (array for globalAllDevices, set for lookup)
local function seedCommitted()
  local committed = {}
  local out = {}

  local hives, _ = ConfigManager.loadFromFile(HIVES_FILE)
  if hives then
    for _, hive in ipairs(hives) do
      for _, slot in ipairs(HIVE_SLOTS) do
        local name = hive[slot]
        if type(name) == "string" and not committed[name] then
          committed[name] = true
          table.insert(out, name)
        end
      end
    end
  end

  return out, committed
end

-- ==================== SCAN A SINGLE HIVE ====================

--- Scan all 3 blocks of one hive and group them into a record.
--- On failure it rolls back the global device list so the same hive
--- can be attempted again cleanly.
--- @param globalAllDevices table
--- @param committed table set of already-used peripherals (hives map scope)
--- @return table|nil { hive=, reader=, relay= }
local function scanHive(globalAllDevices, committed)
  local snapshot = #globalAllDevices

  chatSeparator()
  chatHighlight("=== Step 1/3: " .. ChatUtil.device("Hive Block") .. " ===")
  local hiveBlock = scanOne("hive_block", globalAllDevices)
  if not hiveBlock then
    rollback(globalAllDevices, snapshot)
    return nil
  end

  chatSeparator()
  chatHighlight("=== Step 2/3: " .. ChatUtil.device("Hive Reader") .. " ===")
  local readerBlock = scanOne("reader_block", globalAllDevices)
  if not readerBlock then
    rollback(globalAllDevices, snapshot)
    return nil
  end

  chatSeparator()
  chatHighlight("=== Step 3/3: " .. ChatUtil.device("Redstone Relay") .. " ===")
  local relayBlock = scanOne("relay_block", globalAllDevices)
  if not relayBlock then
    rollback(globalAllDevices, snapshot)
    return nil
  end

  local record = {
    hive = hiveBlock,
    reader = readerBlock,
    relay = relayBlock,
  }

  -- Reject any block already mapped in this hives map.
  for _, slot in ipairs(HIVE_SLOTS) do
    local name = record[slot]
    if committed[name] then
      chatError("Device already in use: " .. ChatUtil.device(name, ChatUtil.code("c")) .. ". Please connect another one.")
      rollback(globalAllDevices, snapshot)
      return nil
    end
  end

  return record
end

-- ==================== HIVE ID HELPERS ====================

--- Format a hive id as shown to the player: 1 -> "id01"
--- @param id number
--- @return string
local function hiveIdStr(id)
  return string.format("id%02d", id)
end

--- Parse a chat input like "id01" into a hive id number (1..99).
--- The "id" prefix distinguishes hive ids from accidental numbers.
--- @param input string
--- @return number|nil
local function parseHiveId(input)
  local s = tostring(input or ""):gsub("%s+", ""):lower()
  local num = s:match("^id(%d+)$")
  if not num then return nil end
  local n = tonumber(num)
  if n and n >= 1 and n <= 99 then return n end
  return nil
end

--- Draw the full hives map onto the monitor before saving.
--- @param mon table monitor
--- @param map table array of { id, hive, reader, relay }
local function showSummary(mon, map)
  local w, h = mon.getSize()
  MonitorUtil.clearScreen(mon)
  MonitorUtil.drawTitle(mon, "=== Hive Map Summary ===", 2)
  local y = 4
  for _, hive in ipairs(map) do
    if y > h - 3 then
      MonitorUtil.drawText(mon, 2, y, "(List continued in chat)", COLORS.darkGray)
      break
    end
    MonitorUtil.drawText(mon, 2, y, hiveIdStr(hive.id), COLORS.highlight)
    MonitorUtil.drawText(mon, 4, y + 1, "hive:   " .. tostring(hive.hive), COLORS.text)
    MonitorUtil.drawText(mon, 4, y + 2, "reader: " .. tostring(hive.reader), COLORS.text)
    MonitorUtil.drawText(mon, 4, y + 3, "relay:  " .. tostring(hive.relay), COLORS.text)
    y = y + 4
  end
end

--- Print the hives map summary into chat.
--- @param map table
local function chatSummary(map)
  for _, hive in ipairs(map) do
    chatInfo(hiveIdStr(hive.id) .. "  hive=" .. ChatUtil.device(hive.hive) .. "  reader=" .. ChatUtil.device(hive.reader) .. "  relay=" .. ChatUtil.device(hive.relay))
  end
end

--- Collect one hive's three blocks and ask the player to confirm in chat.
--- @param globalTheirDevices table consecutive sets of peripherals to skip
--- @param committed table set of peripherals already used
--- @param idLabel string label to show (e.g. "id01" or new id)
--- @return table|nil record { hive, reader, relay } or nil if not found/skipped
local function collectHive(globalAllDevices, committed, idLabel)
  chatSeparator()
  chatHighlight("=== Configure hive " .. idLabel .. " ===")
  local record = scanHive(globalAllDevices, committed)
  if not record then
    chatError("Could not collect all 3 blocks for hive " .. idLabel .. ".")
    return nil
  end
  chatSuccess("Blocks collected for " .. idLabel .. ":")
  chatInfo("  hive:   " .. ChatUtil.device(record.hive))
  chatInfo("  reader: " .. ChatUtil.device(record.reader))
  chatInfo("  relay:  " .. ChatUtil.device(record.relay))
  chatQuestion("Accept these blocks? (Y/N)")
  if ChatUtil.waitForYesNo(120) == true then
    for _, slot in ipairs(HIVE_SLOTS) do
      committed[record[slot]] = true
    end
    return record
  end
  chatError("Blocks skipped for " .. idLabel .. ".")
  return nil
end

--- Show a short final message on the monitor and return automatically
--- to the calling menu (no waiting for a tap). Used after save/send,
--- including on failure or cancel.
--- @param mon table monitor
--- @param text string
--- @param color number
local function exitInfo(mon, text, color)
  local w, h = mon.getSize()
  MonitorUtil.clearScreen(mon)
  MonitorUtil.drawTitle(mon, "=== Hive Map Wizard ===", 2)
  MonitorUtil.drawText(mon, 2, 4, text, color)
  os.sleep(2)
end

--- Save the map, send it to BeeOS and show a final monitor message.
--- @param mon table
--- @param heartConfig table
--- @param map table map { id, hive, reader, relay }[]
local function saveAndSend(map, mon, heartConfig)
  local ok, path = ConfigManager.saveConfig(map, HIVES_FILE)
  if ok then
    chatSuccess("Hives map saved to " .. path .. " (" .. #map .. " hives)!")
  else
    chatError("Failed to save hives map: " .. path)
  end

  local targetId = heartConfig.beeos_id or 1
  local ok2, msg2 = ConfigManager.sendInitialConfig(targetId, { command = "hives_map", data = map })
  if ok2 then
    chatSuccess("Hives map sent to BeeOS!")
  else
    chatError("Failed to send hives map: " .. tostring(msg2))
  end

  exitInfo(mon, "Saved " .. #map .. " hives.", ok and ok2 and COLORS.success or COLORS.error)
end

-- ==================== CREATE ====================

--- Full create flow: scan new hives, show a summary, then save and send.
--- @param mon table monitor
--- @param heartConfig table
function HiveWizard.create(mon, heartConfig)
  if not ChatUtil.isAvailable() then
    ChatUtil.init(nil)
  end

  local w, h = mon.getSize()
  MonitorUtil.clearScreen(mon)
  MonitorUtil.drawTitle(mon, "=== Hive Map Wizard: Create ===", 2)
  MonitorUtil.drawText(mon, 2, 4, "Follow instructions in CHAT.", COLORS.highlight)
  os.sleep(3)

  chatSeparator()
  chatHighlight("=== Hive Map Wizard: Create ===")
  chatInfo("Creating a NEW hives map. Current one will be overwritten.")
  chatInfo("For each hive connect 3 blocks (one at a time):")
  chatInfo(" 1) Hive Block         - inventory methods")
  chatInfo(" 2) Hive Reader        - getBlockData")
  chatInfo(" 3) Redstone Relay     - setBundledOutput")
  chatInfo("Answer Y/N in game chat, or type 'skip' to abort a step.")

  local globalAllDevices = {}
  local committed = {}
  local hives = {}

  local addMore = true
  while addMore do
    local idLabel = hiveIdStr(#hives + 1)
    local record = collectHive(globalAllDevices, committed, idLabel)
    if record then
      table.insert(hives, record)
      chatSuccess("Hive '" .. idLabel .. "' added (" .. #hives .. " total).")
    else
      chatError("Hive not added.")
    end
    chatQuestion("Add another hive? (Y/N)")
    addMore = (ChatUtil.waitForYesNo(120) == true)
  end

  if #hives == 0 then
    chatError("No hives collected. Nothing saved.")
    exitInfo(mon, "No hives collected.", COLORS.error)
  else
    -- Build the map and show a full summary on the monitor before saving.
    local map = ConfigManager.createHivesMap(hives)
    showSummary(mon, map)

    chatSeparator()
    chatHighlight("=== Hives Map Summary ===")
    chatSummary(map)
    chatQuestion("Save this map and send to BeeOS? (Y/N)")
    local confirm = ChatUtil.waitForYesNo(120)
    if confirm == true then
      saveAndSend(map, mon, heartConfig)
    else
      chatError("Save cancelled. Hives map was NOT saved.")
      exitInfo(mon, "Save cancelled.", COLORS.error)
    end
  end
end
-- ==================== EDIT ====================

--- Edit flow: the player selects a hive id (id01..id99) in chat.
--- If the id exists its 3 blocks are replaced; if it is new a NEW hive is added.
--- @param mon table monitor
--- @param heartConfig table
function HiveWizard.edit(mon, heartConfig)
  if not ChatUtil.isAvailable() then
    ChatUtil.init(nil)
  end

  local w, h = mon.getSize()
  MonitorUtil.clearScreen(mon)
  MonitorUtil.drawTitle(mon, "=== Hive Map Wizard: Edit ===", 2)
  MonitorUtil.drawText(mon, 2, 4, "Follow instructions in CHAT.", COLORS.highlight)
  os.sleep(3)

  local map, err = ConfigManager.loadFromFile(HIVES_FILE)
  if not map or type(map) ~= "table" or #map == 0 then
    chatError("No hives map to edit: " .. tostring(err))
    exitInfo(mon, "No hives map found.", COLORS.error)
    return
  end

  local existingIds = {}
  for _, hv in ipairs(map) do
    table.insert(existingIds, hiveIdStr(hv.id))
  end

  chatSeparator()
  chatHighlight("=== Hive Map Wizard: Edit ===")
  chatInfo("Existing hives: " .. table.concat(existingIds, ", "))
  chatInfo("Type the hive id to modify (e.g. id01), or 'done' to finish.")
  chatInfo("If the id exists its 3 blocks will be replaced.")
  chatInfo("If the id is new, a NEW hive with that id will be added.")
  chatInfo("Blocks for each hive: Hive Block, Reader, Relay.")

  local globalAllDevices, committed = seedCommitted()
  local changed = 0

  while true do
    chatSeparator()
    chatQuestion("Enter a hive id (id01..id99) or 'done':")
    local input = ChatUtil.waitForAnyMessage(180)
    if input == nil then
      chatInfo("No input. Finishing edit.")
      break
    end

    local token = tostring(input):gsub("%s+", ""):lower()
    if token == "done" or token == "end" or token == "stop" or token == "finish" then
      break
    end

    local idNum = parseHiveId(input)
    if idNum == nil then
      chatError("Invalid input '" .. input .. "'. Use id01..id99 or 'done'.")
    else
      local idLabel = hiveIdStr(idNum)
      local record = collectHive(globalAllDevices, committed, idLabel)
      if record == nil then
        chatError("No blocks collected for " .. idLabel .. ".")
      else
        local found = ConfigManager.findHiveById(map, idNum)
        if found then
          -- Free the previously mapped blocks so they can be reused.
          for _, slot in ipairs(HIVE_SLOTS) do
            committed[found[slot]] = nil
          end
          found.hive = record.hive
          found.reader = record.reader
          found.relay = record.relay
          chatSuccess("Hive " .. idLabel .. " updated (3 blocks replaced).")
        else
          table.insert(map, { id = idNum, hive = record.hive, reader = record.reader, relay = record.relay })
          chatSuccess("NEW hive " .. idLabel .. " added to the map.")
        end
        changed = changed + 1
      end
    end
  end

  if changed == 0 then
    chatError("No changes made. Map not saved.")
    exitInfo(mon, "No changes made.", COLORS.error)
    return
  end

  -- Show the updated map before saving.
  showSummary(mon, map)
  chatSeparator()
  chatHighlight("=== Updated Hives Map Summary ===")
  chatSummary(map)
  chatQuestion("Save and send to BeeOS? (Y/N)")
  local confirm = ChatUtil.waitForYesNo(120)
  if confirm == true then
    saveAndSend(map, mon, heartConfig)
  else
    chatError("Save cancelled. Map was NOT saved.")
    exitInfo(mon, "Save cancelled.", COLORS.error)
  end
end

return HiveWizard