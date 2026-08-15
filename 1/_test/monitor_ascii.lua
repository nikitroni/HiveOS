-- local m = peripheral.wrap("monitor_3") -- имя монитора настриваем под каждый тип кнопки отдельно 
-- m.setTextScale(1.0)
-- m.clear()
-- m.setTextScale(0.5)
-- m.clear()

-- local glass = {
--     {text = "      ___      ", color = colors.lightGray},
--     {text = "     |   |     ", color = colors.lightGray},
--     {text = "     |DNA|     ", color = colors.red}, -- Красный текст внутри
--     {text = "     |   |     ", color = colors.lightGray},
--     {text = "    /     \\    ", color = colors.lightGray},
--     {text = "   |  (X)  |   ", color = colors.blue}, -- Синяя жидкость
--     {text = "   |  / \\  |   ", color = colors.blue},
--     {text = "   | (___) |   ", color = colors.blue},
--     {text = "    \\_____/    ", color = colors.lightGray}
-- }

-- for i, line in ipairs(glass) do
--     m.setCursorPos(1, i)
--     m.setTextColor(line.color)
--     m.write(line.text)
-- end

-- m.setTextScale(0.5)
-- m.setBackgroundColor(colors.black)
-- m.clear()

-- local function p(x, y, color)
--     m.setCursorPos(x, y)
--     m.setBackgroundColor(color)
--     m.write(" ")
-- end

-- -- Рисуем силуэт улья закрашенными ячейками
-- local shape = {
--     {4,5,6,7,8,9,10,11},    -- y=2
--     {3,4,5,6,7,8,9,10,11,12}, -- y=3
--     {2,3,4,5,6,7,8,9,10,11,12,13}, -- y=4
--     {2,3,4, 11,12,13},      -- y=5 (с дыркой посередине)
--     {2,3,4, 11,12,13},      -- y=6 (с дыркой посередине)
--     {2,3,4,5,6,7,8,9,10,11,12,13}, -- y=7
--     {3,4,5,6,7,8,9,10,11,12}, -- y=8
--     {4,5,6,7,8,9,10,11}     -- y=9
-- }

-- for y, row in ipairs(shape) do
--     for _, x in ipairs(row) do
--         -- Чередуем цвета для полосок
--         local c = (y % 2 == 0) and colors.yellow or colors.orange
--         p(x, y + 1, c)
--     end
-- end

-- -- Сброс цвета, чтобы текст потом не красил фон
-- m.setBackgroundColor(colors.black)



--ДНК ЦЕПОЧКА, АНИМИРОВАННАЯ

-- local function drawScene(frame)
--     m.setBackgroundColor(colors.black)
--     m.clear()
    
--     -- Заголовок с имитацией загрузки
--     m.setCursorPos(1, 1)
--     m.setTextColor(colors.lime)
--     local dots = string.rep(".", (math.floor(frame) % 4))
--     m.write(">GENE ANALYZING" .. dots)

--     for i = 1, 8 do
--         local y = i + 1
--         local t = i * 0.5 + (frame * 0.2) -- Замедляем для плавности
        
--         -- Вычисляем позиции двух нитей
--         local x1 = 8 + math.sin(t) * 5
--         local x2 = 8 + math.sin(t + math.pi) * 5

--         -- Мостик (рисуем только если нити не слишком близко)
--         local startX = math.ceil(math.min(x1, x2))
--         local endX = math.floor(math.max(x1, x2))
--         if endX - startX > 1 then
--             m.setCursorPos(startX + 1, y)
--             m.setTextColor(colors.gray)
--             m.write(string.rep("\140", endX - startX - 1))
--         end

--         -- Нить 1 (Cyan/Blue)
--         m.setCursorPos(math.floor(x1 + 0.5), y)
--         -- Если sin > 0, значит нить "ближе" к нам
--         m.setTextColor(math.sin(t) > 0 and colors.cyan or colors.blue)
--         m.write("\159")

