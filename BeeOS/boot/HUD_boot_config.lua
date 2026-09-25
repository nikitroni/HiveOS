-- boot_config.lua
return {
    -- Progress bar area (rectangle to be filled in green)
    progress_area = {
        minX = 11,   -- left border (column)
        maxX = 40,   -- right border
        minY = 19,   -- top border (row)
        maxY = 27,   -- bottom border (if single row)
    },

    -- All characters to be drawn on top of the background
    -- Format: [rowY] = { [columnX] = {char = "symbol", fg = color}, ... }
    honeycomb_pattern = {
        "      __      __      __      ",
        "     /  \\    /  \\    /  \\     " ,
        "  __/ \\/ \\__/ \\/ \\__/ \\/ \\__  ",
        " /  \\ /\\ /  \\ /\\ /  \\ /\\ /  \\ " ,
        "/ \\/ \\__/ \\/ \\__/ \\/ \\__/ \\/ \\" ,
        "\\ /\\ /  \\ /\\ /  \\ /\\ /  \\ /\\ /",
        " \\__/ \\/ \\__/ \\/ \\__/ \\/ \\__/ ",
        "    \\ /\\ /  \\ /\\ /  \\ /\\ /    ",
        "     \\__/    \\__/    \\__/     ",
    },
    pattern_start = { x=11, y=19},
    foreground = {
        -- Percentage digits (initially 0 0 0)
        [30] = {
            [24] = {char = "0", fg = colors.yellow},
            [25] = {char = "0", fg = colors.yellow},
            [26] = {char = "0", fg = colors.yellow},
            [27] = {char = "%", fg = colors.yellow},
        },
        -- If there are other characters (letters, frames) - add similarly
    },

    -- Percentage digit coordinates (for fast updates)
    percent_digits = {
        {x = 24, y = 30},
        {x = 25, y = 30},
        {x = 26, y = 30}
    },

    -- -- Percent sign coordinate
    percent_sign = {x = 27, y = 30}
}