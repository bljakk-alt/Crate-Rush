-- CrateRush
-- logic/cockpitDisplay.lua - Prepared cockpit display filters. UI consumes this; it does not inspect shard truth.

local cockpitDisplay = {}
CrateRush.cockpitDisplay = cockpitDisplay

local function sameShard(left, right)
    if left == nil or right == nil then return false end
    if CrateRush.crateKeys and CrateRush.crateKeys.sameShard then
        return CrateRush.crateKeys:sameShard(left, right)
    end
    return tostring(left) == tostring(right)
end

local function makeKey(zoneID, shardID)
    if CrateRush.crateKeys and CrateRush.crateKeys.make then
        return CrateRush.crateKeys:make(zoneID, shardID)
    end
    if zoneID and shardID then
        return tostring(zoneID) .. ":" .. tostring(shardID)
    end
    return nil
end

local function getConfirmedShard(zoneID)
    if CrateRush.shardService and CrateRush.shardService.getConfirmedShard then
        return CrateRush.shardService:getConfirmedShard(zoneID)
    end
    return nil
end

function cockpitDisplay:payloadMatchesConfirmedSelection(payload, selectedZoneID, selectedShardID, selectedKey)
    if type(payload) ~= "table" then return false, "missing_payload" end
    if not selectedZoneID or not selectedShardID or not selectedKey then return false, "no_confirmed_selection" end
    if not sameShard(selectedShardID, payload.shardID) then return false, "selected_shard_mismatch" end
    if makeKey(payload.zoneID, payload.shardID) ~= selectedKey then return false, "selected_key_mismatch" end

    local confirmedShardID = getConfirmedShard(payload.zoneID)
    if not sameShard(confirmedShardID, payload.shardID) then return false, "shard_not_confirmed" end
    return true
end

function cockpitDisplay:isClaimedState(state)
    if CrateRush.isCrateStateClaimed then
        return CrateRush.isCrateStateClaimed(state)
    end
    return false
end
