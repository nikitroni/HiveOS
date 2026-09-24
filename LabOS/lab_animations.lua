-- lab_animations.lua
-- Функции для анимаций на лабораторном мониторе.
-- Каждая функция рисует только в заданной области, не очищая остальной экран.

local Anim = {}

-- ==================== ВСПОМОГАТЕЛЬНЫЕ ====================
-- Проверка, что monitor существует
local function checkMonitor(mon)
    if not mon then
        error("Monitor is nil")
    end
end

-- ==================== АНИМАЦИЯ WIN ====================
-- Матрица букв WIN (как в предоставленном коде)
local winLogo = {
    "                    ",
    "  w   w wwwww  w   w",
    "  w   w   w    ww  w",
    "  w   w   w    w w w",
    "  w w w   w    w  ww",
    "  w w w   w    w   w",
    "  w w w   w    w   w",
    "   w w  wwwww  w   w"
}
local winColors = {
    colors.red, colors.orange, colors.yellow, colors.green,
    colors.lightBlue, colors.blue, colors.purple, colors.magenta
}
-- Рисует логотип WIN в позиции (startX, startY) с переливающимися цветами.
-- frame увеличивается каждый кадр.
function Anim.drawWin(monitor, startX, startY, frame)
    checkMonitor(monitor)
    for row = 1, #winLogo do
        local line = winLogo[row]
        for col = 1, #line do
            local char = line:sub(col, col)
            if char ~= " " then
                local colorIdx = (col + frame) % #winColors + 1
                monitor.setCursorPos(startX + col - 1, startY + row - 1)
                monitor.setTextColor(winColors[colorIdx])
                monitor.write("w")  -- символ "w" как в оригинале
            end
        end
    end
end

-- ==================== АНИМАЦИЯ WAIT ====================
local waitLogo = {
    "                       ",
    " x   x  xx  xxxxx xxxxx",
    " x   x x  x   x     x  ",
    " x   x x  x   x     x  ",
    " x x x xxxx   x     x  ",
    " xx xx x  x   x     x  ",
    " x   x x  x xxxxx   x  "
}
local waitFade = {colors.white, colors.lightGray, colors.gray, colors.black}
-- Рисует логотип WAIT с эффектом затухания.
-- frame определяет яркость: чем больше frame, тем темнее (циклически).
function Anim.drawWait(monitor, startX, startY, frame)
    checkMonitor(monitor)
    local colorIdx = (math.floor(frame / 4)) % #waitFade + 1
    local currentColor = waitFade[colorIdx]
    for row = 1, #waitLogo do
        local line = waitLogo[row]
        for col = 1, #line do
            local char = line:sub(col, col)
            monitor.setCursorPos(startX + col - 1, startY + row - 1)
            if char == "x" then
                monitor.setTextColor(currentColor)
                monitor.write("x")
            else
                monitor.write(" ")
            end
        end
    end
end

-- ==================== АНИМАЦИЯ ДНК ====================
local dnaPattern = {
    {cL="x",  cR=" ",  conn=" ", isX=true},
    {cL="/",  cR="\\", conn=" ", isX=false},
    {cL="|",  cR="|",  conn="-", isX=false},
    {cL="\\", cR="/",  conn=" ", isX=false},
}
-- Рисует одну цепочку ДНК.
-- startX, startY – координаты левого верхнего угла области (она занимает 3 символа в ширину и height строк).
-- height – высота цепочки (количество строк). В вашем случае 10.
-- frame – номер кадра для анимации (определяет сдвиг).
-- inverted – если true, меняет цвета красный/синий местами.
function Anim.drawDNA(monitor, startX, startY, height, frame, inverted)
    checkMonitor(monitor)
    monitor.setBackgroundColor(colors.black)
    for i = 1, height do
        local y = startY + i - 1
        local idx = (i + frame - 1) % 4 + 1
        local line = dnaPattern[idx]

        local phase = math.floor((i + frame - 1) / 4) % 2
        if inverted then
            phase = (phase == 0) and 1 or 0
        end

        local colL = (phase == 0) and colors.red or colors.blue
        local colR = (phase == 0) and colors.blue or colors.red

        if line.isX then
            monitor.setCursorPos(startX + 1, y)
            monitor.setTextColor(colors.white)
            monitor.write("X")   -- заменили "x" на "X" для контраста
        else
            monitor.setCursorPos(startX, y)
            monitor.setTextColor(colL)
            monitor.write(line.cL)   -- "/", "\", "|"

            monitor.setCursorPos(startX + 2, y)
            monitor.setTextColor(colR)
            monitor.write(line.cR)   -- "\", "/", "|"

            if line.conn ~= " " then
                monitor.setCursorPos(startX + 1, y)
                monitor.setTextColor(colors.white)
                monitor.write(line.conn)   -- "-"
            end
        end
    end
end

return Anim