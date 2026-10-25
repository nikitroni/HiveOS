local protocol = "hiveos.pocket.v1"
local hostProtocol = "heartos"
local hostName = "main"
local heartId = settings.get("hiveos.heartId")
local connected = false
local pendingPair = false
local pairStartedAt = nil
local lastHeartbeatAt = nil
local prompt = nil
local input = ""
local lines = {}
local scroll = 0
local status = "Finding HeartOS..."
local actions = {
  ["1"] = "beeos_create", ["2"] = "beeos_edit",
  ["3"] = "labos_create", ["4"] = "labos_edit",
  ["5"] = "hive_create", ["6"] = "hive_edit",
}

local function findWirelessModem()
  return peripheral.find("modem", function(_, modem)
    if not modem or type(modem.isWireless) ~= "function" then return false end
    local ok, wireless = pcall(modem.isWireless)
    return ok and wireless == true
  end)
end

local function openNetwork()
  local modem = findWirelessModem()
  if not modem then return false end
  local name = peripheral.getName(modem)
  if not name then return false end
  if rednet.isOpen(name) then return true end
  local ok = pcall(rednet.open, name)
  return ok and rednet.isOpen(name)
end

local function findHeart()
  if not openNetwork() then
    status = "Attach a wireless modem"
    return nil
  end
  local ok, id = pcall(rednet.lookup, hostProtocol, hostName, 2)
  if ok and type(id) == "number" then return id end
  status = "HeartOS is offline"
  return nil
end

local function send(id, message)
  if type(id) ~= "number" or not openNetwork() then return false end
  local ok, sent = pcall(rednet.send, id, message, protocol)
  return ok and sent == true
end

