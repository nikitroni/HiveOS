-- hive_signal.lua
-- Async relay signaling cycle for the hive map (Phase 3).
-- Cycle: ON for `on` s, then OFF for `off` s, repeated `cycles` times (default
-- 12 ~= 60 s at 3+2 s). After the last OFF the relays are turned off and the
-- cycle ends. Runs on os.startTimer / os.pullEvent timers, NEVER blocks the UI.
-- Relay output follows the ATM10 redstone relay API used in
--   lab_geneproduction.lua: relay.setOutput(side, bool) with an explicit side
--   (front/top/back/...) so the pulse goes ON in EVERY direction.
-- Fallback: relay.setOutput(bool) (all-sides digital) -> setBundledOutput ->
--   setAnalogOutput.

local ChatUtil = require("chat_util")

local HiveSignal = {}

-- Every side of the relay, so a pulse propagates in all directions.
local RELAY_SIDES = { "front", "back", "left", "right", "top", "bottom" }

local state = {
  relays = nil,        -- array of { name, p, method, useSides }
  phase = "idle",      -- "idle" | "on" | "off"
  timerId = nil,       -- id of the pending phase timer
  cycleOn = 2,
  cycleOff = 1,
  cyclesLeft = 0,      -- runs remaining (decremented after each ON/OFF cycle)
  remaining = 0,       -- whole seconds the button stays locked (decrements as ticks fire)
}

-- ==================== RELAY METHODS ====================

local function hasMethod(methods, method)
  for _, m in ipairs(methods) do
    if m == method then return true end
  end
  return false
end

--- Detect whether `setOutput` takes a side first (relay.setOutput(side, bool)).
--- Probes with a harmless OFF on "front": the call fails on boolean-only APIs.
--- @param p table wrapped peripheral
--- @return boolean
local function probeSideOutput(p)
  local ok = pcall(function()
    p.setOutput("front", false)
  end)
  return ok == true
end

--- Auto-detect the relay output method.
--- ATM10 relay API (lab_geneproduction) uses setOutput(side, bool); if the
--- probe fails we fall back to all-sides digital/bundled/analog.
--- @param name string peripheral name
--- @param p table wrapped peripheral
--- @return string method, boolean useSides
local function detectMethod(name, p)
  local ok, methods = pcall(function()
    return peripheral.getMethods(name)
  end)
  if ok and type(methods) == "table" then
    if hasMethod(methods, "setOutput") then
      return "setOutput", probeSideOutput(p)
    end
    if hasMethod(methods, "setBundledOutput") then return "setBundledOutput", false end
    if hasMethod(methods, "setAnalogOutput") then return "setAnalogOutput", false end
    return nil, false
  end
  -- Fallback: probe the wrapped peripheral directly.
  if type(p.setOutput) == "function" then
    return "setOutput", probeSideOutput(p)
  end
  if type(p.setBundledOutput) == "function" then return "setBundledOutput", false end
  if type(p.setAnalogOutput) == "function" then return "setAnalogOutput", false end
  return nil, false
end

--- Turn all relays ON or OFF via their detected method.
--- For side-based relays emits on every side so the pulse covers all
--- directions (front/back/left/right/top/bottom).
--- @param on boolean
local function setRelays(on)
  for _, r in ipairs(state.relays or {}) do
    pcall(function()
      if r.method == "setOutput" then
        if r.useSides then
          for _, side in ipairs(RELAY_SIDES) do
            r.p.setOutput(side, on)
          end
        else
          r.p.setOutput(on)
        end
      elseif r.method == "setBundledOutput" then
        r.p.setBundledOutput(on and colors.white or 0)
      elseif r.method == "setAnalogOutput" then
        r.p.setAnalogOutput(on and 15 or 0)
      end
    end)
  end
end

--- Fully stop the cycle (turn relays OFF, clear state). No chat messages.
local function forceStop()
  if state.timerId then
    os.cancelTimer(state.timerId)
    state.timerId = nil
  end
  setRelays(false)
  state.relays = nil
  state.phase = "idle"
  state.remaining = 0
