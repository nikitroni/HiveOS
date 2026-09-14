-- dump_peripherals.lua
-- Dump all peripherals, their types, methods, and try to get additional info.

local filename = "peripheral_dump.txt"

local file = fs.open(filename, "w")
if not file then
    print("Failed to open file for writing.")
    return
end

local names = peripheral.getNames()
if #names == 0 then
    file.writeLine("No peripherals found.")
    file.close()
    print("No peripherals found.")
    return
end

file.writeLine("=== Peripheral Dump ===")
file.writeLine("Total devices: " .. #names)
file.writeLine("")

-- Helper: try to call a method and return result or error string
local function tryMethod(p, method, ...)
    if type(p[method]) ~= "function" then
        return nil, "method not found"
    end
    local ok, result = pcall(p[method], ...)
    if ok then
        return result, nil
    else
        return nil, tostring(result)
    end
end

-- Helper: format a value for output
local function formatValue(v)
    if type(v) == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostring(val))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

for _, name in ipairs(names) do
    file.writeLine("----------------------------------------")
    file.writeLine("Peripheral: " .. name)

    -- Type
    local pType = peripheral.getType(name)
    if pType then
        file.writeLine("  Type: " .. pType)
    else
        file.writeLine("  Type: (unknown)")
    end

    -- Wrap
    local p = peripheral.wrap(name)
    if not p then
        file.writeLine("  (failed to wrap)")
        file.writeLine("")
    else
        -- Methods
        local methods = peripheral.getMethods(name)
        if methods and #methods > 0 then
            file.writeLine("  Methods (" .. #methods .. "):")
            for _, method in ipairs(methods) do
                file.writeLine("    " .. method)
            end
        else
            file.writeLine("  Methods: (none or unable to retrieve)")
        end

        -- Additional info attempts
        file.writeLine("  --- Additional info ---")

        -- Monitor size
        local size, err = tryMethod(p, "getSize")
        if size then
            file.writeLine("  getSize() -> " .. formatValue(size))
        end

        -- Inventory size / list
        local invSize, err = tryMethod(p, "size")
        if invSize then
            file.writeLine("  size() -> " .. formatValue(invSize))
        end

        local list, err = tryMethod(p, "list")
        if list then
            local count = 0
            for _ in pairs(list) do count = count + 1 end
            file.writeLine("  list() -> " .. count .. " item(s)")
        end

        -- Energy
        local energy, err = tryMethod(p, "getEnergy")
        if energy then
            file.writeLine("  getEnergy() -> " .. formatValue(energy))
        end

        local energyStored, err = tryMethod(p, "getEnergyStored")
        if energyStored then
            file.writeLine("  getEnergyStored() -> " .. formatValue(energyStored))
        end

        local maxEnergy, err = tryMethod(p, "getMaxEnergyStored")
        if maxEnergy then
            file.writeLine("  getMaxEnergyStored() -> " .. formatValue(maxEnergy))
        end

        -- Fluids
        local fluid, err = tryMethod(p, "getFluid")
        if fluid then
            file.writeLine("  getFluid() -> " .. formatValue(fluid))
        end

        local tanks, err = tryMethod(p, "getTanks")
        if tanks then
            file.writeLine("  getTanks() -> " .. formatValue(tanks))
        end

        -- Block data (for readers)
        local blockData, err = tryMethod(p, "getBlockData")
        if blockData then
            file.writeLine("  getBlockData() -> " .. formatValue(blockData))
        end
    end

    file.writeLine("") -- empty line between devices
end

file.close()
print("Dump written to " .. filename)