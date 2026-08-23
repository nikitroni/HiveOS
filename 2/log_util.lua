-- log_util.lua
-- Logger for errors and events into a text file
-- Format: [TIMESTAMP] LEVEL: message
-- Path: logs/error.log (auto-creates logs/ folder)

local LogUtil = {}

--- Get full path to log file
local function getLogPath()
    return "logs/error.log"
end

--- Initialize: create logs/ folder if it doesn't exist
function LogUtil.init()
    if not fs.exists("logs") then
        fs.makeDir("logs")
    end
end

--- Get current timestamp
local function timestamp()
    local t = os.time()
    local days = math.floor(t / 86400)
    local hours = math.floor((t % 86400) / 3600)
    local minutes = math.floor((t % 3600) / 60)
    local seconds = t % 60
    return string.format("[%dd %02d:%02d:%02d]", days, hours, minutes, seconds)
end

--- Write a message of any level to the log file
--- @param level string "ERROR", "WARN", "INFO", "DEBUG"
--- @param message string log text
--- @param ... any additional args (will be serialized)
function LogUtil.log(level, message, ...)
    LogUtil.init()

    local fullMessage = timestamp() .. " " .. level .. ": " .. tostring(message)

    local args = {...}
    if #args > 0 then
        for i = 1, #args do
            fullMessage = fullMessage .. " " .. tostring(args[i])
        end
    end

    local f = io.open(getLogPath(), "a")
    if f then
        f:write(fullMessage .. "\n")
        f:close()
    end

    print(fullMessage)
end

--- Log an error
--- @param message string error description
function LogUtil.error(message, ...)
    LogUtil.log("ERROR", message, ...)
end

--- Log a warning
--- @param message string warning description
function LogUtil.warn(message, ...)
    LogUtil.log("WARN", message, ...)
end

--- Log an info message
--- @param message string text
function LogUtil.info(message, ...)
    LogUtil.log("INFO", message, ...)
end

--- Log a debug message
--- @param message string text
function LogUtil.debug(message, ...)
    LogUtil.log("DEBUG", message, ...)
end

--- Clear the log file
function LogUtil.clearLog()
    LogUtil.init()
    local f = io.open(getLogPath(), "w")
    if f then
        f:close()
    end
end

--- Read the entire log
--- @return string|nil, string|nil content or error
function LogUtil.readLog()
    LogUtil.init()
    local f = io.open(getLogPath(), "r")
    if f then
        local content = f:read("*a")
        f:close()
        return content, nil
    end
    return nil, "Log not found"
end

return LogUtil