local relay = peripheral.wrap("redstone_relay_2")
if not relay then error("Relay not found") end

local sides = {"top", "bottom", "left", "right", "front", "back"}
for _, side in ipairs(sides) do
    print("Testing side: " .. side)
    relay.setOutput(side, true)
    sleep(2)
    relay.setOutput(side, false)
    sleep(0.5)
end
print("Done")