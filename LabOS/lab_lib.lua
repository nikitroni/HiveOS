-- lab_lib.lua
-- LabOS library: all static terminal information in one place.
-- Contains: bee genetics, HUD layout, panel coordinates, log, DNA,
-- processor slots, relay and resource settings.
--
-- Peripherals are NOT written here: they come from HeartOS in
-- labos_config.lua, and the lab_config_loader.lua adapter puts them into lab.peripherals.

local lab = {}

-- ==================== GENETICS (formerly lab_genetics.lua) ====================

-- Target elite gene values
lab.ELITE = {
    productivity = "productivity.very_high",
    endurance = "endurance.strong",
    behavior = "behavior.metaturnal",
    weather_tolerance = "weather_tolerance.any"
}

-- Gene level colors
lab.levelColors = {
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

-- Gene level color by name and value
function lab.getGeneLevelColor(geneName, level)
    -- level may be a string like "productivity.normal" or just "normal"
    local pureLevel = level:match("%.(.+)$") or level
    return lab.levelColors[pureLevel] or colors.white
end

-- Bee name formatting
function lab.formatBeeName(rawType)
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

-- ==================== PERIPHERALS ====================
-- Peripheral names are NOT stored here: they come from HeartOS in
-- labos_config.lua, and the lab_config_loader.lua adapter puts them here.
-- If there is no config yet - this block is empty, the terminal waits for the config
-- (see LAB_main.lua - printConfigStatus).
lab.peripherals = {}

-- ==================== BEE CARDS (5 cells) ====================
lab.bee_grid = {
    start_x = 1,
    start_y = 16,
    cols = 5,
    offset_x = 14,
    offset_y = 11,
    offsets = {
        title = { x = 1, y = 1 },               -- bee name (or " --EMPTY-- ")
        -- Gene headers
        gene_Productivity     = { x = 1, y = 2 },
        gene_W_Tolerance      = { x = 1, y = 4 },
        gene_Behavior         = { x = 1, y = 6 },
        gene_Endurance        = { x = 1, y = 8 },
        -- Gene values (level text)
        gene_Productivity_val = { x = 1, y = 3 },
        gene_W_Tolerance_val  = { x = 1, y = 5 },
        gene_Behavior_val     = { x = 1, y = 7 },
        gene_Endurance_val    = { x = 1, y = 9 },
    },
}

-- ==================== LOG AREA (9 rows + title) ====================
lab.log_area = {
    start_x = 23,
    start_y = 3,
    width   = 22,   -- width in characters
    height  = 10,   -- total rows (including the title)
    title   = "<<<<<<UPGRADE LOG>>>>>>",
    title_y = 3,    -- Y for the title (usually matches start_y)
    -- Coordinates for the content (9 rows)
    content_x = 23,
    content_y = 4,  -- first log row
    content_height = 9,
}

-- ==================== DNA STRANDS ====================
lab.dna = {
    left_start_x = 20,   -- X of the first strand
    right_start_x = 46,  -- X of the second strand (20 + 26)
    start_y = 3,
    height = 10,          -- how many rows it occupies
    -- Other parameters (characters, colors) are set in the animation code
}

-- ==================== INDEXER PANEL (GENE INDEXER) ====================
lab.gene_indexer_panel = {
    start_x = 3,
    start_y = 3,
    width   = 17,
    height  = 10,
    title_chars = {   -- for the colored caption
        {char="G", x=3, col=colors.red},
        {char="E", x=4, col=colors.orange},
        {char="N", x=5, col=colors.yellow},
        {char="E", x=6, col=colors.green},
        {char="I", x=8, col=colors.lightBlue},
        {char="N", x=9, col=colors.lightBlue},
        {char="D", x=10, col=colors.lightBlue},
        {char="E", x=11, col=colors.blue},
        {char="X", x=12, col=colors.blue},
        {char="E", x=13, col=colors.purple},
        {char="R", x=14, col=colors.purple},
    },
    -- Positions for outputting gene counts
    genes = {
        { name = "Productivity",   key = "productivity",      name_x = 0, name_y = 2, level_x = 0, level_y = 3, count_x = 10, count_y = 3 },
        { name = "Endurance",      key = "endurance",         name_x = 0, name_y = 4, level_x = 0, level_y = 5, count_x = 10, count_y = 5 },
        { name = "Behavior",       key = "behavior",          name_x = 0, name_y = 6, level_x = 0, level_y = 7, count_x = 10, count_y = 7 },
        { name = "W.Tolerance",    key = "weather_tolerance", name_x = 0, name_y = 8, level_x = 0, level_y = 9, count_x = 10, count_y = 9 },
    },
}

-- ==================== NEEDS PANEL (BEE GENETICS) ====================
lab.bee_genetics_panel = {
    start_x = 49,
    start_y = 3,
    width   = 21,
    height  = 10,
    title_chars = {
        {char="B", x=3, col=colors.yellow},
        {char="E", x=4, col=colors.yellow},
        {char="E", x=5, col=colors.yellow},
        {char="G", x=7, col=colors.red},
        {char="E", x=8, col=colors.orange},
        {char="N", x=9, col=colors.yellow},
        {char="E", x=10, col=colors.green},
        {char="T", x=11, col=colors.lightBlue},
        {char="I", x=12, col=colors.blue},
        {char="C", x=13, col=colors.purple},
        {char="S", x=14, col=colors.cyan},
    },
    -- Positions for outputting "Need:" labels and values
    needs = {
        { name = "Productivity",   key = "productivity",       name_x = 4, name_y = 2, need_x = 0, need_y = 3, count_x = 15, count_y = 3 },
        { name = "Endurance",      key = "endurance",          name_x = 5, name_y = 4, need_x = 0, need_y = 5, count_x = 15, count_y = 5 },
        { name = "Behavior",       key = "behavior",           name_x = 5, name_y = 6, need_x = 0, need_y = 7, count_x = 15, count_y = 7 },
        { name = "W.Tolerance",    key = "weather_tolerance",  name_x = 4, name_y = 8, need_x = 0, need_y = 9, count_x = 15, count_y = 9 },
    },
}

-- ==================== PLACEHOLDERS AND FORMATS ====================
lab.labels = {
    no_bee = " -- EMPTY-- ",   -- shown in a cell if there is no bee
}

-- ==================== PROCESSOR (slots and timings) ====================
lab.processor = {
    gene_start_slot = 3,
    honey_crafter_slot = 2,
    result_crafter_slot = 11,
    incubator_bee_slot = 1,
    incubator_gene_slot = 2,
    incubator_result_slot = 3,
    craft_wait = 1,
    incubate_wait = 5,
    craft_timeout = 5,
    incubate_timeout = 10,
}

-- ==================== RELAY AND GENE PRODUCTION SETTINGS ====================
lab.relay_sides = {"back", "top", "front"}
lab.target_gene_count = 64
lab.min_resources = 32
lab.resource_items = {
    "minecraft:sunflower",
    "productivebees:honey_treat",
}
lab.relay_cycle = {
    phase1_back_top_duration = 5,          -- duration of phase 1 (back and top on)
    phase2_delay = 0.5,                    -- pause between phases
    phase2_front_duration = 6,             -- duration of phase 2 (pulsing on front)
    phase2_front_pulse_duration = 0.5,     -- front pulse duration in phase 2
    phase2_front_pulse_interval = 1,       -- interval between pulses in phase 2
}

-- ==================== MISCELLANEOUS ====================
lab.chat_box = "chat_box_0"
lab.bg_file = "HUD_lab.nfp"

return lab