-- lab_upgrade_all_v4.lua
-- Сканирует бочку, находит всех неэлитных пчёл, улучшает их через крафтер и инкубатор.
-- Использует проверенные слоты: гены в 3-6, honey_treat в слот 2.

local logsDir = "logs"
if not fs.exists(logsDir) then fs.makeDir(logsDir) end
local reportFile = logsDir .. "/lab_upgrade_all_v4.txt"

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
    log("=== LAB UPGRADE ALL V4 ===")
    log("Date: " .. os.date())
    log("")
end
clearLog()

-- Периферии
local barrel = peripheral.wrap("minecraft:barrel_1")
local reader = peripheral.wrap("block_reader_19")
local crafter = peripheral.wrap("enderio:crafter_0")
local indexer = peripheral.wrap("productivebees:gene_indexer_1")
local incubator = peripheral.wrap("productivebees:incubator_1")
local indexerReader = peripheral.wrap("block_reader_17")

if not barrel then log("ERROR: Barrel not found"); return end
if not reader then log("ERROR: Barrel reader not found"); return end
if not crafter then log("ERROR: Crafter not found"); return end
if not indexer then log("ERROR: Indexer not found"); return end
if not incubator then log("ERROR: Incubator not found"); return end
if not indexerReader then log("ERROR: Indexer reader not found"); return end

log("All peripherals found.")

-- Функция для перемещения предмета
local function push(src, srcName, dstName, srcSlot, count, dstSlot)
    return src.pushItems(dstName, srcSlot, count, dstSlot) or 0
end

-- Функция для очистки контейнера (переместить всё в бочку)
local function clearContainer(cont, contName)
    local moved = 0
    for slot = 1, cont.size() do
        local item = cont.getItemDetail(slot)
        if item then
            moved = moved + cont.pushItems("minecraft:barrel_1", slot, item.count)
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

-- Функция проверки элитности
local function isElite(bee)
    return bee.productivity == "productivity.very_high"
        and bee.endurance == "endurance.strong"
        and bee.behavior == "behavior.metaturnal"
        and bee.weather == "weather_tolerance.any"
end

-- Получаем данные о всех предметах в бочке
local barrelData = reader.getBlockData()
if not barrelData or not barrelData.Items then
    log("No data from barrel reader")
    return
end