--         -- Нить 2 (Magenta/Purple)
--         m.setCursorPos(math.floor(x2 + 0.5), y)
--         m.setTextColor(math.sin(t + math.pi) > 0 and colors.magenta or colors.purple)
--         m.write("\159")
--     end
    
--     -- Рандомный "генетический код" снизу для пафоса
--     m.setCursorPos(1, 10)
--     m.setTextColor(colors.gray)
--     local chars = {"A","C","G","T", "1", "4", "8"}
--     local code = ""
--     for i=1,12 do code = code .. chars[math.random(1,7)] end
--     m.write("SEQ:" .. code)
-- end

-- -- Основной цикл
-- local f = 0
-- while true do
--     drawScene(f)
--     f = f + 1
--     os.sleep(0.05) -- Уменьшили задержку для плавности
-- end




-- -- --ПЧЕЛА ЛЕТАЕТ
-- local function rect(x, y, w, h, color)
--     m.setBackgroundColor(color)
--     for i = 0, h - 1 do
--         m.setCursorPos(x, y + i)
--         m.write(string.rep(" ", w))
--     end
-- end

-- local function drawTitanBee(frame)
--     m.setBackgroundColor(colors.black)
--     m.clear()

--     -- Плавное покачивание всей пчелы
--     local offset = math.sin(frame * 0.2) * 1
--     local x, y = 3, 4 + offset

--     -- 1. КРЫЛЬЯ (меняют положение)
--     local wingShift = (math.floor(frame * 3) % 2 == 0) and 0 or 1
--     m.setBackgroundColor(colors.lightGray)
--     -- Левое крыло
--     rect(x + 2, y - 2 + wingShift, 2, 2, colors.lightGray)
--     -- Правое крыло
--     rect(x + 5, y - 2 + wingShift, 2, 2, colors.lightGray)

--     -- 2. ТЕЛО (Массивные блоки 2x2 для каждого сегмента)
--     rect(x, y, 2, 2, colors.yellow) -- Голова
--     rect(x + 2, y, 2, 2, colors.black)  -- Полоса 1
--     rect(x + 4, y, 2, 2, colors.yellow) -- Полоса 2
--     rect(x + 6, y, 2, 2, colors.black)  -- Полоса 3
--     rect(x + 8, y + 1, 1, 1, colors.gray) -- ЖАЛО (теперь оно заметное)

--     -- 3. ГЛАЗ (на голове)
--     m.setCursorPos(x, y)
--     m.setBackgroundColor(colors.white)
--     m.write(" ")
-- end

-- local f = 0
-- while true do
--     drawTitanBee(f)
--     f = f + 0.5
--     os.sleep(0.05)
-- end



-- -- кнопка RESRESH
-- local ring = {
--     {x=5, y=2}, {x=6, y=2}, {x=7, y=2}, {x=8, y=2}, {x=9, y=2}, {x=10, y=2}, {x=11, y=2},
--     {x=12, y=3}, {x=13, y=4}, {x=14, y=5}, {x=14, y=6}, {x=13, y=7},
--     {x=12, y=8}, {x=11, y=9}, {x=10, y=9}, {x=9, y=9}, {x=8, y=9}, {x=7, y=9}, {x=6, y=9}, {x=5, y=9},
--     {x=4, y=8}, {x=3, y=7}, {x=2, y=6}, {x=2, y=5}, {x=3, y=4}, {x=4, y=3}
-- }

-- local function drawWideRefresh(frame)
--     m.setBackgroundColor(colors.black)
--     m.clear()

--     for i = 1, #ring do
--         local head = math.floor(frame) % #ring + 1
--         local distance = (i - head) % #ring
--         if distance < 0 then distance = distance + #ring end

--         local col = colors.green
--         if distance == 0 then
--             col = colors.white 
--         elseif distance < 7 then
--             col = colors.lime  
--         elseif distance > #ring - 4 then
--             col = colors.black 
--         end

--         if col ~= colors.black then
--             m.setBackgroundColor(col)
            
--             -- 1. ОСНОВНОЙ ПИКСЕЛЬ
--             m.setCursorPos(ring[i].x, ring[i].y)
--             m.write(" ")
            
