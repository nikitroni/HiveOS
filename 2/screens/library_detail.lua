-- library_detail.lua
-- HeartOS "Library" detail screen (Phase 4): shows every level of one gene.
-- Gene data (name, header symbol, levels with sym/color) comes from
-- hud.library.genes in heart_config.lua.
-- Scale (hud.library.detail.scale, default 4) is applied ONLY in this inner
-- screen and restored to hud.text_scale on exit. If the monitor grid at the
-- requested scale cannot fit the content, the scale steps down so the gene
-- symbol, its levels and the bottom hint always stay readable and on-screen.
-- Any monitor tap returns to library_menu.
--
-- Layout (per spec):
--   row 1    : gene name, centered
--   row 2    : centered gene symbol (gene.header)
--   rows 3+  : the gene levels, one per row, NO blank rows between them
--   last row : "Tap to return"

local MonitorUtil = require("screens/monitor_util")
local ChatUtil = require("chat_util")

local LibraryDetail = {}

local DEFAULT_SCALE = 4
local MIN_SCALE = 1

--- Resolve a config color (string name or number) to a colors.* value.
--- @param value any
--- @param default number
--- @return number
local function toColor(value, default)
    if value == nil then return default end
    if type(value) == "number" then return value end
    return colors[value] or default
end

--- Center text horizontally on the monitor.
--- @return number x starting column (>= 1)
local function centerX(w, text)
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    return x
end

function LibraryDetail.run(mon, heartConfig, geneId)
    local ok, err = pcall(function()
        local library = (heartConfig.hud and heartConfig.hud.library) or {}
        local detailCfg = library.detail or {}
        local listCfg = detailCfg.list or {}
        local gene = (library.genes or {})[geneId]

        local oldScale = (heartConfig.hud and heartConfig.hud.text_scale) or 1
        local requested = detailCfg.scale or DEFAULT_SCALE
        local listText = toColor(listCfg.textColor, colors.white)
        local listBg = toColor(listCfg.bgColor, colors.black)

        -- Levels of this gene (may be 0 if the gene is missing).
        local levels = {}
        if gene and type(gene.levels) == "table" then
            for _, levelKey in ipairs(gene.order or {}) do
                local level = gene.levels[levelKey]
                if level then
                    table.insert(levels, {
                        key = levelKey,
                        sym = level.sym,
                        color = toColor(level.color, colors.white),
                    })
                end
            end
        end

        -- Rows needed: 1 blank + 1 symbol + #levels + 1 hint.
        local needed = 3 + #levels
        local scale = requested
        if scale > MIN_SCALE then
            while scale > MIN_SCALE do
                mon.setTextScale(scale)
                mon.setBackgroundColor(colors.black)
                mon.clear()
                local _, hs = mon.getSize()
                if hs >= needed then break end
                scale = scale - 1
            end
        end
        mon.setTextScale(scale)
        mon.setBackgroundColor(colors.black)
        mon.clear()
        local w, h = mon.getSize()

        local function waitForTap()
            pcall(os.pullEvent, "monitor_touch")
        end

        -- Missing gene: show a sane error screen, then return to the menu.
        if not gene or type(gene.levels) ~= "table" then
            local line = 2
            if h < 3 then line = 1 end
            local label = geneId or "gene"
            if #label > w then label = label:sub(1, w) end
            local msg = "Gene data not found."
            MonitorUtil.drawText(mon, 2, line, label, colors.white, colors.black)
            MonitorUtil.drawText(mon, 2, line + 1, msg, colors.red, colors.black)
            if h >= 3 then
                MonitorUtil.drawText(mon, 2, h, "Tap to return", colors.gray, colors.black)
            end
            if not ChatUtil.isAvailable() then ChatUtil.init(nil) end
            ChatUtil.sendError("Library: gene data not found (" .. tostring(geneId) .. ").")
            waitForTap()
            mon.setTextScale(oldScale)
            return
        end

        -- Row 1: centered gene name.
        local nameText = gene.name or tostring(geneId)
        if #nameText > w then nameText = nameText:sub(1, w) end
        MonitorUtil.drawText(mon, centerX(w, nameText), 1, nameText, colors.yellow, colors.black)

        -- Row 2: centered gene symbol.
        local symbol = gene.header
        if symbol == nil or #symbol == 0 then
            symbol = gene.name or tostring(geneId)
        end
        if #symbol > w then symbol = symbol:sub(1, w) end
        MonitorUtil.drawText(mon, centerX(w, symbol), 2, symbol, colors.yellow, colors.black)

        -- Rows 3..: the levels, one per row, NO gaps (spacing = 1).
        local x = listCfg.x or 3
        local y = listCfg.y or 3
        if y < 3 then y = 3 end
        -- Keep the whole list above the bottom hint row.
        if y + #levels > h then
            y = math.max(3, h - #levels)
        end
        for _, lv in ipairs(levels) do
            local keyText = tostring(lv.key)
            local avail = w - (x + 2)
            if avail < 1 then avail = 1 end
            if #keyText > avail then keyText = keyText:sub(1, avail) end
            MonitorUtil.drawText(mon, x, y, lv.sym, lv.color, colors.black)
            MonitorUtil.drawText(mon, x + 2, y, keyText, listText, listBg)
            y = y + 1
        end

        -- Bottom row: tap-to-return hint.
        if h >= 3 then
            local hint = "Tap to return"
            if #hint > w then hint = hint:sub(1, w) end
            MonitorUtil.drawText(mon, centerX(w, hint), h, hint, colors.gray, colors.black)
        end

        waitForTap()
        mon.setTextScale(oldScale)
    end)

    if not ok then
        -- Hard guarantee: never let the inner screen kill HeartOS. Restore the
        -- scale and surface the error in chat so it can be fixed.
        if mon.setTextScale then
            mon.setTextScale((heartConfig.hud and heartConfig.hud.text_scale) or 1)
        end
        if not ChatUtil.isAvailable() then ChatUtil.init(nil) end
        ChatUtil.sendError("Library detail error: " .. tostring(err))
    end
end

return LibraryDetail