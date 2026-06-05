-- CrateRush
-- logic/domainEvents.lua - Small synchronous domain event bus.

local domainEvents = {}
CrateRush.domainEvents = domainEvents

local subscribers = {}

local function isValidEventName(eventName)
    return type(eventName) == "string" and eventName ~= ""
end

local function reportError(eventName, err)
    if CrateRush.debug and CrateRush.debug.log then
        CrateRush.debug:log("DOMAIN EVENT ERROR | event=" .. tostring(eventName) .. " err=" .. tostring(err))
    end
end

local function createSubscriber(eventName, ownerOrHandler, handlerOrMethod)
    if type(ownerOrHandler) == "function" and handlerOrMethod == nil then
        return {
            eventName = eventName,
            owner     = nil,
            handler   = ownerOrHandler,
        }
    end

    if type(ownerOrHandler) == "table"
        and (type(handlerOrMethod) == "function" or type(handlerOrMethod) == "string")
    then
        return {
            eventName = eventName,
            owner     = ownerOrHandler,
            handler   = handlerOrMethod,
        }
    end

    return nil
end

local function callSubscriber(subscriber, payload, eventName)
    if not subscriber then return false end

    local handler = subscriber.handler
    local owner = subscriber.owner

    if type(handler) == "string" then
        if type(owner) ~= "table" or type(owner[handler]) ~= "function" then
            return false
        end
        local ok, err = pcall(owner[handler], owner, payload, eventName)
        if not ok then
            reportError(eventName, err)
        end
        return ok
    end

    if type(handler) ~= "function" then return false end

    local ok, err
    if owner then
        ok, err = pcall(handler, owner, payload, eventName)
    else
        ok, err = pcall(handler, payload, eventName)
    end

    if not ok then
        reportError(eventName, err)
    end

    return ok
end

function domainEvents:subscribe(eventName, ownerOrHandler, handlerOrMethod)
    if not isValidEventName(eventName) then return nil end

    local subscriber = createSubscriber(eventName, ownerOrHandler, handlerOrMethod)
    if not subscriber then return nil end

    subscribers[eventName] = subscribers[eventName] or {}
    subscribers[eventName][subscriber] = true

    return subscriber
end

function domainEvents:unsubscribe(subscriber)
    if not subscriber or not subscriber.eventName then return false end

    local eventSubscribers = subscribers[subscriber.eventName]
    if not eventSubscribers or not eventSubscribers[subscriber] then return false end

    eventSubscribers[subscriber] = nil
    if not next(eventSubscribers) then
        subscribers[subscriber.eventName] = nil
    end

    return true
end

function domainEvents:unsubscribeAll(owner)
    if not owner then return 0 end

    local removed = 0
    for eventName, eventSubscribers in pairs(subscribers) do
        for subscriber in pairs(eventSubscribers) do
            if subscriber.owner == owner then
                eventSubscribers[subscriber] = nil
                removed = removed + 1
            end
        end

        if not next(eventSubscribers) then
            subscribers[eventName] = nil
        end
    end

    return removed
end

function domainEvents:publish(eventName, payload)
    if not isValidEventName(eventName) then return 0 end

    local eventSubscribers = subscribers[eventName]
    if not eventSubscribers then return 0 end

    local snapshot = {}
    for subscriber in pairs(eventSubscribers) do
        snapshot[#snapshot + 1] = subscriber
    end

    local delivered = 0
    for _, subscriber in ipairs(snapshot) do
        if eventSubscribers[subscriber] and callSubscriber(subscriber, payload, eventName) then
            delivered = delivered + 1
        end
    end

    return delivered
end

domainEvents.emit = domainEvents.publish
