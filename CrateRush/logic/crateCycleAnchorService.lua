-- CrateRush
-- logic/crateCycleAnchorService.lua - Accepted crate cycle anchor matcher.

local crateCycleAnchorService = {}
CrateRush.crateCycleAnchorService = crateCycleAnchorService

function crateCycleAnchorService:isCrateCycleAnchor(text, npcName)
    if not text or not npcName then return false end
    if not CrateRush.CRATE_CYCLE_ANCHOR_NPC_NAMES
        or not CrateRush.CRATE_CYCLE_ANCHOR_NPC_NAMES[npcName]
    then
        return false
    end

    local lowerText = text:lower()
    if CrateRush.CRATE_CYCLE_ANCHOR_PHRASES then
        for _, phrase in ipairs(CrateRush.CRATE_CYCLE_ANCHOR_PHRASES) do
            if lowerText:find(phrase, 1, true) then
                return true
            end
        end
    end

    return false
end
