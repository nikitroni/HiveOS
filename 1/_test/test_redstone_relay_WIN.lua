-- test_redstone_relay.lua
-- Тестирует редстоун-реле: отправляет 3 коротких сигнала на стороны "front" (север) и "top" (верх).
-- Логи сохраняются в папку logs.

local logsDir = "logs"
if not fs.exists(logsDir) then
    fs.makeDir(logsDir)
end

local reportFile = logsDir .. "/redstone_relay_test.txt"

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
    log("=== REDSTONE RELAY TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

local relay = peripheral.wrap("redstone_relay_0")
if not relay then
    log("ERROR: redstone_relay_0 not found")
    return
end

log("Relay found. Available methods:")
for k, v in pairs(relay) do
    if type(v) == "function" then
        log("  " .. k)
    end
end

-- Стороны для теста: front (север) и top (верх)
local sides = {"front", "top"}

-- Функция для отправки импульса
local function sendPulse(side, duration)
    log("Sending pulse on side: " .. side .. " (duration: " .. duration .. "s)")
    
    -- Включаем сигнал
    local success, err = pcall(function()
        relay.setOutput(side, true)
    end)
    
    if success then
        log("  Signal ON")
        sleep(duration)
        
        -- Выключаем
        local ok, err2 = pcall(function()
            relay.setOutput(side, false)
        end)
        if ok then
            log("  Signal OFF")
        else
            log("  Failed to turn OFF: " .. tostring(err2))
        end
    else
        log("  Failed to setOutput: " .. tostring(err))
    end
end

-- Отправляем по 3 импульса на каждую сторону
for _, side in ipairs(sides) do
    log("\n--- Testing side: " .. side .. " ---")
    for i = 1, 3 do
        log("Pulse #" .. i)
        sendPulse(side, 0.5)  -- длительность 0.2 секунды
        if i < 3 then
            sleep(2.0)  -- пауза между импульсами
        end
    end
    log("Completed 3 pulses on " .. side)
    sleep(1)  -- пауза между сторонами
end

log("\n=== END OF TEST ===")
print("Test complete. Report saved to " .. reportFile)