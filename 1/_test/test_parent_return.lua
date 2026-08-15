-- test_parent_return.lua
-- Исследует возможность возврата родителей из breeding chamber.
-- Помещает двух родителей (даже если они в одном стаке) в слоты 2 и 3,
-- затем пробует все способы их изъятия.
-- Логи сохраняются в папку logs.

local logsDir = "logs"
if not fs.exists(logsDir) then fs.makeDir(logsDir) end
local reportFile = logsDir .. "/parent_return_test.txt"

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
    log("=== PARENT RETURN TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

-- Конфигурация
local config = {
    lab_chest = "minecraft:barrel_1",
    cage_chest = "minecraft:barrel_2",
    chamber = "productivebees:breeding_chamber_1"
}

-- Подключаем периферии
local labChest = peripheral.wrap(config.lab_chest)
local cageChest = peripheral.wrap(config.cage_chest)
local chamber = peripheral.wrap(config.chamber)

if not labChest then log("ERROR: lab_chest not found"); return end
if not cageChest then log("ERROR: cage_chest not found"); return end
if not chamber then log("ERROR: breeding chamber not found"); return end

log("All peripherals found.")

-- Функция для перемещения предметов
local function push(src, dstName, srcSlot, count)
    return src.pushItems(dstName, srcSlot, count) or 0
end

local function pull(dst, srcName, srcSlot, count)
    return dst.pullItems(srcName, srcSlot, count) or 0
end

-- 1. Определяем общее количество пчёл в lab_chest
local totalBees = 0
for slot = 1, labChest.size() do
    local item = labChest.getItemDetail(slot)
    if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
        totalBees = totalBees + item.count
    end
end
log("Total bees in lab chest: " .. totalBees)
if totalBees < 2 then
    log("ERROR: Need at least 2 bees in lab chest")
    return
end

-- 2. Перемещаем двух пчёл в слоты 2 и 3 камеры
log("\n--- Moving parents to chamber slots 2 and 3 ---")
local beesMoved = 0
for i = 1, 2 do
    for slot = 1, labChest.size() do
        if beesMoved >= i then break end
        local item = labChest.getItemDetail(slot)
        if item and (item.name == "productivebees:sturdy_bee_cage" or item.name == "productivebees:bee_cage") then
            -- Перемещаем одну клетку
            local moved = push(labChest, config.chamber, slot, 1)
            if moved == 1 then
                beesMoved = beesMoved + 1
                log(string.format("  Moved 1 bee from slot %d (auto-assigned)", slot))
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

-- Проверим, где они оказались
local slot2item = chamber.getItemDetail(2)
local slot3item = chamber.getItemDetail(3)
log("Slot 2 after move: " .. (slot2item and slot2item.name or "empty"))
log("Slot 3 after move: " .. (slot3item and slot3item.name or "empty"))

-- 3. Пробуем различные способы изъятия
log("\n--- Attempting to retrieve parents ---")

-- Способ 1: pushItems из камеры в lab_chest без указания слота
local attempt1 = push(chamber, config.lab_chest, 2, 1)
log("Method 1: chamber:pushItems(lab_chest,2,1) -> " .. attempt1)
if attempt1 == 0 then
    local attempt1b = push(chamber, config.cage_chest, 2, 1)
    log("Method 1b: chamber:pushItems(cage_chest,2,1) -> " .. attempt1b)
end

-- Способ 2: pullItems из lab_chest из камеры
local attempt2 = pull(labChest, config.chamber, 2, 1)
log("Method 2: labChest:pullItems(chamber,2,1) -> " .. attempt2)

-- Способ 3: pushItems с указанием слота в lab_chest (например, слот 1)
local attempt3 = chamber.pushItems(config.lab_chest, 2, 1, 1)
log("Method 3: chamber:pushItems(lab_chest,2,1,1) -> " .. attempt3)

-- Способ 4: pushItems в cage_chest с указанием слота
local attempt4 = chamber.pushItems(config.cage_chest, 2, 1, 1)
log("Method 4: chamber:pushItems(cage_chest,2,1,1) -> " .. attempt4)

-- Повторяем для слота 3
log("\n--- Testing slot 3 ---")
local attempt1_3 = push(chamber, config.lab_chest, 3, 1)
log("Method 1 (slot3): chamber:pushItems(lab_chest,3,1) -> " .. attempt1_3)
if attempt1_3 == 0 then
    local attempt1b_3 = push(chamber, config.cage_chest, 3, 1)
    log("Method 1b (slot3): chamber:pushItems(cage_chest,3,1) -> " .. attempt1b_3)
end
local attempt2_3 = pull(labChest, config.chamber, 3, 1)
log("Method 2 (slot3): labChest:pullItems(chamber,3,1) -> " .. attempt2_3)
local attempt3_3 = chamber.pushItems(config.lab_chest, 3, 1, 1)
log("Method 3 (slot3): chamber:pushItems(lab_chest,3,1,1) -> " .. attempt3_3)
local attempt4_3 = chamber.pushItems(config.cage_chest, 3, 1, 1)
log("Method 4 (slot3): chamber:pushItems(cage_chest,3,1,1) -> " .. attempt4_3)

-- 4. Проверим, остались ли пчёлы в камере
slot2item = chamber.getItemDetail(2)
slot3item = chamber.getItemDetail(3)
log("\nAfter attempts:")
log("Slot 2: " .. (slot2item and slot2item.name or "empty"))
log("Slot 3: " .. (slot3item and slot3item.name or "empty"))

log("\n=== END OF TEST ===")
print("Test completed. See log in " .. reportFile)