-- device_types.lua
-- Список типов периферии для поиска при создании конфига.
-- Каждый элемент описывает: что ищем, какой метод проверяем, сколько можно добавить.
-- Можно редактировать вручную: добавлять новые типы, менять методы проверки, лимиты.
--
-- Формат:
-- {
--   key = "уникальный_ключ",                     -- ключ в конфиге
--   label = "Название для чата",                  -- что пишем в чат
--   checkMethods = {"метод1", "метод2"},           -- методы для проверки типа
--   max = 1 или nil,                               -- 1 = только один, nil = безлимит
--   group = "beeos" | "labos" | "hives",           -- к какой системе относится
-- }
--
-- ВНИМАНИЕ: все блоки из списка ОБЯЗАТЕЛЬНЫ к добавлению.
-- Пропустить блок нельзя — мастер будет запрашивать его, пока не получит.
-- Если какое-то устройство физически отсутствует — удали его из этого файла.

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
        key = "cage_chest",
        label = "Cage Chest",
        checkMethods = {"list", "getItemDetail", "pushItems"},
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
        key = "resource_chest",
        label = "Resource Chest (Honey, Treat)",
        checkMethods = {"list", "getItemDetail", "pushItems"},
        max = 1,
        group = "labos",
    },

    -- ==================== HIVES (HeartOS) ====================
    -- Для каждого улья сканируются и добавляются 3 блока:
    -- сам улей (hive_block), ридер (reader_block) и реле (relay_block).
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