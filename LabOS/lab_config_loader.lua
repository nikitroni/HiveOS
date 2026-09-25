-- lab_config_loader.lua
-- LabOS peripheral adapter.
--
-- LabOS uses the static library lab_lib.lua (HUD coordinates, genes,
-- settings - without peripherals) and the dynamic config labos_config.lua from HeartOS
-- (peripheral names only, flat keys).
--
-- Adapter tasks:
--   1. Load lab_lib.lua (static base).
--   2. Load labos_config.lua (peripherals from HeartOS).
--   3. Map HeartOS flat keys onto the structure expected by the modules
--      lab_*.lua (gene_indexer -> bee_indexer, crafter_1..4 -> crafters[1..4],
--      refresh -> button_monitors.breed, relay_incubator -> relay, etc.).
--   4. Merge peripheral names into lab_lib.peripherals.
--
-- Consumers (lab_utils, lab_hud, etc.) read require("lab_lib").peripherals
-- - they don't need to change them themselves.

local LAB_LIB_FILE = "lab_lib.lua"
local LABOS_CONFIG_FILE = "labos_config.lua"

-- ==================== FILE LOADING ====================

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

-- ==================== DYNAMIC -> STATIC MAPPING ====================

-- Correspondence of HeartOS flat keys -> lab.peripherals structure.
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
    -- New key gene_produce (the button was renamed). The old bee_produce
    -- is also mapped here for compatibility - the HeartOS config may contain
    -- either bee_produce or gene_produce; both -> button_monitors.gene_produce.
    { key = "gene_produce",      set = { "button_monitors", "gene_produce" } },
    -- Breeding button: in the HeartOS config the key is "breed".
    { key = "breed",             set = { "button_monitors", "breed" } },
}

-- Applies the dynamic peripherals on top of the static base.
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

-- ==================== PERIPHERAL PRESENCE CHECK ====================

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

-- ==================== ASSEMBLY ====================

-- Load the lab library (with peripheral reassembly).
-- Returns lab_lib with merged peripherals.
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

    -- Consumers require("lab_lib") get a fresh library each time,
    -- but so that updates work without restarting the terminal, the cache is reset.
    package.loaded["lab_lib"] = labLib
    return labLib
end

-- Reassemble after receiving a new dynamic config.
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