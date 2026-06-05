-- CrateRush
-- logic/timers.lua — Timer state and refresh logic for crate respawn countdowns.

local timers = {}
CrateRush.timers = timers

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local TIMER_REMOVE_REASON = CrateRush.TIMER_REMOVE_REASON

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

local function sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function notifyExpiredNoSightings(zoneID, shardID, lastSeenAt, maxUnseenSeconds)
    CrateRush.debug:log("TIMER STALE | zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " lastSeenAt=" .. tostring(lastSeenAt)
        .. " maxUnseenSeconds=" .. tostring(maxUnseenSeconds)
        .. " | notification placeholder")

    if CrateRush.onTimerExpiredDueToNoSightings then
        local ok, err = pcall(CrateRush.onTimerExpiredDueToNoSightings, zoneID, shardID, lastSeenAt, maxUnseenSeconds)
        if not ok then
            CrateRush.debug:log("TIMER STALE NOTIFY ERROR | " .. tostring(err))
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

    CrateRush.debug:log("TIMER REMOVED | key=" .. tostring(key)
        .. " reason=" .. tostring(reason or TIMER_REMOVE_REASON.MANUAL))
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

        CrateRush.debug:log("TIMER REMOVED | key=" .. tostring(item.key)
            .. " reason=" .. TIMER_REMOVE_REASON.ZONE_SHARD_REPLACED)
    end
end

local function isTimerStale(timer, now)
    if not timer or not timer.zoneID then return false end
    local lastSeenAt = timer.lastSeenAt or timer.timerStart
    if not lastSeenAt then return false end

    local maxUnseenSeconds = getMaxUnseenSeconds(timer.zoneID)
    return (now - lastSeenAt) > maxUnseenSeconds, lastSeenAt, maxUnseenSeconds
end

local function tick()
    local now = GetServerTime()

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

function timers:onStateChange(zoneID, shardID, state, timerStart, lastSeenAt, source, timerQuality)
    if not zoneID or not shardID or not timerStart then return end
    local k = tostring(zoneID) .. ":" .. tostring(shardID)
    local zoneName = CrateRush.getCrateZoneName and CrateRush.getCrateZoneName(zoneID) or nil
    if not zoneName then
        local ok, mapInfo = pcall(C_Map.GetMapInfo, zoneID)
        zoneName = (ok and mapInfo and mapInfo.name) or tostring(zoneID)
    end

    removeOtherTimersForZone(zoneID, shardID)

    if CrateRush.domainState and CrateRush.domainState.setTimer then
        CrateRush.domainState:setTimer(zoneID, shardID, {
            zoneName     = zoneName,
            timerStart   = timerStart,
            lastSeenAt   = lastSeenAt or timerStart,
            source       = source,
            timerSource  = source,
            timerQuality = timerQuality,
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
    removeOtherTimersForZone(zoneID, shardID)

    local k = tostring(zoneID) .. ":" .. tostring(shardID)
    if CrateRush.domainState and CrateRush.domainState.getTimer and CrateRush.domainState:getTimer(zoneID, shardID) then
        CrateRush.domainState:touchTimer(zoneID, shardID, lastSeenAt)
        tick()
        return
    end

    local record = CrateRush.storage and CrateRush.storage.getCrateHistory and CrateRush.storage:getCrateHistory(zoneID, shardID)
    if record and record.timestamp and sameShard(record.shardID, shardID) then
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
    if type(payload) ~= "table" or not payload.key then return end
    removeTimerKey(payload.key, true, payload.reason or TIMER_REMOVE_REASON.MANUAL)
end

function timers:removeByKey(key)
    if not key then return end
    removeTimerKey(key, true, TIMER_REMOVE_REASON.MANUAL)
end

function timers:remove(zoneID, shardID)
    if not zoneID or not shardID then return end
    local k = tostring(zoneID) .. ":" .. tostring(shardID)
    timers:removeByKey(k)
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

    local now = GetServerTime()
    for historyKey, record in pairs(history) do
        local zoneID = record and record.zoneID or tostring(historyKey):match("^([^:]+)")
        zoneID = tonumber(zoneID) or zoneID
        if record and zoneID and record.shardID and record.timestamp then
            local elapsed = now - record.timestamp
            local lastSeenAt = record.lastSeenAt or record.timestamp
            local k = tostring(zoneID) .. ":" .. tostring(record.shardID)
            local zoneName = CrateRush.getCrateZoneName and CrateRush.getCrateZoneName(tonumber(zoneID) or zoneID) or nil
            if not zoneName then
                local ok, mapInfo = pcall(C_Map.GetMapInfo, tonumber(zoneID) or zoneID)
                zoneName = (ok and mapInfo and mapInfo.name) or tostring(zoneID)
            end

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
                CrateRush.debug:log("TIMER RESTORED | zone=" .. zoneName .. " shard=" .. tostring(record.shardID) .. " elapsed=" .. tostring(elapsed) .. "s")
            end
        end
    end

    if CrateRush.domainState and CrateRush.domainState.hasActiveTimers and CrateRush.domainState:hasActiveTimers() then
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
end
