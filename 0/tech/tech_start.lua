-- tech/tech_start.lua
local Genetics = require("library")
local HiveReader = require("hive_reader")
local configList = require("tech.HUD_tech_config_1")
local configDetail = require("tech.HUD_tech_config_2")
local LabManager = require("lab_manager")
local Logger = require("logger")
-- paintutils глобален

-- Состояние
local mode = "list"
local currentPage = 1
local selectedHiveIndex = 1

-- Опции запуска (устанавливаются в run; handleClick использует их, напр. sendToLab)
local sharedOpts = nil

-- Таймерные счётчики (модульные, доступны и processTick, и run)
local lastUpdateTime = os.clock()
local updateInterval = 5
local timerTicks = 0

-- Время последнего клика (debounce двойных touch-событий)
local lastTouchTime = 0

-- Цвета фона
local BG_LIST = colors.lightGray
local BG_DETAIL_DARK = colors.black
local BG_DETAIL_GREY = colors.gray
local BG_SYMBOL_LIGHT = colors.lightGray

-- ====================== ОТРИСОВКА СПИСКА ======================

local function drawListCell(mon, hive, baseX, baseY)
    local off = configList.offsets
    local labels = configList.labels

    mon.setBackgroundColor(BG_LIST)
    mon.setCursorPos(baseX + off.hive_text.x, baseY + off.hive_text.y)
    mon.setTextColor(labels.colors.hive)
    mon.write(string.format(labels.hive_template, hive.id))

    if hive.data and hive.data.bees and #hive.data.bees > 0 then
        mon.setBackgroundColor(BG_LIST)
        mon.setCursorPos(baseX + off.bee_prefix.x, baseY + off.bee_prefix.y)
        mon.setTextColor(colors.white)
        mon.write("-")

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
            if #name > 10 then name = name:sub(1,10) end
            local beeText = string.format("%s x%d", name, #hive.data.bees)
            mon.setBackgroundColor(BG_LIST)
            mon.setCursorPos(baseX + off.bee_name.x, baseY + off.bee_name.y)
            mon.setTextColor(labels.colors.bee)
            mon.write(beeText)
        else
            mon.setBackgroundColor(BG_LIST)
            mon.setCursorPos(baseX + off.bee_name.x, baseY + off.bee_name.y)
            mon.setTextColor(labels.colors.empty)
            mon.write("   WARNING")
        end
    else
        mon.setBackgroundColor(BG_LIST)
        mon.setCursorPos(baseX + off.bee_name.x, baseY + off.bee_name.y)
        mon.setTextColor(labels.colors.empty)
        local emptyText = labels.no_bee:gsub("\t", " ")
        mon.write(emptyText)
    end
end

local function drawList(mon)
    local totalHives = HiveReader.count()
    local totalPages = math.ceil(totalHives / configList.grid.hives_per_page)

    local bg = paintutils.loadImage("tech/HUD_tech_1.nfp")
    if bg then
        paintutils.drawImage(bg, 1, 1, mon)
    else
        mon.setBackgroundColor(colors.black)
        mon.clear()
    end

    local grid = configList.grid
    local startIdx = (currentPage - 1) * grid.hives_per_page + 1
    local hives = HiveReader.getHives()

    for i = 1, grid.hives_per_page do
        local hiveIdx = startIdx + i - 1
        if hiveIdx <= #hives then
            local col = (i - 1) % grid.cols
            local row = math.floor((i - 1) / grid.cols)
            local baseX = grid.start_x + col * grid.offset_x
            local baseY = grid.start_y + row * grid.offset_y
            drawListCell(mon, hives[hiveIdx], baseX, baseY)
        end
    end

    local f = configList.footer
    if f then
        local pageText = string.format(f.page.label, currentPage, math.max(totalPages, 1))
        if f.back then
            mon.setBackgroundColor(f.back.bg)
            mon.setTextColor(f.back.fg)
            mon.setCursorPos(f.back.x, f.y)
            mon.write(f.back.label)
        end
        if f.page then
            mon.setBackgroundColor(f.page.bg)
            mon.setTextColor(f.page.fg)
            mon.setCursorPos(f.page.x, f.y)
            mon.write(pageText)
        end
        if f.next then
            mon.setBackgroundColor(f.next.bg)
            mon.setTextColor(f.next.fg)
            mon.setCursorPos(f.next.x, f.y)
            mon.write(f.next.label)
        end
    end
    mon.setBackgroundColor(colors.black)
end

-- ====================== ОТРИСОВКА ДЕТАЛЬНОГО ЭКРАНА ======================

local function drawDetail(mon, hive)
    local cfg = configDetail
    local stats = cfg.stats_hive
    local off = cfg.grid.offsets
    local grid = cfg.grid
    local totalHives = HiveReader.count()

    local bg = paintutils.loadImage("tech/HUD_tech_2.nfp")
    if bg then
        paintutils.drawImage(bg, 1, 1, mon)
    else
        mon.setBackgroundColor(colors.black)
        mon.clear()
    end

    -- Декоративные соты (на сером фоне)
    if cfg.honeycomb then
        mon.setBackgroundColor(BG_DETAIL_GREY)
        local hc = cfg.honeycomb
        for y, line in ipairs(hc.pattern) do
            for x = 1, #line do
                local char = line:sub(x, x)
                if char ~= " " then
                    mon.setCursorPos(hc.start_x + x - 1, hc.start_y + y - 1)
                    mon.setTextColor(colors.yellow)
                    mon.write(char)
                end
            end
        end
    end

    -- === Верхняя часть (чёрный фон) ===
    mon.setBackgroundColor(BG_DETAIL_DARK)

    -- Заголовок улья
    mon.setCursorPos(stats.hive_text.x, stats.hive_text.y)
    mon.setTextColor(colors.yellow)
    mon.write(string.format(stats.hive_template, hive.id))

    -- Апгрейды с символом '>' (на чёрном фоне)
    local upgrades = (hive.data and hive.data.upgrades) or {}
    for i = 1, stats.upgrade_count do
        local y = stats.upgrade_list.y + (i - 1)
        mon.setCursorPos(stats.upgrade_list.x - 1, y)
        mon.setTextColor(colors.white)
        mon.write(">")
        mon.setCursorPos(stats.upgrade_list.x, y)
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
            mon.setTextColor(colors.lightGray)
            mon.write("--------------")
        end
    end

    -- Прогресс-бар
    local percent = 0
    if hive.data and hive.data.inventoryPercent then
        percent = hive.data.inventoryPercent
    end
    local bar = stats.bar
    local fill = math.floor(percent / 100 * bar.width + 0.5)
    local barColor = Genetics.getProgressColor(percent)
    for i = 0, bar.width - 1 do
        mon.setCursorPos(bar.x + i, bar.y)
        if i < fill then
            mon.setTextColor(barColor)
        else
            mon.setTextColor(colors.lightGray)
        end
        mon.write(bar.char)
    end

    -- Проценты и %
    local pStr = string.format("%03d", math.floor(percent))
    mon.setCursorPos(stats.bar_text.percent_x, bar.y)
    mon.setTextColor(barColor)
    mon.write(pStr)

    mon.setCursorPos(stats.bar_text.unit_x, bar.y)
    mon.setTextColor(colors.yellow)
    mon.write("%")

    mon.setCursorPos(stats.bar_text.dash_x, bar.y)
    mon.setTextColor(colors.lightGray)
    mon.write("-")

    -- Статистика слотов, сот, пыльцы (из данных)
    local rows = stats.rows
    if hive.data then
        mon.setCursorPos(rows.slots.x, rows.slots.y)
        mon.setTextColor(colors.white)
        mon.write(rows.slots.label)
        mon.setCursorPos(rows.slots.value_x, rows.slots.y)
        mon.write(tostring(hive.data.occupiedSlots or 0) .. "/9")

        mon.setCursorPos(rows.comb.x, rows.comb.y)
        mon.write(rows.comb.label)
        mon.setCursorPos(rows.comb.value_x, rows.comb.y)
        mon.write(tostring(hive.data.combCount or 0))

        mon.setCursorPos(rows.puff.x, rows.puff.y)
        mon.write(rows.puff.label)
        mon.setCursorPos(rows.puff.value_x, rows.puff.y)
        mon.write(tostring(hive.data.puffCount or 0))
    else
        mon.setCursorPos(rows.slots.x, rows.slots.y)
        mon.write(rows.slots.label)
        mon.setCursorPos(rows.slots.value_x, rows.slots.y)
        mon.write("?/9")
    end

    -- === Нижняя часть: карточки пчёл ===
    local bees = (hive.data and hive.data.bees) or {}
    for cellIdx = 1, 5 do
        local col = (cellIdx - 1) % 3
        local row = math.floor((cellIdx - 1) / 3)
        local baseX = grid.start_x + col * grid.offset_x
        local baseY = grid.start_y + row * grid.offset_y

        mon.setBackgroundColor(BG_DETAIL_GREY)

        if cellIdx <= #bees then
            local bee = bees[cellIdx]
            -- Имя пчелы (обрезаем до 10 символов)
            local beeName = Genetics.formatBeeName(bee.type) or "Unknown"
            if #beeName > 10 then beeName = beeName:sub(1,10) end
            mon.setCursorPos(baseX + off.title.x, baseY + off.title.y)
            mon.setTextColor(colors.white)
            mon.write(string.format("%s#%d", beeName, cellIdx))

            -- Гены
            local geneMap = {
                { nameKey = "bee_productivity",      title = off.gene_Productivity,     val = off.gene_Productivity_val },
                { nameKey = "bee_weather_tolerance", title = off.gene_W_Tolerance,      val = off.gene_W_Tolerance_val },
                { nameKey = "bee_behavior",          title = off.gene_Behavior,         val = off.gene_Behavior_val },
                { nameKey = "bee_endurance",         title = off.gene_Endurance,        val = off.gene_Endurance_val },
            }
            for gIdx, gene in ipairs(geneMap) do
                local level = bee.genes and bee.genes[gene.nameKey]

                -- Символ "-" перед названием гена (светло-серый фон)
                mon.setBackgroundColor(BG_SYMBOL_LIGHT)
                mon.setCursorPos(baseX + off.prefix_gene.x, baseY + off.prefix_gene.y + (gIdx-1)*2)
                mon.setTextColor(colors.white)
                mon.write("-")

                -- Название гена (серый фон)
                mon.setBackgroundColor(BG_DETAIL_GREY)
                mon.setCursorPos(baseX + gene.title.x, baseY + gene.title.y)
                mon.setTextColor(colors.white)
                mon.write(Genetics.genes[gene.nameKey].name)

                -- Символ ">" перед значением (светло-серый фон)
                mon.setBackgroundColor(BG_SYMBOL_LIGHT)
                mon.setCursorPos(baseX + off.prefix_gene.x, baseY + off.prefix_gene.y + (gIdx-1)*2 + 1)
                mon.setTextColor(colors.white)
                mon.write(">")

                -- Значение гена (серый фон)
                mon.setBackgroundColor(BG_DETAIL_GREY)
                mon.setCursorPos(baseX + gene.val.x, baseY + gene.val.y)
                if level then
                    local text, color = Genetics.getGeneLevel(gene.nameKey, level)
                    mon.setTextColor(color)
                    mon.write(text)
                else
                    mon.setTextColor(colors.lightGray)
                    mon.write("-")
                end
            end
        else
            -- Пустая ячейка
            mon.setCursorPos(baseX + off.title.x, baseY + off.title.y)
            mon.setTextColor(colors.red)
            mon.write(cfg.labels.no_bee)
        end
    end

    -- Футер детального экрана
    local f = configDetail.footer
    if f then
        local pageText = string.format(f.page.label, selectedHiveIndex, math.max(totalHives, 1))
        if f.back then
            mon.setBackgroundColor(f.back.bg)
            mon.setTextColor(f.back.fg)
            mon.setCursorPos(f.back.x, f.y)
            mon.write(f.back.label)
        end
        if f.page then
            mon.setBackgroundColor(f.page.bg)
            mon.setTextColor(f.page.fg)
            mon.setCursorPos(f.page.x, f.y)
            mon.write(pageText)
        end
        if f.next then
            mon.setBackgroundColor(f.next.bg)
            mon.setTextColor(f.next.fg)
            mon.setCursorPos(f.next.x, f.y)
            mon.write(f.next.label)
        end
    end
    mon.setBackgroundColor(colors.black)
end

-- ====================== ОБРАБОТКА КЛИКОВ ======================

local function handleClick(mon, x, y)
    if mode == "list" then
        local grid = configList.grid
        local hives = HiveReader.getHives()
        local startIdx = (currentPage - 1) * grid.hives_per_page + 1
        for i = 1, grid.hives_per_page do
            local hiveIdx = startIdx + i - 1
            if hiveIdx <= #hives then
                local col = (i - 1) % grid.cols
                local row = math.floor((i - 1) / grid.cols)
                local cellX1 = grid.start_x + col * grid.offset_x
                local cellY1 = grid.start_y + row * grid.offset_y
                local cellX2 = cellX1 + 13
                local cellY2 = cellY1 + 2
                if x >= cellX1 and x <= cellX2 and y >= cellY1 and y <= cellY2 then
                    selectedHiveIndex = hiveIdx
                    mode = "detail"
                    drawDetail(mon, hives[hiveIdx])
                    return
                end
            end
        end
        -- Кнопки навигации в списке (если будут добавлены)
    elseif mode == "detail" then
        local s = configDetail.screen
        if not s then return end
        if x >= s.lab_button.x1 and x <= s.lab_button.x2 and y >= s.lab_button.y1 and y <= s.lab_button.y2 then
    local hive = HiveReader.getHives()[selectedHiveIndex]
    if hive then
                local hiveBlockName = hive.hiveBlock   -- это строка из конфига
        if hiveBlockName then
            -- Неблокирующая отправка: startSend начинает state-машину,
            -- завершение идёт по таймеру через sendTick.
            if sharedOpts and sharedOpts.sendToLab then
                sharedOpts.sendToLab(selectedHiveIndex, hive.data, hiveBlockName)
                Logger.log("LAB: send started (non-blocking) for hive " .. selectedHiveIndex)
            else
                -- Fallback: синхронный запуск без таймера (не должен случиться)
                LabManager.startSend(selectedHiveIndex, hive.data, hiveBlockName)
                Logger.log("LAB: send (no tick available) for hive " .. selectedHiveIndex)
            end
        else
            Logger.log("LAB: hiveBlockName is nil for hive " .. selectedHiveIndex)
        end
    end
        elseif x >= s.back_button.x1 and x <= s.back_button.x2 and y >= s.back_button.y1 and y <= s.back_button.y2 then
            if selectedHiveIndex > 1 then
                selectedHiveIndex = selectedHiveIndex - 1
                drawDetail(mon, HiveReader.getHives()[selectedHiveIndex])
            end
        elseif x >= s.next_button.x1 and x <= s.next_button.x2 and y >= s.next_button.y1 and y <= s.next_button.y2 then
            if selectedHiveIndex < HiveReader.count() then
                selectedHiveIndex = selectedHiveIndex + 1
                drawDetail(mon, HiveReader.getHives()[selectedHiveIndex])
            end
        elseif x >= s.page_button.x1 and x <= s.page_button.x2 and y >= s.page_button.y1 and y <= s.page_button.y2 then
            mode = "list"
            drawList(mon)
        end
    end
end

-- ====================== ОСНОВНОЙ ЦИКЛ ======================

-- Один тик (только heartbeat + данные + watchdog, БЕЗ info/sendTick)
local dataBusy = false
local function processTick(mon, opts, now)
    timerTicks = (timerTicks or 0) + 1
    if timerTicks % 10 == 0 then
        Logger.log("TECH heartbeat tick " .. timerTicks)
    end

    -- Watchdog: если отправка зависла >60с — сброс
    LabManager.abortStuckSend()

    -- Асинхронный запрос данных (воркер HiveReader.worker живёт отдельно)
    if now - lastUpdateTime >= updateInterval and not dataBusy and not LabManager.isSending() then
        dataBusy = true
        HiveReader.requestUpdate()
    end
end

local function run(mon, opts)
    opts = opts or {}
    sharedOpts = opts
    LabManager.reset()

    local oldTerm = term.redirect(mon)
    mon.setTextScale(1.0)
    Logger.log("TECH: run started, term->" .. tostring(peripheral.getName(mon)))

    local function exitRun(res)
        term.redirect(oldTerm)
        sharedOpts = nil
        return res
    end

    local function redrawCurrent()
        if mode == "list" then drawList(mon)
        else drawDetail(mon, HiveReader.getHives()[selectedHiveIndex]) end
    end

    if mode == "detail" and (selectedHiveIndex < 1 or selectedHiveIndex > HiveReader.count()) then
        mode = "list"
    end

    -- Первый кадр сразу
    local okFirst = pcall(redrawCurrent)
    if not okFirst then Logger.log("TECH: initial draw failed") end
    HiveReader.requestUpdate()

    local lastTickTime = os.clock()
    local tickTimer = os.startTimer(0.1)

    -- Простой loop без parallel: parallel-оркестрация в BeeOs.runScreens
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        tickTimer = os.startTimer(0.1)
        local now = os.clock()

        local ok, err = pcall(function()
            if event == "timer" and p1 == tickTimer then
                if now - lastTickTime >= 0.1 then
                    lastTickTime = now
                    local okT = pcall(processTick, mon, opts, now)
                    if not okT then Logger.log("TECH: processTick error") end
                end

            elseif event == "monitor_touch" and p1 == peripheral.getName(mon) then
                now = os.clock()
                if not lastTouchTime or now - lastTouchTime >= 0.3 then
                    lastTouchTime = now
                    pcall(handleClick, mon, p2, p3)
                end

            elseif event == "rednet_message" then
                local sender, msg = p1, p2
                Logger.log("TECH rednet " .. tostring(sender) .. ": " .. textutils.serialize(msg))
                if opts.rednetHandler then
                    local okH, action = pcall(opts.rednetHandler, sender, msg)
                    if okH then
                        Logger.log("TECH: rednetHandler action='" .. tostring(action) .. "'")
                        if action == "reload" or action == "freeze" then
                            Logger.log("TECH: exiting run loop, action=" .. tostring(action))
                            return exitRun(action)
                        end
                    else
                        Logger.log("TECH: rednetHandler error: " .. tostring(action))
                    end
                end
                if msg and msg.type == "lab_complete" then
                    Logger.log("TECH lab_complete for hive " .. tostring(msg.hive_id))
                    pcall(function()
                        LabManager.returnBeesToHive(msg.hive_id, msg.bee_count or 0)
                        HiveReader.requestUpdate()
                        redrawCurrent()
                    end)
                end

            elseif event == HiveReader.READ_COMPLETE then
                dataBusy = false
                lastUpdateTime = now
                pcall(redrawCurrent)

            elseif event == "send_complete" then
                pcall(redrawCurrent)
            end
        end)
        if not ok then Logger.log("TECH: loop error: " .. tostring(err)) end
    end
end

return { run = run }