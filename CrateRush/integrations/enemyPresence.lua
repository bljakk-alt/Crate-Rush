-- CrateRush
-- integrations/enemyPresence.lua - Enemy Presence feature module.

local enemyPresence = {}
CrateRush.enemyPresence = enemyPresence

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT
local CRATE_STATE = CrateRush.CRATE_STATE

local POWER_MANA = 0
local POWER_RAGE = 1
local POWER_FOCUS = 2
local POWER_ENERGY = 3
local POWER_RUNIC_POWER = 6
local POWER_LUNAR_POWER = 8
local POWER_MAELSTROM = 11
local POWER_INSANITY = 13

local CLASS_NUM = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 3,
    ROGUE = 4,
    PRIEST = 5,
    DEATHKNIGHT = 6,
    SHAMAN = 7,
    MAGE = 8,
    WARLOCK = 9,
    MONK = 10,
    DRUID = 11,
    DEMONHUNTER = 12,
    EVOKER = 13,
}

local HEALER_CONFIRMED_DPS = 0
local HEALER_CONFIRMED = 1
local HEALER_POSSIBLE = 2

local active = false
local target = nil
local currentZoneID = nil
local currentShardID = nil
local currentKey = nil
local lifecycleState = nil
local entries = {}
local broadcasted = {}
local pendingOutbound = {}
local frame = nil
local lastProximityCheckAt = 0
local lastSyncAt = 0
local lastSummarySignature = nil
local lastNameplateWarningKey = nil

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ENEMY | " .. tostring(message))
    end
end

local function serverTime()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function configBool(key, fallback)
    return CrateRush.config and CrateRush.config.getBoolean and CrateRush.config:getBoolean(key, fallback) or fallback
end

local function configNumber(key, fallback)
    return CrateRush.config and CrateRush.config.getNumber and CrateRush.config:getNumber(key, fallback) or fallback
end

local function isWarModeActive()
    return CrateRush.playerContext
        and CrateRush.playerContext.isWarModeEnabled
        and CrateRush.playerContext:isWarModeEnabled()
        or false
end

local function isEnabled()
    return configBool("moduleEnemyPresenceEnabled", false) == true and isWarModeActive()
end

local function areEnemyNameplatesEnabled()
    if C_CVar and C_CVar.GetCVarBool then
        local ok, value = pcall(C_CVar.GetCVarBool, "nameplateShowEnemies")
        if ok and value ~= nil then return value == true end
    end

    if GetCVarBool then
        local ok, value = pcall(GetCVarBool, "nameplateShowEnemies")
        if ok and value ~= nil then return value == true end
    end

    local value = nil
    if C_CVar and C_CVar.GetCVar then
        local ok, result = pcall(C_CVar.GetCVar, "nameplateShowEnemies")
        if ok then value = result end
    elseif GetCVar then
        local ok, result = pcall(GetCVar, "nameplateShowEnemies")
        if ok then value = result end
    end

    if value == nil then return true end
    return value == true or value == 1 or value == "1"
end

local function makeKey(zoneID, shardID)
    if CrateRush.crateKeys and CrateRush.crateKeys.make then
        return CrateRush.crateKeys:make(zoneID, shardID)
    end
    if zoneID and shardID then return tostring(zoneID) .. ":" .. tostring(shardID) end
    return nil
end

local function publish(eventName, payload)
    if CrateRush.domainEvents and eventName then
        CrateRush.domainEvents:publish(eventName, payload or {})
    end
end

local function mapDistanceDegrees(a, b)
    if not a or not b or not a.x or not a.y or not b.x or not b.y then return nil end
    local dx = (tonumber(a.x) - tonumber(b.x)) * 100
    local dy = (tonumber(a.y) - tonumber(b.y)) * 100
    return math.sqrt((dx * dx) + (dy * dy))
end

local function radiusToMapDegrees(yards)
    return (tonumber(yards) or 100) / 100
end

local function getPlayerPosition(zoneID)
    if not C_Map or not C_Map.GetPlayerMapPosition or not zoneID then return nil end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, zoneID, "player")
    if not ok or not position then return nil end
    local x, y = position:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return { x = x, y = y }
end

