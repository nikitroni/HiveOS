-- test_me_interface.lua
-- Выводит содержимое всех слотов ME интерфейса в файл me_interface_dump.txt

local interfaceName = "ae2:interface_0"  -- замените на реальное имя вашего интерфейса
local logFile = "me_interface_dump.txt"


local function log(...)
    local file = fs.open(logFile, "a")
    if file then
        for i = 1, select('#', ...) do
            file.write(tostring(select(i, ...)) .. " ")
        end
        file.write("\n")
        file.close()
    end
end

-- Очищаем лог-файл перед записью
local f = fs.open(logFile, "w")
if f then f.close() end

log("=== ME INTERFACE INVENTORY DUMP ===")
log("Date: " .. os.date())
log("")

local interface = peripheral.wrap(interfaceName)
if not interface then
    log("ERROR: Interface '" .. interfaceName .. "' not found!")
    print("Error: interface not found")
    return
end

-- Получаем список доступных методов (для информации)
local methods = {}
for k, v in pairs(interface) do
    if type(v) == "function" then
        table.insert(methods, k)
    end
end
log("Available methods: " .. table.concat(methods, ", "))

-- Получаем размер инвентаря
local size = interface.size()
log("Inventory size: " .. size)

-- Перебираем все слоты
for slot = 1, size do
    local item = interface.getItemDetail(slot)
    if item then
        log("Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
        if item.components then
            log("  components: " .. textutils.serialize(item.components))
        else
            log("  no components")
        end
    else
        log("Slot " .. slot .. ": empty")
    end
end

log("=== END OF DUMP ===")
print("Dump complete. See " .. logFile)