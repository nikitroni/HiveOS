-- test_breeding_chamber.lua
-- Исследует камеру разведения: методы, слоты, содержимое.
-- Логи сохраняются в папку logs.

local chamberName = "productivebees:breeding_chamber_1"
local logsDir = "logs"
if not fs.exists(logsDir) then fs.makeDir(logsDir) end
local reportFile = logsDir .. "/breeding_chamber_test.txt"

local function log(...)
    local f = fs.open(reportFile, "a")
    if f then
        for i = 1, select('#', ...) do
            f.write(tostring(select(i, ...)) .. " ")
        end
        f.write("\n")
        f.close()
    end
end

local function clearLog()
    local f = fs.open(reportFile, "w")
    if f then f.close() end
    log("=== BREEDING CHAMBER TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

local chamber = peripheral.wrap(chamberName)
if not chamber then
    log("ERROR: " .. chamberName .. " not found!")
    return
end

log("Chamber found. Available methods:")
local methods = {}
for k, v in pairs(chamber) do
    if type(v) == "function" then
        table.insert(methods, k)
    end
end
table.sort(methods)
log("  " .. table.concat(methods, ", "))
log("")

-- Получаем размер инвентаря (если есть метод size)
if chamber.size then
    local size = chamber.size()
    log("Inventory size: " .. size)
else
    log("No size method, trying list() to guess...")
end

-- Пытаемся получить список предметов через list()
local items = {}
if chamber.list then
    items = chamber.list() or {}
else
    log("No list() method.")
end

log("Items in chamber (list()):")
for slot, item in pairs(items) do
    log("  Slot " .. slot .. ": " .. (item.name or "?") .. " x" .. (item.count or 0))
end

-- Детальная информация по слотам (если есть getItemDetail)
if chamber.getItemDetail then
    log("\nDetailed item info (getItemDetail):")
    for slot = 1, (chamber.size and chamber.size() or 20) do
        local detail = chamber.getItemDetail(slot)
        if detail then
            log("  Slot " .. slot .. ": " .. detail.name .. " x" .. detail.count)
            if detail.components then
                log("    components:")
                for compName, compData in pairs(detail.components) do
                    if type(compData) == "table" then
                        log("      " .. compName .. " = table")
                        -- Если это gene_group, выведем подробнее
                        if compName == "productivebees:gene_group" then
                            for k, v in pairs(compData) do
                                log("        " .. k .. " = " .. tostring(v))
                            end
                        end
                    else
                        log("      " .. compName .. " = " .. tostring(compData))
                    end
                end
            else
                log("    no components")
            end
        end
    end
else
    log("No getItemDetail method.")
end

log("\n=== END OF TEST ===")
print("Test complete. Report saved to " .. reportFile)