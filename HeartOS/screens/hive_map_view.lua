-- hive_map_view.lua
-- Visual hive map screen (Phase 3).
-- Renders the hive grid from hud.hive_map.grid in heart_config.lua:
--   - each hive is a FIXED 2x1 cell (just the two digits), ONLY those cells
--     are active/drawn/clickable
--   - stepX = CELL_W + gapX; stepY = CELL_H + gapY; every `sectionSize`
--     cells/rows form a section separated by `sectionGap` blank cells
--   - 48 cells per page, Prev/Next pagination, selection persists across pages
--   - cells without a hive are drawn but NOT clickable
--   - Signalise button drives HiveSignal (async relay cycle, non-blocking)
--   - Slot button reserved ("Coming Soon"), Back returns to the hive menu.
-- Background and button positions come from hud.hive_map.

local MonitorUtil = require("screens/monitor_util")
local HudUtil = require("screens/hud_util")
local ChatUtil = require("chat_util")
local ConfigManager = require("config_manager")
local HiveSignal = require("hive_signal")

local HiveMapView = {}

local HIVES_FILE = "hives_map.lua"
local SLOTS_PER_PAGE = 48
local MAX_ID = 96
-- Hive cell size (digits): 2 wide x 1 tall. Only these cells are active.
local CELL_W = 2
local CELL_H = 1

-- ==================== GRID MATH ====================
-- Slot numbers are 1..48 (one page); the real hive id is (page * 48) + slot.
-- Each group is a "ring" of `cols` columns x `rows` rows of 2x1 cells.
--   stepX = CELL_W + gapX  (horizontal step, incl. the blank columns)
--   stepY = CELL_H + gapY  (vertical step,    incl. the blank rows)
-- Groups 1/3 (bottom_up / top_down): the two columns sit side by side with a
--   gapX spacer; rows stack every stepY; every `sectionSize` rows form a
--   section, sections separated by `sectionGap` blank rows.
-- Group 2 (left_right): columns step every stepX, rows every stepY,
--   every `sectionSize` columns form a section, separated by sectionGap cols.
--- @param grid table hud.hive_map.grid
--- @param slot number slot number on the current page (1..48)
--- @return number|nil x, number|nil y, number|nil CELL_W, number|nil CELL_H
local function cellForSlot(grid, slot)
  for _, g in ipairs(grid.groups or {}) do
    if slot >= g.idStart and slot <= g.idStart + g.rows * g.cols - 1 then
      local idx = slot - g.idStart
      local order = g.order or "top_down"
      local gapX = g.gapX or g.gap or 1
      local gapY = g.gapY or g.gap or 1
      local sectionGap = g.sectionGap or 1
      local sectionSize = g.sectionSize or 4
      local stepX = CELL_W + gapX
      local stepY = CELL_H + gapY

      local x, y
      if order == "bottom_up" then
        -- Columns side by side; pairs counted bottom-up. Sections are blocks:
        -- the lower block (ids 1-8) sits at the bottom, upper block above it.
        local pair = math.floor(idx / g.cols)
        local inPair = idx % g.cols
        local s = math.floor(pair / sectionSize)
        local k = pair % sectionSize
        local fromTop = math.max(1, math.floor(g.rows / sectionSize)) - 1 - s
        local blockTopY = g.startY + fromTop * (sectionSize * stepY + sectionGap)
        local within = sectionSize - 1 - k
        x = g.startX + inPair * stepX
        y = blockTopY + within * stepY
      elseif order == "top_down" then
        -- Same as bottom_up but pairs counted top-down.
        local pair = math.floor(idx / g.cols)
        local inPair = idx % g.cols
        local s = math.floor(pair / sectionSize)
        local k = pair % sectionSize
        local blockTopY = g.startY + s * (sectionSize * stepY + sectionGap)
        x = g.startX + inPair * stepX
        y = blockTopY + k * stepY
      else -- "left_right"
        -- Columns side by side; sections are horizontal blocks of columns.
        local colIdx = math.floor(idx / g.rows)
        local rowIdx = idx % g.rows
        local s = math.floor(colIdx / sectionSize)
        local k = colIdx % sectionSize
        x = g.startX + s * (sectionSize * stepX + sectionGap) + k * stepX
        y = g.startY + rowIdx * stepY
      end

      return x, y, CELL_W, CELL_H
    end
  end
  return nil, nil, nil, nil
end

-- ==================== MAP DATA ====================

