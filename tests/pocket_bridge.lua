local originalLoadfile = loadfile
local assertions = 0
local function expect(value, label)
  assertions = assertions + 1
  assert(value, label)
end

local now = 0
local saved = {}
local sent = {}
local queued = {}
local env = setmetatable({
  settings = {
    get = function(key) return saved[key] end,
    set = function(key, value) saved[key] = value end,
    unset = function(key) saved[key] = nil end,
    save = function() return true end,
  },
  os = {
    clock = function() return now end,
    queueEvent = function(name, value) queued[#queued + 1] = { name, value } end,
  },
  rednet = {
    send = function(id, body, protocol)
      sent[#sent + 1] = { id = id, body = body, protocol = protocol }
      return true
    end,
  },
}, { __index = _G })
local bridge = assert(originalLoadfile("HiveOS/2/pocket_bridge.lua", "t", env))()
local protocol = "hiveos.pocket.v1"
local code = bridge.getPairCode()
local function event(id, body)
  return { "rednet_message", id, body, protocol }
end

bridge.handleEvent(event(17, { type = "pair", code = "wrong" }))
expect(sent[#sent].body.ok == false, "Wrong code rejected")
expect(bridge.getPocketId() == nil, "Wrong code did not pair")
bridge.handleEvent(event(17, { type = "pair", code = code }))
expect(sent[#sent].body.ok == true, "Correct code accepted")
expect(bridge.getPocketId() == 17, "Pocket ID persisted")
expect(saved["hiveos.pocketId"] == 17, "Settings persisted")
expect(bridge.isOnline(), "Pocket online after pairing")
bridge.handleEvent(event(18, { type = "pair", code = code }))
expect(sent[#sent].body.ok == false, "Second pocket refused")
bridge.handleEvent(event(18, { type = "hello" }))
expect(sent[#sent].body.ok == false, "Foreign heartbeat refused")

expect(bridge.prompt("yesno", "Proceed?"), "Prompt delivered")
local sequence = sent[#sent].body.seq
expect(type(sequence) == "number", "Prompt numbered")
expect(bridge.takeReply(event(18, { type = "reply", seq = sequence, text = "y" })) == nil,
  "Foreign reply refused")
expect(bridge.takeReply(event(17, { type = "reply", seq = sequence - 1, text = "y" })) == nil,
  "Stale reply refused")
expect(bridge.takeReply(event(17, { type = "reply", seq = sequence, text = " y " })) == "y",
  "Current reply accepted and trimmed")
expect(bridge.takeReply(event(17, { type = "reply", seq = sequence, text = "y" })) == nil,
  "Duplicate reply refused")

local fallbacks = 0
bridge.setFallback(function(message)
  fallbacks = fallbacks + 1
  return message == "[BeeOS] alert"
end)
now = 14
expect(not bridge.isOnline(), "Pocket timeout detected")
expect(bridge.notify("BeeOS", "alert"), "Private fallback used")
expect(fallbacks == 1, "One fallback call")
bridge.handleEvent(event(17, { type = "hello" }))
expect(bridge.isOnline(), "Heartbeat restores online status")
expect(bridge.notify("LabOS", "alert"), "Online notification delivered")
expect(fallbacks == 1, "No duplicate private message when online")
bridge.handleEvent(event(9, { type = "notify", role = "BeeOS", text = "alert", id = 4 }))
expect(sent[#sent].body.type == "notify_ack" and sent[#sent].body.id == 4
    and sent[#sent].body.ok == true, "Role notification acknowledged")

bridge.handleEvent(event(18, { type = "action", action = "beeos_create" }))
expect(#queued == 0, "Foreign pocket action rejected")
bridge.handleEvent(event(17, { type = "action", action = "beeos_create" }))
expect(#queued == 1 and queued[1][1] == "pocket_action"
    and queued[1][2] == "beeos_create", "Paired action queued")
bridge.handleEvent(event(17, { type = "action", action = "labos_create" }))
expect(#queued == 1, "Concurrent action rejected")
bridge.setWizardBusy(false)
bridge.handleEvent(event(17, { type = "action", action = "unknown" }))
expect(#queued == 1, "Unknown action rejected")

print("Pocket bridge tests passed: " .. assertions .. " assertions")
