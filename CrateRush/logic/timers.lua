-- CrateRush
-- logic/timers.lua — Timer state and refresh logic for crate respawn countdowns.

local timers = {}
CrateRush.timers = timers

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local TIMER_REMOVE_REASON = CrateRush.TIMER_REMOVE_REASON
local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local crateKeys = CrateRush.crateKeys

local function getFrequency(zoneID)
    if not zoneID then return CrateRush.DEFAULT_ZONE_FREQUENCY end
    return (CrateRush.ZONE_FREQUENCY and CrateRush.ZONE_FREQUENCY[zoneID]) or CrateRush.DEFAULT_ZONE_FREQUENCY
end

local function getMaxUnseenCycles()
    local fallback = CrateRush.TIMING.TIMER_MAX_UNSEEN_CYCLES
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("timerMaxUnseenCycles", fallback)
    end
    return fallback
end

local function getMaxUnseenSeconds(zoneID)
    return getFrequency(zoneID) * getMaxUnseenCycles()
end

local function getZoneName(zoneID)
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneName then
        return CrateRush.zoneResolver:getCrateZoneName(zoneID)
    end
    return zoneID and tostring(zoneID) or "Unknown"
end

local tickFrame

local function getTimerRecords()
    if CrateRush.domainState and CrateRush.domainState.getTimerRecords then
        return CrateRush.domainState:getTimerRecords()
    end
    return {}
end

local function getTimerByKey(key)
    if CrateRush.domainState and CrateRush.domainState.getTimerByKey then
        return CrateRush.domainState:getTimerByKey(key)
    end
    return nil
end

local function getActiveTimerForZone(zoneID)
    if CrateRush.domainState and CrateRush.domainState.getActiveTimer then
        return CrateRush.domainState:getActiveTimer(zoneID)
    end
    return nil
end

local function hasActiveTimers()
    if CrateRush.domainState and CrateRush.domainState.hasActiveTimers then
        return CrateRush.domainState:hasActiveTimers()
    end
    return next(getTimerRecords()) ~= nil
end

local function shouldPreferTimer(candidate, candidateKey, current)
    if not candidate then return false end
    if not current then return true end

    local activeTimer = getActiveTimerForZone(candidate.zoneID)
    if activeTimer and activeTimer.key == candidateKey then return true end
    if activeTimer and activeTimer.key == current.key then return false end

    local candidateSeen = tonumber(candidate.lastSeenAt or candidate.timerStart or 0) or 0
    local currentSeen = tonumber(current.lastSeenAt or current.timerStart or 0) or 0
    return candidateSeen > currentSeen
end

local function publishDomainEvent(eventName, payload)
    if not CrateRush.domainEvents or not CrateRush.domainEvents.publish then return end
    if not eventName then return end
    CrateRush.domainEvents:publish(eventName, payload or {})
end

local function publishActiveTimersChanged(sorted, now)
    if not DOMAIN_EVENT or not DOMAIN_EVENT.ACTIVE_TIMER_CHANGED then return end
    publishDomainEvent(DOMAIN_EVENT.ACTIVE_TIMER_CHANGED, {
        sorted = sorted or {},
        now    = now,
    })
end

local function publishActiveTimerRemoved(key, timer, reason)
    if not DOMAIN_EVENT or not DOMAIN_EVENT.ACTIVE_TIMER_REMOVED then return end
    publishDomainEvent(DOMAIN_EVENT.ACTIVE_TIMER_REMOVED, {
        key     = key,
        zoneID  = timer and timer.zoneID or nil,
        shardID = timer and timer.shardID or nil,
        reason  = reason or TIMER_REMOVE_REASON.MANUAL,
    })
end

local function resetLifecycleRecord(zoneID, shardID)
    if not zoneID or not shardID then return end
    if CrateRush.crateLifecycle and CrateRush.crateLifecycle.reset then
        CrateRush.crateLifecycle:reset(zoneID, shardID)
    end
end

