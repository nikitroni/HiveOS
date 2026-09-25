-- hive_reader.lua
local Genetics = require("library")
local LabManager = require("lab_manager")
local Logger = require("logger")

local HiveReader = {}
local hives = {}
local updateInterval = 10
local lastUpdate = 0

local function loadLuaTable(path)
  if not fs.exists(path) then return nil end
  local handler, err = loadfile(path)
  if not handler then return nil end
  local ok, result = pcall(handler)
  if ok and type(result) == "table" then return result end
  return nil
end

function HiveReader.loadBeeOSConfig(path)
  return loadLuaTable(path or "beeos_config.lua")
end

function HiveReader.loadHiveMap(path)
  path = path or "hives_map.lua"
  local cfg = loadLuaTable(path)
  if not cfg then
    hives = {}
    return false
  end

  hives = {}
  for _, entry in ipairs(cfg) do
    table.insert(hives, {
      id = entry.id,
      readerName = entry.reader or entry.reader_block,
      hiveBlock = entry.hive or entry.hive_block,
      relay = entry.relay or entry.relay_block,
      reader = nil,
      data = nil,
      error = nil,
    })
  end
  -- Hives are displayed by ascending id, regardless of the record order
  -- in hives_map.lua (addition order in the config may differ).
  table.sort(hives, function(a, b)
    return (a.id or math.huge) < (b.id or math.huge)
  end)
  return #hives > 0
end

function HiveReader.connectAll()
    for _, hive in ipairs(hives) do
        --- @type table
        local reader = peripheral.wrap(hive.readerName)
        if reader then
            hive.reader = reader
            hive.error = nil
        else
            hive.error = "Reader not found"
        end
    end
end

local function parseBeeGenes(attrHandler)
    local genes = {}
    for geneKey, val in pairs(attrHandler) do
        if type(val) == "string" then
            local level = val:match("%.(.+)$")
            if level then
                genes[geneKey] = level:gsub("_", "")
            else
                genes[geneKey] = val
            end
        end
    end
    return genes
end

local function readHive(hive)
    if not hive.reader then
        hive.error = "No reader"
        return
    end
    local ok, result = pcall(function()
        local raw = hive.reader.getBlockData()
        if not raw then return nil end

        local data = {}

        -- Bees
        data.bees = {}
        if raw.bees then
            for _, bee in ipairs(raw.bees) do
                local beeData = { type = "unknown", genes = {} }
                if bee.entity_data then
                    if bee.entity_data.type then
                        beeData.type = bee.entity_data.type
                    end
                    -- Look for attributes in different places
                    local attrHandler = nil
                    if bee.entity_data.NeoForgeData and bee.entity_data.NeoForgeData["productivebees:attributes_handler"] then
                        attrHandler = bee.entity_data.NeoForgeData["productivebees:attributes_handler"]
                    elseif bee.entity_data["neoforge:attachments"] and bee.entity_data["neoforge:attachments"]["productivebees:attributes_handler"] then
                        attrHandler = bee.entity_data["neoforge:attachments"]["productivebees:attributes_handler"]
                    end
                    if attrHandler then
                        beeData.genes = parseBeeGenes(attrHandler)
                    end
                end
                table.insert(data.bees, beeData)
            end
        end

        -- Upgrades
        data.upgrades = {}
        if raw.upgrades and raw.upgrades.Items then
            for _, item in ipairs(raw.upgrades.Items) do
                local id = item.id
                local name = id:match("upgrade_(.+)$") or id
                name = name:gsub("^productivelib:", "")
                name = name:gsub("_", "")
                table.insert(data.upgrades, name)
            end
        end

        -- Calculate inventory fill percentage (slots 2-10 only)
        data.inventoryPercent = 0
        if raw.inv and raw.inv.Items then
            -- Filter out items located in slots 2-10
            local filteredItems = {}
            for _, item in ipairs(raw.inv.Items) do
                if item.Slot and item.Slot >= 2 and item.Slot <= 10 then
                    table.insert(filteredItems, item)
                end
            end
            data.inventoryPercent = Genetics.calculateAdvancedProgress(filteredItems, 9)
        end
        data.occupiedSlots = 0
data.combCount = 0
data.puffCount = 0
if raw.inv and raw.inv.Items then
    for _, item in ipairs(raw.inv.Items) do
        if item.Slot and item.Slot >= 2 and item.Slot <= 10 then
            data.occupiedSlots = data.occupiedSlots + 1
            if item.id:find("configurable_honeycomb") or item.id:find("configurable_comb") then
                data.combCount = data.combCount + (item.count or 0)
            elseif item.id:find("pollen_puff") then
                data.puffCount = data.puffCount + (item.count or 0)
            end
        end
    end
end

        return data
    end)

    if ok then
        hive.data = result
        hive.error = nil
    else
        hive.error = tostring(result)
    end
end

function HiveReader.updateIfNeeded()
    local now = os.clock()
    if now - lastUpdate >= updateInterval then
        for _, hive in ipairs(hives) do
            readHive(hive)
        end
        lastUpdate = now
    end
end

function HiveReader.getHives()
    return hives
end

function HiveReader.count()
    return #hives
end

function HiveReader.forceUpdate()
    for _, hive in ipairs(hives) do
        readHive(hive)
    end
    lastUpdate = os.clock()
end

-- ==================== ASYNCHRONOUS READING (worker) ====================
-- getBlockData may "hang" forever (the block does not respond), and in a single
-- thread this would completely freeze the terminal (pcall does NOT save from a hang).
-- Therefore the live loops (tech/info) do NOT read data themselves, but request
-- a read from the worker, which runs in a separate thread via parallel.waitForAny.
-- If a read hangs - ONLY the worker remains hanging, the UI stays alive,
-- and the results arrive via the HiveReader.READ_COMPLETE event (when they arrive).

HiveReader.READ_COMPLETE = "hive_read_complete"
local READ_REQUEST = "hive_read_request"

-- Worker: waits for a request, reads ALL hives, reports completion.
-- Started from the tech loop: parallel.waitForAny(loopFn, HiveReader.worker).
-- While bees are being sent (LabManager.isSending) the hives change and reading
-- will almost certainly hang - we skip it, but still answer
-- READ_COMPLETE so the loops unblock dataBusy and update later.
-- The whole loop is wrapped in pcall - an unexpected error will not kill parallel.
function HiveReader.worker()
    while true do
        local ok, err = pcall(function()
            os.pullEvent(READ_REQUEST)
            if LabManager.isSending() then
                os.queueEvent(HiveReader.READ_COMPLETE)
            else
                for _, hive in ipairs(hives) do
                    readHive(hive)
                end
                os.queueEvent(HiveReader.READ_COMPLETE)
            end
        end)
        if not ok then
            Logger.log("HIVE: worker error: " .. tostring(err))
        end
    end
end

-- NON-BLOCKING read request: just queues an event to the worker and returns immediately.
function HiveReader.requestUpdate()
    os.queueEvent(READ_REQUEST)
end

return HiveReader