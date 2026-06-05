-- CrateRush
-- logic/domainState.lua - Runtime owner for domain state indexes.

local domainState = {}
CrateRush.domainState = domainState

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT

local lifecycleByKey = {}
local currentLifecycleKeyByZone = {}
local timerByKey = {}
local activeTimerKeyByZone = {}
local zoneShardStatusByZone = {}
local visibleTimersByZone = {}

local function makeKey(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

local function parseZoneFromKey(key)
    if not key then return nil end
    local zoneID = tostring(key):match("^([^:]+)")
    return tonumber(zoneID) or zoneID
end

local function sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function copyTable(value)
    if type(value) ~= "table" then return {} end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

local function copyIndex(index)
    local copy = {}
    for key, value in pairs(index or {}) do
        copy[key] = copyTable(value)
    end
    return copy
end

local function removeOtherZoneKeys(index, zoneID, shardID)
    if not index or not zoneID or not shardID then return {} end

    local removed = {}
    for key, record in pairs(index) do
        if record
            and tostring(record.zoneID or parseZoneFromKey(key)) == tostring(zoneID)
            and not sameShard(record.shardID, shardID)
        then
            removed[#removed + 1] = {
                key    = key,
                record = record,
            }
        end
    end

    for _, item in ipairs(removed) do
        index[item.key] = nil
    end

    return removed
end

function domainState:makeKey(zoneID, shardID)
    return makeKey(zoneID, shardID)
end

function domainState:getOrCreateLifecycle(zoneID, shardID, initial)
    local key = makeKey(zoneID, shardID)
    if not key then return nil end

    if not lifecycleByKey[key] then
        local record = copyTable(initial)
        record.key = key
        record.zoneID = zoneID
        record.shardID = shardID
        lifecycleByKey[key] = record
    end

    return lifecycleByKey[key]
end

function domainState:setCurrentLifecycle(zoneID, shardID)
    local key = makeKey(zoneID, shardID)
    if not key then return false end

    currentLifecycleKeyByZone[tostring(zoneID)] = key
    return true
end

function domainState:removeOtherLifecyclesForZone(zoneID, shardID)
    local removed = removeOtherZoneKeys(lifecycleByKey, zoneID, shardID)
    local currentKey = zoneID and currentLifecycleKeyByZone[tostring(zoneID)] or nil
    if currentKey then
        for _, item in ipairs(removed) do
            if item.key == currentKey then
                currentLifecycleKeyByZone[tostring(zoneID)] = nil
                break
            end
        end
    end
    return removed
end

function domainState:removeLifecycle(zoneID, shardID)
    local key = makeKey(zoneID, shardID)
    if not key then return nil end

    local record = lifecycleByKey[key]
    lifecycleByKey[key] = nil

    if zoneID and currentLifecycleKeyByZone[tostring(zoneID)] == key then
        currentLifecycleKeyByZone[tostring(zoneID)] = nil
    end

    return record
end

function domainState:getLifecycle(zoneID, shardID)
    local key = makeKey(zoneID, shardID)
    return key and lifecycleByKey[key] or nil
end

function domainState:getCurrentLifecycle(zoneID)
    local key = zoneID and currentLifecycleKeyByZone[tostring(zoneID)] or nil
    return key and lifecycleByKey[key] or nil
end

function domainState:getLifecycleRecords()
    return lifecycleByKey
end

function domainState:getLifecycleRecordsSnapshot()
    return copyIndex(lifecycleByKey)
end

function domainState:setTimer(zoneID, shardID, timer)
    local key = makeKey(zoneID, shardID)
    if not key then return nil end

    domainState:removeOtherTimersForZone(zoneID, shardID)

    local record = copyTable(timerByKey[key])
    for field, value in pairs(timer or {}) do
        record[field] = value
    end
    record.key = key
    record.zoneID = zoneID
    record.shardID = shardID

    timerByKey[key] = record
    activeTimerKeyByZone[tostring(zoneID)] = key

    return record
end

function domainState:touchTimer(zoneID, shardID, lastSeenAt)
    local key = makeKey(zoneID, shardID)
    local timer = key and timerByKey[key] or nil
    if not timer then return nil end

    timer.lastSeenAt = lastSeenAt or timer.lastSeenAt or timer.timerStart
    return timer
end

function domainState:removeOtherTimersForZone(zoneID, shardID)
    local removed = removeOtherZoneKeys(timerByKey, zoneID, shardID)
    local activeKey = zoneID and activeTimerKeyByZone[tostring(zoneID)] or nil
    if activeKey then
        for _, item in ipairs(removed) do
            if item.key == activeKey then
                activeTimerKeyByZone[tostring(zoneID)] = nil
                break
            end
        end
    end
    return removed
end

function domainState:removeTimerByKey(key)
    if not key then return nil end

    local timer = timerByKey[key]
    timerByKey[key] = nil

    if timer and timer.zoneID and activeTimerKeyByZone[tostring(timer.zoneID)] == key then
        activeTimerKeyByZone[tostring(timer.zoneID)] = nil
    else
        local zoneID = parseZoneFromKey(key)
        if zoneID and activeTimerKeyByZone[tostring(zoneID)] == key then
            activeTimerKeyByZone[tostring(zoneID)] = nil
        end
    end

    return timer
end

function domainState:removeTimer(zoneID, shardID)
    return domainState:removeTimerByKey(makeKey(zoneID, shardID))
end

function domainState:getTimer(zoneID, shardID)
    local key = makeKey(zoneID, shardID)
    return key and timerByKey[key] or nil
end

function domainState:getTimerByKey(key)
    return key and timerByKey[key] or nil
end

function domainState:getActiveTimer(zoneID)
    local key = zoneID and activeTimerKeyByZone[tostring(zoneID)] or nil
    return key and timerByKey[key] or nil
end

function domainState:getTimerRecords()
    return timerByKey
end

function domainState:getTimerRecordsSnapshot()
    return copyIndex(timerByKey)
end

function domainState:hasActiveTimers()
    return next(timerByKey) ~= nil
end

function domainState:onZoneShardStatusChanged(payload)
    if type(payload) ~= "table" or not payload.zoneID then return end

    zoneShardStatusByZone[tostring(payload.zoneID)] = {
        zoneID   = payload.zoneID,
        zoneName = payload.zoneName,
        shardID  = payload.shardID,
        status   = payload.status,
    }
end

function domainState:onCurrentZoneShardChanged(payload)
    if type(payload) ~= "table" or not payload.zoneID then return end

    zoneShardStatusByZone[tostring(payload.zoneID)] = {
        zoneID   = payload.zoneID,
        zoneName = payload.zoneName,
        shardID  = payload.shardID,
        status   = payload.status,
    }
end

function domainState:onCrateStateChanged(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID or not payload.state then return end

    local record = domainState:getOrCreateLifecycle(payload.zoneID, payload.shardID)
    if not record then return end

    domainState:removeOtherLifecyclesForZone(payload.zoneID, payload.shardID)
    domainState:setCurrentLifecycle(payload.zoneID, payload.shardID)

    local update = copyTable(payload)
    for field, value in pairs(update) do
        record[field] = value
    end
    record.state = payload.state
    record.lifecycleStartedAt = payload.lifecycleStartedAt
        or record.lifecycleStartedAt
        or payload.lastDetectedAt
        or payload.detectedAt

    if payload.timerStart then
        domainState:removeOtherTimersForZone(payload.zoneID, payload.shardID)
        domainState:setTimer(payload.zoneID, payload.shardID, {
            timerStart   = payload.timerStart,
            timerSource  = payload.timerSource or payload.source,
            timerQuality = payload.timerQuality,
            lastSeenAt   = payload.lastSeenAt or payload.timerStart,
        })
    end
end

function domainState:onCrateSightingSeen(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID then return end

    if payload.timerStart then
        domainState:removeOtherTimersForZone(payload.zoneID, payload.shardID)
        domainState:setTimer(payload.zoneID, payload.shardID, {
            timerStart   = payload.timerStart,
            timerSource  = payload.timerSource or payload.source,
            timerQuality = payload.timerQuality,
            lastSeenAt   = payload.lastSeenAt or payload.timerStart,
        })
    end

    local lifecycle = domainState:getLifecycle(payload.zoneID, payload.shardID)
    if lifecycle then
        lifecycle.lastSeenAt = payload.lastSeenAt or lifecycle.lastSeenAt
    end
end

function domainState:onActiveTimerChanged(payload)
    if type(payload) ~= "table" or type(payload.sorted) ~= "table" then return end

    visibleTimersByZone = {}
    for _, item in ipairs(payload.sorted) do
        if item and item.key then
            local zoneID = parseZoneFromKey(item.key)
            if zoneID then
                visibleTimersByZone[tostring(zoneID)] = copyTable(item)
            end
        end
    end
end

function domainState:onActiveTimerRemoved(payload)
    if type(payload) ~= "table" then return end

    local key = payload.key or makeKey(payload.zoneID, payload.shardID)
    if key then
        domainState:removeTimerByKey(key)
    end

    if payload.zoneID then
        visibleTimersByZone[tostring(payload.zoneID)] = nil
    end
end

function domainState:getVisibleTimer(zoneID)
    return zoneID and visibleTimersByZone[tostring(zoneID)] or nil
end

function domainState:getZoneShardStatus(zoneID)
    return zoneID and zoneShardStatusByZone[tostring(zoneID)] or nil
end

function domainState:snapshot()
    return {
        lifecycleByKey            = lifecycleByKey,
        currentLifecycleKeyByZone = currentLifecycleKeyByZone,
        timerByKey                = timerByKey,
        activeTimerKeyByZone      = activeTimerKeyByZone,
        visibleTimersByZone       = visibleTimersByZone,
        zoneShardStatusByZone     = zoneShardStatusByZone,
    }
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED, domainState, "onZoneShardStatusChanged")
    end
    if DOMAIN_EVENT.CURRENT_ZONE_SHARD_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CURRENT_ZONE_SHARD_CHANGED, domainState, "onCurrentZoneShardChanged")
    end
    if DOMAIN_EVENT.CRATE_STATE_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, domainState, "onCrateStateChanged")
    end
    if DOMAIN_EVENT.CRATE_SIGHTING_SEEN then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_SIGHTING_SEEN, domainState, "onCrateSightingSeen")
    end
    if DOMAIN_EVENT.ACTIVE_TIMER_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_CHANGED, domainState, "onActiveTimerChanged")
    end
    if DOMAIN_EVENT.ACTIVE_TIMER_REMOVED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_REMOVED, domainState, "onActiveTimerRemoved")
    end
end
