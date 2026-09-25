-- LAB_main.lua
-- Main executable file of the laboratory terminal (LabOS).
--
-- Initializes peripherals via lab_config_loader (static
-- lab_lib.lua + dynamic labos_config.lua from HeartOS), brings up
-- rednet, accepts configs via the HeartOS protocol (freeze / update_config /
-- unfreeze / status / busy?), reports its status (free/busy) and draws
-- the wait screen (HUD_Lab_Boot.nfp) while frozen or waiting for configs.
--
-- Single event owner - the main loop (os.pullEvent without a filter),
-- so rednet messages are never lost; rendering is done in this
-- same loop on a timer.

local ConfigLoader = require("lab_config_loader")
local lib = ConfigLoader.load()

local Utils = require("lab_utils")
local HUD = require("lab_hud")
local Buttons = require("lab_buttons")
local Processor = require("lab_processor")
local GeneProduction = require("lab_geneproduction")
local Breeding = require("lab_breeding")
local Boot = require("lab_boot")
local RednetProtocol = require("rednet_protocol")

-- ==================== GLOBAL VARIABLES ====================
local running = true
local frame = 0
local mode = "wait"
local logBuffer = {}
local bees = {}
local geneCounts = {}
local neededCounts = {}

local targetHive = nil
--- @type string|nil
local targetHiveBlock = nil
local lastSenderId = nil
local lastExpectedCount = nil
local processing = false

-- HeartOS protocol
local currentStatus = "free"
local frozen = false
local waitPrepared = false  -- redraw of the wait background when the mode changes
-- Safeguard against a lost unfreeze: if the freeze lasts too long without
-- active configuration (no config arrives), we lift it automatically.
local frozenSince = nil
local FROZEN_MAX_SECONDS = 60
local lastConfigActivity = os.clock()
-- WIN screen timer (show ~5 s after a successful upgrade, then WAIT)
local winSince = 0

-- State file
local STATE_FILE = "lab_state.dat"
local cancelRequested = false

-- Dynamic config from HeartOS (saved to labos_config.lua)
local LABOS_CONFIG_FILE = "labos_config.lua"

-- ==================== LOG HELPER FUNCTIONS ====================
local LOG_DIR = "_logs"
local LOG_FILE = "_logs/lab_os.log"
local function ensureLabLogDir()
    if not fs.exists(LOG_DIR) then
        pcall(fs.makeDir, LOG_DIR)
    end
end

-- Writes both to the screen buffer (HUD) and to a file (for debugging)
local function addLogLine(line)
    if type(line) ~= "string" then
        line = tostring(line)
    end
    line = line:gsub("§.", "")

    -- To the file (always, without loss)
    ensureLabLogDir()
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(os.date("%H:%M:%S") .. " " .. line)
        f.close()
    end

    -- To the HUD screen buffer
    table.insert(logBuffer, line)
    if #logBuffer > 9 then
        table.remove(logBuffer, 1)
    end
end

-- ==================== STATE LOADING AND SAVING ====================
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local content = file.readAll()
        file.close()
        local ok, state = pcall(textutils.unserialize, content)
        if ok and state then
            targetHive = state.hive_id
            targetHiveBlock = state.hive_block
            lastSenderId = state.sender_id
            lastExpectedCount = state.expected_count
            addLogLine("Loaded previous state from " .. STATE_FILE)
        else
            print("Failed to load state, ignoring.")
        end
    end
end

local function saveState()
    local state = {
        hive_id = targetHive,
        hive_block = targetHiveBlock,
        sender_id = lastSenderId,
        expected_count = lastExpectedCount,
    }
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

local function clearState()
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end
    targetHive = nil
    targetHiveBlock = nil
    lastSenderId = nil
    lastExpectedCount = nil
end

