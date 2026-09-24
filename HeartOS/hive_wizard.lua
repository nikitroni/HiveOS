-- hive_wizard.lua
-- Wizard for scanning the hives map via in-game chat.
-- For each hive it scans and groups 3 connected peripherals:
--   hive_block   -> the hive block itself (beehive, inventory access)
--   reader_block -> block reader (getBlockData)
--   relay_block  -> redstone relay (setBundledOutput / setAnalogOutput)
-- The result is saved to hives_map.lua and sent to BeeOS via rednet.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
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
local function chatWarning(msg) ChatUtil.sendWarning(msg) end
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
--- @param ui table|nil optional { mon, monSide } monitor UI for the Back button
--- @return string|nil found peripheral name, or nil if skipped/timeout
--- @return boolean cancelled true when the user pressed Back on the monitor
local function scanOne(key, globalAllDevices, ui)
  local base = HIVE_TYPES[key]
  if not base then
    chatError("Internal error: hive type '" .. key .. "' not found.")
    return nil, false
  end

  -- Copy with max=1 so scanDeviceType stops after the first confirmed match.
  local singleType = {
    key = base.key,
    label = base.label,
    checkMethods = base.checkMethods,
    max = 1,
    group = base.group,
  }

  local found, cancelled = ConfigWizard.scanDeviceType(singleType, globalAllDevices, ui)
  if cancelled then
    return nil, true
  end
  if #found > 0 then
    return found[1], false
  end
  return nil, false
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

--- Draw the create-step page for one hive slot (no-op without a monitor UI).
--- @param ui table|nil { mon, monSide }
--- @param idLabel string hive label (e.g. "id01")
--- @param stepNum number 1..3
--- @param stepLabel string e.g. "Hive Block"
local function drawHiveStep(ui, idLabel, stepNum, stepLabel)
  if not ui then return end
  ConfigWizard.drawCreateStep(ui.mon, "=== Hive Map Wizard: Create ===", {
    "Hive " .. idLabel,
    "Step " .. stepNum .. "/3: " .. stepLabel,
    "Connect in CHAT. Press Back to cancel.",
  })
end

--- Scan all 3 blocks of one hive and group them into a record.
--- On failure it rolls back the global device list so the same hive
--- can be attempted again cleanly.
--- @param globalAllDevices table
--- @param committed table set of already-used peripherals (hives map scope)
--- @param idLabel string hive label shown on the monitor step page
--- @param ui table|nil optional { mon, monSide } monitor UI for the Back button
--- @return table|nil { hive=, reader=, relay= }
--- @return boolean cancelled true when the user pressed Back on the monitor
local function scanHive(globalAllDevices, committed, idLabel, ui)
  local snapshot = #globalAllDevices

  chatSeparator()
  chatHighlight("=== Step 1/3: " .. ChatUtil.device("Hive Block") .. " ===")
  drawHiveStep(ui, idLabel, 1, "Hive Block")
  local hiveBlock, cancelled1 = scanOne("hive_block", globalAllDevices, ui)
  if cancelled1 then
    rollback(globalAllDevices, snapshot)
    return nil, true
  end
  if not hiveBlock then
    rollback(globalAllDevices, snapshot)
    return nil, false
  end

  chatSeparator()
  chatHighlight("=== Step 2/3: " .. ChatUtil.device("Hive Reader") .. " ===")
  drawHiveStep(ui, idLabel, 2, "Hive Reader")
  local readerBlock, cancelled2 = scanOne("reader_block", globalAllDevices, ui)
  if cancelled2 then
    rollback(globalAllDevices, snapshot)
    return nil, true
  end
  if not readerBlock then
    rollback(globalAllDevices, snapshot)
    return nil, false
  end

  chatSeparator()
  chatHighlight("=== Step 3/3: " .. ChatUtil.device("Redstone Relay") .. " ===")
  drawHiveStep(ui, idLabel, 3, "Redstone Relay")
  local relayBlock, cancelled3 = scanOne("relay_block", globalAllDevices, ui)
  if cancelled3 then
    rollback(globalAllDevices, snapshot)
    return nil, true
  end
  if not relayBlock then
    rollback(globalAllDevices, snapshot)
    return nil, false
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
      return nil, false
    end
  end

  return record, false
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

