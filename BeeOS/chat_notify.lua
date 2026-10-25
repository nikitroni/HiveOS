-- Send private BeeOS notifications to the configured owner.
local ChatNotify = {}

local sectionSign = "\194\167"
local motd = {
  white = sectionSign .. "f",
  green = sectionSign .. "a",
  red = sectionSign .. "c",
}
local terminalTag = "BeeOS"
local chatBox

local function loadConfig()
  if not fs.exists("beeos_config.lua") then return nil end
  local handler = loadfile("beeos_config.lua")
  if not handler then return nil end
  local ok, cfg = pcall(handler)
  if ok and type(cfg) == "table" then return cfg end
  return nil
end

function ChatNotify.init()
  local cfg = loadConfig()
  local chatName = cfg and cfg.peripherals and cfg.peripherals.chat_box
  if type(chatName) == "string" and chatName ~= "" then
    chatBox = peripheral.wrap(chatName)
    if chatBox then return true end
  end
  chatBox = peripheral.find("chat_box") or peripheral.find("chatBox")
  return chatBox ~= nil
end

-- Detect the API by method availability; failed private sends stay private.
local function send(message)
  local cfg = loadConfig()
  local owner = cfg and cfg.owner
  if type(owner) ~= "string" or not owner:match("%S") then return false end
  if not chatBox and not ChatNotify.init() then return false end

  local ok, sent = pcall(function()
    if type(chatBox.sendMessageToPlayer) == "function" then
      return chatBox.sendMessageToPlayer(message, owner, terminalTag, nil, nil, nil, true)
    end
    if type(chatBox.sendMessage) == "function" then
      return chatBox.sendMessage(message, { player = owner, prefix = terminalTag, utf8 = true })
    end
    return false
  end)
  return ok and sent == true
end

function ChatNotify.sendInfo(message)
  return send(motd.white .. message)
end

function ChatNotify.sendSuccess(message)
  return send(motd.green .. message)
end

function ChatNotify.sendError(message)
  return send(motd.red .. message)
end

return ChatNotify
