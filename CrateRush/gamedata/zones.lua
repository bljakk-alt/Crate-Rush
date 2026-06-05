-- CrateRush
-- gamedata/zones.lua - Crate zone allowlist and map ID resolution.

local zones = {}
CrateRush.ZONES = zones
CrateRush.zones = zones

CrateRush.ALLOWED_CRATE_ZONES = {
    [2248] = true, -- Isle of Dorn
    [2214] = true, -- Ringing Deeps
    [2215] = true, -- Hallowfall
    [2255] = true, -- Azj-Kahet
    [2346] = true, -- Undermine
    [2369] = true, -- Siren Isle
    [2022] = true, -- Waking Shores
    [2023] = true, -- Ohn'ahran Plains
    [2024] = true, -- Azure Span
    [2025] = true, -- Thaldraszus
    [2371] = true, -- K'aresh
    [2393] = true, -- Silvermoon City
    [2405] = true, -- Voidstorm
    [2413] = true, -- Harandar
    [2395] = true, -- Eversong Woods
    [2437] = true, -- Zul'Aman
    [2444] = true, -- Slayer's Rise
}

local CRATE_ZONE_BY_MAP_ID = {
    -- Midnight
    [2405] = 2405, -- Voidstorm
    [2444] = 2444, -- Slayer's Rise
    [2393] = 2393, -- Silvermoon City
    [2413] = 2413, -- Harandar
    [2576] = 2413, -- The Den -> Harandar
    [2395] = 2395, -- Eversong Woods
    [2437] = 2437, -- Zul'Aman
    [2536] = 2437, -- Atal'Aman -> Zul'Aman (RCT comment: ZA)

    -- The War Within
    [2213] = 2255, -- City of Threads -> Azj-Kahet
    [2214] = 2214, -- The Ringing Deeps
    [2215] = 2215, -- Hallowfall
    [2216] = 2255, -- Ara-Kara: City of Echoes -> Azj-Kahet
    [2248] = 2248, -- Isle of Dorn
    [2255] = 2255, -- Azj-Kahet
    [2256] = 2255, -- The Echoing City -> Azj-Kahet
    [2346] = 2346, -- Undermine
    [2369] = 2369, -- Siren Isle
    [2371] = 2371, -- K'aresh
    [2472] = 2371, -- Tazavesh -> K'aresh

    -- Dragonflight
    [2022] = 2022, -- The Waking Shores
    [2023] = 2023, -- Ohn'ahran Plains
    [2024] = 2024, -- The Azure Span
    [2025] = 2025, -- Thaldraszus
    [2112] = 2025, -- Valdrakken -> Thaldraszus
    [2239] = 2023, -- Bel'ameth -> Ohn'ahran Plains
}

local ZONE_CACHE = {}

local function toNumber(zoneID)
    return zoneID and tonumber(zoneID) or nil
end

local function getMapInfo(mapID)
    if not mapID or not C_Map or not C_Map.GetMapInfo then return nil end

    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok then return info end
    return nil
end

local function isAllowed(zoneID)
    zoneID = toNumber(zoneID)
    return zoneID ~= nil
        and CrateRush.ALLOWED_CRATE_ZONES ~= nil
        and CrateRush.ALLOWED_CRATE_ZONES[zoneID] == true
end

local function cacheResult(rawMapID, crateZoneID)
    ZONE_CACHE[rawMapID] = crateZoneID or false
    return crateZoneID
end

function zones:resolveCrateZoneID(mapID)
    mapID = toNumber(mapID)
    if not mapID then return nil end

    local mappedZoneID = CRATE_ZONE_BY_MAP_ID[mapID]
    if mappedZoneID ~= nil then
        return isAllowed(mappedZoneID) and mappedZoneID or nil
    end

    local cached = ZONE_CACHE[mapID]
    if cached ~= nil then
        return cached or nil
    end

    local current = mapID
    local seen = {}
    local depth = 0

    while current and not seen[current] and depth < 10 do
        seen[current] = true
        depth = depth + 1

        mappedZoneID = CRATE_ZONE_BY_MAP_ID[current]
        if mappedZoneID ~= nil then
            return cacheResult(mapID, isAllowed(mappedZoneID) and mappedZoneID or nil)
        end

        if isAllowed(current) then
            return cacheResult(mapID, current)
        end

        local info = getMapInfo(current)
        local parentMapID = info and toNumber(info.parentMapID) or nil
        if not parentMapID or parentMapID == 0 or parentMapID == current then
            break
        end

        current = parentMapID
    end

    return cacheResult(mapID, nil)
end

function zones:isAllowedCrateZone(mapID)
    return self:resolveCrateZoneID(mapID) ~= nil
end

function zones:getCrateZoneName(mapID)
    local crateZoneID = self:resolveCrateZoneID(mapID) or toNumber(mapID)
    if not crateZoneID then return "Unknown" end

    local info = getMapInfo(crateZoneID)
    return (info and info.name) or tostring(crateZoneID)
end

function CrateRush.resolveCrateZoneID(mapID)
    return zones:resolveCrateZoneID(mapID)
end

function CrateRush.isAllowedCrateZone(mapID)
    return zones:isAllowedCrateZone(mapID)
end

function CrateRush.getCrateZoneName(mapID)
    return zones:getCrateZoneName(mapID)
end
