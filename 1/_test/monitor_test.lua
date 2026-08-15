-- Укажи имя своего маленького монитора
local MONITOR_NAME = "monitor_3"
local mon = peripheral.wrap(MONITOR_NAME)

if not mon then
    error("Monitor " .. MONITOR_NAME .. " not found!")
end

local logPath = "logs/monitor_scales.txt"
if not fs.exists("logs") then fs.makeDir("logs") end
local file = fs.open(logPath, "w")

local scales = {0.5, 1, 1.5, 2, 3, 4, 5}
local testText = "GENE"

file.writeLine("--- Monitor Scale Test Result ---")
print("Starting scale test on " .. MONITOR_NAME)

for _, s in ipairs(scales) do
    -- Устанавливаем масштаб
    mon.setTextScale(s)
    mon.clear()
    
    -- Получаем размеры при этом масштабе
    local w, h = mon.getSize()
    
    -- Записываем в файл
    local info = string.format("Scale: %.1f | Width: %d | Height: %d", s, w, h)
    file.writeLine(info)
    
    -- Выводим на монитор для визуальной оценки
    mon.setCursorPos(1, 1)
    mon.write(testText)
    
    print("Testing " .. info)
    
    -- Ждем 2 секунды, чтобы ты успел посмотреть на монитор
    os.sleep(2)
end

file.close()
mon.setTextScale(1) -- Возвращаем стандарт после теста
print("Test finished. Results saved in " .. logPath)