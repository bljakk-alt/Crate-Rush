-- CrateRush
-- locale/ruRU.lua — Russian

local L = CrateRush.locale:NewLocale("CrateRush", "ruRU")
if not L then return end

-- Addon Info
L["ADDON_LOADED"]          = "CrateRush загружен. Введите /cr для помощи."

-- Messages
L["WARMODE_REQUIRED"]      = "Для отслеживания ящиков требуется режим войны."
L["PLANE_SPOTTED"]         = "Самолёт замечен в %s!"
L["CRATE_DROPPING"]        = "Ящик падает в %s!"
L["CRATE_LANDED"]          = "Ящик приземлился в %s!"
L["CRATE_CLAIMED"]         = "Ящик захвачен %s в %s!"
L["NEXT_SPAWN"]            = "Следующее появление в %s примерно через %d минут."
