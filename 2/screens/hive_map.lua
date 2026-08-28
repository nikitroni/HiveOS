-- hive_map.lua
-- Thick wrapper over hive_wizard.lua.
-- Entry point HiveMap.run(mon, heartConfig) kept for main_menu.lua.

local HiveWizard = require("hive_wizard")

local HiveMap = {}

--- Launch the hive scanning wizard
--- @param mon table monitor
--- @param heartConfig table HeartOS config
function HiveMap.run(mon, heartConfig)
  HiveWizard.create(mon, heartConfig)
end

return HiveMap