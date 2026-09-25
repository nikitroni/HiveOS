-- tech/HUD_tech_config_2.lua
-- Detailed screen configuration for the technical monitor
-- Shown when a hive is clicked in the list

return {
    -- Decorative honeycomb pattern (drawn on top of the background, if needed)
    honeycomb = {
        start_x = 20,
        start_y = 1,
        pattern = {
            "      __      __      __      ",
            "     /  \\    /  \\    /  \\     ",
            "  __/ \\/ \\__/ \\/ \\__/ \\/ \\__  ",
            " /  \\ /\\ /  \\ /\\ /  \\ /\\ /  \\ ",
            "/ \\/ \\__/ \\/ \\__/ \\/ \\__/ \\/ \\",
            "\\ /\\ /  \\ /\\ /  \\ /\\ /  \\ /\\ /",
            " \\__/ \\/ \\__/ \\/ \\__/ \\/ \\__/ ",
            "    \\ /\\ /  \\ /\\ /  \\ /\\ /    ",
            "     \\__/    \\__/    \\__/     ",
        },
    },

    -- Hive statistics block (upper left part)
    stats_hive = {
        bg = colors.black,   -- block background (if not overridden by .nfp)
        hive_text   = { x = 3, y = 2 },            -- header position "---HIVE#01---"
        hive_template = " ---HIVE#%02d--- ",       -- header format

        upgrade_list = { x = 4, y = 3 },            -- first upgrade row
        upgrade_count = 4,                           -- total upgrade rows

        bar = {                                     -- progress bar
            x = 3, y = 7,
            width = 10,
            char = string.char(127),                 -- character ░
        },
        bar_text = {                                 -- text after the bar
            dash_x   = 13,   -- position of the dash '-'
            percent_x = 14,   -- position of the percent digits
            unit_x   = 17,    -- position of the '%' sign
        },

        -- Inventory statistics (slots, combs, pollen)
        rows = {
            slots = { y = 8, x = 3, label = "Slots -",  value_x = 10 },  -- example: "Slots - 5/9"
            comb  = { y = 9, x = 3, label = "Comb  -",  value_x = 10 },  -- total number of combs/blocks
            puff  = { y = 10, x = 3, label = "Puff  -", value_x = 10 },  -- amount of pollen
        },
    },

    -- Grid for bee cards (5 bees maximum)
    grid = {
        start_x = 3,
        start_y = 11,
        cols = 3,
        rows = 2,               -- 3x2 = 6 cells, but only 5 are used (first row 3, second row 2)
        offset_x = 15,           -- cell width + gap
        offset_y = 12,           -- cell height + gap

        -- Offsets inside a cell (relative to its top-left corner)
        offsets = {
            title = { x = 1, y = 1 },               -- bee name (with number, e.g. "Draconic#1")

            -- Gene headers (always shown, even if there is no bee? per your description - only if a bee exists)
            gene_Productivity     = { x = 1, y = 2 },
            gene_W_Tolerance      = { x = 1, y = 4 },
            gene_Behavior         = { x = 1, y = 6 },
            gene_Endurance        = { x = 1, y = 8 },

            -- Gene values
            gene_Productivity_val = { x = 1, y = 3 },
            gene_W_Tolerance_val  = { x = 1, y = 5 },
            gene_Behavior_val     = { x = 1, y = 7 },
            gene_Endurance_val    = { x = 1, y = 9 },

            prefix_gene = { x = 0, y = 2 },          -- character ">" or "-" before genes (optional)
        },
    },

    -- Text labels for the footer (display)
    footer = {
        y = 32,
        back = { x = 35, label = "BACK",  bg = colors.red,   fg = colors.black },
        page = { x = 39, label = "%02d/%02d", bg = colors.black, fg = colors.white }, -- current hive number / total
        next = { x = 44, label = "NEXT",  bg = colors.green, fg = colors.black },
    },

    -- Clickable areas (buttons)
    screen = {
        lab_button = { x1 = 35, y1 = 23, x2 = 47, y2 = 29 },   -- large LAB button
        back_button = { x1 = 35, y1 = 31, x2 = 38, y2 = 33 },   -- ◄ or BACK
        page_button = { x1 = 39, y1 = 31, x2 = 43, y2 = 33 },   -- return to the hive list
        next_button = { x1 = 44, y1 = 31, x2 = 47, y2 = 33 },   -- ► or NEXT
    },

    -- Placeholders and helper constants
    labels = {
        no_bee = " -- EMPTY-- ",   -- shown in a cell if there is no bee
    },
}