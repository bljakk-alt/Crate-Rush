-- CrateRush
-- comms.lua - CrateRush addon-to-addon protocol management.

local comms = {}
CrateRush.comms = comms

local PROTO = CrateRush.PROTO

local FIELD_SEPARATOR = ";"
local KEY_VALUE_SEPARATOR = "="

local MANAGEMENT_TYPES = {
    [PROTO.MSG.TOKEN_REQUEST] = true,
    [PROTO.MSG.TOKEN_UPDATE]  = true,
}

local NORMAL_TYPES = {
    [PROTO.MSG.TIMER_SYNC_REQUEST]  = true,
    [PROTO.MSG.TIMER_SYNC_RESPONSE] = true,
    [PROTO.MSG.TIMER_DELETE]        = true,
    [PROTO.MSG.CRATE_CYCLE_ANCHOR]  = true,
    [PROTO.MSG.ENEMY_PRESENCE_REPORT] = true,
}

comms.groupToken = nil
comms.requestAttempts = 0
comms.lastTokenRequestAt = nil
comms.lastTimerSyncRequestAt = nil
comms.requestContextKey = nil
comms.tokenRequestExhausted = false
comms.initialized = false
comms.lastMemberRosterContextKey = nil

local throttledDebugAtByKey = {}

local function debugLog(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("COMMS | " .. tostring(message))
    end
end

local function serverTime()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function debugLogThrottled(key, message, seconds)
    key = tostring(key or message or "unknown")
    local now = serverTime()
    local last = throttledDebugAtByKey[key]
    if last and now - last < (seconds or 30) then return end
    throttledDebugAtByKey[key] = now
    debugLog(message)
end

local function isWarModeActive()
    return CrateRush.playerContext
        and CrateRush.playerContext.isWarModeEnabled
        and CrateRush.playerContext:isWarModeEnabled()
        or false
end

local function isGrouped()
    return IsInGroup and IsInGroup() == true
end

local function isRaid()
    return IsInRaid and IsInRaid() == true
end

local function isLeader()
    return UnitIsGroupLeader and UnitIsGroupLeader("player") == true
end

local function getPlayerGUID()
    return UnitGUID and UnitGUID("player") or nil
end

local function getGroupChannel()
    if isRaid() then return PROTO.CHANNEL.RAID end
    if isGrouped() then return PROTO.CHANNEL.PARTY end
    return nil
end

local function getUnitFullName(unit)
    if not unit or not UnitName then return nil end

    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    else
        name, realm = UnitName(unit)
    end

    if not name then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function unitNameMatches(unit, sender)
    if not unit or not sender then return false end

    local name = UnitName and UnitName(unit) or nil
    local fullName = getUnitFullName(unit)
    if sender == name or sender == fullName then return true end

    if Ambiguate then
        local senderShort = Ambiguate(sender, "short")
        local senderNone = Ambiguate(sender, "none")
        local fullShort = fullName and Ambiguate(fullName, "short") or nil
        local fullNone = fullName and Ambiguate(fullName, "none") or nil
        return senderShort == name
            or senderNone == name
            or senderShort == fullShort
            or senderNone == fullNone
    end

    return false
end

local function eachGroupUnit(callback)
    if not callback then return nil end

    local result = callback("player")
    if result then return result end

    if isRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            result = callback("raid" .. i)
            if result then return result end
        end
    elseif isGrouped() then
        local count = math.max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1)
        for i = 1, count do
            result = callback("party" .. i)
            if result then return result end
        end
    end

    return nil
end

local function findCurrentLeaderUnit()
    return eachGroupUnit(function(unit)
        if UnitExists and UnitExists(unit) and UnitIsGroupLeader and UnitIsGroupLeader(unit) then
            return unit
        end
        return nil
    end)
end

local function getCurrentLeaderGUID()
    local unit = findCurrentLeaderUnit()
    return unit and UnitGUID and UnitGUID(unit) or nil
end

local function getCurrentLeaderTarget()
    local unit = findCurrentLeaderUnit()
    return unit and getUnitFullName(unit) or nil
end

local function resolveSenderGUID(sender)
    if not sender then return nil end

    return eachGroupUnit(function(unit)
        if UnitExists and UnitExists(unit) and unitNameMatches(unit, sender) then
            return UnitGUID and UnitGUID(unit) or nil
        end
        return nil
    end)
end

local function isValidManagementChannel(channel)
    return channel == PROTO.CHANNEL.PARTY
        or channel == PROTO.CHANNEL.RAID
        or channel == PROTO.CHANNEL.WHISPER
