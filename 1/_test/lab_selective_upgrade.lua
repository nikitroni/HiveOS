-- lab_selective_upgrade.lua
-- Сканирует бочку, находит неэлитных пчёл, определяет недостающие гены,
-- выбирает крафтер по количеству недостающих генов (1-4),
-- крафтит улучшатель и применяет его к пчеле в инкубаторе.

local logsDir = "logs"
if not fs.exists(logsDir) then fs.makeDir(logsDir) end
local reportFile = logsDir .. "/lab_selective_upgrade.txt"

local function log(...)
    local f = fs.open(reportFile, "a")
    if f then
        for i = 1, select('#', ...) do
            f.write(tostring(select(i, ...)) .. " ")
        end
        f.write("\n")
        f.close()
    end
end

local function clearLog()
    local f = fs.open(reportFile, "w")
    if f then f.close() end
    log("=== LAB SELECTIVE UPGRADE ===")
    log("Date: " .. os.date())
    log("")
end
clearLog()

-- Конфигурация имён периферий
local config = {
    barrel = "minecraft:barrel_1",
    barrelReader = "block_reader_19",
    indexer = "productivebees:gene_indexer_1",
    indexerReader = "block_reader_17",
    incubator = "productivebees:incubator_1",
    -- Массив крафтеров: индекс = количество генов
    crafters = {
        [1] = "enderio:crafter_1",
        [2] = "enderio:crafter_2",
        [3] = "enderio:crafter_3",
        [4] = "enderio:crafter_0",
    }
}

-- Подключаем периферии
local barrel = peripheral.wrap(config.barrel)
local barrelReader = peripheral.wrap(config.barrelReader)
local indexer = peripheral.wrap(config.indexer)
local indexerReader = peripheral.wrap(config.indexerReader)
local incubator = peripheral.wrap(config.incubator)

-- Проверяем наличие всех периферий
local function checkPeripherals()
    if not barrel then log("ERROR: Barrel not found"); return false end
    if not barrelReader then log("ERROR: Barrel reader not found"); return false end
    if not indexer then log("ERROR: Indexer not found"); return false end
    if not indexerReader then log("ERROR: Indexer reader not found"); return false end
    if not incubator then log("ERROR: Incubator not found"); return false end
    for i = 1, 4 do
        if not peripheral.wrap(config.crafters[i]) then
            log("ERROR: Crafter for " .. i .. " genes not found: " .. config.crafters[i])
            return false
        end
    end
    log("All peripherals found.")
    return true
end

if not checkPeripherals() then return end

-- Функция для перемещения предмета
local function push(src, srcName, dstName, srcSlot, count, dstSlot)
    return src.pushItems(dstName, srcSlot, count, dstSlot) or 0
end

-- Очистка контейнера (переместить всё в бочку)
local function clearContainer(cont, contName)
    local moved = 0
    for slot = 1, cont.size() do
        local item = cont.getItemDetail(slot)
        if item then
            moved = moved + cont.pushItems(config.barrel, slot, item.count)
        end
    end
    return moved
end

-- Функция для получения данных о пчеле из бочки (по данным ридера)
local function getBeeData(item)
    local components = item.components
    if not components then return nil end
    local custom = components["minecraft:custom_data"]
    if not custom then return nil end
    local attachments = custom["neoforge:attachments"]
    if not attachments then return nil end
    local attrHandler = attachments["productivebees:attributes_handler"]
    if not attrHandler then return nil end
    return {
        slot = item.Slot + 1,
        type = custom.type,
        productivity = attrHandler.bee_productivity,
        endurance = attrHandler.bee_endurance,
        behavior = attrHandler.bee_behavior,
        weather = attrHandler.bee_weather_tolerance,
    }
end

-- Целевые элитные значения
local targetValues = {
    productivity = "productivity.very_high",
    endurance = "endurance.strong",
    behavior = "behavior.metaturnal",
    weather = "weather_tolerance.any"
}

-- Функция определения недостающих генов
local function getMissingGenes(bee)
    local missing = {}
    if bee.productivity ~= targetValues.productivity then table.insert(missing, "productivity") end
    if bee.endurance ~= targetValues.endurance then table.insert(missing, "endurance") end
    if bee.behavior ~= targetValues.behavior then table.insert(missing, "behavior") end
    if bee.weather ~= targetValues.weather then table.insert(missing, "weather_tolerance") end
    return missing
