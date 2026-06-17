-- CrateRush
-- logic/announcements/timerSoon.lua - Timer-based announcement when a zone timer approaches rollover.

local timerSoon = {}
CrateRush.timerSoonAnnouncements = timerSoon

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT or {}
local MESSAGE_ID = CrateRush.ANNOUNCEMENT_MESSAGE_ID or {}
local announcedCycleByTimerKey = {}

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("TIMER SOON | " .. tostring(message))
    end
end

local function getDefinition()
    return CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.getDefinition
        and CrateRush.announcementMessageConfig:getDefinition(MESSAGE_ID.AUTO_TIMER_SOON)
        or nil
end

local function isEnabled()
    return CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.isEnabled
        and CrateRush.announcementMessageConfig:isEnabled(MESSAGE_ID.AUTO_TIMER_SOON)
end

local function getLeadSeconds()
    local definition = getDefinition() or {}
    local key = definition.keys and definition.keys.leadSeconds or nil
    local fallback = tonumber(definition.timerLeadSeconds) or 30
    if CrateRush.config and CrateRush.config.getNumber then
        return math.max(0, CrateRush.config:getNumber(key, fallback) or fallback)
    end
    return fallback
end

local function getZoneName(zoneID, fallback)
    if fallback and fallback ~= "" then return fallback end
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneName then
        return CrateRush.zoneResolver:getCrateZoneName(zoneID)
    end
    return zoneID and tostring(zoneID) or "Unknown"
end

local function getAnnouncementZoneName(zoneID, fallback)
    local zoneName = getZoneName(zoneID, fallback)
    if tonumber(zoneID) == 2437 then
        return "Zul Aman"
    end
    return zoneName
end

local function getZoneEnglishName(zoneID)
    if CrateRush.zoneResolver and CrateRush.zoneResolver.getCrateZoneEnglishName then
        return CrateRush.zoneResolver:getCrateZoneEnglishName(zoneID)
    end
    if CrateRush.getCrateZoneEnglishName then
        return CrateRush.getCrateZoneEnglishName(zoneID)
    end
    return getZoneName(zoneID)
end

local function formatEta(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "unknown" end
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return tostring(seconds) .. "s" end
    local minutes = math.floor(seconds / 60)
    local rest = seconds % 60
    if rest == 0 then return tostring(minutes) .. "m" end
    return tostring(minutes) .. "m" .. tostring(rest) .. "s"
end

local function cycleIndex(item, now)
    local timerStart = tonumber(item and item.timerStart)
    local freq = tonumber(item and item.freq)
    if not timerStart or not freq or freq <= 0 then return nil end
    return math.floor(math.max(0, (now or 0) - timerStart) / freq) + 1
end

local function buildTokens(item)
    return {
        ["%zone%"] = getAnnouncementZoneName(item.zoneID, item.zoneName),
        ["%zone_en%"] = getZoneEnglishName(item.zoneID),
        ["%zone_english%"] = getZoneEnglishName(item.zoneID),
        ["%shard%"] = item.shardID and tostring(item.shardID) or "?",
        ["%state%"] = "",
        ["%state_en%"] = "",
        ["%coords%"] = "",
        ["%coordinates%"] = "",
        ["%map_pin%"] = "",
        ["%mappin%"] = "",
        ["%time_to_next%"] = formatEta(item.remaining),
        ["%time_to_drop%"] = "",
        ["%time_to_land%"] = "",
        ["%time_to_claim%"] = "",
        ["%time_to_loot%"] = "",
        ["%claimed_by_faction%"] = "",
        ["%claimed_by_faction_en%"] = "",
        ["%enemy_total%"] = "",
        ["%healers%"] = "",
    }
end

local function routeTimerSoon(item)
    local tokens = buildTokens(item)
    local message = CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.format
        and CrateRush.announcementMessageConfig:format(MESSAGE_ID.AUTO_TIMER_SOON, tokens)
        or nil
    if not message or message == "" then return false end

    local announcement = {
        messageID = MESSAGE_ID.AUTO_TIMER_SOON,
        zoneID = item.zoneID,
        shardID = item.shardID,
        source = "timerSoon",
        message = message,
        tokens = tokens,
        payload = item,
    }

    if CrateRush.announcementRouter and CrateRush.announcementRouter.route then
        return CrateRush.announcementRouter:route(announcement) > 0
    end
    return false
end

function timerSoon:onActiveTimerChanged(payload)
    if not isEnabled() then return end
    if type(payload) ~= "table" or type(payload.sorted) ~= "table" then return end

    local leadSeconds = getLeadSeconds()
    if leadSeconds <= 0 then return end

    local now = tonumber(payload.now) or 0
    for _, item in ipairs(payload.sorted) do
        local remaining = tonumber(item and item.remaining)
        local key = item and item.key
        local nextCycle = cycleIndex(item, now)
        if key and remaining and nextCycle and remaining <= leadSeconds then
            if announcedCycleByTimerKey[key] ~= nextCycle then
                debugLog("announce zone=" .. tostring(item.zoneID)
                    .. " shard=" .. tostring(item.shardID)
                    .. " remaining=" .. tostring(math.floor(remaining + 0.5))
                    .. " lead=" .. tostring(leadSeconds))
                if routeTimerSoon(item) then
                    announcedCycleByTimerKey[key] = nextCycle
                else
                    debugLog("delivery_failed zone=" .. tostring(item.zoneID)
                        .. " shard=" .. tostring(item.shardID)
                        .. " remaining=" .. tostring(math.floor(remaining + 0.5)))
                end
            end
        end
    end
end

function timerSoon:onActiveTimerRemoved(payload)
    if type(payload) ~= "table" then return end
    local key = payload.key
    if key then announcedCycleByTimerKey[key] = nil end
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.ACTIVE_TIMER_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_CHANGED, timerSoon, "onActiveTimerChanged")
    end
    if DOMAIN_EVENT.ACTIVE_TIMER_REMOVED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_REMOVED, timerSoon, "onActiveTimerRemoved")
    end
end