-- ==================== DATA REFRESH ====================
local function refreshData()
    local okBees, resBees = pcall(Utils.getBeesFromBarrel)
    if okBees then bees = resBees else bees = {} addLogLine("Error reading barrel") end
    local okCounts, resCounts = pcall(Utils.getGeneCountsFromIndexer)
    if okCounts then geneCounts = resCounts else geneCounts = {} addLogLine("Error reading indexer") end
    -- neededCounts is computed without reading peripherals, always safe
    do
        local ok, res = pcall(Utils.calculateNeededGenes, bees)
        if ok then neededCounts = res else neededCounts = {} end
    end
end

-- ==================== HEARTOS PROTOCOL ====================

-- Save the dynamic config from HeartOS and reassemble the library
local function saveDynamicConfig(data)
    if type(data) ~= "table" then return false end
    local file = fs.open(LABOS_CONFIG_FILE, "w")
    if not file then return false end
    file.write("return " .. textutils.serialize(data))
    file.close()
    -- Modules cache lab_lib, so we reload them after reassembly
    package.loaded["lab_lib"] = nil
    package.loaded["lab_hud"] = nil
    package.loaded["lab_buttons"] = nil
    package.loaded["lab_processor"] = nil
    package.loaded["lab_utils"] = nil
    package.loaded["lab_breeding"] = nil
    package.loaded["lab_geneproduction"] = nil
    return true
end

-- Handles one rednet message from HeartOS.
-- Returns: "config_reloaded" (config accepted, UI/peripherals need updating),
--   nil (just replied).
local function handleConfigMessage(sender, message)
    -- Debug output to the terminal console (shows what is happening)
    if type(message) == "string" then
        addLogLine("Net<- '" .. tostring(message) .. "'")
        if message == "busy?" or message == "status" then
            addLogLine("STATUS? -> " .. tostring(currentStatus))
            rednet.send(sender, currentStatus)
        elseif message == "freeze" then
            if currentStatus == "busy" then
                -- Terminal is busy with a task: do not freeze, Edit must not open
                rednet.send(sender, "wait")
            else
                frozen = true
                frozenSince = os.clock()
                rednet.send(sender, "frozen")
            end
        elseif message == "unfreeze" then
            frozen = false
            frozenSince = nil
            waitPrepared = false
            rednet.send(sender, "running")
        end
        return nil
    end

    if type(message) ~= "table" or type(message.command) ~= "string" then
        return nil
    end

    local command = message.command
    if command == "request_config" then
        addLogLine("Net<- request_config")
        if saveDynamicConfig(message.data) then
            rednet.send(sender, "config_received")
        else
            rednet.send(sender, "config_error")
        end
        return "config_reloaded"
    end

    if command == "update_config" then
        addLogLine("Net<- update_config")
        if currentStatus == "busy" then
            rednet.send(sender, "wait")
            return nil
        end
        lastConfigActivity = os.clock()
        if saveDynamicConfig(message.data) then
            rednet.send(sender, "config_updated")
        else
            rednet.send(sender, "config_error")
        end
        return "config_reloaded"
    end

    return nil
end

-- ==================== TASK QUEUE (declared before onBeeOut etc.) ====================
-- Long tasks (Bee return / upgrade / production / breeding)
-- run in a separate taskWorker thread so as not to block the main
-- loop (render + events). runTask puts a task into the queue.
local taskQueue = {}
local runTask = nil   -- assigned below, but visible to everyone
local taskWorker = nil

-- ==================== BUTTON HANDLERS ====================
local function setBusy(busy)
    processing = busy
    if busy then
        currentStatus = "busy"
    else
        currentStatus = "free"
    end
end

-- Notify the LabOS chat box (shared helper; red for errors, green otherwise).
local function notifyChat(msg, isError)
    Utils.sendChat(msg, isError)
end

