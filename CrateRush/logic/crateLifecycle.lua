-- CrateRush
-- logic/crateLifecycle.lua - Crate lifecycle, guardian, and plane confirmation service.

local lifecycle = {}
CrateRush.crateLifecycle = lifecycle

local CRATE_STATE = CrateRush.CRATE_STATE
local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local TIMER_REMOVE_REASON = CrateRush.TIMER_REMOVE_REASON

local STATE_IDLE     = CRATE_STATE.IDLE
local STATE_DETECTED = CRATE_STATE.DETECTED or CRATE_STATE.FLYING
local STATE_FLYING   = CRATE_STATE.FLYING
local STATE_DROPPING = CRATE_STATE.DROPPING
local STATE_LANDED   = CRATE_STATE.LANDED
local STATE_CLAIMED_BY_ALLIANCE = CRATE_STATE.CLAIMED_BY_ALLIANCE
local STATE_CLAIMED_BY_HORDE    = CRATE_STATE.CLAIMED_BY_HORDE

local STATE_ORDER = {
    [STATE_IDLE]                = 0,
    [STATE_DETECTED]            = 1,
    [STATE_FLYING]              = 1,
    [STATE_DROPPING]            = 2,
    [STATE_LANDED]              = 3,
    [STATE_CLAIMED_BY_ALLIANCE] = 4,
    [STATE_CLAIMED_BY_HORDE]    = 4,
}

local PLANE_CONFIRM_SECONDS = CrateRush.TIMING.PLANE_CONFIRM_SECONDS
local PLANE_CONFIRM_REQUIRED_SIGHTINGS = CrateRush.TIMING.PLANE_CONFIRM_REQUIRED_SIGHTINGS

local recentPlane = {}

local function zoneLog(msg)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ZONECHECK | " .. tostring(msg))
    end
end

local function resolveCrateZoneID(zoneID)
    if CrateRush.zoneResolver and CrateRush.zoneResolver.resolveCrateZoneID then
        return CrateRush.zoneResolver:resolveCrateZoneID(zoneID)
    end
    if CrateRush.resolveCrateZoneID then
        return CrateRush.resolveCrateZoneID(zoneID)
    end
    return tonumber(zoneID) or zoneID
end

