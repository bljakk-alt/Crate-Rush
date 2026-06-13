-- CrateRush
-- data/db.lua — Single SavedVariables gateway. All persistence goes through here.

local storage = {}
CrateRush.storage = storage

local crateKeys = CrateRush.crateKeys
local crateStateChangedSubscriber = nil
local crateSightingSeenSubscriber = nil

local DEFAULT_PROFILE = {
    enabled                    = true,
    showWarningFrame           = true,
    showTimerbars              = true,
    filterIDs                  = {},
    crateHistory               = {},
    zoneShards                 = {},
    shardConfirmCount          = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT,
    ambiguousShardConfirmCount = CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT,
    debugState                 = {
        fontSize = 11,
        width    = 700,
        height   = 400,
    },
}

local function copyValue(value)
    if type(value) ~= "table" then return value end
    local copied = {}
    for key, child in pairs(value) do
        copied[key] = copyValue(child)
    end
    return copied
end

local function applyDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
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
            local crateKey = crateKeys:make(zoneID, shardID)

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
        local zoneID = record and (record.zoneID or crateKeys:parseZone(crateKey)) or nil
        if zoneID then
            local zoneKey = tostring(zoneID)
            local currentShard = zoneShards[zoneKey] and zoneShards[zoneKey].shardID or nil
            local current = byZone[zoneKey]
            local prefer = false

            if not current then
                prefer = true
            elseif currentShard then
                local recordMatches = crateKeys:sameShard(record.shardID, currentShard)
                local currentMatches = crateKeys:sameShard(current.record and current.record.shardID, currentShard)
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

    local keysToRemove = {}
    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record
            and tostring(record.zoneID or crateKeys:parseZone(crateKey)) == tostring(zoneID)
            and not crateKeys:sameShard(record.shardID, shardID)
        then
            keysToRemove[#keysToRemove + 1] = crateKey
        end
    end

    for _, crateKey in ipairs(keysToRemove) do
        storage.sv.profile.crateHistory[crateKey] = nil
    end
end

local function recordCrateFromPayload(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID then return false end

    storage:recordCrate(
        payload.zoneID,
        payload.shardID,
        payload.timerStart,
        payload.lastSeenAt,
        payload.timerSource or payload.source,
        payload.lastDetectedAt,
        payload.timerQuality
    )
    return true
end

local function normalizeAnnouncementCycleKey(cycleKey)
    return tostring(cycleKey or "nil")
end

local function subscribeDomainPersistenceEvents()
    if not CrateRush.domainEvents or not CrateRush.DOMAIN_EVENT then return end

    if not crateStateChangedSubscriber and CrateRush.DOMAIN_EVENT.CRATE_STATE_CHANGED then
        crateStateChangedSubscriber = CrateRush.domainEvents:subscribe(
            CrateRush.DOMAIN_EVENT.CRATE_STATE_CHANGED,
            storage,
            "onCrateStateChanged"
        )
    end

    if not crateSightingSeenSubscriber and CrateRush.DOMAIN_EVENT.CRATE_SIGHTING_SEEN then
        crateSightingSeenSubscriber = CrateRush.domainEvents:subscribe(
            CrateRush.DOMAIN_EVENT.CRATE_SIGHTING_SEEN,
            storage,
            "onCrateSightingSeen"
        )
    end
end

function storage:init(savedVars)
    storage.sv = savedVars or {}
    if storage.sv then
        storage.sv.profile = storage.sv.profile or copyValue(DEFAULT_PROFILE)
        applyDefaults(storage.sv.profile, DEFAULT_PROFILE)
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

    subscribeDomainPersistenceEvents()
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
    local crateKey = crateKeys:make(zoneID, shardID)
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
        announced      = existing and existing.announced or nil,
    }
end

function storage:wasCrateStateAnnounced(zoneID, shardID, cycleKey, state)
    if not zoneID or not shardID or not cycleKey or not state then return false end

    local record = storage:getCrateHistory(zoneID, shardID)
    local announced = record and record.announced or nil
    if type(announced) ~= "table" then return false end
    if announced.cycleKey ~= normalizeAnnouncementCycleKey(cycleKey) then return false end
    if type(announced.states) ~= "table" then return false end

    return announced.states[state] ~= nil
end

function storage:recordCrateStateAnnouncement(payload, cycleKey, state, announcedAt)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID or not state then return false end
    if not storage.sv then return false end

    recordCrateFromPayload(payload)

    local crateKey = crateKeys:make(payload.zoneID, payload.shardID)
    if not crateKey then return false end

    local record = storage.sv.profile.crateHistory[crateKey]
    if type(record) ~= "table" then return false end

    cycleKey = normalizeAnnouncementCycleKey(cycleKey)
    if type(record.announced) ~= "table" or record.announced.cycleKey ~= cycleKey then
        record.announced = {
            cycleKey = cycleKey,
            states   = {},
        }
    elseif type(record.announced.states) ~= "table" then
        record.announced.states = {}
    end

    record.announced.states[state] = announcedAt or true
    record.announced.updatedAt = announcedAt
    return true
end

function storage:onCrateStateChanged(payload)
    return recordCrateFromPayload(payload)
end

function storage:onCrateSightingSeen(payload)
    return recordCrateFromPayload(payload)
end

function storage:getCrateHistory(zoneID, shardID)
    if not storage.sv then return nil end
    if shardID then
        local crateKey = crateKeys:make(zoneID, shardID)
        return crateKey and storage.sv.profile.crateHistory[crateKey] or nil
    end

    local newest = nil
    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record and tostring(record.zoneID or crateKeys:parseZone(crateKey)) == tostring(zoneID) then
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
    local record = storage.sv.profile.crateHistory[crateKeys:make(zoneID, shardID)]
    if not record then return false end

    record.lastSeenAt = lastSeenAt or record.lastSeenAt or record.timestamp
    return true
end

function storage:removeCrate(zoneID, shardID)
    if not storage.sv or not zoneID then return false end

    if shardID then
        storage.sv.profile.crateHistory[crateKeys:make(zoneID, shardID)] = nil
        return true
    end

    local keysToRemove = {}
    for crateKey, record in pairs(storage.sv.profile.crateHistory) do
        if record and tostring(record.zoneID or crateKeys:parseZone(crateKey)) == tostring(zoneID) then
            keysToRemove[#keysToRemove + 1] = crateKey
        end
    end
    for _, crateKey in ipairs(keysToRemove) do
        storage.sv.profile.crateHistory[crateKey] = nil
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
