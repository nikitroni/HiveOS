-- monitor_util.lua
-- Helper functions for monitor UI: buttons, text, dialogs, paginated views

local MonitorUtil = {}

-- Default color palette
local COLORS = {
    bg = colors.black,
    text = colors.white,
    button_bg = colors.gray,
    button_text = colors.white,
    button_hover_bg = colors.lightGray,
    title = colors.yellow,
    error = colors.red,
    success = colors.green,
    highlight = colors.cyan,
}

MonitorUtil.COLORS = COLORS

-- ==================== BUTTONS ====================

-- Create button data structure
-- Single line buttons (no 2-line bracket wrapping)
-- height is optional (default 1) and used for rectangular hit testing
function MonitorUtil.createButton(x, y, width, label, action, color, height)
    return {
        x = x, y = y,
        width = width or #label,
        height = height or 1,
        label = label,
        action = action or "",
        color = color or COLORS.button_bg,
    }
end

-- Draw a single button.
-- Button fill = button.color; label color = button.textColor (default white).
-- A label may contain "\n" to break it into several lines, which are drawn
-- on consecutive rows from button.y (up to button.height rows).
function MonitorUtil.drawButton(mon, button, isHovered)
    local bgColor = isHovered and COLORS.button_hover_bg or button.color
    local x = button.x
    local y = button.y
    local width = button.width or #(button.label or "")
    if width < 1 then width = 1 end
    local height = button.height or 1
    mon.setBackgroundColor(bgColor)
    mon.setTextColor(button.textColor or COLORS.button_text)

    -- Split the label into lines on "\n". Empty lines are kept so a leading
    -- or trailing "\n" shifts the text (e.g. "\nConfig BeeOS" -> row 2).
    local lines = {}
    for line in ((button.label or "") .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    if #lines == 0 then lines = {""} end

    -- Fill every row of the button block with bgColor and write lines on top.
    for row = 0, height - 1 do
        local line = lines[row + 1] or ""
        if #line < width then
            line = line .. string.rep(" ", width - #line)
        end
        mon.setCursorPos(x, y + row)
        mon.write(line)
    end
    mon.setBackgroundColor(COLORS.bg)
end

-- Draw multiple buttons in a row (evenly spaced)
-- buttons: array of button tables (must have .width)
-- startX, y: position
-- totalWidth: total available width
function MonitorUtil.drawButtonRow(mon, buttons, startX, y, totalWidth)
    if #buttons == 0 then return end

    local totalBtnWidth = 0
    for _, btn in ipairs(buttons) do
        totalBtnWidth = totalBtnWidth + btn.width
    end
    local gap = math.floor((totalWidth - totalBtnWidth) / (#buttons + 1))
    if gap < 1 then gap = 1 end

    local curX = startX + gap
    for _, btn in ipairs(buttons) do
        btn.x = curX
        btn.y = y
        MonitorUtil.drawButton(mon, btn, false)
        curX = curX + btn.width + gap
    end
end

-- ==================== TEXT & TITLE ====================

-- Draw centered title. bg is optional (defaults to COLORS.bg).
function MonitorUtil.drawTitle(mon, text, y, bg)
    local w, h = mon.getSize()
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    mon.setCursorPos(x, y)
    mon.setTextColor(COLORS.title)
    mon.setBackgroundColor(bg or COLORS.bg)
    mon.write(text)
end

-- Draw text at position. bg is optional (defaults to COLORS.bg).
-- When drawing over a HUD background, pass a bg matching the image
-- so the text does not paint a black box over it.
function MonitorUtil.drawText(mon, x, y, text, color, bg)
    mon.setCursorPos(x, y)
    mon.setTextColor(color or COLORS.text)
    mon.setBackgroundColor(bg or COLORS.bg)
    mon.write(text)
end

-- Draw wrapped text. Splits long lines to fit within maxWidth (chars).
-- Returns the next available Y position.
function MonitorUtil.drawTextWrap(mon, x, y, text, maxWidth, color)
    color = color or COLORS.text
    mon.setTextColor(color)
    mon.setBackgroundColor(COLORS.bg)
    local w = mon.getSize()
    local limit = maxWidth or (w - x)
    if limit < 1 then limit = 1 end
    local curY = y
    while #text > 0 do
        if #text <= limit then
            mon.setCursorPos(x, curY)
            mon.write(text)
            curY = curY + 1
            break
        else
            -- Try to break at space
            local breakAt = limit
            -- Find last space within limit
            local lastSpace = text:sub(1, limit):match("^.*%s")
            if lastSpace then
                breakAt = #lastSpace - 1
            end
            if breakAt < 1 then breakAt = limit end
            mon.setCursorPos(x, curY)
            mon.write(text:sub(1, breakAt))
            text = text:sub(breakAt + 1)
            -- Skip leading spaces
            text = text:match("^%s*(.*)") or text
            curY = curY + 1
        end
    end
    return curY
end

-- ==================== GROUP LINE ====================

--- Нарисовать строку "key: values" с переносом если не влезает в одну строку
--- Возвращает следующую свободную строку y
function MonitorUtil.drawGroupLine(mon, x, y, key, values, groupColor, maxWidth)
    local prefix = key .. ": "
    local prefixLen = #prefix
    local display = type(values) == "table" and table.concat(values, ", ") or tostring(values)

    -- Пробуем уместить всё в одну строку
    local oneLine = prefix .. display
    if #oneLine <= maxWidth then
        MonitorUtil.drawText(mon, x, y, prefix, groupColor)
        MonitorUtil.drawText(mon, x + prefixLen, y, display, MonitorUtil.COLORS.text)
        return y + 1
    end

    -- Не влезло: помещаем prefix + сколько влезет display на первой строке
    local canFit = maxWidth - prefixLen
    if canFit < 1 then canFit = 1 end
    if canFit >= #display then
        MonitorUtil.drawText(mon, x, y, prefix, groupColor)
        MonitorUtil.drawText(mon, x + prefixLen, y, display, MonitorUtil.COLORS.text)
        return y + 1
    end

    -- Берём максимум display, стараясь разорвать по пробелу
    local take = canFit
    local sub = display:sub(1, take)
    local lastSpace = sub:match("^.*%s")
    if lastSpace then
        take = #lastSpace - 1
    end
    if take < 1 then take = canFit end

    local firstPart = display:sub(1, take)
    display = display:sub(take + 1)
    display = display:match("^%s*(.*)") or display

    MonitorUtil.drawText(mon, x, y, prefix .. firstPart, groupColor)

    -- Остаток display с переносом (на полную ширину, без отступа prefix)
    y = y + 1
    local remainingWidth = maxWidth
    if remainingWidth < 2 then remainingWidth = 2 end
    while #display > 0 do
        if #display <= remainingWidth then
            MonitorUtil.drawText(mon, x, y, display, MonitorUtil.COLORS.text)
            y = y + 1
            break
        else
            local take2 = remainingWidth
            local sub2 = display:sub(1, take2)
            local lastSpace2 = sub2:match("^.*%s")
            if lastSpace2 then
                take2 = #lastSpace2 - 1
            end
            if take2 < 1 then take2 = remainingWidth end
            MonitorUtil.drawText(mon, x, y, display:sub(1, take2), MonitorUtil.COLORS.text)
            display = display:sub(take2 + 1)
            display = display:match("^%s*(.*)") or display
            y = y + 1
        end
    end

    return y
end

-- Draw vertical divider line (for columns)
function MonitorUtil.drawVerticalDivider(mon, x, startY, endY)
    mon.setTextColor(colors.darkGray)
    for y = startY, endY do
        mon.setCursorPos(x, y)
        mon.write("|")
    end
end

-- Clear entire screen
function MonitorUtil.clearScreen(mon)
    mon.setBackgroundColor(COLORS.bg)
    mon.clear()
    mon.setCursorPos(1, 1)
end

-- ==================== BOX & PROGRESS ====================

-- Draw border box
function MonitorUtil.drawBox(mon, x, y, width, height, borderColor)
    local c = borderColor or colors.darkGray
    mon.setTextColor(c)
    -- Top
    mon.setCursorPos(x, y)
    mon.write(string.rep("-", width))
    -- Bottom
    mon.setCursorPos(x, y + height - 1)
    mon.write(string.rep("-", width))
    -- Sides
    for row = y + 1, y + height - 2 do
        mon.setCursorPos(x, row)
        mon.write("|")
        mon.setCursorPos(x + width - 1, row)
        mon.write("|")
    end
end

-- Draw animated progress bar (width in chars, progress 0.0-1.0)
-- Returns the end x position
function MonitorUtil.drawProgressBar(mon, x, y, width, progress, color)
    color = color or COLORS.success
    local filled = math.floor(progress * width)
    if filled < 0 then filled = 0 end
    if filled > width then filled = width end

    -- Background (dark)
    mon.setBackgroundColor(colors.gray)
    mon.setCursorPos(x, y)
    mon.write(string.rep(" ", width))

    -- Filled part
    if filled > 0 then
        mon.setBackgroundColor(color)
        mon.setCursorPos(x, y)
        mon.write(string.rep(" ", filled))
    end

    -- Percentage text overlay
    local pct = math.floor(progress * 100) .. "%"
    local pctX = x + math.floor((width - #pct) / 2)
    mon.setCursorPos(pctX, y)
    mon.setTextColor(colors.white)
    mon.write(pct)

    mon.setBackgroundColor(COLORS.bg)
    return x + width
end

-- ==================== TOUCH HANDLING ====================

-- Find which button was pressed based on touch coordinates.
-- Uses the button height for a rectangular vertical hit test (default 1).
function MonitorUtil.getPressedButton(buttons, touchX, touchY)
    for _, btn in ipairs(buttons) do
        local width = btn.width or #(btn.label or "")
        local height = btn.height or 1
        if touchX >= btn.x and touchX <= btn.x + width - 1
        and touchY >= btn.y and touchY <= btn.y + height - 1 then
            return btn
        end
    end
    return nil
end

-- ==================== PAGINATED VIEW ====================

-- Resolve the footer (back/prev/next buttons + page text position).
-- With a screenId the layout comes from hud.create_edit config;
-- without it the legacy hardcoded layout is used.
local function resolvePaginatedFooter(mon, screenId, currentPage, totalPages)
    if screenId then
        local HudUtil = require("screens/hud_util")
        local footer = HudUtil.getFooter(mon, currentPage + 1, totalPages)
        local prev, next
        if currentPage > 0 then prev = footer.prev end
        if currentPage < totalPages - 1 then next = footer.next end
        return footer.back, prev, next, footer.pageText, footer.pageX, footer.pageY, footer.pageColor, footer.pageBg
    end

    local w, h = mon.getSize()
    local backBtn = MonitorUtil.createButton(2, h - 1, 7, " [Back]", "back", colors.red)
    local prev, next
    if currentPage > 0 then
        prev = MonitorUtil.createButton(w - 19, h - 1, 7, " [<Prev]", "prev", colors.blue)
    end
    if currentPage < totalPages - 1 then
        next = MonitorUtil.createButton(w - 11, h - 1, 7, " [Next>]", "next", colors.blue)
    end
    local pageText = "Page " .. (currentPage + 1) .. "/" .. totalPages
    local pageX = math.floor((w - #pageText) / 2) + 1
    if pageX < 1 then pageX = 1 end
    local prevStart = w - 19
    if pageX + #pageText >= prevStart then
        pageX = prevStart - #pageText - 2
    end
    if pageX < 12 then pageX = 12 end
    return backBtn, prev, next, pageText, pageX, h - 1, COLORS.highlight, nil
end

--- Show a paginated list of items on the monitor.
--- @param mon table monitor
--- @param title string centered title
--- @param items table array of {key, value, color} in display order
--- @param side string monitor side for touch events
--- @param linesPerPage number|nil lines per page (excluding title and buttons). Default: h - 5
--- @param interactive boolean|nil if true (default) waits for touch input; if false just draws first page and returns
--- @param screenId string|nil when set, draws the hud.create_edit background and uses its footer coordinates
function MonitorUtil.paginatedView(mon, title, items, side, linesPerPage, interactive, screenId)
    if interactive == nil then interactive = true end
    local w, h = mon.getSize()
    local listX, listY, listW, listBg = 4, 4, w - 4, nil
    if screenId then
        local HudUtil = require("screens/hud_util")
        local area = HudUtil.getArea(mon)
        listX, listY, listW, listBg = area.x, area.y, area.w, area.bgColor
        if linesPerPage == nil then linesPerPage = area.h end
    end
    linesPerPage = linesPerPage or (h - 5) -- leave 2 rows for buttons (h-1 and h)
    if linesPerPage < 1 then linesPerPage = 1 end

    local currentPage = 0
    -- Pre-compute item lines: each item is an array of lines
    local itemLines = {}
    for idx, item in ipairs(items) do
        local prefix = item.key .. ": "
        local prefixLen = #prefix
        local display = type(item.value) == "table" and table.concat(item.value, ", ") or tostring(item.value)
        local lines = {}

        local oneLine = prefix .. display
        if #oneLine <= listW then
            table.insert(lines, {prefix = prefix, display = display, prefixLen = prefixLen, color = item.color})
        else
            -- Не влезло: помещаем максимум display на первой строке вместе с prefix
            local remaining = display
            local canFit = listW - prefixLen -- сколько символов display помещается на первой строке
            if canFit > 0 then
                local take = canFit
                if take > #remaining then take = #remaining end
                local sub = remaining:sub(1, take)
                local lastSpace = sub:match("^.*%s")
                if lastSpace then
                    take = #lastSpace - 1
                end
                if take < 1 then take = canFit end
                table.insert(lines, {prefix = prefix, display = remaining:sub(1, take), prefixLen = prefixLen, color = item.color})
                remaining = remaining:sub(take + 1)
                remaining = remaining:match("^%s*(.*)") or remaining
            else
                table.insert(lines, {prefix = prefix, display = "", prefixLen = prefixLen, color = item.color})
            end

            -- Остаток display на следующих строках (без отступа prefix)
            local lineWidth = listW
            if lineWidth < 2 then lineWidth = 2 end
            while #remaining > 0 do
                if #remaining <= lineWidth then
                    table.insert(lines, {prefix = "", display = remaining, prefixLen = 0, color = item.color})
                    remaining = ""
                else
                    local take = lineWidth
                    local sub = remaining:sub(1, take)
                    local lastSpace = sub:match("^.*%s")
                    if lastSpace then
                        take = #lastSpace - 1
                    end
                    if take < 1 then take = lineWidth end
                    table.insert(lines, {prefix = "", display = remaining:sub(1, take), prefixLen = 0, color = item.color})
                    remaining = remaining:sub(take + 1)
                    remaining = remaining:match("^%s*(.*)") or remaining
                end
            end
        end
        table.insert(itemLines, lines)
    end

    -- Back button (always on the left, compact width 7)
    local backBtn = MonitorUtil.createButton(2, h - 1, 7, " [Back]", "back", colors.red)

    -- Total pages
    local totalLines = 0
    for _, lines in ipairs(itemLines) do
        totalLines = totalLines + #lines
    end
    local totalPages = math.max(1, math.ceil(totalLines / linesPerPage))

    -- Если влезает на одну страницу — ограничиваем linesPerPage, чтобы drawnY не вылез за кнопки
    if totalPages <= 1 then
        linesPerPage = math.min(linesPerPage, totalLines)
    end

    -- Если нет данных — рисуем сообщение и (если interactive) ждём Back
    if totalLines == 0 then
        MonitorUtil.clearScreen(mon)
        if screenId then
            local HudUtil = require("screens/hud_util")
            HudUtil.drawBackground(mon, "create_edit")
            HudUtil.createEditTitle(mon, title)
            backBtn = HudUtil.getFooter(mon, 1, 1).back
        else
            MonitorUtil.drawTitle(mon, title, 2, listBg)
        end
        MonitorUtil.drawText(mon, listX, listY, "(no data to display)", COLORS.darkGray, listBg)
        if interactive then
            MonitorUtil.drawButton(mon, backBtn, false)
            pcall(os.pullEvent, "monitor_touch")
        end
        return
    end

    while true do
        MonitorUtil.clearScreen(mon)
        if screenId then
            local HudUtil = require("screens/hud_util")
            HudUtil.drawBackground(mon, "create_edit")
            HudUtil.createEditTitle(mon, title)
        else
            MonitorUtil.drawTitle(mon, title, 2, listBg)
        end

        -- Draw items for current page
        local startLine = currentPage * linesPerPage + 1
        local endLine = math.min(startLine + linesPerPage - 1, totalLines)
        local lineIdx = 1
        local drawnY = listY
        for _, lines in ipairs(itemLines) do
            for _, line in ipairs(lines) do
                if lineIdx >= startLine and lineIdx <= endLine then
                    if line.prefix ~= "" then
                        MonitorUtil.drawText(mon, listX, drawnY, line.prefix, line.color, listBg)
                    end
                    if line.display ~= "" then
                        MonitorUtil.drawText(mon, listX + line.prefixLen, drawnY, line.display, COLORS.text, listBg)
                    end
                    drawnY = drawnY + 1
                end
                lineIdx = lineIdx + 1
            end
        end

        -- Page indicator + Back/Prev/Next from hud config (screenId) or legacy layout
        local backBtn, prevBtn, nextBtn, pageText, pageX, pageY, pageColor, pageBg =
            resolvePaginatedFooter(mon, screenId, currentPage, totalPages)
        MonitorUtil.drawText(mon, pageX, pageY, pageText, pageColor, pageBg)
        if prevBtn then
            MonitorUtil.drawButton(mon, prevBtn, false)
        end
        if nextBtn then
            MonitorUtil.drawButton(mon, nextBtn, false)
        end
        MonitorUtil.drawButton(mon, backBtn, false)

        -- If not interactive, draw first page and return immediately
        if not interactive then return end

        -- Wait for touch
        local ok, event, touchedSide, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and touchedSide == side then
            local allButtons = { backBtn }
            if prevBtn then table.insert(allButtons, prevBtn) end
            if nextBtn then table.insert(allButtons, nextBtn) end

            local pressed = MonitorUtil.getPressedButton(allButtons, tx, ty)
            if pressed then
                if pressed.action == "prev" then
                    currentPage = currentPage - 1
                elseif pressed.action == "next" then
                    currentPage = currentPage + 1
                elseif pressed.action == "back" then
                    return
                end
            end
        end
    end
end

-- ==================== DIALOGS ====================
-- Confirmations are handled through chat answers (waitForYesNo), not via
-- monitor buttons. No on-monitor yes/no dialog is provided.

return MonitorUtil