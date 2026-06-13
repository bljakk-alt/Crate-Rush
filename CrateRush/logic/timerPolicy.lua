-- CrateRush
-- logic/timerPolicy.lua - Timer anchor policy for crate lifecycle evidence.

local timerPolicy = {}
CrateRush.timerPolicy = timerPolicy

local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local TIMER_ANCHOR_REASON = CrateRush.TIMER_ANCHOR_REASON
local LEGACY_CRATE_CYCLE_ANCHOR_SOURCE = "MONSTER_SAY"

local function resolveCrateZoneID(zoneID)
    if CrateRush.zoneResolver and CrateRush.zoneResolver.resolveCrateZoneID then
        return CrateRush.zoneResolver:resolveCrateZoneID(zoneID)
    end
    if CrateRush.resolveCrateZoneID then
        return CrateRush.resolveCrateZoneID(zoneID)
    end
    return tonumber(zoneID) or zoneID
end

function timerPolicy:getFrequency(zoneID)
    zoneID = resolveCrateZoneID(zoneID) or zoneID
    if not zoneID then return CrateRush.DEFAULT_ZONE_FREQUENCY end
    return (CrateRush.ZONE_FREQUENCY and CrateRush.ZONE_FREQUENCY[zoneID]) or CrateRush.DEFAULT_ZONE_FREQUENCY
end

function timerPolicy:getLifecycleDetectionGuardianSeconds()
    local fallback = CrateRush.TIMING.LIFECYCLE_DETECTION_GUARDIAN_SECONDS
    if CrateRush.config and CrateRush.config.getNumber then
        return CrateRush.config:getNumber("lifecycleDetectionGuardianSeconds", fallback)
    end
    return fallback
end

function timerPolicy:getCyclePosition(timerStart, now, frequency)
    if not timerStart or not now or not frequency or frequency <= 0 then
        return 0, 0, frequency or 0
    end

    local elapsed = math.max(0, now - timerStart)
    local cycleIndex = math.floor(elapsed / frequency)
    local cycleAge = elapsed - (cycleIndex * frequency)
    local remaining = frequency - cycleAge

    return cycleIndex, cycleAge, remaining
end

function timerPolicy:getNextRolloverTime(timerStart, now, frequency)
    if not timerStart or not now or not frequency or frequency <= 0 then return nil end

    local elapsed = now - timerStart
    if elapsed <= 0 then
        return timerStart + frequency
    end

    local cycles = math.ceil(elapsed / frequency)
    if cycles < 1 then cycles = 1 end

    return timerStart + (cycles * frequency)
end

function timerPolicy:getAnchorTimingDebug(oldTimerStart, newTimerStart, frequency)
    if not oldTimerStart or not newTimerStart then
        return " elapsed=nil cycles=nil cycleTime=nil cycleEstimate=nil"
    end

    local elapsed = newTimerStart - oldTimerStart
    if elapsed < 0 then
        return " elapsed=" .. tostring(elapsed) .. " cycles=nil cycleTime=nil cycleEstimate=nil"
    end

    local cycles = 1
    if frequency and frequency > 0 then
        cycles = math.max(1, math.floor((elapsed / frequency) + 0.5))
    end

    local cycleTime = elapsed / cycles
    return " elapsed=" .. tostring(elapsed)
        .. " cycles=" .. tostring(cycles)
        .. " cycleTime=" .. string.format("%.2f", cycleTime)
        .. " cycleEstimate=" .. string.format("%.2f", cycleTime)
end

function timerPolicy:isAuthoritativeTimerSource(source)
    return source == CRATE_SOURCE.CRATE_CYCLE_ANCHOR
        or source == LEGACY_CRATE_CYCLE_ANCHOR_SOURCE
end

function timerPolicy:getTimerQualityForSource(source)
    if self:isAuthoritativeTimerSource(source) then return "anchor" end
    return "fallback"
end

function timerPolicy:shouldResetTimerAnchor(record, zoneID, source, now)
    source = source or CRATE_SOURCE.UNKNOWN
    local frequency = self:getFrequency(zoneID)
    local cycleIndex, cycleAge, remaining = self:getCyclePosition(record.timerStart, now, frequency)

    if self:isAuthoritativeTimerSource(source) then
        return true, TIMER_ANCHOR_REASON.CRATE_CYCLE_ANCHOR, 0, 0, frequency
    end

    if not record.timerStart then
        return true, TIMER_ANCHOR_REASON.NO_TIMER, 0, 0, frequency
    end

    local nextRollover = self:getNextRolloverTime(record.timerStart, now, frequency)
    -- Non-anchor evidence may only pull the timer earlier toward the missed cycle anchor.
    if nextRollover and now < nextRollover and cycleAge >= self:getLifecycleDetectionGuardianSeconds() then
        return true, TIMER_ANCHOR_REASON.EARLIER_THAN_ROLLOVER, 0, 0, frequency
    end

    return false, "existing_timer", cycleIndex, cycleAge, remaining
end

function timerPolicy:applyTimerLifecycle(record, zoneID, source, now)
    local resetTimer, timerReason, cycleIndex, cycleAge, remaining = self:shouldResetTimerAnchor(record, zoneID, source, now)
    local oldTimerStart = record.timerStart

    if resetTimer then
        record.timerStart = now
        record.timerSource = source
        record.timerQuality = self:getTimerQualityForSource(source)
        record.observedCycleIndex = 0
        cycleIndex = 0
        cycleAge = 0
        remaining = self:getFrequency(zoneID)

        CrateRush.debug:log("TIMER ANCHOR | zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(record.shardID)
            .. " source=" .. tostring(source)
            .. " quality=" .. tostring(record.timerQuality)
            .. " reason=" .. tostring(timerReason)
            .. " oldStart=" .. tostring(oldTimerStart)
            .. " newStart=" .. tostring(record.timerStart)
            .. " freq=" .. tostring(self:getFrequency(zoneID))
            .. self:getAnchorTimingDebug(oldTimerStart, record.timerStart, self:getFrequency(zoneID)))
    elseif record.timerStart and not record.observedCycleIndex then
        record.observedCycleIndex = cycleIndex
    end

    return resetTimer, timerReason, cycleIndex, cycleAge, remaining
end
