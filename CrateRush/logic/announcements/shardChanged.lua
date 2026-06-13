-- CrateRush
-- logic/announcements/shardChanged.lua - Announcement for confirmed zone shard changes.

local shardChanged = {}
CrateRush.shardChangedAnnouncements = shardChanged

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT or {}
local MESSAGE_ID = CrateRush.ANNOUNCEMENT_MESSAGE_ID or {}

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("SHARD CHANGED ANNOUNCE | " .. tostring(message))
    end
end

local function isEnabled()
    return CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.isEnabled
        and CrateRush.announcementMessageConfig:isEnabled(MESSAGE_ID.SHARD_CHANGED)
end

local function getZoneName(zoneID, fallback)
    if fallback and fallback ~= "" then return fallback end
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneName then
        return CrateRush.zoneResolver:getCrateZoneName(zoneID)
    end
    return zoneID and tostring(zoneID) or "Unknown"
end

local function buildTokens(payload)
    local oldShardID = payload.oldShardID or payload.previousShardID
    local newShardID = payload.newShardID or payload.shardID
    return {
        ["%zone%"] = getZoneName(payload.zoneID, payload.zoneName),
        ["%shard%"] = newShardID and tostring(newShardID) or "?",
        ["%old_shard%"] = oldShardID and tostring(oldShardID) or "?",
        ["%new_shard%"] = newShardID and tostring(newShardID) or "?",
        ["%state%"] = "",
        ["%coords%"] = "",
        ["%coordinates%"] = "",
        ["%map_pin%"] = "",
        ["%mappin%"] = "",
        ["%time_to_next%"] = "",
        ["%time_to_drop%"] = "",
        ["%time_to_land%"] = "",
        ["%time_to_claim%"] = "",
        ["%time_to_loot%"] = "",
        ["%claimed_by_faction%"] = "",
        ["%enemy_total%"] = "",
        ["%healers%"] = "",
    }
end

function shardChanged:onZoneShardChanged(payload)
    if not isEnabled() then return false end
    if type(payload) ~= "table" or not payload.zoneID then return false end

    local oldShardID = payload.oldShardID or payload.previousShardID
    local newShardID = payload.newShardID or payload.shardID
    if not oldShardID or not newShardID then return false end
    if CrateRush.crateKeys and CrateRush.crateKeys.sameShard and CrateRush.crateKeys:sameShard(oldShardID, newShardID) then
        return false
    end

    local tokens = buildTokens(payload)
    local message = CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.format
        and CrateRush.announcementMessageConfig:format(MESSAGE_ID.SHARD_CHANGED, tokens)
        or nil
    if not message or message == "" then return false end

    local announcement = {
        messageID = MESSAGE_ID.SHARD_CHANGED,
        zoneID = payload.zoneID,
        shardID = newShardID,
        source = "shardChanged",
        message = message,
        tokens = tokens,
        payload = payload,
    }

    debugLog("zone=" .. tostring(payload.zoneID)
        .. " old=" .. tostring(oldShardID)
        .. " new=" .. tostring(newShardID))

    if CrateRush.announcementRouter and CrateRush.announcementRouter.route then
        return CrateRush.announcementRouter:route(announcement) > 0
    end
    return false
end

if CrateRush.domainEvents and DOMAIN_EVENT and DOMAIN_EVENT.ZONE_SHARD_CHANGED then
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ZONE_SHARD_CHANGED, shardChanged, "onZoneShardChanged")
end