end

local function isValidGroupChannel(channel)
    return channel == PROTO.CHANNEL.PARTY
        or channel == PROTO.CHANNEL.RAID
end

local function isSupportedType(messageType)
    return MANAGEMENT_TYPES[messageType] == true
        or NORMAL_TYPES[messageType] == true
end

local function makeContextKey()
    local channel = getGroupChannel()
    if not channel then return nil end
    local leaderGUID = getCurrentLeaderGUID()
    if not leaderGUID and not isLeader() then return nil end
    return tostring(channel) .. ":" .. tostring(leaderGUID or getPlayerGUID() or "leader")
end

local function wipeToken(reason)
    if comms.groupToken then
        debugLog("TOKEN_WIPE reason=" .. tostring(reason))
    end
    comms.groupToken = nil
    comms.lastTimerSyncRequestAt = nil
end

local function resetRequestState(reason)
    comms.requestAttempts = 0
    comms.lastTokenRequestAt = nil
    comms.lastTimerSyncRequestAt = nil
    comms.tokenRequestExhausted = false
    comms.requestContextKey = makeContextKey()
    debugLog("TOKEN_REQUEST_RESET reason=" .. tostring(reason)
        .. " context=" .. tostring(comms.requestContextKey))
end

local function ensureRequestContext(reason)
    local contextKey = makeContextKey()
    if not contextKey then return false end
    if comms.requestContextKey ~= contextKey then
        comms.requestContextKey = contextKey
        comms.requestAttempts = 0
        comms.lastTokenRequestAt = nil
        comms.tokenRequestExhausted = false
        debugLog("TOKEN_REQUEST_CONTEXT reason=" .. tostring(reason)
            .. " context=" .. tostring(contextKey))
        return true
    end
    return false
end