local function resetRuntime(reason)
    local wasActive = active
    active = false
    entries = {}
    broadcasted = {}
    pendingOutbound = {}
    lastSummarySignature = nil
    lastNameplateWarningKey = nil
    if wasActive then
        debugLog("SCAN_OFF reason=" .. tostring(reason)
            .. " zone=" .. tostring(currentZoneID)
            .. " shard=" .. tostring(currentShardID))
        publish(DOMAIN_EVENT.ENEMY_PRESENCE_SCAN_STATE_CHANGED, {
            active = false,
            reason = reason,
            zoneID = currentZoneID,
            shardID = currentShardID,
        })
    end
    publish(DOMAIN_EVENT.ENEMY_PRESENCE_CHANGED, enemyPresence:getSummary(reason))
end

local function setContext(zoneID, shardID, state)
    local key = makeKey(zoneID, shardID)
    if key ~= currentKey then
        resetRuntime("context_changed")
        currentZoneID = zoneID
        currentShardID = shardID
        currentKey = key
    end
    lifecycleState = state or lifecycleState
end

local function setTarget(zoneID, shardID, x, y, source)
    zoneID = tonumber(zoneID)
    x = tonumber(x)
    y = tonumber(y)
    if not zoneID or not shardID or not x or not y or (x == 0 and y == 0) then return false end

    setContext(zoneID, shardID, lifecycleState)
    local changed = not target
        or target.zoneID ~= zoneID
        or tostring(target.shardID) ~= tostring(shardID)
        or target.x ~= x
        or target.y ~= y
        or target.source ~= source

    target = {
        zoneID = zoneID,
        shardID = shardID,
        x = x,
        y = y,
        source = source or "unknown",
        updatedAt = serverTime(),
    }

    if changed then
        debugLog("TARGET zone=" .. tostring(zoneID)
            .. " shard=" .. tostring(shardID)
            .. " source=" .. tostring(source)
            .. " x=" .. tostring(x)
            .. " y=" .. tostring(y))
    end
    return true
end

local function classToNum(classFilename)
    return CLASS_NUM[classFilename]
end

local function classifyHealer(classFilename, powerType)
    if classFilename == "PRIEST" then
        return powerType == POWER_MANA and HEALER_CONFIRMED or HEALER_CONFIRMED_DPS
    elseif classFilename == "DRUID" then
        return powerType == POWER_MANA and HEALER_CONFIRMED or HEALER_CONFIRMED_DPS
    elseif classFilename == "MONK" then
        return powerType == POWER_MANA and HEALER_CONFIRMED or HEALER_CONFIRMED_DPS
    elseif classFilename == "SHAMAN" then
        return powerType == POWER_MAELSTROM and HEALER_CONFIRMED_DPS or HEALER_POSSIBLE
    elseif classFilename == "PALADIN" or classFilename == "EVOKER" then
        return HEALER_POSSIBLE
    end
    return HEALER_CONFIRMED_DPS
end
local function ensureEntry(guid)
    if not guid then return nil end
    entries[guid] = entries[guid] or {
        guid = guid,
        localSeen = false,
        remoteReporters = {},
    }
    return entries[guid]
end

local function addPending(guid)
    if not guid or broadcasted[guid] then return end
    pendingOutbound[guid] = true
end

local function updateLocalEnemy(unitToken)
    if not active or not unitToken then return false end
    if UnitIsPlayer and not UnitIsPlayer(unitToken) then return false end
    if UnitIsEnemy and not UnitIsEnemy("player", unitToken) then return false end

    local guid = UnitGUID and UnitGUID(unitToken) or nil
    if not guid then return false end

    local _, classFilename = UnitClass(unitToken)
    local classNum = classToNum(classFilename)
    if not classNum then return false end

    local powerType = UnitPowerType and UnitPowerType(unitToken) or nil
    local faction = UnitFactionGroup and UnitFactionGroup(unitToken) or nil
    local level = UnitLevel and UnitLevel(unitToken) or nil
    local now = serverTime()
    local entry = ensureEntry(guid)
    if not entry then return false end

    local wasNewLocal = entry.localSeen ~= true
    entry.classNum = classNum
    entry.class = classFilename
    entry.healerBit = classifyHealer(classFilename, powerType)
    entry.faction = faction
    entry.level = level
    entry.localSeen = true
    entry.localLastSeen = now

    if wasNewLocal then
        debugLog("LOCAL_SEEN zone=" .. tostring(currentZoneID)
            .. " shard=" .. tostring(currentShardID)
            .. " class=" .. tostring(classFilename)
            .. " healer=" .. tostring(entry.healerBit))
    end

    addPending(guid)
    enemyPresence:publishSummary("local_seen")
    return true
end