--             -- 2. ВТОРОЙ ПИКСЕЛЬ (СТРОГО ОДИН)
--             -- Смещение идет только вовнутрь, чтобы не раздувать кольцо
--             local ox, oy = 0, 0
--             if ring[i].y == 2 then oy = 1       -- Верхняя планка: рисуем вниз
--             elseif ring[i].y == 9 then oy = -1   -- Нижняя планка: рисуем вверх
--             elseif ring[i].x == 2 then ox = 1    -- Левый бок: рисуем вправо
--             elseif ring[i].x == 14 then ox = -1  -- Правый бок: рисуем влево
--             elseif ring[i].x > 11 then ox = -1   -- Углы справа
--             elseif ring[i].x < 5 then ox = 1     -- Углы слева
--             end
            
--             m.setCursorPos(ring[i].x + ox, ring[i].y + oy)
--             m.write(" ")
--         end
--     end

--     -- Текст REFRESH
--     m.setBackgroundColor(colors.black)
--     m.setTextColor(colors.lime)
--     m.setCursorPos(5, 5) 
--     m.write("REFRESH")
-- end

-- local f = 0
-- while true do
--     drawWideRefresh(f)
--     f = f + 0.8 -- ТВОЯ СКОРОСТЬ
--     os.sleep(0.05)
-- end



-- -- УЛЕЙ
-- local layers = {
--     {y=2, x1=7, x2=10}, -- Крышка
--     {y=3, x1=6, x2=11}, -- Плечи
--     {y=4, x1=5, x2=12}, -- Слой 1
--     {y=5, x1=4, x2=13}, -- Центр верх
--     {y=6, x1=4, x2=13}, -- Центр низ
--     {y=7, x1=5, x2=12}, -- Слой 2
--     {y=8, x1=6, x2=11}, -- Бедра
--     {y=9, x1=7, x2=10}  -- Дно
-- }

-- local function drawButtonHive(t)
--     m.setBackgroundColor(colors.black)
--     m.clear()

--     -- Анимация "дыхания": меняем основной цвет между желтым и оранжевым
--     local pulse = math.sin(t) * 0.5 + 0.5
--     local mainCol = (pulse > 0.5) and colors.yellow or colors.orange
--     local altCol = (pulse > 0.5) and colors.orange or colors.yellow

--     for i, l in ipairs(layers) do
--         -- Чередуем цвета слоев для объема
--         m.setBackgroundColor(i % 2 == 0 and mainCol or altCol)
--         for x = l.x1, l.x2 do
--             m.setCursorPos(x, l.y)
--             m.write(" ")
--         end
--     end

--     -- Анимированный леток (вход): плавно мигает красным/черным
--     local holeCol = (math.sin(t * 4) > 0) and colors.brown or colors.black
--     m.setBackgroundColor(holeCol)
--     m.setCursorPos(8, 7)
--     m.write("  ")

--     -- Текст кнопки
--     m.setCursorPos(5, 5)
--     m.setTextColor(colors.black)
--     -- Текст всегда на контрастном фоне центрального слоя
--     m.setBackgroundColor(mainCol)
--     m.write("BEE HIVE")

--     m.setCursorPos(6, 6)
--     m.setTextColor(colors.black)
--     -- Текст всегда на контрастном фоне центрального слоя
--     m.setBackgroundColor(altCol)
--     m.write("RETURN")
-- end

-- local timer = 0
-- while true do
--     drawButtonHive(timer)
--     timer = timer + 0.2
--     os.sleep(0.1)
-- end




-- -- Матрица букв WIN (как на скрине image_cbd395.png)
-- -- "w" - это маркер символа, который будет переливаться

-- local logo = {
--     "w   w wwwww  w   w",
--     "w   w   w    ww  w",
--     "w   w   w    w w w",
--     "w w w   w    w  ww",
--     "w w w   w    w   w",
--     "w w w   w    w   w",
--     " w w  wwwww  w   w"
-- }

-- -- Таблица цветов радуги для ComputerCraft

