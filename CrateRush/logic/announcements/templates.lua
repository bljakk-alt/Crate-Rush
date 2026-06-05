-- CrateRush
-- logic/announcements/templates.lua - Announcement message and placeholder expansion.

local templates = {}
CrateRush.announcementTemplates = templates

local CRATE_STATE = CrateRush.CRATE_STATE

local function getZoneName(zoneID)
    if not zoneID then return "Unknown" end
    if CrateRush.getCrateZoneName then
        return CrateRush.getCrateZoneName(zoneID)
    end

    local ok, mapInfo = pcall(C_Map.GetMapInfo, zoneID)
    if not ok or not mapInfo then return tostring(zoneID) end
    return mapInfo.name or tostring(zoneID)
end

local function shouldIncludeMapPinLocation()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("includeMapPinInDropAndLandedAnnouncements", true)
    end
    return true
end

local function getMapPinLocation(zoneID, state, payload)
    if not shouldIncludeMapPinLocation() then return nil end
    if state ~= CRATE_STATE.DROPPING and state ~= CRATE_STATE.LANDED then return nil end

    return CrateRush.map
        and CrateRush.map.getMapPinLocation
        and CrateRush.map:getMapPinLocation(zoneID, payload.dropX, payload.dropY)
        or nil
end

local function getBaseMessage(zoneName, shard, state)
    local L = CrateRush.L
    if not L then return nil end

    if (state == CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING) and L["PLANE_SPOTTED"] then
        return L["PLANE_SPOTTED"]:format(zoneName, shard)
    elseif state == CRATE_STATE.DROPPING and L["CRATE_DROPPING"] then
        return L["CRATE_DROPPING"]:format(zoneName, shard)
    elseif state == CRATE_STATE.LANDED and L["CRATE_LANDED"] then
        return L["CRATE_LANDED"]:format(zoneName, shard)
    elseif (state == CRATE_STATE.CLAIMED_BY_ALLIANCE or state == CRATE_STATE.CLAIMED_BY_HORDE) and L["CRATE_CLAIMED"] then
        return L["CRATE_CLAIMED"]:format(zoneName, shard)
    end

    return nil
end

local function buildTokens(zoneName, shard, state, mapPin, payload)
    return {
        ["%zone%"]        = zoneName,
        ["%shard%"]       = shard,
        ["%state%"]       = tostring(state or ""),
        ["%coordinates%"] = mapPin or "",
        ["%x%"]           = tostring(payload and payload.dropX or ""),
        ["%y%"]           = tostring(payload and payload.dropY or ""),
    }
end

function templates:build(payload)
    if type(payload) ~= "table" or not payload.zoneID or not payload.shardID or not payload.state then
        return nil
    end

    local zoneName = getZoneName(payload.zoneID)
    local shard = tostring(payload.shardID or "?")
    local msg = getBaseMessage(zoneName, shard, payload.state)
    if not msg then return nil end

    local mapPin = getMapPinLocation(payload.zoneID, payload.state, payload)
    if mapPin then
        msg = msg .. " " .. mapPin
    end

    return {
        zoneID   = payload.zoneID,
        shardID  = payload.shardID,
        state    = payload.state,
        source   = payload.source,
        message  = msg,
        mapPin   = mapPin,
        payload  = payload,
        tokens   = buildTokens(zoneName, shard, payload.state, mapPin, payload),
    }
end
