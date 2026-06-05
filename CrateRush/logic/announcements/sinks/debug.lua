-- CrateRush
-- logic/announcements/sinks/debug.lua - Debug announcement sink.

local sink = {}

function sink:send(announcement)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ANNOUNCE | " .. tostring(announcement.message))
    end
    return true
end

if CrateRush.announcementRouter then
    CrateRush.announcementRouter:registerSink("debug", sink)
end
