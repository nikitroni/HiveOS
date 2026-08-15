-- lab_utils.lua
-- Вспомогательные функции для лабораторного терминала.
-- Чтение данных из бочки и индексера, анализ генов пчёл.

local config = require("lab_config")

local Utils = {}

-- ==================== КОНСТАНТЫ ====================
local ELITE_VALUES = {
    productivity = "productivity.very_high",
    endurance = "endurance.strong",
    behavior = "behavior.metaturnal",
    weather_tolerance = "weather_tolerance.any"
}

local GENE_ATTRIBUTES = { "productivity", "endurance", "behavior", "weather_tolerance" }

-- ==================== ЧТЕНИЕ ПЧЁЛ ИЗ БОЧКИ ====================
function Utils.getBeesFromBarrel()
    local reader = peripheral.wrap(config.peripherals.reader_bee)
    if not reader then error("Reader for barrel not found") end

    local data = reader.getBlockData()
    if not data or not data.Items then return {} end

    local bees = {}
    for _, item in ipairs(data.Items) do
        if item.id == "productivebees:sturdy_bee_cage" or item.id == "productivebees:bee_cage" then
            local components = item.components
            if components then
                local custom = components["minecraft:custom_data"]
                if custom then
                    local attachments = custom["neoforge:attachments"]
                    if attachments then
                        local attrHandler = attachments["productivebees:attributes_handler"]
                        if attrHandler then
                            for i = 1, item.count do   -- каждая клетка в стаке
                                table.insert(bees, {
                                    slot = item.Slot + 1,
                                    type = custom.type,
                                    productivity = attrHandler.bee_productivity,
                                    endurance = attrHandler.bee_endurance,
                                    behavior = attrHandler.bee_behavior,
                                    weather_tolerance = attrHandler.bee_weather_tolerance,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return bees
end

-- ==================== ЧТЕНИЕ ГЕНОВ ИЗ ИНДЕКСЕРА ====================
function Utils.getGeneCountsFromIndexer()
    local reader = peripheral.wrap(config.peripherals.reader_indexer)
    if not reader then error("Reader for indexer not found") end

    local data = reader.getBlockData()
    if not data or not data.inv or not data.inv.Items then
        return { productivity = 0, endurance = 0, behavior = 0, weather_tolerance = 0 }
    end

    local counts = { productivity = 0, endurance = 0, behavior = 0, weather_tolerance = 0 }
    for _, item in ipairs(data.inv.Items) do
        local geneGroup = item.components and item.components["productivebees:gene_group"]
        if geneGroup and geneGroup.purity == 100 then
            local attr = geneGroup.attribute
            if counts[attr] ~= nil then
                counts[attr] = counts[attr] + item.count
            end
        end
    end
    return counts
end

-- ==================== ПРОВЕРКА ЭЛИТНОСТИ ПЧЕЛЫ ====================
function Utils.isElite(bee)
    return bee.productivity == ELITE_VALUES.productivity
        and bee.endurance == ELITE_VALUES.endurance
        and bee.behavior == ELITE_VALUES.behavior
        and bee.weather_tolerance == ELITE_VALUES.weather_tolerance
end

-- ==================== ПОДСЧЁТ НЕДОСТАЮЩИХ ГЕНОВ ====================
function Utils.calculateNeededGenes(bees)
    local needed = { productivity = 0, endurance = 0, behavior = 0, weather_tolerance = 0 }
    for _, bee in ipairs(bees) do
        if not Utils.isElite(bee) then
            if bee.productivity ~= ELITE_VALUES.productivity then
                needed.productivity = needed.productivity + 1
            end
            if bee.endurance ~= ELITE_VALUES.endurance then
                needed.endurance = needed.endurance + 1
            end
            if bee.behavior ~= ELITE_VALUES.behavior then
                needed.behavior = needed.behavior + 1
            end
            if bee.weather_tolerance ~= ELITE_VALUES.weather_tolerance then
                needed.weather_tolerance = needed.weather_tolerance + 1
            end
        end
    end
    return needed
end

-- ==================== ФОРМАТИРОВАНИЕ ЧИСЛА ====================
function Utils.formatGeneCount(count, digits)
    digits = digits or 2
    local fmt = "%0" .. digits .. "d"
    return string.format(fmt, count)
end

return Utils