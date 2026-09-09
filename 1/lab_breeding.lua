-- lab_breeding.lua
-- Модуль для размножения пчёл по запросу из чата.
-- Использует библиотеку lab_lib (периферия из HeartOS-конфига через адаптер).

local lib = require("lab_lib")

local Breeding = {}

-- Цветок (можно вынести в библиотеку)
local FLOWER = "minecraft:sunflower"

-- ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====================
local function chatMessage(msg)
    local chat = peripheral.wrap(lib.chat_box)
    if chat then
        pcall(function()
            chat.sendMessage(msg, { prefix = "LabOS", prefixColor = "blue", utf8 = true })
        end)
    else
        print(msg)
    end
end

-- ==================== ОСНОВНАЯ ФУНКЦИЯ ====================
function Breeding.run(logCallback)
    logCallback = logCallback or function() end

    -- Получаем имена из библиотеки (периферия из конфига HeartOS)
    local labChestName = lib.peripherals.lab_chest
    local cageChestName = lib.peripherals.cage_chest
    local resourceChestName = lib.peripherals.resource_chest
    local chamberName = lib.peripherals.breeding_chamber

    if not chamberName then
        logCallback("ERROR: breeding_chamber not defined in config")
        return false
    end

    -- Подключаем периферии
    local labChest = peripheral.wrap(labChestName)
    local cageChest = peripheral.wrap(cageChestName)
    local resourceChest = peripheral.wrap(resourceChestName)
    local chamber = peripheral.wrap(chamberName)

    if not labChest then logCallback("ERROR: lab chest missing"); return false end
    if not cageChest then logCallback("ERROR: cage chest missing"); return false end
    if not resourceChest then logCallback("ERROR: resource chest missing"); return false end
    if not chamber then logCallback("ERROR: breeding chamber missing"); return false end

    logCallback("Breeding process started. Waiting for command...")
    chatMessage("Breeding: Enter number of bees (e.g., 4)")

    -- Ожидаем ввод через обычный игровой чат (с таймаутом, чтобы не висеть
    -- вечно и не держать статус busy)
    local count = nil
    local deadline = os.clock() + 60
    while true do
        local ok, evt, username, chatMsg = pcall(os.pullEventTimeout, 1, "chat")
        if not ok or os.clock() >= deadline then
            chatMessage("Breeding timeout - no input, aborted.")
            logCallback("ERROR: breeding input timeout")
            return false
        end
        if evt == "chat" and chatMsg then
            local num = tonumber(chatMsg)
            if num and num > 0 then
                count = num
                break
            else
                chatMessage("Invalid number, try again:")
            end
        end
    end

    logCallback(string.format("Breeding %d bees.", count))

    -- === ПРОВЕРКА РЕСУРСОВ ===
    -- Пустые клетки
    local cageCount = 0
    for slot = 1, cageChest.size() do
        local item = cageChest.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            cageCount = cageCount + item.count
        end
    end
    if cageCount < count then
        chatMessage(string.format("Not enough empty cages (need %d, have %d)", count, cageCount))
        logCallback("ERROR: not enough cages")
        return false
    end

    -- Цветы
    local flowerCount = 0
    for slot = 1, resourceChest.size() do
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == FLOWER then
            flowerCount = flowerCount + item.count
        end
    end
    if flowerCount < 2 * count then
        chatMessage(string.format("Not enough flowers (need %d, have %d)", 2*count, flowerCount))
        logCallback("ERROR: not enough flowers")
        return false
    end

    -- === ПЕРЕМЕЩЕНИЕ РЕСУРСОВ ===
    -- 1. Пустые клетки в слот 1
    logCallback("Placing " .. count .. " cages into slot 1")
    local cagesPlaced = 0
    for slot = 1, cageChest.size() do
        if cagesPlaced >= count then break end
        local item = cageChest.getItemDetail(slot)
        if item and (item.name == "productivebees:bee_cage" or item.name == "productivebees:sturdy_bee_cage") then
            local need = count - cagesPlaced
            local toTake = math.min(item.count, need)
            local moved = cageChest.pushItems(chamberName, slot, toTake, 1)
            if moved > 0 then
                cagesPlaced = cagesPlaced + moved
            end
        end
    end
    if cagesPlaced < count then
        chatMessage("ERROR: failed to place cages")
        return false
    end

    -- 2. Цветы в слот 4
    logCallback("Placing " .. count .. " flowers into slot 4")
    local flowersSlot4 = 0
    for slot = 1, resourceChest.size() do
        if flowersSlot4 >= count then break end
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == FLOWER then
            local need = count - flowersSlot4
            local toTake = math.min(item.count, need)
            local moved = resourceChest.pushItems(chamberName, slot, toTake, 4)
            if moved > 0 then
                flowersSlot4 = flowersSlot4 + moved
            end
        end
    end
    if flowersSlot4 < count then
        chatMessage("ERROR: not enough flowers for slot 4")
        return false
    end

    -- 3. Цветы в слот 5
    logCallback("Placing " .. count .. " flowers into slot 5")
    local flowersSlot5 = 0
    for slot = 1, resourceChest.size() do
        if flowersSlot5 >= count then break end
        local item = resourceChest.getItemDetail(slot)
        if item and item.name == FLOWER then
            local need = count - flowersSlot5
            local toTake = math.min(item.count, need)
            local moved = resourceChest.pushItems(chamberName, slot, toTake, 5)
            if moved > 0 then
                flowersSlot5 = flowersSlot5 + moved
            end
        end
    end
    if flowersSlot5 < count then
        chatMessage("ERROR: not enough flowers for slot 5")
        return false
    end

    -- === ЦИКЛ СБОРА ПОТОМКОВ ===
    local collected = 0
    for i = 1, count do
        logCallback(string.format("Waiting for offspring %d/%d...", i, count))
        sleep(3)

        local result = chamber.getItemDetail(6)
        if result then
            -- ВНИМАНИЕ: используем labChestName (строку), а не объект labChest!
            local moved = chamber.pushItems(labChestName, 6, 1)
            if moved > 0 then
                collected = collected + moved
                logCallback("Collected: " .. result.name)
            else
                logCallback("ERROR: failed to collect offspring")
            end
        else
            logCallback("No offspring yet, waiting more...")
            sleep(2)
            result = chamber.getItemDetail(6)
            if result then
                local moved = chamber.pushItems(labChestName, 6, 1)
                if moved > 0 then
                    collected = collected + moved
                    logCallback("Collected: " .. result.name)
                end
            end
        end
    end

    logCallback(string.format("Breeding completed. Collected %d bees.", collected))
    chatMessage(string.format("Breeding done. %d bees added to lab chest.", collected))
    return true
end

return Breeding