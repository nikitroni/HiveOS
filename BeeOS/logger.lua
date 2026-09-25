-- logger.lua
-- Module for logging to a file (not to a monitor and not to chat - to avoid
-- disturbing the screens and losing data). File: _logs/terminal.log in folder 0/

local Logger = {}   -- <-- DON'T FORGET: module declaration!

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
    -- Do NOT duplicate to the computer console (print uses term, and the log is
    -- called from async threads and must not touch monitors/term)
end

return Logger