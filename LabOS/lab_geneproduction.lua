-- lab_geneproduction.lua
-- Module for producing missing genes via the redstone relay.
-- Checks resource supplies, runs a pulse cycle, monitors the indexer.
-- Accepts a callback for outputting the log to the screen.

local lib = require("lab_lib")
local Utils = require("lab_utils")

local GeneProduction = {}

-- ==================== PARAMETERS FROM THE LAB LIBRARY ====================
local per = lib.peripherals
local relayName = per.relay or "redstone_relay_0"
local relaySides = lib.relay_sides or {"front", "top", "back"}
local pulseDuration = lib.relay_pulse_duration or 2
local pauseBetween = 1
local pauseAfter = lib.relay_pause_after or 3
local targetCount = lib.target_gene_count or 64
local resourceChestName = per.resource_chest
local minResources = lib.min_resources or 32
local resourceItems = lib.resource_items or {
    "minecraft:sunflower",
    "productivebees:honey_treat"
}

-- ==================== SENDING NOTIFICATIONS TO CHAT ====================
local function chatMessage(msg, isError)
    Utils.sendChat(msg, isError)
end

-- ==================== RESOURCE CHECK (each type separately) ====================
function GeneProduction.checkResources()
    --- @type table
    local chest = peripheral.wrap(resourceChestName)
    if not chest then
        chatMessage("Resource chest not found!", true)
        return false
    end

    local counts = {}
    for _, itemName in ipairs(resourceItems) do
        counts[itemName] = 0
    end

    for slot = 1, chest.size() do
        local item = chest.getItemDetail(slot)
        if item then
            for _, allowed in ipairs(resourceItems) do
                if item.name == allowed then
                    counts[allowed] = counts[allowed] + item.count
                    break
                end
            end
        end
    end

    -- Check that each resource is sufficient (at least 1)
    for _, itemName in ipairs(resourceItems) do
        if counts[itemName] == 0 then
            chatMessage("Missing " .. itemName, true)
            return false
        end
    end
    return true
end

-- ==================== GENE SUFFICIENCY CHECK ====================
function GeneProduction.getShortages()
    local counts = Utils.getGeneCountsFromIndexer()
    local shortages = {}
    for _, attr in ipairs({"productivity", "endurance", "behavior", "weather_tolerance"}) do
        shortages[attr] = math.max(0, targetCount - (counts[attr] or 0))
    end
    return shortages
end

-- ==================== SHORTAGES AGAINST EXPLICIT TARGETS ====================
-- Used by the upgrade flow: produce only as many genes as the pending bees need.
function GeneProduction.getShortagesFor(targets)
    local counts = Utils.getGeneCountsFromIndexer()
    local shortages = {}
    for attr, target in pairs(targets or {}) do
        shortages[attr] = math.max(0, (target or 0) - (counts[attr] or 0))
    end
    return shortages
end

-- ==================== STARTING PRODUCTION OF ONE CYCLE ====================
function GeneProduction.produceCycle(logCallback)
    logCallback = logCallback or function() end
    --- @type table
    local relay = peripheral.wrap(relayName)
    if not relay then
        chatMessage("Redstone relay not found! Production aborted.", true)
        return false
    end

    logCallback(">pulse seq...")

    -- Load the cycle parameters from the library
    local rc = lib.relay_cycle
    local phase1_dur = rc.phase1_back_top_duration or 5
    local phase2_delay = rc.phase2_delay or 1
    local phase2_dur = rc.phase2_front_duration or 5
    local pulse2_dur = rc.phase2_front_pulse_duration or 0.5
    local pulse2_int = rc.phase2_front_pulse_interval or 1

    -- Phase 1: turn back and top ON continuously
    logCallback(" phase1: back+top ON")
    local okBack, errBack = pcall(relay.setOutput, "back", true)
    if not okBack then
        chatMessage("Failed to turn ON back: " .. tostring(errBack), true)
        return false
    end
    local okTop, errTop = pcall(relay.setOutput, "top", true)
    if not okTop then
        chatMessage("Failed to turn ON top: " .. tostring(errTop), true)
        return false
    end
    sleep(phase1_dur)
    sleep(0.01)
    pcall(relay.setOutput, "back", false)
    pcall(relay.setOutput, "top", false)

    -- Pause
    if phase2_delay > 0 then
        logCallback(string.format(" pause %ds", phase2_delay))
        sleep(phase2_delay)
        sleep(0.01)
    end

    -- Phase 2: pulse on front
    logCallback(" phase2: front pulses")
    local start2 = os.clock()
    local endPhase2 = start2 + phase2_dur
    while os.clock() < endPhase2 do
        local okFront, errFront = pcall(relay.setOutput, "front", true)
        if not okFront then
            chatMessage("Failed to turn ON front: " .. tostring(errFront), true)
            return false
        end
        sleep(pulse2_dur)
        sleep(0.01)
        pcall(relay.setOutput, "front", false)

        local nextPulse = os.clock() + (pulse2_int - pulse2_dur)
        while os.clock() < nextPulse and os.clock() < endPhase2 do
            sleep(0.05)
        end
    end

    logCallback(">pulses done, wait...")
    sleep(pauseAfter)
    sleep(0.01)
    return true