local function notifyExpiredNoSightings(zoneID, shardID, lastSeenAt, maxUnseenSeconds)
    CrateRush.logDebug("TIMER STALE | zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " lastSeenAt=" .. tostring(lastSeenAt)
        .. " maxUnseenSeconds=" .. tostring(maxUnseenSeconds)
        .. " | notification placeholder")

    if CrateRush.onTimerExpiredDueToNoSightings then
        local ok, err = pcall(CrateRush.onTimerExpiredDueToNoSightings, zoneID, shardID, lastSeenAt, maxUnseenSeconds)
        if not ok then
            CrateRush.logDebug("TIMER STALE NOTIFY ERROR | " .. tostring(err))
        end
    end
end

local function removeTimerKey(key, removeStorage, reason, resetRuntimeRecord)
    local timer = getTimerByKey(key)
    if not timer then return end

    if CrateRush.domainState and CrateRush.domainState.removeTimerByKey then
        CrateRush.domainState:removeTimerByKey(key)
    end

    publishActiveTimerRemoved(key, timer, reason)

    if removeStorage and CrateRush.storage and CrateRush.storage.removeCrate then
        CrateRush.storage:removeCrate(timer.zoneID, timer.shardID)
    end

    if removeStorage or resetRuntimeRecord then
        resetLifecycleRecord(timer.zoneID, timer.shardID)
    end

    CrateRush.logDebug("TIMER REMOVED | key=" .. tostring(key)
        .. " reason=" .. tostring(reason or TIMER_REMOVE_REASON.MANUAL))

    if not hasActiveTimers() and timers.stopTick then
        timers:stopTick()
    end
end

local function removeOtherTimersForZone(zoneID, shardID)
    if not zoneID or not shardID then return end

    local removed = CrateRush.domainState
        and CrateRush.domainState.removeOtherTimersForZone
        and CrateRush.domainState:removeOtherTimersForZone(zoneID, shardID)
        or {}

    for _, item in ipairs(removed) do
        local timer = item.record
        publishActiveTimerRemoved(item.key, timer, TIMER_REMOVE_REASON.ZONE_SHARD_REPLACED)

        resetLifecycleRecord(timer.zoneID, timer.shardID)

        CrateRush.logDebug("TIMER REMOVED | key=" .. tostring(item.key)
            .. " reason=" .. TIMER_REMOVE_REASON.ZONE_SHARD_REPLACED)
    end
end

local function markTimersDirtyExceptZones(includedZones)
    includedZones = includedZones or {}
    local dirtyCount = 0

    for _, timer in pairs(getTimerRecords()) do
        local zoneKey = timer and timer.zoneID and tostring(timer.zoneID) or nil
        if zoneKey and not includedZones[zoneKey] then
            timer.dirty = true
            dirtyCount = dirtyCount + 1
        end
    end

    return dirtyCount
end

local function isTimerStale(timer, now)
    if not timer or not timer.zoneID then return false end
    local lastSeenAt = timer.lastSeenAt or timer.timerStart
    if not lastSeenAt then return false end

    local maxUnseenSeconds = getMaxUnseenSeconds(timer.zoneID)
    return (now - lastSeenAt) > maxUnseenSeconds, lastSeenAt, maxUnseenSeconds
end

