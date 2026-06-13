-- CrateRush
-- logic/announcements/sinks/partyRaid.lua - Party/raid chat announcement output.

local sink = {}
local CHAT_CHANNEL = CrateRush.CHAT_CHANNEL

local function getDefinition(announcement)
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.getDefinition then
        return CrateRush.announcementMessageConfig:getDefinition(announcement and announcement.messageID)
    end
    return nil
end

local function messageOutputEnabled(announcement, outputName, fallback)
    if CrateRush.announcementMessageConfig and CrateRush.announcementMessageConfig.isOutputEnabled then
        return CrateRush.announcementMessageConfig:isOutputEnabled(
            announcement and announcement.messageID,
            outputName,
            fallback
        )
    end
    return fallback ~= false
end

local function hasRaidAuthority()
    return (UnitIsGroupLeader and UnitIsGroupLeader("player"))
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or false
end


local function isManualForced(announcement)
    return announcement and announcement.forcePartyRaid == true
end

local function useRaidWarning(announcement)
    local definition = getDefinition(announcement)
    local delivery = definition and definition.automaticDelivery or nil
    if delivery and delivery.raidWarningAllowed == false then return false end
    if not hasRaidAuthority() then return false end
    return messageOutputEnabled(announcement, "raidWarning", false)
end

local function getOutboundChannel(announcement)
    local manualForced = isManualForced(announcement)

    if IsInRaid and IsInRaid() then
        if not manualForced and not hasRaidAuthority() then
            return nil, "raid_not_leader_or_assistant"
        end
        if not manualForced and useRaidWarning(announcement) then
            return CHAT_CHANNEL.RAID_WARNING
        end
        return CHAT_CHANNEL.RAID
    elseif IsInGroup and IsInGroup() then
        return CHAT_CHANNEL.PARTY
    end
    return nil, "not_in_group"
end

function sink:isEnabled(announcement)
    if announcement and announcement.localOnly then
        return false
    end
    if announcement and announcement.forcePartyRaid then
        return true
    end
    if CrateRush.config and CrateRush.config.getBoolean
        and not CrateRush.config:getBoolean("announceToPartyRaid", true)
    then
        return false
    end
    return messageOutputEnabled(announcement, "partyRaid", true)
end

function sink:send(announcement)
    if announcement and announcement.localOnly then return false end

    local channel, reason = getOutboundChannel(announcement)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ANNOUNCE TARGET | sink=partyRaid channel=" .. tostring(channel or "LOCAL_ONLY")
            .. " reason=" .. tostring(reason or "ok"))
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