end

-- Production run.
-- opts (optional):
--   targets   = { attr = count, ... } absolute indexer counts to reach.
--               Without targets the run tops every gene up to target_gene_count
--               (button behaviour). With targets it stops as soon as every listed
--               attribute reaches its own target (upgrade flow).
--   maxCycles = hard safety limit (default 50, or 200 in targeted mode).
-- Returns: reached (boolean), info = { reached, reason, counts }.
function GeneProduction.runProduction(logCallback, opts)
    logCallback = logCallback or function(msg) print(msg) end
    opts = opts or {}
    local targets = opts.targets
    local targeted = type(targets) == "table"
    local maxCycles = opts.maxCycles or (targeted and 200 or 50)

    local function computeShortages()
        if targeted then
            return GeneProduction.getShortagesFor(targets)
        end
        return GeneProduction.getShortages()
    end

    local function makeInfo(reached, reason)
        return { reached = reached, reason = reason, counts = Utils.getGeneCountsFromIndexer() }
    end

    local function finishOk()
        logCallback("OK all produced")
        logCallback("===FINISHED===")
        if not targeted then
            chatMessage("Production finished successfully. All genes at target.")
        end
        return true, makeInfo(true, "ok")
    end

    logCallback("")
    logCallback("===PROD START===")
    if not GeneProduction.checkResources() then
        chatMessage("Insufficient resources at start. Aborting.", true)
        logCallback("!ERROR: no resources")
        logCallback("===ABORTED===")
        return false, makeInfo(false, "resources")
    end
    logCallback("OK resources")

    local shortages = computeShortages()
    local anyMissing = false
    for attr, need in pairs(shortages) do
        if need > 0 then
            anyMissing = true
            logCallback(string.format(" need %d %s", need, attr))
        end
    end

    if not anyMissing then
        return finishOk()
    end

    logCallback("start loops...")
    logCallback("")

    local cycle = 0
    local previousCounts = Utils.getGeneCountsFromIndexer()

    while cycle < maxCycles do
      -- Small pause before the check so the screen can redraw
      sleep(0.01)

      if not GeneProduction.checkResources() then
        chatMessage("Resources exhausted during production. Stopping.", true)
        logCallback("!ERROR: resources out")
        logCallback("===STOPPED===")
        return false, makeInfo(false, "resources")
      end

      shortages = computeShortages()
      local totalMissing = 0
      for _, need in pairs(shortages) do
        totalMissing = totalMissing + need
      end

      if totalMissing == 0 then
        return finishOk()
      end

      logCallback(string.format("---CYCLE %d---", cycle + 1))
      logCallback(string.format(" still %d total", totalMissing))

      local success = GeneProduction.produceCycle(logCallback)
      if not success then
        chatMessage("Production cycle failed. Aborting.", true)
        logCallback("!ERROR: cycle failed")
        logCallback("===ABORTED===")
        return false, makeInfo(false, "relay")
      end

      sleep(0.01)

      local newCounts = Utils.getGeneCountsFromIndexer()
      logCallback(" results:")
      for attr, need in pairs(shortages) do
        local added = (newCounts[attr] or 0) - (previousCounts[attr] or 0)
        if added > 0 then
          logCallback(string.format(" +%d %s", added, attr))
        end
      end
      previousCounts = newCounts
      logCallback("")

      cycle = cycle + 1
      sleep(0.1)
    end

    if not targeted then
      chatMessage("Production stopped after max cycles.", true)
    end
    logCallback("!ERROR: max cycles")
    logCallback("===STOPPED===")
    return false, makeInfo(false, "cycles")
end

return GeneProduction