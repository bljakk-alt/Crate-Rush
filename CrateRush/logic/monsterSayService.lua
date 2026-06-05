-- CrateRush
-- logic/monsterSayService.lua - Monster say crate announcement matcher.

local monsterSayService = {}
CrateRush.monsterSayService = monsterSayService

function monsterSayService:isCrateAnnouncement(text, npcName)
    if not text or not npcName then return false end
    if not CrateRush.CRATE_NPC_NAMES or not CrateRush.CRATE_NPC_NAMES[npcName] then return false end

    local lowerText = text:lower()
    if CrateRush.CRATE_NPC_PHRASES then
        for _, phrase in ipairs(CrateRush.CRATE_NPC_PHRASES) do
            if lowerText:find(phrase, 1, true) then
                return true
            end
        end
    end

    return false
end