local function tick()
    local now = CrateRush.clock:serverTime()

    local expired = {}
    for k, t in pairs(getTimerRecords()) do
        local stale, lastSeenAt, maxUnseenSeconds = isTimerStale(t, now)
        if stale then
            expired[#expired + 1] = {
                key              = k,
                zoneID           = t.zoneID,
                shardID          = t.shardID,
                lastSeenAt       = lastSeenAt,
                maxUnseenSeconds = maxUnseenSeconds,
            }
        end
    end

    for _, item in ipairs(expired) do
        removeTimerKey(item.key, true, TIMER_REMOVE_REASON.STALE_NO_SIGHTINGS)
        notifyExpiredNoSightings(item.zoneID, item.shardID, item.lastSeenAt, item.maxUnseenSeconds)
    end

    -- Build sorted list by remaining time ascending
    local visibleByZone = {}
    for k, t in pairs(getTimerRecords()) do
        if t and t.zoneID and t.timerStart then
            local freq      = getFrequency(t.zoneID)
            local elapsed   = now - t.timerStart
            local remaining = freq - (elapsed % freq)
            local item = {
                key       = k,
                zoneID    = t.zoneID,
                zoneName  = t.zoneName,
                shardID   = t.shardID,
                timerStart = t.timerStart,
                lastSeenAt = t.lastSeenAt,
                remaining = remaining,
                freq      = freq,
                maxUnseenCycles = getMaxUnseenCycles(),
                dirty     = t.dirty == true,
            }
            local zoneKey = tostring(t.zoneID)
            if shouldPreferTimer(t, k, visibleByZone[zoneKey]) then
                visibleByZone[zoneKey] = item
            end
        end
    end

    local sorted = {}
    for _, item in pairs(visibleByZone) do
        sorted[#sorted + 1] = item
    end

    table.sort(sorted, function(a, b) return a.remaining < b.remaining end)

    publishActiveTimersChanged(sorted, now)
end

function timers:startTick()
    if tickFrame then return end
    tickFrame = CreateFrame("Frame")
    tickFrame:SetScript("OnUpdate", function(self, elapsed)
        self.accum = (self.accum or 0) + elapsed
        if self.accum >= 1 then
            self.accum = 0
            tick()
        end
    end)
end

function timers:stopTick()
    if not tickFrame then return end
    tickFrame:SetScript("OnUpdate", nil)
    tickFrame:Hide()
    tickFrame = nil
end

function timers:onStateChange(zoneID, shardID, state, timerStart, lastSeenAt, source, timerQuality, dirty)
    if not zoneID or not shardID or not timerStart then return end
    local k = crateKeys:make(zoneID, shardID)
    local zoneName = getZoneName(zoneID)

    removeOtherTimersForZone(zoneID, shardID)

    if CrateRush.domainState and CrateRush.domainState.setTimer then
        CrateRush.domainState:setTimer(zoneID, shardID, {
            zoneName     = zoneName,
            timerStart   = timerStart,
            lastSeenAt   = lastSeenAt or timerStart,
            source       = source,
            timerSource  = source,
            timerQuality = timerQuality,
            dirty        = dirty == true,
        })
    end

    local activeTimer = getTimerByKey(k)
    if activeTimer then
        activeTimer.zoneName = zoneName
        activeTimer.source = source
    end

    timers:startTick()
    tick()
end

function timers:onTimerSeen(zoneID, shardID, lastSeenAt)
    if not zoneID or not shardID or not lastSeenAt then return end

    if CrateRush.domainState and CrateRush.domainState.getTimer and CrateRush.domainState:getTimer(zoneID, shardID) then
        removeOtherTimersForZone(zoneID, shardID)
        CrateRush.domainState:touchTimer(zoneID, shardID, lastSeenAt)
        tick()
        return
    end

    local record = CrateRush.storage and CrateRush.storage.getCrateHistory and CrateRush.storage:getCrateHistory(zoneID, shardID)
    if record and record.timestamp and crateKeys:sameShard(record.shardID, shardID) then
        timers:onStateChange(zoneID, shardID, nil, record.timestamp, lastSeenAt or record.lastSeenAt, record.source, record.timerQuality)
    end
end

function timers:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    timers:onStateChange(
        payload.zoneID,
        payload.shardID,
        payload.state,
        payload.timerStart,
        payload.lastSeenAt,
        payload.timerSource or payload.source,
        payload.timerQuality
    )
end

function timers:onCrateSightingSeen(payload)
    if type(payload) ~= "table" then return end
    timers:onTimerSeen(payload.zoneID, payload.shardID, payload.lastSeenAt)
end

function timers:onTimerRemovalRequested(payload)
    if type(payload) ~= "table" then return end

    if payload.key then
        removeTimerKey(payload.key, true, payload.reason or TIMER_REMOVE_REASON.MANUAL)
        return
    end

    if payload.zoneID then
        timers:removeZone(payload.zoneID, payload.reason or TIMER_REMOVE_REASON.MANUAL)
    end
end

function timers:removeByKey(key)
    if not key then return end
    removeTimerKey(key, true, TIMER_REMOVE_REASON.MANUAL)
end

function timers:remove(zoneID, shardID)
    if not zoneID or not shardID then return end
    local k = crateKeys:make(zoneID, shardID)
    timers:removeByKey(k)
end

function timers:removeZone(zoneID, reason)
    if not zoneID then return false end

    local activeTimer = getActiveTimerForZone(zoneID)
    if activeTimer and activeTimer.key then
        removeTimerKey(activeTimer.key, true, reason or TIMER_REMOVE_REASON.MANUAL)
        return true
    end

    if CrateRush.storage and CrateRush.storage.removeCrate then
        return CrateRush.storage:removeCrate(zoneID)
    end

    return false
end

function timers:applyRemoteSnapshot(entries, senderGUID)
    if type(entries) ~= "table" then return false end

    local includedZones = {}
    local applied = 0

    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local zoneID = tonumber(entry.zoneID or entry.zoneId)
            local shardID = entry.shardID or entry.shardId
            local timerStart = tonumber(entry.timerStart or entry.nextTimerStart)
            local lastSeenAt = tonumber(entry.lastSeenAt) or timerStart

            if zoneID and shardID and timerStart then
                includedZones[tostring(zoneID)] = true
                timers:onStateChange(
                    zoneID,
                    shardID,
                    nil,
                    timerStart,
                    lastSeenAt,
                    CRATE_SOURCE.REMOTE_TIMER_SYNC,
                    "remote",
                    entry.dirty == true or entry.dirty == "true"
                )
                applied = applied + 1
            end
        end
    end

    local dirtyCount = markTimersDirtyExceptZones(includedZones)
    tick()

    CrateRush.logDebug("TIMER SYNC APPLIED | timers=" .. tostring(applied)
        .. " dirty=" .. tostring(dirtyCount)
        .. " senderGUID=" .. tostring(senderGUID))

    return true
end

function timers:onTimerSyncReceived(payload)
    if type(payload) ~= "table" then return end
    timers:applyRemoteSnapshot(payload.timers, payload.senderGUID)
end

function timers:getActiveTimersSnapshot()
    if CrateRush.domainState and CrateRush.domainState.getTimerRecordsSnapshot then
        return CrateRush.domainState:getTimerRecordsSnapshot()
    end
    return {}
end

function timers:getActiveTimerForZone(zoneID)
    if not zoneID then return nil end
    if CrateRush.domainState and CrateRush.domainState.getActiveTimer then
        return CrateRush.domainState:getActiveTimer(zoneID)
    end
    return nil
end

function timers:restore()
    local history = CrateRush.storage and CrateRush.storage:getAll()
    if not history then return end

    local now = CrateRush.clock:serverTime()
    for historyKey, record in pairs(history) do
        local zoneID = record and record.zoneID or tostring(historyKey):match("^([^:]+)")
        zoneID = tonumber(zoneID) or zoneID
        if record and zoneID and record.shardID and record.timestamp then
            local elapsed = now - record.timestamp
            local lastSeenAt = record.lastSeenAt or record.timestamp
            local zoneName = getZoneName(tonumber(zoneID) or zoneID)

            local maxUnseenSeconds = getMaxUnseenSeconds(tonumber(zoneID) or zoneID)
            if (now - lastSeenAt) > maxUnseenSeconds then
                if CrateRush.storage and CrateRush.storage.removeCrate then
                    CrateRush.storage:removeCrate(tonumber(zoneID) or zoneID, record.shardID)
                end
                notifyExpiredNoSightings(tonumber(zoneID) or zoneID, record.shardID, lastSeenAt, maxUnseenSeconds)
            else
                timers:onStateChange(
                    tonumber(zoneID) or zoneID,
                    record.shardID,
                    nil,
                    record.timestamp,
                    lastSeenAt,
                    record.source,
                    record.timerQuality
                )
                CrateRush.logDebug("TIMER RESTORED | zone=" .. zoneName .. " shard=" .. tostring(record.shardID) .. " elapsed=" .. tostring(elapsed) .. "s")
            end
        end
    end

    if hasActiveTimers() then
        timers:startTick()
    end
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.CRATE_STATE_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, timers, "onCrateStateChanged")
    end
    if DOMAIN_EVENT.CRATE_SIGHTING_SEEN then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_SIGHTING_SEEN, timers, "onCrateSightingSeen")
    end
    if DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED, timers, "onTimerRemovalRequested")
    end
    if DOMAIN_EVENT.TIMER_SYNC_RECEIVED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.TIMER_SYNC_RECEIVED, timers, "onTimerSyncReceived")
    end
end
