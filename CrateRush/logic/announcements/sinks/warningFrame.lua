-- CrateRush
-- logic/announcements/sinks/warningFrame.lua - Floating local warning output.

local sink = {}

function sink:send(announcement)
    if CrateRush.warningframe and CrateRush.warningframe.show then
        CrateRush.warningframe:show(announcement.message)
        return true
    end
    return false
end

if CrateRush.announcementRouter then
    CrateRush.announcementRouter:registerSink("warningFrame", sink)
end
