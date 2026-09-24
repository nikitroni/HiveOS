-- lab_buttons.lua
-- Модуль для управления 4 мониторами-кнопками.
-- Каждая кнопка имеет свой монитор, анимируется независимо и обрабатывает нажатия.
-- Мониторы резолвятся ЛЕНИВО (когда периферия уже настроена конфигом от HeartOS).

local lib = require("lab_lib")
local Buttons = {}

-- Инициализируется при первом использовании (после прихода конфига)
local monitors = nil
local function getMonitors()
    if not monitors then
        monitors = {}

        -- Безопасный wrap: если имя в конфиге отсутствует (nil), пропускаем.
        local function wname(name)
            if type(name) ~= "string" or name == "" then
                return nil
            end
            return peripheral.wrap(name)
        end

        local bm = lib.peripherals.button_monitors or {}
        monitors.bee_out = wname(bm.bee_out)
        monitors.gene_upgrade = wname(bm.gene_upgrade)
        monitors.gene_produce = wname(bm.gene_produce)
        monitors.breed = wname(bm.breed)

        for name, mon in pairs(monitors) do
            if mon then mon.setTextScale(0.5) end
        end
    end
    return monitors
end

-- Постоянные буферы кнопок (одни на модуль, не пересоздаются на кадр)
local buffers = {}

local function rect(mon, x, y, w, h, color)
    mon.setBackgroundColor(color)
    for i = 0, h - 1 do
        mon.setCursorPos(x, y + i)
        mon.write(string.rep(" ", w))
    end
end

-- Кнопка BEE HIVE OUT
local function drawBeeOutButton(mon, frame)
    local layers = {
        {y=3, x1=7, x2=10}, {y=3, x1=6, x2=11}, {y=4, x1=5, x2=12},
        {y=5, x1=4, x2=13}, {y=6, x1=4, x2=13}, {y=7, x1=5, x2=12},
        {y=8, x1=6, x2=11}, {y=9, x1=7, x2=10}
    }
    mon.setBackgroundColor(colors.black)
    mon.clear()

    local pulse = math.sin(frame) * 0.5 + 0.5
    local mainCol = (pulse > 0.5) and colors.yellow or colors.orange
    local altCol = (pulse > 0.5) and colors.orange or colors.yellow

    for i, l in ipairs(layers) do
        mon.setBackgroundColor(i % 2 == 0 and mainCol or altCol)
        for x = l.x1, l.x2 do
            mon.setCursorPos(x, l.y)
            mon.write(" ")
        end
    end

    local holeCol = (math.sin(frame * 4) > 0) and colors.brown or colors.black
    mon.setBackgroundColor(holeCol)
    mon.setCursorPos(8, 7)
    mon.write("  ")

    mon.setBackgroundColor(mainCol)
    mon.setTextColor(colors.black)
    mon.setCursorPos(5, 5)
    mon.write("BEE HIVE")
    mon.setCursorPos(6, 6)
    mon.write("RETURN")
end

-- Кнопка GENE UPGRADE
local lastCode = ""
local function drawGeneUpgradeButton(mon, frame)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    mon.setCursorPos(1, 1)
    mon.setTextColor(colors.lime)
    local dots = string.rep(".", (math.floor(frame) % 4))
    mon.write(">GENE ANALYZING" .. dots)

    for i = 1, 8 do
        local y = i + 1
        local t = i * 0.5 + (frame * 0.2)
        local x1 = 8 + math.sin(t) * 5
        local x2 = 8 + math.sin(t + math.pi) * 5
        local startX = math.ceil(math.min(x1, x2))
        local endX = math.floor(math.max(x1, x2))
        -- В функции drawGeneUpgradeButton:
        if endX - startX > 1 then
            mon.setCursorPos(startX + 1, y)
            mon.setTextColor(colors.gray)
            mon.write(string.rep(string.char(140), endX - startX - 1))  -- символ \140
        end
        mon.setCursorPos(math.floor(x1 + 0.5), y)
        mon.setTextColor(math.sin(t) > 0 and colors.cyan or colors.blue)
        mon.write(string.char(159))  -- символ \159
        mon.setCursorPos(math.floor(x2 + 0.5), y)
        mon.setTextColor(math.sin(t + math.pi) > 0 and colors.magenta or colors.purple)
        mon.write(string.char(159))
    end

    if frame % 5 == 0 or lastCode == "" then
        local chars = {"A","C","G","T","1","4","8"}
        lastCode = ""
        for i=1,12 do lastCode = lastCode .. chars[math.random(1,7)] end
    end
    mon.setCursorPos(1, 10)
    mon.setTextColor(colors.gray)
    mon.write("SEQ:" .. lastCode)
end