local function makeKey(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

local function normalizeState(state)
    if state == STATE_FLYING then return STATE_DETECTED end
    return state
end

local function getStoredRecord(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID or not CrateRush.storage or not CrateRush.storage.getCrateHistory then
        return nil
    end

    local record = CrateRush.storage:getCrateHistory(zoneID, shardID)
    if record and tostring(record.shardID) == tostring(shardID) then
        return record
    end
    return nil
end

local function publishCrateStateChanged(zoneID, shardID, state, record, source, timerReason, cycleAge, remaining)
    if not DOMAIN_EVENT or not DOMAIN_EVENT.CRATE_STATE_CHANGED then return end
    if not CrateRush.domainEvents or not CrateRush.domainEvents.publish then return end

    CrateRush.domainEvents:publish(DOMAIN_EVENT.CRATE_STATE_CHANGED, {
        zoneID             = zoneID,
        shardID            = shardID,
        state              = state,
        source             = source,
        timerReason        = timerReason,
        timerStart         = record and record.timerStart or nil,
        timerSource        = record and record.timerSource or source,
        timerQuality       = record and record.timerQuality or nil,
        lastSeenAt         = record and record.lastSeenAt or nil,
        lastDetectedAt     = record and record.lastDetectedAt or nil,
        lifecycleStartedAt = record and (record.lifecycleStartedAt or record.lastDetectedAt) or nil,
        observedCycleIndex = record and record.observedCycleIndex or nil,
        detectedAt         = record and record.detectedAt or nil,
        dropX              = record and record.dropX or nil,
        dropY              = record and record.dropY or nil,
        cycleAge           = cycleAge,
        remaining          = remaining,
    })
end

local function publishCrateSightingSeen(record, source)
    if not DOMAIN_EVENT or not DOMAIN_EVENT.CRATE_SIGHTING_SEEN then return end
    if not CrateRush.domainEvents or not CrateRush.domainEvents.publish then return end
    if not record or not record.zoneID or not record.shardID then return end

    CrateRush.domainEvents:publish(DOMAIN_EVENT.CRATE_SIGHTING_SEEN, {
        zoneID             = record.zoneID,
        shardID            = record.shardID,
        source             = source,
        timerStart         = record.timerStart,
        timerSource        = record.timerSource or source,
        timerQuality       = record.timerQuality,
        lastSeenAt         = record.lastSeenAt,
        lastDetectedAt     = record.lastDetectedAt,
        lifecycleStartedAt = record.lifecycleStartedAt or record.lastDetectedAt,
    })
end

local function removeOtherRecordsForZone(zoneID, shardID)
    if not zoneID or not shardID then return end

    local removed = CrateRush.domainState
        and CrateRush.domainState.removeOtherLifecyclesForZone
        and CrateRush.domainState:removeOtherLifecyclesForZone(zoneID, shardID)
        or {}

    for _, item in ipairs(removed) do
        CrateRush.debug:log("SHARDMAP REMOVED | key=" .. tostring(item.key)
            .. " reason=" .. TIMER_REMOVE_REASON.ZONE_SHARD_REPLACED)
    end
end

local function persistTimerSeen(record, source)
    if not record or not record.zoneID or not record.shardID or not record.timerStart then return end

    if CrateRush.storage and CrateRush.storage.recordCrate then
        CrateRush.storage:recordCrate(
            record.zoneID,
            record.shardID,
            record.timerStart,
            record.lastSeenAt,
            record.timerSource or source,
            record.lastDetectedAt,
            record.timerQuality
        )
    end

    publishCrateSightingSeen(record, source)
end

local function shouldAcceptLifecycleStart(record, source, now)
    source = source or CRATE_SOURCE.UNKNOWN

    if source == CRATE_SOURCE.MONSTER_SAY then
        return true, "monster_say", nil
    end

    local lifecycleStartedAt = record and (record.lifecycleStartedAt or record.lastDetectedAt) or nil
    if not lifecycleStartedAt then
        return true, "first_detection", nil
    end

    local guardian = CrateRush.timerPolicy:getLifecycleDetectionGuardianSeconds()
    local elapsed = now - lifecycleStartedAt
    if elapsed >= guardian then
        return true, "guardian_elapsed", elapsed
    end

    return false, "guardian_active", elapsed
end

local function getOrCreate(zoneID, shardID)
    local key = makeKey(zoneID, shardID)
    if not key then return nil end
    if not CrateRush.domainState or not CrateRush.domainState.getOrCreateLifecycle then
        return nil
    end

    local record = CrateRush.domainState:getLifecycle(zoneID, shardID)
    if not record then
        local stored = getStoredRecord(zoneID, shardID)
        record = CrateRush.domainState:getOrCreateLifecycle(zoneID, shardID, {
            zoneID             = zoneID,
            shardID            = shardID,
            state              = STATE_IDLE,
            timerStart         = stored and stored.timestamp or nil,
            timerSource        = stored and stored.source or nil,
            timerQuality       = stored and stored.timerQuality or (stored and stored.timestamp and CrateRush.timerPolicy:getTimerQualityForSource(stored.source)) or nil,
            lastSeenAt         = stored and (stored.lastSeenAt or stored.timestamp) or nil,
            lastDetectedAt     = stored and (stored.lastDetectedAt or stored.lastSeenAt or stored.timestamp) or nil,
            lifecycleStartedAt = stored and (stored.lastDetectedAt or stored.lastSeenAt or stored.timestamp) or nil,
            observedCycleIndex = nil,
            detectedAt         = nil,
            dropX              = nil,
            dropY              = nil,
            announced          = {},
        })
    end
    return record
end

function lifecycle:isCrateObjectState(vignetteType)
    return vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_DROPPING
        or vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_LANDED
        or vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_BY_ALLIANCE
        or vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_BY_HORDE
end

function lifecycle:shouldProcessObjectState(vignetteType, firstSeenGUID, zoneID, shardID)
    if not self:isCrateObjectState(vignetteType) then return false end
    if firstSeenGUID then return true end

    return self:getRecord(zoneID, shardID) == nil
        or not (CrateRush.domainState and CrateRush.domainState.getTimer and CrateRush.domainState:getTimer(zoneID, shardID))
end

function lifecycle:canTransition(zoneID, shardID, newState)
    zoneID = resolveCrateZoneID(zoneID)
    newState = normalizeState(newState)
    if not zoneID or not shardID or not newState then return false end
    local record = getOrCreate(zoneID, shardID)
    if not record then return false end

    local currentOrder = STATE_ORDER[record.state] or 0
    local newOrder = STATE_ORDER[newState] or 0
    return newOrder > currentOrder
end

function lifecycle:transition(zoneID, shardID, newState, dropX, dropY, source)
    zoneID = resolveCrateZoneID(zoneID)
    newState = normalizeState(newState)
    if not zoneID or not shardID or not newState then return false end

    local record = getOrCreate(zoneID, shardID)
    if not record then return false end

    source = source or newState
    local now = GetServerTime()
    local currentOrder = STATE_ORDER[record.state] or 0
    local newOrder = STATE_ORDER[newState] or 0
    local hasRuntimeLifecycle = currentOrder > 0
    local hasStoredLifecycle = record.lifecycleStartedAt ~= nil or record.lastDetectedAt ~= nil
    local lifecycleStartAllowed = select(1, shouldAcceptLifecycleStart(record, source, now))
    local needsLifecycleStart = newState == STATE_DETECTED
        or not hasRuntimeLifecycle and not hasStoredLifecycle
        or (hasRuntimeLifecycle and lifecycleStartAllowed)
        or (hasRuntimeLifecycle and newOrder <= currentOrder)
        or (not hasRuntimeLifecycle and hasStoredLifecycle and lifecycleStartAllowed)

    local timerReason, cycleIndex, cycleAge, remaining = "unchanged", nil, nil, nil
    local publishedAny = false

    if needsLifecycleStart then
        local detectionAccepted, detectionReason, detectionElapsed = shouldAcceptLifecycleStart(record, source, now)
        if not detectionAccepted then
            record.lastSeenAt = now
            zoneLog("LIFECYCLE_GUARD zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(shardID)
                .. " state=" .. tostring(newState)
                .. " source=" .. tostring(source)
                .. " reason=" .. tostring(detectionReason)
                .. " elapsed=" .. tostring(detectionElapsed)
                .. " guardian=" .. tostring(CrateRush.timerPolicy:getLifecycleDetectionGuardianSeconds()))
            persistTimerSeen(record, source)
            return false
        end

        removeOtherRecordsForZone(zoneID, shardID)
        if CrateRush.domainState and CrateRush.domainState.setCurrentLifecycle then
            CrateRush.domainState:setCurrentLifecycle(zoneID, shardID)
        end

        record.state = STATE_DETECTED
        record.lifecycleStartedAt = now
        record.lastDetectedAt = now
        record.detectedAt = now
        record.announced = {}
        record.lastSeenAt = now

        local _, appliedTimerReason, appliedCycleIndex, appliedCycleAge, appliedRemaining =
            CrateRush.timerPolicy:applyTimerLifecycle(record, zoneID, source, now)
        timerReason = appliedTimerReason
        cycleIndex = appliedCycleIndex
        cycleAge = appliedCycleAge
        remaining = appliedRemaining

        if CrateRush.storage and CrateRush.storage.recordCrate then
            CrateRush.storage:recordCrate(zoneID, shardID, record.timerStart, record.lastSeenAt, record.timerSource or source, record.lastDetectedAt, record.timerQuality)
        end

        CrateRush.debug:log("SHARDMAP | zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " state=" .. STATE_DETECTED
            .. " source=" .. tostring(source)
            .. " timerReason=" .. tostring(timerReason)
            .. " detectionReason=lifecycle_start"
            .. " cycleAge=" .. tostring(cycleAge)
            .. " remaining=" .. tostring(remaining))

        publishCrateStateChanged(zoneID, shardID, STATE_DETECTED, record, source, timerReason, cycleAge, remaining)
        publishedAny = true
    else
        removeOtherRecordsForZone(zoneID, shardID)
        if CrateRush.domainState and CrateRush.domainState.setCurrentLifecycle then
            CrateRush.domainState:setCurrentLifecycle(zoneID, shardID)
        end
        local frequency = CrateRush.timerPolicy:getFrequency(zoneID)
        cycleIndex, cycleAge, remaining = CrateRush.timerPolicy:getCyclePosition(record.timerStart, now, frequency)
    end

    if newState ~= STATE_DETECTED then
        currentOrder = STATE_ORDER[record.state] or 0
        if newOrder <= currentOrder then
            record.lastSeenAt = now
            persistTimerSeen(record, source)
            zoneLog("LIFECYCLE_DUPLICATE zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(shardID)
                .. " state=" .. tostring(newState)
                .. " current=" .. tostring(record.state)
                .. " source=" .. tostring(source))
            return publishedAny
        end

        record.state = newState
        record.lastSeenAt = now
        if dropX and dropY then record.dropX = dropX; record.dropY = dropY end

        if not record.timerStart then
            local _, appliedTimerReason, appliedCycleIndex, appliedCycleAge, appliedRemaining =
                CrateRush.timerPolicy:applyTimerLifecycle(record, zoneID, source, now)
            timerReason = appliedTimerReason
            cycleIndex = appliedCycleIndex
            cycleAge = appliedCycleAge
            remaining = appliedRemaining
        end

        if CrateRush.storage and CrateRush.storage.recordCrate then
            CrateRush.storage:recordCrate(zoneID, shardID, record.timerStart, record.lastSeenAt, record.timerSource or source, record.lastDetectedAt, record.timerQuality)
        end

        CrateRush.debug:log("SHARDMAP | zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " state=" .. newState
            .. " source=" .. tostring(source)
            .. " timerReason=" .. tostring(timerReason)
            .. " detectionReason=state_progress"
            .. " cycleAge=" .. tostring(cycleAge)
            .. " remaining=" .. tostring(remaining))

        publishCrateStateChanged(zoneID, shardID, newState, record, source, timerReason, cycleAge, remaining)
        publishedAny = true
    end

    return publishedAny
end

function lifecycle:onPlaneSeen(zoneID, shardID, vignetteGUID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID or not vignetteGUID then return false end
    local key = makeKey(zoneID, shardID)
    if not key then return false end

    local now = GetServerTime()
    local guardRecord = CrateRush.domainState
        and CrateRush.domainState.getLifecycle
        and CrateRush.domainState:getLifecycle(zoneID, shardID)
        or getStoredRecord(zoneID, shardID)
    local detectionAccepted = shouldAcceptLifecycleStart(guardRecord, CRATE_SOURCE.FLYING, now)
    if not detectionAccepted then
        recentPlane[key] = nil
        return false
    end

    if not recentPlane[key] then
        recentPlane[key] = { guid = vignetteGUID, firstSeenAt = now, lastSeenAt = now, count = 1 }
        zoneLog("PLANE_SEEN zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " count=1/" .. tostring(PLANE_CONFIRM_REQUIRED_SIGHTINGS))
        return false
    elseif recentPlane[key].guid ~= vignetteGUID then
        recentPlane[key] = { guid = vignetteGUID, firstSeenAt = now, lastSeenAt = now, count = 1 }
        zoneLog("PLANE_RESET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=newGuid count=1/" .. tostring(PLANE_CONFIRM_REQUIRED_SIGHTINGS))
        return false
    end

    local gap = now - (recentPlane[key].lastSeenAt or now)
    if gap > PLANE_CONFIRM_SECONDS then
        recentPlane[key] = { guid = vignetteGUID, firstSeenAt = now, lastSeenAt = now, count = 1 }
        zoneLog("PLANE_RESET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=gap gap=" .. tostring(gap)
            .. " count=1/" .. tostring(PLANE_CONFIRM_REQUIRED_SIGHTINGS))
        return false
    end

    recentPlane[key].lastSeenAt = now
    recentPlane[key].count = (recentPlane[key].count or 1) + 1
    zoneLog("PLANE_SEEN zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " count=" .. tostring(recentPlane[key].count) .. "/" .. tostring(PLANE_CONFIRM_REQUIRED_SIGHTINGS)
        .. " gap=" .. tostring(gap))

    if recentPlane[key].count >= PLANE_CONFIRM_REQUIRED_SIGHTINGS then
        local confirmed = self:transition(zoneID, shardID, STATE_DETECTED, nil, nil, CRATE_SOURCE.FLYING)
        recentPlane[key] = nil
        return confirmed
    end

    return false
end

function lifecycle:getRecord(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if not CrateRush.domainState or not CrateRush.domainState.getLifecycle then return nil end
    return CrateRush.domainState:getLifecycle(zoneID, shardID)
end

function lifecycle:reset(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if CrateRush.domainState and CrateRush.domainState.removeLifecycle then
        CrateRush.domainState:removeLifecycle(zoneID, shardID)
    end
end

function lifecycle:getAll()
    if not CrateRush.domainState or not CrateRush.domainState.getLifecycleRecords then return {} end
    return CrateRush.domainState:getLifecycleRecords()
end
