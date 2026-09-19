-- hive_reader.lua
local Genetics = require("library")
local LabManager = require("lab_manager")

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

        -- Пчёлы
        data.bees = {}
        if raw.bees then
            for _, bee in ipairs(raw.bees) do
                local beeData = { type = "unknown", genes = {} }
                if bee.entity_data then
                    if bee.entity_data.type then
                        beeData.type = bee.entity_data.type
                    end
                    -- Ищем атрибуты в разных местах
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

        -- Апгрейды
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

        -- Расчёт процента заполнения инвентаря (только слоты 2-10)
        data.inventoryPercent = 0
        if raw.inv and raw.inv.Items then
            -- Отфильтровываем предметы, лежащие в слотах 2-10
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

-- ==================== АСИНХРОННОЕ ЧТЕНИЕ (воркер) ====================
-- getBlockData может "зависнуть" навсегда (блок не отвечает), и в едином
-- потоке это полностью заморозило бы терминал (pcall от зависания НЕ спасает).
-- Поэтому живые циклы (tech/info) НЕ читают данные сами, а запрашивают чтение
-- у воркера, который крутится в отдельном потоке через parallel.waitForAny.
-- Если чтение зависло — остаётся висеть ТОЛЬКО воркер, UI продолжает жить,
-- а результаты приходят событием HiveReader.READ_COMPLETE (когда дойдут).

HiveReader.READ_COMPLETE = "hive_read_complete"
local READ_REQUEST = "hive_read_request"

-- Воркер: ждёт запрос, читает ВСЕ ульи, сообщает о завершении.
-- Запускается из tech-цикла: parallel.waitForAny(loopFn, HiveReader.worker).
-- Пока идёт отправка пчёл (LabManager.isSending) улья изменяются и чтение
-- почти гарантированно зависнет — пропускаем его, но всё равно отвечаем
-- READ_COMPLETE, чтобы циклы разблокировали dataBusy и обновились позже.
-- Весь цикл обёрнут в pcall — неожиданная ошибка не убьёт parallel.
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

-- НЕБЛОКИРУЮЩИЙ запрос чтения: просто ставит событие воркеру и сразу выходит.
function HiveReader.requestUpdate()
    os.queueEvent(READ_REQUEST)
end

return HiveReader