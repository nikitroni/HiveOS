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
local scanStep = nil
local choiceList = nil
local choiceScroll = 0
local promptText = nil
local flash = nil
local flashTimer = nil

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

local function drawCentered(y, value, textColor, backgroundColor)
  local width = select(1, term.getSize())
  local visible = tostring(value):sub(1, width)
  term.setCursorPos(math.max(1, math.floor((width - #visible) / 2) + 1), y)
  term.setTextColor(textColor or colors.white)
  term.setBackgroundColor(backgroundColor or colors.black)
  term.write(visible)
end

local function wrapLines(value, width)
  local result = {}
  local remaining = tostring(value or "")
  while #remaining > width do
    local cut = remaining:sub(1, width):match("^.*()%s") or width
    result[#result + 1] = remaining:sub(1, cut):gsub("%s+$", "")
    remaining = remaining:sub(cut + 1):gsub("^%s+", "")
  end
  result[#result + 1] = remaining
  return result
end

local function draw()
  local width, height = term.getSize()
  if flash then
    local background = flash.ok and colors.green or colors.red
    term.setBackgroundColor(background)
    term.clear()
    local heading = flash.ok and "DEVICE ACCEPTED" or "WRONG DEVICE"
    local parts = wrapLines(flash.label, math.max(10, width - 2))
    local startY = math.max(1, math.floor((height - #parts - 2) / 2) + 1)
    drawCentered(startY, heading, colors.white, background)
    for index, part in ipairs(parts) do
      drawCentered(startY + index + 1, part, colors.white, background)
    end
    return
  end

  term.setBackgroundColor(colors.black)
  term.clear()
  drawText(1, " PocketOS", colors.white, colors.blue)
  drawText(2, status, connected and colors.lime or colors.orange)

  local footerStart = height - 3
  if choiceList then
    drawText(4, choiceList.label == "Choose hive to edit"
      and "CHOOSE HIVE" or "CHOOSE DEVICE", colors.cyan)
    for index, part in ipairs(wrapLines(choiceList.label, math.max(10, width - 2))) do
      if index > 2 then break end
      drawText(4 + index, part, colors.yellow)
    end
    drawText(7, choiceList.label == "Choose device to edit"
      and "Tap item / 0=Finish" or "Tap item / PgDn=More", colors.lightGray)
    local lastRow = footerStart - 1
    for row = 8, lastRow do
      local index = choiceScroll + row - 7
      local name = choiceList.items[index]
      if name then
        drawText(row, tostring(index) .. ". " .. name, colors.white)
      end
    end
  elseif scanStep then
    local step = math.max(1, scanStep.step)
    local total = math.max(step, scanStep.total)
    drawText(4, "DEVICE " .. step .. "/" .. total, colors.cyan)
    local barWidth = math.max(1, width - 2)
    local filled = math.floor((step - 1) * barWidth / total)
    drawText(5, string.rep("=", filled) .. string.rep("-", barWidth - filled), colors.green)
    drawText(7, "CONNECT NOW", colors.white, colors.blue)
    for index, part in ipairs(wrapLines(scanStep.label, math.max(10, width - 2))) do
      if index > 3 then break end
      drawText(7 + index, " " .. part, colors.yellow, colors.blue)
    end
    if scanStep.signalOnly then
      drawText(12, "Connect or reconnect it", colors.lightGray)
      drawText(13, "Accepted automatically", colors.lightGray)
    else
      drawText(12, "Connect an unused device", colors.lightGray)
      drawText(13, "Auto-select if only one", colors.lightGray)
    end
  elseif promptText then
    drawText(4, "YOUR ANSWER", colors.cyan)
    for index, part in ipairs(wrapLines(promptText, math.max(10, width - 2))) do
      if 4 + index >= footerStart then break end
      drawText(4 + index, part, colors.white)
    end
  else
    local last = math.max(0, #lines - scroll)
    local first = math.max(1, last - (footerStart - 4))
    for row = 3, footerStart - 1 do
      local index = first + row - 3
      if index <= last then drawText(row, lines[index]) end
    end
  end

  if not heartId then
    drawText(footerStart, "Pair code from HeartOS:", colors.cyan)
    drawText(footerStart + 1, "> " .. input, colors.white, colors.gray)
    drawText(footerStart + 2, "Enter=Pair", colors.yellow)
  elseif prompt and prompt.kind == "scan" then
    drawText(footerStart, "Waiting for device", colors.cyan)
    drawText(footerStart + 1, "> " .. input:sub(-math.max(1, width - 3)), colors.white, colors.gray)
    drawText(footerStart + 2,
      scanStep and scanStep.canFinish and "[Finish]     Esc=Back"
        or scanStep and scanStep.signalOnly and "Connect block  Esc=Back"
        or "Skip=type skip  Esc=Back", colors.yellow)
  elseif prompt and prompt.kind == "choice" then
    drawText(footerStart, "Type device number", colors.cyan)
    drawText(footerStart + 1, "> " .. input:sub(-math.max(1, width - 3)), colors.white, colors.gray)
    drawText(footerStart + 2, "Enter=Select  Esc=Back", colors.yellow)
  elseif prompt then
    drawText(footerStart, prompt.yesNo and "[Y] Yes  [N] No" or "Type response", colors.cyan)
    drawText(footerStart + 1, "> " .. input:sub(-math.max(1, width - 3)), colors.white, colors.gray)
    drawText(footerStart + 2, "Enter=Send  Esc=Cancel", colors.yellow)
  else
    drawText(footerStart, "Ready for setup", colors.cyan)
    drawText(footerStart + 1, "Start on HeartOS", colors.white, colors.gray)
    drawText(footerStart + 2, "Alerts appear here", colors.yellow)
  end
  if not heartId or prompt then
    term.setCursorPos(math.min(width, #input + 3), footerStart + 1)
  end
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
    if prompt.kind ~= "scan" then addLine("> " .. trimmed) end
    prompt = nil
    promptText = nil
    choiceList = nil
    input = ""
    status = scanStep and "Processing device..." or "Waiting for HeartOS..."
  else
    status = "Reply not sent; try again"
  end
end

local function handleMessage(sender, message, receivedProtocol)
  if receivedProtocol ~= protocol or sender ~= heartId or type(message) ~= "table" then return end
  if message.type == "unpaired" then
    heartId = nil
    connected = false
    pendingPair = false
    prompt = nil
    promptText = nil
    scanStep = nil
    choiceList = nil
    flash = nil
    lines = {}
    scroll = 0
    lastHeartbeatAt = nil
    input = ""
    settings.unset("hiveos.heartId")
    settings.save()
    status = "Pair again from HeartOS"
  elseif message.type == "paired" then
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
      promptText = nil
      choiceList = nil
      settings.unset("hiveos.heartId")
      settings.save()
      status = tostring(message.reason or "Pairing rejected")
    end
  elseif message.type == "message" and connected and type(message.text) == "string" then
    if type(message.seq) == "number" then
      prompt = {
        seq = message.seq,
        kind = message.kind,
        yesNo = message.kind == "yesno" or message.text:find("%([Yy]/[Nn]%)") ~= nil,
      }
      input = ""
      if message.kind == "scan" then
        status = "Waiting for device"
      else
        scanStep = nil
        choiceList = nil
        promptText = message.text:gsub("\194\167.", ""):gsub("\167.", "")
        status = "Reply on this screen"
      end
    elseif not scanStep then
      addLine(message.text)
    end
  elseif message.type == "wizard_step" and connected
      and type(message.step) == "number" and type(message.total) == "number"
      and type(message.label) == "string" then
    scanStep = {
      step = message.step, total = message.total,
      label = message.label, signalOnly = message.signalOnly == true,
      canFinish = message.canFinish == true,
    }
    promptText = nil
    choiceList = nil
    prompt = nil
    input = ""
    lines = {}
    status = "Configuring devices"
  elseif message.type == "wizard_choices" and connected
      and type(message.seq) == "number" and type(message.label) == "string"
      and type(message.choices) == "table" then
    choiceList = { label = message.label, items = message.choices }
    choiceScroll = 0
    prompt = { seq = message.seq, kind = "choice", yesNo = false }
    input = ""
    status = "Select matching device"
  elseif message.type == "wizard_result" and connected
      and type(message.label) == "string" then
    flash = { ok = message.ok == true, label = message.label }
    flashTimer = os.startTimer(1.5)
  elseif message.type == "wizard_end" and connected then
    scanStep = nil
    choiceList = nil
    if prompt and prompt.kind == "scan" then prompt = nil end
    if not prompt then promptText = nil end
    input = ""
    status = "Ready for next step"
  elseif message.type == "wizard_closed" and connected then
    prompt = nil
    promptText = nil
    scanStep = nil
    choiceList = nil
    flash = nil
    input = ""
    lines = {}
    scroll = 0
    status = "Connected to HeartOS"
  elseif message.type == "clear_prompt" and connected and prompt
      and message.seq == prompt.seq then
    prompt = nil
    promptText = nil
    choiceList = nil
    input = ""
    status = scanStep and "Processing device..." or "Continuing..."
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
  elseif event == "timer" and first == flashTimer then
    flash = nil
    flashTimer = nil
  elseif event == "char" then
    if not heartId or prompt then input = input .. first end
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
      if choiceList then
        choiceScroll = math.max(0, choiceScroll - 3)
      else
        scroll = math.min(math.max(0, #lines - 1), scroll + 3)
      end
    elseif first == keys.pageDown then
      if choiceList then
        local pageSize = math.max(1, select(2, term.getSize()) - 11)
        choiceScroll = math.min(math.max(0, #choiceList.items - pageSize), choiceScroll + 3)
      else
        scroll = math.max(0, scroll - 3)
      end
    end
  elseif event == "mouse_scroll" then
    if choiceList then
      local pageSize = math.max(1, select(2, term.getSize()) - 11)
      choiceScroll = math.max(0, math.min(math.max(0, #choiceList.items - pageSize), choiceScroll + first))
    else
      scroll = math.max(0, math.min(#lines, scroll + first))
    end
  elseif event == "mouse_click" then
    local height = select(2, term.getSize())
    if prompt and prompt.kind == "scan" and scanStep and scanStep.canFinish
        and third == height - 1 and second <= 10 then
      submit("done")
    elseif prompt and prompt.kind == "choice" and choiceList
        and third >= 8 and third < height - 4 then
      local index = choiceScroll + third - 7
      if choiceList.items[index] then submit(tostring(index)) end
    elseif prompt and prompt.yesNo and third == height - 3 then
      if second <= 8 then submit("y") elseif second <= 16 then submit("n") end
    end
  elseif event == "term_resize" then
    scroll = 0
  end
end
