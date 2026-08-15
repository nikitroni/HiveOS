-- test_incubator1.lua
-- Исследует productivebees:incubator_1: методы, содержимое, слоты.
-- Логи сохраняются в папку logs.

local logsDir = "logs"
if not fs.exists(logsDir) then
    fs.makeDir(logsDir)
end

local reportFile = logsDir .. "/incubator1_test.txt"

local function log(...)
    local file = fs.open(reportFile, "a")
    if file then
        for i = 1, select('#', ...) do
            file.write(tostring(select(i, ...)) .. " ")
        end
        file.write("\n")
        file.close()
    end
end

local function clearLog()
    local f = fs.open(reportFile, "w")
    if f then f.close() end
    log("=== INCUBATOR 1 TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

local incubator = peripheral.wrap("productivebees:incubator_1")
if not incubator then
    log("ERROR: incubator_1 not found")
    return
end

-- Список методов
local methods = {}
for k, v in pairs(incubator) do
    if type(v) == "function" then
        table.insert(methods, k)
    end
end
log("Available methods: " .. table.concat(methods, ", "))

-- Размер инвентаря (если есть метод size)
if incubator.size then
    local size = incubator.size()
    log("Inventory size: " .. size)
end

-- Содержимое через list()
local items = incubator.list and incubator.list() or {}
log("Items in incubator (list()):")
for slot, item in pairs(items) do
    log("  Slot " .. slot .. ": " .. (item.name or "?") .. " x" .. (item.count or 0))
end

-- Детальная информация по первым 10 слотам
log("Detailed item info (getItemDetail):")
for slot = 1, 3 do
    local detail = incubator.getItemDetail and incubator.getItemDetail(slot)
    if detail then
        log("  Slot " .. slot .. ": " .. detail.name .. " x" .. detail.count)
        if detail.components then
            log("    components: " .. textutils.serialize(detail.components))
        end
    end
end

log("\n=== END OF TEST ===")
print("Test complete. Report saved to " .. reportFile)