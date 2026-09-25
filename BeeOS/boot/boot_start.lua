-- boot/boot_start.lua
-- Shared boot module for BeeOS.
-- Provides the boot animation, the infinite wait screen shown while the
-- terminal has no configs, config file helpers and the HeartOS rednet
-- config protocol (freeze / update_config / unfreeze / status / busy?).

local RednetProtocol = require("rednet_protocol")

local BEEOS_CONFIG_FILE = "beeos_config.lua"
local HIVE_MAP_FILE = "hives_map.lua"

local currentStatus = "free"
local frozen = false
local release = false

-- ==================== REDNET ====================

-- Open the modem and register this terminal as host of beeos/main.
local function openRednet()
  local ok, err = RednetProtocol.host("beeos", "main")
  if not ok then
    print("BeeOS rednet host failed: " .. tostring(err))
    return false
  end
  return true
end

-- ==================== CONFIG FILE HELPERS ====================

local function saveConfigTable(data, path)
  if type(data) ~= "table" then return false end
  local file = fs.open(path, "w")
  if not file then return false end
  file.write("return " .. textutils.serialize(data))
  file.close()
  return true
end

local function loadConfigTable(path)
  if not fs.exists(path) then return nil end
  local handler, err = loadfile(path)
  if not handler then return nil end
  local ok, result = pcall(handler)
  if ok and type(result) == "table" then
    return result
  end
  return nil
end

-- ==================== STATUS SETTINGS ====================

local function setCurrentStatus(status)
  currentStatus = status
end

local function getCurrentStatus()
  return currentStatus
end

local function isFrozen()
  return frozen
end

-- ==================== REDNET CONFIG PROTOCOL ====================

-- Handles one HeartOS message. Returns an action for the caller:
--   "reload" - configs were saved, the terminal must restart its screens
--   "freeze" - the terminal must go into the wait / boot screen state
--   nil      - no action needed (status/freeze-state handled inline)
local function handleConfigMessage(sender, message)
  if type(message) == "string" then
    if message == "busy?" or message == "status" then
      rednet.send(sender, currentStatus)
    elseif message == "freeze" then
      if currentStatus == "busy" then
        -- Terminal is busy with a task (sending bees): do not freeze,
        -- Edit must not open and interrupt the process.
        rednet.send(sender, "wait")
        return nil
      end
      frozen = true
      rednet.send(sender, "frozen")
      return "freeze"
    elseif message == "unfreeze" then
      frozen = false
      rednet.send(sender, "running")
    end
    return nil
  end

  if type(message) ~= "table" or type(message.command) ~= "string" then
    return nil
  end

  local command = message.command
  if command == "request_config" then
    if type(message.data) == "table" then
      if message.data.command == "hives_map" then
        saveConfigTable(message.data.data, HIVE_MAP_FILE)
      else
        saveConfigTable(message.data, BEEOS_CONFIG_FILE)
      end
    end
    rednet.send(sender, "config_received")
    return "reload"
  end

  if command == "update_config" then
    if currentStatus == "busy" then
      rednet.send(sender, "wait")
      return nil
    end
    if type(message.data) == "table" then
      if message.data.command == "hives_map" then
        saveConfigTable(message.data.data, HIVE_MAP_FILE)
      else
        saveConfigTable(message.data, BEEOS_CONFIG_FILE)
      end
    end
    rednet.send(sender, "config_updated")
    return "reload"
  end

  return nil
end

-- ==================== WAIT / BOOT SCREEN ====================

local bootCfg = nil

local function parsePattern(pattern, startX, startY)
  local result = {}
  for rowIdx, line in ipairs(pattern) do
    local y = startY + rowIdx - 1
    result[y] = {}
    for colIdx = 1, #line do
      local char = line:sub(colIdx, colIdx)
      if char ~= " " then
        local x = startX + colIdx - 1
        result[y][x] = { char = char, fg = colors.yellow }
      end
    end
  end
  return result
end

local function loadBootConfig()
  if not bootCfg then
    bootCfg = require("boot/HUD_boot_config")
    if bootCfg.honeycomb_pattern then
      bootCfg.foreground = parsePattern(bootCfg.honeycomb_pattern, bootCfg.pattern_start.x, bootCfg.pattern_start.y)
    end
  end
  return bootCfg
end

local function prepareScreen(mon, cfg)
  cfg = cfg or loadBootConfig()
  local bg = paintutils.loadImage("boot/HUD_boot.nfp")
  if not bg then
    error("HUD_boot.nfp not found")
  end
  mon.setTextScale(1.0)
  mon.setBackgroundColor(colors.gray)
  mon.clear()
  local oldTerm = term.redirect(mon)
  -- drawImage + guaranteed term restore (even on error)
  local ok, err = pcall(paintutils.drawImage, bg, 1, 1)
  term.redirect(oldTerm)
  if not ok then error(tostring(err)) end
  return cfg
end

