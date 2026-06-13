-- CrateRush
-- logic/transitionGuard.lua - Prevent stale crate evidence from crossing zone transitions.

local transitionGuard = {}
CrateRush.transitionGuard = transitionGuard

local vignetteZoneOwners = {}
local vignetteContextZoneOwners = {}
local vignetteZoneOwnerCount = 0
local vignetteContextZoneOwnerCount = 0

local CACHE_MAX_AGE_SECONDS = CrateRush.TIMING.TRANSITION_GUARD_CACHE_MAX_AGE_SECONDS
local CACHE_MAX_ENTRIES = CrateRush.TIMING.TRANSITION_GUARD_CACHE_MAX_ENTRIES

local function nowSeconds()
    return CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or 0
end

local function pruneOwnerMap(ownerMap, count)
    local now = nowSeconds()
    local expired = {}

    for key, entry in pairs(ownerMap) do
        local seenAt = entry and entry.seenAt or 0
        if now - seenAt > CACHE_MAX_AGE_SECONDS then
            expired[#expired + 1] = key
        end
    end

    for _, key in ipairs(expired) do
        if ownerMap[key] then
            ownerMap[key] = nil
            count = math.max(0, count - 1)
        end
    end

    while count > CACHE_MAX_ENTRIES do
        local oldestKey = nil
        local oldestSeenAt = nil
        for key, entry in pairs(ownerMap) do
            local seenAt = entry and entry.seenAt or 0
            if not oldestSeenAt or seenAt < oldestSeenAt then
                oldestKey = key
                oldestSeenAt = seenAt
            end
        end

        if not oldestKey then return count end
        ownerMap[oldestKey] = nil
        count = math.max(0, count - 1)
    end

    return count
end

local function pruneOwners()
    vignetteZoneOwnerCount = pruneOwnerMap(vignetteZoneOwners, vignetteZoneOwnerCount)
    vignetteContextZoneOwnerCount = pruneOwnerMap(vignetteContextZoneOwners, vignetteContextZoneOwnerCount)
end

local function log(zoneLog, msg)
    if zoneLog then
        zoneLog(msg)
    elseif CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ZONECHECK | " .. tostring(msg))
    end
end

function transitionGuard:claimSighting(sighting, zoneID, trigger, zoneLog)
    if not sighting or not sighting.isKnownCrateVignette or not zoneID then return true end
    pruneOwners()

    local contextKey = sighting.contextKey
    local contextOwner = contextKey and vignetteContextZoneOwners[contextKey] or nil
    local contextOwnedZoneID = contextOwner and contextOwner.zoneID or nil
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

    local owner = vignetteZoneOwners[sighting.guid]
    local ownedZoneID = owner and owner.zoneID or nil
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
        if not vignetteContextZoneOwners[contextKey] then
            vignetteContextZoneOwnerCount = vignetteContextZoneOwnerCount + 1
        end
        vignetteContextZoneOwners[contextKey] = {
            zoneID = zoneID,
            seenAt = nowSeconds(),
        }
    end
    if not vignetteZoneOwners[sighting.guid] then
        vignetteZoneOwnerCount = vignetteZoneOwnerCount + 1
    end
    vignetteZoneOwners[sighting.guid] = {
        zoneID = zoneID,
        seenAt = nowSeconds(),
    }
    return true
end