--- Load the hives map: which hive ids exist and their relay names.
--- @return table present set of existing hive ids
--- @return table relaysById id -> relay peripheral name
--- @return number maxId highest existing hive id
local function loadMapData()
  local present = {}
  local relaysById = {}
  local maxId = 0

  local map = ConfigManager.loadFromFile(HIVES_FILE)
  if type(map) == "table" then
    for _, hive in ipairs(map) do
      local id = hive and hive.id
      if type(id) == "number" and id >= 1 then
        present[id] = true
        if type(hive.relay) == "string" and hive.relay ~= "" then
          relaysById[id] = hive.relay
        end
        if id > maxId then maxId = id end
      end
    end
  end

  return present, relaysById, maxId
end

-- ==================== LEGACY FALLBACK (no grid config) ====================

--- Minimal loop: only signal/slot/back buttons, no grid.
--- @return nil
local function legacyLoop(mon, heartConfig)
  while true do
    MonitorUtil.clearScreen(mon)
    HudUtil.drawBackground(mon, "hive_map")
    HudUtil.drawLabel(mon, "hive_map", "title")

    local buttons = {}
    for _, btnId in ipairs({ "signal", "slot", "back" }) do
      local btn = HudUtil.createButton(mon, "hive_map", btnId)
      if btn then
        table.insert(buttons, btn)
        MonitorUtil.drawButton(mon, btn, false)
      end
    end

    local ok, event, side, tx, ty = pcall(os.pullEvent, "monitor_touch")
    if ok and side == heartConfig.main_monitor then
      local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
      if pressed then
        if pressed.action == "back" then
          return
        elseif pressed.action == "signal" then
          ChatUtil.sendSuccess("Signal pressed (action stub).")
        end
      end
    end
  end
end

-- ==================== MAIN ENTRY ====================