local function snapshotNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return 0 end
    local count = 0
    local plates = C_NamePlate.GetNamePlates()
    for _, plate in ipairs(plates or {}) do
        local unit = plate and plate.namePlateUnitToken
        if unit and updateLocalEnemy(unit) then
            count = count + 1
        end
    end
    return count
end

local function confidenceFor(entry)
    local remoteCount = 0
    for _ in pairs(entry.remoteReporters or {}) do
        remoteCount = remoteCount + 1
    end
    if entry.localSeen then
        return remoteCount >= 2 and "HIGH" or "MEDIUM"
    end
    if remoteCount >= 3 then return "HIGH" end
    if remoteCount >= 2 then return "MEDIUM" end
    return "LOW"
end

local function buildSummary(reason)
    local total = 0
    local confirmed = 0
    local possible = 0
    local confidence = "LOW"
    local anyMedium = false
    local anyHigh = false

    for _, entry in pairs(entries) do
        total = total + 1
        if tonumber(entry.healerBit) == HEALER_CONFIRMED then
            confirmed = confirmed + 1
        elseif tonumber(entry.healerBit) == HEALER_POSSIBLE then
            possible = possible + 1
        end
        local c = confidenceFor(entry)
        if c == "HIGH" then anyHigh = true end
        if c == "MEDIUM" then anyMedium = true end
    end

    if anyHigh then confidence = "HIGH" elseif anyMedium then confidence = "MEDIUM" end

    local nameplatesEnabled = areEnemyNameplatesEnabled()
    local warning = active == true and nameplatesEnabled ~= true and "enemy_nameplates_off" or nil

    return {
        active = active == true,
        hasData = total > 0,
        hasWarning = warning ~= nil,
        warning = warning,
        nameplatesEnabled = nameplatesEnabled,
        reason = reason,
        zoneID = currentZoneID,
        shardID = currentShardID,
        key = currentKey,
        target = target,
        total = total,
        totalRange = tostring(total),
        confirmedHealers = confirmed,
        possibleHealers = possible,
        healerMin = confirmed,
        healerMax = confirmed + possible,
        healerRange = tostring(confirmed) .. "+" .. tostring(possible),
        confidence = confidence,
        updatedAt = serverTime(),
    }
end

function enemyPresence:getSummary(reason)
    return buildSummary(reason)
end

function enemyPresence:publishSummary(reason)
    local summary = buildSummary(reason)
    local signature = tostring(summary.active) .. ":" .. tostring(summary.total)
        .. ":" .. tostring(summary.confirmedHealers) .. ":" .. tostring(summary.possibleHealers)
        .. ":" .. tostring(summary.confidence) .. ":" .. tostring(summary.zoneID)
        .. ":" .. tostring(summary.shardID) .. ":" .. tostring(summary.warning)
    if signature == lastSummarySignature then return false end
    lastSummarySignature = signature
    publish(DOMAIN_EVENT.ENEMY_PRESENCE_CHANGED, summary)
    debugLog("SUMMARY active=" .. tostring(summary.active)
        .. " zone=" .. tostring(summary.zoneID)
        .. " shard=" .. tostring(summary.shardID)
        .. " total=" .. tostring(summary.total)
        .. " healers=" .. tostring(summary.healerRange)
        .. " confidence=" .. tostring(summary.confidence)
        .. " warning=" .. tostring(summary.warning))

    if summary.warning == "enemy_nameplates_off" and lastNameplateWarningKey ~= summary.key then
        lastNameplateWarningKey = summary.key
        debugLog("WARNING nameplates_off zone=" .. tostring(summary.zoneID)
            .. " shard=" .. tostring(summary.shardID))
    elseif summary.warning ~= "enemy_nameplates_off" then
        lastNameplateWarningKey = nil
    end
    return true
end

local function setActive(value, reason)
    value = value == true
    if active == value then return false end

    if not value then
        resetRuntime(reason or "scan_inactive")
        return true
    end

    active = true
    entries = {}
    broadcasted = {}
    pendingOutbound = {}
    lastSummarySignature = nil
    lastNameplateWarningKey = nil
    debugLog("SCAN_ON reason=" .. tostring(reason)
        .. " zone=" .. tostring(currentZoneID)
        .. " shard=" .. tostring(currentShardID)
        .. " target=" .. tostring(target and target.source)
        .. " radiusYards=" .. tostring(configNumber("enemyPresenceRadiusYards", 250)))
    publish(DOMAIN_EVENT.ENEMY_PRESENCE_SCAN_STATE_CHANGED, {
        active = true,
        reason = reason,
        zoneID = currentZoneID,
        shardID = currentShardID,
        target = target,
    })
    local count = snapshotNameplates()
    debugLog("SNAPSHOT count=" .. tostring(count))
    enemyPresence:publishSummary("scan_on")
    return true
