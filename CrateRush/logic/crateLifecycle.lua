-- CrateRush
-- logic/crateLifecycle.lua - Crate lifecycle, guardian, and plane confirmation service.

local lifecycle = {}
CrateRush.crateLifecycle = lifecycle

local CRATE_STATE = CrateRush.CRATE_STATE
local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local TIMER_REMOVE_REASON = CrateRush.TIMER_REMOVE_REASON
local crateKeys = CrateRush.crateKeys

local STATE_IDLE     = CRATE_STATE.IDLE
local STATE_DETECTED = CRATE_STATE.DETECTED
local STATE_FLYING   = CRATE_STATE.FLYING
local STATE_DROPPING = CRATE_STATE.DROPPING
local STATE_LANDED   = CRATE_STATE.LANDED
local STATE_CLAIMED_BY_ALLIANCE = CRATE_STATE.CLAIMED_BY_ALLIANCE
local STATE_CLAIMED_BY_HORDE    = CRATE_STATE.CLAIMED_BY_HORDE
local STATE_CLAIMED_BY_MY_FACTION = CRATE_STATE.CLAIMED_BY_MY_FACTION
local STATE_CLAIMED_BY_OPPOSITE_FACTION = CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION

local STATE_ORDER = {
    [STATE_IDLE]                = 0,
    [STATE_DETECTED]            = 1,
    [STATE_FLYING]              = 1,
    [STATE_DROPPING]            = 2,
    [STATE_LANDED]              = 3,
    [STATE_CLAIMED_BY_ALLIANCE] = 4,
    [STATE_CLAIMED_BY_HORDE]    = 4,
    [STATE_CLAIMED_BY_MY_FACTION] = 4,
    [STATE_CLAIMED_BY_OPPOSITE_FACTION] = 4,
}

local PLANE_CONFIRM_SECONDS = CrateRush.TIMING.PLANE_CONFIRM_SECONDS
local PLANE_ANCHOR_CONFIRM_TICKS = CrateRush.TIMING.PLANE_ANCHOR_CONFIRM_TICKS or 3
local PLANE_ANCHOR_CONFIRM_WINDOW_SECONDS = CrateRush.TIMING.PLANE_ANCHOR_CONFIRM_WINDOW_SECONDS or 6
local LANDED_GONE_FLYING_CONFIRM_COUNT = CrateRush.TIMING.LANDED_GONE_FLYING_CONFIRM_COUNT or 2
local LANDED_GONE_EXPIRY_SECONDS = CrateRush.TIMING.LANDED_GONE_EXPIRY_SECONDS or 4

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

local function normalizeState(state)
    if state == STATE_FLYING then return STATE_DETECTED end
    return state
end

local function clearLandedGoneTracker(record)
    if not record then return end
    record.landedSeenAt = nil
    record.landedLastSeenAt = nil
    record.landedGoneSince = nil
    record.landedGoneFlyingCount = nil
    record.landedGoneExpiryToken = nil
    record.landedGUID = nil
end

local function resetLifecycleMilestones(record)
    if not record then return end
    record.droppedAt = nil
    record.landedAt = nil
    record.claimedAt = nil
    record.claimedFaction = nil
    record.claimedFactionName = nil
    record.freshClaim = false
end

local function touchLandedTracker(record, now, landedGUID)
    if not record then return end
    record.landedSeenAt = record.landedSeenAt or now
    record.landedLastSeenAt = now
    record.landedGoneSince = nil
    record.landedGoneFlyingCount = 0
    record.landedGoneExpiryToken = nil
    record.landedGUID = landedGUID or record.landedGUID
end

