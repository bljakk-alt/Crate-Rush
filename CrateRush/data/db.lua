-- CrateRush
-- data/db.lua — Single SavedVariables gateway. All persistence goes through here.

local storage = {}
CrateRush.storage = storage

local function makeCrateKey(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

local function getZoneFromCrateKey(crateKey)
    if not crateKey then return nil end
    local zone = tostring(crateKey):match("^([^:]+)")
    return tonumber(zone) or zone
end

local function sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function getRecordTimestamp(record)
    if type(record) ~= "table" then return 0 end
    return tonumber(record.lastSeenAt or record.timestamp or record.lastDetectedAt or 0) or 0
end

local function migrateCrateHistory()
    if not storage.sv or not storage.sv.profile or not storage.sv.profile.crateHistory then return end

    local migrated = {}
    for historyKey, record in pairs(storage.sv.profile.crateHistory) do
        if type(record) == "table" then
            local keyText = tostring(historyKey)
            local keyZone, keyShard = keyText:match("^([^:]+):(.+)$")
            local zoneID = record.zoneID or keyZone or historyKey
            local shardID = record.shardID or keyShard
            local crateKey = makeCrateKey(zoneID, shardID)

            if crateKey then
                record.zoneID = tonumber(zoneID) or zoneID
                record.shardID = shardID
                migrated[crateKey] = record
            end
        end
    end

    local byZone = {}
    local zoneShards = storage.sv.profile.zoneShards or {}
    for crateKey, record in pairs(migrated) do
        local zoneID = record and (record.zoneID or getZoneFromCrateKey(crateKey)) or nil
        if zoneID then
            local zoneKey = tostring(zoneID)
            local currentShard = zoneShards[zoneKey] and zoneShards[zoneKey].shardID or nil
            local current = byZone[zoneKey]
            local prefer = false

            if not current then
                prefer = true
            elseif currentShard then
                local recordMatches = sameShard(record.shardID, currentShard)
                local currentMatches = sameShard(current.record and current.record.shardID, currentShard)
                if recordMatches and not currentMatches then
                    prefer = true
                elseif recordMatches == currentMatches
                    and getRecordTimestamp(record) > getRecordTimestamp(current.record)
                then
                    prefer = true
                end
            elseif getRecordTimestamp(record) > getRecordTimestamp(current.record) then
                prefer = true
            end

            if prefer then
                byZone[zoneKey] = {
                    key    = crateKey,
                    record = record,
                }
            end
        end
    end

    storage.sv.profile.crateHistory = {}
    for _, item in pairs(byZone) do
        storage.sv.profile.crateHistory[item.key] = item.record
    end
end

local function removeOtherCratesForZone(zoneID, shardID)
    if not storage.sv or not zoneID or not shardID then return end

    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record
            and tostring(record.zoneID or getZoneFromCrateKey(crateKey)) == tostring(zoneID)
            and not sameShard(record.shardID, shardID)
        then
            storage.sv.profile.crateHistory[crateKey] = nil
        end
    end
end

function storage:init(savedVars)
    storage.sv = savedVars
    if storage.sv then
        storage.sv.profile = storage.sv.profile or {}
        storage.sv.profile.filterIDs = storage.sv.profile.filterIDs or {}
        storage.sv.profile.crateHistory = storage.sv.profile.crateHistory or {}
        storage.sv.profile.zoneShards = storage.sv.profile.zoneShards or {}
        migrateCrateHistory()
        storage.sv.profile.ambiguousShardConfirmCount =
            storage.sv.profile.ambiguousShardConfirmCount
            or CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT

        if not storage.sv.profile.shardConfirmCountVersion then
            if storage.sv.profile.shardConfirmCount == nil
                or tonumber(storage.sv.profile.shardConfirmCount) == 4
            then
                storage.sv.profile.shardConfirmCount = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT
            end
            storage.sv.profile.shardConfirmCountVersion = 2
        end
    end
end

-- Filter IDs
function storage:getFilterIDs()
    return storage.sv and storage.sv.profile.filterIDs or {}
end

function storage:setFilterIDs(idTable)
    if storage.sv then
        storage.sv.profile.filterIDs = idTable
    end
end

-- Current shard observed for a crate zone. This is separate from timer history.
function storage:recordZoneShard(zoneID, shardID, seenAt, source)
    if not storage.sv or not zoneID or not shardID then return false end
    storage.sv.profile.zoneShards[tostring(zoneID)] = {
        shardID = shardID,
        seenAt  = seenAt,
        source  = source,
    }
    return true
end

function storage:getZoneShard(zoneID)
    if not storage.sv or not zoneID then return nil end
    return storage.sv.profile.zoneShards[tostring(zoneID)]
end

-- Crate history: timer anchor + last sighting per zone/shard, with one active shard retained per zone.
function storage:recordCrate(zoneID, shardID, timestamp, lastSeenAt, source, lastDetectedAt, timerQuality)
    if not storage.sv or not zoneID or not shardID then return end
    local crateKey = makeCrateKey(zoneID, shardID)
    if not crateKey then return end

    removeOtherCratesForZone(zoneID, shardID)

    local existing = storage.sv.profile.crateHistory[crateKey]
    storage.sv.profile.crateHistory[crateKey] = {
        zoneID         = zoneID,
        shardID        = shardID,
        timestamp      = timestamp,
        lastSeenAt     = lastSeenAt or timestamp,
        lastDetectedAt = lastDetectedAt or (existing and existing.lastDetectedAt) or lastSeenAt or timestamp,
        source         = source or (existing and existing.source) or nil,
        timerQuality   = timerQuality or (existing and existing.timerQuality) or nil,
    }
end

function storage:getCrateHistory(zoneID, shardID)
    if not storage.sv then return nil end
    if shardID then
        local crateKey = makeCrateKey(zoneID, shardID)
        return crateKey and storage.sv.profile.crateHistory[crateKey] or nil
    end

    local newest = nil
    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record and tostring(record.zoneID or getZoneFromCrateKey(crateKey)) == tostring(zoneID) then
            if not newest
                or tonumber(record.lastSeenAt or record.timestamp or 0) > tonumber(newest.lastSeenAt or newest.timestamp or 0)
            then
                newest = record
            end
        end
    end
    return newest
end

function storage:touchCrate(zoneID, shardID, lastSeenAt)
    if not storage.sv or not zoneID or not shardID then return false end
    local record = storage.sv.profile.crateHistory[makeCrateKey(zoneID, shardID)]
    if not record then return false end

    record.lastSeenAt = lastSeenAt or record.lastSeenAt or record.timestamp
    return true
end

function storage:removeCrate(zoneID, shardID)
    if not storage.sv or not zoneID then return false end

    if shardID then
        storage.sv.profile.crateHistory[makeCrateKey(zoneID, shardID)] = nil
        return true
    end

    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record and tostring(record.zoneID or getZoneFromCrateKey(crateKey)) == tostring(zoneID) then
            storage.sv.profile.crateHistory[crateKey] = nil
        end
    end
    return true
end

function storage:getAll()
    return storage.sv and storage.sv.profile.crateHistory or {}
end
function storage:get(key)
    return storage.sv and storage.sv.profile[key]
end

function storage:set(key, value)
    if storage.sv then
        storage.sv.profile[key] = value
    end
end
