-- CrateRush
-- logic/zoneResolver.lua - Crate zone resolution service.

local zoneResolver = {}
CrateRush.zoneResolver = zoneResolver

local function toNumber(value)
    return value and tonumber(value) or nil
end

function zoneResolver:resolveCrateZoneID(mapID)
    if CrateRush.zones and CrateRush.zones.resolveCrateZoneID then
        return CrateRush.zones:resolveCrateZoneID(mapID)
    end

    if CrateRush.resolveCrateZoneID then
        return CrateRush.resolveCrateZoneID(mapID)
    end

    return toNumber(mapID) or mapID
end

function zoneResolver:isAllowedCrateZone(mapID)
    return self:resolveCrateZoneID(mapID) ~= nil
end

function zoneResolver:getMapName(mapID)
    if not mapID then return "Unknown" end
    if not C_Map or not C_Map.GetMapInfo then return tostring(mapID) end

    local ok, mapInfo = pcall(C_Map.GetMapInfo, mapID)
    if ok and mapInfo and mapInfo.name then
        return mapInfo.name
    end

    return tostring(mapID)
end

function zoneResolver:getCrateZoneName(mapID)
    if not mapID then return "Unknown" end

    if CrateRush.zones and CrateRush.zones.getCrateZoneName then
        return CrateRush.zones:getCrateZoneName(mapID)
    end

    if CrateRush.getCrateZoneName then
        return CrateRush.getCrateZoneName(mapID)
    end

    local crateZoneID = self:resolveCrateZoneID(mapID) or toNumber(mapID) or mapID
    return self:getMapName(crateZoneID)
end

function zoneResolver:getPlayerMapID()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return mapID end
    return nil
end

function zoneResolver:getPlayerCrateZoneID()
    return self:resolveCrateZoneID(self:getPlayerMapID())
end

function zoneResolver:getPlayerZoneContext()
    local rawMapID = self:getPlayerMapID()
    local crateZoneID = self:resolveCrateZoneID(rawMapID)

    return {
        rawMapID      = rawMapID,
        rawZoneName   = self:getMapName(rawMapID),
        crateZoneID   = crateZoneID,
        crateZoneName = crateZoneID and self:getCrateZoneName(crateZoneID) or nil,
    }
end
