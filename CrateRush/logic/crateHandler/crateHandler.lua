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
local crateCycleAnchorService = CrateRush.crateCycleAnchorService
local prediction = CrateRush.prediction
local crateKeys = CrateRush.crateKeys

local scanVignettes
local scanSequence = 0
local lastGroupRosterLogAt = nil
local lastGroupRosterLogKey = nil

local function zoneLog(msg)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.logDebug("ZONECHECK | " .. tostring(msg))
    end
end

local function logKnownVignette(sighting, mapID, rawMapID, trigger)
    if not sighting or not sighting.isKnownCrateVignette then return end
    if sighting.vignetteType == VIGNETTE_TYPE.PLANE_FLYING and not sighting.hasPosition then return end

    CrateRush.logDebug(string.format(
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
            CrateRush.logDebug("  DUMP[" .. tostring(sighting.guid) .. "] " .. tostring(k) .. "=" .. tostring(v))
        end
    end

    return firstSeenGUID
end

local function recordScanObservation(scanContext, mapID, sighting)
    if not scanContext or not scanContext.observedByKey then return end
    if not mapID or not sighting or not sighting.shardID then return end

    local key = crateKeys:make(mapID, sighting.shardID)
    if not key then return end

    local entry = scanContext.observedByKey[key]
    if not entry then
        entry = {
            zoneID = mapID,
            shardID = sighting.shardID,
        }
        scanContext.observedByKey[key] = entry
    end

    entry.seenAny = true

    if sighting.vignetteType == VIGNETTE_TYPE.PLANE_FLYING then
        entry.planeSeen = true
    elseif sighting.vignetteType == VIGNETTE_TYPE.CRATE_LANDED then
        entry.landedSeen = true
        entry.landedGUID = sighting.guid
    elseif CrateRush.isCrateVignetteClaimed and CrateRush.isCrateVignetteClaimed(sighting.vignetteType) then
        local claimedState, claimedSource, claimedFaction = CrateRush.getPlayerRelativeClaimedStateForVignette(sighting.vignetteType)
        entry.claimedSeen = claimedState ~= nil
        entry.claimedState = claimedState
        entry.claimedSource = claimedSource
        entry.claimedFaction = claimedFaction
        entry.claimedByMyFactionSeen = claimedState == CRATE_STATE.CLAIMED_BY_MY_FACTION
    end
end

local function processPlaneSighting(sighting, mapID, trigger)
    if not sighting or sighting.vignetteType ~= VIGNETTE_TYPE.PLANE_FLYING then return end
    if not sighting.hasPosition then return end
    if trigger ~= SCAN_TRIGGER.VIGNETTES_UPDATED then
        return
    end
    if not shardService:isZoneConfirmed(mapID) then return end

    local planeConfirmed = crateLifecycle:onPlaneSeen(mapID, sighting.shardID, sighting.guid, sighting.x, sighting.y)
    if planeConfirmed then
        shardService:acceptCrateEventShard(mapID, sighting.shardID, CRATE_SOURCE.FLYING)
    end
    if prediction and prediction.onPlaneSighting then
        prediction:onPlaneSighting(mapID, sighting, trigger, planeConfirmed)
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
    else
        local claimedState, claimedSource = CrateRush.getPlayerRelativeClaimedStateForVignette(sighting.vignetteType)
        if claimedState and claimedSource then
            crateLifecycle:transition(
                mapID,
                sighting.shardID,
                claimedState,
                sighting.position and sighting.position.x or sighting.x,
                sighting.position and sighting.position.y or sighting.y,
                claimedSource
            )
            shardService:acceptCrateEventShard(mapID, sighting.shardID, claimedSource)
        end
    end
end

local function processVignette(sighting, mapID, trigger, rawMapID, scanID, confirmedShardAtScanStart, scanContext)
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

    if mapID and sighting.shardID and not crateKeys:sameShard(confirmedShardAtScanStart, sighting.shardID) then
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

    recordScanObservation(scanContext, mapID, sighting)

    processPlaneSighting(sighting, mapID, trigger)

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
    local scanContext = {
        observedByKey = {},
    }

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

            processVignette(sighting, mapID, trigger, rawMapID, scanID, confirmedShardAtScanStart, scanContext)
        end
    end

    if crateLifecycle and crateLifecycle.onVignetteScanComplete then
        crateLifecycle:onVignetteScanComplete(mapID, confirmedShardAtScanStart, scanContext, trigger)
    end
end

shardService:setScanFunction(scanVignettes)

function crateHandler:onPlayerEnteringWorld(isInitialLogin, isReloadingUi)
    CrateRush.logDebug("PLAYER_ENTERING_WORLD | initialLogin=" .. tostring(isInitialLogin) .. " reload=" .. tostring(isReloadingUi))
    if prediction and prediction.onPlayerEnteringWorld then
        prediction:onPlayerEnteringWorld()
    end
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
    CrateRush.logDebug("ZONE_CHANGED_NEW_AREA | mapID=" .. tostring(mapID)
        .. " zone=" .. tostring(zoneContext.rawZoneName)
        .. " crateZoneID=" .. tostring(crateZoneID)
        .. " crateZone=" .. tostring(crateZoneName))
    if prediction and prediction.onZoneChanged then
        prediction:onZoneChanged(crateZoneID, mapID)
    end
    if crateZoneID then
        shardService:beginZone(crateZoneID)
    else
        zoneLog("ZONE_CHANGE_SKIP rawZone=" .. tostring(mapID) .. " notCrateZone")
    end
end

function crateHandler:onVignettesUpdated()
    scanVignettes(SCAN_TRIGGER.VIGNETTES_UPDATED)
end

function crateHandler:onNpcAnnouncement(text, npcName, language, channelString, target, flags, unknown1, channelNumber, channelName, unknown2, lineID, guid, ...)
    if not text or not npcName then return end

    CrateRush.logDebug("NPC_ANNOUNCEMENT | npc=" .. tostring(npcName) .. " text=" .. tostring(text))

    if not crateCycleAnchorService:isCrateCycleAnchor(text, npcName) then return end

    CrateRush.logDebug("CRATE_CYCLE_ANCHOR | npc=" .. tostring(npcName))

    local mapID = zoneResolver:getPlayerMapID()
    if not mapID then return end

    local crateZoneID = zoneResolver:resolveCrateZoneID(mapID)
    if not crateZoneID then
        CrateRush.logDebug("CRATE_CYCLE_ANCHOR | ignored outside crate zone rawZone=" .. tostring(mapID))
        return
    end

    local confirmedShardID = shardService:getConfirmedShard(crateZoneID)
    if confirmedShardID then
        local serverEventTime = CrateRush.clock:serverTime()
        local accepted = crateLifecycle:transition(crateZoneID, confirmedShardID, CRATE_STATE.DETECTED, nil, nil, CRATE_SOURCE.CRATE_CYCLE_ANCHOR, serverEventTime)
        shardService:acceptCrateEventShard(crateZoneID, confirmedShardID, CRATE_SOURCE.CRATE_CYCLE_ANCHOR)
        if accepted and CrateRush.comms and CrateRush.comms.sendCrateCycleAnchor then
            CrateRush.comms:sendCrateCycleAnchor(crateZoneID, confirmedShardID, serverEventTime)
        end
    else
        CrateRush.logDebug("CRATE_CYCLE_ANCHOR | waiting for confirmed shard before DETECTED transition")
    end

    scanVignettes(SCAN_TRIGGER.CRATE_CYCLE_ANCHOR)
end

function crateHandler:onGroupRosterUpdate()
    local inRaid = IsInRaid() or false
    local inGroup = IsInGroup() or false
    local members = GetNumGroupMembers() or 0
    local now = CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or 0
    local logKey = tostring(inRaid) .. ":" .. tostring(inGroup)
    if logKey ~= lastGroupRosterLogKey or not lastGroupRosterLogAt or now - lastGroupRosterLogAt >= 60 then
        lastGroupRosterLogAt = now
        lastGroupRosterLogKey = logKey
        CrateRush.logDebug("GROUP_ROSTER_UPDATE | inRaid=" .. tostring(inRaid) .. " inGroup=" .. tostring(inGroup) .. " members=" .. tostring(members))
    end
    scanVignettes(SCAN_TRIGGER.GROUP_ROSTER_UPDATE)
end