local function encodeValue(value)
    local text = tostring(value)
    return text:gsub("([^A-Za-z0-9_%-])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function decodeValue(value)
    if value == nil then return nil, "missing_value" end

    local index = 1
    while true do
        local percentAt = value:find("%", index, true)
        if not percentAt then break end

        local hex = value:sub(percentAt + 1, percentAt + 2)
        if #hex ~= 2 or not hex:match("^%x%x$") then
            return nil, "bad_escape"
        end
        index = percentAt + 3
    end

    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function encodeFields(fields)
    if type(fields) ~= "table" then return nil end

    local ordered = {}
    local preferred = { "v", "type", "senderGUID", "groupToken", "token", "zoneId", "shardId", "serverEventTime", "timerList", "entries" }
    local used = {}
    for _, key in ipairs(preferred) do
        if fields[key] ~= nil then
            ordered[#ordered + 1] = key
            used[key] = true
        end
    end

    local rest = {}
    for key, value in pairs(fields) do
        if value ~= nil and not used[key] then
            rest[#rest + 1] = key
        end
    end
    table.sort(rest)
    for _, key in ipairs(rest) do
        ordered[#ordered + 1] = key
    end

    local chunks = {}
    for _, key in ipairs(ordered) do
        if type(key) ~= "string" or key == "" or key:find("[;=]") then
            return nil
        end
        chunks[#chunks + 1] = key .. KEY_VALUE_SEPARATOR .. encodeValue(fields[key])
    end

    return table.concat(chunks, FIELD_SEPARATOR)
end

local function decodeFields(message)
    if type(message) ~= "string" or message == "" then return nil, "empty_message" end

    local fields = {}
    for chunk in string.gmatch(message, "([^;]+)") do
        local key, rawValue = chunk:match("^([^=]+)=(.*)$")
        if not key or key == "" or key:find("[;=]") then
            return nil, "bad_field"
        end
        if fields[key] ~= nil then
            return nil, "duplicate_key"
        end

        local value, err = decodeValue(rawValue)
        if value == nil and err then
            return nil, err
        end
        fields[key] = value
    end

    if not fields.v or not fields.type or not fields.senderGUID then
        return nil, "missing_required_field"
    end

    return fields
end

local function encodeTimerEntryField(key, value)
    if value == nil then return nil end
    return tostring(key) .. ":" .. encodeValue(value)
end

local function encodeTimerEntry(entry)
    if type(entry) ~= "table" then return nil end

    local parts = {}
    local ordered = { "zoneId", "shardId", "nextTimerStart", "dirty" }
    for _, key in ipairs(ordered) do
        local encoded = encodeTimerEntryField(key, entry[key])
        if encoded then
            parts[#parts + 1] = encoded
        end
    end

    return table.concat(parts, ",")
end

local function decodeTimerEntry(entryText)
    if type(entryText) ~= "string" or entryText == "" then return nil, "empty_timer_entry" end

    local entry = {}
    for part in string.gmatch(entryText, "([^,]+)") do
        local key, rawValue = part:match("^([^:]+):(.*)$")
        if not key or key == "" then
            return nil, "bad_timer_field"
        end
        if entry[key] ~= nil then
            return nil, "duplicate_timer_field"
        end

        local value, err = decodeValue(rawValue)
        if value == nil and err then
            return nil, err
        end
        entry[key] = value
    end

    if not entry.zoneId or not entry.shardId or not entry.nextTimerStart then
        return nil, "missing_timer_field"
    end

    return entry
end

local function encodeTimerList(entries)
    if type(entries) ~= "table" then return "" end

    local chunks = {}
    for _, entry in ipairs(entries) do
        local encoded = encodeTimerEntry(entry)
        if encoded and encoded ~= "" then
            chunks[#chunks + 1] = encoded
        end
    end

    return table.concat(chunks, ".")
end

local function decodeTimerList(timerList)
    if timerList == nil or timerList == "" then return {} end
    if type(timerList) ~= "string" then return nil, "bad_timer_list" end

    local entries = {}
    for entryText in string.gmatch(timerList, "([^%.]+)") do
        local entry, err = decodeTimerEntry(entryText)
        if not entry then return nil, err end
        entries[#entries + 1] = entry
    end

    return entries
end

local function getTimerSnapshotEntries()
    local snapshot = CrateRush.timers
        and CrateRush.timers.getActiveTimersSnapshot
        and CrateRush.timers:getActiveTimersSnapshot()
        or {}

    local entries = {}
    for _, timer in pairs(snapshot) do
        if timer and timer.zoneID and timer.shardID and timer.timerStart then
            entries[#entries + 1] = {
                zoneId         = timer.zoneID,
                shardId        = timer.shardID,
                nextTimerStart = timer.timerStart,
                dirty          = timer.dirty == true and "true" or "false",
            }
        end
    end

    table.sort(entries, function(a, b)
        local zoneA = tostring(a.zoneId or "")
        local zoneB = tostring(b.zoneId or "")
        if zoneA == zoneB then
            return tostring(a.shardId or "") < tostring(b.shardId or "")
        end
        return zoneA < zoneB
    end)

    return entries
end

function comms:HashToken(raw)
    local hash = 5381
    raw = tostring(raw or "")
    for i = 1, #raw do
        hash = ((hash * 33) + string.byte(raw, i)) % 2147483647
    end
    return string.format("%08x", hash)
end

function comms:CreateGroupToken()
    local leaderGUID = getPlayerGUID()
    if not leaderGUID then return nil end

    local raw = tostring(leaderGUID)
        .. ":"
        .. tostring(serverTime())
        .. ":"
        .. tostring(math.random())
    return self:HashToken(raw)
end

function comms:Encode(fields)
    return encodeFields(fields)
end

function comms:Decode(message)
    return decodeFields(message)
end

function comms:getStatus()
    return {
        active = isWarModeActive() and isGrouped() and self.groupToken ~= nil,
        token = self.groupToken,
        grouped = isGrouped(),
        channel = getGroupChannel(),
        leader = isLeader(),
        leaderGUID = getCurrentLeaderGUID(),
        requestAttempts = self.requestAttempts,
        tokenRequestExhausted = self.tokenRequestExhausted,
        initialized = self.initialized,
        lastTimerSyncRequestAt = self.lastTimerSyncRequestAt,
    }
end

function comms:init()
    if self.initialized then return true end
    if not CrateRush.RegisterComm then
        debugLog("INIT_FAILED reason=ace_comm_missing")
        return false
    end

    CrateRush:RegisterComm(PROTO.PREFIX, "OnCommReceived")
    self.initialized = true
    debugLog("INIT prefix=" .. tostring(PROTO.PREFIX) .. " version=" .. tostring(PROTO.VERSION))
    self:refreshProtocolContext("init")
    return true
end

function comms:sendEncoded(fields, channel, target)
    if not fields or not channel then return false end
    local message = encodeFields(fields)
    if not message then
        debugLog("SEND_BLOCKED reason=encode_failed type=" .. tostring(fields.type))
        return false
    end

    local ok, err = pcall(CrateRush.SendCommMessage, CrateRush, PROTO.PREFIX, message, channel, target)
    if not ok then
        debugLog("SEND_FAILED type=" .. tostring(fields.type)
            .. " channel=" .. tostring(channel)
            .. " target=" .. tostring(target)
            .. " err=" .. tostring(err))
        return false
    end

    debugLog("SEND type=" .. tostring(fields.type)
        .. " channel=" .. tostring(channel)
        .. " target=" .. tostring(target or "group"))
    return true
end

function comms:sendTokenRequest(reason)
    if not isWarModeActive() then wipeToken("war_mode_off"); return false end
    if not isGrouped() then wipeToken("not_grouped"); return false end
    if isLeader() then return false end
    if self.groupToken then return false end

    ensureRequestContext(reason or "token_request")

    if self.tokenRequestExhausted then
        return false
    end

    if self.requestAttempts >= PROTO.TOKEN_REQUEST_MAX_ATTEMPTS then
        self.tokenRequestExhausted = true
        debugLogThrottled("token_request_max_attempts", "TOKEN_REQUEST_BLOCKED reason=max_attempts attempts=" .. tostring(self.requestAttempts), 30)
        return false
    end

    local now = serverTime()
    if self.lastTokenRequestAt and now - self.lastTokenRequestAt < PROTO.TOKEN_REQUEST_THROTTLE_SECONDS then
        debugLogThrottled("token_request_throttle", "TOKEN_REQUEST_BLOCKED reason=throttle remaining="
            .. tostring(PROTO.TOKEN_REQUEST_THROTTLE_SECONDS - (now - self.lastTokenRequestAt)), 30)
        return false
    end

    local leaderTarget = getCurrentLeaderTarget()
    if not leaderTarget then
        debugLog("TOKEN_REQUEST_BLOCKED reason=leader_target_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("TOKEN_REQUEST_BLOCKED reason=sender_guid_missing")
        return false
    end

    self.requestAttempts = self.requestAttempts + 1
    self.lastTokenRequestAt = now

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.TOKEN_REQUEST,
        senderGUID = senderGUID,
    }, PROTO.CHANNEL.WHISPER, leaderTarget)
end

function comms:sendTokenUpdate(channel, target)
    if not isWarModeActive() then wipeToken("war_mode_off"); return false end
    if not isGrouped() then wipeToken("not_grouped"); return false end
    if not isLeader() then return false end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("TOKEN_UPDATE_BLOCKED reason=sender_guid_missing")
        return false
    end

    if not self.groupToken then
        self.groupToken = self:CreateGroupToken()
    end

    if not self.groupToken then
        debugLog("TOKEN_UPDATE_BLOCKED reason=token_create_failed")
        return false
    end

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.TOKEN_UPDATE,
        senderGUID = senderGUID,
        token = self.groupToken,
    }, channel or getGroupChannel(), target)
end

function comms:ensureNormalSendContext(reason)
    if not isWarModeActive() then wipeToken("war_mode_off"); return false, "war_mode_off" end
    if not isGrouped() then wipeToken("not_grouped"); return false, "not_grouped" end

    if not self.groupToken then
        if isLeader() then
            self:createAndBroadcastToken(reason or "normal_send_missing_token")
            if self.groupToken then
                return true
            end
        else
            self:sendTokenRequest(reason or "normal_send_missing_token")
        end
        return false, "token_missing"
    end

    return true
end

function comms:sendTimerSyncRequest(reason)
    local ready, readyErr = self:ensureNormalSendContext(reason or "timer_sync_request")
    if not ready then
        debugLog("TIMER_SYNC_REQUEST_BLOCKED reason=" .. tostring(readyErr))
        return false
    end

    if isLeader() then
        debugLog("TIMER_SYNC_REQUEST_BLOCKED reason=player_is_leader")
        return false
    end

    local now = serverTime()
    if self.lastTimerSyncRequestAt
        and now - self.lastTimerSyncRequestAt < PROTO.TIMER_SYNC_REQUEST_THROTTLE_SECONDS
    then
        debugLog("TIMER_SYNC_REQUEST_BLOCKED reason=throttle remaining="
            .. tostring(PROTO.TIMER_SYNC_REQUEST_THROTTLE_SECONDS - (now - self.lastTimerSyncRequestAt)))
        return false
    end

    local leaderTarget = getCurrentLeaderTarget()
    if not leaderTarget then
        debugLog("TIMER_SYNC_REQUEST_BLOCKED reason=leader_target_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("TIMER_SYNC_REQUEST_BLOCKED reason=sender_guid_missing")
        return false
    end

    self.lastTimerSyncRequestAt = now

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.TIMER_SYNC_REQUEST,
        senderGUID = senderGUID,
        groupToken = self.groupToken,
    }, PROTO.CHANNEL.WHISPER, leaderTarget)
end

function comms:sendTimerSyncResponse(target)
    local ready, readyErr = self:ensureNormalSendContext("timer_sync_response")
    if not ready then
        debugLog("TIMER_SYNC_RESPONSE_BLOCKED reason=" .. tostring(readyErr))
        return false
    end

    if not isLeader() then
        debugLog("TIMER_SYNC_RESPONSE_BLOCKED reason=player_not_leader")
        return false
    end

    if not target then
        debugLog("TIMER_SYNC_RESPONSE_BLOCKED reason=target_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("TIMER_SYNC_RESPONSE_BLOCKED reason=sender_guid_missing")
        return false
    end

    local entries = getTimerSnapshotEntries()
    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.TIMER_SYNC_RESPONSE,
        senderGUID = senderGUID,
        groupToken = self.groupToken,
        timerList = encodeTimerList(entries),
    }, PROTO.CHANNEL.WHISPER, target)
end

function comms:sendTimerDelete(zoneID)
    local ready, readyErr = self:ensureNormalSendContext("timer_delete")
    if not ready then
        debugLog("TIMER_DELETE_BLOCKED reason=" .. tostring(readyErr))
        return false
    end

    if not isLeader() then
        debugLog("TIMER_DELETE_BLOCKED reason=player_not_leader")
        return false
    end

    zoneID = tonumber(zoneID)
    if not zoneID then
        debugLog("TIMER_DELETE_BLOCKED reason=zone_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("TIMER_DELETE_BLOCKED reason=sender_guid_missing")
        return false
    end

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.TIMER_DELETE,
        senderGUID = senderGUID,
        groupToken = self.groupToken,
        zoneId = zoneID,
    }, getGroupChannel())
end

function comms:sendEnemyPresenceReport(zoneID, shardID)
    local ready, readyErr = self:ensureNormalSendContext("enemy_presence_report")
    if not ready then
        debugLogThrottled("enemy_presence_report_" .. tostring(readyErr), "ENEMY_PRESENCE_REPORT_BLOCKED reason=" .. tostring(readyErr), 30)
        return false
    end

    if not CrateRush.enemyPresence or not CrateRush.enemyPresence.canSendReports or not CrateRush.enemyPresence:canSendReports() then
        debugLog("ENEMY_PRESENCE_REPORT_BLOCKED reason=no_pending_reports")
        return false
    end

    local channel = getGroupChannel()
    if not channel then
        debugLog("ENEMY_PRESENCE_REPORT_BLOCKED reason=group_channel_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("ENEMY_PRESENCE_REPORT_BLOCKED reason=sender_guid_missing")
        return false
    end

    local entries = CrateRush.enemyPresence:consumePendingReports()
    if not entries or entries == "" then
        debugLog("ENEMY_PRESENCE_REPORT_BLOCKED reason=empty_entries")
        return false
    end

    zoneID = tonumber(zoneID)
    if not zoneID or not shardID then
        debugLog("ENEMY_PRESENCE_REPORT_BLOCKED reason=zone_or_shard_missing")
        return false
    end

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.ENEMY_PRESENCE_REPORT,
        senderGUID = senderGUID,
        groupToken = self.groupToken,
        zoneId = zoneID,
        shardId = shardID,
        entries = entries,
    }, channel)
end
function comms:sendCrateCycleAnchor(zoneID, shardID, serverEventTime)
    local ready, readyErr = self:ensureNormalSendContext("crate_cycle_anchor")
    if not ready then
        debugLog("CRATE_CYCLE_ANCHOR_BLOCKED reason=" .. tostring(readyErr))
        return false
    end

    zoneID = tonumber(zoneID)
    if not zoneID or not shardID then
        debugLog("CRATE_CYCLE_ANCHOR_BLOCKED reason=zone_or_shard_missing")
        return false
    end

    local channel = getGroupChannel()
    if not channel then
        debugLog("CRATE_CYCLE_ANCHOR_BLOCKED reason=group_channel_missing")
        return false
    end

    local senderGUID = getPlayerGUID()
    if not senderGUID then
        debugLog("CRATE_CYCLE_ANCHOR_BLOCKED reason=sender_guid_missing")
        return false
    end

    serverEventTime = tonumber(serverEventTime) or serverTime()

    return self:sendEncoded({
        v = PROTO.VERSION,
        type = PROTO.MSG.CRATE_CYCLE_ANCHOR,
        senderGUID = senderGUID,
        groupToken = self.groupToken,
        zoneId = zoneID,
        shardId = shardID,
        serverEventTime = serverEventTime,
    }, channel)
end

function comms:createAndBroadcastToken(reason)
    if not isWarModeActive() then wipeToken("war_mode_off"); return false end
    if not isGrouped() then wipeToken("not_grouped"); return false end
    if not isLeader() then return false end

    self.groupToken = self:CreateGroupToken()
    resetRequestState(reason or "leader_token_create")

    debugLog("TOKEN_CREATE reason=" .. tostring(reason)
        .. " token=" .. tostring(self.groupToken))

    return self:sendTokenUpdate(getGroupChannel())
end

function comms:refreshProtocolContext(reason)
    reason = reason or "refresh"

    if not isWarModeActive() then
        wipeToken("war_mode_off")
        return false
    end

    if not isGrouped() then
        wipeToken("not_grouped")
        return false
    end

    if reason == "init" or reason == "player_entering_world" then
        wipeToken(reason)
    end

    if isLeader() then
        local contextChanged = ensureRequestContext(reason)
        if contextChanged
            or not self.groupToken
            or reason == "init"
            or reason == "player_entering_world"
            or reason == "group_roster_update"
        then
            return self:createAndBroadcastToken(reason)
        end
        return true
    end

    if reason == "group_roster_update" then
        self.lastMemberRosterContextKey = makeContextKey() or self.lastMemberRosterContextKey
        return self.groupToken ~= nil
    end

    ensureRequestContext(reason)

    if not self.groupToken then
        return self:sendTokenRequest(reason)
    end

    return true
end

function comms:onPlayerEnteringWorld()
    self:refreshProtocolContext("player_entering_world")
end

function comms:onGroupRosterUpdate()
    self:refreshProtocolContext("group_roster_update")
end

function comms:validateBaseMessage(prefix, fields, channel)
    if prefix ~= PROTO.PREFIX then return false, "wrong_prefix" end
    if type(fields) ~= "table" then return false, "decode_failed" end
    if fields.v ~= PROTO.VERSION then return false, "unsupported_version" end
    if not isSupportedType(fields.type) then return false, "unsupported_type" end
    if not isValidManagementChannel(channel) then return false, "invalid_channel" end
    if not isWarModeActive() then wipeToken("war_mode_off"); return false, "war_mode_off" end
    if not isGrouped() then wipeToken("not_grouped"); return false, "not_grouped" end
    return true
end

function comms:validateSenderIdentity(fields, sender)
    local resolvedGUID = resolveSenderGUID(sender)
    if not resolvedGUID then return false, "sender_not_in_group" end
    if resolvedGUID ~= fields.senderGUID then return false, "sender_guid_mismatch" end
    return true
end

function comms:validateNormalMessage(fields, channel, sender)
    if not self.groupToken then return false, "local_token_missing" end
    if not fields.groupToken or fields.groupToken == "" then return false, "message_token_missing" end
    if fields.groupToken ~= self.groupToken then return false, "group_token_mismatch" end

    return self:validateSenderIdentity(fields, sender)
end

function comms:handleTokenRequest(fields, channel, sender)
    if channel ~= PROTO.CHANNEL.WHISPER then return false, "token_request_not_whisper" end
    if not isLeader() then return false, "token_request_receiver_not_leader" end

    local validSender, senderErr = self:validateSenderIdentity(fields, sender)
    if not validSender then return false, senderErr end

    if fields.senderGUID == getPlayerGUID() then return false, "token_request_from_leader" end

    if not self.groupToken then
        self.groupToken = self:CreateGroupToken()
        debugLog("TOKEN_CREATE reason=request token=" .. tostring(self.groupToken))
    end

    if not self.groupToken then return false, "token_missing" end
    return self:sendTokenUpdate(PROTO.CHANNEL.WHISPER, sender), nil
end

function comms:handleTokenUpdate(fields, channel, sender)
    if not isValidManagementChannel(channel) then return false, "token_update_bad_channel" end
    if not fields.token or fields.token == "" then return false, "token_update_missing_token" end

    local validSender, senderErr = self:validateSenderIdentity(fields, sender)
    if not validSender then return false, senderErr end

    local leaderGUID = getCurrentLeaderGUID()
    if not leaderGUID or fields.senderGUID ~= leaderGUID then
        return false, "token_update_sender_not_leader"
    end

    self.groupToken = fields.token
    resetRequestState("token_update")
    debugLog("TOKEN_ACCEPT channel=" .. tostring(channel)
        .. " senderGUID=" .. tostring(fields.senderGUID))
    self:sendTimerSyncRequest("token_update")
    return true
end

function comms:handleTimerSyncRequest(fields, channel, sender)
    if channel ~= PROTO.CHANNEL.WHISPER then return false, "timer_sync_request_not_whisper" end
    if not isLeader() then return false, "timer_sync_request_receiver_not_leader" end

    local validSender, senderErr = self:validateNormalMessage(fields, channel, sender)
    if not validSender then return false, senderErr end

    if fields.senderGUID == getPlayerGUID() then
        return false, "timer_sync_request_from_leader"
    end

    return self:sendTimerSyncResponse(sender), nil
end

function comms:handleTimerSyncResponse(fields, channel, sender)
    if channel ~= PROTO.CHANNEL.WHISPER then return false, "timer_sync_response_not_whisper" end

    local validSender, senderErr = self:validateNormalMessage(fields, channel, sender)
    if not validSender then return false, senderErr end

    local leaderGUID = getCurrentLeaderGUID()
    if not leaderGUID or fields.senderGUID ~= leaderGUID then
        return false, "timer_sync_response_sender_not_leader"
    end

    local entries, timerErr = decodeTimerList(fields.timerList)
    if not entries then return false, timerErr end

    if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT and CrateRush.DOMAIN_EVENT.TIMER_SYNC_RECEIVED then
        CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.TIMER_SYNC_RECEIVED, {
            senderGUID = fields.senderGUID,
            timers     = entries,
        })
    end

    debugLog("TIMER_SYNC_ACCEPT timers=" .. tostring(#entries)
        .. " senderGUID=" .. tostring(fields.senderGUID))
    return true
end

function comms:handleTimerDelete(fields, channel, sender)
    if not isValidGroupChannel(channel) then return false, "timer_delete_not_group_channel" end

    local validSender, senderErr = self:validateNormalMessage(fields, channel, sender)
    if not validSender then return false, senderErr end

    local leaderGUID = getCurrentLeaderGUID()
    if not leaderGUID or fields.senderGUID ~= leaderGUID then
        return false, "timer_delete_sender_not_leader"
    end

    local zoneID = tonumber(fields.zoneId)
    if not zoneID then return false, "timer_delete_missing_zone" end

    if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT and CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED then
        CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED, {
            zoneID = zoneID,
            reason = CrateRush.TIMER_REMOVE_REASON and CrateRush.TIMER_REMOVE_REASON.GROUP_TIMER_DELETE or "group_timer_delete",
            source = PROTO.MSG.TIMER_DELETE,
        })
    end

    debugLog("TIMER_DELETE_ACCEPT zone=" .. tostring(zoneID)
        .. " senderGUID=" .. tostring(fields.senderGUID))
    return true
