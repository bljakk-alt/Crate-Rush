-- CrateRush
-- logic/announcements/manual.lua - Manual UI-triggered announcement routing.

local manual = {}
CrateRush.manualAnnouncements = manual

local CHAT_CHANNEL = CrateRush.CHAT_CHANNEL or {}

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("MANUAL ANNOUNCE | " .. tostring(message))
    end
end

local function getChannel()
    if IsInRaid and IsInRaid() then
        return CHAT_CHANNEL.RAID or "RAID"
    elseif IsInGroup and IsInGroup() then
        return CHAT_CHANNEL.PARTY or "PARTY"
    end
    return nil
end

local function sendWarningFrame(message)
    if CrateRush.warningframe and CrateRush.warningframe.show then
        CrateRush.warningframe:show(message)
        return true
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.92, 0.05, 1)
        return true
    end
    return false
end

function manual:send(message, messageID)
    if type(message) ~= "string" or message == "" then return false end
    if messageID
        and CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.isEnabled
        and not CrateRush.announcementMessageConfig:isEnabled(messageID)
    then
        return false
    end

    local channel = getChannel()
    if channel then
        local ok, err = pcall(SendChatMessage, message, channel)
        if ok then
            debugLog("channel=" .. tostring(channel) .. " message=" .. message)
            return true
        end
        debugLog("error=" .. tostring(err))
        return false
    end

    local delivered = sendWarningFrame(message)
    if delivered then
        debugLog("channel=WARNING_FRAME message=" .. message)
    end
    return delivered
end
