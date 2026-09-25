-- HUD_info_config_1
return {
-- Main grid (Grid)
    grid = {
        start_x = 4,          -- cell start
        start_y = 2,          
        cols = 3,
        rows = 10,
        offset_x = 15,        -- 13 (cell) + 2 (gap) = 15
        offset_y = 3,         -- 2 (cell) + 1 (gap) = 3
        hives_per_page = 30
},

    -- Inner text offsets
    offsets = {
        hive_text = { x = 0, y = 0 },   
        bee_name = { x = 0, y = 1 },            -- bee name
        bee_prefix  = { x = 0, y = 1 },        -- "-" before the bee name
    },

    -- Text and placeholder parameters
    labels = {
        -- Header format: "---HIVE#01---"
        hive_template = "---HIVE#%02d---", 
        -- If there are no bees
        no_bee = "-	E M P T Y -", 
        -- Bee format: "-Conductivex5" (name truncated to 10 characters so x5 fits)
        bee_format = "-%-10sx%d", 
        
        colors = {
            hive = colors.yellow,
            bee = colors.white,
            empty = colors.red,
        }
    },

    -- Navigation buttons (Footer)
    footer = {
        y = 32,
        back = { x = 35, label = "BACK", bg = colors.red, fg = colors.black },
        page = { x = 39, label = "%02d/%02d", bg = colors.black, fg = colors.white }, -- format 01/02
        next = { x = 44, label = "NEXT", bg = colors.green, fg = colors.black }
    },
    screen = {
    back_button = { x1 = 35, y1 = 31, x2 = 37, y2 = 33 }, -- width 4, height 3
    next_button = { x1 = 44, y1 = 31, x2 = 47, y2 = 33 },
},
}