-- test_full_lab_cycle.lua
-- Тестирует полный цикл отправки пчёл в лабораторию с учётом реальной логики улья:
--   - Пустые клетки кладутся в слот 12 → через некоторое время клетки с пчёлами появляются в слотах 3-10.
--   - Для возврата: клетки с пчёлами кладутся в слот 12 → через время пустые клетки появляются в слотах 3-10.
-- Все операции логируются в файл full_cycle_test.txt

local bufferChestName = "minecraft:barrel_0"
local cageChestName = "minecraft:barrel_2"
local labChestName = "minecraft:barrel_1"
local hiveName = "productivebees:advanced_hive_0"
local resultFile = "full_cycle_test.txt"

local buffer = peripheral.wrap(bufferChestName)
local cageChest = peripheral.wrap(cageChestName)
local labChest = peripheral.wrap(labChestName)
local hive = peripheral.wrap(hiveName)

local function logToFile(line)
    local file = fs.open(resultFile, "a")
    if file then
        file.writeLine(os.date("%H:%M:%S") .. ": " .. line)
        file.close()
    end
    print(line)
end

local function initLog()
    local f = fs.open(resultFile, "w")
    if f then f.close() end
    logToFile("=== Full lab cycle test started ===")
end

initLog()

if not buffer then logToFile("ERROR: Buffer chest not found") return end
if not cageChest then logToFile("ERROR: Cage chest not found") return end
if not labChest then logToFile("ERROR: Lab chest not found") return end
if not hive then logToFile("ERROR: Hive not found") return end

logToFile("All peripherals found.")

-- Функция подсчёта клеток с пчёлами в слотах 3-10
local function countBeeCages(hive)
    local count = 0
    for slot = 3, 11 do
        local item = hive.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            count = count + 1
        end
    end
    return count
end
local beeCount = countBeeCages(hive)
print("Bees found:", beeCount)

-- Функция подсчёта пустых клеток в хранилище клеток
local function countEmptyCages()
    local count = 0
    for slot = 1, cageChest.size() do
        local item = cageChest.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            count = count + item.count
        end
    end
    return count
end

-- Получаем количество пчёл в улье через HiveReader (если возможно)
-- Для теста используем HiveReader, предполагая, что он уже загружен (в реальном коде он будет)
-- Если нет, можно запросить ввод вручную или использовать заглушку.
local beeCount = nil
if HiveReader then
    -- Предположим, что мы можем получить данные для этого улья
    -- Но проще для теста будем считать, что мы знаем количество пчёл, например, через ручной ввод
    -- Вместо этого дадим возможность пользователю указать число
    print("Enter the number of bees in hive (or 0 to skip):")
    local input = read()
    beeCount = tonumber(input)
    if not beeCount or beeCount == 0 then
        logToFile("No bees to send. Test aborted.")
        return
    end
else
    -- Если HiveReader недоступен, тоже запросим ввод
    print("HiveReader not loaded. Enter the number of bees in hive:")
    local input = read()
    beeCount = tonumber(input)
    if not beeCount or beeCount == 0 then
        logToFile("No bees to send. Test aborted.")
        return
    end
end

logToFile("Number of bees to send: " .. beeCount)

-- Шаг 1: Очистка слотов 3-11 в буфер (освобождаем место для будущих пустых клеток и возвращаемой продукции)
logToFile("--- Step 1: Clearing hive slots 3-11 to buffer ---")
for slot = 3, 11 do
    local item = hive.getItemDetail(slot)
    if item then
        local moved = hive.pushItems(bufferChestName, slot)
        if moved > 0 then
            logToFile("Moved " .. moved .. " " .. item.name .. " from slot " .. slot .. " to buffer")
        end
    end
end

-- Шаг 2: Помещение пустых клеток в слот 12 (количество = beeCount)
logToFile("--- Step 2: Placing " .. beeCount .. " empty cages into hive slot 12 ---")
-- Проверим, пуст ли слот 12
local slot12Item = hive.getItemDetail(12)
if slot12Item then
    logToFile("Slot 12 is occupied by " .. slot12Item.name .. ". Cannot place cages.")
    return
end

-- Найдём достаточно клеток в cageChest
local cagesPlaced = 0
for slot = 1, cageChest.size() do
    if cagesPlaced >= beeCount then break end
    local item = cageChest.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        local toTake = math.min(item.count, beeCount - cagesPlaced)
        local moved = cageChest.pushItems(hiveName, slot, toTake, 12)
        if moved > 0 then
            cagesPlaced = cagesPlaced + moved
            logToFile("Placed " .. moved .. " cages from slot " .. slot)
        end
    end
