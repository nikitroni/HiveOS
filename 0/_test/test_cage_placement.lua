-- test_cage_placement.lua
-- Тестирует перемещение одной пустой клетки из бочки в улей разными способами
-- Результаты записываются в файл cage_test_result.txt

local cageChestName = "minecraft:barrel_2"
local hiveName = "productivebees:advanced_hive_1"
local resultFile = "cage_test_result.txt"

local cageChest = peripheral.wrap(cageChestName)
local hive = peripheral.wrap(hiveName)

-- Функция для записи в файл (добавление строки)
local function writeResult(line)
    local file = fs.open(resultFile, "a")
    if file then
        file.writeLine(line)
        file.close()
    end
end

-- Очищаем файл перед началом
local f = fs.open(resultFile, "w")
if f then f.close() end
writeResult("Cage placement test started at " .. os.date())

if not cageChest then
    print("ERROR: Cage chest not found")
    writeResult("ERROR: Cage chest not found")
    return
end
if not hive then
    print("ERROR: Hive not found")
    writeResult("ERROR: Hive not found")
    return
end

print("Cage chest inventory:")
writeResult("Cage chest inventory:")
for slot = 1, cageChest.size() do
    local item = cageChest.getItemDetail(slot)
    if item then
        print("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
        writeResult("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
    end
end

-- Найдём клетку
local cageSlot = nil
for slot = 1, cageChest.size() do
    local item = cageChest.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        cageSlot = slot
        break
    end
end

if not cageSlot then
    print("No empty cages found in cage chest!")
    writeResult("No empty cages found!")
    return
end

print("Using cage from slot " .. cageSlot)
writeResult("Using cage from slot " .. cageSlot)

-- Метод 1: pushItems из бочки в улей
writeResult("\n--- Testing pushItems into hive slots 1-12 ---")
for targetSlot = 1, 12 do
    local targetItem = hive.getItemDetail(targetSlot)
    if targetItem then
        local msg = "Slot " .. targetSlot .. " is occupied, skipping"
        print(msg)
        writeResult(msg)
    else
        local moved = cageChest.pushItems(hiveName, cageSlot, 1, targetSlot)
        if moved > 0 then
            local msg = "SUCCESS (pushItems): slot " .. targetSlot .. " moved " .. moved .. " cage"
            print(msg)
            writeResult(msg)
            -- Проверим, что появилось
            local newItem = hive.getItemDetail(targetSlot)
            if newItem then
                local msg2 = "  Hive slot " .. targetSlot .. " now has: " .. newItem.name
                print(msg2)
                writeResult(msg2)
            end
            -- Вернём клетку обратно
            local movedBack = hive.pushItems(cageChestName, targetSlot, 1)
            if movedBack > 0 then
                print("  Returned cage to chest")
                writeResult("  Returned cage to chest")
            end
        else
            local msg = "pushItems to slot " .. targetSlot .. " failed (returned 0)"
            print(msg)
            writeResult(msg)
        end
    end
end

-- Метод 2: pullItems из бочки в улей
writeResult("\n--- Testing pullItems from chest into hive slots 1-12 ---")
for targetSlot = 1, 12 do
    local targetItem = hive.getItemDetail(targetSlot)
    if targetItem then
        local msg = "Slot " .. targetSlot .. " is occupied, skipping"
        print(msg)
        writeResult(msg)
    else
        local moved = hive.pullItems(cageChestName, cageSlot, 1, targetSlot)
        if moved > 0 then
            local msg = "SUCCESS (pullItems): slot " .. targetSlot .. " moved " .. moved .. " cage"
            print(msg)
            writeResult(msg)
            local newItem = hive.getItemDetail(targetSlot)
            if newItem then
                local msg2 = "  Hive slot " .. targetSlot .. " now has: " .. newItem.name
                print(msg2)
                writeResult(msg2)
            end
            local movedBack = hive.pushItems(cageChestName, targetSlot, 1)
            if movedBack > 0 then
                print("  Returned cage to chest")
                writeResult("  Returned cage to chest")
            end
        else
            local msg = "pullItems to slot " .. targetSlot .. " failed"
            print(msg)
            writeResult(msg)
        end
    end
end

writeResult("\nTest finished. Check successful slots above.")
print("\nTest finished. Results saved to " .. resultFile)