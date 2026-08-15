-- library.lua
local Genetics = {}

Genetics.genes = {
    bee_productivity = {
        name = "Productivity",
        header = string.char(18),  -- ↕︎
        levels = {
            normal   = { sym = string.char(143), color = colors.green },
            medium   = { sym = string.char(8),   color = colors.blue },
            high     = { sym = string.char(7),   color = colors.pink },
            veryhigh = { sym = string.char(3),   color = colors.red },
        },
        order = { "normal", "medium", "high", "veryhigh" }
    },
    bee_weather_tolerance = {
        name = "W.Tolerance",
        header = string.char(12),  -- Θ
        levels = {
            none = { sym = string.char(143), color = colors.green },
            rain = { sym = string.char(7),   color = colors.pink },
            any  = { sym = string.char(3),   color = colors.red },
        },
        order = { "none", "rain", "any" }
    },
    bee_behavior = {
        name = "Behavior",
        header = string.char(164),  -- ☼
        levels = {
            diurnal    = { sym = string.char(143), color = colors.green },
            nocturnal  = { sym = string.char(7),   color = colors.pink },
            metaturnal = { sym = string.char(3),   color = colors.red },
        },
        order = { "diurnal", "nocturnal", "metaturnal" }
    },
    bee_endurance = {
        name = "Endurance",
        header = string.char(167),  -- §
        levels = {
            weak    = { sym = string.char(143), color = colors.green },
            normal  = { sym = string.char(8),   color = colors.blue },
            medium  = { sym = string.char(7),   color = colors.pink },
            strong  = { sym = string.char(3),   color = colors.red },
        },
        order = { "weak", "normal", "medium", "strong" }
    }
}

Genetics.hiveUpgrades = {
    productivity  = { name = "prod.ALPHA",  color = colors.green },
    productivity2 = { name = "prod.BETA", color = colors.blue },
    productivity3 = { name = "prod.GAMMA", color = colors.cyan },
    productivity4 = { name = "prod.OMEGA", color = colors.purple },
    simulator     = { name = "simulator",     color = colors.orange },
    block         = { name = "block",         color = colors.yellow },
}

function Genetics.getProgressColor(percent)
    if percent <= 0 then return colors.white
    elseif percent <= 40 then return colors.green
    elseif percent <= 85 then return colors.orange
    else return colors.red end
end

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
    if #name > 11 then name = name:sub(1, 11) end
    return name
end

function Genetics.getGeneInfo(geneName, level)
    local gene = Genetics.genes[geneName]
    if not gene then return "?", colors.white end
    local levelData = gene.levels[level]
    if not levelData then return "?", colors.white end
    return levelData.sym, levelData.color
end

function Genetics.getGeneHeaders()
    return {
        Genetics.genes.bee_productivity.header,
        Genetics.genes.bee_weather_tolerance.header,
        Genetics.genes.bee_behavior.header,
        Genetics.genes.bee_endurance.header
    }
end

function Genetics.getGeneText(geneName, level)
    local gene = Genetics.genes[geneName]
    if not gene then return "Unknown: ?", colors.white end
    local levelData = gene.levels[level]
    if not levelData then return gene.name .. ": ?", colors.white end
    return gene.name .. ": " .. level, levelData.color
end

function Genetics.getGeneNames()
    return { "bee_productivity", "bee_weather_tolerance", "bee_behavior", "bee_endurance" }
end

function Genetics.getUpgradeName(key)
    local up = Genetics.hiveUpgrades[key]
    return up and up.name or key
end

function Genetics.getUpgradeColor(key)
    local up = Genetics.hiveUpgrades[key]
    return up and up.color or colors.white
end

function Genetics.getGeneLevel(geneName, level)
    local gene = Genetics.genes[geneName]
    if not gene then return "?", colors.white end
    local levelData = gene.levels[level]
    if not levelData then return "?", colors.white end
    return level, levelData.color
end

local maxStackMap = {
    ["configurable_honeycomb"] = 64,
    ["configurable_comb"] = 64,
    ["pollen_puff"] = 16,
    ["bee_cage"] = 1,
}

function Genetics.getMaxStack(itemId)
    for pattern, size in pairs(maxStackMap) do
        if itemId:find(pattern, 1, true) then
            return size
        end
    end
    return 64
end

function Genetics.calculateAdvancedProgress(items, maxSlots)
    if not items or maxSlots == 0 then return 0 end
    local totalFill = 0
    for _, item in ipairs(items) do
        local count = item.count or 0
        local maxStack = Genetics.getMaxStack(item.id)
        totalFill = totalFill + (count / maxStack)
    end
    if #items > maxSlots then
        totalFill = totalFill * (maxSlots / #items)
    end
    local percent = (totalFill / maxSlots) * 100
    return math.floor(percent)
end

return Genetics