-- CrateRush
-- logic/announcements/sinks/warningFrame.lua - Floating local warning output.

local sink = {}

function sink:isEnabled(announcement)
    if CrateRush.config and CrateRush.config.getBoolean
        and not CrateRush.config:getBoolean("showWarningFrame", true)
    then
        return false
    end
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.isOutputEnabled then
        return CrateRush.announcementMessageConfig:isOutputEnabled(
            announcement and announcement.messageID,
            "warningFrame",
            true
        )
    end
    return true
end

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
