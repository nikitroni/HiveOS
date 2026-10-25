local realLoadfile = loadfile

local function runCase(devices, answer)
  local listCalls = 0
  local timerId = 0
  local questions = {}
  local chat = {
    device = function(name) return name end,
    code = function() return "" end,
    waitForAnyMessage = function() return answer end,
  }
  for _, method in ipairs({
    "send", "sendInfo", "sendSuccess", "sendError", "sendWarning",
    "sendStep", "sendHighlight", "sendSeparator",
  }) do
    chat[method] = function() return true end
  end
  chat.sendQuestion = function(question)
    questions[#questions + 1] = question
    return true
  end

  local env = setmetatable({
    require = function(name)
      if name == "chat_util" then return chat end
      if name == "log_util" then return { warn = function() end } end
      return {}
    end,
    colors = {
      orange = 1, green = 2, blue = 3, purple = 4,
      yellow = 5, cyan = 6, pink = 7, lightGray = 8,
    },
    peripheral = {
      getNames = function()
        listCalls = listCalls + 1
        if listCalls == 1 then return {} end
        local names = {}
        for i, name in ipairs(devices) do names[i] = name end
        return names
      end,
      getMethods = function() return { "targetMethod" } end,
      getType = function() return "testDevice" end,
    },
    os = {
      startTimer = function()
        timerId = timerId + 1
        return timerId
      end,
      pullEventRaw = function() return "timer", timerId end,
    },
  }, { __index = _G })
  local wizard = assert(realLoadfile("HiveOS/2/config_wizard.lua", "t", env))()
  local found, cancelled = wizard.scanDeviceType({
    label = "Test device",
    max = 1,
    checkMethods = { "targetMethod" },
    types = { testDevice = true },
  }, {}, nil)
  assert(not cancelled)
  return found, questions
end

local single, singleQuestions = runCase({ "device_a" })
assert(#single == 1 and single[1] == "device_a")
assert(#singleQuestions == 1, "A single match must not ask for confirmation")

local multiple, multipleQuestions = runCase({ "device_a", "device_b" }, "2")
assert(#multiple == 1 and multiple[1] == "device_b")
assert(#multipleQuestions == 2, "Multiple matches should ask for one selection")

print("Wizard scan tests passed")
