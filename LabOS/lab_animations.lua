-- lab_animations.lua
-- Functions for animations on the laboratory monitor.
-- Each function draws only in the given area without clearing the rest of the screen.

local Anim = {}

-- ==================== HELPERS ====================
-- Check that the monitor exists
local function checkMonitor(mon)
    if not mon then
        error("Monitor is nil")
    end
end

-- ==================== WIN ANIMATION ====================
-- Matrix of the letters WIN (as in the provided code)
local winLogo = {
    "                    ",
    "  w   w wwwww  w   w",
    "  w   w   w    ww  w",
    "  w   w   w    w w w",
    "  w w w   w    w  ww",
    "  w w w   w    w   w",
    "  w w w   w    w   w",
    "   w w  wwwww  w   w"
}
local winColors = {
    colors.red, colors.orange, colors.yellow, colors.green,
    colors.lightBlue, colors.blue, colors.purple, colors.magenta
}
-- Draws the WIN logo at (startX, startY) with shimmering colors.
-- frame increases every frame.
function Anim.drawWin(monitor, startX, startY, frame)
    checkMonitor(monitor)
    for row = 1, #winLogo do
        local line = winLogo[row]
        for col = 1, #line do
            local char = line:sub(col, col)
            if char ~= " " then
                local colorIdx = (col + frame) % #winColors + 1
                monitor.setCursorPos(startX + col - 1, startY + row - 1)
                monitor.setTextColor(winColors[colorIdx])
                monitor.write("w")  -- character "w" as in the original
            end
        end
    end
end

-- ==================== WAIT ANIMATION ====================
local waitLogo = {
    "                       ",
    " x   x  xx  xxxxx xxxxx",
    " x   x x  x   x     x  ",
    " x   x x  x   x     x  ",
    " x x x xxxx   x     x  ",
    " xx xx x  x   x     x  ",
    " x   x x  x xxxxx   x  "
}
local waitFade = {colors.white, colors.lightGray, colors.gray, colors.black}
-- Draws the WAIT logo with a fade effect.
-- frame determines brightness: the larger frame, the darker (cyclically).
function Anim.drawWait(monitor, startX, startY, frame)
    checkMonitor(monitor)
    local colorIdx = (math.floor(frame / 4)) % #waitFade + 1
    local currentColor = waitFade[colorIdx]
    for row = 1, #waitLogo do
        local line = waitLogo[row]
        for col = 1, #line do
            local char = line:sub(col, col)
            monitor.setCursorPos(startX + col - 1, startY + row - 1)
            if char == "x" then
                monitor.setTextColor(currentColor)
                monitor.write("x")
            else
                monitor.write(" ")
            end
        end
    end
end

-- ==================== DNA ANIMATION ====================
local dnaPattern = {
    {cL="x",  cR=" ",  conn=" ", isX=true},
    {cL="/",  cR="\\", conn=" ", isX=false},
    {cL="|",  cR="|",  conn="-", isX=false},
    {cL="\\", cR="/",  conn=" ", isX=false},
}
-- Draws one DNA strand.
-- startX, startY - coordinates of the top-left corner of the area (it occupies 3 characters wide and height rows).
-- height - height of the strand (number of rows). In your case 10.
-- frame - frame number for the animation (determines the shift).
-- inverted - if true, swaps the red/blue colors.
function Anim.drawDNA(monitor, startX, startY, height, frame, inverted)
    checkMonitor(monitor)
    monitor.setBackgroundColor(colors.black)
    for i = 1, height do
        local y = startY + i - 1
        local idx = (i + frame - 1) % 4 + 1
        local line = dnaPattern[idx]

        local phase = math.floor((i + frame - 1) / 4) % 2
        if inverted then
            phase = (phase == 0) and 1 or 0
        end

        local colL = (phase == 0) and colors.red or colors.blue
        local colR = (phase == 0) and colors.blue or colors.red

        if line.isX then
            monitor.setCursorPos(startX + 1, y)
            monitor.setTextColor(colors.white)
            monitor.write("X")   -- replaced "x" with "X" for contrast
        else
            monitor.setCursorPos(startX, y)
            monitor.setTextColor(colL)
            monitor.write(line.cL)   -- "/", "\", "|"

            monitor.setCursorPos(startX + 2, y)
            monitor.setTextColor(colR)
            monitor.write(line.cR)   -- "\", "/", "|"

            if line.conn ~= " " then
                monitor.setCursorPos(startX + 1, y)
                monitor.setTextColor(colors.white)
                monitor.write(line.conn)   -- "-"
            end
        end
    end
end

return Anim