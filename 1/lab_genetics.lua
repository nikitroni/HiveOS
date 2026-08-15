-- lab_genetics.lua
-- Локальная копия необходимых функций для работы с генами.

local Genetics = {}

-- Целевые элитные значения (как в ELITE_VALUES из lab_utils)
Genetics.ELITE = {
    productivity = "productivity.very_high",
    endurance = "endurance.strong",
    behavior = "behavior.metaturnal",
    weather_tolerance = "weather_tolerance.any"
}

-- Цвета уровней генов (взято из исходной библиотеки)
Genetics.levelColors = {
    normal   = colors.green,
    medium   = colors.blue,
    high     = colors.pink,
    very_high = colors.red,
    weak     = colors.green,
    strong   = colors.red,
    diurnal  = colors.green,
    nocturnal = colors.pink,
    metaturnal = colors.red,
    none     = colors.green,
    rain     = colors.pink,
    any      = colors.red
}

-- Функция получения цвета уровня
function Genetics.getGeneLevelColor(geneName, level)
    -- level может быть строкой вида "productivity.normal" или просто "normal"
    local pureLevel = level:match("%.(.+)$") or level
    return Genetics.levelColors[pureLevel] or colors.white
end

-- Функция форматирования имени пчелы (может пригодиться)
function Genetics.formatBeeName(rawType)
    if not rawType then return "Unknown" end
    local name = rawType:gsub("^productivebees:", "")
    name = name:gsub("_bee$", "")
    local parts = {}
    for part in name:gmatch("[^_]+") do
        part = part:sub(1,1):upper() .. part:sub(2):lower()
        table.insert(parts, part)
    end
    name = table.concat(parts)
    if #name > 10 then name = name:sub(1,10) end
    return name
end

return Genetics