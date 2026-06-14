-- CrateRush
-- logic/announcements/templates.lua - Announcement context and configured message expansion.

local templates = {}
CrateRush.announcementTemplates = templates

local CRATE_STATE = CrateRush.CRATE_STATE or {}
local MESSAGE_ID = CrateRush.ANNOUNCEMENT_MESSAGE_ID or {}
local TIMING = CrateRush.TIMING or {}
local LANDED_ACTION_SECONDS = TIMING.LANDED_ACTION_SECONDS or 300
local CLAIMED_LOOT_WINDOW_SECONDS = TIMING.CLAIMED_LOOT_WINDOW_SECONDS or 58

local function getZoneName(zoneID)
    if not zoneID then return "Unknown" end
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneName then
        return CrateRush.zoneResolver:getCrateZoneName(zoneID)
    end

    return tostring(zoneID)
end

local function shouldIncludeMapPinLocation()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("includeMapPinInDropAndLandedAnnouncements", true)
    end
    return true
end

local function shouldIncludePredictionMapPin()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("includeMapPinInPredictionAnnouncements", true)
    end
    return true
end

local function buildWaypointLinkForAnnouncement(zoneID, state, payload)
    if not shouldIncludeMapPinLocation() then return nil end
    if state ~= CRATE_STATE.DROPPING and state ~= CRATE_STATE.LANDED then return nil end
    if not payload or not payload.dropX or not payload.dropY then return nil end
    if tonumber(payload.dropX) == 0 and tonumber(payload.dropY) == 0 then return nil end

    return CrateRush.map
        and CrateRush.map.setWaypointAndCreateLink
        and CrateRush.map:setWaypointAndCreateLink(zoneID, payload.dropX, payload.dropY)
        or nil
end

local function buildWaypointLinkForPrediction(zoneID, payload)
    if not shouldIncludePredictionMapPin() then return nil end
    if not payload or not payload.dropX or not payload.dropY then return nil end
    if tonumber(payload.dropX) == 0 and tonumber(payload.dropY) == 0 then return nil end

    return CrateRush.map
        and CrateRush.map.setWaypointAndCreateLink
        and CrateRush.map:setWaypointAndCreateLink(zoneID, payload.dropX, payload.dropY)
        or nil
end

local function formatCoord(value)
    value = tonumber(value)
    if not value then return "?" end
    return string.format("%.1f", value * 100)
end

local function buildCoordinateText(payload)
    if not payload or not payload.dropX or not payload.dropY then return nil end
    if tonumber(payload.dropX) == 0 and tonumber(payload.dropY) == 0 then return nil end
    return formatCoord(payload.dropX) .. "/" .. formatCoord(payload.dropY)
end

