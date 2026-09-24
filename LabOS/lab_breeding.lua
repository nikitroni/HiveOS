-- lab_breeding.lua
-- LabOS breeding module: 3-cycle breeding + incubation flow.
-- Peripheral names come from HeartOS config via lab_config_loader (lab_lib).

local lib = require("lab_lib")

local Breeding = {}

-- ==================== CONSTANTS ====================
local SUNFLOWER = "minecraft:sunflower"
local HONEY_TREAT = "productivebees:honey_treat"
local CAGE_NAMES = {
  ["productivebees:bee_cage"] = true,
  ["productivebees:sturdy_bee_cage"] = true,
}

local REQUIRED_FLOWERS = 6
local REQUIRED_HONEY_TREATS = 60
local REQUIRED_EMPTY_CAGES = 3
local CYCLES = 3
local HONEY_TREATS_PER_CYCLE = 20
local ITEM_WAIT_TIMEOUT = 10
local POLL_INTERVAL = 0.5

-- Breeding chamber slots
local CHAMBER_BABY_SLOT = 1
local CHAMBER_PARENT_SLOTS = { 2, 3 }
local CHAMBER_FLOWER_SLOTS = { 4, 5 }

-- Incubator slots
local INCUBATOR_BABY_SLOT = 1
local INCUBATOR_TREAT_SLOT = 2
local INCUBATOR_ADULT_SLOT = 3

-- MOTD section sign (UTF-8) - same as LAB_main.lua
local SECTION_SIGN = "\194\167"

-- Every side of the relay, so a pulse propagates in all directions.
local RELAY_SIDES = { "front", "back", "left", "right", "top", "bottom" }

-- ==================== HELPERS ====================

-- Chat notification with optional MOTD color code ("c" red, "e" yellow).
local function chatMessage(msg, colorCode)
  local chat = peripheral.wrap(lib.chat_box)
  if not chat then
    print(msg)
    return
  end
  local text = msg
  if colorCode then
    text = SECTION_SIGN .. colorCode .. msg
  end
  pcall(function()
    chat.sendMessage(text, { prefix = "LabOS", prefixColor = "blue", utf8 = true })
  end)
end

local function isCage(item)
  return item ~= nil and CAGE_NAMES[item.name] == true
end

-- A cage holds a bee when its displayed name carries the bee suffix, e.g.
-- "Sturdy Bee Cage (Adamant Bee)". getItemDetail on the breeding chamber
-- does not expose the components table, so displayName is the reliable
-- signal; the components path is kept as a fallback for other peripherals.
local function isCageOccupied(item)
  if not isCage(item) then return false end
  if item.displayName and tostring(item.displayName):match("%(.-Bee%)") then
    return true
  end
  local components = item.components
  if components then
    local custom = components["minecraft:custom_data"]
    local attachments = custom and custom["neoforge:attachments"]
    if attachments and attachments["productivebees:attributes_handler"] then
      return true
    end
  end
  return false
end

local function isCageEmpty(item)
  return isCage(item) and not isCageOccupied(item)
end

-- Read bees from the lab chest via the Block Reader attached to it.
-- Returns ({ { slot = 1-based, age = number|nil, type = string|nil }, ... }, nil)
-- or (nil, errorMessage). Only cages holding a bee (isProductiveBee == 1) count.
local function scanBeesInChest()
  local readerName = lib.peripherals.reader_bee
  if type(readerName) ~= "string" or readerName == "" then
    return nil, "reader_bee not defined in config"
  end
  local reader = peripheral.wrap(readerName)
  if not reader then
    return nil, "bee reader missing"
  end

  local ok, data = pcall(function() return reader.getBlockData() end)
  if not ok or not data or not data.Items then
    return nil, "bee reader returned no data"
  end

  local bees = {}
  for _, item in ipairs(data.Items) do
    if CAGE_NAMES[item.id] then
      local components = item.components
      local custom = components and components["minecraft:custom_data"]
      if custom and custom.isProductiveBee == 1 then
        local age = custom.Age
        if age == nil then age = item.Age end
        for _ = 1, (item.count or 1) do
          table.insert(bees, {
            slot = (item.Slot or 0) + 1,
            age = age,
            type = custom.type,
          })
        end
      end
    end
  end
  return bees, nil
