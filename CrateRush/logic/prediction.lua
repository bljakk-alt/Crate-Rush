-- CrateRush
-- logic/prediction.lua - Runtime crate drop prediction service.

local prediction = {}
CrateRush.prediction = prediction

local CRATE_STATE = CrateRush.CRATE_STATE
local VIGNETTE_TYPE = CrateRush.VIGNETTE_TYPE
local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local crateKeys = CrateRush.crateKeys

local DROP_CORRECTION_DISTANCE = 0.03
local ANGLE_TOLERANCE_DEGREES = 5
local ANGLE_FALLBACK_TOLERANCE_DEGREES = 8
local ANGLE_MIN_DISTANCE = 0.001
local ANGLE_SELECTION_MIN_ADVANTAGE_DEGREES = 2
local ANGLE_SWITCH_MIN_ADVANTAGE_DEGREES = 2
local STRONG_ANGLE_BEST_MAX_DEGREES = 1
local STRONG_ANGLE_SECOND_MIN_DEGREES = 2
local STRONG_ANGLE_STABLE_TICKS = 2

local activeByKey = {}
local pendingLogByKey = {}
local routeCandidateStateByKey = {}

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("PREDICTION | " .. tostring(message))
    end
end

local function nowSeconds()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function isEnabled()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("modulePredictionEnabled", false)
    end
    return false
end

local function isTerminalState(state)
    return CrateRush.isCrateStateClaimed(state)
end

local function getLifecycle(zoneID, shardID)
    if not CrateRush.domainState or not CrateRush.domainState.getLifecycle then return nil end
    return CrateRush.domainState:getLifecycle(zoneID, shardID)
end

local function isFlyingLifecycle(zoneID, shardID, planeConfirmed)
    if planeConfirmed then return true end

    local lifecycle = getLifecycle(zoneID, shardID)
    local state = lifecycle and lifecycle.state or nil
    return state == CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING
end

local function getRoute(routeID)
    local routes = CrateRushRoutes or CrateRush.PREDICTION_ROUTES or {}
    return routeID and routes[routeID] or nil
end

local function getCellCandidates(zoneID, roughKey, fineKey)
    if CrateRush.routeData and CrateRush.routeData.getCellCandidates then
        return CrateRush.routeData:getCellCandidates(zoneID, roughKey, fineKey)
    end

    local index = CrateRushRouteCellIndex or CrateRush.PREDICTION_ROUTE_CELL_INDEX or {}
    return index[zoneID]
        and index[zoneID][roughKey]
        and index[zoneID][roughKey][fineKey]
        or nil
end

local function publish(eventName, payload)
    if not CrateRush.domainEvents or not eventName then return 0 end
    return CrateRush.domainEvents:publish(eventName, payload or {})
end

local function toNumber(value)
    return value and tonumber(value) or nil
end

local function formatCoord(value)
    value = toNumber(value)
    if not value then return "?" end
    return string.format("%.1f", value * 100)
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

local function formatAngle(angle)
    angle = tonumber(angle)
    if not angle then return "?" end
    return string.format("%.1f", angle)
end

local function clearOtherPredictionsForZone(zoneID, shardID, reason)
    if not zoneID or not shardID then return 0 end

    local removed = 0
    local targetKey = crateKeys and crateKeys:make(zoneID, shardID) or nil
    local function isOtherZoneShardKey(key)
        return targetKey
            and key
            and key ~= targetKey
            and tostring(crateKeys:parseZone(key)) == tostring(zoneID)
    end

    for key, item in pairs(activeByKey) do
        if item
            and tostring(item.zoneID) == tostring(zoneID)
            and not crateKeys:sameShard(item.shardID, shardID)
        then
            activeByKey[key] = nil
            pendingLogByKey[key] = nil
            routeCandidateStateByKey[key] = nil
            removed = removed + 1
            publish(DOMAIN_EVENT and DOMAIN_EVENT.PREDICTION_CLEARED, {
                zoneID = item.zoneID,
                shardID = item.shardID,
                reason = reason,
                previous = item,
            })
        end
    end

    for key in pairs(routeCandidateStateByKey) do
        if isOtherZoneShardKey(key) then
            routeCandidateStateByKey[key] = nil
            pendingLogByKey[key] = nil
            removed = removed + 1
        end
    end

    for key in pairs(pendingLogByKey) do
        if isOtherZoneShardKey(key) then
            pendingLogByKey[key] = nil
        end
    end

    return removed
