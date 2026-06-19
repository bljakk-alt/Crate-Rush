-- CrateRush
-- ui/model.lua - Display-only adapter for UI renderers.

local model = {}
CrateRush.uiModel = model

local SHARD_STATUS = CrateRush.SHARD_STATUS or {}
local TIMING = CrateRush.TIMING or {}
local LANDED_ACTION_SECONDS = TIMING.LANDED_ACTION_SECONDS or 300
local CLAIMED_LOOT_WINDOW_SECONDS = TIMING.CLAIMED_LOOT_WINDOW_SECONDS or 58
local COCKPIT_EMPTY_TEXT = "n/a"

local ADDON_MEDIA = "Interface/AddOns/CrateRush/media/"
local INDICATOR_WARMODE_ON  = ADDON_MEDIA .. "icons/indicator_warmode_on"
local INDICATOR_WARMODE_OFF = ADDON_MEDIA .. "icons/indicator_warmode_off"

local function numberOr(value, fallback)
    local number = tonumber(value)
    if number == nil then return fallback end
    return number
end

local function clamp(value, minValue, maxValue)
    value = numberOr(value, minValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(numberOr(seconds, 0)))
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

local function formatZoneShardLabel(zoneName, shardID)
    local zone = zoneName or "Unknown"
    if shardID ~= nil and shardID ~= "" then
        return zone .. " [" .. tostring(shardID) .. "]"
    end
    return zone
end

local function formatUnseenCycle(entry, total)
    local lastSeenAt = numberOr(entry.lastSeenAt, nil)
    local maxCycles = numberOr(entry.maxUnseenCycles, nil)
    if not lastSeenAt or not maxCycles or maxCycles <= 0 then return nil end
    if not CrateRush.clock or not CrateRush.clock.serverTime then return nil end

    local now = CrateRush.clock:serverTime()
    local elapsed = math.max(0, now - lastSeenAt)
    local cycle = math.floor(elapsed / math.max(1, total))
    cycle = clamp(cycle, 0, maxCycles)
    return "unseen " .. tostring(cycle) .. "/" .. tostring(maxCycles)
end

local function getDisplayZones()
    if CrateRush.zones and CrateRush.zones.getDisplayCrateZones then
        return CrateRush.zones:getDisplayCrateZones()
    end
    return {}
end

local function getZoneAccent(zoneName)
    return (CrateRush.theme and CrateRush.theme.getZoneColor and CrateRush.theme:getZoneColor(zoneName))
        or (CrateRush.theme and CrateRush.theme.getUIColor and CrateRush.theme:getUIColor("zone", "default"))
        or { 0.16, 0.58, 0.86, 1.00 }
end

local function compactSeconds(seconds)
    seconds = numberOr(seconds, nil)
    if not seconds then return COCKPIT_EMPTY_TEXT end
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then
        return tostring(seconds) .. "s"
    end
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    if remainder == 0 then
        return tostring(minutes) .. "m"
    end
    return tostring(minutes) .. "m" .. tostring(remainder) .. "s"
end

local function approximateSeconds(seconds)
    if seconds == nil then return COCKPIT_EMPTY_TEXT end
    return "~" .. compactSeconds(seconds)
end

