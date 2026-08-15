-- test_barrel_via_reader_deep.lua
-- Рекурсивно выводит все данные, полученные от block_reader_19, включая вложенные таблицы.
-- Это позволит увидеть, где именно хранятся гены пчёл (в custom_data, neoforge:attachments и т.д.).

local logsDir = "logs"
if not fs.exists(logsDir) then
    fs.makeDir(logsDir)
end

local reportFile = logsDir .. "/barrel_via_reader_deep.txt"

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
    log("=== BARREL VIA READER DEEP TEST ===")
    log("Date: " .. os.date())
    log("")
end

clearLog()

local reader = peripheral.wrap("block_reader_19")
if not reader then
    log("ERROR: block_reader_19 not found")
    return
end

local function dumpTable(t, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    if type(t) ~= "table" then
        log(prefix .. tostring(t))
        return
    end
    for k, v in pairs(t) do
        if type(v) == "table" then
            log(prefix .. tostring(k) .. " = table:")
            dumpTable(v, indent + 1)
        else
            log(prefix .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

local data = reader.getBlockData()
if not data then
    log("getBlockData returned nil")
    return
end

log("Full data dump (recursive):")
dumpTable(data)

log("\n=== END OF TEST ===")
print("Test complete. Report saved to " .. reportFile)