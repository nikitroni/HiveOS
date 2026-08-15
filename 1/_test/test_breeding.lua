-- test_breeding_final6.lua
-- Тестирует процесс размножения пчёл в breeding chamber.
-- Родители перемещаются поштучно в отдельные слоты (2 и 3).
-- Цветы: 3 в слот 4, 3 в слот 5.
-- Пустые клетки (3) в слот 1.
-- 3 цикла ожидания (3 сек) и изъятия потомков.
-- В конце возврат родителей с диагностикой и запасным приёмником.
-- Логи сохраняются в папку logs.

local logsDir = "logs"
if not fs.exists(logsDir) then fs.makeDir(logsDir) end
local reportFile = logsDir .. "/breeding_test_final6.txt"

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
    log("=== BREEDING TEST (FINAL6) ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

-- Конфигурация
local config = {
    lab_chest = "minecraft:barrel_1",
    cage_chest = "minecraft:barrel_2",
    resource_chest = "ae2:interface_0",
    chamber = "productivebees:breeding_chamber_1",
    flower = "minecraft:sunflower"
}

-- Подключаем периферии
local labChest = peripheral.wrap(config.lab_chest)
local cageChest = peripheral.wrap(config.cage_chest)
local resourceChest = peripheral.wrap(config.resource_chest)
local chamber = peripheral.wrap(config.chamber)

if not labChest then log("ERROR: lab_chest not found"); return end
if not cageChest then log("ERROR: cage_chest not found"); return end
if not resourceChest then log("ERROR: resource_chest not found"); return end
if not chamber then log("ERROR: breeding chamber not found"); return end

log("All peripherals found.")

-- Вспомогательная функция для перемещения
local function move(src, srcName, dstName, srcSlot, count, dstSlot)
    return src.pushItems(dstName, srcSlot, count, dstSlot) or 0
end

-- Функция для проверки наличия ресурсов
local function checkResources()
    local beeCount = 0
    for slot = 1, labChest.size() do
        local item = labChest.getItemDetail(slot)
        if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
            beeCount = beeCount + item.count
        end
    end
    if beeCount < 2 then
        log("ERROR: Need at least 2 bees in lab chest (found " .. beeCount .. ")")
        return false
    end

    local cageCount = 0
    for slot = 1, cageChest.size() do
        local item = cageChest.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            cageCount = cageCount + item.count
        end
    end
    if cageCount < 3 then
        log("ERROR: Need at least 3 empty cages in cage chest (found " .. cageCount .. ")")
        return false
    end

    local flowerCount = 0
    for slot = 1, resourceChest.size() do
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == config.flower then
            flowerCount = flowerCount + item.count
        end
    end
    if flowerCount < 6 then
        log("ERROR: Need at least 6 " .. config.flower .. " in resource chest (found " .. flowerCount .. ")")
        return false
    end

    log("Resources OK. Bees: " .. beeCount .. ", Cages: " .. cageCount .. ", Flowers: " .. flowerCount)
    return true
end

-- Основной процесс
local function runBreeding()
    log("\n=== STARTING BREEDING PROCESS ===")

    local ok = checkResources()
    if not ok then return end

    -- 2. Перемещаем родителей по одному
    log("Moving parent bees to chamber slots 2 and 3")
    local beesMoved = 0
    local targetSlots = {2, 3}
    for i, targetSlot in ipairs(targetSlots) do
        for slot = 1, labChest.size() do
            if beesMoved >= i then break end
            local item = labChest.getItemDetail(slot)
            if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
                local moved = move(labChest, config.lab_chest, config.chamber, slot, 1, targetSlot)
                if moved == 1 then
                    beesMoved = beesMoved + 1
                    log(string.format("  Moved 1 bee from slot %d to slot %d", slot, targetSlot))
                    break
                end
            end
        end
    end
    if beesMoved < 2 then
        log("ERROR: Failed to move both parent bees")
        return
    end
    log("Parents placed.")

    -- 3. Пустые клетки в слот 1
    log("Placing 3 empty cages into slot 1")
    local cagesPlaced = 0
    for slot = 1, cageChest.size() do
        if cagesPlaced >= 3 then break end
        local item = cageChest.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            local need = 3 - cagesPlaced
            local toTake = math.min(item.count, need)
            local moved = move(cageChest, config.cage_chest, config.chamber, slot, toTake, 1)
            if moved > 0 then
                cagesPlaced = cagesPlaced + moved
                log(string.format("  Moved %d cages from slot %d to slot 1", moved, slot))
            end
        end
    end
    if cagesPlaced < 3 then
        log("ERROR: Failed to place 3 empty cages")
        return
    end
    log("Cages placed.")

    -- 4. Цветы: 3 в слот 4, затем 3 в слот 5
    log("Placing 3 flowers into slot 4 and 3 into slot 5")

    local flowersSlot4 = 0
    for slot = 1, resourceChest.size() do
        if flowersSlot4 >= 3 then break end
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == config.flower then
            local need = 3 - flowersSlot4
            local toTake = math.min(item.count, need)
            local moved = move(resourceChest, config.resource_chest, config.chamber, slot, toTake, 4)
            if moved > 0 then
                flowersSlot4 = flowersSlot4 + moved
                log(string.format("  Moved %d flowers from slot %d to slot 4", moved, slot))
            end
        end
    end
    if flowersSlot4 < 3 then
        log("ERROR: Only " .. flowersSlot4 .. " flowers placed in slot 4, need 3")
        return
    end

    local flowersSlot5 = 0
    for slot = 1, resourceChest.size() do
        if flowersSlot5 >= 3 then break end
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == config.flower then
            local need = 3 - flowersSlot5
            local toTake = math.min(item.count, need)
            local moved = move(resourceChest, config.resource_chest, config.chamber, slot, toTake, 5)
            if moved > 0 then
                flowersSlot5 = flowersSlot5 + moved
                log(string.format("  Moved %d flowers from slot %d to slot 5", moved, slot))
            end
        end
    end
    if flowersSlot5 < 3 then
        log("ERROR: Only " .. flowersSlot5 .. " flowers placed in slot 5, need 3")
        return
    end
    log("Flowers placed.")

    -- 5. Три цикла изъятия потомков
    for cycle = 1, 3 do
        log(string.format("\n--- CYCLE %d ---", cycle))

        log("Waiting 3 seconds for breeding...")
        sleep(3)

        log("Taking result from slot 6 to lab chest")
        local resultItem = chamber.getItemDetail(6)
        if resultItem then
            local moved = move(chamber, config.chamber, config.lab_chest, 6, 1)
            if moved > 0 then
                log("Result moved to lab chest: " .. resultItem.name)
            else
                log("ERROR: Failed to move result")
            end
        else
            log("No result in slot 6")
        end

        sleep(1)
    end

    -- 6. Диагностика свободных слотов в lab_chest
    local freeSlots = 0
    for slot = 1, labChest.size() do
        if not labChest.getItemDetail(slot) then
            freeSlots = freeSlots + 1
        end
    end
    log("Free slots in lab chest before return: " .. freeSlots)

    -- 7. Возврат родителей с запасным приёмником
    log("\n--- Returning parent bees to lab chest ---")
    local parentsReturned = 0
    for parentSlot = 2, 3 do
        local item = chamber.getItemDetail(parentSlot)
        if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
            log(string.format("  Found parent in slot %d: %s", parentSlot, item.name))
            -- Сначала пробуем в lab_chest
            local moved = chamber.pushItems(config.lab_chest, parentSlot, 1)
            if moved > 0 then
                parentsReturned = parentsReturned + moved
                log(string.format("  Returned parent from slot %d to lab chest", parentSlot))
            else
                log("  Failed to move to lab chest, trying cage chest...")
                local moved2 = chamber.pushItems(config.cage_chest, parentSlot, 1)
                if moved2 > 0 then
                    parentsReturned = parentsReturned + moved2
                    log(string.format("  Returned parent from slot %d to cage chest", parentSlot))
                else
                    log(string.format("  Failed to move parent from slot %d to any chest", parentSlot))
                end
            end
        else
            log(string.format("  No parent found in slot %d", parentSlot))
        end
    end
    if parentsReturned == 2 then
        log("Both parents returned.")
    else
        log("WARNING: Could not return both parents (returned " .. parentsReturned .. ")")
    end

    -- Итог: считаем пчёл в lab_chest
    local totalBees = 0
    for slot = 1, labChest.size() do
        local item = labChest.getItemDetail(slot)
        if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
            totalBees = totalBees + item.count
        end
    end
    log(string.format("\nTotal bees in lab chest after breeding: %d", totalBees))
    log("=== BREEDING PROCESS COMPLETED ===")
end

-- Запуск
runBreeding()
print("Breeding test completed. See log in " .. reportFile)