-- CrateRush
-- constants/factions.lua - Canonical faction constants and validation helpers.

CrateRush.FACTION = {
    HORDE    = "HORDE",
    ALLIANCE = "ALLIANCE",
}

CrateRush.FACTION_INFO = {
    [CrateRush.FACTION.HORDE] = {
        key  = CrateRush.FACTION.HORDE,
        localeKey = "FACTION_HORDE",
        fallbackName = "Horde",
    },
    [CrateRush.FACTION.ALLIANCE] = {
        key  = CrateRush.FACTION.ALLIANCE,
        localeKey = "FACTION_ALLIANCE",
        fallbackName = "Alliance",
    },
}

CrateRush.FACTION_FALLBACK_KEY = CrateRush.FACTION.HORDE

function CrateRush.normalizeFactionKey(value)
    local key = value and tostring(value):upper() or nil
    if key and CrateRush.FACTION_INFO[key] then
        return key
    end
    return nil
end

function CrateRush.getFactionName(key)
    local faction = key and CrateRush.FACTION_INFO[key] or nil
    if not faction then return nil end

    local L = CrateRush.L
    local localized = L and faction.localeKey and L[faction.localeKey] or nil
    if localized and localized ~= faction.localeKey then
        return localized
    end

    return faction.fallbackName
end

function CrateRush.getFactionEnglishName(key)
    local faction = key and CrateRush.FACTION_INFO[key] or nil
    return faction and faction.fallbackName or nil
end

function CrateRush.getFallbackFactionKey()
    return CrateRush.FACTION_FALLBACK_KEY
end

function CrateRush.resolveFactionKey(value)
    return CrateRush.normalizeFactionKey(value) or CrateRush.getFallbackFactionKey()
end

function CrateRush.resolveFactionName(value)
    return CrateRush.getFactionName(CrateRush.resolveFactionKey(value))
end

function CrateRush.resolveFactionEnglishName(value)
    return CrateRush.getFactionEnglishName(CrateRush.resolveFactionKey(value))
end

function CrateRush.getOppositeFactionKey(value)
    local key = CrateRush.resolveFactionKey(value)
    if key == CrateRush.FACTION.HORDE then
        return CrateRush.FACTION.ALLIANCE
    end
    return CrateRush.FACTION.HORDE
end
