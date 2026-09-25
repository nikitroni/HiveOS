-- lab_manager.lua
-- Module for sending bees to the laboratory and returning them.
-- Peripheral names are taken from beeos_config.lua (peripherals).
-- Rednet must be open before calling the functions.

local Logger = require("logger")
local ChatNotify = require("chat_notify")
-- Must be the same path (same require cache key) as in BeeOs.lua
-- ("boot/boot_start"): otherwise a SECOND instance of the module loads with its own
-- currentStatus, and busy here will not see the freeze protocol in BeeOs.
local Boot = require("boot/boot_start")
local LabManager = {}
local lock = nil
local lockFile = "lab_lock.dat"

-- Notification to the chat box (as before): prefix [BeeOS], errors in red.
-- We use chat_notify (API autodetect, MOTD colors) instead of raw codes.
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

-- Notification to the chat box (as before): prefix [BeeOS], errors in red.
-- In addition to the file log, so the player immediately sees why the button is blocked.
-- (the implementation via ChatNotify is declared above in this file)

-- Lock check
-- ALWAYS check against the file (do not cache in memory): if the file was deleted by hand,
-- the button should allow sending again.
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
            -- Overwrite with empty so it doesn't get in the way
            local file = fs.open(lockFile, "w")
            file.write("")
            file.close()
        end
    else
        Logger.log("LAB: Lock file already absent")
    end
end

-- Check whether the item is a cage
local function isBeeCage(item)
    return item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage")
end

-- Check free slots in the buffer
local function hasSpaceInBuffer(needSlots)
    local peripherals = getPeripherals()
    --- @type table
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

-- Free exactly count slots in the hive (slots 3-11) by moving items to the buffer
local function freeSlots(hiveBlock, count)
    local peripherals = getPeripherals()
    --- @type table
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

-- Place empty cages into slot 12
local function putEmptyCages(hiveBlock, count)
    local peripherals = getPeripherals()
    --- @type table
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

-- Take cages with bees from slots 3-11 (takes all, returns the count)
local function takeAllBeeCages(hiveBlock)
    local peripherals = getPeripherals()
    --- @type table
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

-- Take cages with retries
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

-- Return cages with bees into slot 12
local function returnBeeCages(hiveBlock, count)
    local peripherals = getPeripherals()
    --- @type table
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

-- Take empty cages from slots 3-11 back to the cage storage
local function takeEmptyCages(hiveBlock)
    local peripherals = getPeripherals()
    --- @type table
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

-- NON-BLOCKING BEE SENDING IN A SEPARATE THREAD
-- ALL peripheral calls to hives/chests (pushItems, getItemDetail)
-- are performed OUTSIDE the main UI loop - in the sendWorker thread, which
-- runs in parallel.waitForAny together with the UI loop. If the peripheral
-- hangs - only this thread hangs, the timer/clicks/rednet remain
-- alive. sleep() inside the thread also does not kill events - parallel gives
-- each thread its own copy of the event queue.
--
--   startSend()  -> validation, sets activeSend, wakes the thread (send_begin)
--   sendWorker() -> thread: waits for send_begin, runs runSendCycle()
--   runSendCycle -> init (free slots, cages into slot 12) ->
--                   wait 2s (sleep) -> take (up to 3x1s) -> broadcast+lock

local activeSend = nil
local SEND_BEGIN = "send_begin"

-- Reset after screen restart
function LabManager.reset()
    activeSend = nil
end

-- Whether sending is currently in progress (gate for hive reads)
function LabManager.isSending()
    return activeSend ~= nil
end

--- Validation and start of sending. Sets the activeSend flag, wakes the thread.
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
    --- @type table
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
    -- Terminal is busy: HeartOS will get "wait" in response to freeze and will not
    -- open Edit until sending completes.
    Boot.setCurrentStatus("busy")
    Logger.log("LAB: send started for hive " .. hiveId .. " (" .. expected .. " bees)")
    os.queueEvent(SEND_BEGIN)
    return state
end

--- Full send cycle (executed in sendWorker).
local function runSendCycle()
    local st = activeSend
    if not st then return end

    local ok, cycleErr = pcall(function()
        local peripherals = getPeripherals()

        -- ===== init: free slots 3-11 =====
        local occupied = 0
        for slot = 3, 11 do
            if st.hiveBlock.getItemDetail(slot) then occupied = occupied + 1 end
        end
        local free = 9 - occupied
        local needToFree = math.max(0, st.expected - free)
        if needToFree > 0 then
            --- @type table
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

        -- ===== init: empty cages into slot 12 =====
        --- @type table
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

        -- ===== wait: give the bees time to move =====
        sleep(2)

        -- ===== take: collect the bees =====
        --- @type table
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
                bee_count = taken,  -- actual number of bees sent
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

    -- Finish: clear the send flag, wake the main loop for redraw.
    -- Set the free status in any case (success or cycle error).
    activeSend = nil
    Boot.setCurrentStatus("free")
    os.queueEvent("send_complete")
end

--- Send thread. Started in parallel.waitForAny TOGETHER with the UI loop.
-- The whole loop is wrapped in pcall - a hung/failed send does not kill parallel.
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

--- Force reset of sending if it has been stuck longer than maxAgeSec.
-- Called from processTick (main loop). Returns true if it reset.
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

--- Old state function (no longer called). Kept to not break require.
function LabManager.tickSend(now)
    return true
end

-- Cycle completion function (return of bees)
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