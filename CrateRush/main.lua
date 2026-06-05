-- CrateRush
-- main.lua — Entry point. Bootstraps all modules.

CrateRush = CrateRush or {}
CrateRush.version = "0.1.0"

-- Register AceComm directly (no AceAddon mixin needed)
local AceComm = LibStub("AceComm-3.0")
AceComm:Embed(CrateRush)

local function onInitialize()
    -- Native SavedVariables
    CrateRushDB = CrateRushDB or {}
    CrateRushDB.profile = CrateRushDB.profile or {
        enabled          = true,
        showWarningFrame = true,
        showTimerbars    = true,
        announceInChat   = true,
        announceInRaid   = true,
        filterIDs        = {},
        crateHistory     = {},
        shardConfirmCount = CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT,
        ambiguousShardConfirmCount = CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT,
        debugState       = {
            fontSize = 11,
            x        = nil,
            y        = nil,
            width    = 700,
            height   = 400,
        },
    }

    CrateRush.storage:init(CrateRushDB)
    CrateRush.config:init(CrateRush.storage)

    -- Apply persisted filter IDs immediately so debug log is filtered from the start
    CrateRush.debug:applyFilters(CrateRush.storage:getFilterIDs())
    CrateRush.debug:applyState(CrateRush.config:get("debugState"))
    CrateRush.debug:setSaveCallback(function(state)
        CrateRush.config:set("debugState", state)
    end)

    CrateRush.onDebugFilterChanged = function(filteredIDs)
        CrateRush.storage:setFilterIDs(filteredIDs)
    end

    -- Restore timers from saved history
    CrateRush.timers:restore()

    -- Register HatedCrateTracker comms prefix
    CrateRush:RegisterComm("RCT", "OnCommReceived")

    -- Slash command
    SLASH_CRATERUSH1 = "/cr"
    SlashCmdList["CRATERUSH"] = function(msg)
        CrateRush:SlashCommand(msg)
    end

    CrateRush.debug:log("CrateRush v" .. CrateRush.version .. " loaded. Type /cr for help.")
    CrateRush.frames:show()
end

function CrateRush:OnCommReceived(prefix, message, distribution, sender)
    -- Delegate to comms module when ready
end

function CrateRush:SlashCommand(msg)
    local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if cmd == "debug" then
        CrateRush.debug:toggle()
    elseif cmd == "display" then
        CrateRush.frames:toggle()
    else
        CrateRush.debug:log("CrateRush v" .. CrateRush.version)
        CrateRush.debug:log("  /cr debug   — toggle debug window")
        CrateRush.debug:log("  /cr display — toggle main display")
    end
end

-- Bootstrap via ADDON_LOADED event
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "CrateRush" then
        onInitialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
