-- CrateRush
-- logic/announcements/router.lua - Fan-out for finalized announcements.

local router = {}
CrateRush.announcementRouter = router

local sinks = {}
local sinkOrder = {}

local function logError(name, err)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("ANNOUNCE SINK ERROR | sink=" .. tostring(name) .. " err=" .. tostring(err))
    end
end

function router:registerSink(name, sink)
    if not name or type(sink) ~= "table" or type(sink.send) ~= "function" then return false end
    if not sinks[name] then
        sinkOrder[#sinkOrder + 1] = name
    end
    sinks[name] = sink
    return true
end

function router:route(announcement)
    if type(announcement) ~= "table" or not announcement.message then return 0 end

    local delivered = 0
    for _, name in ipairs(sinkOrder) do
        local sink = sinks[name]
        local enabled = sink ~= nil
        if enabled and sink.isEnabled then
            local ok, result = pcall(sink.isEnabled, sink, announcement)
            if ok then
                enabled = result
            else
                enabled = false
                logError(name, result)
            end
        end
        if enabled then
            local ok, result = pcall(sink.send, sink, announcement)
            if ok then
                if result ~= false then delivered = delivered + 1 end
            else
                logError(name, result)
            end
        end
    end

    return delivered
end

function router:getSinks()
    return sinks
end