local function onBeeOut()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    if not targetHiveBlock then
        addLogLine("!ERROR: No target hive remembered.")
        return
    end
    if not lastSenderId then
        addLogLine("!ERROR: No sender ID.")
        return
    end
    -- Capture the guarded value: the closure below may run after targetHiveBlock
    -- is cleared, so keep a local copy that LuaLS knows is a non-nil string.
    local hiveBlockName = targetHiveBlock
    -- Bee return runs in taskWorker (does not block rednet)
    setBusy(true)
    runTask(function()
        addLogLine("Returning bees...")
        --- @type table
        local hive = peripheral.wrap(hiveBlockName)
        if not hive then
            addLogLine("!ERROR: Hive not found: " .. hiveBlockName)
            return
        end

        -- Return bees from the barrel to the hive
        --- @type table
        local barrel = peripheral.wrap(lib.peripherals.lab_chest)
        if not barrel then
            addLogLine("!ERROR: Lab chest not found: " .. tostring(lib.peripherals.lab_chest))
            return
        end

        local function isBeeCage(item)
            return Utils.isCageItem(item)
        end

        -- Check: the cage is EMPTY (no bee inside).
        -- The hive ejects an empty cage after processing a returned bee,
        -- usually as sturdy_bee_cage without bee data (sometimes bee_cage).
        local function isCageEmpty(item)
            if not isBeeCage(item) then return false end
            if item.name == "productivebees:bee_cage" then return true end
            -- sturdy_bee_cage: filled if there is a bee in custom_data
            local comp = item.components
            if not comp then return true end
            local cd = comp["minecraft:custom_data"]
            if not cd then return true end
            return not cd.bee_type and not cd.type
        end

        -- Diagnostics: barrel contents BEFORE return
        addLogLine("Barrel before return:")
        for slot = 1, barrel.size() do
            local item = barrel.getItemDetail(slot)
            if item then
                addLogLine(string.format("  slot %d: %s x%d", slot, item.name, item.count))
            end
        end

        -- Return: the hive accepts cages into slot 12 (input slot), one at a time.
        -- We do not move the whole stack - the hive processes cages one by one.
        local moved = 0
        for slot = 1, barrel.size() do
            local item = barrel.getItemDetail(slot)
            if isBeeCage(item) then
                local remaining = item.count
                local attempts = 0
                while remaining > 0 and attempts < 15 do
                    attempts = attempts + 1
                    local slot12Item = hive.getItemDetail(12)
                    if slot12Item then
                        if slot12Item.name == "productivebees:bee_cage" then
                            -- An empty cage got into slot 12 - move it to storage
                            -- to free the hive input slot. (We do not touch
                            -- sturdy_bee_cage in slot 12: it is a filled cage that
                            -- the hive is still processing.)
                            local resourceChestName12 = lib.peripherals.resource_chest
                            --- @type table
                            local c12 = peripheral.wrap(resourceChestName12)
                            if c12 then
                                local cleared = hive.pushItems(resourceChestName12, 12)
                                if cleared > 0 then
                                    addLogLine("Cleared empty cage from hive slot 12")
                                end
                            end
                        else
                            addLogLine("!WARN: hive slot 12 busy (filled cage), waiting")
                        end
                        if hive.getItemDetail(12) then sleep(1) end
                    else
                        local m = barrel.pushItems(hiveBlockName, slot, 1, 12)
                        if m > 0 then
                            moved = moved + m
                            remaining = remaining - m
                            addLogLine(string.format("Returned %d bees to hive.", moved))
                            sleep(0.5)
                        else
                            addLogLine("!WARN: slot " .. slot .. " bee not moved to " .. hiveBlockName)
                            break
                        end
                    end
                end
                if remaining > 0 then
                    addLogLine(string.format("!WARN: %d cages stuck in barrel slot %d", remaining, slot))
                end
            end
        end

        -- Diagnostics: barrel contents AFTER return
        local leftInBarrel = 0
        addLogLine("Barrel after return:")
        for slot = 1, barrel.size() do
            local item = barrel.getItemDetail(slot)
            if item then
                addLogLine(string.format("  slot %d: %s x%d", slot, item.name, item.count))
                if isBeeCage(item) then leftInBarrel = leftInBarrel + item.count end
            end
        end
        addLogLine(string.format("Bees returned: %d, expected: %s, left in barrel: %d", moved, tostring(lastExpectedCount), leftInBarrel))

        -- Take empty cages from the hive to storage.
        -- After returning a bee, the hive ejects an empty cage
        -- (can be either bee_cage or sturdy_bee_cage without bee data).
        -- We collect with retries: the ejection does not happen instantly.
        --- @type table
        local resourceChest = peripheral.wrap(lib.peripherals.resource_chest)
        local collectedEmpty = 0
        if not resourceChest then
            addLogLine("!WARN: resource chest not found, empty cages remain in hive")
        else
            for attempt = 1, 5 do
                local found = false
                for slot = 3, 11 do
                    local item = hive.getItemDetail(slot)
                    if item and isCageEmpty(item) then
                        found = true
                        local m = hive.pushItems(lib.peripherals.resource_chest, slot)
                        if m > 0 then
                            collectedEmpty = collectedEmpty + m
                            addLogLine(string.format("Returned empty cage from slot %d", slot))
                        else
                            addLogLine(string.format("!WARN: empty cage in hive slot %d not moved (resource chest full?)", slot))
                        end
                    end
                end
                -- Also free slot 12 from an empty cage
                local s12 = hive.getItemDetail(12)
                if s12 and isCageEmpty(s12) then
                    found = true
                    local m = hive.pushItems(lib.peripherals.resource_chest, 12)
                    if m > 0 then
                        collectedEmpty = collectedEmpty + m
                        addLogLine("Returned empty cage from hive slot 12")
                    end
                end
                if not found then break end
                if attempt < 5 then sleep(1) end
            end
            addLogLine(string.format("Empty cages collected from hive: %d", collectedEmpty))
        end

        -- Notify BeeOS about the return (clears the lock). We always go to WAIT.
        if moved > 0 then
            rednet.send(lastSenderId, { type = "lab_complete", hive_id = targetHive, bee_count = moved })
            addLogLine(string.format("Sent lab_complete to %s (hive %s, %d bees)", tostring(lastSenderId), tostring(targetHive), moved))
            notifyChat(string.format("%d bees returned to hive %s", moved, tostring(targetHive)))
        else
            addLogLine("!WARN: no bees moved, lock may stay in BeeOS")
            notifyChat("Bees return failed - no bees moved", true)
        end
        clearState()
        mode = "wait"
    end)
