-- CrateRush
-- comms/comms.lua — Addon-to-addon communication via AceEvent.
-- Handles encode/decode, version broadcasting, sync, and public API.

local comms = {}
CrateRush.comms = comms

function comms:init()
    -- Register AceComm prefix and AceEvent listeners.
end

function comms:send(msgType, payload, channel)
    -- Encode and broadcast a message to the given channel (RAID, PARTY, YELL, etc).
end

function comms:onReceive(prefix, message, channel, sender)
    -- Decode incoming message and delegate to appropriate handler.
end

function comms:broadcastVersion()
    -- Broadcast current addon version to group/raid.
end

-- Public API — callable by other addons
CrateRush.API = {}

function CrateRush.API.reportCrateSpotted(zoneID, x, y)
    -- External addons (e.g. HatedCrateTracker) call this to report a crate.
end