-- local colorsList = {
--     colors.red, colors.orange, colors.yellow, colors.green, 
--     colors.lightBlue, colors.blue, colors.purple, colors.magenta
-- }

-- local function drawRainbowWin(offset)
--     m.setBackgroundColor(colors.black)
--     m.clear()
    
--     local startX, startY = 2, 2 -- Начальные координаты на мониторе

--     for row = 1, #logo do
--         local line = logo[row]
--         for col = 1, #line do
--             local char = line:sub(col, col)
            
--             if char ~= " " then
--                 -- Вычисляем индекс цвета в зависимости от колонки и времени (offset)
--                 local colorIndex = (col + offset) % #colorsList + 1
--                 m.setTextColor(colorsList[colorIndex])
                
--                 m.setCursorPos(startX + col - 1, startY + row - 1)
--                 m.write("w") -- Пишем символ "w", как в оригинале
--             end
--         end
--     end
-- end

-- local frame = 0
-- while true do
--     drawRainbowWin(frame)
--     frame = frame + 1
--     os.sleep(0.175) -- Скорость перелива радуги
-- end




-- -- Твой идеальный паттерн
-- local grid = {
--     {cL="x",  cR=" ",  conn=" ", isX=true}, 
--     {cL="/",  cR="\\", conn=" ", isX=false},
--     {cL="|",  cR="|",  conn="-", isX=false},
--     {cL="\\", cR="/",  conn=" ", isX=false},
-- }

-- -- Функция отрисовки одной цепочки
-- local function drawChain(startX, offset, isInverted)
--     for i = 1, 10 do
--         local y = 3 + i
--         local idx = (i + offset - 1) % 4 + 1
--         local line = grid[idx]

--         -- Логика цвета зигзагом
--         local phase = math.floor((i + offset - 1) / 4) % 2
        
--         -- Если isInverted = true, меняем фазу на противоположную
--         if isInverted then
--             phase = (phase == 0) and 1 or 0
--         end

--         local colL = (phase == 0) and colors.red or colors.blue
--         local colR = (phase == 0) and colors.blue or colors.red

--         if line.isX then
--             m.setCursorPos(startX + 1, y)
--             m.setTextColor(colors.white)
--             m.write("x")
--         else
--             -- Левая нить
--             m.setTextColor(colL)
--             m.setCursorPos(startX, y)
--             m.write(line.cL)
            
--             -- Правая нить
--             m.setTextColor(colR)
--             m.setCursorPos(startX + 2, y)
--             m.write(line.cR)
            
--             -- Перемычка
--             if line.conn == "-" then
--                 m.setTextColor(colors.white)
--                 m.setCursorPos(startX + 1, y)
--                 m.write("-")
--             end
--         end
--     end
-- end

-- local frame = 0
-- while true do
--     -- Чистим монитор (или только области цепей)
--     m.clear() 

--     -- Первая цепочка (слева, обычные цвета)
--     drawChain(20, frame, false)

--     -- Вторая цепочка (на 26 правее: 2 + 26 = 28, зеркальные цвета)
--     drawChain(46, frame, true)

--     frame = frame + 1
--     os.sleep(0.15)
-- end



-- -- Компактная матрица WAIT
-- local logo_wait = {
--     "x   x  xxx  xxxxx xxxxx",
--     "x   x x   x   x     x  ",
--     "x   x x   x   x     x  ",
--     "x x x xxxxx   x     x  ",
--     "xx xx x   x   x     x  ",
--     "x   x x   x xxxxx   x  "
-- }

-- -- Цвета от ярко-белого до полной темноты
-- local fade = {colors.white, colors.lightGray, colors.gray, colors.black}

-- local function drawWait(offset)
--     local startX, startY = 6, 3
    
--     -- 1. Вычисляем ОДИН цвет для всей надписи сразу
--     -- Делим offset на 4, чтобы замедлить мерцание
--     local colorIdx = (math.floor(offset / 4)) % #fade + 1
--     local currentColor = fade[colorIdx]