-- Кнопка GENE PRODUCTION (две анимированные пробирки, несинхронные цвета)
local function drawGeneProduceButton(mon, frame)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Локальная WriteAt (пишет в монитор/буфер)
    local function writeAt(x, y, ch, fg, bg)
        mon.setCursorPos(x, y)
        mon.setTextColor(fg)
        mon.setBackgroundColor(bg)
        mon.write(ch)
    end

    -- Заголовок (x=1)
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 1)
    mon.write("GENE PRODUCTION")

    -- ===== Геометрия пробирки (5 колонок) =====
    -- опущены на 2 строки ниже (rimY: 2->4)
    local rimY = 4
    local wallY1 = 5
    local wallY2 = 9
    local bottomY = 10

    -- Рисует одну пробирку с центром в cx (левая стенка) и своим уровнем.
    -- bubble = { x = 0..2 (смещение внутрь), y = absolute } рисуется
    -- строго внутри жидкости (bg = color жидкости, fg = white).
    local function drawTube(cx, color, liquidTopY, bubble)
        cx = cx or 0
        -- Жидкость (снизу вверх, внутри стенок x=cx+1..cx+3)
        for y = wallY2, liquidTopY, -1 do
            for col = cx + 1, cx + 3 do
                writeAt(col, y, " ", color, color)
            end
        end

        -- Пузырёк: x = cx+1+off (только внутри жидкости), bg = цвет жидкости
        if bubble then
            local bx = cx + 1 + bubble.off
            local by = bubble.y
            if by >= liquidTopY and by <= wallY2 then
                writeAt(bx, by, "o", colors.white, color)
            end
        end

        -- Стенки
        for y = wallY1, wallY2 do
            writeAt(cx, y, "|", colors.gray, colors.black)
            writeAt(cx + 4, y, "|", colors.gray, colors.black)
        end

        -- Горлышко
        writeAt(cx, rimY, "/", colors.gray, colors.black)
        writeAt(cx + 1, rimY, "-", colors.gray, colors.black)
        writeAt(cx + 2, rimY, "-", colors.gray, colors.black)
        writeAt(cx + 3, rimY, "-", colors.gray, colors.black)
        writeAt(cx + 4, rimY, "\\", colors.gray, colors.black)

        -- Дно
        writeAt(cx, bottomY, "\\", colors.gray, colors.black)
        writeAt(cx + 1, bottomY, "-", colors.gray, colors.black)
        writeAt(cx + 2, bottomY, "-", colors.gray, colors.black)
        writeAt(cx + 3, bottomY, "-", colors.gray, colors.black)
        writeAt(cx + 4, bottomY, "/", colors.gray, colors.black)
    end

    -- ===== Две пробирки, несинхронные, ускоренная анимация =====
    local liquidColors = { colors.green, colors.blue, colors.red, colors.orange, colors.pink }

    -- Пробирка 1
    local c1 = liquidColors[math.floor(frame / 30) % #liquidColors + 1]
    local lvl1 = 2 + math.floor((math.sin(frame * 0.1) + 1) * 1.5)
    if lvl1 < 1 then lvl1 = 1 end
    if lvl1 > 4 then lvl1 = 4 end
    local top1 = wallY2 - (lvl1 - 1)
    -- Пузырёк 1: off 0..2, поднимается
    local b1 = {
        off = (math.floor(frame / 10)) % 3,
        y = wallY2 - math.floor((frame * 0.35) % 5),
    }

    -- Пробирка 2 (своя фаза)
    local c2 = liquidColors[(math.floor((frame + 45) / 30) + 2) % #liquidColors + 1]
    local lvl2 = 2 + math.floor((math.sin((frame + 3.1) * 0.08) + 1) * 1.5)
    if lvl2 < 1 then lvl2 = 1 end
    if lvl2 > 4 then lvl2 = 4 end
    local top2 = wallY2 - (lvl2 - 1)
    -- Пузырёк 2: своя фаза (другой темп/оффсет) - ВТОРАЯ пробирка тоже с пузырьком
    local b2 = {
        off = (math.floor(frame / 7) + 1) % 3,
        y = wallY2 - math.floor(((frame + 2) * 0.27) % 5),
    }

    -- Центрируем: 2×(5 колонок) + отступ 3 = 13 колонок
    local totalW = 13
    local w, _ = mon.getSize()
    local startX = math.floor((w - totalW) / 2)
    if startX < 1 then startX = 1 end

    -- Левая на 1 правее, правая ещё +9 (итого отступ 3 между ними)
    drawTube(startX + 1, c1, top1, b1)
    drawTube(startX + 9, c2, top2, b2)
end
-- local function drawBeeProduceButton(mon, frame)
--     mon.setBackgroundColor(colors.black)
--     mon.clear()

--     mon.setTextColor(colors.white)
--     mon.setCursorPos(5, 1)
--     mon.write("GENE CHECK")
--     -- Плавное покачивание всей пчелы
--     local offset = math.sin(frame * 0.2) * 1
--     local x, y = 3, 6 + offset

--     -- Крылья (меняют положение)
--     local wingShift = (math.floor(frame * 3) % 2 == 0) and 0 or 1
--     -- Левое крыло
--     rect(mon, x + 2, y - 2 + wingShift, 2, 2, colors.lightGray)
--     -- Правое крыло
--     rect(mon, x + 5, y - 2 + wingShift, 2, 2, colors.lightGray)

--     -- Тело
--     rect(mon, x, y, 2, 2, colors.yellow) -- Голова
--     rect(mon, x + 2, y, 2, 2, colors.black)  -- Полоса 1
--     rect(mon, x + 4, y, 2, 2, colors.yellow) -- Полоса 2
--     rect(mon, x + 6, y, 2, 2, colors.black)  -- Полоса 3
--     rect(mon, x + 8, y + 1, 1, 1, colors.gray) -- Жало

--     -- Глаз
--     mon.setCursorPos(x, y)
--     mon.setBackgroundColor(colors.white)
--     mon.write(" ")
-- end

-- Кнопка BREED – цветок, капля и летающие пчелодетки (замедленная)
local function drawBreedButton(mon, frame)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- === 1. НАЗВАНИЕ ===
    mon.setTextColor(colors.lime)
    mon.setCursorPos(4, 1)
    mon.write("BREED")

    -- === 2. ЦВЕТОК (внизу) ===
    mon.setTextColor(colors.green)
    for y = 7, 9 do
        mon.setCursorPos(6, y)
        mon.write("|")
    end
    mon.setTextColor(colors.pink)
    mon.setCursorPos(5, 6)
    mon.write("/")
    mon.setCursorPos(6, 6)
    mon.write("#")
    mon.setCursorPos(7, 6)
    mon.write("\\")
    mon.setCursorPos(5, 7)
    mon.write("\\")
    mon.setCursorPos(7, 7)
    mon.write("/")

    -- === 3. КАПЛЯ (замедленная: 30 кадров вместо 10) ===
    local dropPhase = (frame % 30)  -- теперь 30 кадров на падение
    local dropY = 2 + math.floor(dropPhase * 9 / 30)  -- масштабируем на высоту 9
    if dropY <= 8 then
        mon.setCursorPos(6, dropY)
        mon.setTextColor(colors.orange)
        mon.write(string.char(7))  -- символ •
    end

    -- === 4. ЛЕТАЮЩИЕ ПЧЕЛОДЕТКИ (замедленное движение) ===
    local slowFrame = math.floor(frame / 2)  -- в 2 раза медленнее
    for i = 1, 4 do
        local x = 2 + ((slowFrame * 2 + i * 7) % 11)
        local y = 2 + ((slowFrame * 3 + i * 5) % 5)
        mon.setCursorPos(x, y)
        mon.setTextColor(colors.yellow)
        mon.write("o")
    end
end

function Buttons.drawAll(frame)
    local mons = getMonitors()

    -- Постоянные буферы: создаются один раз на каждый монитор, затем
    -- переиспользуются (не создаём окно на каждый кадр -> нет моргания).
    local function drawWithBuffer(name, buttonMon, drawFn)
        if not buttonMon then return end

        local buf = buffers[name]
        if not buf then
            buf = window.create(buttonMon, 1, 1, buttonMon.getSize())
            buf.setVisible(false)
            buffers[name] = buf
        end

        buf.setVisible(false)
        buf.setBackgroundColor(colors.black)
        buf.clear()
        term.redirect(buf)
        drawFn(buf, frame)
        term.redirect(buttonMon)
        buf.setVisible(true)
        buf.redraw()
    end

    drawWithBuffer("bee_out", mons.bee_out, drawBeeOutButton)
    drawWithBuffer("gene_upgrade", mons.gene_upgrade, drawGeneUpgradeButton)
    drawWithBuffer("gene_produce", mons.gene_produce, drawGeneProduceButton)
    drawWithBuffer("breed", mons.breed, drawBreedButton)
end

local callbacks = {}

function Buttons.setCallbacks(cb)
    callbacks = cb
end

function Buttons.handleTouch(side, x, y)
    local mons = getMonitors()
    local monName = nil

    -- Сначала пробуем по имени периферии (peripheral.getName)
    for name, mon in pairs(mons) do
        if mon and peripheral.getName(mon) == side then
            monName = name
            break
        end
    end

    -- Fallback: сопоставить side с именами из конфига button_monitors
    if not monName then
        local bm = lib.peripherals.button_monitors or {}
        for k, v in pairs(bm) do
            if v == side then
                monName = k
                break
            end
        end
    end

    if not monName then return end

    if monName == "bee_out" and callbacks.onBeeOut then
        callbacks.onBeeOut()
    elseif monName == "gene_upgrade" and callbacks.onGeneUpgrade then
        callbacks.onGeneUpgrade()
    elseif monName == "gene_produce" and (callbacks.onGeneProduce or callbacks.onBeeProduce) then
        if callbacks.onGeneProduce then
            callbacks.onGeneProduce()
        else
            callbacks.onBeeProduce()
        end
    elseif monName == "breed" and callbacks.onBreed then
        callbacks.onBreed()
    end
end

return Buttons