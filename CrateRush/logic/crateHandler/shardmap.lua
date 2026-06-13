-- CrateRush
-- logic/crateHandler/shardmap.lua - Compatibility facade for shard and lifecycle services.

local shardmap = {}
CrateRush.shardmap = shardmap

function shardmap:onZoneChanged(zoneID)
    if CrateRush.shardService and CrateRush.shardService.onZoneChanged then
        return CrateRush.shardService:onZoneChanged(zoneID)
    end
end

function shardmap:confirmShard(zoneID, shardID, source, sampleKey, requiredCount)
    if CrateRush.shardService and CrateRush.shardService.confirmShard then
        return CrateRush.shardService:confirmShard(zoneID, shardID, source, sampleKey, requiredCount)
    end
end

function shardmap:isZoneConfirmed(zoneID)
    if CrateRush.shardService and CrateRush.shardService.isZoneConfirmed then
        return CrateRush.shardService:isZoneConfirmed(zoneID)
    end
    return false
end

function shardmap:getConfirmedShard(zoneID)
    if CrateRush.shardService and CrateRush.shardService.getConfirmedShard then
        return CrateRush.shardService:getConfirmedShard(zoneID)
    end
    return nil
end

function shardmap:acceptConfirmedShard(zoneID, shardID, source)
    if CrateRush.shardService and CrateRush.shardService.acceptConfirmedShard then
        return CrateRush.shardService:acceptConfirmedShard(zoneID, shardID, source)
    end
    return false
end

function shardmap:extractShardFromGUID(guid)
    if CrateRush.vignetteScanner and CrateRush.vignetteScanner.extractShardFromGUID then
        return CrateRush.vignetteScanner:extractShardFromGUID(guid)
    end
    if not guid or type(guid) ~= "string" then return nil end
    return guid:match("^Vignette%-%d+%-%d+%-%d+%-(%d+)%-")
end

function shardmap:canTransition(zoneID, shardID, newState)
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.canTransition then
        return CrateRush.crateLifecycle:canTransition(zoneID, shardID, newState)
    end
    return false
end

function shardmap:transition(zoneID, shardID, newState, dropX, dropY, source)
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.transition then
        return CrateRush.crateLifecycle:transition(zoneID, shardID, newState, dropX, dropY, source)
    end
    return false
end

function shardmap:onPlaneSeen(zoneID, shardID, vignetteGUID, x, y)
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.onPlaneSeen then
        return CrateRush.crateLifecycle:onPlaneSeen(zoneID, shardID, vignetteGUID, x, y)
    end
    return false
end

function shardmap:getRecord(zoneID, shardID)
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.getRecord then
        return CrateRush.crateLifecycle:getRecord(zoneID, shardID)
    end
    return nil
end

function shardmap:reset(zoneID, shardID)
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.reset then
        return CrateRush.crateLifecycle:reset(zoneID, shardID)
    end
end

function shardmap:getAll()
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.getAll then
        return CrateRush.crateLifecycle:getAll()
    end
    return {}
end