local function drawProgress(mon, cfg, percent, fillColor)
  local area = cfg.progress_area
  local width = area.maxX - area.minX + 1
  local fill = math.floor(percent / 100 * width + 0.5)
  if fill > width then fill = width end

  for y = area.minY, area.maxY do
    for x = area.minX, area.maxX do
      mon.setCursorPos(x, y)
      if x - area.minX < fill then
        mon.setBackgroundColor(fillColor or colors.orange)
      else
        mon.setBackgroundColor(colors.lightGray)
      end
      local cell = cfg.foreground[y] and cfg.foreground[y][x]
      if cell then
        mon.setTextColor(cell.fg)
        mon.write(cell.char)
      else
        mon.write(" ")
      end
    end
  end

  local pStr = string.format("%03d", percent)
  for i, pos in ipairs(cfg.percent_digits) do
    mon.setCursorPos(pos.x, pos.y)
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.yellow)
    mon.write(pStr:sub(i, i))
  end

  mon.setCursorPos(cfg.percent_sign.x, cfg.percent_sign.y)
  mon.setBackgroundColor(colors.gray)
  mon.setTextColor(colors.yellow)
  mon.write("%")
end

-- Full wait frame redraw, used while frozen inside running screens.
local function drawBootFrame(mon)
  local ok = pcall(function()
    local cfg = loadBootConfig()
    local bg = paintutils.loadImage("boot/HUD_boot.nfp")
    if not bg then error("HUD_boot.nfp not found") end
    mon.setTextScale(1.0)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.gray)
    mon.clear()
    local oldTerm = term.redirect(mon)
    local okI, errI = pcall(paintutils.drawImage, bg, 1, 1)
    term.redirect(oldTerm)
    if not okI then error(tostring(errI)) end
    local p = (os.clock() % 4) / 4
    local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
    drawProgress(mon, cfg, math.floor(wave * 100))
  end)
  return ok
end

-- Standard boot animation with a fixed duration.
local function bootMenu(mon, duration)
  duration = duration or 10
  local cfg = prepareScreen(mon)
  local start = os.clock()
  local lastPercent = -1

  while os.clock() - start < duration do
    local p = (os.clock() - start) / duration
    local percent = math.floor(p * 100)

    if percent ~= lastPercent then
      drawProgress(mon, cfg, percent)
      lastPercent = percent
    end
    sleep(0.05)
  end

  drawProgress(mon, cfg, 100, colors.green)
  sleep(0.2)
end

-- Infinite wait loop shown while the terminal has no configs (or while
-- frozen). `monitors` may be empty: then no screen is used and the loop
-- only listens for HeartOS config messages (no monitor is taken over).
-- `onStatusChange` (optional) is called after each received config so the
-- caller can redraw the terminal status. `onMessage` (optional) is called for
-- every received rednet message before the config protocol runs, so the caller
-- can react to non-config messages (e.g. lab_complete) that would otherwise be
-- swallowed by this loop. Finishes the bars to 100% before returning when
-- monitors are present.
local function waitForConfig(monitors, isReady, onStatusChange, onMessage)
  release = false
  local threads = {}
  local cfg = #monitors > 0 and loadBootConfig() or nil

  for _, mon in ipairs(monitors) do
    table.insert(threads, function()
      pcall(prepareScreen, mon, cfg)
      while not release do
        -- Smooth animation 0% -> 100% -> 0% (sine wave, period 4 s).
        -- Draw every frame exactly as in the verified first version.
        local p = (os.clock() % 4) / 4
        local wave = 0.5 - 0.5 * math.cos(p * math.pi * 2)
        pcall(drawProgress, mon, cfg, math.floor(wave * 100))
        sleep(0.05)
      end
      pcall(drawProgress, mon, cfg, 100, colors.green)
      sleep(0.2)
    end)
  end

  table.insert(threads, function()
    while true do
      local _, sender, message = os.pullEvent("rednet_message")
      if onMessage then pcall(onMessage, sender, message) end
      local action = handleConfigMessage(sender, message)
      if action then
        if onStatusChange then onStatusChange() end
      end
      -- Exit when the readiness condition is met
      -- (e.g. unfreeze or all configs arrived)
      local ok, ready = pcall(isReady)
      if ok and ready then
        break
      end
    end
    release = true
  end)

  parallel.waitForAll(table.unpack(threads))
  release = false
end

return {
  show = bootMenu,
  waitForConfig = waitForConfig,
  openRednet = openRednet,
  handleConfigMessage = handleConfigMessage,
  saveConfigTable = saveConfigTable,
  loadConfigTable = loadConfigTable,
  setCurrentStatus = setCurrentStatus,
  getCurrentStatus = getCurrentStatus,
  isFrozen = isFrozen,
  drawBootFrame = drawBootFrame,
  prepareScreen = prepareScreen,
  drawProgress = drawProgress,
  loadBootConfig = loadBootConfig,
}