local function getStoredRecord(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID or not CrateRush.storage or not CrateRush.storage.getCrateHistory then
        return nil
    end

    local record = CrateRush.storage:getCrateHistory(zoneID, shardID)
    if record and crateKeys:sameShard(record.shardID, shardID) then
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
        droppedAt          = record and record.droppedAt or nil,
        landedAt           = record and record.landedAt or nil,
        claimedAt          = record and record.claimedAt or nil,
        claimedFaction     = record and record.claimedFaction or nil,
        claimedFactionName = record and record.claimedFactionName or nil,
        freshClaim         = record and record.freshClaim == true or false,
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
        CrateRush.logDebug("SHARDMAP REMOVED | key=" .. tostring(item.key)
            .. " reason=" .. TIMER_REMOVE_REASON.ZONE_SHARD_REPLACED)
    end
end

local function claimOppositeFromLandedGone(service, zoneID, shardID, record, source, now, flyingCount, elapsedGone)
    zoneLog("LANDED_GONE_CLAIMED_OPPOSITE zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " source=" .. tostring(source)
        .. " flying=" .. tostring(flyingCount or 0) .. "/" .. tostring(LANDED_GONE_FLYING_CONFIRM_COUNT)
        .. " elapsed=" .. tostring(elapsedGone or 0))

    return service:transition(
        zoneID,
        shardID,
        STATE_CLAIMED_BY_OPPOSITE_FACTION,
        record.dropX,
        record.dropY,
        source,
        now
    )
end

local function scheduleLandedGoneExpiry(service, zoneID, shardID, record)
    if not C_Timer or not C_Timer.After or not record or not record.landedGoneSince then return end

    record.landedGoneExpiryToken = (record.landedGoneExpiryToken or 0) + 1
    local token = record.landedGoneExpiryToken
    local goneSince = record.landedGoneSince

    C_Timer.After(LANDED_GONE_EXPIRY_SECONDS, function()
        local current = service:getRecord(zoneID, shardID)
        if not current or current.state ~= STATE_LANDED then return end
        if current.landedGoneExpiryToken ~= token or current.landedGoneSince ~= goneSince then return end

        local now = CrateRush.clock:serverTime()
        local elapsedGone = now - (current.landedGoneSince or now)
        if elapsedGone < LANDED_GONE_EXPIRY_SECONDS then return end

        claimOppositeFromLandedGone(
            service,
            zoneID,
            shardID,
            current,
            CRATE_SOURCE.LANDED_GONE_EXPIRY,
            now,
            current.landedGoneFlyingCount or 0,
            elapsedGone
        )
    end)
end

local function publishTimerSeen(record, source)
    if not record or not record.zoneID or not record.shardID or not record.timerStart then return end

    publishCrateSightingSeen(record, source)
end

local function pruneRecentPlane(now, keepKey)
    now = now or (CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime()) or 0
    local expired = {}

    for key, entry in pairs(recentPlane) do
        if key ~= keepKey and now - (entry and entry.lastSeenAt or 0) > PLANE_CONFIRM_SECONDS then
            expired[#expired + 1] = key
        end
    end

    for _, key in ipairs(expired) do
        recentPlane[key] = nil
    end

end

local function startPlaneCandidate(key, vignetteGUID, now, x, y)
    recentPlane[key] = {
        guid = vignetteGUID,
        firstSeenAt = now,
        lastSeenAt = now,
        lastX = tonumber(x),
        lastY = tonumber(y),
        count = 1,
        samePositionTicks = 1,
    }
end

local function confirmPlane(service, zoneID, shardID, key, reason, detail)
    zoneLog("PLANE_CONFIRMED zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " reason=" .. tostring(reason)
        .. (detail and (" " .. tostring(detail)) or ""))
    recentPlane[key] = nil
    return service:transition(zoneID, shardID, STATE_DETECTED, nil, nil, CRATE_SOURCE.FLYING)
end

local function shouldAcceptLifecycleStart(record, source, now)
    source = source or CRATE_SOURCE.UNKNOWN

    if source == CRATE_SOURCE.CRATE_CYCLE_ANCHOR then
        return true, "crate_cycle_anchor", nil
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
    local key = crateKeys:make(zoneID, shardID)
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
            droppedAt          = nil,
            landedAt           = nil,
            claimedAt          = nil,
            claimedFaction     = nil,
            claimedFactionName = nil,
            freshClaim         = false,
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
        or CrateRush.isCrateVignetteClaimed(vignetteType)
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

function lifecycle:transition(zoneID, shardID, newState, dropX, dropY, source, serverEventTime)
    zoneID = resolveCrateZoneID(zoneID)
    newState = normalizeState(newState)
    if not zoneID or not shardID or not newState then return false end

    local record = getOrCreate(zoneID, shardID)
    if not record then return false end

    source = source or newState
    local now = tonumber(serverEventTime)
    if not now or now <= 0 then
        now = CrateRush.clock:serverTime()
    end
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
            publishTimerSeen(record, source)
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
        resetLifecycleMilestones(record)
        clearLandedGoneTracker(record)

        local _, appliedTimerReason, appliedCycleIndex, appliedCycleAge, appliedRemaining =
            CrateRush.timerPolicy:applyTimerLifecycle(record, zoneID, source, now)
        timerReason = appliedTimerReason
        cycleIndex = appliedCycleIndex
        cycleAge = appliedCycleAge
        remaining = appliedRemaining

        CrateRush.logDebug("SHARDMAP | zone=" .. tostring(zoneID)
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
            publishTimerSeen(record, source)
            zoneLog("LIFECYCLE_DUPLICATE zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(shardID)
                .. " state=" .. tostring(newState)
                .. " current=" .. tostring(record.state)
                .. " source=" .. tostring(source))
            return publishedAny
        end

        local previousState = record.state
        record.state = newState
        record.lastSeenAt = now
        if dropX and dropY then record.dropX = dropX; record.dropY = dropY end
        if newState == STATE_DROPPING then
            record.droppedAt = now
        elseif newState == STATE_LANDED then
            record.landedAt = now
            touchLandedTracker(record, now)
        elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(newState) then
            record.claimedAt = now
            record.freshClaim = newState == STATE_CLAIMED_BY_MY_FACTION and previousState == STATE_LANDED
            if newState == STATE_CLAIMED_BY_MY_FACTION then
                record.claimedFaction = CrateRush.playerContext
                    and CrateRush.playerContext.getFactionKey
                    and CrateRush.playerContext:getFactionKey()
                    or CrateRush.resolveFactionKey(nil)
                record.claimedFactionName = CrateRush.playerContext
                    and CrateRush.playerContext.getFaction
                    and CrateRush.playerContext:getFaction()
                    or CrateRush.resolveFactionName(record.claimedFaction)
            elseif newState == STATE_CLAIMED_BY_OPPOSITE_FACTION then
                record.claimedFaction = "OPPOSITE"
                record.claimedFactionName = "Opposite faction"
            end
            clearLandedGoneTracker(record)
        end

        if not record.timerStart then
            local _, appliedTimerReason, appliedCycleIndex, appliedCycleAge, appliedRemaining =
                CrateRush.timerPolicy:applyTimerLifecycle(record, zoneID, source, now)
            timerReason = appliedTimerReason
            cycleIndex = appliedCycleIndex
            cycleAge = appliedCycleAge
            remaining = appliedRemaining
        end

        CrateRush.logDebug("SHARDMAP | zone=" .. tostring(zoneID)
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

function lifecycle:onPlaneSeen(zoneID, shardID, vignetteGUID, x, y)
    zoneID = resolveCrateZoneID(zoneID)
    x = tonumber(x)
    y = tonumber(y)
    if not zoneID or not shardID or not vignetteGUID or not x or not y then return false end
    local key = crateKeys:make(zoneID, shardID)
    if not key then return false end

    local now = CrateRush.clock:serverTime()
    pruneRecentPlane(now, key)

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
        startPlaneCandidate(key, vignetteGUID, now, x, y)
        local point = CrateRush.routeData and CrateRush.routeData:classifyPlanePoint(zoneID, x, y) or nil
        zoneLog("PLANE_CANDIDATE zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " count=1"
            .. " x=" .. tostring(x)
            .. " y=" .. tostring(y)
            .. " anchor=" .. tostring(point and point.nearAnchor or false)
            .. " drop=" .. tostring(point and point.nearKnownDrop or false)
            .. " routes=" .. tostring(point and point.routeCount or 0))
        return false
    elseif recentPlane[key].guid ~= vignetteGUID then
        startPlaneCandidate(key, vignetteGUID, now, x, y)
        zoneLog("PLANE_RESET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=newGuid count=1")
        return false
    end

    local gap = now - (recentPlane[key].lastSeenAt or now)
    if gap > PLANE_CONFIRM_SECONDS then
        startPlaneCandidate(key, vignetteGUID, now, x, y)
        zoneLog("PLANE_RESET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=gap gap=" .. tostring(gap)
            .. " count=1")
        return false
    end

    local candidate = recentPlane[key]
    local routeData = CrateRush.routeData
    local distance = routeData and routeData:mapDistanceDegrees(candidate.lastX, candidate.lastY, x, y) or nil
    local tolerance = routeData and routeData:getPositionToleranceDegrees() or 0.05
    local moved = distance and distance > tolerance
    local point = routeData and routeData:classifyPlanePoint(zoneID, x, y) or nil

    candidate.lastSeenAt = now
    candidate.count = (candidate.count or 1) + 1

    if moved then
        candidate.lastX = x
        candidate.lastY = y
        candidate.samePositionTicks = 1
        return confirmPlane(self, zoneID, shardID, key, "movement",
            "distance=" .. tostring(distance) .. " tolerance=" .. tostring(tolerance))
    end

    candidate.lastX = x
    candidate.lastY = y
    candidate.samePositionTicks = (candidate.samePositionTicks or 1) + 1

    if point and point.nearAnchor and candidate.samePositionTicks >= PLANE_ANCHOR_CONFIRM_TICKS then
        local anchorWindow = now - (candidate.firstSeenAt or now)
        if anchorWindow <= PLANE_ANCHOR_CONFIRM_WINDOW_SECONDS then
            return confirmPlane(self, zoneID, shardID, key, "anchor_hold",
                "ticks=" .. tostring(candidate.samePositionTicks)
                .. " window=" .. tostring(anchorWindow)
                .. " distance=" .. tostring(point.anchorDistance))
        end

        startPlaneCandidate(key, vignetteGUID, now, x, y)
        zoneLog("PLANE_RESET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=anchor_window window=" .. tostring(anchorWindow)
            .. " count=1")
        return false
    end

    if point and point.nearKnownDrop then
        zoneLog("PLANE_PENDING zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " reason=near_drop"
            .. " ticks=" .. tostring(candidate.samePositionTicks)
            .. " drop=" .. tostring(point.nearestDropID)
            .. " distance=" .. tostring(point.nearestDropDistance)
            .. " gap=" .. tostring(gap))
        return false
    end

    if point and point.knownEnRoute and not point.nearAnchor and candidate.samePositionTicks >= 2 then
        return confirmPlane(self, zoneID, shardID, key, "known_route_hold",
            "ticks=" .. tostring(candidate.samePositionTicks)
            .. " routes=" .. tostring(point.routeCount)
            .. " rough=" .. tostring(point.cells and point.cells.roughKey)
            .. " fine=" .. tostring(point.cells and point.cells.fineKey))
    end

    zoneLog("PLANE_PENDING zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " reason=unknown_hold"
        .. " ticks=" .. tostring(candidate.samePositionTicks)
        .. " routes=" .. tostring(point and point.routeCount or 0)
        .. " anchor=" .. tostring(point and point.nearAnchor or false)
        .. " drop=" .. tostring(point and point.nearKnownDrop or false)
        .. " distance=" .. tostring(distance)
        .. " gap=" .. tostring(gap))

    return false
end

function lifecycle:onVignetteScanComplete(zoneID, shardID, scanContext, trigger)
    if trigger ~= CrateRush.SCAN_TRIGGER.VIGNETTES_UPDATED then return false end
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return false end

    local record = self:getRecord(zoneID, shardID)
    if not record or record.state ~= STATE_LANDED then return false end

    local key = crateKeys:make(zoneID, shardID)
    local observation = scanContext
        and scanContext.observedByKey
        and key
        and scanContext.observedByKey[key]
        or nil

    local now = CrateRush.clock:serverTime()
    if observation and observation.claimedState then
        return self:transition(
            zoneID,
            shardID,
            observation.claimedState,
            record.dropX,
            record.dropY,
            observation.claimedSource,
            now
        )
    end

    if observation and observation.landedSeen then
        touchLandedTracker(record, now, observation.landedGUID)
        return false
    end

    if not record.landedSeenAt and not record.landedLastSeenAt then
        return false
    end

    local landedGoneStarted = not record.landedGoneSince
    record.landedGoneSince = record.landedGoneSince or now
    if landedGoneStarted then
        scheduleLandedGoneExpiry(self, zoneID, shardID, record)
    end
    if observation and observation.planeSeen then
        record.landedGoneFlyingCount = (record.landedGoneFlyingCount or 0) + 1
    end

    local flyingCount = record.landedGoneFlyingCount or 0
    local elapsedGone = now - (record.landedGoneSince or now)
    local source = nil

    if flyingCount >= LANDED_GONE_FLYING_CONFIRM_COUNT then
        source = CRATE_SOURCE.LANDED_GONE_WHILE_FLYING
    elseif elapsedGone >= LANDED_GONE_EXPIRY_SECONDS then
        source = CRATE_SOURCE.LANDED_GONE_EXPIRY
    end

    if not source then
        zoneLog("LANDED_GONE_PENDING zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " flying=" .. tostring(flyingCount) .. "/" .. tostring(LANDED_GONE_FLYING_CONFIRM_COUNT)
            .. " elapsed=" .. tostring(elapsedGone)
            .. " expiry=" .. tostring(LANDED_GONE_EXPIRY_SECONDS))
        return false
    end

    return claimOppositeFromLandedGone(self, zoneID, shardID, record, source, now, flyingCount, elapsedGone)
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