end

-- ==================== TASKS (EXECUTED IN A SEPARATE THREAD) ====================
-- IMPORTANT: long tasks (gene production / upgrade / breeding) must NOT
-- block the main loop, otherwise sleep() inside them will swallow rednet messages
-- (busy?/freeze) due to the filter, and HeartOS will not get a reply. That is why tasks
-- are queued and executed by the taskWorker thread.
runTask = function(taskFn)
    table.insert(taskQueue, taskFn)
end

-- Executes tasks from the queue (with guaranteed busy reset).
-- Runs while there are tasks; otherwise spins on pullEvent (without blocking rednet).
taskWorker = function()
    while running do
        if #taskQueue > 0 then
            local taskFn = table.remove(taskQueue, 1)
            local ok, err = pcall(function()
                taskFn()
            end)
            if not ok then
                print("LAB task error: " .. tostring(err))
                if type(err) == "table" then
                    print(textutils.serialize(err))
                end
                addLogLine("!ERROR: " .. tostring(err))
            end
            setBusy(false)
        else
            os.pullEvent()
        end
    end
end

local function onGeneUpgrade()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Start upgrade.")
        mode = "log"

        -- Collect non-elite bees in the lab chest
        local beesList = Utils.getBeesFromBarrel()
        local nonElite = {}
        for _, bee in ipairs(beesList) do
            if not Utils.isElite(bee) then
                table.insert(nonElite, bee)
            end
        end

        if #nonElite == 0 then
            addLogLine("No bees to upgrade")
            notifyChat("No bees to upgrade", false)
            mode = "wait"
            return
        end

        -- Pre-check genes for the whole batch and produce the missing amount
        local need = Utils.calculateNeededGenes(nonElite)
        local have = Utils.getGeneCountsFromIndexer()
        local attrsMissing = {}
        for attr, n in pairs(need) do
            if n > (have[attr] or 0) then
                table.insert(attrsMissing, attr)
            end
        end

        table.sort(attrsMissing)

        local genesShort = false
        if #attrsMissing > 0 then
            local msg = "Producing genes: " .. table.concat(attrsMissing, ", ")
            addLogLine(msg)
            notifyChat(msg, false)
            GeneProduction.runProduction(function(entry) addLogLine("" .. entry) end, {
                targets = need,
                maxCycles = 200,
            })
            have = Utils.getGeneCountsFromIndexer()
            for attr, n in pairs(need) do
                if (have[attr] or 0) < n then
                    genesShort = true
                end
            end
            if genesShort then
                notifyChat("Gene production incomplete", true)
            end
        end

        -- Pre-check honey_treat (one per bee)
        local honey = Utils.countItem("productivebees:honey_treat")
        if honey <= 0 then
            addLogLine("No honey_treat, aborting upgrade.")
            notifyChat("No honey_treat. Upgrade aborted.", true)
            mode = "wait"
            return
        end
        local limit = math.min(honey, #nonElite)

        local successCount, totalCount, partial = Processor.processAllBees(
            function(msg) addLogLine(msg) end, { maxBees = limit })

        local limited = limit < #nonElite
        if successCount == totalCount and totalCount > 0 and not partial and not genesShort and not limited then
            notifyChat(string.format("Upgrade complete: %d/%d", successCount, totalCount), false)
            mode = "win"
            winSince = os.clock()   -- show WIN ~5 s, then return to WAIT
        else
            addLogLine(string.format("Incomplete: %d/%d ok (partial=%s genesShort=%s limited=%s)",
                successCount, totalCount, tostring(partial), tostring(genesShort), tostring(limited)))
            notifyChat(string.format("Upgrade completed partially: %d/%d ok", successCount, totalCount), true)
            mode = "wait"
        end
    end)
