-- lab_manager.lua
-- Модуль для отправки пчёл в лабораторию и их возврата.
-- Использует конфиг lab_config.lua для имён периферий.
-- Rednet должен быть открыт до вызова функций.

local config = require("lab_config")
local Logger = require("logger")
local LabManager = {}
local lock = nil

-- Проверка блокировки
function LabManager.isLocked()
    if lock then return lock end
    if fs.exists(config.lock_file) then
        local file = fs.open(config.lock_file, "r")
        local lockedHive = file.readAll()
        file.close()
        lock = tonumber(lockedHive) or lockedHive
        return lock
    end
    return nil
end

function LabManager.lock(hiveId)
    lock = hiveId
    local file = fs.open(config.lock_file, "w")
    file.write(tostring(hiveId))
    file.close()
    Logger.log("LAB: Lock set for hive " .. hiveId)
end

function LabManager.unlock()
    lock = nil
    if fs.exists(config.lock_file) then
        local success, err = pcall(fs.delete, config.lock_file)
        if success then
            Logger.log("LAB: Lock removed (file deleted)")
        else
            Logger.log("LAB: Failed to delete lock file: " .. tostring(err))
            -- Перезаписываем пустым, чтобы не мешал
            local file = fs.open(config.lock_file, "w")
            file.write("")
            file.close()
        end
    else
        Logger.log("LAB: Lock file already absent")
    end
end

-- Проверка, является ли предмет клеткой
local function isBeeCage(item)
    return item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage")
end

-- Проверка свободных слотов в буфере
local function hasSpaceInBuffer(needSlots)
    local buffer = peripheral.wrap(config.buffer_chest)
    if not buffer then
        Logger.log("LAB: Buffer chest not found")
        return false
    end
    local freeSlots = 0
    for slot = 1, buffer.size() do
        if not buffer.getItemDetail(slot) then
            freeSlots = freeSlots + 1
        end
    end
    if freeSlots >= needSlots then
        return true
    else
        Logger.log("LAB: Buffer chest has only " .. freeSlots .. " free slots, need " .. needSlots)
        return false
    end
end

-- Освободить ровно count слотов в улье (слоты 3-11), перемещая предметы в буфер
local function freeSlots(hiveBlock, count)
    local buffer = peripheral.wrap(config.buffer_chest)
    if not buffer then
        Logger.log("LAB: Buffer chest not found")
        return false
    end

    local freed = 0
    for slot = 3, 11 do
        if freed >= count then break end
        local item = hiveBlock.getItemDetail(slot)
        if item then
            local moved = hiveBlock.pushItems(config.buffer_chest, slot)
            if moved > 0 then
                freed = freed + 1
                Logger.log("LAB: Moved " .. item.name .. " from slot " .. slot .. " to buffer")
            end
        end
    end

    if freed >= count then
        Logger.log("LAB: Successfully freed " .. freed .. " slots")
        return true
    else
        Logger.log("LAB: Failed to free enough slots (freed " .. freed .. ", needed " .. count .. ")")
        return false
    end
end

-- Помещение пустых клеток в слот 12
local function putEmptyCages(hiveBlock, count)
    local cageChest = peripheral.wrap(config.cage_chest)
    if not cageChest then
        Logger.log("LAB: Cage chest '" .. config.cage_chest .. "' not found")
        return 0
    end

    local slot12Item = hiveBlock.getItemDetail(12)
    if slot12Item then
        Logger.log("LAB: Hive slot 12 is occupied by " .. slot12Item.name .. " – cannot place cages")
        return 0
    end

    local placed = 0
    for slot = 1, cageChest.size() do
        if placed >= count then break end
        local item = cageChest.getItemDetail(slot)
        if isBeeCage(item) then
            local toTake = math.min(item.count, count - placed)
            local moved = cageChest.pushItems(peripheral.getName(hiveBlock), slot, toTake, 12)
            if moved > 0 then
                placed = placed + moved
                Logger.log("LAB: Placed " .. moved .. " empty cages into hive slot 12")
            end
        end
    end
    return placed
end

-- Забор клеток с пчёлами из слотов 3-11 (забирает все, возвращает количество)
local function takeAllBeeCages(hiveBlock)
    local labChest = peripheral.wrap(config.lab_chest)
    if not labChest then
        Logger.log("LAB: Lab chest '" .. config.lab_chest .. "' not found")
        return 0
    end

    local taken = 0
    for slot = 3, 11 do
        local item = hiveBlock.getItemDetail(slot)
        if isBeeCage(item) then
            local moved = hiveBlock.pushItems(config.lab_chest, slot)
            if moved > 0 then
                taken = taken + moved
                Logger.log("LAB: Took " .. moved .. " bee cage from hive slot " .. slot)
            end
        end
    end
    return taken
end

-- Забор клеток с повторными попытками
local function takeBeeCagesWithRetry(hiveBlock, expectedCount, maxAttempts)
    maxAttempts = maxAttempts or 3
    local taken = 0
    for attempt = 1, maxAttempts do
        taken = takeAllBeeCages(hiveBlock)
        if taken >= expectedCount then
            break
        end
        Logger.log("LAB: Attempt " .. attempt .. " took " .. taken .. " cages, need " .. expectedCount .. ". Waiting...")
        sleep(1)
    end
    return taken
