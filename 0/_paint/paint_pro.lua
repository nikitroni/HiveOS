-- Названия мониторов
local canvas = peripheral.wrap("monitor_0")
local palette = peripheral.wrap("monitor_1")

-- Константы
local FILENAME = "_paint/my_drawing.nfp"
local EMPTY_COLOR = "f" -- Черный в NFP (индекс 15)
local selectedColor = "0" -- Начинаем с белой кисти (индекс 0)

-- Соответствие индексов (0..15) цветам ComputerCraft
local colorMap = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
local ccColors = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768}

local canvasData = {}

-- Инициализация пустого массива (черный фон)
local function initCanvas()
    for y = 1, 33 do
        canvasData[y] = {}
        for x = 1, 50 do
            canvasData[y][x] = EMPTY_COLOR
        end
    end
end

-- Отрисовка палитры (увеличенные кнопки 6x7)
local function drawPalette()
    palette.setBackgroundColor(colors.black)
    palette.clear()

    local btnWidth = 6   -- ширина кнопки в символах
    local btnHeight = 7  -- высота кнопки
    local stepX = btnWidth + 1  -- шаг по горизонтали (6 + 1 = 7)
    local stepY = btnHeight + 1 -- шаг по вертикали (7 + 1 = 8)

    for i = 0, 15 do
        local col = i % 5           -- 5 столбцов
        local row = math.floor(i / 5) -- 4 строки (0..3)

        -- Координаты левого верхнего угла кнопки
        local startX = col * stepX + 2
        local startY = row * stepY + 2

        palette.setBackgroundColor(ccColors[i+1])

        for dy = 0, btnHeight - 1 do
            palette.setCursorPos(startX, startY + dy)
            palette.write(string.rep(" ", btnWidth))
        end
    end
end

-- Сохранение в файл
local function saveNFP()
    local file = fs.open(FILENAME, "w")
    for y = 1, 33 do
        local line = ""
        for x = 1, 50 do
            line = line .. canvasData[y][x]
        end
        file.writeLine(line)
    end
    file.close()
end

-- Загрузка и вывод на экран
local function loadNFP()
    if not fs.exists(FILENAME) then
        canvas.setBackgroundColor(colors.black)
        canvas.clear()
        return
    end

    local file = fs.open(FILENAME, "r")
    for y = 1, 33 do
        local line = file.readLine() or ""
        for x = 1, 50 do
            local char = line:sub(x, x)
            if char == "" or char == " " then char = EMPTY_COLOR end
            canvasData[y][x] = char

            -- Сразу рисуем пиксель на монитор
            canvas.setCursorPos(x, y)
            canvas.setBackgroundColor(ccColors[tonumber(char, 16) + 1])
            canvas.write(" ")
        end
    end
    file.close()
end

-- ЗАПУСК
canvas.setTextScale(1)
initCanvas() -- Сначала создаем пустую черную таблицу в памяти
loadNFP()    -- Затем загружаем файл поверх нее (если есть)
drawPalette() -- Рисуем палитру на втором экране

while true do
    local event, side, x, y = os.pullEvent("monitor_touch")

    if side == "monitor_1" then
        -- Выбор цвета на палитре (с учётом новых размеров кнопок)
        local stepX = 7   -- ширина кнопки + 1 (6+1)
        local stepY = 8   -- высота кнопки + 1 (7+1)

        local gridX = math.floor((x - 2) / stepX)
        local gridY = math.floor((y - 2) / stepY)

        if gridX >= 0 and gridX < 5 and gridY >= 0 and gridY < 4 then
            local index = gridY * 5 + gridX + 1
            if index <= 16 then
                selectedColor = colorMap[index]
            end
        end

    elseif side == "monitor_0" then
        -- Рисование на холсте (50x33)
        if x <= 50 and y <= 33 then
            canvasData[y][x] = selectedColor
            canvas.setCursorPos(x, y)
            canvas.setBackgroundColor(ccColors[tonumber(selectedColor, 16) + 1])
            canvas.write(" ")

            saveNFP() -- Автосохранение
        end
    end
end