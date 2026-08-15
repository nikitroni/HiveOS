-- test_crafter_final.lua
-- Тест крафтера:
-- 1. Кладём honey_treat в слот 2.
-- 2. Кладём по одному чистому гену каждого типа в слоты 3-6.
-- 3. Ждём 1 секунду.
-- 4. Забираем предмет из слота 21 крафтера и перемещаем в инкубатор (слот 3).

local logsDir = "logs"
if not fs.exists(logsDir) then
    fs.makeDir(logsDir)
end

local reportFile = logsDir .. "/crafter_final_test.txt"

local function log(...)
    local file = fs.open(reportFile, "a")
    if file then
        for i = 1, select('#', ...) do
            file.write(tostring(select(i, ...)) .. " ")
        end
        file.write("\n")
        file.close()
    end
end

local function clearLog()
    local f = fs.open(reportFile, "w")
    if f then f.close() end
    log("=== CRAFTER FINAL TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

-- Имена периферий
local crafterName = "enderio:crafter_0"
local barrelName = "minecraft:barrel_1"
local indexerName = "productivebees:gene_indexer_1"
local incubatorName = "productivebees:incubator_1"
local readerName = "block_reader_17"

-- Получаем объекты
local crafter = peripheral.wrap(crafterName)
local barrel = peripheral.wrap(barrelName)
local indexer = peripheral.wrap(indexerName)
local reader = peripheral.wrap(readerName)
local incubator = peripheral.wrap(incubatorName)

if not crafter then log("ERROR: Crafter not found") return end
if not barrel then log("ERROR: Barrel not found") return end
if not indexer then log("ERROR: Indexer not found") return end
if not reader then log("ERROR: Reader not found") return end
if not incubator then log("ERROR: Incubator not found") return end

log("All peripherals found.")

-- Функция для перемещения: источник отправляет в назначение
local function push(src, srcName, dstName, srcSlot, count, dstSlot)
    return src.pushItems(dstName, srcSlot, count, dstSlot) or 0
end

-- Получаем данные о генах из ридера
local data = reader.getBlockData()
if not data or not data.inv or not data.inv.Items then
    log("Reader returned no inventory data")
    return
end

-- Собираем чистые гены нужных атрибутов
local geneSlots = {}  -- attr -> slot
for _, item in ipairs(data.inv.Items) do
    local geneGroup = item.components and item.components["productivebees:gene_group"]
    if geneGroup and geneGroup.purity == 100 then
        local attr = geneGroup.attribute
        if attr == "behavior" or attr == "endurance" or attr == "productivity" or attr == "weather_tolerance" then
            if not geneSlots[attr] then  -- берём первый попавшийся
                geneSlots[attr] = item.Slot + 1
                log("Selected " .. attr .. " gene from indexer slot " .. (item.Slot + 1))
            end
        end
    end
end

-- Проверяем, все ли атрибуты есть
local neededAttrs = { "behavior", "endurance", "productivity", "weather_tolerance" }
for _, attr in ipairs(neededAttrs) do
    if not geneSlots[attr] then
        log("Missing gene for " .. attr)
        return
    end
end

-- Помещаем гены в крафтер (слоты 3-6)
local geneCrafterSlots = { 3, 4, 5, 6 }
for i, attr in ipairs(neededAttrs) do
    local srcSlot = geneSlots[attr]
    local dstSlot = geneCrafterSlots[i]
    log("Placing " .. attr .. " gene from indexer slot " .. srcSlot .. " to crafter slot " .. dstSlot)
    local moved = push(indexer, indexerName, crafterName, srcSlot, 1, dstSlot)
    if moved > 0 then
        log("  Moved")
    else
        log("  Failed to move")
    end
end

-- Ищем honey_treat в бочке и помещаем в слот 1 крафтера
local honeySlot = nil
for slot = 1, barrel.size() do
    local item = barrel.getItemDetail(slot)
    if item and item.name == "productivebees:honey_treat" then
        honeySlot = slot
        break
    end
end

if honeySlot then
    log("Found honey_treat in barrel slot " .. honeySlot)
    local moved = push(barrel, barrelName, crafterName, honeySlot, 1, 2)
    if moved > 0 then
        log("  Moved honey_treat to crafter slot 2")
    else
        log("  Failed to move honey_treat")
    end
else
    log("No honey_treat found")
    return
end

-- Ждём крафт
log("Waiting 1 second for craft...")
sleep(1)

-- Проверяем слот 11
local resultItem = crafter.getItemDetail(11)
if resultItem then
    log("Item in crafter slot 21: " .. resultItem.name .. " x" .. resultItem.count)
    -- Перемещаем в инкубатор слот 3
    local moved = push(crafter, crafterName, incubatorName, 11, 1, 2)
    if moved > 0 then
        log("Moved result to incubator slot 3")
    else
        log("Failed to move result to incubator")
    end
else
    log("No item in crafter slot 21")
end

-- Итоговое содержимое крафтера для информации
log("\nCrafter contents after test:")
for slot = 1, 21 do
    local item = crafter.getItemDetail(slot)
    if item then
        log("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
    end
end

log("\n=== END OF TEST ===")
print("Test complete. Report saved to " .. reportFile)