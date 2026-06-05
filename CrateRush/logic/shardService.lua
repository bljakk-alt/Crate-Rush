-- CrateRush
-- logic/shardService.lua - Live shard confirmation and current zone shard status.

local shardService = {}
CrateRush.shardService = shardService

local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local SCAN_TRIGGER = CrateRush.SCAN_TRIGGER
local SHARD_STATUS = CrateRush.SHARD_STATUS
local VIGNETTE_TYPE = CrateRush.VIGNETTE_TYPE

local zoneConfirm = {}
local scanFunc = nil

local zoneShardCheck = {
    zoneID           = nil,
    token            = 0,
    expectedShardID  = nil,
    confirmedShardID = nil,
    graceStarted     = false,
    ignoreUntil      = nil,
    ignoredCount     = 0,
    pollStartedAt    = nil,
    pollCount        = 0,
    observedShardID  = nil,
    observedAt       = nil,
    previousZoneID   = nil,
    previousShardID  = nil,
}

local function zoneLog(msg)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ZONECHECK | " .. tostring(msg))
    end
end

local function nowSeconds()
    return GetTime and GetTime() or 0
end

local function sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
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

local function getShardGraceSeconds()
    local fallback = CrateRush.TIMING.ZONE_SHARD_MISMATCH_GRACE_SECONDS
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("zoneShardMismatchGraceSeconds", fallback)
    end
    return fallback
end

local function getZoneSettleDelaySeconds()
    local fallback = CrateRush.TIMING.ZONE_CHANGE_SETTLE_SCAN_DELAY_SECONDS
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("zoneChangeSettleScanDelaySeconds", fallback)
    end
    return fallback
end

local function getZoneShardPollIntervalSeconds()
    local fallback = CrateRush.TIMING.ZONE_SHARD_POLL_INTERVAL_SECONDS
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("zoneShardPollIntervalSeconds", fallback)
    end
    return fallback
end

local function getZoneShardPollDurationSeconds()
    local fallback = CrateRush.TIMING.ZONE_SHARD_POLL_DURATION_SECONDS
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("zoneShardPollDurationSeconds", fallback)
    end
    return fallback
end

local function getShardConfirmCount()
    local fallback = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("shardConfirmCount", fallback)
    end
    return fallback
end

local function getAmbiguousShardConfirmCount()
    local fallback = CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("ambiguousShardConfirmCount", fallback)
    end
    return fallback
end

local function getStoredShardID(zoneID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not CrateRush.storage or not CrateRush.storage.getCrateHistory then
        return nil
    end

    local record = CrateRush.storage:getCrateHistory(zoneID)
    return record and record.shardID or nil
end

local function publishZoneShardStatus(zoneID, shardID, status)
    if not CrateRush.domainEvents or not CrateRush.domainEvents.publish then return end
    if not CrateRush.DOMAIN_EVENT or not CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED then return end

    local crateZoneID = resolveCrateZoneID(zoneID)
    CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED, {
        zoneID   = crateZoneID,
        zoneName = CrateRush.zoneResolver and CrateRush.zoneResolver:getCrateZoneName(crateZoneID) or tostring(crateZoneID),
        shardID  = shardID,
        status   = status or SHARD_STATUS.UNKNOWN,
    })
end

local function recordZoneShard(zoneID, shardID, source)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return end

    if CrateRush.storage and CrateRush.storage.recordZoneShard then
        CrateRush.storage:recordZoneShard(zoneID, shardID, GetServerTime and GetServerTime() or nowSeconds(), source)
    end
end

function shardService:setScanFunction(fn)
    scanFunc = fn
end

function shardService:isCrateObjectEvidence(vignetteType)
    return vignetteType == VIGNETTE_TYPE.CRATE_DROPPING
        or vignetteType == VIGNETTE_TYPE.CRATE_LANDED
        or vignetteType == VIGNETTE_TYPE.CRATE_CLAIMED_BY_ALLIANCE
        or vignetteType == VIGNETTE_TYPE.CRATE_CLAIMED_BY_HORDE
end