--- Build paginated-view items from a hive map for monitor display
--- (working-area layout, Prev/Next/Back navigation, colored per hive).
--- @param map table array of { id, hive, reader, relay }
--- @return table items { {key=, value=, color=}, ... }
local function mapToItems(map)
  local items = {}
  local itemColors = { colors.orange, colors.green, colors.blue, colors.purple, colors.magenta, colors.red }
  for i, hive in ipairs(map) do
    table.insert(items, {
      key = hiveIdStr(hive.id),
      value = "hive=" .. tostring(hive.hive) .. "\n......reader=" .. tostring(hive.reader) .. "\n......relay=" .. tostring(hive.relay),
      color = itemColors[((i - 1) % #itemColors) + 1],
    })
  end
  return items
end

--- Print the hives map summary into chat.
--- @param map table
local function chatSummary(map)
  for _, hive in ipairs(map) do
    chatInfo(hiveIdStr(hive.id) .. "  hive=" .. ChatUtil.device(hive.hive) .. "  reader=" .. ChatUtil.device(hive.reader) .. "  relay=" .. ChatUtil.device(hive.relay))
  end
end

--- Collect one hive's three blocks and ask the player to confirm in chat.
--- @param globalAllDevices table consecutive sets of peripherals to skip
--- @param committed table set of peripherals already used
--- @param idLabel string label to show (e.g. "id01" or new id)
--- @param ui table|nil optional { mon, monSide } monitor UI for the Back button
--- @return table|nil record { hive, reader, relay } or nil if not found/skipped
--- @return boolean cancelled true when the user pressed Back on the monitor
local function collectHive(globalAllDevices, committed, idLabel, ui)
  chatSeparator()
  chatHighlight("=== Configure hive " .. idLabel .. " ===")
  local record, cancelled = scanHive(globalAllDevices, committed, idLabel, ui)
  if cancelled then
    return nil, true
  end
  if not record then
    chatError("Could not collect all 3 blocks for hive " .. idLabel .. ".")
    return nil, false
  end
  chatSuccess("Blocks collected for " .. idLabel .. ":")
  chatInfo(" hive:     " .. ChatUtil.device(record.hive))
  chatInfo(" reader: " .. ChatUtil.device(record.reader))
  chatInfo(" relay:   " .. ChatUtil.device(record.relay))
  chatQuestion("Accept these blocks? (Y/N)")
  local accepted
  if ui then
    accepted = ConfigWizard.waitYesNoMonitor(ui.mon, ui.monSide, 120)
  else
    accepted = ChatUtil.waitForYesNo(120)
  end
  if accepted == "cancel" then
    return nil, true
  elseif accepted == true then
    for _, slot in ipairs(HIVE_SLOTS) do
      committed[record[slot]] = true
    end
    return record, false
  end
  chatError("Blocks skipped for " .. idLabel .. ".")
  return nil, false
end

--- Show a short final message on the monitor and return automatically
--- to the calling menu (no waiting for a tap). Used after save/send,
--- including on failure or cancel.
--- @param mon table monitor
--- @param text string
--- @param color number
local function exitInfo(mon, text, color)
  local w, h = mon.getSize()
  local area = HudUtil.getArea(mon)
  local listX, listY, listBg = area.x, area.y, area.bgColor
  MonitorUtil.clearScreen(mon)
  HudUtil.drawBackground(mon, "create_edit")
  HudUtil.createEditTitle(mon, "===   Hive Map Wizard  ===")
  MonitorUtil.drawText(mon, listX, listY, text, color, listBg)
  os.sleep(2)
end

--- Заморозить BeeOS перед запуском мастера (как freezeForEdit в config_beeos).
--- Если BeeOS занят (отправка пчёл) — freeze не пройдёт, мастер не откроется.
--- @param heartConfig table
--- @return string|nil protocol or nil when the terminal rejected the freeze
local function freezeBeeOS(heartConfig)
  local protocol = ConfigManager.PROTOCOL.beeos
  local ok, err = ConfigManager.freezeTerminal(protocol)
  if not ok then
    chatError("BeeOS " .. tostring(err))
    return nil
  end
  return protocol
end

--- Save the map, send it to BeeOS (which is already frozen) and show a
--- final monitor message. Unfreezes in any case (best effort), like
--- trySendConfig in config_beeos.lua.
--- @param mon table
--- @param heartConfig table
--- @param map table map { id, hive, reader, relay }[]
--- @param protocol string BeeOS protocol (frozen before calling)
local function saveAndSend(map, mon, heartConfig, protocol)
  local ok, path = ConfigManager.saveConfig(map, HIVES_FILE)
  if ok then
    chatSuccess("Hives map saved to " .. path .. " (" .. #map .. " hives)!")
  else
    chatError("Failed to save hives map: " .. path)
  end

  local ok2, msg2 = ConfigManager.sendUpdateConfig(protocol, { command = "hives_map", data = map })
  if ok2 then
    chatSuccess("Hives map sent to BeeOS!")
  else
    chatError("Failed to send hives map: " .. tostring(msg2))
  end
  ConfigManager.unfreezeTerminal(protocol)  -- best effort: размораживаем в любом случае

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

  local ui = { mon = mon, monSide = heartConfig.main_monitor }
  ConfigWizard.drawCreateStep(mon, "=== Hive Map Wizard: Create ===", {
    "Follow instructions in CHAT.",
    "Press Back on the monitor to cancel.",
  })
  os.sleep(3)

  -- Замораживаем BeeOS на время мастера (как при Edit конфига BeeOS):
  -- ульи — часть BeeOS, он не должен работать, пока карта редактируется.
  -- Если BeeOS занят — отказ и мастер не открывается.
  local protocol = freezeBeeOS(heartConfig)
  if not protocol then
    return
  end

  chatSeparator()
  chatHighlight("=== Hive Map Wizard: Create ===")
  chatWarning("Creating a NEW hives map. Current one will be overwritten.")
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
    local record, cancelled = collectHive(globalAllDevices, committed, idLabel, ui)
    if cancelled then
      chatError("Create cancelled by user.")
      ConfigManager.unfreezeTerminal(protocol)
      exitInfo(mon, "Create cancelled.", COLORS.error)
      return
    end
    if record then
      table.insert(hives, record)
      chatSuccess("Hive '" .. idLabel .. "' added (" .. #hives .. " total).")
    else
      chatError("Hive not added.")
    end
    chatQuestion("Add another hive? (Y/N)")
    local addMoreResult = ConfigWizard.waitYesNoMonitor(ui.mon, ui.monSide, 120)
    if addMoreResult == "cancel" then
      chatError("Create cancelled by user.")
      ConfigManager.unfreezeTerminal(protocol)
      exitInfo(mon, "Create cancelled.", COLORS.error)
      return
    end
    addMore = (addMoreResult == true)
  end

  if #hives == 0 then
    chatError("No hives collected. Nothing saved.")
    ConfigManager.unfreezeTerminal(protocol)
    exitInfo(mon, "No hives collected.", COLORS.error)
  else
    -- Build the map and show a full summary on the monitor before saving.
    local map = ConfigManager.createHivesMap(hives)

    chatSeparator()
    chatHighlight("=== Hives Map Summary ===")
    chatSummary(map)

    -- Interactive summary: working-area layout with Prev/Next/Back buttons,
    -- waits for Y/N in chat (Back/cancel or timeout = decline).
    local confirm = ConfigWizard.waitYesNoNav(
        mon, heartConfig.main_monitor,
        "=== Hives Map Summary ===",
        mapToItems(map),
        "Save this map and send to BeeOS? (Y/N)", 120
    )
    if confirm == true then
      saveAndSend(map, mon, heartConfig, protocol)
    else
      chatError("Save cancelled. Hives map was NOT saved.")
      ConfigManager.unfreezeTerminal(protocol)
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

  local area = HudUtil.getArea(mon)
  local listX, listY, listBg = area.x, area.y, area.bgColor
  MonitorUtil.clearScreen(mon)
  HudUtil.drawBackground(mon, "create_edit")
  HudUtil.createEditTitle(mon, "=== Hive Map Wizard: Edit ===")
  MonitorUtil.drawText(mon, listX, listY, "Loading current config...", COLORS.highlight, listBg)

  local map, err = ConfigManager.loadFromFile(HIVES_FILE)
  if not map or type(map) ~= "table" or #map == 0 then
    chatError("No hives map to edit: " .. tostring(err))
    exitInfo(mon, "No hives map found.", COLORS.error)
    return
  end

  -- Замораживаем BeeOS на время мастера (как при Edit конфига BeeOS).
  -- Если BeeOS занят — отказ и мастер не открывается.
  local protocol = freezeBeeOS(heartConfig)
  if not protocol then
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
    -- Show the current hives map on the monitor (working-area layout with
    -- Prev/Next/Back buttons) and wait for the player to type a hive id in
    -- chat, press Back, or hit the timeout.
    chatSeparator()
    chatQuestion("Enter a hive id (id01..id99) or 'done':")
    local pageResult, capturedMsg = ConfigWizard.editPageLoop(
        mon, heartConfig.main_monitor,
        "===   Hive Map Edit  ===",
        mapToItems(map),
        nil,   -- linesPerPage -> working area height
        180    -- timeout for typing an id in chat
    )

    if pageResult == "back" then
      chatInfo("Edit cancelled by user.")
      ConfigManager.unfreezeTerminal(protocol)
      exitInfo(mon, "Edit cancelled.", COLORS.error)
      return
    elseif pageResult == "timeout" then
      chatInfo("No input. Finishing edit.")
      break
    end

    local input = capturedMsg or ""
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
    ConfigManager.unfreezeTerminal(protocol)
    exitInfo(mon, "No changes made.", COLORS.error)
    return
  end

  -- Show the updated map on the monitor with Prev/Next/Back and wait for Y/N.
  chatSeparator()
  chatHighlight("=== Updated Hives Map Summary ===")
  chatSummary(map)
  local confirm = ConfigWizard.waitYesNoNav(
      mon, heartConfig.main_monitor,
      "=== Updated Hives Map ===",
      mapToItems(map),
      "Save and send to BeeOS? (Y/N)", 120
  )
  if confirm == true then
    saveAndSend(map, mon, heartConfig, protocol)
  else
    chatError("Save cancelled. Map was NOT saved.")
    ConfigManager.unfreezeTerminal(protocol)
    exitInfo(mon, "Save cancelled.", COLORS.error)
  end
end

return HiveWizard