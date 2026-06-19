-- CrateRush
-- logic/crateCycleAnchorService.lua - Accepted crate cycle anchor matcher.

local crateCycleAnchorService = {}
CrateRush.crateCycleAnchorService = crateCycleAnchorService

local function isKnownAnchorNpc(npcName)
    if not CrateRush.CRATE_CYCLE_ANCHOR_NPC_NAMES then return false end
    for knownName in pairs(CrateRush.CRATE_CYCLE_ANCHOR_NPC_NAMES) do
        local ok, matches = pcall(function()
            return npcName == knownName
        end)
        if ok and matches then
            return true
        end
    end
    return false
end

function crateCycleAnchorService:isCrateCycleAnchor(text, npcName)
    if not text or not npcName then return false end
    if not isKnownAnchorNpc(npcName) then
        return false
    end

    local ok, lowerText = pcall(function()
        return text:lower()
    end)
    if not ok or not lowerText then return false end

    if CrateRush.CRATE_CYCLE_ANCHOR_PHRASES then
        for _, phrase in ipairs(CrateRush.CRATE_CYCLE_ANCHOR_PHRASES) do
            local foundOk, found = pcall(function()
                return lowerText:find(phrase, 1, true)
            end)
            if foundOk and found then
                return true
            end
        end
    end

    return false
end
