-- CrateRush
-- logic/domainStateDiagnostics.lua - Debug-only consistency checks for domainState accessors.

local diagnostics = {}
CrateRush.domainStateDiagnostics = diagnostics

local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT

local pendingByZone = {}
local lastMismatchBySignature = {}

local function log(msg)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("DOMAINSTATE CHECK | " .. tostring(msg))
    end
end

local function makeKey(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

local function stringify(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function sameValue(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function logMismatch(reason, zoneID, field, domainValue, facadeValue)
    local signature = tostring(reason)
        .. "|" .. tostring(zoneID)
        .. "|" .. tostring(field)
        .. "|" .. stringify(domainValue)
        .. "|" .. stringify(facadeValue)

    if lastMismatchBySignature[signature] then return end
    lastMismatchBySignature[signature] = true

    log("mismatch reason=" .. tostring(reason)
        .. " zone=" .. tostring(zoneID)
        .. " field=" .. tostring(field)
        .. " domain=" .. stringify(domainValue)
        .. " facade=" .. stringify(facadeValue))
end

local function findShardmapRecordForZone(zoneID)
    if not CrateRush.shardmap or not CrateRush.shardmap.getAll then return nil end

    local records = CrateRush.shardmap:getAll()
    if type(records) ~= "table" then return nil end

    for _, record in pairs(records) do
        if record and tostring(record.zoneID) == tostring(zoneID) then
            return record
        end
    end
    return nil
end

local function compareField(reason, zoneID, field, domain, facade)
    if not sameValue(domain and domain[field], facade and facade[field]) then
        logMismatch(reason, zoneID, field, domain and domain[field], facade and facade[field])
    end
end

function diagnostics:compareLifecycle(zoneID, reason)
    if not zoneID or not CrateRush.domainState then return end

    local domain = CrateRush.domainState:getCurrentLifecycle(zoneID)
    local facade = findShardmapRecordForZone(zoneID)

    if not domain and not facade then return end
    if not domain or not facade then
        logMismatch(reason, zoneID, "lifecycleRecord", domain and "present" or "nil", facade and "present" or "nil")
        return
    end

    compareField(reason, zoneID, "zoneID", domain, facade)
    compareField(reason, zoneID, "shardID", domain, facade)
    compareField(reason, zoneID, "state", domain, facade)
    compareField(reason, zoneID, "timerStart", domain, facade)
    compareField(reason, zoneID, "timerQuality", domain, facade)
end

function diagnostics:compareTimer(zoneID, reason)
    if not zoneID or not CrateRush.domainState or not CrateRush.timers then return end
    if not CrateRush.timers.getActiveTimerForZone then return end

    local domain = CrateRush.domainState:getActiveTimer(zoneID)
    local facade = CrateRush.timers:getActiveTimerForZone(zoneID)

    if not domain and not facade then return end
    if not domain or not facade then
        logMismatch(reason, zoneID, "activeTimer", domain and "present" or "nil", facade and "present" or "nil")
        return
    end

    compareField(reason, zoneID, "zoneID", domain, facade)
    compareField(reason, zoneID, "shardID", domain, facade)
    compareField(reason, zoneID, "timerStart", domain, facade)
    compareField(reason, zoneID, "timerQuality", domain, facade)
end

function diagnostics:compareZone(zoneID, reason)
    diagnostics:compareLifecycle(zoneID, reason)
    diagnostics:compareTimer(zoneID, reason)
end

local function mergeMode(currentMode, nextMode)
    if currentMode == "all" or nextMode == "all" then return "all" end
    if currentMode == nextMode then return currentMode end
    if not currentMode then return nextMode or "all" end
    return "all"
end

local function scheduleCompare(zoneID, reason, mode)
    if not zoneID then return end

    local key = tostring(zoneID)
    pendingByZone[key] = reason or pendingByZone[key] or "event"
    pendingByZone[key .. ":mode"] = mergeMode(pendingByZone[key .. ":mode"], mode or "all")
    if pendingByZone[key .. ":scheduled"] then return end

    pendingByZone[key .. ":scheduled"] = true

    local function run()
        local queuedReason = pendingByZone[key]
        local queuedMode = pendingByZone[key .. ":mode"] or "all"
        pendingByZone[key] = nil
        pendingByZone[key .. ":mode"] = nil
        pendingByZone[key .. ":scheduled"] = nil
        if queuedMode == "timer" then
            diagnostics:compareTimer(zoneID, queuedReason or "event")
        elseif queuedMode == "lifecycle" then
            diagnostics:compareLifecycle(zoneID, queuedReason or "event")
        else
            diagnostics:compareZone(zoneID, queuedReason or "event")
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
    else
        run()
    end
end

function diagnostics:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    scheduleCompare(payload.zoneID, "crateStateChanged", "all")
end

function diagnostics:onCrateSightingSeen(payload)
    if type(payload) ~= "table" then return end
    scheduleCompare(payload.zoneID, "crateSightingSeen", "all")
end

function diagnostics:onActiveTimerChanged(payload)
    if type(payload) ~= "table" or type(payload.sorted) ~= "table" then return end

    for _, item in ipairs(payload.sorted) do
        if item and item.key then
            local zoneID = tostring(item.key):match("^([^:]+)")
            scheduleCompare(tonumber(zoneID) or zoneID, "activeTimerChanged", "timer")
        end
    end
end

function diagnostics:onActiveTimerRemoved(payload)
    if type(payload) ~= "table" then return end
    scheduleCompare(payload.zoneID, "activeTimerRemoved", "timer")
end

if CrateRush.domainEvents and DOMAIN_EVENT then
    if DOMAIN_EVENT.CRATE_STATE_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_STATE_CHANGED, diagnostics, "onCrateStateChanged")
    end
    if DOMAIN_EVENT.CRATE_SIGHTING_SEEN then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.CRATE_SIGHTING_SEEN, diagnostics, "onCrateSightingSeen")
    end
    if DOMAIN_EVENT.ACTIVE_TIMER_CHANGED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_CHANGED, diagnostics, "onActiveTimerChanged")
    end
    if DOMAIN_EVENT.ACTIVE_TIMER_REMOVED then
        CrateRush.domainEvents:subscribe(DOMAIN_EVENT.ACTIVE_TIMER_REMOVED, diagnostics, "onActiveTimerRemoved")
    end
end
