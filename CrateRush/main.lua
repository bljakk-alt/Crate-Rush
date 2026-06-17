-- CrateRush
-- main.lua - Entry point. Bootstraps all modules.

CrateRush = CrateRush or {}
CrateRush.displayName = "Crate Rush"
CrateRush.version = "0.9.1"
CrateRush.versionLabel = CrateRush.displayName .. " " .. CrateRush.version

function CrateRush.logDebug(message)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log(message)
    end
end

local function getChatPrefixColor()
    local factionKey = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or nil

    if factionKey == "ALLIANCE" then
        return "3fa7ff"
    end
    return "ff3b32"
end

function CrateRush:Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff" .. getChatPrefixColor() .. "CrateRush|r " .. tostring(message or ""))
    else
        CrateRush.logDebug("CrateRush " .. tostring(message or ""))
    end
end

local function getAddonMetadata(addonName, field)
    if not addonName or not field then return nil end

    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, addonName, field)
        if ok and value then return value end
    end

    if GetAddOnMetadata then
        local ok, value = pcall(GetAddOnMetadata, addonName, field)
        if ok and value then return value end
    end

    return nil
end

local function applyAddonMetadata(addonName)
    CrateRush.addonName = addonName or CrateRush.addonName or "CrateRush"
    CrateRush.displayName = getAddonMetadata(CrateRush.addonName, "Title")
        or CrateRush.displayName
        or CrateRush.addonName
    CrateRush.version = getAddonMetadata(CrateRush.addonName, "Version")
        or CrateRush.version
        or "unknown"
    CrateRush.versionLabel = CrateRush.displayName .. " " .. CrateRush.version
end

local function applyThemeToUI()
    if CrateRush.frames and CrateRush.frames.applyTheme then
        CrateRush.frames:applyTheme()
    end
    if CrateRush.timerbars and CrateRush.timerbars.applyTheme then
        CrateRush.timerbars:applyTheme()
    end
    if CrateRush.cockpit and CrateRush.cockpit.applyTheme then
        CrateRush.cockpit:applyTheme()
    end
    if CrateRush.configDialog and CrateRush.configDialog.applyTheme then
        CrateRush.configDialog:applyTheme()
    end
end

local lastWarModeWarningAt = 0

local function getActivationMode()
    if CrateRush.config and CrateRush.config.get then
        return CrateRush.config:get("activationMode", "warMode")
    end
    return "warMode"
end

local function isWarModeEnabled()
    return CrateRush.playerContext
        and CrateRush.playerContext.isWarModeEnabled
        and CrateRush.playerContext:isWarModeEnabled()
        or false
end

local function shouldShowMainFrame()
    local mode = getActivationMode()
    if mode == "disabled" then return false end
    if mode == "always" then return true end
    return isWarModeEnabled()
end

local function warnWarModeOffIfNeeded()
    if getActivationMode() ~= "warMode" then return end
    if isWarModeEnabled() then return end
    if not CrateRush.config or not CrateRush.config.getBoolean then return end
    if not CrateRush.config:getBoolean("warnWhenWarModeOff", false) then return end

    local now = CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or 0
    if now > 0 and now - lastWarModeWarningAt < 30 then return end
    lastWarModeWarningAt = now

    local message = "CrateRush is inactive because War Mode is off."
    if CrateRush.warningframe and CrateRush.warningframe.show then
        CrateRush.warningframe:show(message)
    elseif CrateRush.Print then
        CrateRush:Print(message)
    end
end

local function applyMainFrameActivation()
    if not CrateRush.frames then return end

    if shouldShowMainFrame() then
        CrateRush.frames:show()
    elseif CrateRush.frames.hide then
        CrateRush.frames:hide()
        warnWarModeOffIfNeeded()
    end
end

local playerContextChangedSubscriber = nil
local configChangedSubscriber = nil

local function subscribePlayerContextChanged()
    if not CrateRush.domainEvents
        or not CrateRush.DOMAIN_EVENT
        or not CrateRush.DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED
    then
        return
    end

    if playerContextChangedSubscriber then
        CrateRush.domainEvents:unsubscribe(playerContextChangedSubscriber)
    end

    playerContextChangedSubscriber = CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED,
        CrateRush,
        "OnPlayerContextChanged"
    )
end

local function subscribeConfigChanged()
    if not CrateRush.domainEvents
        or not CrateRush.DOMAIN_EVENT
        or not CrateRush.DOMAIN_EVENT.CONFIG_CHANGED
    then
        return
    end

    if configChangedSubscriber then
        CrateRush.domainEvents:unsubscribe(configChangedSubscriber)
    end

    configChangedSubscriber = CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.CONFIG_CHANGED,
        CrateRush,
        "OnConfigChanged"
    )
