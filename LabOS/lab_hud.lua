-- lab_hud.lua
-- Drawing of the main laboratory monitor (71x26) on top of the .nfp background.

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

-- The main monitor is resolved LAZILY (only when the peripherals are already configured
-- by the HeartOS config): at start the config may not exist yet, and we wait
-- for it in the console without touching the monitors.
local MAIN_MONITOR = nil
local function getMainMonitor()
    if not MAIN_MONITOR then
        --- @type table
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

-- Static levels for genes
local GENE_LEVELS = {
    productivity = "Very High",
    endurance    = "Strong",
    behavior     = "Metaturnal",
    weather_tolerance = "Any"
}

-- ==================== LEFT PANEL (GENES IN THE INDEXER) ====================
function HUD.drawGeneIndexer(mon, geneCounts)
    local panel = lib.gene_indexer_panel
    local baseX = panel.start_x
    local baseY = panel.start_y
    drawPanelTitle(mon, panel)

    for _, gene in ipairs(panel.genes) do
        -- Gene name
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(baseX + gene.name_x, baseY + gene.name_y)
        mon.setTextColor(colors.white)
        mon.write(gene.name)

        local level = GENE_LEVELS[gene.key] or "Unknown"
        local count = geneCounts[gene.key] or 0

        -- Level (red)
        mon.setCursorPos(baseX + gene.level_x, baseY + gene.level_y)
        mon.setTextColor(colors.red)
        mon.write(level)

        -- Count (green) on the right
        mon.setCursorPos(baseX + gene.count_x, baseY + gene.count_y)
        mon.setTextColor(colors.green)
        mon.write(string.format("-%03dpcs", count))
    end
end

-- ==================== RIGHT PANEL (NEEDS) ====================
function HUD.drawBeeGenetics(mon, neededCounts)
    local panel = lib.bee_genetics_panel
    local baseX = panel.start_x
    local baseY = panel.start_y
    drawPanelTitle(mon, panel)

    for _, need in ipairs(panel.needs) do
        -- Gene name (white)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(baseX + need.name_x, baseY + need.name_y)
        mon.setTextColor(colors.white)
        mon.write(need.name)

        local level = GENE_LEVELS[need.key] or "Unknown"
        local count = neededCounts[need.key] or 0

        -- "Need: level" line (red) - at the need_x, need_y coordinates
        local needLine = "Need:" .. level
        mon.setCursorPos(baseX + need.need_x, baseY + need.need_y)
        mon.setTextColor(colors.red)
        mon.write(needLine)

        -- Count " -00pcs" (yellow) - at the count_x, count_y coordinates
        local countPart = "-" .. string.format("%02d", count) .. "pcs"
        mon.setCursorPos(baseX + need.count_x, baseY + need.count_y)
        mon.setTextColor(colors.yellow)
        mon.write(countPart)
    end
end

-- ==================== BEE CARDS (at the bottom) ====================
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
            -- Function to output a single gene
            local function writeGene(name, value, xName, yName, xVal, yVal)
                mon.setCursorPos(baseX + xName, baseY + yName)
                mon.setTextColor(colors.white)
                mon.write(name)

                local level = value:match("%.(.+)$") or value
                -- First letter uppercase
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

-- ==================== LOG AREA ====================
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
            -- Truncate to width and pad with spaces
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

-- ==================== DNA STRANDS ====================
function HUD.drawDNA(mon, frame)
    local dna = lib.dna
    Anim.drawDNA(mon, dna.left_start_x, dna.start_y, dna.height, frame, false)
    Anim.drawDNA(mon, dna.right_start_x, dna.start_y, dna.height, frame, true)
end

-- ==================== PERSISTENT MAIN MONITOR BUFFER ====================
-- Created once; every frame we draw into a hidden window and output with a single
-- redraw(). Between frames the monitor keeps the previous frame (no blinking).
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

-- ==================== FULL REDRAW ====================
-- Everything is drawn into a hidden buffer, then atomically to the monitor with one redraw().
function HUD.drawAll(bees, geneCounts, neededCounts, mode, logLines, frame, status)
    local mon = getMainMonitor()
    if not mon then return end   -- peripherals not configured yet, waiting for the config

    local win = getBuffer(mon)
    win.setVisible(false)
    win.setBackgroundColor(colors.black)
    win.clear()

    local oldTerm = term.redirect(win)

    -- Draw the background into the buffer
    if background then
        paintutils.drawImage(background, 1, 1, win)
    else
        win.setBackgroundColor(colors.black)
        win.clear()
    end

    -- DNA (animation)
    HUD.drawDNA(win, frame)

    -- Dynamic elements
    HUD.drawGeneIndexer(win, geneCounts)
    HUD.drawBeeGenetics(win, neededCounts)
    HUD.drawBeeCards(win, bees)
    HUD.drawLogArea(win, mode, logLines, frame)

    -- Status indicator (BUSY - terminal is busy with a task)
    if status then
        win.setCursorPos(1, 1)
        win.setTextColor(status == "busy" and colors.red or colors.green)
        win.setBackgroundColor(colors.black)
        win.write(status == "busy" and "BUSY" or "free")
    end

    term.redirect(oldTerm)

    -- Atomic output of the whole frame
    win.setVisible(true)
    win.redraw()
end

return HUD