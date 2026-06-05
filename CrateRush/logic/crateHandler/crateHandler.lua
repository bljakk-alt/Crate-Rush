-- CrateRush
-- logic/crateHandler/crateHandler.lua - WoW event orchestration for crate-related game signals.

local crateHandler = {}
CrateRush.crateHandler = crateHandler

local CRATE_STATE = CrateRush.CRATE_STATE
local CRATE_SOURCE = CrateRush.CRATE_SOURCE
local SCAN_TRIGGER = CrateRush.SCAN_TRIGGER
local VIGNETTE_TYPE = CrateRush.VIGNETTE_TYPE

local zoneResolver = CrateRush.zoneResolver
local vignetteScanner = CrateRush.vignetteScanner
local shardService = CrateRush.shardService
local crateLifecycle = CrateRush.crateLifecycle
local transitionGuard = CrateRush.transitionGuard
local monsterSayService = CrateRush.monsterSayService

local scanVignettes
local scanSequence = 0

local function zoneLog(msg)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ZONECHECK | " .. tostring(msg))
    end
end

local function sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function logKnownVignette(sighting, mapID, rawMapID, trigger)
    if not sighting or not sighting.isKnownCrateVignette then return end
    if sighting.vignetteType == VIGNETTE_TYPE.PLANE_FLYING and not sighting.hasPosition then return end

    CrateRush.debug:log(string.format(
        "|cffffffff[%s] VIGNETTE | type=%s | vignetteID=%d | name=%s | x=%.4f y=%.4f | mapID=%s rawMapID=%s | guid=%s|r",
        trigger,
        tostring(sighting.vignetteType),
        tonumber(sighting.vignetteID) or 0,
        tostring(sighting.name),
        sighting.x or 0,
        sighting.y or 0,
        tostring(mapID),
        tostring(rawMapID or mapID),
        tostring(sighting.guid)
    ))
end

local function dumpFirstSeenInfo(sighting)
    if not sighting or not sighting.guid then return false end

    local firstSeenGUID = vignetteScanner:markSeen(sighting.guid)
    if firstSeenGUID and sighting.info then
        for k, v in pairs(sighting.info) do
            CrateRush.debug:log("  DUMP[" .. tostring(sighting.guid) .. "] " .. tostring(k) .. "=" .. tostring(v))
        end
    end

    return firstSeenGUID
end

local function processPlaneSighting(sighting, mapID)
    if not sighting or sighting.vignetteType ~= VIGNETTE_TYPE.PLANE_FLYING then return end
    if not sighting.hasPosition then return end
    if not shardService:isZoneConfirmed(mapID) then return end

    local planeConfirmed = crateLifecycle:onPlaneSeen(mapID, sighting.shardID, sighting.guid)
    if planeConfirmed then
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.FLYING)
    end
end

local function processObjectSighting(sighting, mapID, trigger)
    local firstSeenGUID = dumpFirstSeenInfo(sighting)
    local processCrateObjectState = crateLifecycle:shouldProcessObjectState(
        sighting.vignetteType,
        firstSeenGUID,
        mapID,
        sighting.shardID
    )

    if processCrateObjectState and shardService:isPreviousZoneShardPending(mapID, sighting.shardID) then
        zoneLog("CRATE_OBJECT_DEFER_PREVIOUS_SHARD zone=" .. tostring(mapID)
            .. " previousZone=" .. tostring(shardService:getPreviousZoneID())
            .. " shard=" .. tostring(sighting.shardID)
            .. " type=" .. tostring(sighting.vignetteType)
            .. " trigger=" .. tostring(trigger)
            .. " reason=awaiting_current_zone_confirmation")
        processCrateObjectState = false
    end

    if not processCrateObjectState then return end

    if not firstSeenGUID then
        zoneLog("CRATE_OBJECT_REPROCESS zone=" .. tostring(mapID)
            .. " shard=" .. tostring(sighting.shardID)
            .. " type=" .. tostring(sighting.vignetteType)
            .. " reason=missing_runtime_state")
    end

    if sighting.vignetteType == VIGNETTE_TYPE.CRATE_DROPPING then
        crateLifecycle:transition(mapID, sighting.shardID, CRATE_STATE.DROPPING, sighting.position and sighting.position.x, sighting.position and sighting.position.y, CRATE_SOURCE.DROPPING)
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.DROPPING)
    elseif sighting.vignetteType == VIGNETTE_TYPE.CRATE_LANDED then
        crateLifecycle:transition(mapID, sighting.shardID, CRATE_STATE.LANDED, sighting.position and sighting.position.x, sighting.position and sighting.position.y, CRATE_SOURCE.LANDED)
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.LANDED)
    elseif sighting.vignetteType == VIGNETTE_TYPE.CRATE_CLAIMED_BY_ALLIANCE then
        crateLifecycle:transition(mapID, sighting.shardID, CRATE_STATE.CLAIMED_BY_ALLIANCE, nil, nil, CRATE_SOURCE.CLAIMED_BY_ALLIANCE)
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.CLAIMED_BY_ALLIANCE)
    elseif sighting.vignetteType == VIGNETTE_TYPE.CRATE_CLAIMED_BY_HORDE then
        crateLifecycle:transition(mapID, sighting.shardID, CRATE_STATE.CLAIMED_BY_HORDE, nil, nil, CRATE_SOURCE.CLAIMED_BY_HORDE)
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.CLAIMED_BY_HORDE)
    end