end

local function onBeeProduce()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Start gene prod.")
        mode = "log"
        GeneProduction.runProduction(function(msg) addLogLine("" .. msg) end)
        mode = "wait"   -- after completion return to the WAIT main menu
    end)
end

-- onBreed:
local function onBreed()
    if processing then
        addLogLine("Another process running, wait.")
        return
    end
    setBusy(true)
    runTask(function()
        addLogLine("Starting breeding...")
        mode = "log"
        if Breeding.run(function(msg) addLogLine(msg) end) then
            mode = "win"
            winSince = os.clock()   -- show WIN ~5 s, then return to WAIT
        else
            mode = "wait"
        end
    end)
end

-- Set the button callbacks (re-set after module reload
-- when a new config is received)
local function setupButtonCallbacks()
    Buttons.setCallbacks({
        onBeeOut = onBeeOut,
        onGeneUpgrade = onGeneUpgrade,
        onBeeProduce = onBeeProduce,
        onBreed = onBreed,
    })
end

-- ==================== OPENING REDNET ====================
local function openRednet()
    local ok, err = RednetProtocol.host("labos", "main")
    if not ok then
        print("Failed to open rednet / host labos: " .. tostring(err))
        return false
    end
    print("Rednet registered as labos/main")
    return true
end

-- ==================== WAIT SCREEN ====================
-- The freeze wait is drawn in the timer branch of the main loop via
-- Boot.drawWaitFrame (smooth bar); you can only leave the wait with the
-- unfreeze command (or by receiving a config, which reassembles the screens).