end

-- ==================== CYCLE ====================

--- Start the signaling cycle.
--- Config cycle: { on, off, cycles }. Relays switch ON right away.
--- @param cycle table|nil timing config
--- @param relayNames table array of relay peripheral names
--- @return boolean, string|nil
function HiveSignal.start(cycle, relayNames)
  if HiveSignal.isRunning() then
    return false, "signal cycle already running"
  end

  local relays = {}
  for _, name in ipairs(relayNames) do
    local p = peripheral.wrap(name)
    if not p then
      ChatUtil.sendErrorImmediate("Relay peripheral not found: " .. ChatUtil.device(name))
    else
      local method, useSides = detectMethod(name, p)
      if not method then
        ChatUtil.sendErrorImmediate("Relay " .. ChatUtil.device(name) .. " has no output method.")
      else
        table.insert(relays, { name = name, p = p, method = method, useSides = useSides })
      end
    end
  end

  if #relays == 0 then
    return false, "no usable relays"
  end

  cycle = cycle or {}
  state.relays = relays
  state.cycleOn = cycle.on or 2
  state.cycleOff = cycle.off or 1
  state.cyclesLeft = cycle.cycles or 20
  -- The button stays locked for the whole planned cycle:
  -- on + off seconds, repeated `cycles` times.
  state.remaining = state.cyclesLeft * (state.cycleOn + state.cycleOff)
  state.phase = "on"
  setRelays(true)
  state.timerId = os.startTimer(state.cycleOn)

  local names = {}
  for _, r in ipairs(relays) do
    table.insert(names, ChatUtil.device(r.name))
  end
  ChatUtil.sendInfoImmediate("Signal started for " .. #relays .. " hive relay(s): " .. table.concat(names, ", "))
  ChatUtil.sendInfoImmediate("ON " .. state.cycleOn .. "s / OFF " .. state.cycleOff .. "s, " .. state.cyclesLeft .. " cycles.")

  return true
end

--- Advance the cycle by one timer. Called from the UI event loop.
--- @param timerId number id of the fired timer
function HiveSignal.tick(timerId)
  if not HiveSignal.isRunning() then return end
  if state.timerId ~= timerId then return end
  state.timerId = nil

  if state.phase == "on" then
    -- ON period finished: turn relays OFF, count the whole cycle done.
    setRelays(false)
    state.cyclesLeft = state.cyclesLeft - 1
    state.remaining = state.remaining - state.cycleOn
    if state.cyclesLeft <= 0 then
      ChatUtil.sendInfoImmediate("Signal finished for " .. #(state.relays or {}) .. " relay(s). Relays off.")
      forceStop()
      return
    end
    state.phase = "off"
    state.timerId = os.startTimer(state.cycleOff)
  elseif state.phase == "off" then
    -- OFF period finished: relays ON again.
    state.remaining = state.remaining - state.cycleOff
    setRelays(true)
    state.phase = "on"
    state.timerId = os.startTimer(state.cycleOn)
  end
end

--- Stop the cycle and turn all relays OFF. Safe to call any time.
function HiveSignal.stop()
  if not HiveSignal.isRunning() then return end
  forceStop()
  ChatUtil.sendInfoImmediate("Signal stopped. Relays off.")
end

--- Whether a cycle is currently running.
--- @return boolean
function HiveSignal.isRunning()
  return state.phase ~= "idle" and state.relays ~= nil
end

--- Remaining whole seconds the button will stay locked.
--- Decremented on every phase tick of the cycle (on + off), so it does NOT
--- depend on os.time() / os.clock() and never gets stuck at a constant.
--- @return number integer >= 0
function HiveSignal.getRemainingSeconds()
  if not HiveSignal.isRunning() then return 0 end
  return math.max(0, state.remaining)
end

return HiveSignal