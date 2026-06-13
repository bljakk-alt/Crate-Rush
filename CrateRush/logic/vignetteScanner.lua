-- CrateRush
-- logic/vignetteScanner.lua - Raw vignette reading and crate vignette classification.

local vignetteScanner = {}
CrateRush.vignetteScanner = vignetteScanner

local VIGNETTE_TYPE = CrateRush.VIGNETTE_TYPE
local seenGUIDs = {}
local seenGUIDCount = 0

local SEEN_GUID_MAX_AGE_SECONDS = CrateRush.TIMING.VIGNETTE_SEEN_CACHE_MAX_AGE_SECONDS
local SEEN_GUID_MAX_ENTRIES = CrateRush.TIMING.VIGNETTE_SEEN_CACHE_MAX_ENTRIES

local function nowSeconds()
    return CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or 0
end

local function pruneSeenGUIDs(now)
    now = now or nowSeconds()

    local expired = {}
    for guid, entry in pairs(seenGUIDs) do
        local seenAt = entry and entry.seenAt or 0
        if now - seenAt > SEEN_GUID_MAX_AGE_SECONDS then
            expired[#expired + 1] = guid
        end
    end

    for _, guid in ipairs(expired) do
        if seenGUIDs[guid] then
            seenGUIDs[guid] = nil
            seenGUIDCount = math.max(0, seenGUIDCount - 1)
        end
    end

    while seenGUIDCount > SEEN_GUID_MAX_ENTRIES do
        local oldestGUID = nil
        local oldestSeenAt = nil
        for guid, entry in pairs(seenGUIDs) do
            local seenAt = entry and entry.seenAt or 0
            if not oldestSeenAt or seenAt < oldestSeenAt then
                oldestGUID = guid
                oldestSeenAt = seenAt
            end
        end

        if not oldestGUID then return end
        seenGUIDs[oldestGUID] = nil
        seenGUIDCount = math.max(0, seenGUIDCount - 1)
    end
end

local function extractShardFromGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    return guid:match("^Vignette%-%d+%-%d+%-%d+%-(%d+)%-")
end

local function getVignetteContextKey(guid)
    if not guid or type(guid) ~= "string" then return nil end
    return guid:match("^(Vignette%-%d+%-%d+%-%d+%-%d+)%-")
end

function vignetteScanner:getVignettes()
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes then return nil end

    local ok, vignettes = pcall(C_VignetteInfo.GetVignettes)
    if ok then return vignettes end
    return nil
end

function vignetteScanner:extractShardFromGUID(guid)
    return extractShardFromGUID(guid)
end

function vignetteScanner:markSeen(guid)
    if not guid then return false end
    pruneSeenGUIDs()
    if seenGUIDs[guid] then return false end
    seenGUIDs[guid] = { seenAt = nowSeconds() }
    seenGUIDCount = seenGUIDCount + 1
    return true
end

function vignetteScanner:wasSeen(guid)
    pruneSeenGUIDs()
    return guid and seenGUIDs[guid] or false
end

function vignetteScanner:getVignetteInfo(vignetteGUID)
    if not vignetteGUID then return nil end
    if not C_VignetteInfo or not C_VignetteInfo.GetVignetteInfo then return nil end

    local ok, info = pcall(C_VignetteInfo.GetVignetteInfo, vignetteGUID)
    if ok then return info end
    return nil
end

function vignetteScanner:getVignettePosition(vignetteGUID, mapID)
    if not vignetteGUID or not mapID then return nil end
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettePosition then return nil end

    local ok, position = pcall(C_VignetteInfo.GetVignettePosition, vignetteGUID, mapID)
    if ok then return position end
    return nil
end

function vignetteScanner:getVignetteType(vignetteID)
    local mappedType = vignetteID and CrateRush.VIGNETTE_IDS and CrateRush.VIGNETTE_IDS[vignetteID] or nil
    return mappedType or VIGNETTE_TYPE.UNKNOWN, mappedType
end

function vignetteScanner:isKnownCrateType(vignetteType)
    return vignetteType ~= VIGNETTE_TYPE.UNKNOWN
        and vignetteType ~= VIGNETTE_TYPE.OTHER
end

function vignetteScanner:read(vignetteGUID, mapID, rawMapID)
    local info = self:getVignetteInfo(vignetteGUID)
    if not info then return nil end

    local vignetteType, mappedVignetteType = self:getVignetteType(info.vignetteID)
    local positionMapID = rawMapID or mapID
    local position = self:getVignettePosition(vignetteGUID, positionMapID)
    local x = position and position.x or 0
    local y = position and position.y or 0

    return {
        guid                   = vignetteGUID,
        info                   = info,
        vignetteID             = info.vignetteID,
        name                   = info.name,
        vignetteType           = vignetteType,
        mappedVignetteType     = mappedVignetteType,
        isKnownCrateVignette   = self:isKnownCrateType(vignetteType),
        position               = position,
        x                      = x,
        y                      = y,
        hasPosition            = position and x ~= 0 and y ~= 0,
        shardID                = extractShardFromGUID(vignetteGUID),
        contextKey             = getVignetteContextKey(vignetteGUID),
    }
end