log("Barrel items: " .. #barrelData.Items)

-- Собираем всех неэлитных пчёл
local nonEliteBees = {}
for _, item in ipairs(barrelData.Items) do
    if item.id == "productivebees:sturdy_bee_cage" then
        local bee = getBeeData(item)
        if bee and not isElite(bee) then
            table.insert(nonEliteBees, bee)
            log("Found non-elite bee at slot " .. bee.slot .. ": type=" .. bee.type)
        end
    end
end

if #nonEliteBees == 0 then
    log("No non-elite bees found.")
    return
end

local totalBees = #nonEliteBees
log("Total non-elite bees: " .. totalBees)

-- Получаем данные о генах из индексера
local geneData = indexerReader.getBlockData()
if not geneData or not geneData.inv or not geneData.inv.Items then
    log("No gene data from indexer reader")
    return
end

log("Gene items in indexer: " .. #geneData.inv.Items)

-- Собираем чистые гены по атрибутам, учитывая количество в каждом слоте
local pureGenes = {} -- attr -> список { slot, count }
for _, item in ipairs(geneData.inv.Items) do
    local geneGroup = item.components and item.components["productivebees:gene_group"]
    if geneGroup and geneGroup.purity == 100 then
        local attr = geneGroup.attribute
        if attr == "behavior" or attr == "endurance" or attr == "productivity" or attr == "weather_tolerance" then
            if not pureGenes[attr] then pureGenes[attr] = {} end
            table.insert(pureGenes[attr], { slot = item.Slot + 1, count = item.count })
        end
    end
end

-- Проверяем, хватает ли общего количества генов
local neededAttrs = { "behavior", "endurance", "productivity", "weather_tolerance" }
for _, attr in ipairs(neededAttrs) do
    local totalCount = 0
    if pureGenes[attr] then
        for _, entry in ipairs(pureGenes[attr]) do
            totalCount = totalCount + entry.count
        end
    end
    log(attr .. " genes available: " .. totalCount .. ", need " .. totalBees)
    if totalCount < totalBees then
        log("Not enough pure genes for " .. attr .. " (need " .. totalBees .. ", have " .. totalCount .. ")")
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
for _, entry in ipairs(honeyPool) do
    totalHoney = totalHoney + entry.count
end
log("Honey_treat total count: " .. totalHoney .. ", need " .. totalBees)
if totalHoney < totalBees then
    log("Not enough honey_treat in barrel (need " .. totalBees .. ", have " .. totalHoney .. ")")
    return
end

-- Функция для извлечения одного гена из пула
local function takeGene(attr)
    local entries = pureGenes[attr]
    if not entries or #entries == 0 then return nil end
    local entry = entries[1]
    entry.count = entry.count - 1
    local slot = entry.slot
    if entry.count == 0 then
        table.remove(entries, 1)
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

-- Слоты в крафтере (проверенные в тесте)
local geneCrafterSlots = { 3, 4, 5, 6 }  -- для генов
local honeyCrafterSlot = 2                 -- для honey_treat
local resultCrafterSlot = 11               -- выходной слот

-- Основной цикл улучшения
local upgradedCount = 0
for i, bee in ipairs(nonEliteBees) do
    log("\n--- Processing bee " .. i .. " from slot " .. bee.slot .. " ---")

    -- Очищаем крафтер и инкубатор перед каждым шагом
    clearContainer(crafter, "enderio:crafter_0")
    clearContainer(incubator, "productivebees:incubator_1")

    -- Кладём гены в крафтер (слоты 3-6)
    for j, attr in ipairs(neededAttrs) do
        local geneSlot = takeGene(attr)
        if not geneSlot then
            log("  Unexpected: no gene left for " .. attr)
            goto next_bee
        end
        local dstSlot = geneCrafterSlots[j]
        log("Moving " .. attr .. " gene from indexer slot " .. geneSlot .. " to crafter slot " .. dstSlot)
        local moved = push(indexer, "productivebees:gene_indexer_1", "enderio:crafter_0", geneSlot, 1, dstSlot)
        if moved == 0 then
            log("  Failed to move gene")
            goto next_bee
        else
            log("  Moved")
        end
    end

    -- Кладём honey_treat в крафтер (слот 2)
    local honeySlot = takeHoney()
    if not honeySlot then
        log("Unexpected: no honey left")
        goto next_bee
    end
    log("Moving honey_treat from barrel slot " .. honeySlot .. " to crafter slot " .. honeyCrafterSlot)
    local movedHoney = push(barrel, "minecraft:barrel_1", "enderio:crafter_0", honeySlot, 1, honeyCrafterSlot)
    if movedHoney == 0 then
        log("Failed to move honey_treat")
        goto next_bee
    end
    log("Moved honey_treat")

    -- Ждём крафт
    log("Waiting 1 second for craft...")
    sleep(1)

    -- Забираем результат из слота 11 крафтера
    local resultItem = crafter.getItemDetail(resultCrafterSlot)
    if not resultItem then
        log("No result in crafter slot " .. resultCrafterSlot)
        goto next_bee
    end
    log("Craft result: " .. resultItem.name)

    -- Перемещаем результат в инкубатор слот 2
    local incubatorResultSlot = 2
    log("Moving result to incubator slot " .. incubatorResultSlot)
    local movedResult = push(crafter, "enderio:crafter_0", "productivebees:incubator_1", resultCrafterSlot, 1, incubatorResultSlot)
    if movedResult == 0 then
        log("Failed to move result to incubator")
        goto next_bee
    end

    -- Перемещаем пчелу в инкубатор слот 1
    log("Moving bee from barrel slot " .. bee.slot .. " to incubator slot 1")
    local movedBee = push(barrel, "minecraft:barrel_1", "productivebees:incubator_1", bee.slot, 1, 1)
    if movedBee == 0 then
        log("Failed to move bee to incubator")
        goto next_bee
    end

    -- Ждём инкубацию
    log("Waiting 5 seconds for incubation...")
    sleep(5)

    -- Забираем результат из инкубатора слот 3
    local upgradedBee = incubator.getItemDetail(3)
    if not upgradedBee then
        log("No result in incubator slot 3")
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

    -- Возвращаем улучшенную пчелу в бочку
    log("Moving upgraded bee to barrel slot " .. freeSlot)
    local movedBack = push(incubator, "productivebees:incubator_1", "minecraft:barrel_1", 3, 1, freeSlot)
    if movedBack > 0 then
        log("Returned upgraded bee to barrel slot " .. freeSlot)
        upgradedCount = upgradedCount + 1
    else
        log("Failed to return upgraded bee")
    end

    ::next_bee::
end

log("\n=== SUMMARY ===")
log("Total non-elite bees: " .. totalBees)
log("Successfully upgraded: " .. upgradedCount)
log("=== END OF SCRIPT ===")
print("Upgrade process complete. Report saved to " .. reportFile)