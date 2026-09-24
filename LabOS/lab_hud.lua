-- lab_hud.lua
-- Отрисовка основного лабораторного монитора (71x26) поверх .nfp фона.

local lib = require("lab_lib")
local Utils = require("lab_utils")
local Anim = require("lab_animations")
local paintutils = _G.paintutils
local staticDrawn = false
local staticBuffer = nil

local HUD = {}

local function stripColorCodes(str)
    return str:gsub("§.", "")
end

-- Главный монитор резолвится ЛЕНИВО (только когда периферия уже настроена
-- конфигом от HeartOS): при старте конфига может ещё не быть, и мы ждём
-- его в консоли, не трогая мониторы.
local MAIN_MONITOR = nil
local function getMainMonitor()
    if not MAIN_MONITOR then
        local mon = peripheral.wrap(lib.peripherals.main_monitor)
        if mon then
            mon.setTextScale(1.0)
            MAIN_MONITOR = mon
        end
    end
    return MAIN_MONITOR
end

local background = nil
if lib.bg_file and fs.exists(lib.bg_file) then
    background = paintutils.loadImage(lib.bg_file)
else
    print("Background file not found. Using black background.")
end

local function drawPanelTitle(mon, panelConfig)
    local baseX = panelConfig.start_x
    local baseY = panelConfig.start_y
    local chars = panelConfig.title_chars
    for _, ch in ipairs(chars) do
        mon.setCursorPos(baseX + ch.x, baseY)
        mon.setTextColor(ch.col)
        mon.setBackgroundColor(colors.black)
        mon.write(ch.char)
    end
end

-- Статические уровни для генов
local GENE_LEVELS = {
    productivity = "Very High",
    endurance    = "Strong",
    behavior     = "Metaturnal",
    weather_tolerance = "Any"
}

-- ==================== ЛЕВАЯ ПАНЕЛЬ (ГЕНЫ В ИНДЕКСЕРЕ) ====================
function HUD.drawGeneIndexer(mon, geneCounts)
    local panel = lib.gene_indexer_panel
    local baseX = panel.start_x
    local baseY = panel.start_y
    drawPanelTitle(mon, panel)

    for _, gene in ipairs(panel.genes) do
        -- Название гена
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(baseX + gene.name_x, baseY + gene.name_y)
        mon.setTextColor(colors.white)
        mon.write(gene.name)

        local level = GENE_LEVELS[gene.key] or "Unknown"
        local count = geneCounts[gene.key] or 0

        -- Уровень (красный)
        mon.setCursorPos(baseX + gene.level_x, baseY + gene.level_y)
        mon.setTextColor(colors.red)
        mon.write(level)

        -- Количество (зелёное) справа
        mon.setCursorPos(baseX + gene.count_x, baseY + gene.count_y)
        mon.setTextColor(colors.green)
        mon.write(string.format("-%03dpcs", count))
    end
end

-- ==================== ПРАВАЯ ПАНЕЛЬ (ПОТРЕБНОСТИ) ====================
function HUD.drawBeeGenetics(mon, neededCounts)
    local panel = lib.bee_genetics_panel
    local baseX = panel.start_x
    local baseY = panel.start_y
    drawPanelTitle(mon, panel)

    for _, need in ipairs(panel.needs) do
        -- Название гена (белое)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(baseX + need.name_x, baseY + need.name_y)
        mon.setTextColor(colors.white)
        mon.write(need.name)

        local level = GENE_LEVELS[need.key] or "Unknown"
        local count = neededCounts[need.key] or 0

        -- Строка "Need: уровень" (красная) – по координатам need_x, need_y
        local needLine = "Need:" .. level
        mon.setCursorPos(baseX + need.need_x, baseY + need.need_y)
        mon.setTextColor(colors.red)
        mon.write(needLine)

        -- Количество " -00pcs" (жёлтое) – по координатам count_x, count_y
        local countPart = "-" .. string.format("%02d", count) .. "pcs"
        mon.setCursorPos(baseX + need.count_x, baseY + need.count_y)
        mon.setTextColor(colors.yellow)
        mon.write(countPart)
    end
end

