-- CrateRush
-- logic/announcements/sinks/defaultChatFrame.lua - Local clickable chat preview.

local sink = {}

function sink:isEnabled()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("echoAnnouncementsToDefaultChatFrame", true)
    end
    return true
end

function sink:send(announcement)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(announcement.message)
        return true
    end
    return false
end

if CrateRush.announcementRouter then
    CrateRush.announcementRouter:registerSink("defaultChatFrame", sink)
end
