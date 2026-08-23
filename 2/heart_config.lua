-- heart_config.lua
-- Конфигурация HeartOS (центральный терминал управления)
-- Настраивается вручную

return {
    -- Монитор, подключённый вплотную к верхней стороне терминала
    main_monitor = "top",

    -- Rednet-канал для связи с BeeOS и LabOS
    rednet_channel = 1234,

    -- Rednet ID терминалов BeeOS и LabOS
    beeos_id = 0,
    labos_id = 1,
}