--     for row = 1, #logo_wait do
--         local line = logo_wait[row]
--         for col = 1, #line do
--             local char = line:sub(col, col)
--             m.setCursorPos(startX + col, startY + row)
            
--             if char == "x" then
--                 m.setTextColor(currentColor)
--                 m.write("x") -- Твой символ для отрисовки
--             else
--                 m.write(" ") -- Очистка пустот внутри ячейки
--             end
--         end
--     end
-- end

-- -- Пример интеграции в цикл
-- local frame = 0
-- while true do
--     -- Тут вызываются твои функции drawChain(2, frame, false) и т.д.
    
--     drawWait(frame)
    
--     frame = frame + 1
--     os.sleep(0.1)
-- end


-- local currentCode = ""

-- local function drawScene(frame)
--     m.setBackgroundColor(colors.black)
--     m.clear()
    
--     -- Заголовок с имитацией загрузки
--     m.setCursorPos(1, 1)
--     m.setTextColor(colors.lime)
--     local dots = string.rep(".", (math.floor(frame) % 4))
--     m.write(">GENE ANALYZING" .. dots)

--     -- Отрисовка ДНК (без изменений)
--     for i = 1, 8 do
--         local y = i + 1
--         local t = i * 0.5 + (frame * 0.2)
--         local x1 = 8 + math.sin(t) * 5
--         local x2 = 8 + math.sin(t + math.pi) * 5
--         local startX = math.ceil(math.min(x1, x2))
--         local endX = math.floor(math.max(x1, x2))
--         if endX - startX > 1 then
--             m.setCursorPos(startX + 1, y)
--             m.setTextColor(colors.gray)
--             m.write(string.rep("\140", endX - startX - 1))
--         end
--         m.setCursorPos(math.floor(x1 + 0.5), y)
--         m.setTextColor(math.sin(t) > 0 and colors.cyan or colors.blue)
--         m.write("\159")
--         m.setCursorPos(math.floor(x2 + 0.5), y)
--         m.setTextColor(math.sin(t + math.pi) > 0 and colors.magenta or colors.purple)
--         m.write("\159")
--     end
    
--     -- 2. ЛОГИКА ЗАМЕДЛЕННОГО ОБНОВЛЕНИЯ SEQ
--     -- Обновляем строку только каждые 10 кадров (примерно раз в 0.5 сек)
--     if frame % 5 == 0 or currentCode == "" then
--         local chars = {"A","C","G","T", "1", "4", "8"}
--         currentCode = ""
--         for i=1,12 do 
--             currentCode = currentCode .. chars[math.random(1,7)] 
--         end
--     end

--     -- Отрисовка текущего кода (пишется каждый кадр, но меняется редко)
--     m.setCursorPos(1, 10)
--     m.setTextColor(colors.gray)
--     m.write("SEQ:" .. currentCode)
-- end

-- -- Основной цикл (без изменений)
-- local f = 0
-- while true do
--     drawScene(f)
--     f = f + 1
--     os.sleep(0.05)
-- end

-- local m = peripheral.wrap("monitor_3")
-- m.setTextScale(0.5)

-- local w, h = m.getSize()

-- local function drawUI(frame)
--     m.setBackgroundColor(colors.black)
--     m.clear()

--     local centerX, centerY = w / 2, h / 2
    
--     -- 1. РИСУЕМ 3D СФЕРУ (Набор вращающихся колец)
--     for r = 5, 20, 3 do
--         -- Каждое кольцо вращается под своим углом
--         local angle = frame * 0.2 + (r * 0.1)
--         local cosA = math.cos(angle)
--         local sinA = math.sin(angle)

--         -- Рисуем точки кольца
--         for i = 0, math.pi * 2, 0.2 do
--             local x = math.cos(i) * r
--             local y = math.sin(i) * r
            
--             -- Поворот в 3D пространстве
--             local rotX = x * cosA - y * sinA
--             local rotZ = x * sinA + y * cosA
            
