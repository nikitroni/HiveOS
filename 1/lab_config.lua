-- lab_config.lua
-- Конфигурация лабораторного терминала

return {
    -- ========== ПЕРИФЕРИЙНЫЕ УСТРОЙСТВА ==========
    -- (замените на свои реальные имена)
    peripherals = {
        main_monitor    = "monitor_3",      -- основной монитор 71x26
        button_monitors = {                  -- 4 монитора для кнопок
            bee_out     = "monitor_7",
            gene_upgrade = "monitor_8",
            bee_produce = "monitor_9",
            refresh     = "monitor_10",
        },
        cage_chest      = "minecraft:barrel_2",  -- сундук с пустыми клетками
        lab_chest       = "minecraft:barrel_1",  -- сундук с пчёлами
        reader_bee      = "block_reader_19",     -- ридер на lab_chest
        reader_indexer  = "block_reader_20",     -- ридер на индексатор
        bee_indexer     = "productivebees:gene_indexer_2", -- сам индексатор
        breeding_chamber = "productivebees:breeding_chamber_1",
        crafters = {                              -- крафтеры для 1-4 генов
            [1] = "enderio:crafter_4",
            [2] = "enderio:crafter_5",
            [3] = "enderio:crafter_6",
            [4] = "enderio:crafter_7",
        },
        incubator = "productivebees:incubator_3",
        relay = "redstone_relay_1",  -- имя реле
        resource_chest = "ae2:interface_0",  -- сундук с цветами и honey_treat
        chat_box = "chat_box_0",

         relay_sides = {"back", "top", "front"},
        target_gene_count = 64,
        min_resources = 32,
        resource_items = {
        "minecraft:sunflower",
        "productivebees:honey_treat",
        },
        relay_cycle = {
        phase1_back_top_duration = 5,          -- длительность фазы 1 (back и top включены)
        phase2_delay = 0.5,                       -- пауза между фазами
        phase2_front_duration = 5,              -- длительность фазы 2 (пульсация на front)
        phase2_front_pulse_duration = 0.5,      -- длительность импульса на front в фазе 2
        phase2_front_pulse_interval = 1,        -- интервал между импульсами в фазе 2
        },

       
    

        rednet_channel  = 1234,
        bg_file = "HUD_lab.nfp",   -- путь к файлу фона
    },

    -- ========== КАРТОЧКИ ПЧЁЛ (5 ячеек) ==========
    bee_grid = {
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
    },

    -- ========== ОБЛАСТЬ ЛОГА (9 строк + заголовок) ==========
    log_area = {
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
    },

    -- ========== ДНК-ЦЕПОЧКИ ==========
    dna = {
        left_start_x = 20,   -- X первой цепочки
        right_start_x = 46,  -- X второй цепочки (20 + 26)
        start_y = 3,
        height = 10,          -- сколько строк занимает
        -- Остальные параметры (символы, цвета) заданы в коде анимации
    },

    -- ========== ПАНЕЛЬ ИНДЕКСЕРА (GENE INDEXER) ==========
    gene_indexer_panel = {
        start_x = 3,
        start_y = 3,
        width   = 17,
        height  = 10,
        title_chars = {   -- для цветной надписи (как в вашем конфиге)
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
        },

    -- ========== ПАНЕЛЬ ПОТРЕБНОСТЕЙ (BEE GENETICS) ==========
    bee_genetics_panel = {
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
            { name = "W.Tolerance",    key = "weather_tolerance",  name_x = 4, name_y = 8, need_x = 0, need_y = 9, count_x = 15, count_y = 9  },
        },
    },

    -- ========== ЗАГЛУШКИ И ФОРМАТЫ ==========
    labels = {
        no_bee = " -- EMPTY-- ",   -- отображается в ячейке, если пчелы нет
    },

    processor = {
        gene_start_slot = 3,
        honey_crafter_slot = 2,
        result_crafter_slot = 11,
        incubator_bee_slot = 1,
        incubator_gene_slot = 2,
        incubator_result_slot = 3,
        craft_wait = 1,
        incubate_wait = 5,
    },

}