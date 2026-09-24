-- info/HUD_info_config.lua
return {
    grid = {
        hives_per_page = 8,
        cols = 2,
        rows = 4,
        offset_x = 25,
        offset_y = 8,
        start_x = 2,
        start_y = 2,
    },
    offsets = {
        hive_text   = { x = 0, y = 0 },        -- "---HIVE#01---"
        bee_prefix  = { x = 0, y = 1 },        -- "-" перед именем пчелы
        upgrade_symbol = { x = 0, y = 2 },     -- ">" перед апгрейдами
        elite       = { x = 16, y = 0 },        -- "►ELITE◄"
        separator   = { x = 15, start_y = 0, end_y = 6 }, -- вертикальная черта слева
        gene_headers= { x = 18, y = 1 },        -- "↕︎☼Θ§"
        bee_numbers = { x = 17, y = 2 },         -- цифры 1..5

        upgrade_count = 4,

        id          = { x = 6, y = 0 },         -- номер после "HIVE#"
        bee_name    = { x = 1, y = 1 },         -- имя пчелы
        upgrade_list= { x = 1, y = 2 },          -- текст апгрейда

        bar = {
            x = 0, y = 6,
            width = 10,
            char = string.char(127),
        },
        bar_text = {
            dash_x = 10,
            percent_x = 11,
            unit_x = 14,
            y = 6,
        },

        gene_grid = {
            start_x = 18,
            start_y = 2,
            spacing_x = 1,
        },
    },
    placeholders = {
        no_bee = "  -E M P T Y-  ",   -- 14 символов
        no_upgrade = "--------------", -- 14 дефисов
        no_gene = "-",
        colors = {
            empty = colors.red,
            dash = colors.lightGray,
            percent = colors.yellow,
        },
    },
    pagination = {
        x = 44,
        y = 33,
        color = colors.white,
    },
    timings = {
        data_update = 5,
        page_flip = 8,
    },
        timer = {
        x = 2,
        y = 33,
        color = colors.green,
        bg = colors.black,
    },
     
}