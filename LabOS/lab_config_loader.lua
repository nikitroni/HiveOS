-- lab_config_loader.lua
-- Адаптер периферии LabOS.
--
-- LabOS использует статичную библиотеку lab_lib.lua (координаты HUD, гены,
-- настройки — без периферии) и динамичный конфиг labos_config.lua от HeartOS
-- (только имена периферии, плоские ключи).
--
-- Задачи адаптера:
--   1. Загрузить lab_lib.lua (статичная база).
--   2. Загрузить labos_config.lua (периферия от HeartOS).
--   3. Смапить плоские ключи HeartOS на структуру, которую ожидают модули
--      lab_*.lua (gene_indexer -> bee_indexer, crafter_1..4 -> crafters[1..4],
--      refresh -> button_monitors.breed, relay_incubator -> relay и т.д.).
--   4. Подмешать имена периферии в lab_lib.peripherals.
--
-- Потребители (lab_utils, lab_hud и др.) читают require("lab_lib").peripherals
-- — сами их менять не нужно.

local LAB_LIB_FILE = "lab_lib.lua"
local LABOS_CONFIG_FILE = "labos_config.lua"

-- ==================== ЗАГРУЗКА ФАЙЛОВ ====================

local function loadTableFile(path)
    if not fs.exists(path) then
        return nil
    end
    local fn, err = loadfile(path)
    if not fn then
        print("lab_config_loader: cannot load " .. path .. ": " .. tostring(err))
        return nil
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "table" then
        return result
    end
    print("lab_config_loader: invalid format in " .. path)
    return nil
end

-- ==================== МАППИНГ ДИНАМИЧЕСКОГО -> СТАТИЧЕСКОГО ====================

-- Соответствие плоских ключей HeartOS -> структуре lab.peripherals.
local MAP = {
    { key = "main_monitor",      set = { "main_monitor" } },
    { key = "lab_chest",         set = { "lab_chest" } },
    { key = "resource_chest",    set = { "resource_chest" } },
    { key = "reader_bee",        set = { "reader_bee" } },
    { key = "reader_indexer",    set = { "reader_indexer" } },
    { key = "gene_indexer",      set = { "bee_indexer" } },
    { key = "breeding_chamber",  set = { "breeding_chamber" } },
    { key = "incubator",         set = { "incubator" } },
    { key = "relay_incubator",   set = { "relay" } },
    { key = "clicker_breeding_relay", set = { "clicker_breeding_relay" } },
    { key = "crafter_1",         set = { "crafters", 1 } },
    { key = "crafter_2",         set = { "crafters", 2 } },
    { key = "crafter_3",         set = { "crafters", 3 } },
    { key = "crafter_4",         set = { "crafters", 4 } },
    { key = "bee_out",           set = { "button_monitors", "bee_out" } },
    { key = "gene_upgrade",      set = { "button_monitors", "gene_upgrade" } },
    -- Новый ключ gene_produce (кнопка переименована). Старый bee_produce
    -- тоже мапится сюда для совместимости - конфиг HeartOS может содержать
    -- либо bee_produce, либо gene_produce; оба -> button_monitors.gene_produce.
    { key = "gene_produce",      set = { "button_monitors", "gene_produce" } },
    -- Кнопка размножения: в конфиге HeartOS ключ "breed".
    { key = "breed",             set = { "button_monitors", "breed" } },
}

-- Применяет динамическую периферию поверх статической базы.
local function mergePeripheralNames(labLib, dynamicConfig)
    local dynamicPeripherals = dynamicConfig.peripherals
    if type(dynamicPeripherals) ~= "table" then
        return
    end

    local target = labLib.peripherals
    if type(target) ~= "table" then
        target = {}
        labLib.peripherals = target
    end

    for _, mapping in ipairs(MAP) do
        local value = dynamicPeripherals[mapping.key]
        if type(value) == "string" and value ~= "" then
            local node = target
            for i = 1, #mapping.set - 1 do
                local k = mapping.set[i]
                if type(node[k]) ~= "table" then
                    node[k] = {}
                end
                node = node[k]
            end
            node[mapping.set[#mapping.set]] = value
        end
    end
end

-- ==================== ПРОВЕРКА НАЛИЧИЯ ПЕРИФЕРИИ ====================

local function checkPeripherals(labLib)
    local p = labLib.peripherals
    if type(p) ~= "table" then return end

    local function checkName(name, label)
        if type(name) ~= "string" or name == "" then return end
        if not peripheral.isPresent(name) then
            print("lab_config_loader: peripheral '" .. name .. "' not present (" .. tostring(label) .. ")")
        end
    end

    checkName(p.main_monitor, "main_monitor")
    checkName(p.lab_chest, "lab_chest")
    checkName(p.resource_chest, "resource_chest")
    checkName(p.reader_bee, "reader_bee")
    checkName(p.reader_indexer, "reader_indexer")
    checkName(p.bee_indexer, "bee_indexer")
    checkName(p.breeding_chamber, "breeding_chamber")
    checkName(p.incubator, "incubator")
    checkName(p.relay, "relay")
    checkName(p.clicker_breeding_relay, "clicker_breeding_relay")
    checkName(labLib.chat_box, "chat_box")
    if type(p.crafters) == "table" then
        for i, v in ipairs(p.crafters) do
            checkName(v, "crafter_" .. i)
        end
    end
    if type(p.button_monitors) == "table" then
        for name, v in pairs(p.button_monitors) do
            checkName(v, "button_monitor:" .. name)
        end
    end
end

-- ==================== СБОРКА ====================

-- Загрузить библиотеку лабы (с пересборкой периферии).
-- Возвращает lab_lib с подмешанной периферией.
local function load()
    local labLib = loadTableFile(LAB_LIB_FILE)
    if not labLib then
        error("lab_config_loader: static lab_lib.lua not found or invalid")
    end

    local dynamicConfig = loadTableFile(LABOS_CONFIG_FILE)
    if dynamicConfig then
        mergePeripheralNames(labLib, dynamicConfig)
    end

    checkPeripherals(labLib)

    -- Потребители require("lab_lib") получают свежую библиотеку каждый раз,
    -- но чтобы обновление работало без перезагрузки терминала, кэш сбрасываем.
    package.loaded["lab_lib"] = labLib
    return labLib
end

-- Пересобрать после приёма нового динамического конфига.
local function reload()
    package.loaded["lab_lib"] = nil
    package.loaded["lab_hud"] = nil
    package.loaded["lab_buttons"] = nil
    package.loaded["lab_processor"] = nil
    package.loaded["lab_utils"] = nil
    package.loaded["lab_breeding"] = nil
    package.loaded["lab_geneproduction"] = nil
    return load()
end

return {
    load = load,
    reload = reload,
}