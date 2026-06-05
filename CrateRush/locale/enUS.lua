-- CrateRush
-- locale/enUS.lua — English strings.

local L = CrateRush.locale:NewLocale("CrateRush", "enUS", true)
if not L then return end

L["ADDON_LOADED"]       = "CrateRush loaded."
L["WARMODE_REQUIRED"]   = "War Mode is required to track crates."
L["PLANE_SPOTTED"]      = "War Supply Crate detected flying in %s [shard %s]"
L["CRATE_DROPPING"]     = "War Supply Crate dropping in %s [shard %s]"
L["CRATE_LANDED"]       = "War Supply Crate LANDED in %s [shard %s] - GO NOW!"
L["CRATE_CLAIMED"]      = "War Supply Crate claimed in %s [shard %s]"
L["NEXT_SPAWN"]         = "Next spawn in %s in approximately %d minutes."

CrateRush.L = CrateRush.locale:GetLocale("CrateRush")
