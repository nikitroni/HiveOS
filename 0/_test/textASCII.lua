local m0 = peripheral.wrap("monitor_1")
local m1 = peripheral.wrap("monitor_0")
local m2 = peripheral.wrap("monitor_2")

if not m0 or not m1 or not m2 then
    print("Error: Check monitor connections!")
    return
end

local function drawUltraTight(mon, startChar, endChar)
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local w, h = mon.getSize()
    local x, y = 1, 1 -- Start from the very corner
    
    for c = startChar, endChar do
        if c > 255 then break end
        
        -- Block: 3 (ID) + 4 (symbols) = 7 cells
        -- x + 8 means 1 empty space between blocks
        if x + 7 > w then
            x = 1
            y = y + 2 -- Keep vertical gap
        end
        
        if y > h then break end

        -- Draw ID
        mon.setCursorPos(x, y)
        mon.setTextColor(colors.gray)
        mon.write(string.format("%03d", c))

        -- Draw symbols (no space after ID)
        mon.setCursorPos(x + 3, y)
        mon.setTextColor(colors.white)
        local s = string.char(c)
        mon.write(s:rep(4))

        x = x + 8 -- Tight horizontal step
    end
end

print("Redrawing with ultra tight columns...")
drawUltraTight(m0, 0, 85)
drawUltraTight(m1, 86, 171)
drawUltraTight(m2, 172, 255)
print("Done!")