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
expect(bridge.showScanStep(2, 18, "Bee Button Monitor"), "Scan step delivered")
expect(sent[#sent].body.type == "wizard_step" and sent[#sent].body.step == 2
    and sent[#sent].body.total == 18, "Scan progress is structured")
expect(bridge.showScanResult(true, "Bee Button Monitor"), "Scan result delivered")
expect(sent[#sent].body.type == "wizard_result" and sent[#sent].body.ok == true,
  "Accepted device can trigger pocket feedback")
expect(bridge.promptChoices("Crafter #1", { "enderio:crafter_5", "enderio:crafter_6" }),
  "Candidate list delivered")
local choiceSequence = sent[#sent].body.seq
expect(sent[#sent].body.type == "wizard_choices"
    and #sent[#sent].body.choices == 2, "Pocket receives all candidates")
expect(bridge.takeReply(event(17, { type = "reply", seq = choiceSequence, text = "2" })) == "2",
  "Pocket candidate choice accepted")
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

expect(bridge.prompt("question", "Connect device"), "Device prompt delivered")
local deviceSequence = sent[#sent].body.seq
bridge.clearPrompt()
expect(sent[#sent].body.type == "clear_prompt" and sent[#sent].body.seq == deviceSequence,
  "Pocket prompt dismissed after automatic detection")
expect(bridge.takeReply(event(17, { type = "reply", seq = deviceSequence, text = "done" })) == nil,
  "Dismissed prompt cannot advance another step")

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

bridge.handleEvent(event(17, { type = "action", action = "beeos_create" }))
expect(#queued == 0, "Pocket cannot start a HeartOS wizard")

expect(not bridge.sendPairCode(function() return true end),
  "A paired PocketOS must not expose a pairing code")
expect(not bridge.resetPairing(function() return false end),
  "Failed private delivery must keep the old pairing")
expect(bridge.getPocketId() == 17 and saved["hiveos.pocketId"] == 17,
  "Old pairing remains active when private delivery fails")
local privateCode
expect(bridge.resetPairing(function(message)
  privateCode = message:match("(%d%d%d%d%d%d)$")
  return privateCode ~= nil
end), "Private delivery permits replacement")
expect(bridge.getPocketId() == nil and saved["hiveos.pocketId"] == nil,
  "Old pairing removed after delivery")
expect(bridge.getPairCode() == privateCode, "Privately delivered code is the active code")
expect(sent[#sent].body.type == "unpaired" and sent[#sent].id == 17,
  "Old PocketOS is notified of revocation")
bridge.handleEvent(event(18, { type = "pair", code = privateCode }))
expect(bridge.getPocketId() == 18, "New PocketOS accepts the private code")

print("Pocket bridge tests passed: " .. assertions .. " assertions")