end

local function configureDebug()
    return
end

-- Register AceComm directly (no AceAddon mixin needed)
local AceComm = LibStub("AceComm-3.0")
AceComm:Embed(CrateRush)

local function onInitialize(addonName)
    applyAddonMetadata(addonName)

    CrateRushDB = CrateRushDB or {}
    CrateRushDebugDB = CrateRushDebugDB or {}
    CrateRush.storage:init(CrateRushDB)
    CrateRush.config:init(CrateRush.storage)
    subscribePlayerContextChanged()
    subscribeConfigChanged()
    if CrateRush.playerContext and CrateRush.playerContext.init then
        CrateRush.playerContext:init()
    end
    if CrateRush.theme and CrateRush.theme.init then
        CrateRush.theme:init()
    end

    -- Apply persisted filter IDs immediately so debug log is filtered from the start
    configureDebug()

    CrateRush.onDebugFilterChanged = function(filteredIDs)
        if CrateRush.storage and CrateRush.storage.setFilterIDs then
            CrateRush.storage:setFilterIDs(filteredIDs)
        end
    end

    -- Restore timers from saved history
    CrateRush.timers:restore()

    if CrateRush.comms and CrateRush.comms.init then
        CrateRush.comms:init()
    end
    if CrateRush.enemyPresence and CrateRush.enemyPresence.init then
        CrateRush.enemyPresence:init()
    end

    -- Slash command
    SLASH_CRATERUSH1 = "/cr"
    SlashCmdList["CRATERUSH"] = function(msg)
        CrateRush:SlashCommand(msg)
    end

    CrateRush.logDebug(CrateRush.versionLabel .. " loaded. Type /cr for help.")
    applyMainFrameActivation()
end

function CrateRush:OnCommReceived(prefix, message, distribution, sender)
    if CrateRush.comms and CrateRush.comms.onReceive then
        return CrateRush.comms:onReceive(prefix, message, distribution, sender)
    end
    return false
end

function CrateRush:OnPlayerContextChanged()
    if CrateRush.theme and CrateRush.theme.init then
        CrateRush.theme:init()
    end

    applyThemeToUI()
    applyMainFrameActivation()
end

function CrateRush:OnConfigChanged(payload)
    local key = payload and payload.key or nil

    if key == "factionOverride"
        and CrateRush.playerContext
        and CrateRush.playerContext.refresh
    then
        CrateRush.playerContext:refresh(CrateRush.DOMAIN_EVENT.CONFIG_CHANGED)
    end

    if key == "factionOverride" or key == "showWarmodeIndicator" then
        if CrateRush.theme and CrateRush.theme.init then
            CrateRush.theme:init()
        end
        applyThemeToUI()
    end

    if key == "activationMode" or key == "warnWhenWarModeOff" then
        applyMainFrameActivation()
    end

    if CrateRush.configDialog and CrateRush.configDialog.refresh then
        CrateRush.configDialog:refresh()
    end
end

local function printCrateRushMessage(message)
    CrateRush:Print(message)
end

function CrateRush:SetFactionOverride(factionKey)
    if not CrateRush.playerContext or not CrateRush.playerContext.setFactionOverride then
        printCrateRushMessage("Faction override is not available yet.")
        return false
    end

    if not CrateRush.playerContext:setFactionOverride(factionKey) then
        printCrateRushMessage("Unknown faction.")
        return false
    end

    printCrateRushMessage("Faction theme forced to " .. CrateRush.playerContext:getFaction() .. ".")
    return true
end

function CrateRush:ClearFactionOverride()
    if CrateRush.playerContext and CrateRush.playerContext.clearFactionOverride then
        CrateRush.playerContext:clearFactionOverride()
    end

    printCrateRushMessage("Faction theme returned to automatic detection.")
end

function CrateRush:SlashCommand(msg)
    local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if cmd == "config" then
        if CrateRush.configDialog then
            CrateRush.configDialog:toggle()
        end
    elseif cmd == "display" then
        CrateRush.frames:toggle()
    elseif cmd == "auto" or cmd == "faction auto" then
        CrateRush:ClearFactionOverride()
    else
        CrateRush.logDebug(CrateRush.versionLabel)
        CrateRush.logDebug("  /cr config  - open configuration")
        CrateRush.logDebug("  /cr display - toggle main display")
        CrateRush.logDebug("  /cr auto    - use detected player faction")
    end
end

-- Bootstrap via ADDON_LOADED event
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "CrateRush" then
        onInitialize(addonName)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
