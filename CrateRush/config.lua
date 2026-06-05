-- CrateRush
-- config.lua — Runtime settings gateway. SavedVariables are still owned by data/db.lua.

local config = {}
CrateRush.config = config

local DEFAULTS = {
    enabled                              = true,
    showWarningFrame                     = true,
    showTimerbars                        = true,
    announceInChat                       = true,
    announceInRaid                       = true,
    echoAnnouncementsToDefaultChatFrame  = true,
    includeMapPinInDropAndLandedAnnouncements = true,
    debugEnabled                         = false,
    zoneShardMismatchGraceSeconds        = CrateRush.TIMING.ZONE_SHARD_MISMATCH_GRACE_SECONDS,
    zoneChangeSettleScanDelaySeconds     = CrateRush.TIMING.ZONE_CHANGE_SETTLE_SCAN_DELAY_SECONDS,
    zoneShardPollIntervalSeconds         = CrateRush.TIMING.ZONE_SHARD_POLL_INTERVAL_SECONDS,
    zoneShardPollDurationSeconds         = CrateRush.TIMING.ZONE_SHARD_POLL_DURATION_SECONDS,
    lifecycleDetectionGuardianSeconds    = CrateRush.TIMING.LIFECYCLE_DETECTION_GUARDIAN_SECONDS,
    timerMaxUnseenCycles                 = CrateRush.TIMING.TIMER_MAX_UNSEEN_CYCLES,
    shardConfirmCount                    = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT,
    ambiguousShardConfirmCount           = CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT,
    debugState = {
        fontSize = 11,
        x        = nil,
        y        = nil,
        width    = 700,
        height   = 400,
    },
}

local function copyValue(value)
    if type(value) ~= "table" then return value end
    local copied = {}
    for k, v in pairs(value) do
        copied[k] = copyValue(v)
    end
    return copied
end

function config:init(storage)
    config.storage = storage
end

function config:get(key, fallback)
    if not key then return fallback end
    if config.storage and config.storage.get then
        local stored = config.storage:get(key)
        if stored ~= nil then
            return stored
        end
    end
    local default = DEFAULTS[key]
    if default ~= nil then
        return copyValue(default)
    end
    return fallback
end

function config:getNumber(key, fallback)
    return tonumber(config:get(key, fallback)) or fallback
end

function config:getBoolean(key, fallback)
    local value = config:get(key, fallback)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "string" then
        local lower = value:lower()
        if lower == "true" or lower == "1" or lower == "yes" or lower == "on" then return true end
        if lower == "false" or lower == "0" or lower == "no" or lower == "off" then return false end
    end
    return fallback
end

function config:set(key, value)
    if not key then return false end
    if config.storage and config.storage.set then
        config.storage:set(key, value)
        return true
    end
    return false
end

function config:getDefaults()
    return copyValue(DEFAULTS)
end
