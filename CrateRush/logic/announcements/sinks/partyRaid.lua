-- CrateRush
-- logic/announcements/sinks/partyRaid.lua - Party/raid chat announcement output.

local sink = {}
local CHAT_CHANNEL = CrateRush.CHAT_CHANNEL

local function getOutboundChannel()
    if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return CHAT_CHANNEL.RAID_WARNING
    elseif IsInGroup() then
        return CHAT_CHANNEL.PARTY
    end
    return nil
end

function sink:send(announcement)
    local channel = getOutboundChannel()
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ANNOUNCE TARGET | sink=partyRaid channel=" .. tostring(channel or "LOCAL_ONLY"))
    end

    if not channel then return false end

    local ok, err = pcall(SendChatMessage, announcement.message, channel)
    if not ok then
        if CrateRush.debug and CrateRush.debug.log then
            CrateRush.debug:log("ANNOUNCE ERROR | " .. tostring(err))
        end
        return false
    end

    return true
end

if CrateRush.announcementRouter then
    CrateRush.announcementRouter:registerSink("partyRaid", sink)
end
