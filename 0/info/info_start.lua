-- info/info_start.lua
local Genetics = require("library")
local config = require("info.HUD_info_config")
-- paintutils глобален

local function drawHiveStatic(mon, baseX, baseY, hiveId)
    local off = config.offsets
    mon.setBackgroundColor(colors.gray)
    mon.setCursorPos(baseX + off.hive_text.x, baseY + off.hive_text.y)
    mon.setTextColor(colors.yellow)
    mon.write(" ---HIVE#" .. string.format("%02d", hiveId) .. "--- ")

    if off.upgrade_symbol then
        for i = 0, off.upgrade_count - 1 do
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(baseX + off.upgrade_symbol.x, baseY + off.upgrade_symbol.y + i)
            mon.setTextColor(colors.white)
            mon.write(">")
        end
    end

    if off.elite then
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.elite.x, baseY + off.elite.y)
        mon.setTextColor(colors.red)
        mon.write(string.char(16) .. "ELITE" .. string.char(17))
    end

    if off.separator then
        for y = baseY + off.separator.start_y, baseY + off.separator.end_y do
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(baseX + off.separator.x, y)
            mon.setTextColor(colors.white)
            mon.write("|")
        end
    end

    if off.gene_headers then
        local headers = Genetics.getGeneHeaders()
        for i, sym in ipairs(headers) do
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(baseX + off.gene_headers.x + (i-1), baseY + off.gene_headers.y)
            mon.setTextColor(colors.white)
            mon.write(sym)
        end
    end

    if off.bee_numbers then
        for i = 1, 5 do
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(baseX + off.bee_numbers.x, baseY + off.bee_numbers.y + (i-1))
            mon.setTextColor(colors.white)
            mon.write(tostring(i))
        end
    end
end

