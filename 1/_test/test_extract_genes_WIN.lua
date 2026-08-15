-- extract_genes.lua
-- Скрипт для извлечения 100% генов из генного индексатора в бочку.

local logsDir = "logs"
if not fs.exists(logsDir) then
    fs.makeDir(logsDir)
end

local logFile = logsDir .. "/gene_extract.log"

local function log(...)
    local file = fs.open(logFile, "a")
    if file then
        for i = 1, select('#', ...) do
            file.write(tostring(select(i, ...)) .. " ")
        end
        file.write("\n")
        file.close()
    end
end

-- Очищаем лог при старте
local f = fs.open(logFile, "w")
if f then f.close() end
log("=== GENE EXTRACTION STARTED ===")
log("Date: " .. os.date())

-- Конфигурация
local READER_NAME = "block_reader_17"
local BARREL_NAME = "minecraft:barrel_1"
local TARGET_COUNT = 5

-- Нужные атрибуты и их количество
local needed = {
    behavior = TARGET_COUNT,
    endurance = TARGET_COUNT,
    productivity = TARGET_COUNT,
    weather_tolerance = TARGET_COUNT
}

-- Подключаем ридер
local reader = peripheral.wrap(READER_NAME)
if not reader then
    error("Reader '" .. READER_NAME .. "' not found!")
end

-- Находим индексатор по размеру 104
local indexer = nil
for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)
    if p and p.size and p.size() == 104 then
        indexer = p
        log("Found indexer: " .. name)
        break
    end
end

if not indexer then
    error("Indexer with 104 slots not found!")
end

-- Подключаем бочку и проверяем свободное место
local barrel = peripheral.wrap(BARREL_NAME)
if not barrel then
    error("Barrel '" .. BARREL_NAME .. "' not found!")
end

local freeSlots = 0
for slot = 1, barrel.size() do
    if not barrel.getItemDetail(slot) then
        freeSlots = freeSlots + 1
    end
end
log("Barrel free slots: " .. freeSlots)

if freeSlots == 0 then
    error("Barrel is full, cannot extract genes.")
end

-- Получаем данные от ридера
local data = reader.getBlockData()
if not data or not data.inv or not data.inv.Items then
    error("No inventory data from reader.")
end

log("Data received from reader.")
local totalMoved = 0
local movedSlots = 0

for _, item in ipairs(data.inv.Items) do
    local geneGroup = item.components and item.components["productivebees:gene_group"]
    if geneGroup then
        local attr = geneGroup.attribute
        local purity = geneGroup.purity
        if purity == 100 and needed[attr] and needed[attr] > 0 then
            local slotCC = item.Slot + 1  -- перевод в 1-индексацию
            local available = item.count
            local toMove = math.min(available, needed[attr])

            -- Проверяем, есть ли ещё свободные слоты в бочке
            if freeSlots == 0 then
                log("No more free slots in barrel, stopping.")
                break
            end

            log(string.format("Moving %d %s gene(s) from slot %d (reader slot %d)", toMove, attr, slotCC, item.Slot))

            local moved = indexer.pushItems(BARREL_NAME, slotCC, toMove)
            if moved and moved > 0 then
                needed[attr] = needed[attr] - moved
                totalMoved = totalMoved + moved
                movedSlots = movedSlots + 1
                freeSlots = freeSlots - 1  -- приблизительно (если предмет попал в новый слот)
                log("  Moved " .. moved .. ", remaining needed: " .. needed[attr])
            else
                log("  Failed to move (pushItems returned 0)")
            end
        end
    end
end

log("--- Extraction summary ---")
log("Total genes moved: " .. totalMoved)
for attr, left in pairs(needed) do
    if left > 0 then
        log("Missing " .. attr .. ": " .. left .. " pcs")
    else
        log(attr .. ": fully extracted")
    end
end
log("=== EXTRACTION ENDED ===")
print("Extraction completed. See log: " .. logFile)