--             -- Проекция (объем)
--             local p = 5 / (5 - (rotZ / 10))
--             local px = centerX + rotX * p * 2.2 -- компенсация ширины символа
--             local py = centerY + y * p * 0.8
            
--             if px >= 1 and px <= w and py >= 1 and py <= h then
--                 m.setCursorPos(math.floor(px), math.floor(py))
--                 -- Цвет зависит от глубины (rotZ)
--                 if rotZ > 5 then
--                     m.setTextColor(colors.cyan)
--                     m.write("\159") -- Яркая точка спереди
--                 elseif rotZ > -5 then
--                     m.setTextColor(colors.blue)
--                     m.write("\143") -- Тусклая точка сбоку
--                 else
--                     m.setTextColor(colors.gray)
--                     m.write(".") -- Точка сзади
--                 end
--             end
--         end
--     end

--     -- 2. АНИМЕ-ДЕКОР (Заполнение пустоты)
--     m.setTextColor(colors.red)
--     -- Угловые скобки интерфейса
--     m.setCursorPos(2, 2) m.write(">> NEURO-SYNC: 98.4%")
--     m.setCursorPos(w-20, 2) m.write("CORE_TEMP: NOMINAL")
    
--     -- Иероглифы (вертикально справа)
--     local kanji = {"待", "機", "中"}
--     m.setTextColor(colors.orange)
--     for i, char in ipairs(kanji) do
--         m.setCursorPos(w-5, h/2 - 2 + i)
--         m.write(char)
--     end

--     -- Нижняя панель данных
--     m.setTextColor(colors.gray)
--     m.setCursorPos(2, h-1)
--     local loading = string.rep("\140", (frame % 30))
--     m.write("SEC_LINK: " .. loading)
-- end

-- local f = 0
-- while true do
--     drawUI(f)
--     f = f + 0.5
--     os.sleep(0.05)
-- end

local m = peripheral.wrap("monitor_10") -- поменяй сторону, если нужно
m.setTextScale(0.5)
local w, h = m.getSize()

-- Пчела: Классика (B) - работает на всех текстурпаках
local function drawBee(x, y, label)
    m.setCursorPos(x, y)
    m.setTextColor(colors.yellow)
    m.write("("..label..")")
    m.setTextColor(colors.white)
    m.setCursorPos(x+1, y-1)
    m.write("^") -- Одно маленькое крылышко сверху
end

-- Сота: Текстовая рамка (самый надежный вариант)
local function drawCell(x, y, active)
    m.setTextColor(active and colors.yellow or colors.orange)
    m.setCursorPos(x-1, y-1) m.write("/--\\")
    m.setCursorPos(x-2, y)   m.write("|    |")
    m.setCursorPos(x-1, y+1) m.write("\\--/")
end

local function main()
    local f = 0
    while true do
        m.setBackgroundColor(colors.black)
        m.clear()
        
        local midX, midY = math.floor(w/2), math.floor(h/2)
        local t = f % 40

        -- Текст сверху (без рамок, просто BREED)
        m.setTextColor(colors.white)
        m.setCursorPos(midX - 2, 2)
        m.write("BREED")

        if t < 15 then
            -- 1. Сближение
            drawCell(midX, midY, false)
            drawBee(2 + t, midY, "B")
            drawBee(w - 3 - t, midY, "B")
            
        elseif t < 25 then
            -- 2. Скрещивание
            drawCell(midX, midY, true)
            m.setTextColor(colors.red)
            m.setCursorPos(midX, midY)
            m.write("\3") -- Красное сердце (номер 3)
            
        else
            -- 3. Результат
            drawCell(midX, midY, false)
            -- Родители остаются по бокам, не закрывая текст
            drawBee(midX - 6, midY, "B")
            drawBee(midX + 4, midY, "B")
            
            -- Малыш вылетает горизонтально в свободную зону
            local fly = t - 25
            drawBee(midX + fly, midY + 2, "b")
            
            m.setTextColor(colors.lime)
            m.setCursorPos(midX - 3, h)
            m.write("SUCCESS")
        end

        f = f + 1
        os.sleep(0.1)
    end
end

main()