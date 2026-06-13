-- CrateRush
-- constants/keys.lua - Shared key helpers for zone/shard records.

local crateKeys = {}
CrateRush.crateKeys = crateKeys

function crateKeys:make(zoneID, shardID)
    if not zoneID or not shardID then return nil end
    return tostring(zoneID) .. ":" .. tostring(shardID)
end

function crateKeys:parseZone(key)
    if not key then return nil end

    local zone = tostring(key):match("^([^:]+)")
    return tonumber(zone) or zone
end

function crateKeys:sameShard(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end
