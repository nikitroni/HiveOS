local function bootMenu(monitor, duration)
    duration = duration or 10

    -- 1. Загружаем фон
    local bg = paintutils.loadImage("boot/HUD_boot.nfp")
    if not bg then
        error("HUD_boot.nfp not found")
    end

    -- 2. Настройка конкретного монитора (без term.redirect)
    monitor.setTextScale(1.0)
    monitor.setBackgroundColor(colors.gray)
    monitor.clear()

    -- 3. Рисуем фон
    -- Используем специальный способ отрисовки для конкретного монитора
    local oldTerm = term.redirect(monitor)
    paintutils.drawImage(bg, 1, 1)
    term.redirect(oldTerm) -- Сразу возвращаем, чтобы не мешать другим потокам

    -- 4. Загружаем конфиг
    local cfg = require("boot/HUD_boot_config")
    
    -- -- 5. Рисуем символы BEEOS (через объект monitor)
    -- Функция для превращения текстового шаблона в таблицу координат
    local function parsePattern(pattern, startX, startY)
        local result = {}
        for rowIdx, line in ipairs(pattern) do
            local y = startY + rowIdx - 1
            result[y] = {}
            for colIdx = 1, #line do
                local char = line:sub(colIdx, colIdx)
                if char ~= " " then -- Пробелы игнорируем, чтобы видеть фон
                    local x = startX + colIdx - 1
                    result[y][x] = {char = char, fg = colors.yellow}
                end
            end
        end
        return result
    end

    -- Автоматически заполняем cfg.foreground из твоего шаблона
    if cfg.honeycomb_pattern then
        cfg.foreground = parsePattern(cfg.honeycomb_pattern, cfg.pattern_start.x, cfg.pattern_start.y)
    end

    -- 6. Прогресс-бар (анимация)
    local area = cfg.progress_area
    local width = area.maxX - area.minX + 1
    local start = os.clock()
    local lastPercent = -1

    while os.clock() - start < duration do
        local p = (os.clock() - start) / duration
        local percent = math.floor(p * 100)
        local fill = math.floor(p * width)

        if percent ~= lastPercent then
            for y = area.minY, area.maxY do
                for x = area.minX, area.maxX do
                    monitor.setCursorPos(x, y)
                    if x - area.minX < fill then
                        monitor.setBackgroundColor(colors.orange)
                    else
                        monitor.setBackgroundColor(colors.lightGray)
                    end
                    
                    local cell = cfg.foreground[y] and cfg.foreground[y][x]
                    if cell then
                        monitor.setTextColor(cell.fg)
                        monitor.write(cell.char)
                    else
                        monitor.write(" ")
                    end
                end
            end

            -- Цифры процента
            local pStr = string.format("%03d", percent)
            for i, pos in ipairs(cfg.percent_digits) do
                monitor.setCursorPos(pos.x, pos.y)
                monitor.setBackgroundColor(colors.gray)
                monitor.setTextColor(colors.yellow)
                monitor.write(pStr:sub(i, i))
            end
            
            monitor.setCursorPos(cfg.percent_sign.x, cfg.percent_sign.y)
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(colors.yellow)
            monitor.write("%")
            
            lastPercent = percent
        end
        sleep(0.05)
    end

    -- 7. Финальная фиксация (100%)
    -- Сначала дорисовываем полоску
    for y = area.minY, area.maxY do
        for x = area.minX, area.maxX do
            monitor.setCursorPos(x, y)
            monitor.setBackgroundColor(colors.green)
            local cell = cfg.foreground[y] and cfg.foreground[y][x]
            if cell then
                monitor.setTextColor(cell.fg)
                monitor.write(cell.char)
            else
                monitor.write(" ")
            end
        end
    end

    -- ТЕПЕРЬ ЦИФРЫ (с принудительным сбросом цвета фона)
    local pStr = "100"
    for i, pos in ipairs(cfg.percent_digits) do
        monitor.setCursorPos(pos.x, pos.y)
        -- РЕШЕНИЕ: Указываем серый фон, чтобы перебить зеленый от полоски
        monitor.setBackgroundColor(colors.gray) 
        monitor.setTextColor(colors.yellow)
        monitor.write(pStr:sub(i, i))
    end
    
    -- Знак процента тоже на сером
    monitor.setCursorPos(cfg.percent_sign.x, cfg.percent_sign.y)
    monitor.setBackgroundColor(colors.gray)
    monitor.write("%")

    sleep(0.5)
end

return { show = bootMenu }