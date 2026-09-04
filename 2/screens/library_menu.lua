-- library_menu.lua
-- HeartOS "Library" screen (Phase 4): gene selection menu.
-- Background, title and buttons come from hud.library.menu in heart_config.lua.
-- Buttons drive the LibraryDetail screen (see library_detail.lua).

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ChatUtil = require("chat_util")

local LibraryMenu = {}

-- Draw the nfp background from hud.library.menu.background.
-- Falls back to a plain black screen when the image is missing.
local function drawBackground(mon, heartConfig)
    local menu = (heartConfig.hud and heartConfig.hud.library and heartConfig.hud.library.menu) or {}
    local path = menu.background
    if not path or #path == 0 then return end
    local ok, img = pcall(paintutils.loadImage, path)
    if not ok or not img then return end
    local oldTerm = term.redirect(mon)
    pcall(paintutils.drawImage, img, 1, 1)
    term.redirect(oldTerm)
end

-- Draw a single menu button from the config spec and return the hit-test table.
local function drawButton(mon, spec)
    if type(spec) ~= "table" then return nil end
    local btn = MonitorUtil.createButton(
        spec.x, spec.y, spec.w or #(spec.label or ""), spec.label or "",
        spec.id or spec.action or spec.label,
        spec.bgColor and HudUtil.color(spec.bgColor) or colors.gray, spec.h or 1)
    if spec.textColor then btn.textColor = HudUtil.color(spec.textColor) end
    MonitorUtil.drawButton(mon, btn, false)
    return btn
end

function LibraryMenu.run(mon, heartConfig)
    local menu = (heartConfig.hud and heartConfig.hud.library and heartConfig.hud.library.menu) or {}
    local title = menu.title or {}

    while true do
        MonitorUtil.clearScreen(mon)
        drawBackground(mon, heartConfig)

        if type(title) == "table" then
            MonitorUtil.drawText(mon, title.x, title.y, title.text or "",
                HudUtil.color(title.textColor or "yellow"),
                title.bgColor and HudUtil.color(title.bgColor) or colors.gray)
        end

        local buttons = {}
        for _, spec in ipairs(menu.buttons or {}) do
            local btn = drawButton(mon, spec)
            if btn then table.insert(buttons, btn) end
        end

        local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
        if ok and side == heartConfig.main_monitor then
            local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
            if pressed then
                if pressed.action == "back" then
                    return
                else
                    local LibraryDetail = require("screens/library_detail")
                    local okRun, errRun = pcall(LibraryDetail.run, mon, heartConfig, pressed.action)
                    if not okRun then
                        -- Restore the scale if the detail screen crashed mid-way,
                        -- then report the error so the menu keeps working.
                        mon.setTextScale((heartConfig.hud and heartConfig.hud.text_scale) or 1)
                        if not ChatUtil.isAvailable() then ChatUtil.init(nil) end
                        ChatUtil.sendError("Library detail error: " .. tostring(errRun))
                    end
                end
            end
        end
    end
end

return LibraryMenu