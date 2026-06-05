-- CrateRush
-- logic/announce.lua - Announcement service subscribed to crate state changes.

local announce = {}
CrateRush.announce = announce

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT

local announcedByCrate = {}

local function getCrateKey(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

local function getCycleKey(payload)
    if type(payload) ~= "table" then return "unknown" end
    return tostring(payload.lifecycleStartedAt or payload.lastDetectedAt or payload.detectedAt or payload.timerStart or "nil")
end

local function shouldAnnounce(zoneID, shardID, state, payload)
    local crateKey = getCrateKey(zoneID, shardID)
    if not crateKey or not state then return false end

    local cycleKey = getCycleKey(payload)
    local announced = announcedByCrate[crateKey]
    if not announced or announced.cycleKey ~= cycleKey then
        announced = {
            cycleKey = cycleKey,
            states   = {},
        }
        announcedByCrate[crateKey] = announced
    end

    if announced.states[state] then return false end
    announced.states[state] = true
    return true
end

function announce:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    self:onStateChange(payload.zoneID, payload.shardID, payload.state, payload)
end

function announce:onStateChange(zoneID, shardID, state, payload)
    if not zoneID or not shardID or not state then return end
    if not shouldAnnounce(zoneID, shardID, state, payload) then return end

    local announcement = CrateRush.announcementTemplates
        and CrateRush.announcementTemplates.build
        and CrateRush.announcementTemplates:build(payload)
        or nil
    if not announcement then return end

    if CrateRush.announcementRouter and CrateRush.announcementRouter.route then
        CrateRush.announcementRouter:route(announcement)
    end
end

if CrateRush.domainEvents and DOMAIN_EVENT and DOMAIN_EVENT.CRATE_STATE_CHANGED then
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, announce, "onCrateStateChanged")
end
