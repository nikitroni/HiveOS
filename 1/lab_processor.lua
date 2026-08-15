-- lab_processor.lua
-- Улучшение пчёл с компактным логом и правильной проверкой ресурсов.

local config = require("lab_config")
local Utils = require("lab_utils")
local Genetics = require("lab_genetics")

local Processor = {}

-- Параметры из конфига
local crafters = config.peripherals.crafters
local incubatorName = config.peripherals.incubator
local barrelName = config.peripherals.lab_chest
local indexerName = config.peripherals.bee_indexer
local resourceChestName = config.peripherals.resource_chest   -- ME интерфейс с honey_treat
local geneStartSlot = config.processor.gene_start_slot or 3
local honeyCrafterSlot = config.processor.honey_crafter_slot or 2
local resultCrafterSlot = config.processor.result_crafter_slot or 11
local incubatorBeeSlot = config.processor.incubator_bee_slot or 1
local incubatorGeneSlot = config.processor.incubator_gene_slot or 2
local incubatorResultSlot = config.processor.incubator_result_slot or 3
local craftWait = config.processor.craft_wait or 1
local incubateWait = config.processor.incubate_wait or 5

-- Вспомогательная функция push с защитой от nil
local function push(src, srcName, dstName, srcSlot, count, dstSlot)
    if not src then
        error("push: source is nil (srcName=" .. tostring(srcName) .. ")")
    end
    return src.pushItems(dstName, srcSlot, count, dstSlot) or 0
end

-- Очистка крафтера и инкубатора
local function clearContainer(cont, contName)
    if not cont then return 0 end
    local moved = 0
    for slot = 1, cont.size() do
        local item = cont.getItemDetail(slot)
        if item then
            moved = moved + cont.pushItems(barrelName, slot, item.count)
        end
    end
    return moved
end

-- Получить список недостающих генов для пчелы
local function getMissingGenes(bee)
    local missing = {}
    if bee.productivity ~= Genetics.ELITE.productivity then table.insert(missing, "productivity") end
    if bee.endurance ~= Genetics.ELITE.endurance then table.insert(missing, "endurance") end
    if bee.behavior ~= Genetics.ELITE.behavior then table.insert(missing, "behavior") end
    if bee.weather_tolerance ~= Genetics.ELITE.weather_tolerance then table.insert(missing, "weather_tolerance") end
    return missing
end

-- Поиск слота с чистым геном
function Processor.findGeneSlot(attr)
    local reader = peripheral.wrap(config.peripherals.reader_indexer)
    if not reader then return nil end
    local data = reader.getBlockData()
    if not data or not data.inv or not data.inv.Items then return nil end
    for _, item in ipairs(data.inv.Items) do
        local geneGroup = item.components and item.components["productivebees:gene_group"]
        if geneGroup and geneGroup.purity == 100 and geneGroup.attribute == attr then
            return item.Slot + 1
        end
    end
    return nil
end

-- Улучшение одной пчелы
function Processor.processBee(bee, logCallback)
    logCallback = logCallback or function() end

    local missing = getMissingGenes(bee)
    local geneCount = #missing
    if geneCount == 0 then
        logCallback("bee already elite")
        return true
    end

    logCallback(string.format("upg bee %d miss %d", bee.slot, geneCount))

    local crafterName = crafters[geneCount]
    if not crafterName then
        logCallback("no crafter for " .. geneCount)
        return false
    end
    local crafter = peripheral.wrap(crafterName)
    if not crafter then
        logCallback("crafter not found")
        return false
    end

    -- Очистка
    clearContainer(crafter, crafterName)
    local incubator = peripheral.wrap(incubatorName)
    if incubator then clearContainer(incubator, incubatorName) end

    -- Загрузка генов
    for idx, attr in ipairs(missing) do
        local geneSlot = Processor.findGeneSlot(attr)
        if not geneSlot then
            logCallback("no pure " .. attr)
            return false
        end
        local dstSlot = geneStartSlot + (idx - 1)
        logCallback(string.format(" mv %s %d->%d", attr, geneSlot, dstSlot))
        local moved = push(peripheral.wrap(indexerName), indexerName, crafterName, geneSlot, 1, dstSlot)
        if moved == 0 then
            logCallback(" mv failed")
            return false
        end
    end

    -- Загрузка honey_treat из resource_chest
    local resourceChest = peripheral.wrap(resourceChestName)
    if not resourceChest then
        logCallback("ERROR: resource chest nil")
        return false
    end

    local honeySlot = nil
    for slot = 1, resourceChest.size() do
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == "productivebees:honey_treat" then
            honeySlot = slot
            break
        end
    end
    if not honeySlot then
        logCallback("no honey_treat")
        return false
    end

    logCallback(string.format(" mv honey %d->%d", honeySlot, honeyCrafterSlot))
    local movedHoney = push(resourceChest, resourceChestName, crafterName, honeySlot, 1, honeyCrafterSlot)
    if movedHoney == 0 then
        logCallback("mv honey failed")
        return false
    end

    -- Крафт
    logCallback("wait craft")
    sleep(craftWait)

    local resultItem = crafter.getItemDetail(resultCrafterSlot)
    if not resultItem then
        logCallback("no result")
        return false
    end
    logCallback("craft ok")

    -- Перемещение в инкубатор
    local movedResult = push(crafter, crafterName, incubatorName, resultCrafterSlot, 1, incubatorGeneSlot)
    if movedResult == 0 then
        logCallback("mv result fail")
        return false
    end

    -- Перемещение пчелы
    local barrel = peripheral.wrap(barrelName)
    local movedBee = push(barrel, barrelName, incubatorName, bee.slot, 1, incubatorBeeSlot)
    if movedBee == 0 then
        logCallback("mv bee fail")
        return false
    end

    logCallback("incubating")
    sleep(incubateWait)

    local upgradedBee = incubator.getItemDetail(incubatorResultSlot)
    if not upgradedBee then
        logCallback("no incubated")
        return false
    end
    logCallback("incub done")

    -- Поиск свободного слота в бочке
    local freeSlot = nil
    for slot = 1, barrel.size() do
        if not barrel.getItemDetail(slot) then
            freeSlot = slot
            break
        end
    end
    if not freeSlot then
        logCallback("no free slot")
        return false
    end

    local movedBack = push(incubator, incubatorName, barrelName, incubatorResultSlot, 1, freeSlot)
    if movedBack > 0 then
        logCallback("returned to " .. freeSlot)
    else
        logCallback("return fail")
        return false
    end

    return true
end

-- Улучшение всех неэлитных пчёл
function Processor.processAllBees(logCallback)
    logCallback = logCallback or function() end

    local bees = Utils.getBeesFromBarrel()
    local nonElite = {}
    for _, bee in ipairs(bees) do
        if not Utils.isElite(bee) then
            table.insert(nonElite, bee)
        end
    end

    if #nonElite == 0 then
        logCallback("no bees")
        return 0, 0
    end

    logCallback(string.format("found %d", #nonElite))

    local successCount = 0
    for i, bee in ipairs(nonElite) do
        logCallback(string.format("bee %d/%d", i, #nonElite))
        local ok = Processor.processBee(bee, logCallback)
        if ok then
            successCount = successCount + 1
        else
            logCallback("fail")
        end
        if i < #nonElite then sleep(1) end
    end

    logCallback(string.format("done %d/%d", successCount, #nonElite))
    return successCount, #nonElite
end

return Processor