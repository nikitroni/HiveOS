-- rednet_protocol.lua
-- Dynamic rednet discovery for one terminal. The three terminals have
-- isolated file systems, so this file is duplicated in 0/, 1/ and 2/.
-- Provides: open + host registration, lookup with retries, protocol send.

local RednetProtocol = {}

local HOSTNAME = "main"
local LOOKUP_ATTEMPTS = 5
local LOOKUP_TIMEOUT = 1
local LOOKUP_INTERVAL = 1

local openSide = nil

-- Open the modem (side only, no channel) if it is not open yet.
local function ensureOpen()
  if openSide and rednet.isOpen(openSide) then
    return true
  end

  local candidates = {}
  local modem = peripheral.find("modem")
  if type(modem) == "string" then
    candidates[#candidates + 1] = modem
  end
  candidates[#candidates + 1] = "back"

  for _, side in ipairs(candidates) do
    if peripheral.getType(side) == "modem" then
      local ok = pcall(rednet.open, side)
      if ok then
        openSide = side
        return true
      end
    end
  end
  return false
end

--- Open the modem and register this terminal as host of protocol/hostname.
--- @return boolean, string|nil
function RednetProtocol.host(protocol, hostname)
  hostname = hostname or HOSTNAME
  if not ensureOpen() then
    return false, "No modem"
  end
  local ok, err = pcall(rednet.host, protocol, hostname)
  if not ok then
    return false, tostring(err)
  end
  return true
end

--- Find a terminal by protocol/hostname. Retries LOOKUP_ATTEMPTS times.
--- @return number|nil
function RednetProtocol.lookup(protocol, hostname)
  hostname = hostname or HOSTNAME
  if not ensureOpen() then
    return nil
  end
  for attempt = 1, LOOKUP_ATTEMPTS do
    local ok, id = pcall(rednet.lookup, protocol, hostname, LOOKUP_TIMEOUT)
    if ok and type(id) == "number" then
      return id
    end
    if attempt < LOOKUP_ATTEMPTS then
      sleep(LOOKUP_INTERVAL)
    end
  end
  return nil
end

--- Look up the terminal and send the message under its protocol.
--- @return boolean, number|string
function RednetProtocol.send(protocol, message, hostname)
  local id = RednetProtocol.lookup(protocol, hostname)
  if not id then
    return false, "not found: " .. tostring(protocol)
  end
  local ok, err = pcall(rednet.send, id, message, protocol)
  if not ok then
    return false, tostring(err)
  end
  return true, id
end

return RednetProtocol