function HiveMapView.run(mon, heartConfig)
  if not ChatUtil.isAvailable() then
    ChatUtil.init(nil)
  end

  local hud = (heartConfig.hud and heartConfig.hud.hive_map) or {}
  local grid = hud.grid

  if not grid or type(grid.groups) ~= "table" or #grid.groups == 0 then
    legacyLoop(mon, heartConfig)
    return
  end

  local present, relaysById, maxId = loadMapData()

  if maxId > MAX_ID then
    ChatUtil.sendError("Map exceeds " .. MAX_ID .. " hives. Only ids 1-" .. MAX_ID .. " are shown.")
  end

  local selected = {}          -- global selection: hive id -> true
  local currentPage = 0        -- 0-based
  local pageCount = math.max(1, math.ceil(math.min(maxId, MAX_ID) / SLOTS_PER_PAGE))
  local lastSignalAt = 0       -- debounce: wall time of the last signal tap

  local cellColors = grid.cellColors or {}
  local colPresent = HudUtil.color(cellColors.present or "green")
  local colAbsent = HudUtil.color(cellColors.absent or "gray")
  local colSelected = HudUtil.color(cellColors.selected or "yellow")
  local idFormat = grid.idFormat or "%02d"

  local function formatId(id)
    return string.format(idFormat, id)
  end

  -- ==================== SIGNAL HELPERS ====================

  local function selectedRelayNames()
    local names = {}
    for id, _ in pairs(selected) do
      if relaysById[id] then
        table.insert(names, { id = id, name = relaysById[id] })
      end
    end
    table.sort(names, function(a, b) return a.id < b.id end)
    local out = {}
    for _, item in ipairs(names) do
      table.insert(out, item.name)
    end
    return out
  end

  local function canSignal()
    return #selectedRelayNames() > 0 and not HiveSignal.isRunning()
  end

  local function startSignal()
    -- Guard: never restart while a cycle is running. If we got here while
    -- running (fast double-tap race), report the real remaining time instead.
    if HiveSignal.isRunning() then
      ChatUtil.sendErrorImmediate("Signal already running. Try again in " .. tostring(HiveSignal.getRemainingSeconds()) .. "s.")
      return
    end
    local relays = selectedRelayNames()
    if #relays == 0 then
      ChatUtil.sendErrorImmediate("No selected hive has a relay block.")
      return
    end
    local cycle = hud.signal_cycle or {}
    local ok, err = HiveSignal.start(cycle, relays)
    if not ok then
      if HiveSignal.isRunning() then
        ChatUtil.sendErrorImmediate("Signal already running. Try again in " .. tostring(HiveSignal.getRemainingSeconds()) .. "s.")
      else
        ChatUtil.sendErrorImmediate("Signal failed to start: " .. tostring(err))
      end
    end
  end

  -- ==================== RENDER ====================

  local function drawPageIndicator()
    local page = hud.page or {}
    local w, h = mon.getSize()
    local text = "Page " .. (currentPage + 1) .. "/" .. pageCount
    local x = page.x
    if not x then
      x = math.floor((w - #text) / 2) + 1
      if x < 1 then x = 1 end
    end
    local y = (page.y or (h - 1)) + ((page.line or 1) - 1)
    local bg = page.bgColor and HudUtil.color(page.bgColor)
    MonitorUtil.drawText(mon, x, y, text, HudUtil.color(page.textColor or "white"), bg)
  end

  local function render()
    MonitorUtil.clearScreen(mon)
    HudUtil.drawBackground(mon, "hive_map")
    HudUtil.drawLabel(mon, "hive_map", "title")

    local buttons = {}

    -- Grid cells for the current page.
    local startId = currentPage * SLOTS_PER_PAGE + 1
    for slot = 1, SLOTS_PER_PAGE do
      local id = startId + slot - 1
      local x, y, cw, ch = cellForSlot(grid, slot)
      if x then
        local color, textColor
        if selected[id] then
          color, textColor = colSelected, colors.black
        elseif present[id] then
          color, textColor = colPresent, colors.white
        else
          color, textColor = colAbsent, colors.black
        end
        local btn = MonitorUtil.createButton(x, y, cw, formatId(id), tostring(id), color, ch)
        btn.textColor = textColor
        MonitorUtil.drawButton(mon, btn, false)
        -- Only hives present in the map are clickable.
        if present[id] then
          table.insert(buttons, btn)
        end
      end
    end

    -- Footer: Signal (disabled look when unusable), Slot, Prev/Next, Back.
    local signalBtn = HudUtil.createButton(mon, "hive_map", "signal")
    if signalBtn then
      if not canSignal() then
        signalBtn.color = colors.gray
        signalBtn.textColor = colors.white
      end
      table.insert(buttons, signalBtn)
      MonitorUtil.drawButton(mon, signalBtn, false)
    end

    local slotBtn = HudUtil.createButton(mon, "hive_map", "slot")
    if slotBtn then
      table.insert(buttons, slotBtn)
      MonitorUtil.drawButton(mon, slotBtn, false)
    end

    if pageCount > 1 then
      if currentPage > 0 then
        local prevBtn = HudUtil.createButton(mon, "hive_map", "prev")
        if prevBtn then
          table.insert(buttons, prevBtn)
          MonitorUtil.drawButton(mon, prevBtn, false)
        end
      end
      if currentPage < pageCount - 1 then
        local nextBtn = HudUtil.createButton(mon, "hive_map", "next")
        if nextBtn then
          table.insert(buttons, nextBtn)
          MonitorUtil.drawButton(mon, nextBtn, false)
        end
      end
    end

    local backBtn = HudUtil.createButton(mon, "hive_map", "back")
    if backBtn then
      table.insert(buttons, backBtn)
      MonitorUtil.drawButton(mon, backBtn, false)
    end

    drawPageIndicator()

    return buttons
  end

  -- ==================== EVENT LOOP ====================
  -- Delta render: the screen is fully redrawn only when something actually
  -- changed (page/selection/start|stop), NOT on every pullEvent. This avoids
  -- the monitor "blink" caused by a full redraw on each relay pulse/tap.
  local dirty = true
  local buttons = {}

  while true do
    if dirty then
      buttons = render()
      dirty = false
    end

    local ok, event, p1, p2, p3 = pcall(os.pullEvent)
    if not ok then
      break
    end

    if event == "timer" then
      HiveSignal.tick(p1)
      dirty = true
    elseif event == "monitor_touch" then
      local side, tx, ty = p1, p2, p3
      if side == heartConfig.main_monitor then
        local pressed = MonitorUtil.getPressedButton(buttons, tx, ty)
        if pressed then
          local action = pressed.action
          if action == "back" then
            HiveSignal.stop()
            return
          elseif action == "prev" then
            if currentPage > 0 then currentPage = currentPage - 1 end
            dirty = true
          elseif action == "next" then
            if currentPage < pageCount - 1 then currentPage = currentPage + 1 end
            dirty = true
          elseif action == "signal" then
            -- While a cycle runs: ALWAYS report the remaining time immediately,
            -- so a tap gives instant feedback (the countdown is accurate).
            if HiveSignal.isRunning() then
              ChatUtil.sendErrorImmediate("Signal already running. Try again in " .. tostring(HiveSignal.getRemainingSeconds()) .. "s.")
            else
              -- Not running: debounce rapid double-taps before starting.
              if os.time() - lastSignalAt >= 1 then
                lastSignalAt = os.time()
                startSignal()
                dirty = true
              end
            end
          elseif tonumber(action) then
            local id = tonumber(action)
            if selected[id] then
              selected[id] = nil
            else
              selected[id] = true
            end
            dirty = true
          end
        end
      end
    end
  end
end

return HiveMapView