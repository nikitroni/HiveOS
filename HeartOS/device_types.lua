-- device_types.lua
-- List of peripheral types to search for when creating a config.
-- Each element describes: what we search for, which method we check, how many can be added.
-- Can be edited manually: add new types, change check methods, limits.
--
-- Format:
-- {
--   key = "unique_key",                          -- key in the config
--   label = "Name for chat",                     -- what we write to chat
--   checkMethods = {"method1", "method2"},        -- methods to check the type
--   max = 1 or nil,                               -- 1 = only one, nil = unlimited
--   group = "beeos" | "labos" | "hives",          -- which system it belongs to
-- }
--
-- ATTENTION: all blocks in the list are MANDATORY to add.
-- A block cannot be skipped - the wizard will keep asking for it until it gets it.
-- If some device is physically absent - delete it from this file.

return {
    -- ==================== BEEOS ====================
    {
        key = "tech_monitor",
        label = "Tech Bee Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = nil,
        group = "beeos",
    },
    {
        key = "info_monitors",
        label = "Info Bee Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = nil,
        group = "beeos",
    },
    {
        key = "buffer_chest",
        label = "Buffer Chest",
        checkMethods = {"list", "getItemDetail", "pushItems", "pullItems"},
        max = 1,
        group = "beeos",
    },
    {
        key = "cage_chest",
        label = "Cage Chest",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "beeos",
    },
    {
        key = "lab_chest",
        label = "Lab Chest",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "beeos",
    },
     

    -- ==================== LABOS ====================
    {
        key = "main_monitor",
        label = "Lab Main Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = 1,
        group = "labos",
    },
    {
        key = "bee_out",
        label = "Bee Button Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = 1,
        group = "labos",
    },
    {
        key = "gene_upgrade",
        label = "Gene Upgrade Button Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = 1,
        group = "labos",
    },
    {
        key = "gene_produce",
        label = "Gene Produce Button Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = 1,
        group = "labos",
    },
    {
        key = "breed",
        label = "Breed Button Monitor",
        checkMethods = {"write", "setCursorPos"},
        max = 1,
        group = "labos",
    },
    {
        key = "lab_chest",
        label = "Lab Chest",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "reader_bee",
        label = "Bee Reader for Lab Chest",
        checkMethods = {"getBlockData"},
        max = 1,
        group = "labos",
    },
    {
        key = "gene_indexer",
        label = "Gene Indexer",
        checkMethods = {"list", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "reader_indexer",
        label = "Indexer Reader",
        checkMethods = {"getBlockData"},
        max = 1,
        group = "labos",
    },
    {
        key = "breeding_chamber",
        label = "Breeding Chamber",
        checkMethods = {"list", "getItemDetail"},
        max = 1,
        group = "labos",
    },
    {
        key = "crafter_1",
        label = "Crafter #1",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "crafter_2",
        label = "Crafter #2",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "crafter_3",
        label = "Crafter #3",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "crafter_4",
        label = "Crafter #4",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "incubator",
        label = "Incubator",
        checkMethods = {"list", "pushItems"},
        max = 1,
        group = "labos",
    },
    {
        key = "relay_incubator",
        label = "Relay Incubator",
        checkMethods = {"setBundledOutput", "setAnalogOutput"},
        max = 1,
        group = "labos",
    },
    {
        key = "clicker_breeding_relay",
        label = "Breeding Automation Relay",
        checkMethods = {"setBundledOutput", "setAnalogOutput"},
        max = 1,
        group = "labos",
    },
    {
        key = "resource_chest",
        label = "Resource Chest (Honey, Treat, Cage)",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },

    -- ==================== HIVES (HeartOS) ====================
    -- For each hive 3 blocks are scanned and added:
    -- the hive itself (hive_block), the reader (reader_block) and the relay (relay_block).
    {
        key = "hive_block",
        label = "Hive Block",
        checkMethods = {"list", "getItemDetail", "pushItems", "pullItems"},
        max = nil,
        group = "hives",
    },
    {
        key = "reader_block",
        label = "Hive Reader",
        checkMethods = {"getBlockData"},
        max = nil,
        group = "hives",
    },
    {
        key = "relay_block",
        label = "Redstone Relay",
        checkMethods = {"setBundledOutput", "setAnalogOutput"},
        max = nil,
        group = "hives",
    },
}