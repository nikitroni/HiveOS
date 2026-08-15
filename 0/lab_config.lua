-- lab_config.lua
return {
    -- Имена периферийных устройств (можно заменить на свои)
    buffer_chest = "minecraft:barrel_0",      -- сундук для временного хранения (очистка улья)
    cage_chest   = "minecraft:barrel_2",      -- сундук с пустыми клетками (productivebees:bee_cage or productivebees:sturdy_bee_cage)
    lab_chest    = "minecraft:barrel_1",      -- сундук, куда отправляются пчёлы в клетках
    -- Канал rednet для связи с лабораторным терминалом
    rednet_channel = 1234,
    -- Файл блокировки (хранит ID улья, который сейчас обрабатывается)
    lock_file = "lab_lock.dat",
}