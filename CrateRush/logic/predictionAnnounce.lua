-- CrateRush
-- logic/predictionAnnounce.lua - Routed output for accepted prediction updates.

local predictionAnnounce = {}
CrateRush.predictionAnnounce = predictionAnnounce

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local crateKeys = CrateRush.crateKeys

local announcedByCrate = {}

local function getCrateKey(payload)
    if type(payload) ~= "table" then return nil end
    if crateKeys and crateKeys.make then
        return crateKeys:make(payload.zoneID, payload.shardID)
    end
    if not payload.zoneID or not payload.shardID then return nil end
    return tostring(payload.zoneID) .. ":" .. tostring(payload.shardID)
end

local function getCycleKey(payload)
    if type(payload) ~= "table" then return "current" end
    return tostring(payload.lifecycleStartedAt or payload.lastDetectedAt or payload.detectedAt or "current")
end

local function roundedDisplayCoord(value)
    value = tonumber(value)
    if not value then return nil end
    return tostring(math.floor((value * 1000) + 0.5))
end

local function getLocationSignature(payload)
    if type(payload) ~= "table" then return nil end

    local x = roundedDisplayCoord(payload.dropX)
    local y = roundedDisplayCoord(payload.dropY)
    if not x or not y then return nil end

    return x .. ":" .. y
end

local function shouldAnnouncePrediction(payload)
    local crateKey = getCrateKey(payload)
    local locationSignature = getLocationSignature(payload)
    if not crateKey or not locationSignature then return false end

    local cycleKey = getCycleKey(payload)
    local announced = announcedByCrate[crateKey]
    if not announced or announced.cycleKey ~= cycleKey then
        announcedByCrate[crateKey] = {
            cycleKey = cycleKey,
            locationSignature = locationSignature,
        }
        return true
    end

    if announced.locationSignature == locationSignature then
        return false
    end

    announced.locationSignature = locationSignature
    return true
end

function predictionAnnounce:onPredictionUpdated(payload)
    if type(payload) ~= "table" then return end
    if not shouldAnnouncePrediction(payload) then return end

    local announcement = CrateRush.announcementTemplates
        and CrateRush.announcementTemplates.buildPrediction
        and CrateRush.announcementTemplates:buildPrediction(payload)
        or nil
    if not announcement then return end

    if CrateRush.announcementRouter and CrateRush.announcementRouter.route then
        CrateRush.announcementRouter:route(announcement)
    end
end

function predictionAnnounce:onPredictionCleared(payload)
    if type(payload) ~= "table" then return end

    local crateKey = getCrateKey(payload)
        or (payload.previous and getCrateKey(payload.previous))
    if crateKey then
        announcedByCrate[crateKey] = nil
    end
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.PREDICTION_UPDATED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.PREDICTION_UPDATED, predictionAnnounce, "onPredictionUpdated")
    end
    if DOMAIN_EVENT.PREDICTION_CLEARED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.PREDICTION_CLEARED, predictionAnnounce, "onPredictionCleared")
    end
end