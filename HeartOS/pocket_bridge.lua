local PocketBridge = {}

local protocol = "hiveos.pocket.v1"
local pocketId = settings.get("hiveos.pocketId")
local pairCode = tostring(math.random(100000, 999999))
local lastSeen = nil
local nextSequence = 0
local activeSequence = nil
local fallback = nil
local wizardBusy = false
local actions = {
  beeos_create = true, beeos_edit = true,
  labos_create = true, labos_edit = true,
  hive_create = true, hive_edit = true,
}

function PocketBridge.setWizardBusy(value)
  wizardBusy = value == true
end

function PocketBridge.setFallback(sendPrivate)
  fallback = sendPrivate
end

function PocketBridge.getPairCode()
  if pocketId then return nil end
  return pairCode
end

function PocketBridge.getPocketId()
  return pocketId
end

function PocketBridge.resetPairing()
  pocketId = nil
  lastSeen = nil
  activeSequence = nil
  pairCode = tostring(math.random(100000, 999999))
  settings.unset("hiveos.pocketId")
  return settings.save()
end

function PocketBridge.isOnline()
  return type(pocketId) == "number" and lastSeen ~= nil
      and os.clock() - lastSeen < 13
end

local function sendToPocket(message)
  if not PocketBridge.isOnline() then return false end
  local ok, sent = pcall(rednet.send, pocketId, message, protocol)
  return ok and sent == true
end

function PocketBridge.send(kind, text)
  return sendToPocket({ type = "message", kind = kind, text = text })
end

function PocketBridge.prompt(kind, text)
  if not PocketBridge.isOnline() then return false end
  nextSequence = nextSequence + 1
  local sequence = nextSequence
  local sent = sendToPocket({ type = "message", kind = kind, text = text, seq = sequence })
  if sent then activeSequence = sequence end
  return sent
end

function PocketBridge.clearPrompt()
  activeSequence = nil
end

function PocketBridge.takeReply(eventData)
  if eventData[1] ~= "rednet_message" or eventData[2] ~= pocketId
      or eventData[4] ~= protocol or type(eventData[3]) ~= "table" then
    return nil
  end
  local message = eventData[3]
  if message.type ~= "reply" or type(message.seq) ~= "number"
      or message.seq ~= activeSequence or type(message.text) ~= "string" then
    return nil
  end
  local answer = message.text:match("^%s*(.-)%s*$")
  if answer == "" then return nil end
  activeSequence = nil
  lastSeen = os.clock()
  return answer
end

function PocketBridge.notify(role, text)
  local message = "[" .. tostring(role) .. "] " .. tostring(text)
  if PocketBridge.send("notification", message) then return true end
  if fallback then return fallback(message) == true end
  return false
end

function PocketBridge.handleEvent(eventData)
  if eventData[1] ~= "rednet_message" or eventData[4] ~= protocol
      or type(eventData[3]) ~= "table" then return end
  local sender, message = eventData[2], eventData[3]
  if message.type == "pair" then
    local accepted = pocketId == nil and tostring(message.code) == pairCode
    if accepted then
      pocketId = sender
      lastSeen = os.clock()
      settings.set("hiveos.pocketId", sender)
      if not settings.save() then
        settings.unset("hiveos.pocketId")
        pocketId = nil
        lastSeen = nil
        accepted = false
      end
    end
    rednet.send(sender, {
      type = "paired", ok = accepted,
      reason = accepted and nil or "Invalid code or PocketOS already paired",
    }, protocol)
  elseif message.type == "hello" then
    local accepted = sender == pocketId
    if accepted then lastSeen = os.clock() end
    rednet.send(sender, {
      type = "paired", ok = accepted,
      reason = accepted and nil or "PocketOS is not paired with HeartOS",
    }, protocol)
  elseif message.type == "notify" and (message.role == "BeeOS" or message.role == "LabOS")
      and type(message.text) == "string" then
    local delivered = PocketBridge.notify(message.role, message.text)
    rednet.send(sender, {
      type = "notify_ack", id = message.id, ok = delivered,
    }, protocol)
  elseif message.type == "action" and sender == pocketId and actions[message.action] then
    if wizardBusy or not PocketBridge.isOnline() then
      rednet.send(sender, { type = "status", text = "HeartOS is busy; try again from the main menu" }, protocol)
    else
      wizardBusy = true
      rednet.send(sender, { type = "status", text = "Opening " .. message.action }, protocol)
      os.queueEvent("pocket_action", message.action)
    end
  end
end

function PocketBridge.run()
  while true do
    local eventData = { os.pullEvent("rednet_message") }
    PocketBridge.handleEvent(eventData)
  end
end

return PocketBridge
