-- CrateRush
-- logic/syncDisplay.lua - Prepared Sync strip display state. UI consumes this; it does not inspect comms.

local syncDisplay = {}
CrateRush.syncDisplay = syncDisplay

local STATUS_ACTIVE = "active"
local STATUS_REJECTED = "rejected"
local STATUS_UNAVAILABLE = "unavailable"

function syncDisplay:getDisplay()
    local status = CrateRush.comms and CrateRush.comms.getStatus and CrateRush.comms:getStatus() or nil
    if type(status) ~= "table" then
        return { status = STATUS_UNAVAILABLE }
    end

    if status.active then
        return {
            status = STATUS_ACTIVE,
            channel = status.channel,
            leaderGUID = status.leaderGUID,
        }
    end

    if status.grouped and status.tokenRequestExhausted then
        return {
            status = STATUS_REJECTED,
            channel = status.channel,
            leaderGUID = status.leaderGUID,
        }
    end

    return {
        status = STATUS_UNAVAILABLE,
        channel = status.channel,
        leaderGUID = status.leaderGUID,
    }
end