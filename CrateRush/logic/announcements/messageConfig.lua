-- CrateRush
-- logic/announcements/messageConfig.lua - Config-backed announcement templates and placeholder expansion.

local messageConfig = {}
CrateRush.announcementMessageConfig = messageConfig

local function getDefinition(messageID)
    local byID = CrateRush.ANNOUNCEMENT_MESSAGE_BY_ID or {}
    return byID[messageID]
end

local function getConfigValue(key, fallback)
    if CrateRush.config and CrateRush.config.get then
        local value = CrateRush.config:get(key, fallback)
        if value ~= nil then return value end
    end
    return fallback
end

local function getConfigBoolean(key, fallback)
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean(key, fallback)
    end
    return fallback
end

local function addFactionTokens(tokens)
    tokens = type(tokens) == "table" and tokens or {}

    local factionKey = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or nil

    local myFaction = CrateRush.resolveFactionName
        and CrateRush.resolveFactionName(factionKey)
        or nil

    local oppositeKey = CrateRush.getOppositeFactionKey
        and CrateRush.getOppositeFactionKey(factionKey)
        or nil

    local oppositeFaction = CrateRush.resolveFactionName
        and CrateRush.resolveFactionName(oppositeKey)
        or nil

    if tokens["%my_faction%"] == nil then
        tokens["%my_faction%"] = myFaction or ""
    end
    if tokens["%opposite_faction%"] == nil then
        tokens["%opposite_faction%"] = oppositeFaction or ""
    end

    return tokens
end

local function addDefaultTokens(tokens)
    tokens = type(tokens) == "table" and tokens or {}
    for _, placeholder in ipairs(CrateRush.ANNOUNCEMENT_PLACEHOLDERS or {}) do
        if tokens[placeholder] == nil then
            tokens[placeholder] = ""
        end
    end
    return tokens
end
local function cleanMessage(message)
    message = tostring(message or "")
    message = message:gsub("%s+", " ")
    message = message:gsub("%s+$", "")
    message = message:gsub("^%s+", "")
    message = message:gsub("%s+([,.!?:;])", "%1")
    return message
end

function messageConfig:getDefinition(messageID)
    return getDefinition(messageID)
end

function messageConfig:getDefinitionByCockpitTrigger(trigger)
    local byTrigger = CrateRush.ANNOUNCEMENT_MESSAGE_BY_COCKPIT_TRIGGER or {}
    return byTrigger[trigger]
end

function messageConfig:getMessageIDByCockpitTrigger(trigger, fallback)
    local definition = self:getDefinitionByCockpitTrigger(trigger)
    return definition and definition.id or fallback
end

function messageConfig:getCatalog()
    return CrateRush.ANNOUNCEMENT_MESSAGE_CATALOG or {}
end

function messageConfig:getPlaceholders()
    return CrateRush.ANNOUNCEMENT_PLACEHOLDERS or {}
end

function messageConfig:getSettings(messageID)
    local definition = getDefinition(messageID)
    if not definition then return nil end
    local keys = definition.keys or {}
    local defaults = definition.defaultOutputs or {}

    return {
        id              = messageID,
        enabled         = getConfigBoolean(keys.enabled, definition.defaultEnabled ~= false),
        template        = getConfigValue(keys.template, definition.defaultTemplate or ""),
        defaultChatFrame = getConfigBoolean(keys.defaultChatFrame, defaults.defaultChatFrame ~= false),
        warningFrame     = getConfigBoolean(keys.warningFrame, defaults.warningFrame ~= false),
        partyRaid        = getConfigBoolean(keys.partyRaid, defaults.partyRaid ~= false),
        raidWarning      = getConfigBoolean(keys.raidWarning, defaults.raidWarning == true),
    }
end

function messageConfig:isEnabled(messageID)
    local settings = self:getSettings(messageID)
    if not settings then return true end
    return settings.enabled ~= false
end

function messageConfig:isOutputEnabled(messageID, outputName, fallback)
    if not messageID then return fallback ~= false end
    local settings = self:getSettings(messageID)
    if not settings then return fallback ~= false end
    if settings[outputName] == nil then return fallback ~= false end
    return settings[outputName] == true
end

function messageConfig:format(messageID, tokens, fallbackTemplate)
    local definition = getDefinition(messageID)
    if definition and not self:isEnabled(messageID) then return nil end

    tokens = addFactionTokens(tokens)
    tokens = addDefaultTokens(tokens)
    local template = fallbackTemplate
    if definition then
        local settings = self:getSettings(messageID)
        template = settings and settings.template or definition.defaultTemplate or fallbackTemplate
    end

    if type(template) ~= "string" or template == "" then return nil end

    local message = template:gsub("%%[%w_]+%%", function(token)
        local value = tokens[token]
        if value == nil then return "" end
        return tostring(value)
    end)

    return cleanMessage(message)
end