end

-- ==================== RELAY PULSE (auto-detected API) ====================

local function hasMethod(methods, method)
  for _, m in ipairs(methods) do
    if m == method then return true end
  end
  return false
end

-- Probe with a harmless OFF on "front": fails on boolean-only APIs.
local function probeSideOutput(p)
  return pcall(function() p.setOutput("front", false) end) == true
end

-- Returns (method, useSides) for the relay, or (nil, false) when unsupported.
local function detectRelayMethod(name, p)
  local ok, methods = pcall(function() return peripheral.getMethods(name) end)
  if ok and type(methods) == "table" then
    if hasMethod(methods, "setOutput") then
      return "setOutput", probeSideOutput(p)
    end
    if hasMethod(methods, "setBundledOutput") then return "setBundledOutput", false end
    if hasMethod(methods, "setAnalogOutput") then return "setAnalogOutput", false end
    return nil, false
  end
  if type(p.setOutput) == "function" then
    return "setOutput", probeSideOutput(p)
  end
  if type(p.setBundledOutput) == "function" then return "setBundledOutput", false end
  if type(p.setAnalogOutput) == "function" then return "setAnalogOutput", false end
  return nil, false
end

-- Drive the relay ON/OFF through the detected method, covering all sides.
local function setRelayOutput(p, method, useSides, on)
  pcall(function()
    if method == "setOutput" then
      if useSides then
        for _, side in ipairs(RELAY_SIDES) do
          p.setOutput(side, on)
        end
      else
        p.setOutput(on)
      end
    elseif method == "setBundledOutput" then
      p.setBundledOutput(on and colors.white or 0)
    elseif method == "setAnalogOutput" then
      p.setAnalogOutput(on and 15 or 0)
    end
  end)
end

local function countByName(container, itemName)
  local total = 0
  for slot = 1, container.size() do
    local item = container.getItemDetail(slot)
    if item and item.name == itemName then
      total = total + item.count
    end
  end
  return total
end

local function countEmptyCages(container)
  local total = 0
  for slot = 1, container.size() do
    local item = container.getItemDetail(slot)
    if isCageEmpty(item) then
      total = total + item.count
    end
  end
  return total
end

-- Move up to `count` of an item (matched by name) from source into target slot.
-- Returns the amount actually moved.
local function moveByName(source, targetName, itemName, count, toSlot)
  local moved = 0
  for slot = 1, source.size() do
    if moved >= count then break end
    local item = source.getItemDetail(slot)
    if item and item.name == itemName then
      local toTake = math.min(item.count, count - moved)
      local m = source.pushItems(targetName, slot, toTake, toSlot)
      if type(m) == "number" and m > 0 then
        moved = moved + m
      end
    end
  end
  return moved
end

-- Move up to `count` empty cages from source into target slot.
local function moveEmptyCages(source, targetName, count, toSlot)
  local moved = 0
  for slot = 1, source.size() do
    if moved >= count then break end
    local item = source.getItemDetail(slot)
    if isCageEmpty(item) then
      local toTake = math.min(item.count, count - moved)
      local m = source.pushItems(targetName, slot, toTake, toSlot)
      if type(m) == "number" and m > 0 then
        moved = moved + m
      end
    end
  end
  return moved
end

-- Wait until the slot holds an item, polling within the given timeout (seconds).
local function waitForItem(container, slot, timeout)
  local deadline = os.clock() + timeout
  while os.clock() < deadline do
    local item = container.getItemDetail(slot)
    if item then return item end
    sleep(POLL_INTERVAL)
  end
  return nil
end

