-- CrateRush
-- logic/announcements/manualService.lua - Manual announcement message selection and placeholder context.

local service = {}
CrateRush.manualAnnouncementService = service

local MESSAGE_ID = CrateRush.ANNOUNCEMENT_MESSAGE_ID or {}
local COCKPIT_TRIGGER = CrateRush.ANNOUNCEMENT_COCKPIT_TRIGGER or {}

local function getZoneName(zoneID, fallback)
    if fallback and fallback ~= "" then return fallback end
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneName then
        return CrateRush.zoneResolver:getCrateZoneName(zoneID)
    end
    if CrateRush.getCrateZoneName then
        return CrateRush.getCrateZoneName(zoneID)
    end
    return zoneID and tostring(zoneID) or "Unknown"
end

local function formatCoord(value)
    value = tonumber(value)
    if not value then return nil end
    if value <= 1 then value = value * 100 end
    return string.format("%.1f", value)
end

local function formatEta(seconds)
    seconds = tonumber(seconds)
    if not seconds then return nil end
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return tostring(seconds) .. "s" end
    local minutes = math.floor(seconds / 60)
    local rest = seconds % 60
    if rest == 0 then return tostring(minutes) .. "m" end
    return tostring(minutes) .. "m" .. tostring(rest) .. "s"
end

local function remainingFromPrediction(payload, field)
    if type(payload) ~= "table" or payload[field] == nil then return nil end
    local remaining = tonumber(payload[field])
    if not remaining then return nil end
    local predictedAt = tonumber(payload.predictedAt)
    if predictedAt and CrateRush.clock and CrateRush.clock.serverTime then
        remaining = remaining - math.max(0, CrateRush.clock:serverTime() - predictedAt)
    end
    return math.max(0, remaining)
end

local function mapPin(zoneID, x, y)
    return CrateRush.map
        and CrateRush.map.setWaypointAndCreateLink
        and CrateRush.map:setWaypointAndCreateLink(zoneID, x, y)
        or nil
end

local function locationTokens(zoneID, x, y)
    local coordX = formatCoord(x)
    local coordY = formatCoord(y)
    local coords = coordX and coordY and (coordX .. "/" .. coordY) or "location not available"
    local pin = coordX and coordY and mapPin(zoneID, x, y) or ""
    return coords, pin
end

local function baseTokens(payload)
    payload = type(payload) == "table" and payload or {}
    local coords, pin = locationTokens(payload.zoneID, payload.dropX, payload.dropY)
    return {
        ["%zone%"]          = getZoneName(payload.zoneID, payload.zoneName),
        ["%shard%"]         = payload.shardID and tostring(payload.shardID) or "?",
        ["%state%"]         = "",
        ["%coords%"]        = coords,
        ["%coordinates%"]   = coords,
        ["%map_pin%"]       = pin,
        ["%mappin%"]        = pin,
        ["%time_to_next%"]  = "",
        ["%time_to_drop%"]  = "",
        ["%time_to_land%"]  = "",
        ["%time_to_claim%"] = "",
        ["%time_to_loot%"]  = "",
        ["%claimed_by_faction%"] = "",
        ["%enemy_total%"]   = "",
        ["%healers%"]       = "",
    }
end

local function formatMessage(messageID, tokens)
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.format then
        return CrateRush.announcementMessageConfig:format(messageID, tokens)
    end
    return nil
end

local function send(messageID, tokens)
    local message = formatMessage(messageID, tokens)
    if CrateRush.manualAnnouncements and CrateRush.manualAnnouncements.send then
        return CrateRush.manualAnnouncements:send(message, messageID)
    end
    return false
end

local function messageIDForCockpitTrigger(trigger, fallback)
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.getMessageIDByCockpitTrigger then
        return CrateRush.announcementMessageConfig:getMessageIDByCockpitTrigger(trigger, fallback)
    end
    return fallback
end

local function messageIDForState(state)
    if state == CrateRush.CRATE_STATE.DETECTED or state == CrateRush.CRATE_STATE.FLYING then
        return MESSAGE_ID.CRATE_DETECTED
    elseif state == CrateRush.CRATE_STATE.DROPPING then
        return MESSAGE_ID.CRATE_DROPPING
    elseif state == CrateRush.CRATE_STATE.LANDED then
        return MESSAGE_ID.CRATE_LANDED
    elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then
        return MESSAGE_ID.CRATE_CLAIMED
    end
    return nil
