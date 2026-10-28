local realLoadfile = loadfile

local function runCase(devices, answer, present, attachEvent, deviceType, methodMap, ui, assigned)
  local listCalls = 0
  local timerId = 0
  local eventCalls = 0
  local questions = {}
  local scanEvents = {}
  local answerIndex = 0
  local function nextAnswer()
    if type(answer) ~= "table" then return answer end
    answerIndex = answerIndex + 1
    return answer[answerIndex]
  end
  local chat = {
    device = function(name) return name end,
    code = function() return "" end,
    waitForAnyMessage = nextAnswer,
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
      if name == "pocket_bridge" then return {
        clearPrompt = function() end,
        prompt = function() return false end,
        showScanStep = function(step, total, label)
          scanEvents[#scanEvents + 1] = { type = "step", step = step, total = total, label = label }
        end,
        showScanResult = function(ok, label)
          scanEvents[#scanEvents + 1] = { type = "result", ok = ok, label = label }
        end,
        promptChoices = function() return false end,
        endScan = function() end,
      } end
      return {}
    end,
    colors = {
      orange = 1, green = 2, blue = 3, purple = 4,
      yellow = 5, cyan = 6, pink = 7, lightGray = 8,
    },
    peripheral = {
      getNames = function()
        listCalls = listCalls + 1
        if (attachEvent and eventCalls == 0) or (listCalls == 1 and not present) then
          return {}
        end
        local names = {}
        for i, name in ipairs(devices) do names[i] = name end
        return names
      end,
      getMethods = function(name)
        return methodMap and methodMap[name] or { "targetMethod" }
      end,
      getType = function() return "testDevice" end,
    },
    os = {
      startTimer = function()
        timerId = timerId + 1
        return timerId
      end,
      pullEventRaw = function()
        eventCalls = eventCalls + 1
        if attachEvent and eventCalls == 1 then return "peripheral", devices[1] end
        return "timer", timerId
      end,
    },
  }, { __index = _G })
  local wizard = assert(realLoadfile("HiveOS/2/config_wizard.lua", "t", env))()
  local found, cancelled = wizard.scanDeviceType(deviceType or {
    label = "Test device",
    max = 1,
    checkMethods = { "targetMethod" },
    types = { testDevice = true },
  }, assigned or {}, ui)
  assert(not cancelled)
  return found, questions, scanEvents
end

local single, singleQuestions = runCase({ "device_a" })
assert(#single == 1 and single[1] == "device_a")
assert(#singleQuestions == 1, "A single match must not ask for confirmation")

local multiple, multipleQuestions = runCase({ "device_a", "device_b" }, { "2", "y" }, true)
assert(#multiple == 1 and multiple[1] == "device_b")
assert(#multipleQuestions == 2, "Multiple matches should ask for selection and confirmation")

local reconsidered = runCase({ "device_a", "device_b" }, { "1", "n", "2", "y" }, true)
assert(#reconsidered == 1 and reconsidered[1] == "device_b",
  "Rejected candidate must return to the choice list")

local present, presentQuestions, presentEvents = runCase({ "device_a" }, nil, true)
assert(#present == 1 and present[1] == "device_a")
assert(#presentQuestions == 0, "A single connected device should be selected immediately")
assert(presentEvents[1].type == "step" and presentEvents[1].step == 1
    and presentEvents[2].type == "result" and presentEvents[2].ok == true,
  "Pocket receives a step and accepted-device result")

local attached, attachedQuestions = runCase({ "device_a" }, nil, false, true)
assert(#attached == 1 and attached[1] == "device_a")
assert(#attachedQuestions == 1, "An attach event should advance without typing")

local inventoryMethods = { "list", "getItemDetail", "pushItems" }
local crafter = runCase({ "minecraft:barrel_9", "enderio:crafter_5" }, nil, true, false, {
  label = "Crafter #1", max = 1, checkMethods = inventoryMethods,
  namePatterns = { "^enderio:crafter_" },
}, {
  ["minecraft:barrel_9"] = inventoryMethods,
  ["enderio:crafter_5"] = inventoryMethods,
})
assert(#crafter == 1 and crafter[1] == "enderio:crafter_5",
  "A barrel must never be accepted as a crafter")

local relay = runCase({ "redstone_relay_1" }, nil, true, false, {
  label = "Breeding Relay", max = 1, checkMethods = {},
  anyMethods = { "setOutput", "setAnalogOutput" },
  namePatterns = { "^redstone_relay_" },
}, { ["redstone_relay_1"] = { "setOutput" } })
assert(#relay == 1 and relay[1] == "redstone_relay_1",
  "A relay with setOutput must be accepted")

local swapRelay, swapQuestions = runCase({ "redstone_relay_1" }, { "y" }, true, false, {
  label = "Relay Incubator", max = 1, checkMethods = { "setOutput" },
  namePatterns = { "^redstone_relay_" },
}, { ["redstone_relay_1"] = { "setOutput" } }, {
  confirmSingle = true,
  oldValue = "redstone_relay_66",
  allowExisting = { ["redstone_relay_1"] = true },
  assignmentOwners = { ["redstone_relay_1"] = "Breeding Automation Relay" },
}, { "redstone_relay_1", "redstone_relay_66" })
assert(#swapRelay == 1 and swapRelay[1] == "redstone_relay_1")
assert(#swapQuestions == 1 and swapQuestions[1]:find("Swap redstone_relay_1", 1, true),
  "Edit must describe and confirm a swap with an assigned device")

print("Wizard scan tests passed")