end

local function shouldWatchState(state)
    return state == CRATE_STATE.DROPPING or state == CRATE_STATE.LANDED
end

function enemyPresence:evaluateProximity(reason)
    if not isEnabled() then
        return setActive(false, reason or "disabled")
    end

    if not target or not target.zoneID or not target.x or not target.y then
        return setActive(false, reason or "no_target")
    end

    local playerPosition = getPlayerPosition(target.zoneID)
    if not playerPosition then
        return setActive(false, reason or "player_position_missing")
    end

    local distance = mapDistanceDegrees(playerPosition, target)
    local radius = radiusToMapDegrees(configNumber("enemyPresenceRadiusYards", 250))
    if distance and distance <= radius then
        local changed = setActive(true, reason or "inside_radius")
        if not changed then
            enemyPresence:publishSummary(reason or "inside_radius")
        end
        return changed
    end
    return setActive(false, reason or "outside_radius")
end

function enemyPresence:onNamePlateUnitAdded(unitToken)
    return updateLocalEnemy(unitToken)
end

function enemyPresence:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end

    setContext(payload.zoneID, payload.shardID, payload.state)

    if payload.state == CRATE_STATE.DROPPING and payload.dropX and payload.dropY then
        setTarget(payload.zoneID, payload.shardID, payload.dropX, payload.dropY, "dropping")
    elseif payload.state == CRATE_STATE.LANDED and payload.dropX and payload.dropY then
        setTarget(payload.zoneID, payload.shardID, payload.dropX, payload.dropY, "landed")
    elseif CrateRush.isCrateStateClaimed and CrateRush.isCrateStateClaimed(payload.state) then
        resetRuntime("crate_claimed")
        return
    elseif not shouldWatchState(payload.state) then
        if payload.state ~= CRATE_STATE.DETECTED then
            resetRuntime("state_" .. tostring(payload.state))
            return
        end
    end

    enemyPresence:evaluateProximity("crate_state")
end

function enemyPresence:onPredictionUpdated(payload)
    if type(payload) ~= "table" then return end
    if target and target.source ~= "prediction" then return end
    setContext(payload.zoneID, payload.shardID, lifecycleState)
    if setTarget(payload.zoneID, payload.shardID, payload.dropX, payload.dropY, "prediction") then
        enemyPresence:evaluateProximity("prediction")
    end
end

function enemyPresence:onPredictionCleared(payload)
    if target and target.source == "prediction" then
        target = nil
        enemyPresence:evaluateProximity("prediction_cleared")
    end
end

function enemyPresence:onConfigChanged(payload)
    local key = payload and payload.key or nil
    if key == "moduleEnemyPresenceEnabled" or key == "enemyPresenceRadiusYards" or key == "enemyPresenceProximityPollSeconds" then
        enemyPresence:evaluateProximity("config_" .. tostring(key))
    end
end

function enemyPresence:onPlayerContextChanged()
    enemyPresence:evaluateProximity("player_context")
end

function enemyPresence:onPlayerEnteringWorld()
    enemyPresence:evaluateProximity("entering_world")
end

function enemyPresence:onZoneChanged()
    resetRuntime("zone_changed")
    target = nil
    currentZoneID = nil
    currentShardID = nil
    currentKey = nil
    lifecycleState = nil
end

function enemyPresence:onPlayerFlagsChanged()
    enemyPresence:evaluateProximity("player_flags_changed")
end

function enemyPresence:onGroupRosterUpdate()
    if not IsInGroup or not IsInGroup() then
        resetRuntime("left_group")
    end
end

local function encodeEntry(entry)
    if not entry or not entry.guid or not entry.classNum or entry.healerBit == nil then return nil end
    return "g:" .. tostring(entry.guid) .. ",c:" .. tostring(entry.classNum) .. ",h:" .. tostring(entry.healerBit)
end

