-- lab_processor.lua
-- Bee upgrade with pre-checks, safe cleanup and compact logging.

local lib = require("lab_lib")
local Utils = require("lab_utils")

local Processor = {}

-- Parameters from the lab library
local crafters = lib.peripherals.crafters
local incubatorName = lib.peripherals.incubator
local barrelName = lib.peripherals.lab_chest
local indexerName = lib.peripherals.bee_indexer
local resourceChestName = lib.peripherals.resource_chest   -- ME interface (honey_treat)
local geneStartSlot = lib.processor.gene_start_slot or 3
local honeyCrafterSlot = lib.processor.honey_crafter_slot or 2
local resultCrafterSlot = lib.processor.result_crafter_slot or 11
local incubatorBeeSlot = lib.processor.incubator_bee_slot or 1
local incubatorGeneSlot = lib.processor.incubator_gene_slot or 2
local incubatorResultSlot = lib.processor.incubator_result_slot or 3
local craftTimeout = math.max(lib.processor.craft_timeout or 5, lib.processor.craft_wait or 1)
local incubateTimeout = math.max(lib.processor.incubate_timeout or 10, lib.processor.incubate_wait or 5)

local HONEY_TREAT = "productivebees:honey_treat"
local GENE_GROUP = "productivebees:gene_group"

-- ==================== CHAT ====================
local lastChatMessage = nil
local crafterClogged = false
local incubatorClogged = false
local function chatMessage(msg, isError)
    -- Collapse repeated identical messages so a batch failure does not spam chat
    if msg == lastChatMessage then return end
    lastChatMessage = msg
    Utils.sendChat(msg, isError)
end

-- ==================== SAFE PERIPHERAL HELPERS ====================
--- @param src table wrapped inventory
--- @param dstName string destination peripheral name
--- @param srcSlot number
--- @param count number
--- @param dstSlot number|nil
--- @return number
local function pushOnce(src, dstName, srcSlot, count, dstSlot)
    if not src then return 0 end
    local ok, moved = pcall(function()
        return src.pushItems(dstName, srcSlot, count, dstSlot)
    end)
    if not ok then return 0 end
    return moved or 0
end

-- Move items with a few retries; never raises, returns 0 on failure.
--- @param src table wrapped inventory
--- @param dstName string destination peripheral name
--- @param srcSlot number
--- @param count number
--- @param dstSlot number|nil
--- @param attempts number|nil
--- @return number
local function pushRetry(src, dstName, srcSlot, count, dstSlot, attempts)
    attempts = attempts or 3
    local moved = 0
    for i = 1, attempts do
        moved = pushOnce(src, dstName, srcSlot, count, dstSlot)
        if moved > 0 then return moved end
        if i < attempts then sleep(0.25) end
    end
    return moved
end

--- @param cont table wrapped inventory
--- @return number|nil
local function findFreeSlot(cont)
    if not cont then return nil end
    local okSize, size = pcall(function() return cont.size() end)
    if not okSize then return nil end
    for slot = 1, size do
        local okDetail, item = pcall(function() return cont.getItemDetail(slot) end)
        if okDetail and not item then return slot end
    end
    return nil
end

-- Wait until a slot becomes occupied, or return nil on timeout.
--- @param cont table wrapped inventory
--- @param slot number
--- @param timeout number seconds
--- @return table|nil
local function waitForItem(cont, slot, timeout)
    if not cont then return nil end
    local deadline = os.clock() + (timeout or 0)
    while true do
        local ok, item = pcall(function() return cont.getItemDetail(slot) end)
        if ok and item then return item end
        if os.clock() >= deadline then return nil end
        sleep(0.2)
    end
end

-- Move the listed slots back to their source containers.
-- Only the given slots are inspected (never the whole inventory), and moves are
-- single-attempt (no retries) so an unextractable slot fails fast.
-- Returns: leftover (number), details (string describing stuck slots).
--- @param cont table wrapped inventory
--- @param routes table array of { slot, target }
--- @return number, string
local function clearWithRoutes(cont, routes)
    if not cont then return 0, "" end
    local leftover = 0
    local details = {}
    for _, route in ipairs(routes or {}) do
        local slot = route.slot
        local target = route.target or barrelName
        local okDetail, item = pcall(function() return cont.getItemDetail(slot) end)
        if okDetail and item then
            local moved = 0
            if target then moved = pushOnce(cont, target, slot, item.count) end
            if moved == 0 and target ~= barrelName then
                moved = pushOnce(cont, barrelName, slot, item.count)
            end
            if moved == 0 then
                leftover = leftover + (item.count or 0)
                table.insert(details, string.format("s%d:%s x%d", slot, tostring(item.name), item.count or 0))
            end
        end
    end
    return leftover, table.concat(details, " ")
