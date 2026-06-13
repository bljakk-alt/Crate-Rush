-- CrateRush
-- logic/routeData.lua - Cheap route-data queries shared by lifecycle and prediction.

local routeData = {}
CrateRush.routeData = routeData

local function toNumber(value)
    return value and tonumber(value) or nil
end

function routeData:getPositionToleranceDegrees()
    return tonumber(CrateRush.TIMING and CrateRush.TIMING.PLANE_POSITION_TOLERANCE_DEGREES) or 0.05
end

function routeData:mapDistanceDegrees(x1, y1, x2, y2)
    x1 = toNumber(x1)
    y1 = toNumber(y1)
    x2 = toNumber(x2)
    y2 = toNumber(y2)
    if not x1 or not y1 or not x2 or not y2 then return nil end

    local dx = (x1 - x2) * 100
    local dy = (y1 - y2) * 100
    return math.sqrt((dx * dx) + (dy * dy))
end

function routeData:isNearPoint(x, y, point, tolerance)
    if not point then return false, nil end
    local distance = self:mapDistanceDegrees(x, y, point.x, point.y)
    if not distance then return false, nil end
    return distance <= (tolerance or self:getPositionToleranceDegrees()), distance
end

function routeData:getZoneAnchor(zoneID)
    local anchors = CrateRushZoneAnchors or CrateRush.ZONE_ANCHORS or {}
    return anchors[tonumber(zoneID) or zoneID]
end

function routeData:getCellKeys(x, y)
    x = toNumber(x)
    y = toNumber(y)
    if not x or not y or x <= 0 or y <= 0 then return nil end

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

function routeData:getCellCandidates(zoneID, roughKey, fineKey)
    local index = CrateRushRouteCellIndex or CrateRush.PREDICTION_ROUTE_CELL_INDEX or {}
    return index[zoneID]
        and index[zoneID][roughKey]
        and index[zoneID][roughKey][fineKey]
        or nil
end

function routeData:isNearKnownDrop(zoneID, x, y, tolerance)
    local clustersByZone = CrateRushDropClusters or CrateRush.PREDICTION_DROP_CLUSTERS or {}
    local clusters = clustersByZone[zoneID]
    if type(clusters) ~= "table" then return false, nil, nil end

    tolerance = tolerance or self:getPositionToleranceDegrees()
    local closestID, closestDistance = nil, nil
    for clusterID, cluster in pairs(clusters) do
        if cluster and cluster.x and cluster.y then
            local distance = self:mapDistanceDegrees(x, y, cluster.x, cluster.y)
            if distance and (not closestDistance or distance < closestDistance) then
                closestID = clusterID
                closestDistance = distance
            end
            if distance and distance <= tolerance then
                return true, clusterID, distance
            end
        end
    end

    return false, closestID, closestDistance
end

local function countUniqueRoutes(candidates)
    if type(candidates) ~= "table" then return 0 end

    local seen = {}
    local count = 0
    for _, candidate in ipairs(candidates) do
        local routeID = candidate and candidate.routeID
        if routeID and not seen[routeID] then
            seen[routeID] = true
            count = count + 1
        end
    end
    return count
end

function routeData:classifyPlanePoint(zoneID, x, y)
    local tolerance = self:getPositionToleranceDegrees()
    local anchor = self:getZoneAnchor(zoneID)
    local nearAnchor, anchorDistance = self:isNearPoint(x, y, anchor, tolerance)
    local nearDrop, dropID, dropDistance = self:isNearKnownDrop(zoneID, x, y, tolerance)
    local cells = self:getCellKeys(x, y)
    local candidates = cells and self:getCellCandidates(zoneID, cells.roughKey, cells.fineKey) or nil
    local routeCount = countUniqueRoutes(candidates)

    return {
        tolerance = tolerance,
        nearAnchor = nearAnchor,
        anchorDistance = anchorDistance,
        nearKnownDrop = nearDrop,
        nearestDropID = dropID,
        nearestDropDistance = dropDistance,
        cells = cells,
        routeCount = routeCount,
        knownEnRoute = routeCount == 1 and not nearDrop,
    }
end
