-- CrateRush
-- logic/transitionGuard.lua - Prevent stale crate evidence from crossing zone transitions.

local transitionGuard = {}
CrateRush.transitionGuard = transitionGuard

local vignetteZoneOwners = {}
local vignetteContextZoneOwners = {}

local function log(zoneLog, msg)
    if zoneLog then
        zoneLog(msg)
    elseif CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ZONECHECK | " .. tostring(msg))
    end
end

function transitionGuard:claimSighting(sighting, zoneID, trigger, zoneLog)
    if not sighting or not sighting.isKnownCrateVignette or not zoneID then return true end

    local contextKey = sighting.contextKey
    local contextOwnedZoneID = contextKey and vignetteContextZoneOwners[contextKey] or nil
    if contextOwnedZoneID and tostring(contextOwnedZoneID) ~= tostring(zoneID) then
        log(zoneLog, "STALE_ZONE_CONTEXT ownerZone=" .. tostring(contextOwnedZoneID)
            .. " currentZone=" .. tostring(zoneID)
            .. " trigger=" .. tostring(trigger)
            .. " vignetteID=" .. tostring(sighting.vignetteID)
            .. " shard=" .. tostring(sighting.shardID)
            .. " context=" .. tostring(contextKey)
            .. " guid=" .. tostring(sighting.guid))
        return false
    end

    local ownedZoneID = vignetteZoneOwners[sighting.guid]
    if ownedZoneID and tostring(ownedZoneID) ~= tostring(zoneID) then
        log(zoneLog, "STALE_ZONE_GUID ownerZone=" .. tostring(ownedZoneID)
            .. " currentZone=" .. tostring(zoneID)
            .. " trigger=" .. tostring(trigger)
            .. " vignetteID=" .. tostring(sighting.vignetteID)
            .. " shard=" .. tostring(sighting.shardID)
            .. " guid=" .. tostring(sighting.guid))
        return false
    end

    if contextKey then
        vignetteContextZoneOwners[contextKey] = zoneID
    end
    vignetteZoneOwners[sighting.guid] = zoneID
    return true
end