-- ==================== PERIPHERAL REFRESH AFTER CONFIG ====================
-- After receiving a config all modules are reloaded; the main program must
-- get the fresh config and fresh peripheral wrappers.
local function reinitAfterConfig()
    lib = require("lab_config_loader").reload()
    Utils = require("lab_utils")
    HUD = require("lab_hud")
    Buttons = require("lab_buttons")
    Processor = require("lab_processor")
    GeneProduction = require("lab_geneproduction")
    Breeding = require("lab_breeding")
    setupButtonCallbacks()   -- the new Buttons module has empty callbacks
    refreshData()
end

-- ==================== MAIN LOOP ====================

-- Check: are the peripherals configured (labos_config.lua arrived from HeartOS)
local function hasPeripheralConfig()
    local ok, res = pcall(ConfigLoader.load)
    if ok and res and res.peripherals and res.peripherals.main_monitor then
        return true
    end
    return false
end

-- Prints the current peripheral config state to the computer terminal.
-- Monitors are not used (as in BeeOS).
local function printConfigStatus()
    local native = term.native()
    local old = term.current()
    term.redirect(native)
    term.clear()
    term.setCursorPos(1, 1)

    local function line(label, present)
        term.write("[")
        term.setTextColor(present and colors.green or colors.red)
        term.write(present and " OK " or " -- ")
        term.setTextColor(colors.white)
        term.write("] ")
        print(label)
    end

    print("LabOS: waiting for HeartOS config")
    print("")
    line("labos_config.lua (peripherals)", hasPeripheralConfig())
    print("")
    print("Config is sent from the HeartOS")
    print("terminal (Configure LabOS).")

    term.redirect(old)
end

-- Single wait for a message from HeartOS.
-- Returns true when a config has arrived and been processed (config_reloaded).
local function waitForConfigMessage()
    while true do
        -- pcall returns (ok, eventName, p1, p2, ...); for rednet_message:
        -- p1 = senderId, p2 = message
        local okPull, evt, senderId, msg = pcall(os.pullEvent, "rednet_message")
        if okPull and evt == "rednet_message" then
            local action = handleConfigMessage(senderId, msg)
            if action == "config_reloaded" then
                return true
            end
        end
    end
end

print("Starting laboratory terminal...")
openRednet()

-- Config wait gate (as in BeeOS): while the peripherals are not configured -
-- blink the status in the console; do not take over the monitors.
local waiting = false
while not hasPeripheralConfig() do
    if not waiting then
        printConfigStatus()
        waiting = true
    end
    waitForConfigMessage()
    reinitAfterConfig()
    if hasPeripheralConfig() then
        break
    else
        printConfigStatus()
        os.sleep(1)
    end
end

-- Config received. Important: when sending, HeartOS does freeze -> update_config ->
-- unfreeze. freeze arrives in the gate (frozen=true), while unfreeze may arrive
-- in the window between leaving the gate and starting the threads and get lost. Therefore
-- after successfully receiving a config we start work unconditionally:
-- reset frozen (an unfreeze arriving later will not hurt).
frozen = false
waitPrepared = false

-- Config received - show the updated status (green [ OK ])
printConfigStatus()

refreshData()
loadState()   -- restore state after restart
-- If there are no bees in the barrel, reset the state
if #bees == 0 then
    clearState()
end

setupButtonCallbacks()

