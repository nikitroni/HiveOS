-- test_chamber_methods.lua
local chamber = peripheral.wrap("productivebees:breeding_chamber_1")
print("Methods:")
for k, v in pairs(chamber) do
    if type(v) == "function" then
        print("  " .. k)
        -- Попробуем вызвать без аргументов (осторожно)
        local ok, res = pcall(v, chamber)
        if ok then
            print("    -> " .. tostring(res))
        end
    end
end