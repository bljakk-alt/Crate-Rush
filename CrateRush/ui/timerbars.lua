-- CrateRush
-- ui/timerbars.lua — Timer bars container. Separate from header frame.
-- Container is transparent and non-interactive. Only bars catch mouse events.

local timerbars = {}
CrateRush.timerbars = timerbars

local BAR_HEIGHT   = 21
local BAR_SPACING  = 1
local WHITE_TEXTURE = "Interface/Buttons/WHITE8X8"
local BAR_COLOR    = { r = 0.16, g = 0.58, b = 0.86 }
local WARN_COLOR   = { r = 1.00, g = 0.72, b = 0.18 }
local URGENT_COLOR = { r = 1.00, g = 0.24, b = 0.24 }
local BAR_BG       = { r = 0.04, g = 0.05, b = 0.06, a = 0.86 }
local URGENT_SECONDS = CrateRush.TIMING.TIMERBAR_URGENT_SECONDS
local WARNING_SECONDS = CrateRush.TIMING.TIMERBAR_WARNING_SECONDS

local container   -- transparent frame anchored below header
local bars     = {}
local barOrder = {}

local function isMainVisible()
    return CrateRush.frames and CrateRush.frames.isShown and CrateRush.frames:isShown()
end

local function requestTimerRemoval(key)
    if not key then return end
    if not CrateRush.domainEvents or not CrateRush.DOMAIN_EVENT then return end
    if not CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED then return end

    CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.TIMER_REMOVAL_REQUESTED, {
        key    = key,
        reason = CrateRush.TIMER_REMOVE_REASON and CrateRush.TIMER_REMOVE_REASON.MANUAL or "manual",
        source = "timerbars",
    })
end

local function getContainer()
    if container then return container end

    local header = CrateRush.frames and CrateRush.frames:getFrame()
    if not header then return nil end

    container = CreateFrame("Frame", "CrateRushTimersFrame", UIParent)
    container:SetWidth(header:GetWidth())
    container:SetHeight(0)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    container:SetFrameStrata("MEDIUM")
    container:EnableMouse(false)  -- container does not catch mouse events
    container:Hide()

    -- Keep container aligned with header when header moves
    header:HookScript("OnDragStop", function()
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    end)

    return container
end

local function updateContainerHeight()
    local c = getContainer()
    if not c then return end
    local count = timerbars:getCount()
    if count == 0 then
        c:SetHeight(1)
    else
        c:SetHeight(count * (BAR_HEIGHT + BAR_SPACING))
    end
end

local function getOrCreateBar(key)
    if bars[key] then return bars[key] end

    local c = getContainer()
    if not c then return nil end

    local bar = CreateFrame("StatusBar", nil, c)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetStatusBarColor(BAR_COLOR.r, BAR_COLOR.g, BAR_COLOR.b, 1)
    bar:EnableMouse(true)  -- bars DO catch mouse events for shift+rightclick

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(BAR_BG.r, BAR_BG.g, BAR_BG.b, BAR_BG.a)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT",  bar, "LEFT",  7, 0)
    label:SetPoint("RIGHT", bar, "RIGHT", -60, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.92, 0.94, 0.96, 1)
    bar.label = label

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -7, 0)
    timeText:SetJustifyH("RIGHT")
    timeText:SetTextColor(0.98, 0.98, 0.98, 1)
    bar.timeText = timeText

    -- Shift+RightClick asks the timer service to own removal.
    bar:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() and self.key then
            requestTimerRemoval(self.key)
        end
    end)

    bar.key = key
    bars[key] = bar
    barOrder[#barOrder + 1] = key
    return bar
end

local function repositionBars()
    local c = getContainer()
    if not c then return end

    local i = 0
    for _, key in ipairs(barOrder) do
        local bar = bars[key]
        if bar and bar:IsShown() then
            local offset = -(i * (BAR_HEIGHT + BAR_SPACING))
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT",  c, "TOPLEFT",  0, offset)
            bar:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, offset)
            i = i + 1
        end
    end

    updateContainerHeight()
end