local function addLine(value)
  local width = math.max(10, select(1, term.getSize()) - 1)
  local plain = tostring(value):gsub("\194\167.", ""):gsub("\167.", "")
  plain = plain:gsub("%c", " ")
  while #plain > width do
    local cut = width
    local space = plain:sub(1, width):match("^.*()%s")
    if space and space > width / 2 then cut = space end
    lines[#lines + 1] = plain:sub(1, cut):gsub("%s+$", "")
    plain = plain:sub(cut + 1):gsub("^%s+", "")
  end
  lines[#lines + 1] = plain
  while #lines > 120 do table.remove(lines, 1) end
  scroll = 0
end

local function drawText(y, value, textColor, backgroundColor)
  local width = select(1, term.getSize())
  term.setCursorPos(1, y)
  term.setTextColor(textColor or colors.white)
  term.setBackgroundColor(backgroundColor or colors.black)
  term.clearLine()
  term.write(tostring(value):sub(1, width))
end

local function draw()
  local width, height = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  drawText(1, " HiveOS Pocket", colors.white, colors.blue)
  drawText(2, status, connected and colors.lime or colors.orange)

  local footerStart = height - 3
  local last = math.max(0, #lines - scroll)
  local first = math.max(1, last - (footerStart - 4))
  for row = 3, footerStart - 1 do
    local index = first + row - 3
    if index <= last then drawText(row, lines[index]) end
  end

  if not heartId then
    drawText(footerStart, "Pair code from HeartOS:", colors.cyan)
    drawText(footerStart + 1, "> " .. input, colors.white, colors.gray)
    drawText(footerStart + 2, "Enter=Pair", colors.yellow)
  elseif prompt then
    drawText(footerStart, prompt.yesNo and "[Y] Yes  [N] No" or "Type response", colors.cyan)
    drawText(footerStart + 1, "> " .. input:sub(-math.max(1, width - 3)), colors.white, colors.gray)
    drawText(footerStart + 2, "Enter=Send  Esc=Cancel", colors.yellow)
  else
    drawText(footerStart, "1 Bee+  2 Bee Edit", colors.cyan)
    drawText(footerStart + 1, "3 Lab+  4 Lab Edit", colors.white, colors.gray)
    drawText(footerStart + 2, "5 Hive+ 6 Hive Edit", colors.yellow)
  end
  term.setCursorPos(math.min(width, #input + 3), footerStart + 1)
end

local function pairWithCode(code)
  local id = findHeart()
  if not id then return end
  if code == "" then
    status = "Enter a pair code"
    return
  end
  heartId = id
  pendingPair = true
  pairStartedAt = os.clock()
  connected = false
  status = "Pairing..."
  if not send(id, { type = "pair", code = code }) then
    heartId = nil
    pendingPair = false
    status = "Could not send pair code"
  end
end

local function reconnect()
  if not heartId or not openNetwork() then return end
  local id = findHeart()
  if not id then connected = false return end
  if id ~= heartId then
    connected = false
    heartId = nil
    settings.unset("hiveos.heartId")
    settings.save()
    status = "HeartOS changed; pair again"
    return
  end
  if not send(heartId, { type = "hello" }) then
    connected = false
    status = "HeartOS is offline"
  end
end

local function submit(value)
  if not prompt or not heartId or not connected then return end
  local trimmed = value:match("^%s*(.-)%s*$")
  if trimmed == "" then return end
  if send(heartId, { type = "reply", seq = prompt.seq, text = trimmed }) then
    addLine("> " .. trimmed)
    prompt = nil
    input = ""
    status = "Waiting for HeartOS..."
  else
    status = "Reply not sent; try again"
  end
end

local function startAction(key)
  local action = actions[key]
  if not action or not connected or not heartId then return end
  if send(heartId, { type = "action", action = action }) then
    status = "Opening " .. action
  else
    status = "Could not reach HeartOS"
  end
end

local function handleMessage(sender, message, receivedProtocol)
  if receivedProtocol ~= protocol or sender ~= heartId or type(message) ~= "table" then return end
  if message.type == "paired" then
    pendingPair = false
    pairStartedAt = nil
    if message.ok == true then
      local wasConnected = connected
      connected = true
      lastHeartbeatAt = os.clock()
      status = "Connected to HeartOS"
      if settings.get("hiveos.heartId") ~= heartId then
        settings.set("hiveos.heartId", heartId)
        if not settings.save() then status = "Could not save pairing" end
      end
      if not wasConnected then
        input = ""
        addLine("Paired with HeartOS #" .. heartId)
      end
    else
      connected = false
      heartId = nil
      prompt = nil
      settings.unset("hiveos.heartId")
      settings.save()
      status = tostring(message.reason or "Pairing rejected")
    end
  elseif message.type == "message" and connected and type(message.text) == "string" then
    addLine(message.text)
    if type(message.seq) == "number" then
      prompt = {
        seq = message.seq,
        yesNo = message.kind == "yesno" or message.text:find("%([Yy]/[Nn]%)") ~= nil,
      }
      input = ""
      status = "Reply on this screen"
    end
  elseif message.type == "status" and connected and type(message.text) == "string" then
    status = message.text
  end
end

if not openNetwork() then
  status = "Attach a wireless modem"
elseif heartId then
  reconnect()
else
  status = "Enter HeartOS pair code"
end

local reconnectTimer = os.startTimer(5)
while true do
  draw()
  local event, first, second, third = os.pullEvent()
  if event == "rednet_message" then
    handleMessage(first, second, third)
  elseif event == "timer" and first == reconnectTimer then
    if pendingPair and pairStartedAt and os.clock() - pairStartedAt > 12 then
      pendingPair = false
      heartId = nil
      status = "Pair timeout; enter code again"
    elseif heartId and not pendingPair then
      if lastHeartbeatAt and os.clock() - lastHeartbeatAt > 15 then
        connected = false
        status = "HeartOS is offline"
      end
      reconnect()
    end
    reconnectTimer = os.startTimer(5)
  elseif event == "char" then
    if not heartId or prompt then input = input .. first
    else startAction(first) end
  elseif event == "paste" then
    if not heartId or prompt then input = input .. first end
  elseif event == "key" then
    if first == keys.backspace then
      input = input:sub(1, -2)
    elseif first == keys.enter or first == keys.numPadEnter then
      if not heartId then pairWithCode(input) else submit(input) end
    elseif first == keys.escape and prompt then
      submit("cancel")
    elseif first == keys.pageUp then
      scroll = math.min(math.max(0, #lines - 1), scroll + 3)
    elseif first == keys.pageDown then
      scroll = math.max(0, scroll - 3)
    end
  elseif event == "mouse_scroll" then
    scroll = math.max(0, math.min(#lines, scroll + first))
  elseif event == "mouse_click" then
    local height = select(2, term.getSize())
    if prompt and prompt.yesNo and third == height - 3 then
      if second <= 8 then submit("y") elseif second <= 16 then submit("n") end
    elseif not prompt and connected and third >= height - 3 and third <= height - 1 then
      local row = third - (height - 3)
      local column = second <= select(1, term.getSize()) / 2 and 1 or 2
      startAction(tostring(row * 2 + column))
    end
  elseif event == "term_resize" then
    scroll = 0
  end
end
