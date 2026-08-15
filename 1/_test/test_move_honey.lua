-- test_move_honey.lua
-- Проверяет наличие honey_treat в ME интерфейсе и перемещает 3 штуки в barrel_1.

-- Укажите здесь реальные имена ваших периферий
local interfaceName = "ae2:interface_0"   -- замените на ваше имя
local barrelName = "minecraft:barrel_1"

local interface = peripheral.wrap(interfaceName)
local barrel = peripheral.wrap(barrelName)

if not interface then
    print("ERROR: Interface not found!")
    return
end
if not barrel then
    print("ERROR: Barrel not found!")
    return
end

print("Scanning interface for honey_treat...")

local honeySlot = nil
local honeyCount = 0
for slot = 1, interface.size() do
    local item = interface.getItemDetail(slot)
    if item and item.name == "productivebees:honey_treat" then
        honeySlot = slot
        honeyCount = item.count
        break
    end
end

if not honeySlot then
    print("No honey_treat found in interface.")
    return
end

print(string.format("Found %d honey_treat in slot %d.", honeyCount, honeySlot))

local toMove = math.min(honeyCount, 3)
local moved = interface.pushItems(barrelName, honeySlot, toMove)

if moved > 0 then
    print(string.format("Successfully moved %d honey_treat to barrel.", moved))
else
    print("Failed to move honey_treat (pushItems returned 0).")
end