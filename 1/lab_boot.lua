-- lab_boot.lua
-- Экран ожидания LabOS: рисуется фон HUD_Lab_Boot.nfp на главном мониторе,
-- поверх - плавно анимированная цветная полоса загрузки.
-- Координаты полосы (из макета): x=20, y=16, w=33, h=9.
-- Цифры процента НЕ выводятся - только шкала.
-- Дополнительно: забавная анимация "колбочек" - области на фоне заливки
-- случайными яркими цветами (координаты задаются в таблице FLASKS ниже).

local BOOT_FILE = "HUD_Lab_Boot.nfp"

local BAR = {
    x = 20,
    y = 16,
    w = 33,
    h = 9,
}

-- Области колбочек для случайной яркой заливки (забавная анимация).
-- Колба 1 (левая): нижняя ёмкость + горлышко; колба 2 (правая): то же.
-- Каждая клетка в этих областях меняет цвет в каждом кадре.
local FLASKS = {
    -- Колба 1 (левая): ёмкость
    { x = 5,  y = 13, w = 7, h = 5 },
    -- Колба 1 (левая): горлышко
    { x = 7,  y = 10, w = 3, h = 3 },
    -- Колба 2 (правая): ёмкость
    { x = 61, y = 13, w = 7, h = 5 },
    -- Колба 2 (правая): горлышко
    { x = 63, y = 10, w = 3, h = 3 },
}

-- Палитра ярких цветов для колбочек
local FLASK_COLORS = {
    colors.red,
    colors.orange,
    colors.yellow,
    colors.green,
    colors.cyan,
    colors.blue,
    colors.purple,
    colors.pink,
    colors.magenta,
}

local preparedMonitors = {}

local function isPrepared(mon)
    return preparedMonitors[mon] == true
end

local function markPrepared(mon)
    preparedMonitors[mon] = true
end

-- ==================== АНИМАЦИЯ КОЛБ (медленная) ====================
-- Набор цветов для всех клеток колб, который обновляется раз в
-- FLASK_INTERVAL секунд. Между обновлениями цвета стабильны -
-- анимация получается плавной и не рябит.

local FLASK_INTERVAL = 0.4   -- каждые 0.8 с набор цветов меняется

local flaskCellColors = {}   -- [index] = color
local flaskColorsTime = 0

local function ensureFlaskColors()
    local now = os.clock()
    if now - flaskColorsTime >= FLASK_INTERVAL then
        -- пересчитываем общее число клеток
        local total = 0
        for _, area in ipairs(FLASKS) do
            total = total + area.w * area.h
        end
        flaskCellColors = {}
        for i = 1, total do
            flaskCellColors[i] = FLASK_COLORS[math.random(#FLASK_COLORS)]
        end
        flaskColorsTime = now
    end
end

-- Залить области колбочек: стабильные на интервал цвета.
local function drawFlaskAnimation(mon)
    if #FLASKS == 0 then return end
    ensureFlaskColors()
    local idx = 0
    for _, area in ipairs(FLASKS) do
        for row = 0, area.h - 1 do
            for col = 0, area.w - 1 do
                idx = idx + 1
                local color = flaskCellColors[idx]
                mon.setCursorPos(area.x + col, area.y + row)
                mon.setBackgroundColor(color)
                mon.setTextColor(color)
                mon.write(" ")
            end
        end
    end
end

-- Полная очистка и отрисовка фона один раз на монитор (до анимации полосы)
function prepareScreen(mon)
    local bg = paintutils.loadImage(BOOT_FILE)
    if not bg then
        error("HUD_Lab_Boot.nfp not found")
    end
    mon.setTextScale(1.0)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local oldTerm = term.redirect(mon)
    paintutils.drawImage(bg, 1, 1)
    term.redirect(oldTerm)
    markPrepared(mon)
end

-- Рисует полосу прогресса (только область полосы).
-- percent: 0..100
local function drawBar(mon, percent)
    local total = BAR.w * BAR.h
    local fill = math.floor(percent / 100 * total + 0.5)
    if fill < 0 then fill = 0 end
    if fill > total then fill = total end

    for row = 0, BAR.h - 1 do
        for col = 0, BAR.w - 1 do
            local i = row * BAR.w + col
            mon.setCursorPos(BAR.x + col, BAR.y + row)
            if i < fill then
                mon.setBackgroundColor(colors.orange)
            else
                mon.setBackgroundColor(colors.lightGray)
            end
            mon.setTextColor(colors.white)
            mon.write(" ")
        end
    end
end

-- Один кадр анимации ожидания: только полоса (фон уже нарисован prepareScreen).
-- Плавная шкала 0% -> 100% -> 0%.
function drawWaitFrame(mon)
    local ok = pcall(function()
        if not isPrepared(mon) then
            prepareScreen(mon)
        end
        local p = (os.clock() % 4) / 4
        local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
        drawBar(mon, math.floor(wave * 100))
        drawFlaskAnimation(mon)
    end)
    return ok
end

-- Стартовая анимация фиксированной длительности
function show(mon, duration)
    duration = duration or 4
    prepareScreen(mon)
    local start = os.clock()
    while os.clock() - start < duration do
        local p = (os.clock() - start) / duration
        local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
        drawBar(mon, math.floor(wave * 100))
        drawFlaskAnimation(mon)
        sleep(0.05)
    end
end

return {
    show = show,
    prepareScreen = prepareScreen,
    drawWaitFrame = drawWaitFrame,
}