function timerbars:updateSorted(sorted)
    if not sorted then return end

    local seen = {}
    for _, entry in ipairs(sorted) do
        if entry and entry.key then
            seen[entry.key] = true
        end
    end

    local stale = {}
    for key in pairs(bars) do
        if not seen[key] then
            stale[#stale + 1] = key
        end
    end
    for _, key in ipairs(stale) do
        timerbars:remove(key)
    end

    if not isMainVisible() then
        timerbars:hideContainer()
        return
    end

    -- Update each bar's content
    for _, entry in ipairs(sorted) do
        local bar = getOrCreateBar(entry.key)
        if bar then
            bar:SetMinMaxValues(0, entry.freq)
            bar:SetValue(math.max(0, entry.freq - entry.remaining))
            bar.label:SetText((entry.zoneName or "Unknown") .. " [" .. tostring(entry.shardID or "?") .. "]")

            local mins = math.floor(entry.remaining / 60)
            local secs = entry.remaining % 60
            bar.timeText:SetText(string.format("%02d:%02d", mins, secs))

            if entry.remaining <= URGENT_SECONDS then
                bar:SetStatusBarColor(URGENT_COLOR.r, URGENT_COLOR.g, URGENT_COLOR.b, 1)
            elseif entry.remaining <= WARNING_SECONDS then
                bar:SetStatusBarColor(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 1)
            else
                bar:SetStatusBarColor(BAR_COLOR.r, BAR_COLOR.g, BAR_COLOR.b, 1)
            end

            bar:Show()
        end
    end

    -- Reposition in sorted order
    local c = getContainer()
    if not c then return end

    local i = 0
    for _, entry in ipairs(sorted) do
        local bar = bars[entry.key]
        if bar and bar:IsShown() then
            local offset = -(i * (BAR_HEIGHT + BAR_SPACING))
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT",  c, "TOPLEFT",  0, offset)
            bar:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, offset)
            i = i + 1
        end
    end

    -- Update container height
    local count = #sorted
    c:SetHeight(count > 0 and count * (BAR_HEIGHT + BAR_SPACING) or 1)
    if count > 0 and not c:IsShown() then c:Show() end
end

function timerbars:update(key, zoneName, shardID, remaining, total)
    if not key then return end

    if not isMainVisible() then
        timerbars:hideContainer()
        return
    end

    local bar = getOrCreateBar(key)
    if not bar then return end

    local freq = total or CrateRush.DEFAULT_ZONE_FREQUENCY
    bar:SetMinMaxValues(0, freq)
    bar:SetValue(math.max(0, freq - (remaining or 0)))
    bar.label:SetText((zoneName or "Unknown") .. " [" .. tostring(shardID or "?") .. "]")

    local mins = math.floor((remaining or 0) / 60)
    local secs = (remaining or 0) % 60
    bar.timeText:SetText(string.format("%02d:%02d", mins, secs))

    if (remaining or 0) <= URGENT_SECONDS then
        bar:SetStatusBarColor(URGENT_COLOR.r, URGENT_COLOR.g, URGENT_COLOR.b, 1)
    elseif (remaining or 0) <= WARNING_SECONDS then
        bar:SetStatusBarColor(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 1)
    else
        bar:SetStatusBarColor(BAR_COLOR.r, BAR_COLOR.g, BAR_COLOR.b, 1)
    end

    bar:Show()
    repositionBars()

    local c = getContainer()
    if c and not c:IsShown() then c:Show() end
end

function timerbars:remove(key)
    if not key or not bars[key] then return end
    bars[key]:Hide()
    bars[key] = nil
    for i, k in ipairs(barOrder) do
        if k == key then
            table.remove(barOrder, i)
            break
        end
    end
    repositionBars()
end

function timerbars:showContainer()
    if not isMainVisible() then return end

    local c = getContainer()
    if c and timerbars:getCount() > 0 then c:Show() end
end

function timerbars:hideContainer()
    if container then container:Hide() end
end

function timerbars:getCount()
    local count = 0
    for _, bar in pairs(bars) do
        if bar and bar:IsShown() then count = count + 1 end
    end
    return count
end

function timerbars:onActiveTimerChanged(payload)
    if type(payload) ~= "table" then return end
    timerbars:updateSorted(payload.sorted or {})
end

function timerbars:onActiveTimerRemoved(payload)
    if type(payload) ~= "table" then return end
    timerbars:remove(payload.key)
end

if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT then
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ACTIVE_TIMER_CHANGED,
        timerbars,
        "onActiveTimerChanged"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ACTIVE_TIMER_REMOVED,
        timerbars,
        "onActiveTimerRemoved"
    )
end
