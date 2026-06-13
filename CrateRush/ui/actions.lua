-- CrateRush
-- ui/actions.lua - UI command requests; owns no domain truth.

local actions = {}
CrateRush.uiActions = actions

local function publish(eventName, payload)
    if not eventName then return false end
    if not CrateRush.domainEvents or not CrateRush.domainEvents.publish then return false end
    CrateRush.domainEvents:publish(eventName, payload or {})
    return true
end

local function manualService()
    return CrateRush.manualAnnouncementService
end

function actions:requestTimerRemoval(key)
    if not key then return false end
    if not CrateRush.DOMAIN_EVENT or not CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED then return false end

    return publish(CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED, {
        key    = key,
        reason = CrateRush.TIMER_REMOVE_REASON and CrateRush.TIMER_REMOVE_REASON.MANUAL or "manual",
        source = "ui",
    })
end

function actions:openSettings()
    if CrateRush.configDialog and CrateRush.configDialog.toggle then
        CrateRush.configDialog:toggle()
        return true
    end

    if CrateRush.onSettingsClicked then
        CrateRush.onSettingsClicked()
        return true
    end

    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("SETTINGS | settings panel is not implemented yet")
    end

    return false
end

function actions:announceTimerRow(row)
    local service = manualService()
    return service and service.announceTimerRow and service:announceTimerRow(row) or false
end

function actions:announcePrediction(payload)
    local service = manualService()
    return service and service.announcePrediction and service:announcePrediction(payload) or false
end

function actions:pinPrediction(payload)
    local service = manualService()
    return service and service.pinPrediction and service:pinPrediction(payload) or false
end

function actions:announceTiming(statePayload, predictionPayload)
    local service = manualService()
    return service and service.announceTiming and service:announceTiming(statePayload, predictionPayload) or false
end

function actions:announceState(statePayload, predictionPayload)
    local service = manualService()
    return service and service.announceState and service:announceState(statePayload, predictionPayload) or false
end

function actions:announceEnemy(enemyPayload)
    local service = manualService()
    return service and service.announceEnemy and service:announceEnemy(enemyPayload) or false
end