end

local function processVignette(sighting, mapID, trigger, rawMapID, scanID, confirmedShardAtScanStart)
    if not sighting or not sighting.guid or not sighting.info then return end

    local canUseForZoneShard = shardService:canUseSightingForZoneShard(mapID, sighting)
    if sighting.isKnownCrateVignette and mapID and canUseForZoneShard then
        if not transitionGuard:claimSighting(sighting, mapID, trigger, zoneLog) then
            return
        end
    end

    logKnownVignette(sighting, mapID, rawMapID, trigger)

    if shardService:shouldIgnoreDuringSettle(mapID, sighting, trigger) then
        return
    end

    -- Any valid current-map vignette can identify the live shard for the header.
    -- Only known crate vignettes are allowed to drive crate state/timers below.
    if canUseForZoneShard then
        shardService:processShardEvidence(mapID, sighting.shardID, sighting.vignetteType, trigger, scanID)
    end

    if not sighting.isKnownCrateVignette then
        return
    end

    if mapID and sighting.shardID and not sameShard(confirmedShardAtScanStart, sighting.shardID) then
        local confirmedShardNow = shardService:getConfirmedShard(mapID)
        zoneLog("LIFECYCLE_DEFER_UNCONFIRMED_SHARD zone=" .. tostring(mapID)
            .. " shard=" .. tostring(sighting.shardID)
            .. " confirmedAtScanStart=" .. tostring(confirmedShardAtScanStart)
            .. " confirmedNow=" .. tostring(confirmedShardNow)
            .. " trigger=" .. tostring(trigger)
            .. " vignetteID=" .. tostring(sighting.vignetteID)
            .. " reason=shard_not_confirmed_at_scan_start")
        return
    end

    if sighting.vignetteType == VIGNETTE_TYPE.PLANE_FLYING and not sighting.hasPosition then
        return
    end

    processPlaneSighting(sighting, mapID)

    if not mapID or not sighting.shardID then
        zoneLog("LIFECYCLE_DEFER trigger=" .. tostring(trigger)
            .. " vignetteID=" .. tostring(sighting.vignetteID)
            .. " type=" .. tostring(sighting.vignetteType)
            .. " mapID=" .. tostring(mapID)
            .. " shard=" .. tostring(sighting.shardID)
            .. " guid=" .. tostring(sighting.guid))
        return
    end

    processObjectSighting(sighting, mapID, trigger)
end

