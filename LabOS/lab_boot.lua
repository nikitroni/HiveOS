-- lab_boot.lua
-- LabOS wait screen: the HUD_Lab_Boot.nfp background is drawn on the main monitor,
-- on top - a smoothly animated colored loading bar.
-- Bar coordinates (from the layout): x=20, y=16, w=33, h=9.
-- Percentage digits are NOT displayed - only the scale.
-- Additionally: a fun "flasks" animation - areas on the background filled
-- with random bright colors (coordinates are set in the FLASKS table below).

local BOOT_FILE = "HUD_Lab_Boot.nfp"

local BAR = {
    x = 20,
    y = 16,
    w = 33,
    h = 9,
}

-- Flask areas for random bright fill (fun animation).
-- Flask 1 (left): lower vessel + neck; flask 2 (right): same.
-- Each cell in these areas changes color every frame.
local FLASKS = {
    -- Flask 1 (left): vessel
    { x = 5,  y = 13, w = 7, h = 5 },
    -- Flask 1 (left): neck
    { x = 7,  y = 10, w = 3, h = 3 },
    -- Flask 2 (right): vessel
    { x = 61, y = 13, w = 7, h = 5 },
    -- Flask 2 (right): neck
    { x = 63, y = 10, w = 3, h = 3 },
}

-- Palette of bright colors for the flasks
local FLASK_COLORS = {
    colors.red,
    colors.orange,
    colors.yellow,
    colors.green,
    colors.cyan,
    colors.blue,
    colors.purple,
    colors.pink,
    colors.magenta,
}

local preparedMonitors = {}

local function isPrepared(mon)
    return preparedMonitors[mon] == true
end

local function markPrepared(mon)
    preparedMonitors[mon] = true
end

-- ==================== FLASK ANIMATION (slow) ====================
-- Set of colors for all flask cells, refreshed once every
-- FLASK_INTERVAL seconds. Between refreshes the colors are stable -
-- the animation turns out smooth and does not flicker.

local FLASK_INTERVAL = 0.4   -- every 0.4 s the color set changes

local flaskCellColors = {}   -- [index] = color
local flaskColorsTime = 0

local function ensureFlaskColors()
    local now = os.clock()
    if now - flaskColorsTime >= FLASK_INTERVAL then
        -- recalculate the total number of cells
        local total = 0
        for _, area in ipairs(FLASKS) do
            total = total + area.w * area.h
        end
        flaskCellColors = {}
        for i = 1, total do
            flaskCellColors[i] = FLASK_COLORS[math.random(#FLASK_COLORS)]
        end
        flaskColorsTime = now
    end
end

-- Fill the flask areas: colors stable for the interval.
local function drawFlaskAnimation(mon)
    if #FLASKS == 0 then return end
    ensureFlaskColors()
    local idx = 0
    for _, area in ipairs(FLASKS) do
        for row = 0, area.h - 1 do
            for col = 0, area.w - 1 do
                idx = idx + 1
                local color = flaskCellColors[idx]
                mon.setCursorPos(area.x + col, area.y + row)
                mon.setBackgroundColor(color)
                mon.setTextColor(color)
                mon.write(" ")
            end
        end
    end
end

-- Full clear and background draw once per monitor (before the bar animation)
function prepareScreen(mon)
    local bg = paintutils.loadImage(BOOT_FILE)
    if not bg then
        error("HUD_Lab_Boot.nfp not found")
    end
    mon.setTextScale(1.0)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local oldTerm = term.redirect(mon)
    paintutils.drawImage(bg, 1, 1)
    term.redirect(oldTerm)
    markPrepared(mon)
end

-- Draws the progress bar (bar area only).
-- percent: 0..100
local function drawBar(mon, percent)
    local total = BAR.w * BAR.h
    local fill = math.floor(percent / 100 * total + 0.5)
    if fill < 0 then fill = 0 end
    if fill > total then fill = total end

    for row = 0, BAR.h - 1 do
        for col = 0, BAR.w - 1 do
            local i = row * BAR.w + col
            mon.setCursorPos(BAR.x + col, BAR.y + row)
            if i < fill then
                mon.setBackgroundColor(colors.orange)
            else
                mon.setBackgroundColor(colors.lightGray)
            end
            mon.setTextColor(colors.white)
            mon.write(" ")
        end
    end
end

-- One frame of the wait animation: only the bar (the background is already drawn by prepareScreen).
-- Smooth scale 0% -> 100% -> 0%.
function drawWaitFrame(mon)
    local ok = pcall(function()
        if not isPrepared(mon) then
            prepareScreen(mon)
        end
        local p = (os.clock() % 4) / 4
        local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
        drawBar(mon, math.floor(wave * 100))
        drawFlaskAnimation(mon)
    end)
    return ok
end

-- Startup animation of fixed duration
function show(mon, duration)
    duration = duration or 4
    prepareScreen(mon)
    local start = os.clock()
    while os.clock() - start < duration do
        local p = (os.clock() - start) / duration
        local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
        drawBar(mon, math.floor(wave * 100))
        drawFlaskAnimation(mon)
        sleep(0.05)
    end
end

return {
    show = show,
    prepareScreen = prepareScreen,
    drawWaitFrame = drawWaitFrame,
}