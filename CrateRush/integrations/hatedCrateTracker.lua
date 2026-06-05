-- CrateRush
-- integrations/hatedCrateTracker.lua — Bridge to HatedCrateTracker via AceEvent.
-- Optional. Gracefully skipped if HatedCrateTracker is not installed.

local hct = {}
CrateRush.integrations = CrateRush.integrations or {}
CrateRush.integrations.hatedCrateTracker = hct

function hct:init()
    if not HatedCrateTracker then return end  -- graceful degradation
    -- Subscribe to HatedCrateTracker AceEvents
end