scanVignettes = function(trigger)
    if not trigger then return end

    local vignettes = vignetteScanner:getVignettes()
    if not vignettes then return end

    scanSequence = scanSequence + 1
    local scanID = scanSequence

    local rawMapID = zoneResolver:getPlayerMapID()
    local mapID = zoneResolver:resolveCrateZoneID(rawMapID)
    local confirmedShardAtScanStart = mapID and shardService:getConfirmedShardAtScanStart(mapID) or nil

    local isRescanTrigger = trigger == SCAN_TRIGGER.ZONE_SHARD_GRACE
        or trigger == SCAN_TRIGGER.ZONE_SETTLED
        or trigger == SCAN_TRIGGER.ZONE_POLL

    if isRescanTrigger then
        zoneLog("RESCAN_RESULT trigger=" .. tostring(trigger)
            .. " rawMapID=" .. tostring(rawMapID)
            .. " mapID=" .. tostring(mapID)
            .. " count=" .. tostring(#vignettes))
    end

    for _, vignetteGUID in ipairs(vignettes) do
        local sighting = vignetteScanner:read(vignetteGUID, mapID, rawMapID)
        if sighting then
            if isRescanTrigger and sighting.mappedVignetteType then
                zoneLog("RESCAN_VIGNETTE guid=" .. tostring(vignetteGUID)
                    .. " vignetteID=" .. tostring(sighting.vignetteID)
                    .. " type=" .. tostring(sighting.vignetteType)
                    .. " shard=" .. tostring(sighting.shardID))
            end

            processVignette(sighting, mapID, trigger, rawMapID, scanID, confirmedShardAtScanStart)
        end
    end
end

shardService:setScanFunction(scanVignettes)

function crateHandler:onPlayerEnteringWorld(isInitialLogin, isReloadingUi)
    CrateRush.debug:log("PLAYER_ENTERING_WORLD | initialLogin=" .. tostring(isInitialLogin) .. " reload=" .. tostring(isReloadingUi))
    local mapID = zoneResolver:getPlayerMapID()
    if mapID then
        local crateZoneID = zoneResolver:resolveCrateZoneID(mapID)
        if crateZoneID then
            shardService:beginZone(crateZoneID)
        else
            zoneLog("ENTER_WORLD_SKIP rawZone=" .. tostring(mapID) .. " notCrateZone")
        end
    end
end

function crateHandler:onZoneChanged()
    local zoneContext = zoneResolver:getPlayerZoneContext()
    local mapID = zoneContext.rawMapID
    local crateZoneID = zoneContext.crateZoneID
    local crateZoneName = zoneContext.crateZoneName or "n/a"
    CrateRush.debug:log("ZONE_CHANGED_NEW_AREA | mapID=" .. tostring(mapID)
        .. " zone=" .. tostring(zoneContext.rawZoneName)
        .. " crateZoneID=" .. tostring(crateZoneID)
        .. " crateZone=" .. tostring(crateZoneName))
    if crateZoneID then
        shardService:beginZone(crateZoneID)
    else
        zoneLog("ZONE_CHANGE_SKIP rawZone=" .. tostring(mapID) .. " notCrateZone")
    end
end

function crateHandler:onVignettesUpdated()
    scanVignettes(SCAN_TRIGGER.VIGNETTES_UPDATED)
end

function crateHandler:onMonsterSay(text, npcName)
    if not text or not npcName then return end
    CrateRush.debug:log("MONSTER_SAY | npc=" .. tostring(npcName) .. " text=" .. tostring(text))

    if not monsterSayService:isCrateAnnouncement(text, npcName) then return end

    CrateRush.debug:log("MONSTER_SAY MATCHED | npc=" .. tostring(npcName))

    local mapID = zoneResolver:getPlayerMapID()
    if not mapID then return end

    local crateZoneID = zoneResolver:resolveCrateZoneID(mapID)
    if not crateZoneID then
        CrateRush.debug:log("MONSTER_SAY MATCHED | ignored outside crate zone rawZone=" .. tostring(mapID))
        return
    end

    local confirmedShardID = shardService:getConfirmedShard(crateZoneID)
    if confirmedShardID then
        crateLifecycle:transition(crateZoneID, confirmedShardID, CRATE_STATE.DETECTED, nil, nil, CRATE_SOURCE.MONSTER_SAY)
        shardService:acceptCrateEventShard(crateZoneID, confirmedShardID, CRATE_SOURCE.MONSTER_SAY)
    else
        CrateRush.debug:log("MONSTER_SAY MATCHED | waiting for confirmed shard before FLYING transition")
    end

    scanVignettes(SCAN_TRIGGER.MONSTER_SAY)
end

function crateHandler:onGroupRosterUpdate()
    local inRaid = IsInRaid() or false
    local inGroup = IsInGroup() or false
    local members = GetNumGroupMembers() or 0
    CrateRush.debug:log("GROUP_ROSTER_UPDATE | inRaid=" .. tostring(inRaid) .. " inGroup=" .. tostring(inGroup) .. " members=" .. tostring(members))
    scanVignettes(SCAN_TRIGGER.GROUP_ROSTER_UPDATE)
end
