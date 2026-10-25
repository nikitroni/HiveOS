local realLoadfile = loadfile
local sent = {}
local saved = {}
local currentTime = 0
local env = setmetatable({
  settings = {
    get = function(key) return saved[key] end,
    set = function(key, value) saved[key] = value end,
    unset = function(key) saved[key] = nil end,
    save = function() return true end,
  },
  os = { clock = function() return currentTime end, sleep = function() end },
  rednet = {
    send = function(id, message, protocol)
      sent[#sent + 1] = { id = id, message = message, protocol = protocol }
      return true
    end,
  },
  peripheral = { getNames = function() return {} end },
}, { __index = _G })
local bridge = assert(realLoadfile("HiveOS/2/pocket_bridge.lua", "t", env))()
env.require = function(name)
  if name == "pocket_bridge" then return bridge end
  if name == "log_util" then return { warn = function() end } end
  error("Unexpected require: " .. tostring(name))
end
local chat = assert(realLoadfile("HiveOS/2/chat_util.lua", "t", env))()
chat.setOwner("Owner")
local protocol = "hiveos.pocket.v1"
local function event(id, message)
  return { "rednet_message", id, message, protocol }
end
bridge.handleEvent(event(44, { type = "pair", code = bridge.getPairCode() }))
assert(bridge.isOnline())
assert(chat.sendQuestion("Proceed? (Y/N)"))
local prompt = sent[#sent].message
assert(prompt.type == "message" and prompt.kind == "yesno" and type(prompt.seq) == "number")
local _, rejected = chat.extractOwnerChat(event(45, { type = "reply", seq = prompt.seq, text = "y" }))
assert(rejected == nil, "Foreign pocket controlled the wizard")
local player, answer = chat.extractOwnerChat(event(44, { type = "reply", seq = prompt.seq, text = "y" }))
assert(player == "Owner" and answer == "y", "Paired pocket answer was lost")
local _, duplicate = chat.extractOwnerChat(event(44, { type = "reply", seq = prompt.seq, text = "n" }))
assert(duplicate == nil, "Duplicate answer was accepted")
local _, chatReply = chat.extractOwnerChat({ "chat", "Owner", "$y" })
assert(chatReply == nil, "Game chat controlled a paired wizard")
assert(chat.sendQuestion("Choose device"))
local nextPrompt = sent[#sent].message
assert(nextPrompt.seq > prompt.seq)
local _, stale = chat.extractOwnerChat(event(44, { type = "reply", seq = prompt.seq, text = "1" }))
assert(stale == nil, "Old prompt answer reached a new question")
local _, choice = chat.extractOwnerChat(event(44, { type = "reply", seq = nextPrompt.seq, text = "1" }))
assert(choice == "1")

local queuedEvents = {}
env.os.startTimer = function() return 90 end
env.os.pullEvent = function()
  local item = table.remove(queuedEvents, 1)
  assert(item, "No event queued for dialogue")
  return table.unpack(item)
end
assert(chat.sendQuestion("Answer yes"))
local chatPrompt = sent[#sent].message
queuedEvents[#queuedEvents + 1] = event(44, {
  type = "reply", seq = chatPrompt.seq, text = "yes",
})
assert(chat.waitForChat(10) == "yes", "waitForChat ignored the pocket event")
assert(chat.sendQuestion("Enter device key"))
local anyPrompt = sent[#sent].message
queuedEvents[#queuedEvents + 1] = event(44, {
  type = "reply", seq = anyPrompt.seq, text = "tech_monitor",
})
assert(chat.waitForAnyMessage(10) == "tech_monitor",
  "waitForAnyMessage ignored the pocket event")

print("Pocket dialogue integration tests passed")
