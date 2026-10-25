-- Run from the workspace root with a Lua 5.3+ interpreter.
local realLoadfile = loadfile
local assertions = 0

local function equal(actual, expected, label)
  assertions = assertions + 1
  assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local paths = {
  BeeOS = "HiveOS/0/chat_notify.lua",
  LabOS = "HiveOS/1/lab_utils.lua",
  HeartOS = "HiveOS/2/chat_util.lua",
}

local function createAdapter(role, version, outcome)
  local state = { owner = "Owner", calls = {}, configExists = true, available = true }
  local lib = { owner = state.owner, chat_box = "chat_box_0", peripherals = {} }
  local box = {}
  local function record(method, ...)
    state.calls[#state.calls + 1] = { method = method, args = table.pack(...) }
    if outcome == "throw" then error("Simulated peripheral failure") end
    if outcome == "nil" then return nil end
    return outcome == "true"
  end
  box.sendMessage = function(...) return record("sendMessage", ...) end
  if version == "0.7" then
    box.sendMessageToPlayer = function(...) return record("sendMessageToPlayer", ...) end
  end
  local env = setmetatable({
    fs = { exists = function() return state.configExists end },
    loadfile = function(path)
      equal(path, "beeos_config.lua", "Only mocked config may be loaded")
      return function()
        return { owner = state.owner, peripherals = { chat_box = "chat_box_0" } }
      end
    end,
    peripheral = {
      wrap = function() if state.available then return box end end,
      find = function() if state.available then return box end end,
      getNames = function() return state.available and { "chat_box_0" } or {} end,
      getMethods = function() return { "sendMessage" } end,
    },
    require = function(name)
      if name == "lab_lib" then return lib end
      if name == "log_util" then return { warn = function() end } end
      error("Unexpected dependency: " .. tostring(name))
    end,
    os = { sleep = function() end },
  }, { __index = _G })
  local adapter = assert(realLoadfile(paths[role], "t", env))()
  local function setOwner(owner)
    state.owner = owner
    lib.owner = owner
    if role == "HeartOS" then adapter.setOwner(owner) end
  end
  if role == "HeartOS" then
    adapter.init("chat_box_0")
    adapter.setOwner(state.owner)
  end
  local function send()
    if role == "LabOS" then return adapter.sendChat("notice", false) end
    return adapter.sendSuccess("notice")
  end
  return state, adapter, send, setOwner
end

for _, role in ipairs({ "BeeOS", "LabOS", "HeartOS" }) do
  for _, version in ipairs({ "0.7", "0.8" }) do
    for _, outcome in ipairs({ "true", "false", "nil", "throw" }) do
      local state, _, send = createAdapter(role, version, outcome)
      local label = role .. " AP " .. version .. " " .. outcome
      equal(send(), outcome == "true", label .. " result")
      equal(#state.calls, 1, label .. " no fallback or duplicate")
      local call = state.calls[1]
      equal(call.args[1]:sub(1, 3), "\194\167a", label .. " UTF-8 green")
      if version == "0.7" then
        equal(call.method, "sendMessageToPlayer", label .. " private method")
        equal(call.args.n, 7, label .. " argument count")
        equal(call.args[2], "Owner", label .. " recipient")
        equal(call.args[3], role, label .. " prefix")
        for index = 4, 6 do equal(call.args[index], nil, label .. " optional argument") end
        equal(call.args[7], true, label .. " UTF-8 enabled")
      else
        equal(call.method, "sendMessage", label .. " options API")
        equal(call.args.n, 2, label .. " argument count")
        equal(type(call.args[2]), "table", label .. " options table")
        equal(call.args[2].player, "Owner", label .. " private recipient")
        equal(call.args[2].prefix, role, label .. " prefix")
        equal(call.args[2].utf8, true, label .. " UTF-8 enabled")
      end
    end
    for _, missing in ipairs({ "nil", "empty", "whitespace" }) do
      local state, _, send, setOwner = createAdapter(role, version, "true")
      local owner
      if missing == "empty" then owner = "" end
      if missing == "whitespace" then owner = "   " end
      setOwner(owner)
      equal(send(), false, role .. " rejects " .. missing .. " owner")
      equal(#state.calls, 0, role .. " no call without owner")
    end
    local state, _, send, setOwner = createAdapter(role, version, "true")
    equal(send(), true, role .. " initial owner")
    setOwner("NewOwner")
    equal(send(), true, role .. " changed owner")
    local args = state.calls[2].args
    local recipient = version == "0.7" and args[2] or args[2].player
    equal(recipient, "NewOwner", role .. " owner change applied")
  end
end

do
  local state, _, send = createAdapter("BeeOS", "0.8", "true")
  state.configExists = false
  equal(send(), false, "BeeOS missing config")
  equal(#state.calls, 0, "BeeOS missing config cannot broadcast")
end

do
  local _, chat = createAdapter("HeartOS", "0.8", "true")
  local uuid = "12345678-1234-1234-1234-123456789abc"
  local events = {
    { "chat", "Owner", "$yes", uuid, true },
    { "chat", uuid, "Owner", "$yes", true },
    { "chat", nil, "Owner", "$yes", true },
    { "chat_signed", "Owner", "$yes" },
    { "chat", "owner", "  $ yes  ", uuid, true },
  }
  for index, event in ipairs(events) do
    local player, message = chat.extractOwnerChat(event)
    equal(player:lower(), "owner", "Owner event " .. index .. " player")
    equal(message, "yes", "Owner event " .. index .. " hidden reply")
  end
  local rejected = {
    { "chat", "Stranger", "$yes", uuid, true },
    { "chat", uuid, "Stranger", "$yes", true },
    { "chat_signed", "Stranger", "$yes" },
    { "chat", "Owner", "$", uuid, true },
    { "chat", "Owner", "[OK] notice", uuid, true },
    { "monitor_touch", "Owner", "yes" },
  }
  for index, event in ipairs(rejected) do
    local player, message = chat.extractOwnerChat(event)
    equal(player, nil, "Rejected event " .. index .. " player")
    equal(message, nil, "Rejected event " .. index .. " message")
  end
  chat.setOwner(nil)
  equal(chat.extractOwnerChat(events[1]), nil, "Replies rejected without owner")
end

print("Private notification tests passed: " .. assertions .. " assertions")
