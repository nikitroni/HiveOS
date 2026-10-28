local PocketBridge = {}

local protocol = "hiveos.pocket.v1"
local pocketId = settings.get("hiveos.pocketId")
local pairCode = tostring(math.random(100000, 999999))
local lastSeen = nil
local nextSequence = 0
local activeSequence = nil
local fallback = nil

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

function PocketBridge.sendPairCode(deliverPrivate)
  if pocketId or type(deliverPrivate) ~= "function" then return false end
  return deliverPrivate("PocketOS pairing code: " .. pairCode) == true
end

function PocketBridge.resetPairing(deliverPrivate)
  if type(deliverPrivate) ~= "function" then return false end
  local newCode = tostring(math.random(100000, 999999))
  if deliverPrivate("PocketOS pairing code: " .. newCode) ~= true then
    return false
  end
  local oldId = pocketId
  local oldSeen = lastSeen
  local oldSequence = activeSequence
  local oldCode = pairCode
  pocketId = nil
  lastSeen = nil
  activeSequence = nil
  pairCode = newCode
  settings.unset("hiveos.pocketId")
  if not settings.save() then
    pocketId = oldId
    lastSeen = oldSeen
    activeSequence = oldSequence
    pairCode = oldCode
    if oldId then settings.set("hiveos.pocketId", oldId) end
    return false
  end
  if type(oldId) == "number" then
    pcall(rednet.send, oldId, { type = "unpaired" }, protocol)
  end
  return true
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

function PocketBridge.showScanStep(step, total, label, signalOnly, canFinish)
  return sendToPocket({
    type = "wizard_step", step = step, total = total, label = label,
    signalOnly = signalOnly == true,
    canFinish = canFinish == true,
  })
end

function PocketBridge.showScanResult(ok, label)
  return sendToPocket({ type = "wizard_result", ok = ok, label = label })
end

function PocketBridge.endScan()
  return sendToPocket({ type = "wizard_end" })
end

function PocketBridge.endWizard()
  activeSequence = nil
  return sendToPocket({ type = "wizard_closed" })
end

function PocketBridge.prompt(kind, text)
  if not PocketBridge.isOnline() then return false end
  nextSequence = nextSequence + 1
  local sequence = nextSequence
  local sent = sendToPocket({ type = "message", kind = kind, text = text, seq = sequence })
  if sent then activeSequence = sequence end
  return sent
end

function PocketBridge.promptChoices(label, choices)
  if not PocketBridge.isOnline() then return false end
  nextSequence = nextSequence + 1
  local sequence = nextSequence
  local sent = sendToPocket({
    type = "wizard_choices", label = label, choices = choices, seq = sequence,
  })
  if sent then activeSequence = sequence end
  return sent
end

function PocketBridge.clearPrompt()
  if activeSequence ~= nil then
    sendToPocket({ type = "clear_prompt", seq = activeSequence })
  end
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
  end
end

function PocketBridge.run()
  while true do
    local eventData = { os.pullEvent("rednet_message") }
    PocketBridge.handleEvent(eventData)
  end
end

return PocketBridge