end

local function getConfidenceLabel(selected, candidateCount)
    if not selected then return "Low" end
    if candidateCount and candidateCount > 1 then return "Medium" end

    local confidence = tonumber(selected.confidence or 0) or 0
    if confidence >= 0.80 then return "High" end
    return "Medium"
end

local function buildCellKeys(x, y)
    if CrateRush.routeData and CrateRush.routeData.getCellKeys then
        return CrateRush.routeData:getCellKeys(x, y)
    end

    local gx = x * 100
    local gy = y * 100

    local roughX = math.floor(gx / 4)
    local roughY = math.floor(gy / 4)
    local fineX = math.floor(gx)
    local fineY = math.floor(gy)

    return {
        gx = gx,
        gy = gy,
        roughX = roughX,
        roughY = roughY,
        fineX = fineX,
        fineY = fineY,
        roughKey = tostring(roughX) .. ":" .. tostring(roughY),
        fineKey = tostring(fineX) .. ":" .. tostring(fineY),
    }
end

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function calculateMovementAngle(previousPoint, point)
    if not previousPoint or not point then return nil end
    if not previousPoint.x or not previousPoint.y or not point.x or not point.y then return nil end

    local dx = point.x - previousPoint.x
    local dy = point.y - previousPoint.y
    local distance = math.sqrt((dx * dx) + (dy * dy))
    if distance < ANGLE_MIN_DISTANCE then return nil end

    local angle = math.deg(atan2(dx, -dy))
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function angleDelta(a, b)
    a = tonumber(a)
    b = tonumber(b)
    if not a or not b then return nil end

    local diff = math.abs((a - b + 180) % 360 - 180)
    return diff
end

local function hydrateCandidate(candidate)
    if type(candidate) ~= "table" then return nil end

    local route = getRoute(candidate.routeID)
    return {
        routeID = candidate.routeID,
        dropClusterID = candidate.dropClusterID or (route and route.dropClusterID) or nil,
        dropX = toNumber(candidate.dropX) or (route and toNumber(route.dropX)) or nil,
        dropY = toNumber(candidate.dropY) or (route and toNumber(route.dropY)) or nil,
        secondsToDrop = toNumber(candidate.secondsToDrop),
        secondsToLand = toNumber(candidate.secondsToLand or candidate.avgDropToLandedSeconds)
            or (route and toNumber(route.avgDropToLandedSeconds))
            or nil,
        angle = toNumber(candidate.angle) or (route and toNumber(route.angle)) or nil,
        samples = tonumber(candidate.samples or 0) or 0,
        confidence = tonumber(candidate.confidence or 0) or 0,
    }
end

local function preferCandidate(a, b)
    if not a then return b end
    if not b then return a end

    if (a.confidence or 0) == (b.confidence or 0) then
        if (a.samples or 0) == (b.samples or 0) then
            return tostring(a.routeID or "") <= tostring(b.routeID or "") and a or b
        end
        return (a.samples or 0) > (b.samples or 0) and a or b
    end

    return (a.confidence or 0) > (b.confidence or 0) and a or b
end

