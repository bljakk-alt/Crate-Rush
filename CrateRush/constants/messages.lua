-- CrateRush
-- constants/messages.lua - Named constants for user-facing messages and announcement configuration.

local L = CrateRush.L
local DOMAIN_EVENT = CrateRush.DOMAIN_EVENT or {}
local MSG = {}
CrateRush.MSG = MSG

MSG.ADDON_LOADED     = L["ADDON_LOADED"]
MSG.WARMODE_REQUIRED = L["WARMODE_REQUIRED"]

local MESSAGE_ID = {
    CRATE_DETECTED  = "crate_detected",
    CRATE_DROPPING  = "crate_dropping",
    CRATE_LANDED    = "crate_landed",
    CRATE_CLAIMED   = "crate_claimed",
    PREDICTION      = "prediction",
    ENEMY_PRESENCE = "enemy_presence",
    AUTO_TIMER_SOON = "auto_timer_soon",
    SHARD_CHANGED  = "shard_changed",
}
CrateRush.ANNOUNCEMENT_MESSAGE_ID = MESSAGE_ID

local ANCHOR_TYPE = {
    EVENT = "event",
    TIMER = "timer",
}
CrateRush.ANNOUNCEMENT_ANCHOR_TYPE = ANCHOR_TYPE

local COCKPIT_TRIGGER = {
    STATE_BOX_SHIFT_CLICK       = "state_box_shift_click",
    PREDICTION_BOX_SHIFT_CLICK  = "prediction_box_shift_click",
    TIMING_BOX_SHIFT_CLICK      = "timing_box_shift_click",
    ENEMY_BOX_SHIFT_CLICK       = "enemy_box_shift_click",
}
CrateRush.ANNOUNCEMENT_COCKPIT_TRIGGER = COCKPIT_TRIGGER

CrateRush.ANNOUNCEMENT_PLACEHOLDERS = {
    "%zone%",
    "%shard%",
    "%old_shard%",
    "%new_shard%",
    "%state%",
    "%coords%",
    "%map_pin%",
    "%time_to_next%",
    "%time_to_drop%",
    "%time_to_land%",
    "%time_to_claim%",
    "%time_to_loot%",
    "%claimed_by_faction%",
    "%my_faction%",
    "%opposite_faction%",
    "%enemy_total%",
    "%healers%",
}

local function keys(id)
    local prefix = "announcement_" .. id .. "_"
    return {
        enabled          = prefix .. "enabled",
        template         = prefix .. "template",
        defaultChatFrame = prefix .. "default_chat_frame",
        warningFrame     = prefix .. "warning_frame",
        partyRaid        = prefix .. "party_raid",
        raidWarning      = prefix .. "raid_warning",
        leadSeconds      = prefix .. "lead_seconds",
    }
end

local function message(id, title, template, enabled, outputs, meta)
    outputs = outputs or {}
    meta = meta or {}
    return {
        id              = id,
        title           = title,
        defaultTemplate = template,
        defaultEnabled  = enabled ~= false,
        defaultOutputs  = {
            defaultChatFrame = outputs.defaultChatFrame ~= false,
            warningFrame     = outputs.warningFrame ~= false,
            partyRaid        = outputs.partyRaid ~= false,
            raidWarning      = outputs.raidWarning == true,
        },
        anchor            = meta.anchor,
        cockpitTriggers   = meta.cockpitTriggers or {},
        automaticDelivery = meta.automaticDelivery,
        manualDelivery    = meta.manualDelivery,
        timerLeadSeconds = meta.timerLeadSeconds,
        configurable      = meta.configurable ~= false,
        keys              = keys(id),
    }
end

local CATALOG = {
    message(
        MESSAGE_ID.CRATE_DETECTED,
        "Crate Detected",
        "War Supply Crate detected flying in %zone% [shard %shard%]",
        true
    ),
    message(
        MESSAGE_ID.CRATE_DROPPING,
        "Crate Dropping",
        "War Supply Crate dropping in %zone% [shard %shard%] at %coords% %map_pin%",
        true
    ),
    message(
        MESSAGE_ID.CRATE_LANDED,
        "Crate Landed",
        "War Supply Crate LANDED in %zone% [shard %shard%] - GO NOW! at %coords% %map_pin%",
        true
    ),
    message(
        MESSAGE_ID.CRATE_CLAIMED,
        "Crate Claimed",
        "War Supply Crate claimed by %claimed_by_faction% in %zone% [shard %shard%]",
        true
    ),
    message(
        MESSAGE_ID.PREDICTION,
        "Prediction",
        "Predicted drop in %zone% at %coords% %map_pin% drop %time_to_drop% land %time_to_land%",
        true,
        { defaultChatFrame = false, warningFrame = false, partyRaid = false, raidWarning = false },
        {
            anchor = {
                type = ANCHOR_TYPE.EVENT,
                event = DOMAIN_EVENT.PREDICTION_UPDATED or "predictionUpdated",
            },
            cockpitTriggers = {
                COCKPIT_TRIGGER.PREDICTION_BOX_SHIFT_CLICK,
                COCKPIT_TRIGGER.TIMING_BOX_SHIFT_CLICK,
            },
            automaticDelivery = {
                leaderGated = true,
                raidWarningAllowed = true,
            },
            manualDelivery = {
                bypassLeaderGate = true,
                raidWarningAllowed = false,
            },
        }
    ),
    message(
        MESSAGE_ID.ENEMY_PRESENCE,
        "Enemy Presence",
        "Enemy presence in %zone%: %enemy_total% enemies, %healers% healers",
        true,
        nil,
        {
            cockpitTriggers = {
                COCKPIT_TRIGGER.ENEMY_BOX_SHIFT_CLICK,
            },
            manualDelivery = {
                bypassLeaderGate = true,
                raidWarningAllowed = false,
            },
        }
    ),
    message(
        MESSAGE_ID.AUTO_TIMER_SOON,
        "Upcoming Crate",
        "Next Crate in %zone% in %time_to_next%",
        false,
        { defaultChatFrame = false, warningFrame = false, partyRaid = true },
        {
            anchor = {
                type = ANCHOR_TYPE.TIMER,
            },
            timerLeadSeconds = 30,
            automaticDelivery = {
                leaderGated = true,
                raidWarningAllowed = true,
            },
        }
    ),
    message(
        MESSAGE_ID.SHARD_CHANGED,
        "Shard Changed",
        "Shard changed in %zone%: old %old_shard%, new %new_shard%",
        false,
        { defaultChatFrame = false, warningFrame = true, partyRaid = true },
        {
            anchor = {
                type = ANCHOR_TYPE.EVENT,
                event = DOMAIN_EVENT.ZONE_SHARD_CHANGED or "zoneShardChanged",
            },
            automaticDelivery = {
                leaderGated = true,
                raidWarningAllowed = true,
            },
        }
    ),
}
CrateRush.ANNOUNCEMENT_MESSAGE_CATALOG = CATALOG

local BY_ID = {}
local BY_COCKPIT_TRIGGER = {}
for _, definition in ipairs(CATALOG) do
    BY_ID[definition.id] = definition
    for _, trigger in ipairs(definition.cockpitTriggers or {}) do
        BY_COCKPIT_TRIGGER[trigger] = definition
    end
end
CrateRush.ANNOUNCEMENT_MESSAGE_BY_ID = BY_ID
CrateRush.ANNOUNCEMENT_MESSAGE_BY_COCKPIT_TRIGGER = BY_COCKPIT_TRIGGER