-- ==================== КАРТОЧКИ ПЧЁЛ (внизу) ====================
function HUD.drawBeeCards(mon, bees)
    local grid = lib.bee_grid
    for i = 1, 5 do
        local baseX = grid.start_x + (i-1) * grid.offset_x
        local baseY = grid.start_y
        local bee = bees[i]
        local off = grid.offsets

        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.title.x, baseY + off.title.y)
        if bee then
            local beeName = lib.formatBeeName(bee.type) or "Unknown"
            if #beeName > 10 then beeName = beeName:sub(1,10) end
            mon.setTextColor(colors.white)
            mon.write(string.format("%s#%d", beeName, i))
        else
            mon.setTextColor(colors.red)
            mon.write(lib.labels.no_bee)
        end

        if bee then
            -- Функция для вывода одного гена
            local function writeGene(name, value, xName, yName, xVal, yVal)
                mon.setCursorPos(baseX + xName, baseY + yName)
                mon.setTextColor(colors.white)
                mon.write(name)

                local level = value:match("%.(.+)$") or value
                -- Первая буква заглавная
                level = level:gsub("^%l", string.upper)
                local color = lib.getGeneLevelColor(name, value) or colors.white
                mon.setCursorPos(baseX + xVal, baseY + yVal)
                mon.setTextColor(color)
                mon.write(level)
            end

            writeGene("Productivity", bee.productivity,
                off.gene_Productivity.x, off.gene_Productivity.y,
                off.gene_Productivity_val.x, off.gene_Productivity_val.y)
            writeGene("Endurance", bee.endurance,
                off.gene_Endurance.x, off.gene_Endurance.y,
                off.gene_Endurance_val.x, off.gene_Endurance_val.y)
            writeGene("Behavior", bee.behavior,
                off.gene_Behavior.x, off.gene_Behavior.y,
                off.gene_Behavior_val.x, off.gene_Behavior_val.y)
            writeGene("W.Tolerance", bee.weather_tolerance,
                off.gene_W_Tolerance.x, off.gene_W_Tolerance.y,
                off.gene_W_Tolerance_val.x, off.gene_W_Tolerance_val.y)
        end
    end
end

-- ==================== ОБЛАСТЬ ЛОГА ====================
function HUD.drawLogArea(mon, mode, logLines, frame)
    local area = lib.log_area
    local baseX = area.start_x
    local baseY = area.start_y

    mon.setBackgroundColor(colors.black)
    mon.setCursorPos(baseX, area.title_y)
    mon.setTextColor(colors.white)
    mon.write(area.title)

    if mode == "wait" then
        Anim.drawWait(mon, baseX, baseY + 1, frame)
    elseif mode == "win" then
        Anim.drawWin(mon, baseX, baseY + 1, frame)
    else
        local lines = logLines or {}
        local startIdx = math.max(1, #lines - 8)
        for i = 1, 9 do
            local lineIdx = startIdx + i - 1
            local rawText = lines[lineIdx] or ""
            local cleanText = stripColorCodes(rawText)
            -- Обрезаем до ширины и дополняем пробелами
            if #cleanText > area.width then
                cleanText = cleanText:sub(1, area.width)
            else
                cleanText = cleanText .. string.rep(" ", area.width - #cleanText)
            end
            mon.setCursorPos(area.content_x, area.content_y + i - 1)
            mon.setTextColor(colors.white)
            mon.setBackgroundColor(colors.black)
            mon.write(cleanText)
        end
    end
end

-- ==================== ДНК-ЦЕПОЧКИ ====================
function HUD.drawDNA(mon, frame)
    local dna = lib.dna
    Anim.drawDNA(mon, dna.left_start_x, dna.start_y, dna.height, frame, false)
    Anim.drawDNA(mon, dna.right_start_x, dna.start_y, dna.height, frame, true)
end

-- ==================== ПОСТОЯННЫЙ БУФЕР ГЛАВНОГО МОНИТОРА ====================
-- Создаётся один раз; каждый кадр рисуем в скрытое окно и выводим одним
-- redraw(). Между кадрами монитор держит предыдущий кадр (без мигания).
local staticBuffer = nil
local staticBufferMon = nil
local function getBuffer(mon)
    if not staticBuffer or staticBufferMon ~= mon then
        staticBuffer = window.create(mon, 1, 1, mon.getSize())
        staticBufferMon = mon
        staticBuffer.setVisible(false)
    end
    return staticBuffer
end

-- ==================== ПОЛНАЯ ОТРИСОВКА ====================
-- Всё рисуется в скрытый буфер, затем одним redraw() атомарно на монитор.
function HUD.drawAll(bees, geneCounts, neededCounts, mode, logLines, frame, status)
    local mon = getMainMonitor()
    if not mon then return end   -- периферия ещё не настроена, ждём конфиг

    local win = getBuffer(mon)
    win.setVisible(false)
    win.setBackgroundColor(colors.black)
    win.clear()

    local oldTerm = term.redirect(win)

    -- Рисуем фон в буфер
    if background then
        paintutils.drawImage(background, 1, 1, win)
    else
        win.setBackgroundColor(colors.black)
        win.clear()
    end

    -- ДНК (анимация)
    HUD.drawDNA(win, frame)

    -- Динамические элементы
    HUD.drawGeneIndexer(win, geneCounts)
    HUD.drawBeeGenetics(win, neededCounts)
    HUD.drawBeeCards(win, bees)
    HUD.drawLogArea(win, mode, logLines, frame)

    -- Индикатор статуса (BUSY - терминал занят задачей)
    if status then
        win.setCursorPos(1, 1)
        win.setTextColor(status == "busy" and colors.red or colors.green)
        win.setBackgroundColor(colors.black)
        win.write(status == "busy" and "BUSY" or "free")
    end

    term.redirect(oldTerm)

    -- Атомарный вывод всего кадра
    win.setVisible(true)
    win.redraw()
end

return HUD