-- ==================== MAIN ====================
function Breeding.run(logCallback)
  logCallback = logCallback or function() end

  local labChestName = lib.peripherals.lab_chest
  local resourceChestName = lib.peripherals.resource_chest
  local chamberName = lib.peripherals.breeding_chamber
  local incubatorName = lib.peripherals.incubator

  local function fail(msg)
    logCallback("ERROR: " .. msg)
    chatMessage(msg, "c")
    return false
  end

  if not labChestName then return fail("lab_chest not defined in config") end
  if not resourceChestName then return fail("resource_chest not defined in config") end
  if not chamberName then return fail("breeding_chamber not defined in config") end
  if not incubatorName then return fail("incubator not defined in config") end

  local labChest = peripheral.wrap(labChestName)
  local resourceChest = peripheral.wrap(resourceChestName)
  local chamber = peripheral.wrap(chamberName)
  local incubator = peripheral.wrap(incubatorName)

  if not labChest then return fail("lab chest missing") end
  if not resourceChest then return fail("resource chest missing") end
  if not chamber then return fail("breeding chamber missing") end
  if not incubator then return fail("incubator missing") end

  -- ==================== PRE-CHECK (no movement yet) ====================
  logCallback("Pre-check: parents and resources...")

  local parentBees, scanErr = scanBeesInChest()
  if not parentBees then return fail(scanErr) end
  if #parentBees ~= 2 then
    return fail(string.format("lab_chest must contain exactly 2 bee cages (found %d)", #parentBees))
  end

  local adultSlots = {}
  for _, bee in ipairs(parentBees) do
    if bee.age == 0 then
      table.insert(adultSlots, bee.slot)
    end
  end
  if #adultSlots ~= 2 then
    return fail(string.format("lab_chest must contain 2 adult bees (found %d)", #adultSlots))
  end

  -- Safety: the parent slots must be free before the move.
  for _, slot in ipairs(CHAMBER_PARENT_SLOTS) do
    if chamber.getItemDetail(slot) ~= nil then
      return fail(string.format("breeding chamber slot %d is not empty", slot))
    end
  end

  local flowerCount = countByName(resourceChest, SUNFLOWER)
  if flowerCount < REQUIRED_FLOWERS then
    return fail(string.format("not enough sunflowers (need %d, have %d)", REQUIRED_FLOWERS, flowerCount))
  end

  local treatCount = countByName(resourceChest, HONEY_TREAT)
  if treatCount < REQUIRED_HONEY_TREATS then
    return fail(string.format("not enough honey treats (need %d, have %d)", REQUIRED_HONEY_TREATS, treatCount))
  end

  local cageCount = countEmptyCages(resourceChest)
  if cageCount < REQUIRED_EMPTY_CAGES then
    return fail(string.format("not enough empty cages (need %d, have %d)", REQUIRED_EMPTY_CAGES, cageCount))
  end

  logCallback(string.format("Resources OK: flowers %d, treats %d, cages %d", flowerCount, treatCount, cageCount))

  -- ==================== MOVE PARENTS -> CHAMBER ====================
  for i, toSlot in ipairs(CHAMBER_PARENT_SLOTS) do
    local fromSlot = adultSlots[i]
    local moved = labChest.pushItems(chamberName, fromSlot, 1, toSlot)
    if type(moved) ~= "number" or moved < 1 then
      return fail(string.format("failed to move parent bee to chamber slot %d", toSlot))
    end
    if not isCageOccupied(chamber.getItemDetail(toSlot)) then
      return fail(string.format("parent bee missing in chamber slot %d", toSlot))
    end
    logCallback(string.format("  parent bee -> chamber slot %d", toSlot))
  end

  -- ==================== CYCLE LOOP ====================
  local collected = 0
  for cycle = 1, CYCLES do
    logCallback(string.format("Cycle %d/%d", cycle, CYCLES))

    -- 1-2: one sunflower per flower slot
    for _, flowerSlot in ipairs(CHAMBER_FLOWER_SLOTS) do
      local moved = moveByName(resourceChest, chamberName, SUNFLOWER, 1, flowerSlot)
      if moved < 1 then
        return fail(string.format("cycle %d: failed to move sunflower to chamber slot %d", cycle, flowerSlot))
      end
      logCallback(string.format("  sunflower -> chamber slot %d", flowerSlot))
    end

    -- 3: one empty cage into the baby output slot
    local cageMoved = moveEmptyCages(resourceChest, chamberName, 1, CHAMBER_BABY_SLOT)
    if cageMoved < 1 then
      return fail(string.format("cycle %d: failed to move empty cage to chamber slot %d", cycle, CHAMBER_BABY_SLOT))
    end
    logCallback(string.format("  empty cage -> chamber slot %d", CHAMBER_BABY_SLOT))

    -- 4: chamber transfers the baby into incubator slot 1 automatically
    local baby = waitForItem(incubator, INCUBATOR_BABY_SLOT, ITEM_WAIT_TIMEOUT)
    if not baby then
      return fail(string.format("cycle %d: timeout waiting for baby in incubator slot %d", cycle, INCUBATOR_BABY_SLOT))
    end
    logCallback(string.format("  baby appeared: %s", baby.name))

    -- 5: feed honey treats
    local treatsMoved = moveByName(resourceChest, incubatorName, HONEY_TREAT, HONEY_TREATS_PER_CYCLE, INCUBATOR_TREAT_SLOT)
    if treatsMoved < HONEY_TREATS_PER_CYCLE then
      return fail(string.format("cycle %d: honey treats not moved (need %d, moved %d)", cycle, HONEY_TREATS_PER_CYCLE, treatsMoved))
    end
    logCallback(string.format("  %d honey treats -> incubator slot %d", treatsMoved, INCUBATOR_TREAT_SLOT))

    -- 6: wait for the adult bee
    local adult = waitForItem(incubator, INCUBATOR_ADULT_SLOT, ITEM_WAIT_TIMEOUT)
    if not adult then
      return fail(string.format("cycle %d: timeout waiting for adult in incubator slot %d", cycle, INCUBATOR_ADULT_SLOT))
    end
    logCallback(string.format("  adult appeared: %s", adult.name))

    -- 7: move the adult bee into the lab chest
    local adultMoved = incubator.pushItems(labChestName, INCUBATOR_ADULT_SLOT)
    if type(adultMoved) ~= "number" or adultMoved < 1 then
      return fail(string.format("cycle %d: failed to move adult bee to lab chest", cycle))
    end
    collected = collected + adultMoved
    logCallback(string.format("  adult bee -> lab chest (%d/%d)", collected, CYCLES))
  end

  -- ==================== AUTOMATION PULSE ====================
  logCallback(string.format("Breeding cycles done. %d adult bees added to lab chest.", collected))

  local relayName = lib.peripherals.clicker_breeding_relay
  if type(relayName) ~= "string" or relayName == "" then
    return fail("clicker_breeding_relay not defined in config")
  end
  local relay = peripheral.wrap(relayName)
  if not relay then
    return fail("breeding automation relay missing")
  end
  local method, useSides = detectRelayMethod(relayName, relay)
  if not method then
    return fail("breeding automation relay has no output method")
  end
  setRelayOutput(relay, method, useSides, true)
  sleep(1)
  setRelayOutput(relay, method, useSides, false)
  logCallback("Automation pulse sent")
  chatMessage("Automation pulse sent", "e")
  sleep(2)

  -- ==================== FINAL CHECK ====================
  local finalBees = scanBeesInChest()
  local finalCount = finalBees and #finalBees or 0
  if finalCount == 5 then
    logCallback("Breeding complete: 5 bees in lab chest.")
    chatMessage("Breeding complete: 5 bees in lab chest.", "a")
    return true
  end
  return fail(string.format("Parents did not return (bees in lab_chest: %d, expected 5)", finalCount))
end

return Breeding