end

-- Only the crafter output slot is extractable. Input slots cannot be pulled out
-- and their items cannot be inspected by attribute, so the crafter must be empty
-- before use: any occupied input slot means the crafter is clogged.

-- Move a leftover crafted result out of the crafter (output is extractable).
--- @param crafter table wrapped crafter peripheral
--- @return number, string
local function clearCrafterOutput(crafter)
    return clearWithRoutes(crafter, { { slot = resultCrafterSlot, target = indexerName } })
end

-- List occupied crafter input slots (genes + honey). They cannot be cleared.
--- @param crafter table wrapped crafter peripheral
--- @return table
local function crafterClogDetails(crafter)
    local occupied = {}
    local slots = { honeyCrafterSlot, geneStartSlot, geneStartSlot + 1, geneStartSlot + 2, geneStartSlot + 3 }
    for _, slot in ipairs(slots) do
        local ok, item = pcall(function() return crafter.getItemDetail(slot) end)
        if ok and item then
            table.insert(occupied, string.format("s%d:%s x%d", slot, tostring(item.name), item.count or 0))
        end
    end
    return occupied
end

-- Flag the batch as clogged if the crafter inputs still hold anything.
--- @param crafter table wrapped crafter peripheral
local function updateClogFlag(crafter)
    if #crafterClogDetails(crafter) > 0 then
        crafterClogged = true
    end
end

-- Incubator input slots (bee/gene) cannot be extracted either; only the output
-- slot (upgraded bee) can be pulled out.
--- @param incubator table wrapped incubator peripheral
--- @return table
local function incubatorClogDetails(incubator)
    local occupied = {}
    for _, slot in ipairs({ incubatorBeeSlot, incubatorGeneSlot }) do
        local ok, item = pcall(function() return incubator.getItemDetail(slot) end)
        if ok and item then
            table.insert(occupied, string.format("s%d:%s x%d", slot, tostring(item.name), item.count or 0))
        end
    end
    return occupied
end

-- ==================== GENE HELPERS ====================
local function getMissingGenes(bee)
    local missing = {}
    if bee.productivity ~= lib.ELITE.productivity then table.insert(missing, "productivity") end
    if bee.endurance ~= lib.ELITE.endurance then table.insert(missing, "endurance") end
    if bee.behavior ~= lib.ELITE.behavior then table.insert(missing, "behavior") end
    if bee.weather_tolerance ~= lib.ELITE.weather_tolerance then table.insert(missing, "weather_tolerance") end
    return missing
end

-- Find the indexer slot holding a 100% pure gene of the given attribute.
function Processor.findGeneSlot(attr)
    --- @type table
    local reader = peripheral.wrap(lib.peripherals.reader_indexer)
    if not reader then return nil end
    local ok, data = pcall(function() return reader.getBlockData() end)
    if not ok or not data or not data.inv or not data.inv.Items then return nil end
    for _, item in ipairs(data.inv.Items) do
        local geneGroup = item.components and item.components[GENE_GROUP]
        if geneGroup and geneGroup.purity == 100 and geneGroup.attribute == attr then
            return item.Slot + 1
        end
    end
    return nil
end

