-- CrateRush
-- utils/clock.lua - Shared server-time clock for domain, storage, telemetry, and comms.

local clock = {}
CrateRush.clock = clock

function clock:serverTime()
    if GetServerTime then
        local ok, value = pcall(GetServerTime)
        if ok and value then
            return value
        end
    end

    if time then
        return time()
    end

    return 0
end

function clock:now()
    return clock:serverTime()
end