end

function comms:handleCrateCycleAnchor(fields, channel, sender)
    if not isValidGroupChannel(channel) then return false, "crate_cycle_anchor_not_group_channel" end

    local validSender, senderErr = self:validateNormalMessage(fields, channel, sender)
    if not validSender then return false, senderErr end
    if fields.senderGUID == getPlayerGUID() then
        debugLog("CRATE_CYCLE_ANCHOR_IGNORED reason=self_echo")
        return true
    end

    local zoneID = tonumber(fields.zoneId)
    local shardID = fields.shardId
    local serverEventTime = tonumber(fields.serverEventTime)
    if not zoneID or not shardID or not serverEventTime then
        return false, "crate_cycle_anchor_missing_fields"
    end

    if not CrateRush.crateLifecycle or not CrateRush.crateLifecycle.transition then
        return false, "crate_lifecycle_missing"
    end

    local accepted = CrateRush.crateLifecycle:transition(
        zoneID,
        shardID,
        CrateRush.CRATE_STATE.DETECTED,
        nil,
        nil,
        CrateRush.CRATE_SOURCE.CRATE_CYCLE_ANCHOR,
        serverEventTime
    )

    debugLog("CRATE_CYCLE_ANCHOR_ACCEPT zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " serverEventTime=" .. tostring(serverEventTime)
        .. " accepted=" .. tostring(accepted)
        .. " senderGUID=" .. tostring(fields.senderGUID))

    return true