-- ==================== SINGLE BEE UPGRADE ====================
-- Returns: ok (boolean), reason (string).
function Processor.processBee(bee, logCallback)
    logCallback = logCallback or function() end

    local missing = getMissingGenes(bee)
    local geneCount = #missing
    if geneCount == 0 then
        logCallback("bee already elite")
        return true, "ok"
    end

    logCallback(string.format("upg bee %d miss %d", bee.slot, geneCount))

    local crafterName = crafters and crafters[geneCount]
    if not crafterName then
        logCallback("no crafter for " .. geneCount)
        chatMessage("No crafter for " .. geneCount .. " genes", true)
        return false, "no_crafter"
    end
    --- @type table
    local crafter = peripheral.wrap(crafterName)
    if not crafter then
        logCallback("crafter not found")
        chatMessage("Crafter not found", true)
        return false, "no_crafter"
    end

    --- @type table
    local barrel = peripheral.wrap(barrelName)
    if not barrel then
        logCallback("barrel not found")
        chatMessage("Lab chest not found", true)
        return false, "no_barrel"
    end

    -- Crafter input slots cannot be extracted: any occupancy means it is clogged,
    -- so stop before touching anything and ask for a manual cleanup.
    local clog = crafterClogDetails(crafter)
    if #clog > 0 then
        crafterClogged = true
        logCallback("crafter clogged [" .. table.concat(clog, " ") .. "]")
        chatMessage("Crafter is clogged. Remove items manually.", true)
        return false, "crafter_clogged"
    end

    -- Only the crafter output slot is extractable: clear a leftover result first.
    local outLeft, outDet = clearCrafterOutput(crafter)
    if outLeft > 0 then
        crafterClogged = true
        logCallback("crafter output stuck [" .. outDet .. "]")
        chatMessage("Crafter output is stuck.", true)
        return false, "result_stuck"
    end

    -- Incubator input slots (bee/gene) cannot be extracted: any occupancy means it
    -- is clogged, so stop and ask for a manual cleanup.
    --- @type table
    local incubator = peripheral.wrap(incubatorName)
    if incubator then
        local incClog = incubatorClogDetails(incubator)
        if #incClog > 0 then
            incubatorClogged = true
            logCallback("incubator clogged [" .. table.concat(incClog, " ") .. "]")
            chatMessage("Incubator is clogged. Remove items manually.", true)
            return false, "incubator_clogged"
        end
    end

    -- A free slot is required before crafting
    local freeSlot = findFreeSlot(barrel)
    if not freeSlot then
        logCallback("no free slot")
        chatMessage("No free slot in lab chest", true)
        return false, "no_free_slot"
    end

    -- Incubator output is extractable: return a leftover upgraded bee, then make
    -- sure a free barrel slot is still available for the current bee.
    if incubator then
        local okOut, outBee = pcall(function() return incubator.getItemDetail(incubatorResultSlot) end)
        if okOut and outBee then
            local dst = findFreeSlot(barrel)
            local moved = 0
            if dst then moved = pushRetry(incubator, barrelName, incubatorResultSlot, outBee.count, dst) end
            if moved == 0 then
                incubatorClogged = true
                logCallback("incubator output stuck")
                chatMessage("Incubator output is stuck.", true)
                return false, "incubator_output_stuck"
            end
            freeSlot = findFreeSlot(barrel)
            if not freeSlot then
                logCallback("no free slot")
                chatMessage("No free slot in lab chest", true)
                return false, "no_free_slot"
            end
        end
    end

    -- Load genes
    for idx, attr in ipairs(missing) do
        local geneSlot = Processor.findGeneSlot(attr)
        if not geneSlot then
            logCallback("no pure " .. attr)
            chatMessage("No pure " .. attr .. " gene in indexer", true)
            updateClogFlag(crafter)
            return false, "no_gene"
        end
        local dstSlot = geneStartSlot + (idx - 1)
        logCallback(string.format(" mv %s %d->%d", attr, geneSlot, dstSlot))
        local moved = pushRetry(peripheral.wrap(indexerName), crafterName, geneSlot, 1, dstSlot)
        if moved == 0 then
            crafterClogged = true
            logCallback(" mv failed [" .. attr .. "]")
            chatMessage("Gene move failed. Crafter needs manual cleaning.", true)
            return false, "gene_move"
        end
    end

    -- Load honey_treat
    --- @type table
    local resourceChest = peripheral.wrap(resourceChestName)
    if not resourceChest then
        logCallback("ERROR: resource chest nil")
        chatMessage("Resource chest not found", true)
        updateClogFlag(crafter)
        return false, "no_resource_chest"
    end

    local honeySlot = nil
    local okSize, size = pcall(function() return resourceChest.size() end)
    if okSize then
        for slot = 1, size do
            local okDetail, item = pcall(function() return resourceChest.getItemDetail(slot) end)
            if okDetail and item and item.name == HONEY_TREAT then
                honeySlot = slot
                break
            end
        end
    end
    if not honeySlot then
        logCallback("no honey_treat")
        chatMessage("No honey_treat in resource chest", true)
        updateClogFlag(crafter)
        return false, "no_honey"
    end

    logCallback(string.format(" mv honey %d->%d", honeySlot, honeyCrafterSlot))
    local movedHoney = pushRetry(resourceChest, crafterName, honeySlot, 1, honeyCrafterSlot)
    if movedHoney == 0 then
        crafterClogged = true
        logCallback("mv honey failed")
        chatMessage("Honey_treat move failed. Crafter needs manual cleaning.", true)
        return false, "honey_move"
    end

    -- Craft
    logCallback("wait craft")
    local resultItem = waitForItem(crafter, resultCrafterSlot, craftTimeout)
    if not resultItem then
        crafterClogged = true
        logCallback("no result")
        chatMessage("Craft produced no result. Crafter needs manual cleaning.", true)
        return false, "no_result"
    end
    logCallback("craft ok")

    -- Input slots cannot be extracted, so any item left after the craft means the
    -- crafter is clogged: flag the batch to stop so it can be cleaned manually.
    local clogAfter = crafterClogDetails(crafter)
    if #clogAfter > 0 then
        crafterClogged = true
        logCallback("crafter clogged after craft [" .. table.concat(clogAfter, " ") .. "]")
        chatMessage("Crafter left items after craft. Upgrade will stop.", true)
    end

    -- Move result and bee into the incubator
    --- @type table
    local incubator2 = incubator or peripheral.wrap(incubatorName)
    if not incubator2 then
        logCallback("incubator not found")
        chatMessage("Incubator not found", true)
        return false, "no_incubator"
    end

    local movedResult = pushRetry(crafter, incubatorName, resultCrafterSlot, 1, incubatorGeneSlot)
    if movedResult == 0 then
        logCallback("mv result fail")
        chatMessage("Result move to incubator failed", true)
        return false, "result_move"
    end

    local movedBee = pushRetry(barrel, incubatorName, bee.slot, 1, incubatorBeeSlot)
    if movedBee == 0 then
        incubatorClogged = true
        logCallback("mv bee fail")
        chatMessage("Bee move to incubator failed. Incubator needs manual cleaning.", true)
        return false, "bee_move"
    end

    logCallback("incubating")
    local upgradedBee = waitForItem(incubator2, incubatorResultSlot, incubateTimeout)
    if not upgradedBee then
        incubatorClogged = true
        logCallback("no incubated")
        chatMessage("Incubation produced no result. Incubator needs manual cleaning.", true)
        return false, "no_incubated"
    end
    logCallback("incub done")

    -- Return the upgraded bee to a free barrel slot
    local backSlot = freeSlot
    local okSlot, occupied = pcall(function() return barrel.getItemDetail(backSlot) end)
    if not okSlot or occupied then
        backSlot = findFreeSlot(barrel)
    end
    if not backSlot then
        logCallback("no free slot")
        chatMessage("No free slot in lab chest", true)
        return false, "no_free_slot"
    end

    local movedBack = pushRetry(incubator2, barrelName, incubatorResultSlot, 1, backSlot)
    if movedBack == 0 then
        logCallback("return fail")
        chatMessage("Upgraded bee return failed", true)
        return false, "return_fail"
    end
    logCallback("returned to " .. backSlot)

    -- Verify the returned bee is actually elite
    local verified = false
    for attempt = 1, 3 do
        local returned = Utils.getBeeBySlot(backSlot)
        if returned and Utils.isElite(returned) then
            verified = true
            break
        end
        sleep(0.25)
    end
    if not verified then
        logCallback("verify fail")
        chatMessage("Bee upgrade not verified", true)
        return false, "not_elite"
    end

    return true, "ok"
