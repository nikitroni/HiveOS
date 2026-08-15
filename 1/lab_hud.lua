-- lab_hud.lua
-- Отрисовка основного лабораторного монитора (71x26) поверх .nfp фона.

local config = require("lab_config")
local Utils = require("lab_utils")
local Genetics = require("lab_genetics")
local Anim = require("lab_animations")
local paintutils = _G.paintutils
local staticDrawn = false
local staticBuffer = nil

local HUD = {}

local function stripColorCodes(str)
    return str:gsub("§.", "")
end

local MAIN_MONITOR = peripheral.wrap(config.peripherals.main_monitor)
if not MAIN_MONITOR then error("Main monitor not found!") end
MAIN_MONITOR.setTextScale(1.0)

local background = nil
if config.peripherals.bg_file and fs.exists(config.peripherals.bg_file) then
    background = paintutils.loadImage(config.peripherals.bg_file)
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
    local panel = config.gene_indexer_panel
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
    local panel = config.bee_genetics_panel
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
    local grid = config.bee_grid
    for i = 1, 5 do
        local baseX = grid.start_x + (i-1) * grid.offset_x
        local baseY = grid.start_y
        local bee = bees[i]
        local off = grid.offsets

        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.title.x, baseY + off.title.y)
        if bee then
            local beeName = Genetics.formatBeeName(bee.type) or "Unknown"
            if #beeName > 10 then beeName = beeName:sub(1,10) end
            mon.setTextColor(colors.white)
            mon.write(string.format("%s#%d", beeName, i))
        else
            mon.setTextColor(colors.red)
            mon.write(config.labels.no_bee)
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
                local color = Genetics.getGeneLevelColor(name, value) or colors.white
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
    local area = config.log_area
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
    local dna = config.dna
    Anim.drawDNA(mon, dna.left_start_x, dna.start_y, dna.height, frame, false)
    Anim.drawDNA(mon, dna.right_start_x, dna.start_y, dna.height, frame, true)
end

-- ==================== ПОЛНАЯ ОТРИСОВКА ====================
function HUD.drawAll(bees, geneCounts, neededCounts, mode, logLines, frame)
    local mon = MAIN_MONITOR
    local oldTerm = term.redirect(mon)

    -- Рисуем фон каждый кадр (стирает предыдущее)
    if background then
        paintutils.drawImage(background, 1, 1, mon)
    else
        mon.setBackgroundColor(colors.black)
        mon.clear()
    end

    -- ДНК (анимация)
    HUD.drawDNA(mon, frame)

    -- Динамические элементы
    HUD.drawGeneIndexer(mon, geneCounts)
    HUD.drawBeeGenetics(mon, neededCounts)
    HUD.drawBeeCards(mon, bees)
    HUD.drawLogArea(mon, mode, logLines, frame)

    term.redirect(oldTerm)
end

return HUD