end

local function humanState(state)
    if state == CrateRush.CRATE_STATE.DETECTED or state == CrateRush.CRATE_STATE.FLYING then
        return "flying"
    elseif state == CrateRush.CRATE_STATE.DROPPING then
        return "dropping"
    elseif state == CrateRush.CRATE_STATE.LANDED then
        return "landed"
    elseif CrateRush.isCrateStateClaimedByMyFaction and CrateRush.isCrateStateClaimedByMyFaction(state) then
        return "lootable"
    elseif CrateRush.isCrateStateClaimedByOppositeFaction and CrateRush.isCrateStateClaimedByOppositeFaction(state) then
        return "claimed by opposite faction"
    elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then
        return "claimed"
    end
    return tostring(state or "unknown")
end

function service:announceTimerRow(row)
    if type(row) ~= "table" or row.noData then return false end
    local tokens = baseTokens(row)
    tokens["%time_to_next%"] = row.timeText or formatEta(row.remaining) or "unknown"
    return send(MESSAGE_ID.AUTO_TIMER_SOON, tokens)
end

function service:announcePrediction(payload)
    if type(payload) ~= "table" or not payload.dropX or not payload.dropY then return false end
    local dropRemaining = remainingFromPrediction(payload, "secondsToDrop")
    if not dropRemaining or dropRemaining <= 0 then return false end

    local tokens = baseTokens(payload)
    tokens["%time_to_drop%"] = formatEta(dropRemaining) or "unknown"
    tokens["%time_to_land%"] = formatEta(remainingFromPrediction(payload, "secondsToLand")) or "unknown"
    return send(messageIDForCockpitTrigger(COCKPIT_TRIGGER.PREDICTION_BOX_SHIFT_CLICK, MESSAGE_ID.PREDICTION), tokens)
end

function service:pinPrediction(payload)
    if type(payload) ~= "table" or payload.dropX == nil or payload.dropY == nil then return false end
    return mapPin(payload.zoneID, payload.dropX, payload.dropY) ~= nil
end

function service:announceTiming(statePayload, predictionPayload)
    if type(predictionPayload) ~= "table" or not predictionPayload.dropX or not predictionPayload.dropY then
        return false
    end

    local tokens = baseTokens(predictionPayload)
    tokens["%time_to_drop%"] = formatEta(remainingFromPrediction(predictionPayload, "secondsToDrop")) or "unknown"
    tokens["%time_to_land%"] = formatEta(remainingFromPrediction(predictionPayload, "secondsToLand")) or "unknown"
    return send(messageIDForCockpitTrigger(COCKPIT_TRIGGER.TIMING_BOX_SHIFT_CLICK, MESSAGE_ID.PREDICTION), tokens)
end

function service:announceState(statePayload, predictionPayload)
    if type(statePayload) ~= "table" then return false end

    local payload = {}
    for key, value in pairs(statePayload) do
        payload[key] = value
    end

    if type(predictionPayload) == "table" then
        if payload.dropX == nil then payload.dropX = predictionPayload.dropX end
        if payload.dropY == nil then payload.dropY = predictionPayload.dropY end
    end

    if CrateRush.announcementTemplates and CrateRush.announcementTemplates.build then
        local announcement = CrateRush.announcementTemplates:build(payload)
        if announcement and announcement.message then
            local messageID = messageIDForCockpitTrigger(COCKPIT_TRIGGER.STATE_BOX_SHIFT_CLICK, announcement.messageID)
            return send(messageID, announcement.tokens)
        end
    end

    local messageID = messageIDForState(payload.state)
    if not messageID then return false end

    local tokens = baseTokens(payload)
    tokens["%state%"] = humanState(payload.state)
    return send(messageID, tokens)
end

function service:announceEnemy(enemyPayload)
    if type(enemyPayload) ~= "table" or not enemyPayload.hasData then return false end
    local tokens = baseTokens(enemyPayload)
    tokens["%enemy_total%"] = enemyPayload.totalRange or enemyPayload.total or "unknown"
    tokens["%healers%"] = enemyPayload.healerRange or enemyPayload.healers or "unknown"
    return send(messageIDForCockpitTrigger(COCKPIT_TRIGGER.ENEMY_BOX_SHIFT_CLICK, MESSAGE_ID.ENEMY_PRESENCE), tokens)
end

