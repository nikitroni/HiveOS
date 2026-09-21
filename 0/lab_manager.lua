-- lab_manager.lua
-- Модуль для отправки пчёл в лабораторию и их возврата.
-- Имена периферий берутся из beeos_config.lua (peripherals).
-- Rednet должен быть открыт до вызова функций.

local Logger = require("logger")
local ChatNotify = require("chat_notify")
-- Обязательно тот же путь (тот же ключ кэша require), что и в BeeOs.lua
-- ("boot/boot_start"): иначе загрузится ВТОРОЙ экземпляр модуля с отдельным
-- currentStatus, и busy здесь не увидит протокол freeze в BeeOs.
local Boot = require("boot/boot_start")
local LabManager = {}
local lock = nil
local lockFile = "lab_lock.dat"

-- Уведомление в чат-бокс (как было раньше): префикс [BeeOS], ошибки красным.
-- Используем chat_notify (автодетект API, MOTD-цвета), а не сырые коды.
local function notifyChat(msg, isError)
    if isError then
        ChatNotify.sendError(msg)
    else
        ChatNotify.sendSuccess(msg)
    end
end

local function getPeripherals()
    local cfg = nil
    if fs.exists("beeos_config.lua") then
        local handler, err = loadfile("beeos_config.lua")
        if handler then
            local ok, result = pcall(handler)
            if ok and type(result) == "table" then cfg = result end
        end
    end
    if cfg and cfg.peripherals then return cfg.peripherals end
    return {}
end

-- Уведомление в чат-бокс (как было раньше): префикс [BeeOS], ошибки красным.
-- Помимо файлового лога, чтобы игрок сразу видел, почему блокируется кнопка.
-- (реализация через ChatNotify объявлена выше в этом файле)

-- Проверка блокировки
-- ВСЕГДА сверяем с файлом (не кэшируем в памяти): если файл удалён руками,
-- кнопка должна снова разрешить отправку.
function LabManager.isLocked()
    if not fs.exists(lockFile) then
        lock = nil
        return nil
    end
    local file = fs.open(lockFile, "r")
    local lockedHive = file.readAll()
    file.close()
    lockedHive = tonumber(lockedHive) or lockedHive
    lock = lockedHive
    return lock
end

function LabManager.lock(hiveId)
    lock = hiveId
    local file = fs.open(lockFile, "w")
    file.write(tostring(hiveId))
    file.close()
    Logger.log("LAB: Lock set for hive " .. hiveId)
end

function LabManager.unlock()
    lock = nil
    if fs.exists(lockFile) then
        local success, err = pcall(fs.delete, lockFile)
        if success then
            Logger.log("LAB: Lock removed (file deleted)")
        else
            Logger.log("LAB: Failed to delete lock file: " .. tostring(err))
            -- Перезаписываем пустым, чтобы не мешал
            local file = fs.open(lockFile, "w")
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
    local peripherals = getPeripherals()
    local buffer = peripheral.wrap(peripherals.buffer_chest)
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
    local peripherals = getPeripherals()
    local buffer = peripheral.wrap(peripherals.buffer_chest)
    if not buffer then
        Logger.log("LAB: Buffer chest not found")
        return false
    end

    local freed = 0
    for slot = 3, 11 do
        if freed >= count then break end
        local item = hiveBlock.getItemDetail(slot)
        if item then
            local moved = hiveBlock.pushItems(peripherals.buffer_chest, slot)
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
    local peripherals = getPeripherals()
    local cageChest = peripheral.wrap(peripherals.cage_chest)
    if not cageChest then
        Logger.log("LAB: Cage chest '" .. tostring(peripherals.cage_chest) .. "' not found")
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
    local peripherals = getPeripherals()
    local labChest = peripheral.wrap(peripherals.lab_chest)
    if not labChest then
        Logger.log("LAB: Lab chest '" .. tostring(peripherals.lab_chest) .. "' not found")
        return 0
    end

    local taken = 0
    for slot = 3, 11 do
        local item = hiveBlock.getItemDetail(slot)
        if isBeeCage(item) then
            local moved = hiveBlock.pushItems(peripherals.lab_chest, slot)
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
    local peripherals = getPeripherals()
    local labChest = peripheral.wrap(peripherals.lab_chest)
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
    local peripherals = getPeripherals()
    local cageChest = peripheral.wrap(peripherals.cage_chest)
    if not cageChest then
        Logger.log("LAB: Cage chest not found for taking empty cages")
        return 0
    end

    local taken = 0
    for slot = 3, 11 do
        local item = hiveBlock.getItemDetail(slot)
        if isBeeCage(item) then
            local moved = hiveBlock.pushItems(peripherals.cage_chest, slot)
            if moved > 0 then
                taken = taken + moved
                Logger.log("LAB: Took empty cage from hive slot " .. slot)
            end
        end
    end
    return taken
