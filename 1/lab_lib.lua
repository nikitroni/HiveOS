-- lab_lib.lua
-- Библиотека LabOS: вся статичная информация терминала в одном месте.
-- Содержит: генетику пчёл, раскладку HUD, координаты панелей, лог, ДНК,
-- слоты процессора, настройки реле и ресурсов.
--
-- Периферийные устройства сюда НЕ записываются: они приходят от HeartOS в
-- labos_config.lua, а адаптер lab_config_loader.lua кладёт их в lab.peripherals.

local lab = {}

-- ==================== ГЕНЕТИКА (ранее lab_genetics.lua) ====================

-- Целевые элитные значения генов
lab.ELITE = {
    productivity = "productivity.very_high",
    endurance = "endurance.strong",
    behavior = "behavior.metaturnal",
    weather_tolerance = "weather_tolerance.any"
}

-- Цвета уровней генов
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

-- Цвет уровня гена по имени и значению
function lab.getGeneLevelColor(geneName, level)
    -- level может быть строкой вида "productivity.normal" или просто "normal"
    local pureLevel = level:match("%.(.+)$") or level
    return lab.levelColors[pureLevel] or colors.white
end

-- Форматирование имени пчелы
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

-- ==================== ПЕРИФЕРИЯ ====================
-- Имена периферии НЕ хранятся здесь: они приходят от HeartOS в
-- labos_config.lua, а адаптер lab_config_loader.lua кладёт их сюда.
-- Если конфига ещё нет - этот блок пуст, терминал ждёт конфиг
-- (см. LAB_main.lua - printConfigStatus).
lab.peripherals = {}

-- ==================== КАРТОЧКИ ПЧЁЛ (5 ячеек) ====================
lab.bee_grid = {
    start_x = 1,
    start_y = 16,
    cols = 5,
    offset_x = 14,
    offset_y = 11,
    offsets = {
        title = { x = 1, y = 1 },               -- имя пчелы (или " --EMPTY-- ")
        -- Заголовки генов
        gene_Productivity     = { x = 1, y = 2 },
        gene_W_Tolerance      = { x = 1, y = 4 },
        gene_Behavior         = { x = 1, y = 6 },
        gene_Endurance        = { x = 1, y = 8 },
        -- Значения генов (текст уровня)
        gene_Productivity_val = { x = 1, y = 3 },
        gene_W_Tolerance_val  = { x = 1, y = 5 },
        gene_Behavior_val     = { x = 1, y = 7 },
        gene_Endurance_val    = { x = 1, y = 9 },
    },
}

-- ==================== ОБЛАСТЬ ЛОГА (9 строк + заголовок) ====================
lab.log_area = {
    start_x = 23,
    start_y = 3,
    width   = 22,   -- ширина в символах
    height  = 10,   -- всего строк (включая заголовок)
    title   = "<<<<<<UPGRADE LOG>>>>>>",
    title_y = 3,    -- Y для заголовка (обычно совпадает с start_y)
    -- Координаты для содержимого (9 строк)
    content_x = 23,
    content_y = 4,  -- первая строка лога
    content_height = 9,
}

-- ==================== ДНК-ЦЕПОЧКИ ====================
lab.dna = {
    left_start_x = 20,   -- X первой цепочки
    right_start_x = 46,  -- X второй цепочки (20 + 26)
    start_y = 3,
    height = 10,          -- сколько строк занимает
    -- Остальные параметры (символы, цвета) заданы в коде анимации
}

-- ==================== ПАНЕЛЬ ИНДЕКСЕРА (GENE INDEXER) ====================
lab.gene_indexer_panel = {
    start_x = 3,
    start_y = 3,
    width   = 17,
    height  = 10,
    title_chars = {   -- для цветной надписи
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
    -- Позиции для вывода количества генов
    genes = {
        { name = "Productivity",   key = "productivity",      name_x = 0, name_y = 2, level_x = 0, level_y = 3, count_x = 10, count_y = 3 },
        { name = "Endurance",      key = "endurance",         name_x = 0, name_y = 4, level_x = 0, level_y = 5, count_x = 10, count_y = 5 },
        { name = "Behavior",       key = "behavior",          name_x = 0, name_y = 6, level_x = 0, level_y = 7, count_x = 10, count_y = 7 },
        { name = "W.Tolerance",    key = "weather_tolerance", name_x = 0, name_y = 8, level_x = 0, level_y = 9, count_x = 10, count_y = 9 },
    },
}

-- ==================== ПАНЕЛЬ ПОТРЕБНОСТЕЙ (BEE GENETICS) ====================
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
    -- Позиции для вывода надписей "Need:" и значений
    needs = {
        { name = "Productivity",   key = "productivity",       name_x = 4, name_y = 2, need_x = 0, need_y = 3, count_x = 15, count_y = 3 },
        { name = "Endurance",      key = "endurance",          name_x = 5, name_y = 4, need_x = 0, need_y = 5, count_x = 15, count_y = 5 },
        { name = "Behavior",       key = "behavior",           name_x = 5, name_y = 6, need_x = 0, need_y = 7, count_x = 15, count_y = 7 },
        { name = "W.Tolerance",    key = "weather_tolerance",  name_x = 4, name_y = 8, need_x = 0, need_y = 9, count_x = 15, count_y = 9 },
    },
}

-- ==================== ЗАГЛУШКИ И ФОРМАТЫ ====================
lab.labels = {
    no_bee = " -- EMPTY-- ",   -- отображается в ячейке, если пчелы нет
}

-- ==================== ПРОЦЕССОР (слоты и тайминги) ====================
lab.processor = {
    gene_start_slot = 3,
    honey_crafter_slot = 2,
    result_crafter_slot = 11,
    incubator_bee_slot = 1,
    incubator_gene_slot = 2,
    incubator_result_slot = 3,
    craft_wait = 1,
    incubate_wait = 5,
}

-- ==================== НАСТРОЙКИ РЕЛЕ И ПРОИЗВОДСТВА ГЕНОВ ====================
lab.relay_sides = {"back", "top", "front"}
lab.target_gene_count = 64
lab.min_resources = 32
lab.resource_items = {
    "minecraft:sunflower",
    "productivebees:honey_treat",
}
lab.relay_cycle = {
    phase1_back_top_duration = 5,          -- длительность фазы 1 (back и top включены)
    phase2_delay = 0.5,                    -- пауза между фазами
    phase2_front_duration = 6,             -- длительность фазы 2 (пульсация на front)
    phase2_front_pulse_duration = 0.5,     -- длительность импульса на front в фазе 2
    phase2_front_pulse_interval = 1,       -- интервал между импульсами в фазе 2
}

-- ==================== СЛУЖЕБНОЕ ====================
lab.chat_box = "chat_box_0"
lab.rednet_channel = 1234
lab.bg_file = "HUD_lab.nfp"

return lab