end

function comms:handleEnemyPresenceReport(fields, channel, sender)
    if not isValidGroupChannel(channel) then return false, "enemy_presence_not_group_channel" end

    local validSender, senderErr = self:validateNormalMessage(fields, channel, sender)
    if not validSender then return false, senderErr end
    if fields.senderGUID == getPlayerGUID() then
        debugLog("ENEMY_PRESENCE_REPORT_IGNORED reason=self_echo")
        return true
    end

    local zoneID = tonumber(fields.zoneId)
    local shardID = fields.shardId
    if not zoneID or not shardID or not fields.entries then
        return false, "enemy_presence_missing_fields"
    end

    if not CrateRush.enemyPresence or not CrateRush.enemyPresence.applyRemoteReport then
        return false, "enemy_presence_missing"
    end

    local accepted, reason = CrateRush.enemyPresence:applyRemoteReport(fields.senderGUID, zoneID, shardID, fields.entries)
    if not accepted then return false, reason end

    debugLog("ENEMY_PRESENCE_REPORT_ACCEPT zone=" .. tostring(zoneID)
        .. " shard=" .. tostring(shardID)
        .. " senderGUID=" .. tostring(fields.senderGUID))
    return true
end
function comms:onReceive(prefix, message, channel, sender)
    local fields, decodeErr = decodeFields(message)
    local valid, reason = self:validateBaseMessage(prefix, fields, channel)
    if not valid then
        debugLog("RECEIVE_IGNORED reason=" .. tostring(reason or decodeErr)
            .. " channel=" .. tostring(channel)
            .. " sender=" .. tostring(sender))
        return false
    end

    local ok, err
    if fields.type == PROTO.MSG.TOKEN_REQUEST then
        ok, err = self:handleTokenRequest(fields, channel, sender)
    elseif fields.type == PROTO.MSG.TOKEN_UPDATE then
        ok, err = self:handleTokenUpdate(fields, channel, sender)
    elseif fields.type == PROTO.MSG.TIMER_SYNC_REQUEST then
        ok, err = self:handleTimerSyncRequest(fields, channel, sender)
    elseif fields.type == PROTO.MSG.TIMER_SYNC_RESPONSE then
        ok, err = self:handleTimerSyncResponse(fields, channel, sender)
    elseif fields.type == PROTO.MSG.TIMER_DELETE then
        ok, err = self:handleTimerDelete(fields, channel, sender)
    elseif fields.type == PROTO.MSG.CRATE_CYCLE_ANCHOR then
        ok, err = self:handleCrateCycleAnchor(fields, channel, sender)
    elseif fields.type == PROTO.MSG.ENEMY_PRESENCE_REPORT then
        ok, err = self:handleEnemyPresenceReport(fields, channel, sender)
    end

    if not ok then
        debugLog("RECEIVE_IGNORED type=" .. tostring(fields.type)
            .. " reason=" .. tostring(err)
            .. " channel=" .. tostring(channel)
            .. " sender=" .. tostring(sender))
        return false
    end

    return true