function enemyPresence:consumePendingReports()
    local list = {}
    for guid in pairs(pendingOutbound) do
        local entry = entries[guid]
        local encoded = encodeEntry(entry)
        if encoded then
            list[#list + 1] = encoded
            broadcasted[guid] = true
        end
        pendingOutbound[guid] = nil
    end
    table.sort(list)
    return table.concat(list, ".")
end

function enemyPresence:hasPendingReports()
    return next(pendingOutbound) ~= nil
end

function enemyPresence:canSendReports()
    return active == true
        and isEnabled()
        and currentZoneID ~= nil
        and currentShardID ~= nil
        and self:hasPendingReports()
end

local function parseEntry(text)
    if type(text) ~= "string" or text == "" then return nil end
    local entry = {}
    for part in string.gmatch(text, "([^,]+)") do
        local key, value = part:match("^([^:]+):(.*)$")
        if key and value then
            entry[key] = value
        end
    end
    if not entry.g or not entry.c or not entry.h then return nil end
    return {
        guid = entry.g,
        classNum = tonumber(entry.c),
        healerBit = tonumber(entry.h),
    }
end

function enemyPresence:applyRemoteReport(senderGUID, zoneID, shardID, entriesText)
    if not active or not isEnabled() then return false, "inactive" end
    if tostring(zoneID) ~= tostring(currentZoneID) then return false, "zone_mismatch" end
    if tostring(shardID) ~= tostring(currentShardID) then return false, "shard_mismatch" end
    if not senderGUID or senderGUID == (UnitGUID and UnitGUID("player") or nil) then return false, "self_or_missing_sender" end

    local changed = false
    local now = serverTime()
    for entryText in string.gmatch(tostring(entriesText or ""), "([^%.]+)") do
        local decoded = parseEntry(entryText)
        if decoded and decoded.guid then
            local entry = ensureEntry(decoded.guid)
            if entry then
                entry.classNum = entry.classNum or decoded.classNum
                entry.healerBit = entry.healerBit or decoded.healerBit
                entry.remoteReporters = entry.remoteReporters or {}
                local reporter = entry.remoteReporters[senderGUID]
                if not reporter then changed = true end
                entry.remoteReporters[senderGUID] = {
                    lastSeen = now,
                    classNum = decoded.classNum,
                    healerBit = decoded.healerBit,
                }
            end
        end
    end

    if changed then
        enemyPresence:publishSummary("remote_report")
    end
    return true
end

function enemyPresence:sendPendingReports()
    if not self:canSendReports() then return false end
    if not CrateRush.comms or not CrateRush.PROTO or not CrateRush.PROTO.MSG.ENEMY_PRESENCE_REPORT then return false end
    return CrateRush.comms:send(CrateRush.PROTO.MSG.ENEMY_PRESENCE_REPORT, {
        zoneID = currentZoneID,
        shardID = currentShardID,
    })
end

local function onUpdate(_, elapsed)
    local now = serverTime()
    local pollSeconds = math.max(0.2, configNumber("enemyPresenceProximityPollSeconds", 1))
    if now - lastProximityCheckAt >= pollSeconds then
        lastProximityCheckAt = now
        enemyPresence:evaluateProximity("poll")
    end

    if now - lastSyncAt >= 1 then
        lastSyncAt = now
        enemyPresence:sendPendingReports()
    end
end

function enemyPresence:init()
    if frame then return true end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", onUpdate)
    debugLog("INIT enabled=" .. tostring(configBool("moduleEnemyPresenceEnabled", false))
        .. " radiusYards=" .. tostring(configNumber("enemyPresenceRadiusYards", 250)))
    return true
end

function enemyPresence:onEvent(event, ...)
    if not CrateRush.EVT then return end
    if event == CrateRush.EVT.NAME_PLATE_UNIT_ADDED then
        return enemyPresence:onNamePlateUnitAdded(...)
    elseif event == CrateRush.EVT.PLAYER_ENTERING_WORLD then
        return enemyPresence:onPlayerEnteringWorld(...)
    elseif event == CrateRush.EVT.ZONE_CHANGED_NEW_AREA then
        return enemyPresence:onZoneChanged(...)
    elseif event == CrateRush.EVT.PLAYER_FLAGS_CHANGED then
        return enemyPresence:onPlayerFlagsChanged(...)
    elseif event == CrateRush.EVT.GROUP_ROSTER_UPDATE then
        return enemyPresence:onGroupRosterUpdate(...)
    end
end
if CrateRush.domainEvents and DOMAIN_EVENT then
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, enemyPresence, "onCrateStateChanged")
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.PREDICTION_UPDATED, enemyPresence, "onPredictionUpdated")
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.PREDICTION_CLEARED, enemyPresence, "onPredictionCleared")
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CONFIG_CHANGED, enemyPresence, "onConfigChanged")
    CrateRush.domainEvents:subscribe(DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED, enemyPresence, "onPlayerContextChanged")
end