end

if cagesPlaced < beeCount then
    logToFile("ERROR: Only placed " .. cagesPlaced .. " cages, need " .. beeCount)
    return
else
    logToFile("SUCCESS: Placed " .. cagesPlaced .. " empty cages into hive slot 12")
end

-- Даём время моде на обработку (тик)
logToFile("Waiting 2 seconds for bees to be captured...")
sleep(2)

-- Шаг 3: Забор клеток с пчёлами из слотов 3-10 в лабораторный сундук
logToFile("--- Step 3: Taking bee cages from hive slots 3-10 to lab chest ---")
local taken = 0
for slot = 3, 10 do
    local item = hive.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        local moved = hive.pushItems(labChestName, slot)
        if moved > 0 then
            taken = taken + moved
            logToFile("Took " .. moved .. " bee cage from slot " .. slot)
        end
    end
end

logToFile("Total bee cages taken: " .. taken)
if taken ~= beeCount then
    logToFile("WARNING: Taken cages count (" .. taken .. ") differs from expected (" .. beeCount .. ")")
end

-- Имитация работы лаборатории (5 секунд)
logToFile("--- Simulating lab work (5 seconds) ---")
sleep(5)

-- Шаг 4: Возврат клеток с пчёлами обратно в слот 12
logToFile("--- Step 4: Returning bee cages to hive slot 12 for release ---")
-- Проверим, пуст ли слот 12
slot12Item = hive.getItemDetail(12)
if slot12Item then
    logToFile("Slot 12 is occupied, cannot place bee cages for return")
    return
end

local cagesReturned = 0
for slot = 1, labChest.size() do
    if cagesReturned >= taken then break end
    local item = labChest.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        local moved = labChest.pushItems(hiveName, slot, 1, 12)
        if moved > 0 then
            cagesReturned = cagesReturned + moved
            logToFile("Returned 1 bee cage to hive slot 12")
        end
    end
end

if cagesReturned < taken then
    logToFile("WARNING: Only returned " .. cagesReturned .. " cages, expected " .. taken)
end

logToFile("Waiting 2 seconds for bees to be released...")
sleep(2)

-- Шаг 5: Забор пустых клеток из слотов 3-10 обратно в хранилище клеток
logToFile("--- Step 5: Taking empty cages from hive slots 3-10 back to cage chest ---")
local emptyTaken = 0
for slot = 3, 11 do
    local item = hive.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        local moved = hive.pushItems(cageChestName, slot)
        if moved > 0 then
            emptyTaken = emptyTaken + moved
            logToFile("Took empty cage from slot " .. slot)
        end
    end
end
logToFile("Total empty cages taken: " .. emptyTaken)

-- Шаг 6: Возврат продукции из буфера обратно в слоты 3-10
logToFile("--- Step 6: Returning items from buffer to hive slots 3-10 ---")
local itemsReturned = 0
for slot = 1, buffer.size() do
    local item = buffer.getItemDetail(slot)
    if item then
        for hiveSlot = 3, 10 do
            if not hive.getItemDetail(hiveSlot) then
                local moved = buffer.pushItems(hiveName, slot, 1, hiveSlot)
                if moved > 0 then
                    itemsReturned = itemsReturned + moved
                    logToFile("Returned " .. item.name .. " to hive slot " .. hiveSlot)
                    break
                end
            end
        end
    end
end
logToFile("Total items returned: " .. itemsReturned)

-- Финальные проверки
local finalBeeCages = 0
for slot = 3, 11 do
    local item = hive.getItemDetail(slot)
    if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
        finalBeeCages = finalBeeCages + 1
    end
end
local finalEmptyCages = countEmptyCages()

logToFile("Final bee cages in hive slots 3-10: " .. finalBeeCages)
logToFile("Final empty cages in cage chest: " .. finalEmptyCages)

-- Успех, если в улье не осталось клеток с пчёлами, а пустых клеток стало не меньше (могли добавиться)
if finalBeeCages == 0 and finalEmptyCages >= initialEmptyCages then
    logToFile("=== TEST PASSED: Cycle completed successfully ===")
else
    logToFile("=== TEST FAILED: Counts mismatch ===")
end
logToFile("=== Test finished ===")