-- logger.lua
-- Модуль для логирования в файл (не на монитор и не в чат - чтобы не мешать
-- работе экранов и не терять данные). Файл: _logs/terminal.log в папке 0/

local Logger = {}   -- <-- НЕ ЗАБЫТЬ: объявление модуля!

local LOG_DIR = "_logs"
local LOG_FILE = "_logs/terminal.log"

local function ensureLogDir()
    if not fs.exists(LOG_DIR) then
        pcall(fs.makeDir, LOG_DIR)
    end
end

function Logger.log(...)
    ensureLogDir()
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(line)
        f.close()
    end
    -- В консоль компьютера НЕ дублируем (print использует term, а лог вызывается
    -- в т.ч. из async-потоков и не должен трогать мониторы/терм)
end

return Logger