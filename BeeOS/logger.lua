-- logger.lua
-- Module for logging to a file (not to a monitor and not to chat - to avoid
-- disturbing the screens and losing data). File: _logs/terminal.log in folder 0/

local Logger = {}   -- <-- DON'T FORGET: module declaration!

local LOG_DIR = "_logs"
local LOG_FILE = "_logs/terminal.log"

local MAX_LOG_SIZE = 50000
local MIN_FREE_SPACE = 5000

local spaceWarned = false

local function ensureLogDir()
    if not fs.exists(LOG_DIR) then
        pcall(fs.makeDir, LOG_DIR)
    end
end

-- File size: fs.getSize, then fs.attributes().size, then a read fallback.
local function getFileSize(path)
    local ok, size = pcall(fs.getSize, path)
    if ok and type(size) == "number" then return size end
    local okAttr, attr = pcall(fs.attributes, path)
    if okAttr and type(attr) == "table" and type(attr.size) == "number" then
        return attr.size
    end
    local f = fs.open(path, "r")
    if not f then return 0 end
    local content = f.readAll()
    f.close()
    if type(content) == "string" then return #content end
    return 0
end

-- One-time cleanup at module start: remove the log when it exceeds the cap.
ensureLogDir()
if getFileSize(LOG_FILE) > MAX_LOG_SIZE then
    pcall(fs.delete, LOG_FILE)
end

-- One-time low-space warning (not printed: the logger may run in async
-- threads and must not touch term/monitors).
local function warnLowSpace()
    if spaceWarned then return end
    spaceWarned = true
    pcall(function()
        local ok, ChatNotify = pcall(require, "chat_notify")
        if ok and ChatNotify and ChatNotify.sendError then
            ChatNotify.sendError("Low disk space, log write skipped")
        end
    end)
end

function Logger.log(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")

    local okSpace, space = pcall(fs.getFreeSpace, "/")
    if okSpace and type(space) == "number" and space < MIN_FREE_SPACE then
        warnLowSpace()
        return
    end
    spaceWarned = false

    ensureLogDir()
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(line)
        f.close()
    end
    -- Do NOT duplicate to the computer console (print uses term, and the log is
    -- called from async threads and must not touch monitors/term)
end

return Logger