end

-- ==================== ALL BEES UPGRADE ====================
-- opts (optional): { maxBees = <number> } caps how many bees are upgraded.
-- Returns: successCount, totalCount, partial.
function Processor.processAllBees(logCallback, opts)
    logCallback = logCallback or function() end
    opts = opts or {}
    local maxBees = opts.maxBees
    lastChatMessage = nil
    crafterClogged = false
    incubatorClogged = false

    local bees = Utils.getBeesFromBarrel()
    local nonElite = {}
    for _, bee in ipairs(bees) do
        if not Utils.isElite(bee) then
            table.insert(nonElite, bee)
        end
    end

    local totalCount = #nonElite
    if totalCount == 0 then
        logCallback("no bees")
        return 0, 0, false
    end
    if maxBees and maxBees < totalCount then
        totalCount = maxBees
    end

    logCallback(string.format("found %d", totalCount))

    -- Read the honey stock once and track it locally instead of rescanning per bee
    local _, honeyLeft = Utils.findItem(HONEY_TREAT)

    local successCount = 0
    local partial = false
    for i = 1, totalCount do
        if honeyLeft <= 0 then
            -- Some earlier failures may not have consumed honey, so confirm once
            local _, fresh = Utils.findItem(HONEY_TREAT)
            honeyLeft = fresh
            if honeyLeft <= 0 then
                logCallback("! no honey_treat")
                chatMessage("No honey_treat. Upgrade stopped.", true)
                partial = true
                break
            end
        end
        local bee = nonElite[i]
        logCallback(string.format("bee %d/%d", i, totalCount))
        local ok = Processor.processBee(bee, logCallback)
        if ok then
            successCount = successCount + 1
        else
            logCallback("fail")
            partial = true
        end
        honeyLeft = honeyLeft - 1
        if crafterClogged or incubatorClogged then
            logCallback("! equipment clogged, stopping")
            chatMessage("Upgrade stopped: crafter/incubator needs manual cleaning.", true)
            partial = true
            break
        end
        if i < totalCount then sleep(1) end
    end

    logCallback(string.format("done %d/%d", successCount, totalCount))
    return successCount, totalCount, partial
end

return Processor