end

-- Получаем данные из бочки
local barrelData = barrelReader.getBlockData()
if not barrelData or not barrelData.Items then
    log("No data from barrel reader")
    return
end

log("Barrel items: " .. #barrelData.Items)

-- Собираем всех неэлитных пчёл
local beesToUpgrade = {}  -- каждая запись: { slot, missing }
for _, item in ipairs(barrelData.Items) do
    if item.id == "productivebees:sturdy_bee_cage" then
        local bee = getBeeData(item)
        if bee then
            local missing = getMissingGenes(bee)
            if #missing > 0 then
                table.insert(beesToUpgrade, { slot = bee.slot, missing = missing })
                log("Found non-elite bee at slot " .. bee.slot .. ": missing " .. table.concat(missing, ", "))
            end
        end
    end
end

if #beesToUpgrade == 0 then
    log("No bees to upgrade.")
    return
end

log("Total bees to upgrade: " .. #beesToUpgrade)

-- Получаем данные о генах из индексера
local geneData = indexerReader.getBlockData()
if not geneData or not geneData.inv or not geneData.inv.Items then
    log("No gene data from indexer reader")
    return
end

-- Собираем чистые гены по атрибутам с учётом количества
local pureGenes = {} -- attr -> список { slot, count }
for _, item in ipairs(geneData.inv.Items) do
    local geneGroup = item.components and item.components["productivebees:gene_group"]
    if geneGroup and geneGroup.purity == 100 then
        local attr = geneGroup.attribute
        if pureGenes[attr] == nil then pureGenes[attr] = {} end
        table.insert(pureGenes[attr], { slot = item.Slot + 1, count = item.count })
    end
end

-- Считаем общее количество доступных генов каждого типа
local availableGenes = {}
for attr, list in pairs(pureGenes) do
    local total = 0
    for _, e in ipairs(list) do total = total + e.count end
    availableGenes[attr] = total
    log("Available " .. attr .. " genes: " .. total)
end

-- Проверяем, хватает ли генов на все недостающие потребности
local neededCounts = {}
for _, bee in ipairs(beesToUpgrade) do
    for _, attr in ipairs(bee.missing) do
        neededCounts[attr] = (neededCounts[attr] or 0) + 1
    end
end
for attr, need in pairs(neededCounts) do
    local have = availableGenes[attr] or 0
    if have < need then
        log("Not enough " .. attr .. " genes: need " .. need .. ", have " .. have)
        return
    end
end

-- Собираем honey_treat из бочки с учётом количества
local honeyPool = {} -- список { slot, count }
for slot = 1, barrel.size() do
    local item = barrel.getItemDetail(slot)
    if item and item.name == "productivebees:honey_treat" then
        table.insert(honeyPool, { slot = slot, count = item.count })
    end
end
local totalHoney = 0
for _, e in ipairs(honeyPool) do totalHoney = totalHoney + e.count end
log("Honey_treat total: " .. totalHoney)
if totalHoney < #beesToUpgrade then
    log("Not enough honey_treat (need " .. #beesToUpgrade .. ")")
    return
end

-- Функция для извлечения одного гена из пула
local function takeGene(attr)
    local list = pureGenes[attr]
    if not list or #list == 0 then return nil end
    local entry = list[1]
    entry.count = entry.count - 1
    local slot = entry.slot
    if entry.count == 0 then
        table.remove(list, 1)
    end
    return slot
end

-- Функция для извлечения одного honey_treat
local function takeHoney()
    if #honeyPool == 0 then return nil end
    local entry = honeyPool[1]
    entry.count = entry.count - 1
    local slot = entry.slot
    if entry.count == 0 then
        table.remove(honeyPool, 1)
    end
    return slot
end

-- Константы слотов
local geneStartSlot = 3      -- первый ген в крафтере (слот 3)
local honeyCrafterSlot = 2   -- слот для honey_treat
local resultCrafterSlot = 11 -- выходной слот крафтера
local incubatorResultSlot = 3 -- выходной слот инкубатора
local incubatorGeneSlot = 2   -- слот для улучшателя
local incubatorBeeSlot = 1    -- слот для пчелы

-- Основной цикл улучшения
local upgradedCount = 0
for i, beeInfo in ipairs(beesToUpgrade) do
    local beeSlot = beeInfo.slot
    local missing = beeInfo.missing
    local geneCount = #missing
    log("\n--- Processing bee " .. i .. " from slot " .. beeSlot .. " (missing " .. geneCount .. " genes: " .. table.concat(missing, ", ") .. ") ---")

    -- Выбираем крафтер по количеству генов
    local crafterName = config.crafters[geneCount]
    if not crafterName then
        log("No crafter defined for " .. geneCount .. " genes")
        goto next_bee
    end
    local crafter = peripheral.wrap(crafterName)
    if not crafter then
        log("Crafter " .. crafterName .. " not found")
        goto next_bee
    end

    -- Очищаем крафтер и инкубатор
    clearContainer(crafter, crafterName)
    clearContainer(incubator, "productivebees:incubator_1")

    -- Кладём нужные гены в крафтер (в слоты, начиная с geneStartSlot)
    for j, attr in ipairs(missing) do
        local geneSlot = takeGene(attr)
        if not geneSlot then
            log("  No " .. attr .. " gene left")
            goto next_bee
        end
        local dstSlot = geneStartSlot + (j - 1)
        log("Moving " .. attr .. " gene from indexer slot " .. geneSlot .. " to crafter slot " .. dstSlot)
        local moved = push(indexer, config.indexer, crafterName, geneSlot, 1, dstSlot)
        if moved == 0 then
            log("  Failed to move gene")
            goto next_bee
        end
    end

    -- Кладём honey_treat в крафтер (слот 2)
    local honeySlot = takeHoney()
    if not honeySlot then
        log("No honey_treat left")
        goto next_bee
    end
    log("Moving honey_treat from barrel slot " .. honeySlot .. " to crafter slot " .. honeyCrafterSlot)
    local movedHoney = push(barrel, config.barrel, crafterName, honeySlot, 1, honeyCrafterSlot)
    if movedHoney == 0 then
        log("Failed to move honey_treat")
        goto next_bee
    end

    -- Ждём крафт
    log("Waiting 1 second for craft...")
    sleep(1)

    -- Забираем результат
    local resultItem = crafter.getItemDetail(resultCrafterSlot)
    if not resultItem then
        log("No result in crafter slot " .. resultCrafterSlot)
        goto next_bee
    end
    log("Craft result: " .. resultItem.name)

    -- Перемещаем результат в инкубатор
    log("Moving result to incubator slot " .. incubatorGeneSlot)
    local movedResult = push(crafter, crafterName, config.incubator, resultCrafterSlot, 1, incubatorGeneSlot)
    if movedResult == 0 then
        log("Failed to move result to incubator")
        goto next_bee
    end

    -- Перемещаем пчелу в инкубатор
    log("Moving bee from barrel slot " .. beeSlot .. " to incubator slot " .. incubatorBeeSlot)
    local movedBee = push(barrel, config.barrel, config.incubator, beeSlot, 1, incubatorBeeSlot)
    if movedBee == 0 then
        log("Failed to move bee to incubator")
        goto next_bee
    end

    -- Ждём инкубацию
    log("Waiting 5 seconds for incubation...")
    sleep(5)

    -- Забираем результат
    local upgradedBee = incubator.getItemDetail(incubatorResultSlot)
    if not upgradedBee then
        log("No result in incubator slot " .. incubatorResultSlot)
        goto next_bee
    end
    log("Incubation result: " .. upgradedBee.name)

    -- Ищем свободный слот в бочке
    local freeSlot = nil
    for slot = 1, barrel.size() do
        if not barrel.getItemDetail(slot) then
            freeSlot = slot
            break
        end
    end
    if not freeSlot then
        log("No free slot in barrel, leaving upgraded bee in incubator")
        goto next_bee
    end

    -- Возвращаем улучшенную пчелу
    log("Moving upgraded bee to barrel slot " .. freeSlot)
    local movedBack = push(incubator, config.incubator, config.barrel, incubatorResultSlot, 1, freeSlot)
    if movedBack > 0 then
        log("Returned upgraded bee to barrel slot " .. freeSlot)
        upgradedCount = upgradedCount + 1
    else
        log("Failed to return upgraded bee")
    end

    ::next_bee::
end

log("\n=== SUMMARY ===")
log("Bees processed: " .. #beesToUpgrade)
log("Successfully upgraded: " .. upgradedCount)
log("=== END OF SCRIPT ===")
print("Selective upgrade complete. Report saved to " .. reportFile)