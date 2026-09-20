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

  for _, slot in ipairs(CHAMBER_PARENT_SLOTS) do
    local item = chamber.getItemDetail(slot)
    if not isCageOccupied(item) then
      return fail(string.format("breeding chamber slot %d has no parent bee", slot))
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

  -- ==================== FINISH ====================
  logCallback(string.format("Breeding completed. %d adult bees added to lab chest.", collected))
  chatMessage(string.format(
    "Breeding complete: %d bees added to lab chest. Remove the parent bees from breeding chamber slots %d and %d manually.",
    collected, CHAMBER_PARENT_SLOTS[1], CHAMBER_PARENT_SLOTS[2]), "e")
  return true
end

return Breeding