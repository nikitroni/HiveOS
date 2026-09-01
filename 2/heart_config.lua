-- heart_config.lua
-- HeartOS (central management terminal) config.
-- Edited manually. The `hud` section holds the layout of every screen.
--
-- UNIFORM ELEMENT SPEC - every element uses the same color names:
--   Text  (title/hint/desc/page): x, y, text, textColor, bgColor
--   Button: id, label, x, y, w, h, textColor, bgColor
--     * textColor - color of the text/label
--     * bgColor   - background behind the text, or button fill
--   x = nil centers horizontally, y = nil uses the bottom row (h - 1).
-- Set bgColor to the nfp panel color behind an element so it blends with
-- the background instead of painting a black box over the image.

return {
  main_monitor = "top",

  -- Rednet channel for communication with BeeOS and LabOS
  rednet_channel = 1234,

  -- Rednet IDs of the BeeOS and LabOS terminals
  beeos_id = 0,
  labos_id = 1,

  hud = {
    text_scale = 1,

    main_menu = {
      path = "screens/HUD/HeartOS_main_menu.nfp",
      title = { x = 11, y = 2, text = "=== HeartOS Control Center ===", textColor = "yellow", bgColor = "gray" },
      hint = { x = 3, y = 25, text = "Select an option above", textColor = "white", bgColor = "gray" },
      buttons = {
        { id = "beeos", label = "\n   Configure BeeOS", action = "beeos", x=15, y=7, w=21, h=3, bgColor = "cyan", textColor = "white" },
        { id = "labos", label = "\n   Configure LabOS  ", action = "labos", x=15, y=11, w=21, h=3, bgColor = "blue", textColor = "white" },
        { id = "hivemap", label = "\n   Configure Hive  ", action = "hivemap", x=15, y=15, w=21, h=3, bgColor = "purple", textColor = "white" },
        { id = "library", label = "\n      LIBRARY  ", action = "library", x=15, y=19, w=21, h=3, bgColor = "brown", textColor = "white" },
      },
    },

    beeos = {
      path = "screens/HUD/BeeOS_LabOS__Hive_menu_1.nfp",
      title = { x = 11, y = 2, text = "   ===   Configure BeeOS   ===", textColor = "yellow", bgColor = "gray" },
      back = { id = "back", label = "\n[ Back ]", action = "back", x=3, y=23, w=8, h=3, bgColor = "red", textColor = "white" },
      columns = {
        {
          id = "create",
          title = { x = 4, y = 6, text = "   Create   ", textColor = "black", bgColor = "green" },
          desc = { x = 4, y = 8, text = "Start a new\ndevice config\nuration. All\ncurrent set\ntings will be\noverwritten.", textColor = "white", bgColor = "gray" },
          start = { x = 6, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "edit",
          title = { x = 20, y = 6, text = "    Edit   ", textColor = "black", bgColor = "orange" },
          desc = { x = 20, y = 8, text = "Modify exist\ning device\nsettings. You\ncan change\nor remove\ndevices.", textColor = "white", bgColor = "gray" },
          start = { x = 22, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "view",
          title = { x = 36, y = 6, text = "    View   ", textColor = "black", bgColor = "blue" },
          desc = { x = 36, y = 8, text = "Display the\ncurrent\ndevice config\nuration\nfor review.", textColor = "white", bgColor = "gray" },
          start = { x = 38, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
      },
    },

    labos = {
      path = "screens/HUD/BeeOS_LabOS__Hive_menu_1.nfp",
      title = { x = 11, y = 2, text = "===   Configure LabOS   ===", textColor = "yellow", bgColor = "gray" },
      back = { id = "back", label = "\n[ Back ]", action = "back", x=3, y=23, w=8, h=3, bgColor = "red", textColor = "white" },
      columns = {
        {
          id = "create",
          title = { x = 4, y = 6, text = "   Create   ", textColor = "black", bgColor = "green" },
          desc = { x = 4, y = 8, text = "Start a new\ndevice config\nuration. All\ncurrent set\ntings will be\noverwritten.", textColor = "white", bgColor = "gray" },
          start = { x = 6, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "edit",
          title = { x = 20, y = 6, text = "    Edit   ", textColor = "black", bgColor = "orange" },
          desc = { x = 20, y = 8, text = "Modify exist\ning device\nsettings. You\ncan change\nor remove\ndevices.", textColor = "white", bgColor = "gray" },
          start = { x = 22, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "view",
          title = { x = 36, y = 6, text = "    View   ", textColor = "black", bgColor = "blue" },
          desc = { x = 36, y = 8, text = "Display the\ncurrent\ndevice config\nuration\nfor review.", textColor = "white", bgColor = "gray" },
          start = { x = 38, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
      },
    },

    hive = {
      path = "screens/HUD/BeeOS_LabOS__Hive_menu_1.nfp",
      title = { x = 11, y = 2, text = "===   Configure Hive    ===", textColor = "yellow", bgColor = "gray" },
      back = { id = "back", label = "\n[ Back ]", action = "back", x=3, y=23, w=8, h=3, bgColor = "red", textColor = "white" },
      columns = {
        {
          id = "create",
          title = { x = 4, y = 6, text = "   Create   ", textColor = "black", bgColor = "green" },
          desc = { x = 4, y = 8, text = "Start a NEW\nhive map\nconfiguration\nAll current\nsettings will\nbe over\nwritten.", textColor = "white", bgColor = "gray" },
          start = { x = 6, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "edit",
          title = { x = 20, y = 6, text = "    Edit   ", textColor = "black", bgColor = "orange" },
          desc = { x = 20, y = 8, text = "Select a hive\nid (e.g.id01)\nto replace\nits blocks\nor add\na NEW hive.", textColor = "white", bgColor = "gray" },
          start = { x = 22, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
        {
          id = "hivemap",
          title = { x = 36, y = 6, text = "  HiveMap  ", textColor = "black", bgColor = "blue" },
          desc = { x = 36, y = 8, text = "Open the\nvisual hive\nmap with\nfunctional\nbuttons.", textColor = "white", bgColor = "gray" },
          start = { x = 38, y = 15, w = 9, h = 3, label = "\n [Start] ", bgColor = "lightGray", textColor = "white" },
        },
      },
    },

    create_edit = {
      path = "screens/HUD/BeeOS_LabOS_Hive_menu_2.nfp",
      -- bgColor default for wizard page text (titles and generated config
      -- lists on the menu_2 image). Set to the panel color behind the text area.
      bgColor = "lightGray",
      -- NEW: wizard page title position/colors (x = nil centers, y = nil = 2)
      title = { x = 11, y = 2, textColor = "yellow", bgColor = "gray" },
      -- NEW: work area where generated config/list text is drawn on the image.
      -- Text is clamped inside { x .. x+w-1, y .. y+h-1 } and uses bgColor.
      area = { x = 3, y = 4, w = 46, h = 18, textColor = "white", bgColor = "lightGray" },
      -- Page indicator ("Page N/M"). line moves it down inside the footer
      -- block (2 = one row below page.y, aligned with multi-line button labels).
      page = { x = 21, y = 23, line = 2, textColor = "white", bgColor = "cyan" },
      back = { x = 3, y = 23, w = 8, h = 3, label = "\n[ Back ]", action = "back", bgColor = "red", textColor = "white" },
      prev = { x = 36, y = 23, w = 6, h = 3, label = "      |\n<<Prev|\n      |", action = "prev", bgColor = "blue", textColor = "white" },
      next = { x = 42, y = 23, w = 7, h = 3, label = "|\n|Next>>\n|", action = "next", bgColor = "blue", textColor = "white" },
    },

    hive_map = {
      path = "screens/HUD/Hive_map_2.nfp",
      title = { x = 11, y = 2, text = "===   View Hive Map      ===", textColor = "yellow", bgColor = "gray" },
      signal = { id = "signal", label = "\n     Signalise", action = "signal", x = 17, y = 12, w = 18, h = 3, bgColor = "magenta", textColor = "white" },
      slot = { id = "slot", label = "\n    Coming Soon", action = "slot", x = 17, y = 17, w = 18, h = 3, bgColor = "orange", textColor = "white" },
      back = { id = "back", label = "\n[ Back ]", action = "back", x=3, y=23, w=8, h=3, bgColor = "red", textColor = "white" },

-- Hive grid. Each group maps slots 1..48 (one page) to monitor cells.
      -- slotId -> cell: the layout math is in hive_map_view.lua; the groups
      -- table lives HERE so all clickable zones come from the config.
      -- Hive cell is FIXED at 2 wide x 1 tall in code (CELL_W x CELL_H):
      --   the two digits occupy exactly 2 active cells, nothing more.
      --   gapX - blank columns between horizontal neighbours (step = CELL_W + gapX)
      --   gapY - blank rows    between vertical   neighbours (step = CELL_H + gapY)
      --   Every `sectionSize` rows/cols form a section, separated by
      --   `sectionGap` blank cells/columns.
      -- cellColors: present = hive exists in hives_map.lua, absent = empty,
      -- selected = toggled by the user (selection persists across pages).
      grid = {
        idFormat = "%02d",
        cellColors = { present = "green", absent = "lightGray", selected = "yellow" },
        groups = {
          -- Group 1: left panel, bottom-up, 2 columns x 8 rows, sections of 4 pairs.
          -- Two columns 2 blocks apart (gapX=2), rows 1 cell apart (gapY=1).
          { idStart = 1, rows = 8, cols = 2, startX = 4, startY = 5, gapX = 2, gapY = 1, sectionGap = 1, sectionSize = 4, order = "bottom_up" },
          -- Group 2: middle panel, left->right, 8 columns x 2 rows, sections of 4 cols.
          -- Columns 1 cell apart (gapX=1 -> step 3), rows 1 cell apart (gapY=1 -> step 2);
          -- sections split by 2 blank columns (gapX + sectionGap = 1 + 1).
          { idStart = 17, rows = 2, cols = 8, startX = 14, startY = 5, gapX = 1, gapY = 1, sectionGap = 1, sectionSize = 4, order = "left_right" },
          -- Group 3: right panel, top-down, 2 columns x 8 rows, sections of 4 pairs.
          { idStart = 33, rows = 8, cols = 2, startX = 42, startY = 5, gapX = 2, gapY = 1, sectionGap = 1, sectionSize = 4, order = "top_down" },
        },
      },

      -- Pagination (48 cells per page). Coordinates are skeleton placeholders,
      -- fill real values after testing (see hive_map_view.lua footer).
      page = { x = 21, y = 23, line = 2, textColor = "white", bgColor = "cyan" },
      prev = { id = "prev", label = "      |\n<<Prev|\n      |", action = "prev", x = 36, y = 23, w = 6, h = 3, bgColor = "blue", textColor = "white" },
      next = { id = "next", label = "|\n|Next>>\n|", action = "next", x = 42, y = 23, w = 7, h = 3, bgColor = "blue", textColor = "white" },

      -- Signalise cycle timing: ON `on` s, OFF `off` s, repeated `cycles` times.
      -- Total lock time = (on + off) * cycles = (2+1)*20 = 60 s.
      -- During the cycle the relay pulses and the Signalise button is locked;
      -- the chat reports the real remaining seconds.
      signal_cycle = { on = 1, off = 0.5, cycles = 20 },
    },
  },
}