end

-- Возврат клеток с пчёлами в слот 12
local function returnBeeCages(hiveBlock, count)
    local labChest = peripheral.wrap(config.lab_chest)
    if not labChest then
        Logger.log("LAB: Lab chest not found for return")
        return 0
    end

    local slot12Item = hiveBlock.getItemDetail(12)
    if slot12Item then
        Logger.log("LAB: Slot 12 is occupied, cannot return cages")
        return 0
    end

    local returned = 0
    for slot = 1, labChest.size() do
        if returned >= count then break end
        local item = labChest.getItemDetail(slot)
        if isBeeCage(item) then
            local moved = labChest.pushItems(peripheral.getName(hiveBlock), slot, 1, 12)
            if moved > 0 then
                returned = returned + moved
                Logger.log("LAB: Returned 1 bee cage to hive slot 12")
            end
        end
    end
    return returned
end

-- Забор пустых клеток из слотов 3-11 обратно в хранилище клеток
local function takeEmptyCages(hiveBlock)
    local cageChest = peripheral.wrap(config.cage_chest)
    if not cageChest then
        Logger.log("LAB: Cage chest not found for taking empty cages")
        return 0
    end

    local taken = 0
    for slot = 3, 11 do
        local item = hiveBlock.getItemDetail(slot)
        if isBeeCage(item) then
            local moved = hiveBlock.pushItems(config.cage_chest, slot)
            if moved > 0 then
                taken = taken + moved
                Logger.log("LAB: Took empty cage from hive slot " .. slot)
            end
        end
    end
    return taken
end

-- Основная функция отправки пчёл
function LabManager.sendBees(hiveId, hiveData, hiveBlockName)
    -- Получаем объект улья по имени
    local hiveBlock = peripheral.wrap(hiveBlockName)
    if not hiveBlock then
        Logger.log("LAB: Failed to wrap hive block: " .. tostring(hiveBlockName))
        return false
    end

    local locked = LabManager.isLocked()
    if locked then
        Logger.log("LAB: Cannot send currently processing hive " .. locked)
        return false
    end

    if not hiveData.bees or #hiveData.bees == 0 then
        Logger.log("LAB: No bees in hive")
        return false
    end

    local expectedBeeCount = #hiveData.bees
    Logger.log("LAB: Attempting to send " .. expectedBeeCount .. " bees from hive " .. hiveId)

    -- Подсчитываем занятые и свободные слоты (3-11)
    local occupied = 0
    for slot = 3, 11 do
        if hiveBlock.getItemDetail(slot) then
            occupied = occupied + 1
        end
    end
    local free = 9 - occupied
    Logger.log("LAB: Hive has " .. occupied .. " occupied slots, " .. free .. " free slots")

    -- Сколько слотов нужно освободить, чтобы свободных стало не меньше expectedBeeCount
    local needToFree = math.max(0, expectedBeeCount - free)
    Logger.log("LAB: Need to free " .. needToFree .. " slots to have room for " .. expectedBeeCount .. " bees")

    -- Проверяем буфер
    if needToFree > 0 then
        if not hasSpaceInBuffer(needToFree) then
            Logger.log("LAB: Buffer chest does not have enough free slots. Aborting.")
            return false
        end

        -- Освобождаем ровно needToFree слотов
        if not freeSlots(hiveBlock, needToFree) then
            Logger.log("LAB: Could not free enough slots, aborting")
            return false
        end
    end

    -- Шаг 2: Помещаем пустые клетки в слот 12
    local cagesPlaced = putEmptyCages(hiveBlock, expectedBeeCount)
    if cagesPlaced < expectedBeeCount then
        Logger.log("LAB: Only " .. cagesPlaced .. " empty cages placed (needed " .. expectedBeeCount .. ")")
        return false
    end

    sleep(2)  -- ждём обработки

    -- Шаг 3: Забираем клетки с пчёлами с повторными попытками
    local beesTaken = takeBeeCagesWithRetry(hiveBlock, expectedBeeCount, 3)
    Logger.log("LAB: Actually took " .. beesTaken .. " bee cages")

    if beesTaken < expectedBeeCount then
        Logger.log("LAB: ERROR: Only " .. beesTaken .. " bees taken, expected " .. expectedBeeCount .. ". Aborting.")
        return false
    end

    LabManager.lock(hiveId)
    Logger.log("LAB: Successfully sent " .. beesTaken .. " bees from hive " .. hiveId)

    if not hiveBlockName then
        Logger.log("LAB: ERROR: hiveBlockName is nil!")
        return false
    end
    rednet.broadcast({
    type = "lab_request",
    hive_id = hiveId,
    bee_count = expectedBeeCount,   -- используем правильную переменную
    hive_block = hiveBlockName
})
Logger.log("LAB: Request broadcast to lab")

    return true
end

-- Функция завершения цикла (возврат пчёл)
function LabManager.returnBeesToHive(hiveId, beeCount)
    local locked = LabManager.isLocked()
    if not locked or tonumber(locked) ~= tonumber(hiveId) then
        Logger.log("LAB: No active lock for hive " .. tostring(hiveId) .. " or mismatch")
        return false
    end
    LabManager.unlock()
    Logger.log("LAB: Cycle completed for hive " .. hiveId)
    return true
end

return LabManager