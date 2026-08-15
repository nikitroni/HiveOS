local mon = peripheral.wrap("monitor_0")

if not mon then
    print("Error: Monitor not found!")
    return
end

-- Список масштабов, которые мы хотим проверить
local scales = {0.5, 1.0, 1.5, 2.0}

for _, s in ipairs(scales) do
    mon.setTextScale(s)
    mon.clear()
    mon.setCursorPos(1, 1)
    
    local w, h = mon.getSize()
    
    -- Выводим информацию на монитор
    mon.setCursorPos(1, 1)
    mon.setTextColor(colors.yellow)
    mon.write("SCALE: " .. tostring(s))
    
    mon.setCursorPos(1, 3)
    mon.setTextColor(colors.white)
    mon.write("Resolution: " .. w .. "x" .. h)
    
    mon.setCursorPos(1, 5)
    mon.setTextColor(colors.lime)
    mon.write("Example: Hive #12 [Active]")
    
    mon.setCursorPos(1, 6)
    mon.setTextColor(colors.lightBlue)
    mon.write("Bees: Draconic x5")
    
    -- Ждем 3 секунды, чтобы ты успел рассмотреть и заскринить
    sleep(3)
end

mon.setTextScale(1.0) -- Возвращаем стандарт после теста
print("Test finished!")