local function drawHiveData(mon, hive, baseX, baseY)
    local off = config.offsets

    -- Имя пчелы или EMPTY
    if hive.data and hive.data.bees and #hive.data.bees > 0 then
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.bee_prefix.x, baseY + off.bee_prefix.y)
        mon.setTextColor(colors.white)
        mon.write("-")

        local beeText
        local beeColor
        local firstType = hive.data.bees[1].type
        local allSame = true
        for _, bee in ipairs(hive.data.bees) do
            if bee.type ~= firstType then
                allSame = false
                break
            end
        end
        if allSame then
            local name = Genetics.formatBeeName(firstType)
            beeText = name .. " x" .. #hive.data.bees
            beeColor = colors.white
        else
            beeText = "WARNING"
            beeColor = config.placeholders.colors.empty
        end
        beeText = beeText .. string.rep(" ", 14 - #beeText)

        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.bee_name.x, baseY + off.bee_name.y)
        mon.setTextColor(beeColor)
        mon.write(beeText)
    else
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.bee_prefix.x, baseY + off.bee_prefix.y)
        mon.setTextColor(config.placeholders.colors.empty)
        mon.write(config.placeholders.no_bee)
    end

    -- Апгрейды
    local upgrades = (hive.data and hive.data.upgrades) or {}
    for i = 1, off.upgrade_count do
        local y = baseY + off.upgrade_list.y + (i - 1)
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.upgrade_list.x, y)
        if i <= #upgrades then
            local key = upgrades[i]
            local name = Genetics.getUpgradeName(key)
            local color = Genetics.getUpgradeColor(key)
            mon.setTextColor(color)
            mon.write(name)
            if #name < 14 then
                mon.write(string.rep(" ", 14 - #name))
            end
        else
            mon.setTextColor(config.placeholders.colors.dash)
            mon.write(config.placeholders.no_upgrade)
        end
    end

    -- Прогресс-бар
    local percent = 0
    if hive.data and hive.data.inventoryPercent then
        percent = hive.data.inventoryPercent
    end
    local fill = math.floor(percent / 100 * off.bar.width + 0.5)
    local barColor = Genetics.getProgressColor(percent)
    for i = 0, off.bar.width - 1 do
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.bar.x + i, baseY + off.bar.y)
        if i < fill then
            mon.setTextColor(barColor)
        else
            mon.setTextColor(config.placeholders.colors.dash)
        end
        mon.write(off.bar.char)
    end

    -- Проценты и %
    mon.setBackgroundColor(colors.gray)
    local pStr = string.format("%03d", math.floor(percent))
    mon.setCursorPos(baseX + off.bar_text.percent_x, baseY + off.bar_text.y)
    mon.setTextColor(barColor)
    mon.write(pStr)

    mon.setBackgroundColor(colors.gray)
    mon.setCursorPos(baseX + off.bar_text.unit_x, baseY + off.bar_text.y)
    mon.setTextColor(config.placeholders.colors.percent)
    mon.write("%")

    if off.bar_text.dash_x then
        mon.setBackgroundColor(colors.gray)
        mon.setCursorPos(baseX + off.bar_text.dash_x, baseY + off.bar_text.y)
        mon.setTextColor(config.placeholders.colors.dash)
        mon.write("-")
    end

    -- Гены
    if hive.data and hive.data.bees then
        for beeIdx = 1, 5 do
            local y = baseY + off.gene_grid.start_y + (beeIdx - 1)
            if beeIdx <= #hive.data.bees then
                local bee = hive.data.bees[beeIdx]
                local geneNames = Genetics.getGeneNames()
                for gIdx, geneName in ipairs(geneNames) do
                    local level = bee.genes and bee.genes[geneName]
                    mon.setBackgroundColor(colors.gray)
                    mon.setCursorPos(baseX + off.gene_grid.start_x + (gIdx-1)*off.gene_grid.spacing_x, y)
                    if level then
                        local sym, color = Genetics.getGeneInfo(geneName, level)
                        mon.setTextColor(color)
                        mon.write(sym)
                    else
                        mon.setTextColor(config.placeholders.colors.dash)
                        mon.write(config.placeholders.no_gene)
                    end
                end
            else
                for gIdx = 1, 4 do
                    mon.setBackgroundColor(colors.gray)
                    mon.setCursorPos(baseX + off.gene_grid.start_x + (gIdx-1)*off.gene_grid.spacing_x, y)
                    mon.setTextColor(config.placeholders.colors.dash)
                    mon.write(config.placeholders.no_gene)
                end
            end
        end
    end
end

local function drawPage(mon, hives, page)
    local bg = paintutils.loadImage("info/HUD_info.nfp")
    if not bg then error("HUD_info.nfp not found!") end
    paintutils.drawImage(bg, 1, 1, mon)

    local grid = config.grid
    local startIdx = (page - 1) * grid.hives_per_page + 1
    for i = 1, grid.hives_per_page do
        local hiveIdx = startIdx + i - 1
        if hiveIdx <= #hives then
            local col = (i - 1) % grid.cols
            local row = math.floor((i - 1) / grid.cols)
            local baseX = grid.start_x + col * grid.offset_x
            local baseY = grid.start_y + row * grid.offset_y
            local hive = hives[hiveIdx]
            drawHiveStatic(mon, baseX, baseY, hive.id)
            drawHiveData(mon, hive, baseX, baseY)
        end
    end
end

local function drawPagination(mon, page, totalPages)
    local pos = config.pagination
    if pos then
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(pos.x, pos.y)
        mon.setTextColor(pos.color or colors.white)
        mon.write(string.format("%d / %d", page, totalPages))
    end
end

local function drawTimer(mon, remaining)
    local t = config.timer
    if t then
        mon.setBackgroundColor(t.bg or colors.black)
        mon.setCursorPos(t.x, t.y)
        mon.setTextColor(t.color or colors.green)
        mon.write(" " .. math.floor(remaining) .. "s")
    end
end

-- Однократная отрисовка на конкретном мониторе с использованием буфера
local function run(mon, page, totalPages, hives, remaining)
    -- Создаём буфер размером с экран монитора
    local buf = window.create(mon, 1, 1, mon.getSize())
    buf.setVisible(false)  -- скрываем отображение до полной отрисовки
    buf.setBackgroundColor(colors.black)
    buf.clear()

    -- Перенаправляем вывод в буфер
    local oldTerm = term.current()
    term.redirect(buf)

    -- Отрисовываем всё в буфер
    drawPage(buf, hives, page)
    drawPagination(buf, page, totalPages)
    drawTimer(buf, remaining)

    -- Возвращаем старый терминал и применяем буфер к монитору
    term.redirect(oldTerm)
    buf.setVisible(true)
    buf.redraw()
end

return { run = run }