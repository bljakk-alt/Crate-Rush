-- CrateRush
-- logic/announcements/sinks/addonComm.lua - Future addon-to-addon announcement output.

local sink = {}

function sink:isEnabled()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("announceToAddonComm", false)
    end
    return false
end

function sink:send(announcement)
    if not CrateRush.comms or not CrateRush.comms.send then return false end

    local ok, result = pcall(CrateRush.comms.send, CrateRush.comms, "ANNOUNCEMENT", announcement, "GROUP")
    if not ok then
        if CrateRush.debug and CrateRush.debug.log then
            CrateRush.debug:log("ANNOUNCE ADDON COMM ERROR | " .. tostring(result))
        end
        return false
    end
    return result == true
end

if CrateRush.announcementRouter then
    CrateRush.announcementRouter:registerSink("addonComm", sink)
end