end

-- НЕБЛОКИРУЮЩАЯ ОТПРАВКА ПЧЁЛ В ОТДЕЛЬНОМ ПОТОКЕ
-- ВСЕ периферийные вызовы к ульям/сундукам (pushItems, getItemDetail)
-- выполняются ВНЕ главного UI-цикла — в потоке sendWorker, который
-- запущен в parallel.waitForAny вместе с UI-циклом. Если периферия
-- зависнет — зависнет только этот поток, таймер/клики/rednet остаются
-- живы. sleep() внутри потока тоже не убивает события — parallel даёт
-- каждому потоку свою копию очереди событий.
--
--   startSend()  → валидация, ставит activeSend, будит поток (send_begin)
--   sendWorker() → поток: ждёт send_begin, выполняет runSendCycle()
--   runSendCycle → init (освободить слоты, клетки в слот 12) →
--                   wait 2с (sleep) → take (до 3×1с) → broadcast+lock

local activeSend = nil
local SEND_BEGIN = "send_begin"

-- Сброс после перезапуска экранов
function LabManager.reset()
    activeSend = nil
end

-- Идёт ли сейчас отправка (для гейта чтения ульев)
function LabManager.isSending()
    return activeSend ~= nil
end

--- Валидация и запуск отправки. Ставит флаг activeSend, будит поток.
function LabManager.startSend(hiveId, hiveData, hiveBlockName)
    if LabManager.isSending() then
        Logger.log("LAB: startSend refused, already in progress")
        return nil
    end
    if not hiveBlockName then
        Logger.log("LAB: startSend: hiveBlockName is nil")
        return nil
    end
    if not hiveData then
        Logger.log("LAB: startSend: hiveData is nil")
        return nil
    end
    local hiveBlock = peripheral.wrap(hiveBlockName)
    if not hiveBlock then
        Logger.log("LAB: startSend: cannot wrap hive block: " .. tostring(hiveBlockName))
        notifyChat("Cannot access hive " .. tostring(hiveId), true)
        return nil
    end
    if LabManager.isLocked() then
        Logger.log("LAB: startSend: already locked: " .. tostring(LabManager.isLocked()))
        notifyChat(string.format("Lab busy - bees of hive %s are being processed, wait", tostring(LabManager.isLocked())), true)
        return nil
    end
    if not hiveData.bees or #hiveData.bees == 0 then
        Logger.log("LAB: startSend: no bees in hive")
        notifyChat("No bees in this hive", true)
        return nil
    end

    local expected = #hiveData.bees
    local state = {
        hiveId = hiveId,
        hiveBlockName = hiveBlockName,
        hiveBlock = hiveBlock,
        expected = expected,
        _started = os.clock(),
    }
    activeSend = state
    -- Терминал занят: HeartOS в ответ на freeze получит "wait" и не
    -- откроет Edit, пока отправка не завершится.
    Boot.setCurrentStatus("busy")
    Logger.log("LAB: send started for hive " .. hiveId .. " (" .. expected .. " bees)")
    os.queueEvent(SEND_BEGIN)
    return state
end

