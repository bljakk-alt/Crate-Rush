-- CrateRush
-- config.lua — Runtime settings gateway. SavedVariables are still owned by data/db.lua.

local config = {}
CrateRush.config = config

-- Release policy for v0.9.x: these outputs are intentionally always enabled.
-- They are not user preferences yet, so config:get() returns these values before
-- reading SavedVariables. Remove this table when global output toggles become
-- real configuration controls.
local FORCED_ON_SETTINGS = {
    showWarningFrame                          = true,
    announceToPartyRaid                       = true,
    announceToAddonComm                       = true,
    includeMapPinInDropAndLandedAnnouncements = true,
    includeMapPinInPredictionAnnouncements   = true,
}

local DEFAULTS = {
    enabled                              = true,
    activationMode                       = "warMode",
    factionOverride                      = nil,
    warnWhenWarModeOff                   = false,
    showWarningFrame                     = true,
    showTimerbars                        = true,
    showWarmodeIndicator                 = true,
    framesLocked                         = false,
    announceToPartyRaid                  = true,
    announceToAddonComm                  = true,
    echoAnnouncementsToDefaultChatFrame  = true,
    includeMapPinInDropAndLandedAnnouncements = true,
    modulePredictionEnabled              = true,
    includeMapPinInPredictionAnnouncements = true,
    moduleBountyEnabled                  = false,
    moduleQueueEnabled                   = false,
    moduleEnemyPresenceEnabled           = false,
    enemyPresenceRadiusYards             = 250,
    enemyPresenceProximityPollSeconds    = 1,
    integrationHatedCrateTrackerEnabled  = false,
    integrationHatedCrateTrackerReceive  = false,
    integrationHatedCrateTrackerSend     = false,
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

local function registerAnnouncementDefaults()
    for _, definition in ipairs(CrateRush.ANNOUNCEMENT_MESSAGE_CATALOG or {}) do
        if definition.configurable ~= false then
            local keys = definition.keys or {}
            local outputs = definition.defaultOutputs or {}
            if keys.enabled then DEFAULTS[keys.enabled] = definition.defaultEnabled ~= false end
            if keys.template then DEFAULTS[keys.template] = definition.defaultTemplate or "" end
            if keys.defaultChatFrame then DEFAULTS[keys.defaultChatFrame] = outputs.defaultChatFrame ~= false end
            if keys.warningFrame then DEFAULTS[keys.warningFrame] = outputs.warningFrame ~= false end
            if keys.partyRaid then DEFAULTS[keys.partyRaid] = outputs.partyRaid ~= false end
            if keys.raidWarning then DEFAULTS[keys.raidWarning] = outputs.raidWarning == true end
            if keys.leadSeconds and definition.timerLeadSeconds then DEFAULTS[keys.leadSeconds] = definition.timerLeadSeconds end
        end
    end
end

registerAnnouncementDefaults()
local function copyValue(value)
    if type(value) ~= "table" then return value end
    local copied = {}
    for k, v in pairs(value) do
        copied[k] = copyValue(v)
    end
    return copied
end

local function valuesEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for key, value in pairs(a) do
        if not valuesEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function publishConfigChanged(key, value, previousValue, source)
    if not CrateRush.domainEvents
        or not CrateRush.DOMAIN_EVENT
        or not CrateRush.DOMAIN_EVENT.CONFIG_CHANGED
    then
        return 0
    end

    return CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.CONFIG_CHANGED, {
        key           = key,
        value         = copyValue(value),
        previousValue = copyValue(previousValue),
        defaultValue  = copyValue(DEFAULTS[key]),
        source        = source or "config",
    })
end

function config:init(storage)
    config.storage = storage
end

function config:get(key, fallback)
    if not key then return fallback end
    if FORCED_ON_SETTINGS[key] ~= nil then
        return FORCED_ON_SETTINGS[key]
    end
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

function config:set(key, value, source)
    if not key then return false end
    if config.storage and config.storage.set then
        local previousValue = config:get(key)
        config.storage:set(key, value)
        local currentValue = config:get(key)
        if not valuesEqual(previousValue, currentValue) then
            publishConfigChanged(key, currentValue, previousValue, source)
        end
        return true
    end
    return false
end

function config:apply(values, source)
    if type(values) ~= "table" then return 0 end

    local changed = 0
    for key, value in pairs(values) do
        local previousValue = config:get(key)
        if config:set(key, value, source) then
            local currentValue = config:get(key)
            if not valuesEqual(previousValue, currentValue) then
                changed = changed + 1
            end
        end
    end
    return changed
end

function config:getDefaults()
    return copyValue(DEFAULTS)
end

function config:getDefault(key, fallback)
    local default = DEFAULTS[key]
    if default ~= nil then
        return copyValue(default)
    end
    return fallback
end

function config:reset(keys)
    if type(keys) ~= "table" then return false end
    for _, key in ipairs(keys) do
        if key and DEFAULTS[key] ~= nil then
            config:set(key, copyValue(DEFAULTS[key]), "reset")
        end
    end
    return true
end