local function hydrateCandidates(candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return nil, nil, 0, "no_candidates"
    end

    local byRoute = {}
    local routeCount = 0
    for _, candidate in ipairs(candidates) do
        local item = hydrateCandidate(candidate)
        if item and item.routeID and item.dropX and item.dropY then
            if not byRoute[item.routeID] then
                routeCount = routeCount + 1
            end
            byRoute[item.routeID] = preferCandidate(byRoute[item.routeID], item)
        end
    end

    if routeCount == 0 then return nil, nil, 0, "no_usable_candidates" end

    return byRoute, nil, routeCount, nil
end

local function countRoutes(routeSet)
    if type(routeSet) ~= "table" then return 0 end

    local count = 0
    for routeID in pairs(routeSet) do
        if routeID then count = count + 1 end
    end
    return count
end

local function firstRouteID(routeSet)
    if type(routeSet) ~= "table" then return nil end
    for routeID in pairs(routeSet) do
        return routeID
    end
    return nil
end

local function getRouteAngle(routeID, candidate)
    local route = getRoute(routeID)
    return toNumber((candidate and candidate.angle) or (route and route.angle))
end

local function selectFromRouteSet(routeSet, byRoute)
    local routeID = firstRouteID(routeSet)
    return routeID and byRoute and byRoute[routeID] or nil
end

local function filterRouteSetByAngle(routeSet, byRoute, observedAngle, tolerance)
    if type(routeSet) ~= "table" or type(byRoute) ~= "table" or not observedAngle then
        return nil, 0
    end

    local filtered = {}
    local count = 0
    for routeID in pairs(routeSet) do
        local candidate = byRoute[routeID]
        local routeAngle = getRouteAngle(routeID, candidate)
        local delta = angleDelta(observedAngle, routeAngle)
        if delta and delta <= tolerance then
            filtered[routeID] = true
            count = count + 1
        end
    end

    return filtered, count
end

local function selectClosestByAngle(routeSet, byRoute, observedAngle, minAdvantage)
    if type(routeSet) ~= "table" or type(byRoute) ~= "table" or not observedAngle then
        return nil, nil, nil, 0
    end

    local bestCandidate
    local bestDelta
    local secondDelta
    local count = 0

    for routeID in pairs(routeSet) do
        local candidate = byRoute[routeID]
        local routeAngle = getRouteAngle(routeID, candidate)
        local delta = angleDelta(observedAngle, routeAngle)
        if delta then
            count = count + 1
            if not bestDelta or delta < bestDelta then
                secondDelta = bestDelta
                bestDelta = delta
                bestCandidate = candidate
            elseif not secondDelta or delta < secondDelta then
                secondDelta = delta
            end
        end
    end

    if not bestCandidate then return nil, bestDelta, secondDelta, count end
    if secondDelta and (secondDelta - bestDelta) < (minAdvantage or 0) then
        return nil, bestDelta, secondDelta, count
    end

    return bestCandidate, bestDelta, secondDelta, count
end
local function intersectRouteSets(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil, 0 end

    local result = {}
    local count = 0
    for routeID in pairs(a) do
        if b[routeID] then
            result[routeID] = true
            count = count + 1
        end
    end
    return result, count
end

local function routeSetFromCandidates(byRoute)
    local routeSet = {}
    for routeID in pairs(byRoute or {}) do
        routeSet[routeID] = true
    end
    return routeSet
end

local function rememberRouteCandidates(key, routeSet, cells, point, pointCount, observedAngle, strongAngleRouteID, strongAngleTicks)
    routeCandidateStateByKey[key] = {
        routeSet = routeSet,
        routeCount = countRoutes(routeSet),
        pointCount = pointCount or 1,
        roughKey = cells and cells.roughKey or nil,
        fineKey = cells and cells.fineKey or nil,
        point = point,
        observedAngle = observedAngle,
        strongAngleRouteID = strongAngleRouteID,
        strongAngleTicks = strongAngleTicks,
        updatedAt = nowSeconds(),
    }
end

local function selectCandidate(key, candidates, cells, point)
    local byRoute, _, routeCount, reason = hydrateCandidates(candidates)
    if not byRoute then return nil, reason, routeCount end

    if routeCount == 1 then
        routeCandidateStateByKey[key] = nil
        local routeID = firstRouteID(byRoute)
        return byRoute[routeID], "single_candidate", routeCount, 1, nil
    end

    local currentRouteSet = routeSetFromCandidates(byRoute)
    local previous = routeCandidateStateByKey[key]
    local observedAngle = previous and calculateMovementAngle(previous.point, point) or nil
    local pointCount = previous and ((previous.pointCount or 1) + 1) or 1

    if previous and previous.routeSet then
        local candidateRouteSet = currentRouteSet
        local candidateRouteCount = routeCount
        local pendingReason = "ambiguous_candidates"

        if previous.fineKey ~= cells.fineKey or previous.roughKey ~= cells.roughKey then
            local intersection, intersectionCount = intersectRouteSets(previous.routeSet, currentRouteSet)
            if intersectionCount == 1 then
                routeCandidateStateByKey[key] = nil
                return selectFromRouteSet(intersection, byRoute), "cell_intersection", 1, pointCount, observedAngle
            elseif intersectionCount > 1 then
                candidateRouteSet = intersection
                candidateRouteCount = intersectionCount
                pendingReason = "ambiguous_intersection"
            else
                candidateRouteSet = currentRouteSet
                candidateRouteCount = routeCount
                pointCount = 1
                pendingReason = "intersection_reset"
            end
        else
            candidateRouteSet = previous.routeSet
            candidateRouteCount = previous.routeCount or routeCount
            pendingReason = "same_cell_ambiguous"
        end

        if observedAngle then
            local filtered, filteredCount = filterRouteSetByAngle(
                candidateRouteSet,
                byRoute,
                observedAngle,
                ANGLE_TOLERANCE_DEGREES
            )
            local angleReason = "angle_match"
            if filteredCount == 0 then
                filtered, filteredCount = filterRouteSetByAngle(
                    candidateRouteSet,
                    byRoute,
                    observedAngle,
                    ANGLE_FALLBACK_TOLERANCE_DEGREES
                )
                angleReason = "angle_fallback_match"
            end

            if filteredCount == 1 then
                routeCandidateStateByKey[key] = nil
                return selectFromRouteSet(filtered, byRoute), angleReason, 1, pointCount, observedAngle
            elseif filteredCount > 1 then
                local closest, bestDelta, secondDelta = selectClosestByAngle(
                    filtered,
                    byRoute,
                    observedAngle,
                    ANGLE_SELECTION_MIN_ADVANTAGE_DEGREES
                )
                if closest then
                    routeCandidateStateByKey[key] = nil
                    return closest, angleReason .. "_closest", filteredCount, pointCount, observedAngle
                end

                local strongClosest, strongBestDelta, strongSecondDelta = selectClosestByAngle(
                    filtered,
                    byRoute,
                    observedAngle,
                    0
                )
                local strongRouteID = strongClosest and strongClosest.routeID or nil
                local strongTicks = 0
                if strongRouteID
                    and strongBestDelta
                    and strongSecondDelta
                    and strongBestDelta < STRONG_ANGLE_BEST_MAX_DEGREES
                    and strongSecondDelta > STRONG_ANGLE_SECOND_MIN_DEGREES
                then
                    strongTicks = previous and previous.strongAngleRouteID == strongRouteID and ((previous.strongAngleTicks or 0) + 1) or 1
                    if strongTicks >= STRONG_ANGLE_STABLE_TICKS then
                        routeCandidateStateByKey[key] = nil
                        return strongClosest,
                            "angle_strong_tiebreak"
                                .. ":best=" .. formatAngle(strongBestDelta)
                                .. ":second=" .. formatAngle(strongSecondDelta)
                                .. ":stable=" .. tostring(strongTicks),
                            filteredCount,
                            pointCount,
                            observedAngle
                    end
                else
                    strongRouteID = nil
                end

                rememberRouteCandidates(key, filtered, cells, point, pointCount, observedAngle, strongRouteID, strongTicks)
                return nil,
                    "ambiguous_angle_closest"
                        .. ":best=" .. formatAngle(bestDelta)
                        .. ":second=" .. formatAngle(secondDelta)
                        .. (strongRouteID and (":strong=" .. tostring(strongRouteID) .. ":stable=" .. tostring(strongTicks)) or ""),
                    filteredCount,
                    pointCount,
                    observedAngle
            end
        end

        if candidateRouteCount == 1 then
            routeCandidateStateByKey[key] = nil
            return selectFromRouteSet(candidateRouteSet, byRoute), "cell_intersection", 1, pointCount, observedAngle
        end

        rememberRouteCandidates(key, candidateRouteSet, cells, point, pointCount, observedAngle)
        return nil, pendingReason, candidateRouteCount, pointCount, observedAngle
    end

    rememberRouteCandidates(key, currentRouteSet, cells, point, 1, nil)
    return nil, "ambiguous_candidates", routeCount, 1, nil
end

local function dropDistance(a, b)
    if not a or not b or not a.dropX or not a.dropY or not b.dropX or not b.dropY then return 0 end
    local dx = a.dropX - b.dropX
    local dy = a.dropY - b.dropY
    return math.sqrt((dx * dx) + (dy * dy))
end

local function shouldAcceptPrediction(current, candidate)
    if not current then return true, "initial" end
    if not candidate then return false, "missing_candidate" end

    if dropDistance(current, candidate) > DROP_CORRECTION_DISTANCE then
        if tostring(current.routeID or "") ~= tostring(candidate.routeID or "") then
            local currentDelta = angleDelta(candidate.observedAngle, current.angle)
            local candidateDelta = angleDelta(candidate.observedAngle, candidate.angle)
            if currentDelta and candidateDelta then
                if candidateDelta + ANGLE_SWITCH_MIN_ADVANTAGE_DEGREES < currentDelta then
                    return true, "drop_location_changed_angle_better"
                end
                return false, "drop_location_changed_angle_not_better"
            end
        end

        return true, "drop_location_changed"
    end

    return false, "stable_prediction"
end

local function logPendingOnce(key, reason, zoneID, shardID, cells, candidateCount, pointCount, observedAngle)
    local marker = tostring(reason)
        .. ":" .. tostring(cells and cells.roughKey)
        .. ":" .. tostring(cells and cells.fineKey)
        .. ":" .. tostring(candidateCount or 0)
        .. ":" .. tostring(pointCount or 0)
        .. ":" .. tostring(observedAngle or "nil")
    if pendingLogByKey[key] == marker then return end
    pendingLogByKey[key] = marker

    debugLog("pending zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " rough=" .. tostring(cells and cells.roughKey)
        .. " fine=" .. tostring(cells and cells.fineKey)
        .. " candidates=" .. tostring(candidateCount or 0)
        .. " points=" .. tostring(pointCount or 0)
        .. " angle=" .. formatAngle(observedAngle)
        .. " reason=" .. tostring(reason))
end

function prediction:getCellKeys(x, y)
    x = toNumber(x)
    y = toNumber(y)
    if not x or not y or x <= 0 or y <= 0 then return nil end
    return buildCellKeys(x, y)
end

function prediction:clear(zoneID, shardID, reason)
    local key = crateKeys and crateKeys:make(zoneID, shardID) or nil
    if not key then return false end

    local previous = activeByKey[key]
    local hadPending = pendingLogByKey[key] ~= nil or routeCandidateStateByKey[key] ~= nil
    if not previous and not hadPending then return false end

    activeByKey[key] = nil
    pendingLogByKey[key] = nil
    routeCandidateStateByKey[key] = nil

    debugLog("cleared zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " reason=" .. tostring(reason))

    if previous then
        publish(DOMAIN_EVENT and DOMAIN_EVENT.PREDICTION_CLEARED, {
            zoneID = zoneID,
            shardID = shardID,
            reason = reason,
            previous = previous,
        })
    end

    return true
end

function prediction:clearAll(reason)
    local hadState = false
    for key, item in pairs(activeByKey) do
        hadState = true
        activeByKey[key] = nil
        if item then
            publish(DOMAIN_EVENT and DOMAIN_EVENT.PREDICTION_CLEARED, {
                zoneID = item.zoneID,
                shardID = item.shardID,
                reason = reason,
                previous = item,
            })
        end
    end
    if next(pendingLogByKey) then hadState = true end
    if next(routeCandidateStateByKey) then hadState = true end
    pendingLogByKey = {}
    routeCandidateStateByKey = {}
    if hadState then
        debugLog("cleared all reason=" .. tostring(reason))
    end
end

function prediction:onPlaneSighting(zoneID, sighting, trigger, planeConfirmed)
    if not isEnabled() then return false end
    if type(sighting) ~= "table" or sighting.vignetteType ~= VIGNETTE_TYPE.PLANE_FLYING then return false end
    if not sighting.hasPosition or not sighting.shardID then return false end
    if not isFlyingLifecycle(zoneID, sighting.shardID, planeConfirmed) then return false end

    local key = crateKeys and crateKeys:make(zoneID, sighting.shardID) or nil
    if not key then return false end
    clearOtherPredictionsForZone(zoneID, sighting.shardID, "shard_changed")

    local cells = self:getCellKeys(sighting.x, sighting.y)
    if not cells then return false end

    local candidates = getCellCandidates(zoneID, cells.roughKey, cells.fineKey)
    local point = {
        x = sighting.x,
        y = sighting.y,
    }
    local selected, reason, candidateCount, pointCount, observedAngle = selectCandidate(key, candidates, cells, point)
    if not selected then
        logPendingOnce(key, reason, zoneID, sighting.shardID, cells, candidateCount, pointCount, observedAngle)
        return false
    end

    local currentPrediction = activeByKey[key]
    if not observedAngle and currentPrediction then
        observedAngle = calculateMovementAngle({
            x = currentPrediction.planeX,
            y = currentPrediction.planeY,
        }, point)
    end

    local payload = {
        zoneID = zoneID,
        shardID = sighting.shardID,
        trigger = trigger,
        source = "route_cell_index",
        predictedAt = nowSeconds(),
        lifecycleStartedAt = (getLifecycle(zoneID, sighting.shardID) or {}).lifecycleStartedAt,
        planeX = sighting.x,
        planeY = sighting.y,
        roughKey = cells.roughKey,
        fineKey = cells.fineKey,
        routeID = selected.routeID,
        dropClusterID = selected.dropClusterID,
        dropX = selected.dropX,
        dropY = selected.dropY,
        secondsToDrop = selected.secondsToDrop,
        secondsToLand = selected.secondsToLand,
        angle = selected.angle,
        observedAngle = observedAngle,
        samples = selected.samples,
        confidence = selected.confidence,
        confidenceLabel = getConfidenceLabel(selected, candidateCount),
        candidateCount = candidateCount or 1,
        routePointCount = pointCount or 1,
        selectionReason = reason,
    }

    local accept, correctionReason = shouldAcceptPrediction(currentPrediction, payload)
    if not accept then
        if correctionReason ~= "stable_prediction" then
            debugLog("ignored zone=" .. tostring(zoneID)
                .. " shard=" .. tostring(sighting.shardID)
                .. " route=" .. tostring(payload.routeID)
                .. " currentRoute=" .. tostring(currentPrediction and currentPrediction.routeID)
                .. " observedAngle=" .. formatAngle(payload.observedAngle)
                .. " routeAngle=" .. formatAngle(payload.angle)
                .. " currentRouteAngle=" .. formatAngle(currentPrediction and currentPrediction.angle)
                .. " reason=" .. tostring(correctionReason))
        end
        return false
    end

    payload.correctionReason = correctionReason
    activeByKey[key] = payload
    pendingLogByKey[key] = nil

    debugLog("drop zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(sighting.shardID)
        .. " route=" .. tostring(payload.routeID)
        .. " cell=" .. tostring(payload.roughKey) .. "/" .. tostring(payload.fineKey)
        .. " drop=" .. formatCoord(payload.dropX) .. "/" .. formatCoord(payload.dropY)
        .. " eta=" .. formatEta(payload.secondsToDrop)
        .. " confidence=" .. tostring(payload.confidenceLabel)
        .. " candidates=" .. tostring(payload.candidateCount)
        .. " points=" .. tostring(payload.routePointCount)
        .. " observedAngle=" .. formatAngle(payload.observedAngle)
        .. " routeAngle=" .. formatAngle(payload.angle)
        .. " reason=" .. tostring(correctionReason))

    publish(DOMAIN_EVENT and DOMAIN_EVENT.PREDICTION_UPDATED, payload)
    return true
end

function prediction:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    if payload.state == CRATE_STATE.DETECTED then
        self:clear(payload.zoneID, payload.shardID, "lifecycle_started")
    elseif isTerminalState(payload.state) then
        self:clear(payload.zoneID, payload.shardID, tostring(payload.state))
    end
end

function prediction:onZoneChanged()
    self:clearAll("zone_changed")
end

function prediction:onPlayerEnteringWorld()
    self:clearAll("player_entering_world")
end

function prediction:getActive(zoneID, shardID)
    local key = crateKeys and crateKeys:make(zoneID, shardID) or nil
    return key and activeByKey[key] or nil
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.CRATE_STATE_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, prediction, "onCrateStateChanged")
    end
end
