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
    },
  },
}