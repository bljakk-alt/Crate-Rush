-- CrateRush
-- logic/crateHandler/map.lua — Map markers for crate locations.
-- Uses native WoW map API. TomTom integration is optional and gracefully degraded.

local map = {}
CrateRush.map = map

local function normalizeMapCoordinate(value)
    value = tonumber(value)
    if not value then return nil end

    -- Blizzard map coordinates are normalized screen/map coordinates:
    -- 0,0 top-left and 1,1 bottom-right. Accept percentages defensively.
    if value > 1 then value = value / 100 end
    if value < 0 or value > 1 then return nil end
    return value
end

local function getMapPinLabel()
    return _G.MAP_PIN_LOCATION or _G.MAP_PIN or "Map Pin Location"
end

local function setUserWaypointAndGetHyperlink(zoneID, x, y)
    if not C_Map or not C_Map.SetUserWaypoint or not C_Map.GetUserWaypointHyperlink then return nil end
    if not UiMapPoint or not UiMapPoint.CreateFromCoordinates then return nil end

    local mapID = tonumber(zoneID)
    if not mapID then return nil end

    local okPoint, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not okPoint or not point then return nil end

    local okSet = pcall(C_Map.SetUserWaypoint, point)
    if not okSet then return nil end

    local okLink, link = pcall(C_Map.GetUserWaypointHyperlink)

    if okLink and type(link) == "string" and link ~= "" then
        return link
    end
    return nil
end

local function formatFallbackWaypointLink(zoneID, x, y)
    local mapID = tonumber(zoneID)
    if not mapID then return nil end

    local linkX = math.floor((x * 10000) + 0.5)
    local linkY = math.floor((y * 10000) + 0.5)
    return string.format(
        "|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r",
        mapID,
        linkX,
        linkY,
        getMapPinLabel()
    )
end

function map:setWaypointAndCreateLink(zoneID, x, y)
    if not zoneID then return nil end

    local mapX = normalizeMapCoordinate(x)
    local mapY = normalizeMapCoordinate(y)
    if not mapX or not mapY then return nil end

    -- Side effect: keep the waypoint active so local chat output also marks the player's map.
    return setUserWaypointAndGetHyperlink(zoneID, mapX, mapY)
        or formatFallbackWaypointLink(zoneID, mapX, mapY)
end

function map:addPin(zoneID, x, y, label)
    -- Add a map pin via native WoW map API.
end

function map:removePin(zoneID, x, y)
    -- Remove a specific map pin.
end

function map:clearZone(zoneID)
    -- Remove all CrateRush pins from a zone.
end

function map:addTomTomWaypoint(zoneID, x, y, label)
    -- Add a TomTom waypoint if TomTom is installed. Silently skips if not.
end