--- Полный цикл отправки (выполняется в sendWorker).
local function runSendCycle()
    local st = activeSend
    if not st then return end

    local ok, cycleErr = pcall(function()
        local peripherals = getPeripherals()

        -- ===== init: освобождаем слоты 3-11 =====
        local occupied = 0
        for slot = 3, 11 do
            if st.hiveBlock.getItemDetail(slot) then occupied = occupied + 1 end
        end
        local free = 9 - occupied
        local needToFree = math.max(0, st.expected - free)
        if needToFree > 0 then
            local buffer = peripheral.wrap(peripherals.buffer_chest)
            if not buffer then
                error("Buffer chest not found")
            end
            local freed = 0
            for slot = 3, 11 do
                if freed >= needToFree then break end
                local item = st.hiveBlock.getItemDetail(slot)
                if item then
                    local m = st.hiveBlock.pushItems(peripherals.buffer_chest, slot)
                    if m > 0 then freed = freed + 1 end
                end
            end
            if freed < needToFree then
                error("Could not free enough slots (freed " .. freed .. ", needed " .. needToFree .. ")")
            end
        end

        -- ===== init: пустые клетки в слот 12 =====
        local cageChest = peripheral.wrap(peripherals.cage_chest)
        local placed = 0
        if cageChest then
            local slot12Item = st.hiveBlock.getItemDetail(12)
            if not slot12Item then
                for slot = 1, cageChest.size() do
                    if placed >= st.expected then break end
                    local item = cageChest.getItemDetail(slot)
                    if isBeeCage(item) then
                        local toTake = math.min(item.count, st.expected - placed)
                        local m = cageChest.pushItems(st.hiveBlockName, slot, toTake, 12)
                        if m > 0 then placed = placed + m end
                    end
                end
            end
        end
        if placed < st.expected then
            error("Not enough empty cages in cage chest (placed " .. placed .. ", needed " .. st.expected .. ")")
        end
        Logger.log("LAB: send init done, waiting 2s")

        -- ===== wait: даём пчёлам переместиться =====
        sleep(2)

        -- ===== take: забираем пчёл =====
        local labChest = peripheral.wrap(peripherals.lab_chest)
        if not labChest then
            error("Lab chest not found")
        end

        local taken = 0
        local attempts = 0
        while taken < st.expected and attempts < 3 do
            attempts = attempts + 1
            for slot = 3, 11 do
                local item = st.hiveBlock.getItemDetail(slot)
                if isBeeCage(item) then
                    local m = st.hiveBlock.pushItems(peripherals.lab_chest, slot)
                    if m > 0 then taken = taken + m end
                end
            end
            if taken < st.expected and attempts < 3 then
                Logger.log("LAB: attempt " .. attempts .. " took " .. taken .. " cages, need " .. st.expected)
                sleep(1)
            end
        end

        if taken >= st.expected then
            LabManager.lock(st.hiveId)
            Logger.log("LAB: Successfully sent " .. taken .. " bees from hive " .. st.hiveId)
            notifyChat(string.format("%d bees sent to lab from hive %s", taken, tostring(st.hiveId)))
            rednet.broadcast({
                type = "lab_request",
                hive_id = st.hiveId,
                bee_count = taken,  -- реальное количество отправленных пчёл
                hive_block = st.hiveBlockName,
                sender_id = os.getComputerID(),
            })
            Logger.log("LAB: Request broadcast to lab")
        else
            error("Only " .. taken .. " bees taken, expected " .. st.expected)
        end
    end)

    if not ok then
        Logger.log("LAB: send cycle error: " .. tostring(cycleErr))
        notifyChat("Send failed: " .. tostring(cycleErr), true)
    end

    -- Завершаем: снимаем флаг отправки, будим главный цикл на перерисовку.
    -- Статус free выставляем в любом случае (успех или ошибка цикла).
    activeSend = nil
    Boot.setCurrentStatus("free")
    os.queueEvent("send_complete")
end

--- Поток отправки. Запускается в parallel.waitForAny ВМЕСТЕ с UI-циклом.
-- Весь цикл обёрнут в pcall — зависшая/ошибочная отправка не убивает parallel.
function LabManager.sendWorker()
    while true do
        local ok, err = pcall(function()
            os.pullEvent(SEND_BEGIN)
            runSendCycle()
        end)
        if not ok then
            Logger.log("LAB: sendWorker error: " .. tostring(err))
        end
    end
end

--- Принудительный сброс отправки, если она зависла дольше maxAgeSec.
-- Вызывается из processTick (главный цикл). Возвращает true если сбросил.
local function abortStuckSend(maxAgeSec)
    if not activeSend then return false end
    if not maxAgeSec then maxAgeSec = 60 end
    if os.clock() - (activeSend._started or 0) < maxAgeSec then return false end
    Logger.log("LAB: aborting stuck send for hive " .. tostring(activeSend.hiveId) .. " (>" .. maxAgeSec .. "s)")
    activeSend = nil
    Boot.setCurrentStatus("free")
    os.queueEvent("send_complete")
    return true
end

function LabManager.abortStuckSend()
    abortStuckSend(60)
end

--- Старая функция состояния (больше не вызывается). Оставлена чтобы не ломать require.
function LabManager.tickSend(now)
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
    notifyChat(string.format("%d bees returned to hive %s", beeCount or 0, tostring(hiveId)))
    return true
end

return LabManager