local function formatEta(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "unknown" end
    seconds = math.floor(seconds + 0.5)
    if seconds <= 0 then return "soon" end
    if seconds < 60 then return "~" .. tostring(seconds) .. "s" end

    local minutes = math.floor(seconds / 60)
    local rest = seconds % 60
    if rest == 0 then return "~" .. tostring(minutes) .. "m" end
    return "~" .. tostring(minutes) .. "m" .. tostring(rest) .. "s"
end

local function formatDuration(seconds)
    seconds = tonumber(seconds)
    if not seconds then return nil end
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return tostring(seconds) .. "s" end

    local minutes = math.floor(seconds / 60)
    local rest = seconds % 60
    if rest == 0 then return tostring(minutes) .. "m" end
    return tostring(minutes) .. "m" .. tostring(rest) .. "s"
end

local function nowSeconds()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return nil
end

local function remainingFrom(startTime, duration)
    startTime = tonumber(startTime)
    duration = tonumber(duration)
    local now = nowSeconds()
    if not startTime or not duration or not now then return nil end
    return math.max(0, duration - math.max(0, now - startTime))
end

local function isLootableClaim(state, payload)
    if CrateRush.isCrateStateClaimedByMyFaction and CrateRush.isCrateStateClaimedByMyFaction(state) then
        return true
    end

    local playerFaction = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or nil
    local claimedFaction = type(payload) == "table" and payload.claimedFaction or nil
    local normalizedClaimed = CrateRush.normalizeFactionKey and CrateRush.normalizeFactionKey(claimedFaction) or nil

    if not playerFaction or not normalizedClaimed then return false end
    return normalizedClaimed == playerFaction
end

local function buildTimeTokens(state, payload)
    payload = type(payload) == "table" and payload or {}

    local timeToClaim = ""
    local timeToLoot = ""

    if state == CRATE_STATE.LANDED then
        timeToClaim = formatDuration(remainingFrom(payload.landedAt or payload.lastSeenAt, LANDED_ACTION_SECONDS)) or ""
    elseif isLootableClaim(state, payload) then
        timeToLoot = formatDuration(remainingFrom(payload.claimedAt or payload.lastSeenAt, CLAIMED_LOOT_WINDOW_SECONDS)) or ""
    end

    return timeToClaim, timeToLoot
end

local function getMessageIDForState(state)
    if state == CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING then
        return MESSAGE_ID.CRATE_DETECTED
    elseif state == CRATE_STATE.DROPPING then
        return MESSAGE_ID.CRATE_DROPPING
    elseif state == CRATE_STATE.LANDED then
        return MESSAGE_ID.CRATE_LANDED
    elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then
        return MESSAGE_ID.CRATE_CLAIMED
    end
    return nil
end

local function humanState(state)
    if state == CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING then return "flying" end
    if state == CRATE_STATE.DROPPING then return "dropping" end
    if state == CRATE_STATE.LANDED then return "landed" end
    if CrateRush.isCrateStateClaimedByMyFaction and CrateRush.isCrateStateClaimedByMyFaction(state) then return "lootable" end
    if CrateRush.isCrateStateClaimedByOppositeFaction and CrateRush.isCrateStateClaimedByOppositeFaction(state) then return "claimed by opposite faction" end
    if CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then return "claimed" end
    return tostring(state or "")
end

local function getMyFactionName()
    if CrateRush.playerContext and CrateRush.playerContext.getFaction then
        return CrateRush.playerContext:getFaction()
    end
    return CrateRush.resolveFactionName and CrateRush.resolveFactionName(nil) or ""
end

local function getOppositeFactionName()
    local factionKey = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or nil
    local oppositeKey = CrateRush.getOppositeFactionKey and CrateRush.getOppositeFactionKey(factionKey) or nil
    return CrateRush.resolveFactionName and CrateRush.resolveFactionName(oppositeKey) or ""
end

local function claimedByFactionText(payload)
    if type(payload) ~= "table" then return "" end
    if CrateRush.isCrateStateClaimedByMyFaction and CrateRush.isCrateStateClaimedByMyFaction(payload.state) then
        return getMyFactionName()
    end
    if CrateRush.isCrateStateClaimedByOppositeFaction and CrateRush.isCrateStateClaimedByOppositeFaction(payload.state) then
        return getOppositeFactionName()
    end
    if payload.claimedFaction and CrateRush.resolveFactionName then
        local factionName = CrateRush.resolveFactionName(payload.claimedFaction)
        if factionName == "Horde" or factionName == "Alliance" then return factionName end
    end
    if payload.claimedFactionName == "Horde" or payload.claimedFactionName == "Alliance" then
        return payload.claimedFactionName
    end
    return ""
end

local function appendLocation(state, coordinates, mapPin)
    local coords = coordinates
    if not coords and (state == CRATE_STATE.DROPPING or state == CRATE_STATE.LANDED) then
        coords = "location not available"
    end

    return coords, mapPin or ""
end

local function buildTokens(zoneName, shard, state, coordinates, mapPin, payload)
    local coords, finalMapPin = appendLocation(state, coordinates, mapPin)
    local timeToClaim, timeToLoot = buildTimeTokens(state, payload)

    return {
        ["%zone%"]          = zoneName,
        ["%shard%"]         = shard,
        ["%state%"]         = humanState(state),
        ["%coords%"]        = coords or "",
        ["%coordinates%"]   = coords or "",
        ["%map_pin%"]       = finalMapPin,
        ["%mappin%"]        = finalMapPin,
        ["%claimed_by_faction%"] = claimedByFactionText(payload),
        ["%time_to_next%"]  = "",
        ["%time_to_drop%"]  = "",
        ["%time_to_land%"]  = "",
        ["%time_to_claim%"] = timeToClaim,
        ["%time_to_loot%"]  = timeToLoot,
        ["%enemy_total%"]   = "",
        ["%healers%"]       = "",
    }
end

function templates:build(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID or not payload.state then
        return nil
    end

    local messageID = getMessageIDForState(payload.state)
    if not messageID then return nil end

    local zoneName = getZoneName(payload.zoneID)
    local shard = tostring(payload.shardID or "?")
    local coordinates = buildCoordinateText(payload)
    local mapPin = buildWaypointLinkForAnnouncement(payload.zoneID, payload.state, payload)
    local tokens = buildTokens(zoneName, shard, payload.state, coordinates, mapPin, payload)

    local msg = CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.format
        and CrateRush.announcementMessageConfig:format(messageID, tokens)
        or nil
    if not msg then return nil end

    return {
        messageID   = messageID,
        zoneID      = payload.zoneID,
        shardID     = payload.shardID,
        state       = payload.state,
        source      = payload.source,
        message     = msg,
        coordinates = coordinates,
        mapPin      = mapPin,
        payload     = payload,
        tokens      = tokens,
    }
end

function templates:buildPrediction(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID then
        return nil
    end
    if not payload.dropX or not payload.dropY then return nil end

    local messageID = MESSAGE_ID.PREDICTION
    local zoneName = getZoneName(payload.zoneID)
    local mapPin = buildWaypointLinkForPrediction(payload.zoneID, payload)
    local shard = tostring(payload.shardID or "?")
    local coords = formatCoord(payload.dropX) .. "/" .. formatCoord(payload.dropY)
    local dropEta = formatEta(payload.secondsToDrop)
    local landEta = formatEta(payload.secondsToLand)
    local tokens = {
        ["%zone%"]          = zoneName,
        ["%shard%"]         = shard,
        ["%state%"]         = "prediction",
        ["%coords%"]        = coords,
        ["%coordinates%"]   = coords,
        ["%map_pin%"]       = mapPin or "",
        ["%mappin%"]        = mapPin or "",
        ["%time_to_next%"]  = "",
        ["%time_to_drop%"]  = dropEta,
        ["%time_to_land%"]  = landEta,
        ["%time_to_claim%"] = "",
        ["%time_to_loot%"]  = "",
        ["%claimed_by_faction%"] = "",
        ["%enemy_total%"]   = "",
        ["%healers%"]       = "",
    }

    local msg = CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.format
        and CrateRush.announcementMessageConfig:format(messageID, tokens)
        or nil
    if not msg then return nil end

    return {
        messageID = messageID,
        zoneID    = payload.zoneID,
        shardID   = payload.shardID,
        state     = "PREDICTION",
        source    = payload.source or "prediction",
        message   = msg,
        localOnly = false,
        mapPin    = mapPin,
        payload   = payload,
        tokens    = tokens,
    }
end

