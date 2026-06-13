-- CrateRush
-- logic/announce.lua - Announcement service subscribed to crate state changes.

local announce = {}
CrateRush.announce = announce

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local crateKeys = CrateRush.crateKeys
local CRATE_STATE = CrateRush.CRATE_STATE or {}
local MESSAGE_ID = CrateRush.ANNOUNCEMENT_MESSAGE_ID or {}

local announcedByCrate = {}

local function getCycleKey(payload)
    if type(payload) ~= "table" then return "unknown" end
    return tostring(payload.lifecycleStartedAt or payload.lastDetectedAt or payload.detectedAt or payload.timerStart or "nil")
end

local function wasPersistedAnnouncement(zoneID, shardID, cycleKey, state)
    return CrateRush.storage
        and CrateRush.storage.wasCrateStateAnnounced
        and CrateRush.storage:wasCrateStateAnnounced(zoneID, shardID, cycleKey, state)
        or false
end

local function persistAnnouncement(payload, cycleKey, state)
    if not CrateRush.storage or not CrateRush.storage.recordCrateStateAnnouncement then return end
    local announcedAt = CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or nil
    CrateRush.storage:recordCrateStateAnnouncement(payload, cycleKey, state, announcedAt)
end

local function getAnnouncementStateKey(state)
    if CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(state) then
        return state
    end
    return state
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

local function isNotificationEnabled(state)
    local messageID = getMessageIDForState(state)
    if not messageID then return false end
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.isEnabled then
        return CrateRush.announcementMessageConfig:isEnabled(messageID)
    end
    return true
end

local function shouldAnnounce(zoneID, shardID, state, payload)
    state = getAnnouncementStateKey(state)
    local crateKey = crateKeys:make(zoneID, shardID)
    if not crateKey or not state then return false, nil end

    local cycleKey = getCycleKey(payload)
    local announced = announcedByCrate[crateKey]
    if not announced or announced.cycleKey ~= cycleKey then
        announced = {
            cycleKey = cycleKey,
            states   = {},
        }
        announcedByCrate[crateKey] = announced
    end

    if announced.states[state] then return false, cycleKey end
    if wasPersistedAnnouncement(zoneID, shardID, cycleKey, state) then
        announced.states[state] = true
        return false, cycleKey
    end

    announced.states[state] = true
    return true, cycleKey
end

function announce:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    self:onStateChange(payload.zoneID, payload.shardID, payload.state, payload)
end

function announce:onStateChange(zoneID, shardID, state, payload)
    if not zoneID or not shardID or not state then return end
    if not isNotificationEnabled(state) then return end

    local shouldSend, cycleKey = shouldAnnounce(zoneID, shardID, state, payload)
    if not shouldSend then return end

    local announcement = CrateRush.announcementTemplates
        and CrateRush.announcementTemplates.build
        and CrateRush.announcementTemplates:build(payload)
        or nil
    if not announcement then return end

    if CrateRush.announcementRouter and CrateRush.announcementRouter.route then
        CrateRush.announcementRouter:route(announcement)
    end

    persistAnnouncement(payload, cycleKey, state)
end

if CrateRush.domainEvents and DOMAIN_EVENT and DOMAIN_EVENT.CRATE_STATE_CHANGED then
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, announce, "onCrateStateChanged")
end