end

function comms:send(msgType, payload)
    if msgType == PROTO.MSG.TIMER_SYNC_REQUEST then
        return self:sendTimerSyncRequest(type(payload) == "table" and payload.reason or "manual")
    elseif msgType == PROTO.MSG.TIMER_SYNC_RESPONSE then
        return self:sendTimerSyncResponse(type(payload) == "table" and payload.target or nil)
    elseif msgType == PROTO.MSG.TIMER_DELETE then
        return self:sendTimerDelete(type(payload) == "table" and (payload.zoneID or payload.zoneId) or payload)
    elseif msgType == PROTO.MSG.CRATE_CYCLE_ANCHOR then
        if type(payload) ~= "table" then
            debugLog("SEND_UNSUPPORTED type=" .. tostring(msgType) .. " reason=payload_missing")
            return false
        end
        return self:sendCrateCycleAnchor(payload.zoneID or payload.zoneId, payload.shardID or payload.shardId, payload.serverEventTime)
    elseif msgType == PROTO.MSG.ENEMY_PRESENCE_REPORT then
        if type(payload) ~= "table" then
            debugLog("SEND_UNSUPPORTED type=" .. tostring(msgType) .. " reason=payload_missing")
            return false
        end
        return self:sendEnemyPresenceReport(payload.zoneID or payload.zoneId, payload.shardID or payload.shardId)
    end

    debugLog("SEND_UNSUPPORTED type=" .. tostring(msgType) .. " phase=timer_sync_protocol")
    return false
end

CrateRush.API = CrateRush.API or {}

function CrateRush.API.reportCrateSpotted()
    debugLog("API_UNSUPPORTED method=reportCrateSpotted phase=timer_sync_protocol")
    return false
end