function shardService:canUseSightingForZoneShard(zoneID, sighting)
    if not zoneID or not sighting or not sighting.shardID then return false end
    return sighting.hasPosition
        or (sighting.isKnownCrateVignette and sighting.vignetteType ~= VIGNETTE_TYPE.PLANE_FLYING)
end

function shardService:isPreviousZoneShard(zoneID, shardID)
    return zoneShardCheck.previousZoneID
        and zoneShardCheck.previousZoneID ~= zoneID
        and sameShard(zoneShardCheck.previousShardID, shardID)
end

function shardService:isPreviousZoneShardPending(zoneID, shardID)
    return self:isPreviousZoneShard(zoneID, shardID)
        and not self:isShardConfirmedForZone(zoneID, shardID)
end

function shardService:isShardConfirmedForZone(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return false end
    if zoneShardCheck.zoneID == zoneID and sameShard(zoneShardCheck.confirmedShardID, shardID) then
        return true
    end
    return sameShard(self:getConfirmedShard(zoneID), shardID)
end

function shardService:getConfirmedShardAtScanStart(zoneID)
    return self:getConfirmedShard(zoneID)
end

function shardService:getPreviousZoneID()
    return zoneShardCheck.previousZoneID
end

function shardService:getPreviousShardID()
    return zoneShardCheck.previousShardID
end

function shardService:shouldIgnoreDuringSettle(zoneID, sighting, trigger)
    if not zoneID or zoneShardCheck.zoneID ~= zoneID or not zoneShardCheck.ignoreUntil then return false end
    if nowSeconds() >= zoneShardCheck.ignoreUntil then return false end

    zoneShardCheck.ignoredCount = (zoneShardCheck.ignoredCount or 0) + 1
    zoneLog("IGNORE_SETTLING token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " trigger=" .. tostring(trigger)
        .. " vignetteID=" .. tostring(sighting and sighting.vignetteID)
        .. " shard=" .. tostring(sighting and sighting.shardID)
        .. " guid=" .. tostring(sighting and sighting.guid))
    return true
end

local function getRequiredShardConfirmCount(self, zoneID, shardID)
    if self:isPreviousZoneShard(zoneID, shardID) then
        return getAmbiguousShardConfirmCount()
    end
    return getShardConfirmCount()
end

local function canFastAcceptStoredMatch(self, zoneID, shardID, vignetteType)
    if not zoneShardCheck.expectedShardID or not sameShard(zoneShardCheck.expectedShardID, shardID) then
        return false
    end
    if self:isPreviousZoneShard(zoneID, shardID) then
        return false
    end
    if self:isCrateObjectEvidence(vignetteType) then
        return true
    end
    return true
end

function shardService:processShardEvidence(zoneID, shardID, vignetteType, trigger, scanID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return false end

    if zoneShardCheck.zoneID == zoneID then
        zoneShardCheck.observedShardID = shardID
        zoneShardCheck.observedAt = nowSeconds()
    end

    local fastAcceptedStoredMatch = false
    if zoneShardCheck.zoneID == zoneID
        and zoneShardCheck.expectedShardID
        and sameShard(zoneShardCheck.expectedShardID, shardID)
        and not sameShard(zoneShardCheck.confirmedShardID, shardID)
        and canFastAcceptStoredMatch(self, zoneID, shardID, vignetteType)
    then
        zoneLog("STORED_MATCH_SEEN token=" .. tostring(zoneShardCheck.token)
            .. " zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " trigger=" .. tostring(trigger)
            .. " -> green")
        self:applyConfirmedZoneShard(zoneID, shardID)
        fastAcceptedStoredMatch = true
    end

    if fastAcceptedStoredMatch then return true end

    local previousConfirmedShardID = self:getConfirmedShard(zoneID)
    local requiredCount = getRequiredShardConfirmCount(self, zoneID, shardID)
    self:confirmShard(zoneID, shardID, trigger, scanID, requiredCount)
    local confirmedShardID = self:getConfirmedShard(zoneID)

    if confirmedShardID and not sameShard(previousConfirmedShardID, confirmedShardID) then
        self:applyConfirmedZoneShard(zoneID, confirmedShardID)
        return true
    end

    return false
end

function shardService:onZoneChanged(zoneID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID then return end
    zoneConfirm[zoneID] = {
        shardID          = nil,
        count            = 0,
        confirmed        = false,
        candidateShardID = nil,
        candidateCount   = 0,
        lastSampleKey    = nil,
        candidateLastSampleKey = nil,
    }
    zoneLog("CONFIRM_RESET zone=" .. tostring(zoneID))
end

function shardService:confirmShard(zoneID, shardID, source, sampleKey, requiredCount)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return end
    local c = zoneConfirm[zoneID]
    if not c then return end

    local confirmCount = tonumber(requiredCount)
        or CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT
    source = source or CRATE_SOURCE.UNKNOWN

    if c.confirmed then
        if sameShard(c.shardID, shardID) then return false end

        if sameShard(c.candidateShardID, shardID) then
            if sampleKey and c.candidateLastSampleKey == sampleKey then
                return false
            end
            c.candidateCount = c.candidateCount + 1
        else
            c.candidateShardID = shardID
            c.candidateCount = 1
        end
        c.candidateLastSampleKey = sampleKey

        zoneLog("CONFIRM_CANDIDATE zone=" .. tostring(zoneID)
            .. " current=" .. tostring(c.shardID)
            .. " candidate=" .. tostring(c.candidateShardID)
            .. " count=" .. tostring(c.candidateCount) .. "/" .. tostring(confirmCount)
            .. " source=" .. tostring(source))

        if c.candidateCount >= confirmCount then
            c.shardID = shardID
            c.count = confirmCount
            c.candidateShardID = nil
            c.candidateCount = 0
            c.lastSampleKey = sampleKey
            c.candidateLastSampleKey = nil
            zoneLog("CONFIRM_CHANGED zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(shardID)
                .. " source=" .. tostring(source))
            return true
        end

        return false
    end

    if sameShard(c.shardID, shardID) then
        if sampleKey and c.lastSampleKey == sampleKey then
            return false
        end
        c.count = c.count + 1
        c.lastSampleKey = sampleKey
        zoneLog("CONFIRM_COUNT zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " count=" .. tostring(c.count) .. "/" .. tostring(confirmCount)
            .. " source=" .. tostring(source))
        if c.count >= confirmCount then
            c.confirmed = true
            zoneLog("CONFIRM_LOCK zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(shardID)
                .. " source=" .. tostring(source))
            return true
        end
    else
        c.shardID = shardID
        c.count = 1
        c.lastSampleKey = sampleKey
        zoneLog("CONFIRM_NEW zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " count=1/" .. tostring(confirmCount)
            .. " source=" .. tostring(source))
    end

    return false
end

function shardService:isZoneConfirmed(zoneID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID then return false end
    local c = zoneConfirm[zoneID]
    return c and c.confirmed or false
end

function shardService:getConfirmedShard(zoneID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID then return nil end
    local c = zoneConfirm[zoneID]
    if c and c.confirmed then
        return c.shardID
    end
    return nil
end

function shardService:acceptConfirmedShard(zoneID, shardID, source)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return false end

    local c = zoneConfirm[zoneID]
    if not c then
        c = {
            shardID          = nil,
            count            = 0,
            confirmed        = false,
            candidateShardID = nil,
            candidateCount   = 0,
            lastSampleKey    = nil,
            candidateLastSampleKey = nil,
        }
        zoneConfirm[zoneID] = c
    end

    if c.confirmed and sameShard(c.shardID, shardID) then
        return false
    end

    c.shardID = shardID
    c.count = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT
    c.confirmed = true
    c.candidateShardID = nil
    c.candidateCount = 0
    c.lastSampleKey = nil
    c.candidateLastSampleKey = nil

    zoneLog("CONFIRM_ACCEPT zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " source=" .. tostring(source or CRATE_SOURCE.UNKNOWN))
    return true
end

local function scheduleZoneShardPoll(token, zoneID)
    if not C_Timer or not C_Timer.After then return end

    local interval = getZoneShardPollIntervalSeconds()
    C_Timer.After(interval, function()
        if zoneShardCheck.token ~= token or zoneShardCheck.zoneID ~= zoneID then
            zoneLog("POLL_SKIP oldToken=" .. tostring(token)
                .. " activeToken=" .. tostring(zoneShardCheck.token)
                .. " activeZone=" .. tostring(zoneShardCheck.zoneID))
            return
        end

        if zoneShardCheck.confirmedShardID then
            zoneLog("POLL_DONE token=" .. tostring(token)
                .. " zone=" .. tostring(zoneID)
                .. " confirmed=" .. tostring(zoneShardCheck.confirmedShardID))
            return
        end

        local startedAt = zoneShardCheck.pollStartedAt or nowSeconds()
        zoneShardCheck.pollStartedAt = startedAt

        local elapsed = nowSeconds() - startedAt
        local duration = getZoneShardPollDurationSeconds()
        if elapsed > duration then
            zoneLog("POLL_TIMEOUT token=" .. tostring(token)
                .. " zone=" .. tostring(zoneID)
                .. " elapsed=" .. tostring(elapsed)
                .. " seconds=" .. tostring(duration)
                .. " count=" .. tostring(zoneShardCheck.pollCount or 0))
            if zoneShardCheck.token == token and zoneShardCheck.zoneID == zoneID then
                zoneShardCheck.graceStarted = false
                if zoneShardCheck.observedShardID then
                    local status = zoneShardCheck.expectedShardID and SHARD_STATUS.CHECKING or SHARD_STATUS.UNKNOWN
                    publishZoneShardStatus(zoneID, zoneShardCheck.observedShardID, status)
                elseif zoneShardCheck.expectedShardID then
                    publishZoneShardStatus(zoneID, nil, SHARD_STATUS.CHECKING)
                else
                    publishZoneShardStatus(zoneID, nil, SHARD_STATUS.UNKNOWN)
                end
            end
            return
        end

        zoneShardCheck.pollCount = (zoneShardCheck.pollCount or 0) + 1
        zoneLog("POLL_SCAN token=" .. tostring(token)
            .. " zone=" .. tostring(zoneID)
            .. " elapsed=" .. tostring(elapsed)
            .. " count=" .. tostring(zoneShardCheck.pollCount))

        if scanFunc then
            scanFunc(SCAN_TRIGGER.ZONE_POLL)
        end

        if zoneShardCheck.token == token
            and zoneShardCheck.zoneID == zoneID
            and not zoneShardCheck.confirmedShardID
        then
            scheduleZoneShardPoll(token, zoneID)
        end
    end)
end

function shardService:startCheck(zoneID)
    local rawMapID = zoneID
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID then
        zoneLog("START_SKIP rawZone=" .. tostring(rawMapID) .. " notCrateZone")
        return
    end

    local settleDelay = getZoneSettleDelaySeconds()
    local previousZoneID = zoneShardCheck.zoneID
    local previousShardID = zoneShardCheck.confirmedShardID or zoneShardCheck.observedShardID

    zoneShardCheck.zoneID = zoneID
    zoneShardCheck.token = zoneShardCheck.token + 1
    zoneShardCheck.expectedShardID = getStoredShardID(zoneID)
    zoneShardCheck.confirmedShardID = nil
    zoneShardCheck.graceStarted = false
    zoneShardCheck.ignoreUntil = nowSeconds() + settleDelay
    zoneShardCheck.ignoredCount = 0
    zoneShardCheck.pollStartedAt = nil
    zoneShardCheck.pollCount = 0
    zoneShardCheck.observedShardID = nil
    zoneShardCheck.observedAt = nil
    zoneShardCheck.previousZoneID = previousZoneID
    zoneShardCheck.previousShardID = previousShardID

    zoneLog("START token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " stored=" .. tostring(zoneShardCheck.expectedShardID)
        .. " settleDelay=" .. tostring(settleDelay)
        .. " previousZone=" .. tostring(zoneShardCheck.previousZoneID)
        .. " previousShard=" .. tostring(zoneShardCheck.previousShardID))

    zoneLog("HEADER_PENDING token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " -> yellow noShard")
    publishZoneShardStatus(zoneID, nil, SHARD_STATUS.CHECKING)

    if C_Timer and C_Timer.After then
        local token = zoneShardCheck.token
        C_Timer.After(settleDelay, function()
            if zoneShardCheck.token ~= token or zoneShardCheck.zoneID ~= zoneID then
                zoneLog("SETTLED_SCAN_SKIP oldToken=" .. tostring(token)
                    .. " activeToken=" .. tostring(zoneShardCheck.token)
                    .. " activeZone=" .. tostring(zoneShardCheck.zoneID))
                return
            end

            zoneShardCheck.ignoreUntil = nil
            zoneLog("SETTLED_SCAN token=" .. tostring(token)
                .. " zone=" .. tostring(zoneID)
                .. " ignoredDuringSettle=" .. tostring(zoneShardCheck.ignoredCount))

            if scanFunc then
                scanFunc(SCAN_TRIGGER.ZONE_SETTLED)
            end

            if zoneShardCheck.token == token
                and zoneShardCheck.zoneID == zoneID
                and not zoneShardCheck.confirmedShardID
            then
                zoneShardCheck.pollStartedAt = nowSeconds()
                zoneShardCheck.pollCount = 0
                zoneLog("POLL_START token=" .. tostring(token)
                    .. " zone=" .. tostring(zoneID)
                    .. " interval=" .. tostring(getZoneShardPollIntervalSeconds())
                    .. " duration=" .. tostring(getZoneShardPollDurationSeconds()))
                scheduleZoneShardPoll(token, zoneID)
            end
        end)
    else
        zoneShardCheck.ignoreUntil = nil
    end
end

function shardService:finalizeZoneShardMismatch(token)
    if zoneShardCheck.token ~= token then
        zoneLog("EXPIRE SKIP oldToken=" .. tostring(token)
            .. " activeToken=" .. tostring(zoneShardCheck.token))
        return
    end

    local zoneID = zoneShardCheck.zoneID
    if scanFunc then
        zoneLog("EXPIRE RESCAN token=" .. tostring(token)
            .. " zone=" .. tostring(zoneID)
            .. " stored=" .. tostring(zoneShardCheck.expectedShardID)
            .. " confirmedBefore=" .. tostring(zoneShardCheck.confirmedShardID))
        scanFunc(SCAN_TRIGGER.ZONE_SHARD_GRACE)
        if zoneShardCheck.token ~= token or zoneShardCheck.zoneID ~= zoneID then
            zoneLog("EXPIRE RESCAN CANCEL token=" .. tostring(token)
                .. " activeToken=" .. tostring(zoneShardCheck.token)
                .. " activeZone=" .. tostring(zoneShardCheck.zoneID))
            return
        end
    end

    local expectedShardID = zoneShardCheck.expectedShardID
    local confirmedShardID = zoneShardCheck.confirmedShardID

    zoneLog("EXPIRE DECIDE token=" .. tostring(token)
        .. " zone=" .. tostring(zoneID)
        .. " stored=" .. tostring(expectedShardID)
        .. " confirmedAfter=" .. tostring(confirmedShardID))

    if not zoneID or not expectedShardID or not confirmedShardID then
        zoneLog("EXPIRE NO_DECISION token=" .. tostring(token)
            .. " missing zone/stored/confirmed")
        return
    end

    zoneShardCheck.graceStarted = false

    if sameShard(expectedShardID, confirmedShardID) then
        zoneLog("MATCH_AFTER_GRACE token=" .. tostring(token)
            .. " zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(confirmedShardID)
            .. " -> green")
        publishZoneShardStatus(zoneID, confirmedShardID, SHARD_STATUS.MATCHED)
        return
    end

    publishZoneShardStatus(zoneID, confirmedShardID, SHARD_STATUS.MISMATCH)
    zoneLog("MISMATCH_FINAL token=" .. tostring(token)
        .. " zone=" .. tostring(zoneID)
        .. " stored=" .. tostring(expectedShardID)
        .. " current=" .. tostring(confirmedShardID)
        .. " -> red")

    if CrateRush.onZoneShardChanged then
        CrateRush.onZoneShardChanged(zoneID, expectedShardID, confirmedShardID)
    end
end

function shardService:applyConfirmedZoneShard(zoneID, shardID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return end

    recordZoneShard(zoneID, shardID, CRATE_SOURCE.ZONE_CHECK)
    self:acceptConfirmedShard(zoneID, shardID, CRATE_SOURCE.ZONE_CHECK)

    if zoneShardCheck.zoneID ~= zoneID then
        self:startCheck(zoneID)
    end

    zoneShardCheck.confirmedShardID = shardID
    zoneShardCheck.observedShardID = shardID
    zoneShardCheck.observedAt = nowSeconds()

    local expectedShardID = zoneShardCheck.expectedShardID
    zoneLog("APPLY_CONFIRMED token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " stored=" .. tostring(expectedShardID)
        .. " confirmed=" .. tostring(shardID)
        .. " graceStarted=" .. tostring(zoneShardCheck.graceStarted))

    if not expectedShardID then
        zoneShardCheck.token = zoneShardCheck.token + 1
        zoneShardCheck.graceStarted = false
        zoneLog("NO_STORED token=" .. tostring(zoneShardCheck.token)
            .. " zone=" .. tostring(zoneID)
            .. " confirmed=" .. tostring(shardID)
            .. " -> white")
        publishZoneShardStatus(zoneID, shardID, SHARD_STATUS.UNKNOWN)
        return
    end

    if sameShard(expectedShardID, shardID) then
        zoneShardCheck.token = zoneShardCheck.token + 1
        zoneShardCheck.graceStarted = false
        zoneLog("MATCH token=" .. tostring(zoneShardCheck.token)
            .. " zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " -> green")
        publishZoneShardStatus(zoneID, shardID, SHARD_STATUS.MATCHED)
        return
    end

    publishZoneShardStatus(zoneID, shardID, SHARD_STATUS.CHECKING)
    zoneLog("MISMATCH_PENDING token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " stored=" .. tostring(expectedShardID)
        .. " current=" .. tostring(shardID)
        .. " -> yellow")

    if zoneShardCheck.graceStarted then
        zoneLog("GRACE_ALREADY_RUNNING token=" .. tostring(zoneShardCheck.token)
            .. " zone=" .. tostring(zoneID))
        return
    end

    zoneShardCheck.graceStarted = true
    local token = zoneShardCheck.token
    local grace = getShardGraceSeconds()

    zoneLog("GRACE_START token=" .. tostring(token)
        .. " zone=" .. tostring(zoneID)
        .. " seconds=" .. tostring(grace))

    if C_Timer and C_Timer.After then
        C_Timer.After(grace, function()
            self:finalizeZoneShardMismatch(token)
        end)
    else
        self:finalizeZoneShardMismatch(token)
    end
end

function shardService:acceptCrateEventShard(zoneID, shardID, source)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID or not shardID then return end

    recordZoneShard(zoneID, shardID, source)
    self:acceptConfirmedShard(zoneID, shardID, source)

    zoneShardCheck.token = zoneShardCheck.token + 1
    zoneShardCheck.zoneID = zoneID
    zoneShardCheck.expectedShardID = shardID
    zoneShardCheck.confirmedShardID = shardID
    zoneShardCheck.observedShardID = shardID
    zoneShardCheck.observedAt = nowSeconds()
    zoneShardCheck.graceStarted = false
    zoneShardCheck.ignoreUntil = nil

    zoneLog("CRATE_EVENT_SHARD_CONFIRMED token=" .. tostring(zoneShardCheck.token)
        .. " zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " source=" .. tostring(source)
        .. " -> green")
    publishZoneShardStatus(zoneID, shardID, SHARD_STATUS.MATCHED)
end

function shardService:beginZone(zoneID)
    zoneID = resolveCrateZoneID(zoneID)
    if not zoneID then return end
    self:onZoneChanged(zoneID)
    self:startCheck(zoneID)
end
