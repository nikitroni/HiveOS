-- lab_geneproduction.lua
-- Модуль для производства недостающих генов через редстоун-реле.
-- Проверяет запасы ресурсов, запускает цикл импульсов, мониторит индексатор.
-- Принимает callback для вывода лога на экран.

local lib = require("lab_lib")
local Utils = require("lab_utils")

local GeneProduction = {}

-- ==================== ПАРАМЕТРЫ ИЗ БИБЛИОТЕКИ ЛАБЫ ====================
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
local chatBoxName = lib.chat_box

-- ==================== ОТПРАВКА УВЕДОМЛЕНИЙ В ЧАТ ====================
local SECTION_SIGN = "\194\167"
local function chatMessage(msg, isError)
    local chat = peripheral.wrap(chatBoxName)
    if chat then
        local color = isError and (SECTION_SIGN .. "c") or (SECTION_SIGN .. "a")
        pcall(function()
            chat.sendMessage(color .. msg, { prefix = "LabOS", prefixColor = "blue", utf8 = true })
        end)
    else
        print("[LabOS] " .. msg)
    end
end

-- ==================== ПРОВЕРКА РЕСУРСОВ (каждый тип отдельно) ====================
function GeneProduction.checkResources()
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

    -- Проверяем, что каждого ресурса достаточно (хотя бы 1)
    for _, itemName in ipairs(resourceItems) do
        if counts[itemName] == 0 then
            chatMessage("Missing " .. itemName, true)
            return false
        end
    end
    return true
end

-- ==================== ПРОВЕРКА ДОСТАТОЧНОСТИ ГЕНОВ ====================
function GeneProduction.getShortages()
    local counts = Utils.getGeneCountsFromIndexer()
    local shortages = {}
    for _, attr in ipairs({"productivity", "endurance", "behavior", "weather_tolerance"}) do
        shortages[attr] = math.max(0, targetCount - (counts[attr] or 0))
    end
    return shortages
end

-- ==================== ЗАПУСК ПРОИЗВОДСТВА ОДНОГО ЦИКЛА ====================
function GeneProduction.produceCycle(logCallback)
    logCallback = logCallback or function() end
    local relay = peripheral.wrap(relayName)
    if not relay then
        chatMessage("Redstone relay not found! Production aborted.", true)
        return false
    end

    logCallback(">pulse seq...")

    -- Загружаем параметры цикла из библиотеки
    local rc = lib.relay_cycle
    local phase1_dur = rc.phase1_back_top_duration or 5
    local phase2_delay = rc.phase2_delay or 1
    local phase2_dur = rc.phase2_front_duration or 5
    local pulse2_dur = rc.phase2_front_pulse_duration or 0.5
    local pulse2_int = rc.phase2_front_pulse_interval or 1

    -- Фаза 1: включить back и top постоянно
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

    -- Пауза
    if phase2_delay > 0 then
        logCallback(string.format(" pause %ds", phase2_delay))
        sleep(phase2_delay)
        sleep(0.01)
    end

    -- Фаза 2: пульсация на front
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

-- ==================== ОСНОВНОЙ ЦИКЛ ПРОИЗВОДСТВА ====================
function GeneProduction.runProduction(logCallback)
    logCallback = logCallback or function(msg) print(msg) end

    -- Начальная проверка ресурсов
    logCallback("")
    logCallback("===PROD START===")
    if not GeneProduction.checkResources() then
        chatMessage("Insufficient resources at start. Aborting.", true)
        logCallback("!ERROR: no resources")
        logCallback("===ABORTED===")
        return false
    end
    logCallback("OK resources")

    local shortages = GeneProduction.getShortages()
    local anyMissing = false
    for attr, need in pairs(shortages) do
        if need > 0 then
            anyMissing = true
            logCallback(string.format(" need %d %s", need, attr))
        end
    end

    if not anyMissing then
        logCallback("OK all done")
        logCallback("===FINISHED===")
        chatMessage("Production finished successfully. All genes at target.")
        return true
    end

    logCallback("start loops...")
    logCallback("")

    local maxCycles = 50
    local cycle = 0
    local previousCounts = Utils.getGeneCountsFromIndexer()

    while cycle < maxCycles do
    -- Небольшая пауза перед проверкой, чтобы дать отрисоваться
    sleep(0.01)

    -- Проверка ресурсов перед циклом
    if not GeneProduction.checkResources() then
        chatMessage("Resources exhausted during production. Stopping.", true)
        logCallback("!ERROR: resources out")
        logCallback("===STOPPED===")
        return false
    end

    shortages = GeneProduction.getShortages()
    local totalMissing = 0
    for _, need in pairs(shortages) do
        totalMissing = totalMissing + need
    end

    if totalMissing == 0 then
        logCallback("OK all produced")
        logCallback("===FINISHED===")
        chatMessage("Production finished successfully. All genes at target.")
        return true
    end

    logCallback(string.format("---CYCLE %d---", cycle+1))
    logCallback(string.format(" still %d total", totalMissing))

    local success = GeneProduction.produceCycle(logCallback)
    if not success then
        chatMessage("Production cycle failed. Aborting.", true)
        logCallback("!ERROR: cycle failed")
        logCallback("===ABORTED===")
        return false
    end

    -- Небольшая пауза после цикла перед следующей итерацией
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

    chatMessage("Production stopped after max cycles.", true)
    logCallback("!ERROR: max cycles")
    logCallback("===STOPPED===")
    return false
end

return GeneProduction