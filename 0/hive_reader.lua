-- hive_reader.lua
local Genetics = require("library")

local HiveReader = {}
local hives = {}
local updateInterval = 10
local lastUpdate = 0

function HiveReader.loadConfig(path)
    path = path or "hives.cfg"
    local file = fs.open(path, "r")
    if not file then
        error("hives.cfg not found at " .. path)
    end
    local content = file.readAll()
    file.close()

    if not content:match("^%s*return") then
        content = "return " .. content
    end

    local func, err = load(content, path, "t", {})
    if not func then
        error("Invalid hives.cfg syntax: " .. tostring(err))
    end
    local cfg = func()
    if type(cfg) ~= "table" then
        error("hives.cfg must return a table")
    end

    hives = {}
    for _, entry in ipairs(cfg) do
        table.insert(hives, {
            id = entry.id,
            readerName = entry.reader_block,
            hiveBlock = entry.hive_block,
            reader = nil,
            data = nil,
            error = nil,
        })
    end
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

return HiveReader