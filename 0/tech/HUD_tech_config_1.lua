-- HUD_info_config_1
return {
-- Основная сетка (Grid)
    grid = {
        start_x = 4,          -- начало ячейки
        start_y = 2,          
        cols = 3,
        rows = 10,
        offset_x = 15,        -- 13 (ячейка) + 2 (зазор) = 15
        offset_y = 3,         -- 2 (ячейка) + 1 (зазор) = 3
        hives_per_page = 30
},

    -- Внутренние смещения текста
    offsets = {
        hive_text = { x = 0, y = 0 },   
        bee_name = { x = 0, y = 1 },            -- имя пчелы
        bee_prefix  = { x = 0, y = 1 },        -- "-" перед именем пчелы
    },

    -- Параметры текста и заглушки
    labels = {
        -- Формат заголовка: "---HIVE#01---"
        hive_template = "---HIVE#%02d---", 
        -- Если пчел нет
        no_bee = "-	E M P T Y -", 
        -- Формат пчелы: "-Conductivex5" (обрезаем имя до 10 символов, чтобы влезло x5)
        bee_format = "-%-10sx%d", 
        
        colors = {
            hive = colors.yellow,
            bee = colors.white,
            empty = colors.red,
        }
    },

    -- Кнопки навигации (Футер)
    footer = {
        y = 32,
        back = { x = 35, label = "BACK", bg = colors.red, fg = colors.black },
        page = { x = 39, label = "%02d/%02d", bg = colors.black, fg = colors.white }, --формат 01/02
        next = { x = 44, label = "NEXT", bg = colors.green, fg = colors.black }
    },
    screen = {
    back_button = { x1 = 35, y1 = 31, x2 = 37, y2 = 33 }, -- ширина 4, высота 3
    next_button = { x1 = 44, y1 = 31, x2 = 47, y2 = 33 },
},
}