local function colorMarkup(text, color)
    if not text or type(color) ~= "table" then return tostring(text or "") end
    local r = math.floor(clamp(color[1] or 1, 0, 1) * 255 + 0.5)
    local g = math.floor(clamp(color[2] or 1, 0, 1) * 255 + 0.5)
    local b = math.floor(clamp(color[3] or 1, 0, 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, tostring(text))
end

local function factionText(factionKey)
    factionKey = CrateRush.resolveFactionKey(factionKey)
    local factionName = CrateRush.getFactionName(factionKey) or "Faction"
    local color = CrateRush.theme and CrateRush.theme.getFactionColor and CrateRush.theme:getFactionColor(factionKey) or nil
    return colorMarkup(factionName, color)
end

local function currentFactionKey()
    return CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or CrateRush.resolveFactionKey(nil)
end

local function nowSeconds()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function remainingFrom(startTime, duration)
    startTime = numberOr(startTime, nil)
    duration = numberOr(duration, nil)
    if not startTime or not duration then return nil end
    return math.max(0, duration - math.max(0, nowSeconds() - startTime))
end

local function progressFrom(startTime, duration)
    startTime = numberOr(startTime, nil)
    duration = numberOr(duration, nil)
    if not startTime or not duration or duration <= 0 then return 0 end
    return clamp((nowSeconds() - startTime) / duration, 0, 1)
end

local function fallDurationFromPrediction(payload)
    if type(payload) ~= "table" then return nil end
    local secondsToDrop = numberOr(payload.secondsToDrop, nil)
    local secondsToLand = numberOr(payload.secondsToLand, nil)
    if not secondsToDrop or not secondsToLand then return nil end
    return math.max(0, secondsToLand - secondsToDrop)
end

local function formatCoord(value)
    local number = numberOr(value, nil)
    if not number then return nil end
    if number <= 1 then number = number * 100 end
    return string.format("%.1f", number)
end

function model:shouldShowWarmodeIndicator()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("showWarmodeIndicator", true)
    end
    return true
end

function model:getThemeDisplay()
    local theme = CrateRush.theme and CrateRush.theme.get and CrateRush.theme:get() or nil

    return {
        faction              = theme and theme.faction or nil,
        factionKey           = theme and theme.key or nil,
        headerTopTexture     = theme and theme.headerTopTexture or nil,
        showWarmodeIndicator = self:shouldShowWarmodeIndicator(),
    }
end

function model:getWarModeDisplay()
    local active = CrateRush.playerContext
        and CrateRush.playerContext.isWarModeEnabled
        and CrateRush.playerContext:isWarModeEnabled()
        or false

    return {
        active  = active,
        texture = active and INDICATOR_WARMODE_ON or INDICATOR_WARMODE_OFF,
    }
end

function model:formatHeader(payload)
    payload = type(payload) == "table" and payload or {}

    local status = payload.status or SHARD_STATUS.UNKNOWN or "unknown"
    local zoneName = payload.zoneName or "Unknown"
    local shardID = payload.shardID
    local label

    if shardID ~= nil and shardID ~= "" then
        label = formatZoneShardLabel(zoneName, shardID)
    elseif status == SHARD_STATUS.CHECKING or status == "pending" then
        label = zoneName .. " [checking shard]"
    else
        label = zoneName
    end

    return {
        zoneID   = payload.zoneID,
        zoneName = zoneName,
        shardID  = shardID,
        status   = status,
        label    = label,
    }
end

function model:formatTimerRow(entry)
    if type(entry) ~= "table" or not entry.key then return nil end

    local total = numberOr(entry.total or entry.freq, CrateRush.DEFAULT_ZONE_FREQUENCY or 1)
    total = math.max(1, total)

    local remaining = math.max(0, math.floor(numberOr(entry.remaining, total)))
    local progress = clamp(entry.progress or (total - remaining), 0, total)
    local label = entry.label or formatZoneShardLabel(entry.zoneName, entry.shardID)
    local urgency = entry.urgency or "normal"

    if not entry.urgency then
        if remaining <= numberOr(TIMING.TIMERBAR_URGENT_SECONDS, 0) then
            urgency = "urgent"
        elseif remaining <= numberOr(TIMING.TIMERBAR_WARNING_SECONDS, 0) then
            urgency = "warning"
        end
    end

    return {
        key             = entry.key,
        zoneID          = entry.zoneID,
        zoneName        = entry.zoneName,
        shardID         = entry.shardID,
        label           = label,
        color           = getZoneAccent(entry.zoneName),
        remaining       = remaining,
        total           = total,
        progress        = progress,
        timeText        = entry.timeText or formatTime(remaining),
        unseenText      = formatUnseenCycle(entry, total),
        urgency         = urgency,
        lifecycleActive = entry.lifecycleActive == true,
    }
end

function model:formatTimerRows(payload)
    local source = {}

    if type(payload) == "table" and type(payload.sorted) == "table" then
        source = payload.sorted
    elseif type(payload) == "table" then
        source = payload
    end

    local rows = {}
    local activeByZone = {}
    for _, entry in ipairs(source) do
        local row = self:formatTimerRow(entry)
        if row then
            rows[#rows + 1] = row
            if row.zoneID then
                activeByZone[tostring(row.zoneID)] = true
            end
        end
    end

    for _, zone in ipairs(getDisplayZones()) do
        if not activeByZone[tostring(zone.zoneID)] then
            rows[#rows + 1] = {
                key = "nodata:" .. tostring(zone.zoneID),
                zoneID = zone.zoneID,
                zoneName = zone.zoneName,
                shardID = nil,
                label = zone.zoneName,
                color = { 0.22, 0.26, 0.30, 1.00 },
                remaining = nil,
                total = 1,
                progress = 0,
                timeText = "NO DATA",
                urgency = "none",
                lifecycleActive = false,
                noData = true,
            }
        end
    end

    return rows
end

function model:getCockpitPlaceholder()
    return {
        state = {
            label = COCKPIT_EMPTY_TEXT,
            detail = COCKPIT_EMPTY_TEXT,
        },
        timing = {
            label = COCKPIT_EMPTY_TEXT,
            detail = COCKPIT_EMPTY_TEXT,
        },
        prediction = {
            label = COCKPIT_EMPTY_TEXT,
            detail = COCKPIT_EMPTY_TEXT,
        },
        enemy = {
            factionLabel = "Enemy",
            totalRange = COCKPIT_EMPTY_TEXT,
            healerRange = COCKPIT_EMPTY_TEXT,
        },
    }
end

function model:formatCrateState(payload, predictionPayload)
    payload = type(payload) == "table" and payload or {}
    local state = payload.state or (CrateRush.CRATE_STATE and CrateRush.CRATE_STATE.IDLE) or "IDLE"
    local display = {
        state = state,
        lifecycleActive = state ~= "IDLE",
        mode = "idle",
        activeStep = 0,
        progressToDrop = 0,
        progressToLand = 0,
        dropTimingAvailable = false,
        landTimingAvailable = false,
        label = "Waiting",
        detail = COCKPIT_EMPTY_TEXT,
        remainingText = payload.remaining and (formatTime(payload.remaining) .. " left") or nil,
    }

    local CRATE_STATE = CrateRush.CRATE_STATE or {}
    if state == CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING then
        local secondsToDrop = predictionPayload and numberOr(predictionPayload.secondsToDrop, nil) or nil
        display.activeStep = 1
        display.mode = "progress"
        display.dropTimingAvailable = secondsToDrop ~= nil
        display.progressToDrop = progressFrom(predictionPayload and predictionPayload.predictedAt, secondsToDrop)
        display.label = "Flying"
        display.detail = "Plane confirmed"
    elseif state == CRATE_STATE.DROPPING then
        local fallDuration = fallDurationFromPrediction(predictionPayload)
        display.activeStep = 2
        display.mode = "progress"
        display.progressToDrop = 1
        display.dropTimingAvailable = true
        display.landTimingAvailable = fallDuration ~= nil
        display.progressToLand = progressFrom(payload.droppedAt or payload.lastSeenAt, fallDuration)
        display.label = "Dropping"
        display.detail = "Crate falling"
    elseif state == CRATE_STATE.LANDED then
        local remaining = remainingFrom(payload.landedAt or payload.lastSeenAt, LANDED_ACTION_SECONDS)
        display.activeStep = 3
        display.mode = "action"
        display.label = "Landed"
        display.detail = "Open NOW"
        display.remainingText = remaining and remaining > 0 and compactSeconds(remaining) or nil
    elseif CrateRush.isCrateStateClaimedByMyFaction and CrateRush.isCrateStateClaimedByMyFaction(state) then
        local remaining = remainingFrom(payload.claimedAt or payload.lastSeenAt, CLAIMED_LOOT_WINDOW_SECONDS)
        if not remaining or remaining <= 0 then return display end
        display.activeStep = 4
        display.mode = "action"
        display.label = "Claimed"
        display.detail = "by " .. factionText(payload.claimedFaction or currentFactionKey())
        display.remainingText = compactSeconds(remaining)
    elseif CrateRush.isCrateStateClaimedByOppositeFaction and CrateRush.isCrateStateClaimedByOppositeFaction(state) then
        local remaining = remainingFrom(payload.claimedAt or payload.lastSeenAt, CLAIMED_LOOT_WINDOW_SECONDS)
        if not remaining or remaining <= 0 then return display end
        local oppositeFaction = payload.claimedFaction
        if not CrateRush.normalizeFactionKey(oppositeFaction) then
            oppositeFaction = CrateRush.getOppositeFactionKey(currentFactionKey())
        end
        display.activeStep = 4
        display.mode = "action"
        display.label = "Claimed"
        display.detail = "by " .. factionText(oppositeFaction)
        display.remainingText = nil
    elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then
        display.activeStep = 4
        display.mode = "action"
        display.label = "Claimed"
        display.detail = "Closed"
    end

    return display
end

function model:formatPrediction(payload, statePayload)
    payload = type(payload) == "table" and payload or {}
    statePayload = type(statePayload) == "table" and statePayload or {}

    local CRATE_STATE = CrateRush.CRATE_STATE or {}
    local state = statePayload.state
    if (CrateRush.isCrateStateClaimedByOppositeFaction and CrateRush.isCrateStateClaimedByOppositeFaction(state))
        or state == CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION
    then
        return {
            coords = COCKPIT_EMPTY_TEXT,
            confidenceText = COCKPIT_EMPTY_TEXT,
            dropText = COCKPIT_EMPTY_TEXT,
            landText = COCKPIT_EMPTY_TEXT,
        }
    end

    local hasObservedLocation = statePayload.dropX ~= nil and statePayload.dropY ~= nil
    local preferObservedLocation = hasObservedLocation
        and (state == CRATE_STATE.DROPPING
            or state == CRATE_STATE.LANDED
            or (CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state)))

    local displayX = payload.dropX
    local displayY = payload.dropY
    if preferObservedLocation or displayX == nil or displayY == nil then
        displayX = statePayload.dropX
        displayY = statePayload.dropY
    end

    local x = formatCoord(displayX)
    local y = formatCoord(displayY)
    local coords = x and y and (x .. ", " .. y) or COCKPIT_EMPTY_TEXT

    local confidenceText = payload.confidenceLabel or COCKPIT_EMPTY_TEXT
    local confidence = numberOr(payload.confidence, nil)
    if preferObservedLocation then
        confidenceText = "100%"
    elseif confidence and confidence > 0 then
        confidenceText = tostring(math.floor((confidence * 100) + 0.5)) .. "%"
    end

    local elapsed = 0
    local predictedAt = tonumber(payload.predictedAt)
    if predictedAt and CrateRush.clock and CrateRush.clock.serverTime then
        elapsed = math.max(0, CrateRush.clock:serverTime() - predictedAt)
    end

    local secondsToDrop = payload.secondsToDrop and math.max(0, numberOr(payload.secondsToDrop, 0) - elapsed) or nil
    local secondsToLand = payload.secondsToLand and math.max(0, numberOr(payload.secondsToLand, 0) - elapsed) or nil

    if state == CRATE_STATE.DROPPING then
        local fallDuration = fallDurationFromPrediction(payload)
        secondsToDrop = nil
        secondsToLand = fallDuration and math.max(0, fallDuration - math.max(0, nowSeconds() - numberOr(statePayload.droppedAt or statePayload.lastSeenAt, nowSeconds()))) or nil
    elseif state == CRATE_STATE.LANDED or (CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state)) then
        secondsToDrop = nil
        secondsToLand = nil
    end

    return {
        coords = coords,
        confidenceText = confidenceText,
        dropText = approximateSeconds(secondsToDrop),
        landText = approximateSeconds(secondsToLand),
    }
end

