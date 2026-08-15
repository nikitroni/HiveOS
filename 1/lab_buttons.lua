-- lab_buttons.lua
-- Модуль для управления 4 мониторами-кнопками.
-- Каждая кнопка имеет свой монитор, анимируется независимо и обрабатывает нажатия.

local config = require("lab_config")
local Buttons = {}

local monitors = {
    bee_out = peripheral.wrap(config.peripherals.button_monitors.bee_out),
    gene_upgrade = peripheral.wrap(config.peripherals.button_monitors.gene_upgrade),
    bee_produce = peripheral.wrap(config.peripherals.button_monitors.bee_produce),
    refresh = peripheral.wrap(config.peripherals.button_monitors.refresh),
}

for name, mon in pairs(monitors) do
    if not mon then
        error("Monitor for button " .. name .. " not found!")
    end
    mon.setTextScale(0.5)
end

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

-- Кнопка BEE (производство генов)
local function drawBeeProduceButton(mon, frame)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    mon.setTextColor(colors.white)
    mon.setCursorPos(5, 1)
    mon.write("BEE CHECK")
    -- Плавное покачивание всей пчелы
    local offset = math.sin(frame * 0.2) * 1
    local x, y = 3, 6 + offset

    -- Крылья (меняют положение)
    local wingShift = (math.floor(frame * 3) % 2 == 0) and 0 or 1
    -- Левое крыло
    rect(mon, x + 2, y - 2 + wingShift, 2, 2, colors.lightGray)
    -- Правое крыло
    rect(mon, x + 5, y - 2 + wingShift, 2, 2, colors.lightGray)

    -- Тело
    rect(mon, x, y, 2, 2, colors.yellow) -- Голова
    rect(mon, x + 2, y, 2, 2, colors.black)  -- Полоса 1
    rect(mon, x + 4, y, 2, 2, colors.yellow) -- Полоса 2
    rect(mon, x + 6, y, 2, 2, colors.black)  -- Полоса 3
    rect(mon, x + 8, y + 1, 1, 1, colors.gray) -- Жало

    -- Глаз
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(colors.white)
    mon.write(" ")
end

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
    drawBeeOutButton(monitors.bee_out, frame)
    drawGeneUpgradeButton(monitors.gene_upgrade, frame)
    drawBeeProduceButton(monitors.bee_produce, frame)
    drawBreedButton(monitors.refresh, frame)
end

local callbacks = {}

function Buttons.setCallbacks(cb)
    callbacks = cb
end

function Buttons.handleTouch(side, x, y)
    local monName = nil
    for name, mon in pairs(monitors) do
        if peripheral.getName(mon) == side then
            monName = name
            break
        end
    end
    if not monName then return end

    if monName == "bee_out" and callbacks.onBeeOut then
        callbacks.onBeeOut()
    elseif monName == "gene_upgrade" and callbacks.onGeneUpgrade then
        callbacks.onGeneUpgrade()
    elseif monName == "bee_produce" and callbacks.onBeeProduce then
        callbacks.onBeeProduce()
    elseif monName == "refresh" and callbacks.onRefresh then
        callbacks.onRefresh()
    end
end

return Buttons