-- ==================== REDNET HANDLING (shared by both threads) ====================
-- Called from renderLoop AND eventLoop, because a rednet message may go
-- to either thread. Handling is non-blocking (flags, config, lab_request),
-- so it is safe in renderLoop. The event goes to exactly one thread,
-- so it is processed once (no loss of unfreeze/freeze/config).
local function handleRednet(senderId, message)
    if message and message.type == "lab_request" then
        targetHive = message.hive_id
        targetHiveBlock = message.hive_block
        lastExpectedCount = message.bee_count
        -- BeeOS passes its real id in sender_id (broadcast may give 0)
        lastSenderId = message.sender_id or senderId
        saveState()
        addLogLine(string.format("Received bees from hive %d (sender %s, expected %s).", targetHive, tostring(lastSenderId), tostring(lastExpectedCount)))
        mode = "wait"
    else
        local action = handleConfigMessage(senderId, message)
        if action == "config_reloaded" then
            -- Config accepted from HeartOS - configuration is done. We lift the
            -- freeze ourselves (unfreeze could be lost in a race
            -- with rendering/loading), otherwise the wait screen would remain
            -- hanging forever.
            frozen = false
            waitPrepared = false
            pcall(function()
                reinitAfterConfig()
                -- show a short loading after the update
                --- @type table
                local mainMon = peripheral.wrap(lib.peripherals.main_monitor)
                if mainMon then
                    Boot.prepareScreen(mainMon)
                    Boot.show(mainMon, 2)
                end
            end)
        end
    end
end

-- ==================== MAIN LOOP (single event owner) ====================
-- A single thread processes EVERYTHING: timer (render), monitor_touch (buttons),
-- rednet_message (HeartOS protocol). Thanks to this, button clicks and
-- protocol messages are NEVER lost (no thread competition for
-- events). Long tasks run in a separate taskWorker thread and do not
-- block this loop.
local function mainLoop()
    local timer = os.startTimer(0.1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == timer then
            local ok, err = pcall(function()
                frame = frame + 1

                -- Safeguard: if the freeze lasts longer than FROZEN_MAX_SECONDS
                -- and there has been no config for a long time - lift it (lost unfreeze).
                if frozen and frozenSince and
                   (os.clock() - frozenSince > FROZEN_MAX_SECONDS) and
                   (os.clock() - lastConfigActivity > FROZEN_MAX_SECONDS) then
                    frozen = false
                    frozenSince = nil
                    waitPrepared = false
                    print("LAB: auto-unfroze after " .. FROZEN_MAX_SECONDS .. "s (lost unfreeze)")
                end

                if frozen then
                    -- Freeze: smooth wait screen (HUD_Lab_Boot.nfp + bar)
                    --- @type table
                    local mainMon = peripheral.wrap(lib.peripherals.main_monitor)
                    if mainMon then
                        if not waitPrepared then
                            Boot.prepareScreen(mainMon)
                            waitPrepared = true
                        end
                        Boot.drawWaitFrame(mainMon)
                    end
                else
                    if waitPrepared then
                        waitPrepared = false
                    end
                    -- Show the WIN screen ~5 s, then return to WAIT
                    if mode == "win" and winSince > 0 and os.clock() - winSince > 5 then
                        mode = "wait"
                        winSince = 0
                    end
                    if frame % 20 == 0 then
                        refreshData()
                    end
                    HUD.drawAll(bees, geneCounts, neededCounts, mode, logBuffer, frame, currentStatus)
                    Buttons.drawAll(frame)
                end
            end)

            if not ok then
                print("LAB render error: " .. tostring(err))
                addLogLine("!RENDER ERROR: " .. tostring(err))
            end

            timer = os.startTimer(0.1)

        elseif event == "monitor_touch" then
            if not frozen then
                local ok, err = pcall(function()
                    -- Diagnostics: which monitor received the click
                    addLogLine("Touch: " .. tostring(p1))
                    Buttons.handleTouch(p1, p2, p3)
                end)
                if not ok then
                    print("LAB touch error: " .. tostring(err))
                    addLogLine("!TOUCH ERROR: " .. tostring(err))
                end
            end

        elseif event == "rednet_message" then
            local okR, errR = pcall(handleRednet, p1, p2)
            if not okR then
                print("LAB rednet error: " .. tostring(errR))
                addLogLine("!REDNET ERROR: " .. tostring(errR))
            end
        end
    end
end

parallel.waitForAny(mainLoop, taskWorker)