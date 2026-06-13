-- CrateRush
-- logic/playerContext.lua - Player-level context shared by domain and UI.

local playerContext = {}
CrateRush.playerContext = playerContext

local actualFactionKey = nil
local overrideFactionKey = nil
local warModeEnabled = false

local function getEffectiveFactionKey()
    return CrateRush.resolveFactionKey(overrideFactionKey or actualFactionKey)
end

local function getFactionName(key)
    return CrateRush.getFactionName(key)
end

local function buildPayload(source, previous)
    local effectiveFactionKey = getEffectiveFactionKey()

    return {
        source              = source,
        factionKey          = effectiveFactionKey,
        faction             = getFactionName(effectiveFactionKey),
        effectiveFactionKey = effectiveFactionKey,
        effectiveFaction    = getFactionName(effectiveFactionKey),
        actualFactionKey    = actualFactionKey,
        actualFaction       = getFactionName(actualFactionKey),
        overrideFactionKey  = overrideFactionKey,
        overrideFaction     = getFactionName(overrideFactionKey),
        isOverridden        = overrideFactionKey ~= nil,
        warModeEnabled      = warModeEnabled == true,
        previousFactionKey  = previous and previous.factionKey or nil,
        previousActualKey   = previous and previous.actualFactionKey or nil,
        previousOverrideKey = previous and previous.overrideFactionKey or nil,
        previousWarModeEnabled = previous and previous.warModeEnabled or nil,
    }
end

local function snapshot()
    return {
        factionKey         = getEffectiveFactionKey(),
        actualFactionKey   = actualFactionKey,
        overrideFactionKey = overrideFactionKey,
        warModeEnabled     = warModeEnabled == true,
    }
end

local function publishIfChanged(source, previous)
    local current = snapshot()
    if previous
        and previous.factionKey == current.factionKey
        and previous.actualFactionKey == current.actualFactionKey
        and previous.overrideFactionKey == current.overrideFactionKey
        and previous.warModeEnabled == current.warModeEnabled
    then
        return false
    end

    if CrateRush.domainEvents
        and CrateRush.DOMAIN_EVENT
        and CrateRush.DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED
    then
        CrateRush.domainEvents:publish(
            CrateRush.DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED,
            buildPayload(source, previous)
        )
    end

    return true
end

local function normalizeFactionKey(value)
    return CrateRush.normalizeFactionKey(value)
end

local function readPlayerFactionKey()
    local ok, faction = pcall(UnitFactionGroup, "player")
    if not ok then return nil end
    return normalizeFactionKey(faction)
end

local function readWarModeEnabled()
    if C_PvP and C_PvP.IsWarModeDesired then
        local ok, value = pcall(C_PvP.IsWarModeDesired)
        return ok and value == true
    end
    return false
end

local function readStoredOverrideKey()
    if not CrateRush.config or not CrateRush.config.get then return nil end
    return normalizeFactionKey(CrateRush.config:get("factionOverride"))
end

local function writeStoredOverrideKey(key)
    if CrateRush.config and CrateRush.config.set then
        CrateRush.config:set("factionOverride", key, "playerContext")
    end
end

function playerContext:init()
    actualFactionKey = readPlayerFactionKey()
    overrideFactionKey = readStoredOverrideKey()
    warModeEnabled = readWarModeEnabled()
    return playerContext:getFactionKey()
end

function playerContext:refresh(source)
    local previous = snapshot()
    actualFactionKey = readPlayerFactionKey()
    overrideFactionKey = readStoredOverrideKey()
    warModeEnabled = readWarModeEnabled()
    publishIfChanged(source or "REFRESH", previous)
    return playerContext:getFactionKey()
end

function playerContext:onPlayerEnteringWorld()
    return playerContext:refresh(CrateRush.EVT and CrateRush.EVT.PLAYER_ENTERING_WORLD or "PLAYER_ENTERING_WORLD")
end

function playerContext:onZoneChanged()
    return playerContext:refresh(CrateRush.EVT and CrateRush.EVT.ZONE_CHANGED_NEW_AREA or "ZONE_CHANGED_NEW_AREA")
end

function playerContext:onPlayerFlagsChanged()
    return playerContext:refresh(CrateRush.EVT and CrateRush.EVT.PLAYER_FLAGS_CHANGED or "PLAYER_FLAGS_CHANGED")
end

function playerContext:setFactionOverride(value)
    local key = normalizeFactionKey(value)
    if not key then return false end

    local previous = snapshot()
    actualFactionKey = readPlayerFactionKey()
    overrideFactionKey = key
    warModeEnabled = readWarModeEnabled()
    writeStoredOverrideKey(key)
    publishIfChanged("FACTION_OVERRIDE", previous)
    return true
end

function playerContext:clearFactionOverride()
    local previous = snapshot()
    actualFactionKey = readPlayerFactionKey()
    overrideFactionKey = nil
    warModeEnabled = readWarModeEnabled()
    writeStoredOverrideKey(nil)
    publishIfChanged("FACTION_OVERRIDE_CLEAR", previous)
end

function playerContext:getFactionKey()
    return getEffectiveFactionKey()
end

function playerContext:getEffectiveFactionKey()
    return getEffectiveFactionKey()
end

function playerContext:getFaction()
    return CrateRush.resolveFactionName(playerContext:getFactionKey())
end

function playerContext:getEffectiveFaction()
    return playerContext:getFaction()
end

function playerContext:getActualFactionKey()
    return actualFactionKey
end

function playerContext:getActualFaction()
    return getFactionName(playerContext:getActualFactionKey())
end

function playerContext:getFactionOverrideKey()
    return overrideFactionKey
end

function playerContext:getFactionOverride()
    local key = playerContext:getFactionOverrideKey()
    return getFactionName(key)
end

function playerContext:isFactionOverridden()
    return overrideFactionKey ~= nil
end

function playerContext:isWarModeEnabled()
    return warModeEnabled == true
end

function playerContext:normalizeFactionKey(value)
    return normalizeFactionKey(value)
end
