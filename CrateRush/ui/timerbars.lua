-- CrateRush
-- ui/timerbars.lua - Timer row renderer. Display-only; timer ownership stays in logic.

local timerbars = {}
CrateRush.timerbars = timerbars

local TIMER_LAYOUT = (CrateRush.layout and CrateRush.layout.timerRows) or {}
local COCKPIT_LAYOUT = (CrateRush.layout and CrateRush.layout.cockpit) or {}
local HEADER_LAYOUT = (CrateRush.layout and CrateRush.layout.header) or {}
local ROW_HEIGHT = TIMER_LAYOUT.rowHeight or 76
local ROW_SPACING = TIMER_LAYOUT.rowSpacing or 10
local ROW_TOP_GAP = TIMER_LAYOUT.rowTopGap or 14
local LABEL_LEFT = (TIMER_LAYOUT.labelLeftPadding or 30) - 3
local LABEL_TOP = TIMER_LAYOUT.labelTopPadding or 16
local LABEL_Y_OFFSET = TIMER_LAYOUT.labelYOffset or 0
local UNSEEN_Y_OFFSET = TIMER_LAYOUT.unseenYOffset or 0
local TOP_ROW_HEIGHT = TIMER_LAYOUT.topRowHeight or 17
local TIME_RIGHT = TIMER_LAYOUT.timerTextRightPadding or 22
local TIME_WIDTH = TIMER_LAYOUT.timerTextWidth or 72
local TIMER_FONT_SIZE = TIMER_LAYOUT.timerFontSize or 14
local UNSEEN_WIDTH = TIMER_LAYOUT.unseenTextWidth or (TIME_WIDTH + 42)
local UNSEEN_TIME_GAP = TIMER_LAYOUT.unseenTimeGap or 3
local LABEL_UNSEEN_GAP = TIMER_LAYOUT.labelUnseenGap or 8
local BAR_LEFT = (TIMER_LAYOUT.barLeftPadding or 30) - 3
local BAR_RIGHT = (TIMER_LAYOUT.barRightPadding or 110) + 3
local BAR_HEIGHT = TIMER_LAYOUT.barHeight or 14
local BAR_BOTTOM = TIMER_LAYOUT.barBottomPadding or 10
local STRIP_WIDTH = TIMER_LAYOUT.activeStripWidth or 5
local STRIP_LEFT_INSET = 2
local STRIP_VERTICAL_INSET = 2
local uiColors = CrateRush.theme:getUIColors()
local surface = CrateRush.surface
local uiModel = CrateRush.uiModel
local uiActions = CrateRush.uiActions
local uiTooltips = CrateRush.tooltips
local URGENT_SECONDS = (CrateRush.TIMING and CrateRush.TIMING.TIMERBAR_URGENT_SECONDS) or 0
local WARNING_SECONDS = (CrateRush.TIMING and CrateRush.TIMING.TIMERBAR_WARNING_SECONDS) or 0
local URGENT_FLASH_INTERVAL = 0.45

local container
local bars = {}
local barOrder = {}
local selectedZoneID
local activeLifecycleByKey = {}

local function getHeaderWidth()
    local header = CrateRush.frames and CrateRush.frames.getFrame and CrateRush.frames:getFrame() or nil
    return (header and header:GetWidth()) or HEADER_LAYOUT.width or TIMER_LAYOUT.width or 329
end

local function getRowWidth()
    local cockpitWidth = COCKPIT_LAYOUT.width or 230
    local gap = COCKPIT_LAYOUT.gapFromTimers or 1
    return math.max(120, getHeaderWidth() - cockpitWidth - gap)
end

local function getTrackWidth()
    return math.max(40, getRowWidth() - BAR_LEFT - BAR_RIGHT)
end

local function isMainVisible()
    return CrateRush.frames and CrateRush.frames.isShown and CrateRush.frames:isShown()
end

local function requestTimerRemoval(key)
    if key and uiActions and uiActions.requestTimerRemoval then
        uiActions:requestTimerRemoval(key)
    end
end

local function sameZone(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function setFontSize(fontString, size)
    if not fontString or not size then return end
    local font, _, flags = fontString:GetFont()
    fontString:SetFont(font or STANDARD_TEXT_FONT, size, flags)
end

local function colorForRow(row)
    return row and row.color or uiColors.timerRows.normal
end

local function withAlpha(color, alpha)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], alpha }
end

local function themedRowBorder(alpha)
    local color = CrateRush.theme and CrateRush.theme.getSurfaceBorder and CrateRush.theme:getSurfaceBorder("row") or nil
    return withAlpha(color, alpha) or { 0.12, 0.14, 0.16, alpha }
end

local function urgencyForRow(row)
    if not row or row.noData then return "none" end
    local remaining = tonumber(row.remaining) or math.huge
    if row.urgency == "urgent" or remaining <= URGENT_SECONDS then
        return "urgent"
    elseif row.urgency == "warning" or remaining <= WARNING_SECONDS then
        return "warning"
    end
    return "normal"
end

local function stopUrgentFlash(row)
    if not row or not row.urgentFlashActive then return end
    row:SetScript("OnUpdate", nil)
    row.urgentFlashActive = false
    row.urgentFlashElapsed = nil
    row.urgentFlashPhase = nil
end

local function startUrgentFlash(row, normalBg, urgentBg, normalBorder, urgentBorder)
    if not row then return end

    row.urgentFlashNormalBg = normalBg
    row.urgentFlashUrgentBg = urgentBg
    row.urgentFlashNormalBorder = normalBorder
    row.urgentFlashUrgentBorder = urgentBorder

    if row.urgentFlashActive then return end

    row.urgentFlashActive = true
    row.urgentFlashElapsed = 0
    surface:setColors(row, urgentBg, urgentBorder)

    local function blend(a, b, t)
        if type(a) ~= "table" or type(b) ~= "table" then return b end
        return {
            (a[1] or 0) + ((b[1] or 0) - (a[1] or 0)) * t,
            (a[2] or 0) + ((b[2] or 0) - (a[2] or 0)) * t,
            (a[3] or 0) + ((b[3] or 0) - (a[3] or 0)) * t,
            (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t,
        }
    end

    row:SetScript("OnUpdate", function(self, elapsed)
        self.urgentFlashElapsed = (self.urgentFlashElapsed or 0) + (elapsed or 0)
        local cycle = (self.urgentFlashElapsed % (URGENT_FLASH_INTERVAL * 2)) / (URGENT_FLASH_INTERVAL * 2)
        local amount = 0.5 - (math.cos(cycle * math.pi * 2) * 0.5)
        surface:setColors(
            self,
            blend(self.urgentFlashNormalBg, self.urgentFlashUrgentBg, amount),
            blend(self.urgentFlashNormalBorder, self.urgentFlashUrgentBorder, amount)
        )
    end)
end

local function getContainer()
    if container then return container end

    local header = CrateRush.frames and CrateRush.frames:getFrame()
    if not header then return nil end

    container = CreateFrame("Frame", "CrateRushTimersFrame", UIParent)
    container:SetWidth(getRowWidth())
    container:SetHeight(1)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -ROW_TOP_GAP)
    container:SetFrameStrata("MEDIUM")
    container:EnableMouse(false)
    container:Hide()

    header:HookScript("OnDragStop", function()
        container:ClearAllPoints()
        container:SetWidth(getRowWidth())
        container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -ROW_TOP_GAP)
    end)

    return container
end

local function updateContainerHeight()
    local c = getContainer()
    if not c then return end
    local count = timerbars:getCount()
    c:SetHeight(count > 0 and count * (ROW_HEIGHT + ROW_SPACING) or 1)
end

local function createBar(key)
    local c = getContainer()
    if not c then return nil end

    local row = surface:create(c, "row", {
        width = getRowWidth(),
        height = ROW_HEIGHT,
        mouseEnabled = true,
    })
    row:SetFrameLevel(c:GetFrameLevel() + 1)
    row.key = key

    local strip = surface:create(row, "progressFill", {
        width = STRIP_WIDTH,
        height = ROW_HEIGHT - (STRIP_VERTICAL_INSET * 2),
        borderSize = 0,
        radius = math.floor(STRIP_WIDTH / 2),
    })
    strip:SetPoint("LEFT", row, "LEFT", STRIP_LEFT_INSET, 0)
    row.strip = strip

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", LABEL_LEFT, -(LABEL_TOP + LABEL_Y_OFFSET))
    label:SetPoint("RIGHT", row, "RIGHT", -(TIME_WIDTH + UNSEEN_WIDTH + TIME_RIGHT + UNSEEN_TIME_GAP + LABEL_UNSEEN_GAP), 0)
    label:SetHeight(TOP_ROW_HEIGHT)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("BOTTOM")
    label:SetTextColor(uiColors.neutral.textPrimary[1], uiColors.neutral.textPrimary[2], uiColors.neutral.textPrimary[3], 1)
    row.label = label

    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    timeText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TIME_RIGHT, -LABEL_TOP)
    timeText:SetWidth(TIME_WIDTH)
    timeText:SetHeight(TOP_ROW_HEIGHT)
    timeText:SetJustifyH("RIGHT")
    timeText:SetJustifyV("BOTTOM")
    setFontSize(timeText, TIMER_FONT_SIZE)
    timeText:SetTextColor(uiColors.neutral.textTimer[1], uiColors.neutral.textTimer[2], uiColors.neutral.textTimer[3], 1)
    row.timeText = timeText

    local track = surface:create(row, "progressTrack", {
        width = getTrackWidth(),
        height = BAR_HEIGHT,
        borderSize = 0,
        radius = math.floor(BAR_HEIGHT / 2),
    })
    track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", BAR_LEFT, BAR_BOTTOM)
    row.track = track

    local unseenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unseenText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(TIME_RIGHT + TIME_WIDTH + UNSEEN_TIME_GAP), -(LABEL_TOP + UNSEEN_Y_OFFSET))
    unseenText:SetWidth(UNSEEN_WIDTH)
    unseenText:SetHeight(TOP_ROW_HEIGHT)
    unseenText:SetJustifyH("RIGHT")
    unseenText:SetJustifyV("BOTTOM")
    local unseenFont, unseenSize, unseenFlags = unseenText:GetFont()
    unseenText:SetFont(unseenFont or STANDARD_TEXT_FONT, math.max(8, (tonumber(unseenSize) or 10) - 1), unseenFlags)
    unseenText:SetTextColor(0.62, 0.68, 0.74, 0.88)
    row.unseenText = unseenText

    local fill = surface:create(track, "progressFill", {
        width = BAR_HEIGHT,
        height = BAR_HEIGHT,
        borderSize = 0,
        radius = math.floor(BAR_HEIGHT / 2),
    })
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    row.fill = fill

    row:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() and self.display and uiActions and uiActions.announceTimerRow then
            uiActions:announceTimerRow(self.display)
        elseif button == "RightButton" and IsShiftKeyDown() and self.key then
            requestTimerRemoval(self.key)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not uiTooltips then return end
        local display = self.display
        local title = display and (display.zoneName or display.label) or "Timer"
        local body = nil
        local showShiftClick = true
        if display and display.noData then
            body = "No timer data available."
            showShiftClick = false
        elseif CrateRush.manualAnnouncementService and CrateRush.manualAnnouncementService.previewTimerRow then
            body = CrateRush.manualAnnouncementService:previewTimerRow(display)
            showShiftClick = body ~= nil and body ~= ""
        end
        uiTooltips:show(self, title, body, {
            showShiftClick = showShiftClick,
        })
    end)
    row:SetScript("OnLeave", function()
        if uiTooltips then uiTooltips:hide() end
    end)

    bars[key] = row
    return row
end

local function getOrCreateBar(key)
    if bars[key] then return bars[key] end
    return createBar(key)
end

local function applyRowVisual(row, display)
    if not row or not display then return end

    local accent = display.noData and { 0.18, 0.22, 0.26, 1.00 } or colorForRow(display)
    local selected = sameZone(display.zoneID, selectedZoneID)
    local urgency = urgencyForRow(display)

    local border = selected and accent or themedRowBorder(display.noData and 0.28 or 0.52)
    local bg = selected and { 0.025, 0.035, 0.065, 0.94 }
        or { 0.025, 0.030, 0.045, display.noData and 0.42 or 0.88 }
    local normalBg = bg
    local normalBorder = border
    local shouldFlashUrgent = false

    if display.noData then
        bg = { 0.010, 0.014, 0.020, 0.36 }
        normalBg = bg
    elseif urgency == "urgent" then
        bg = { 0.16, 0.025, 0.025, 0.82 }
        border = { 0.78, 0.16, 0.14, 0.64 }
        shouldFlashUrgent = true
    elseif urgency == "warning" then
        bg = { 0.34, 0.25, 0.015, 0.84 }
        border = { 1.00, 0.86, 0.12, 0.78 }
    end

    if shouldFlashUrgent then
        startUrgentFlash(row, normalBg, bg, normalBorder, border)
    else
        stopUrgentFlash(row)
        surface:setColors(row, bg, border)
    end

    surface:setColors(row.strip, { accent[1], accent[2], accent[3], display.noData and 0.24 or 1 }, { 0, 0, 0, 0 })
    row.strip:SetShown(true)
    surface:setColors(row.fill, { accent[1], accent[2], accent[3], 0.95 }, { 0, 0, 0, 0 })
end

local function renderRow(row, display)
    row.display = display

    local rowWidth = getRowWidth()
    local trackWidth = getTrackWidth()
    local total = tonumber(display.total) or CrateRush.DEFAULT_ZONE_FREQUENCY or 1
    total = math.max(1, total)
    local progress = math.max(0, math.min(total, tonumber(display.progress) or 0))
    local fillWidth = math.max(1, math.floor(trackWidth * (progress / total)))
    local visualFillWidth = fillWidth <= BAR_HEIGHT and BAR_HEIGHT or fillWidth

    row:SetWidth(rowWidth)
    row.track:SetWidth(trackWidth)
    row.fill:SetWidth(visualFillWidth)
    row.unseenText:SetWidth(UNSEEN_WIDTH)
    row.label:SetText(display.label or ((display.zoneName or "Unknown") .. " [" .. tostring(display.shardID or "?") .. "]"))
    row.timeText:SetText(display.timeText or formatTime(display.remaining or 0))
    row.unseenText:SetText(display.unseenText or "")
    if display.noData then
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", LABEL_LEFT, -(LABEL_TOP + LABEL_Y_OFFSET))
        row.label:SetHeight(TOP_ROW_HEIGHT)
        row.timeText:ClearAllPoints()
        row.timeText:SetPoint("CENTER", row, "CENTER", 0, 0)
        row.timeText:SetWidth(rowWidth - 40)
        row.timeText:SetJustifyH("CENTER")
        row.label:SetTextColor(0.30, 0.36, 0.42, 0.70)
        row.timeText:SetTextColor(0.45, 0.50, 0.56, 0.80)
        row.unseenText:Hide()
    else
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", LABEL_LEFT, -(LABEL_TOP + LABEL_Y_OFFSET))
        row.label:SetPoint("RIGHT", row, "RIGHT", -(TIME_WIDTH + UNSEEN_WIDTH + TIME_RIGHT + UNSEEN_TIME_GAP + LABEL_UNSEEN_GAP), 0)
        row.label:SetHeight(TOP_ROW_HEIGHT)
        row.label:SetJustifyV("BOTTOM")
        row.timeText:ClearAllPoints()
        row.timeText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TIME_RIGHT, -LABEL_TOP)
        row.timeText:SetWidth(TIME_WIDTH)
        row.timeText:SetHeight(TOP_ROW_HEIGHT)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetJustifyV("BOTTOM")
        row.unseenText:ClearAllPoints()
        row.unseenText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(TIME_RIGHT + TIME_WIDTH + UNSEEN_TIME_GAP), -(LABEL_TOP + UNSEEN_Y_OFFSET))
        row.unseenText:SetWidth(UNSEEN_WIDTH)
        row.unseenText:SetHeight(TOP_ROW_HEIGHT)
        row.unseenText:SetJustifyH("RIGHT")
        row.unseenText:SetJustifyV("BOTTOM")
        row.label:SetTextColor(uiColors.neutral.textPrimary[1], uiColors.neutral.textPrimary[2], uiColors.neutral.textPrimary[3], uiColors.neutral.textPrimary[4] or 1)
        row.timeText:SetTextColor(uiColors.neutral.textTimer[1], uiColors.neutral.textTimer[2], uiColors.neutral.textTimer[3], uiColors.neutral.textTimer[4] or 1)
        row.unseenText:SetShown(display.unseenText ~= nil and display.unseenText ~= "")
    end
    row.track:SetShown(not display.noData)
    row.fill:SetShown(not display.noData)
    applyRowVisual(row, display)
    row:Show()
end

local function repositionBars()
    local c = getContainer()
    if not c then return end
    c:SetWidth(getRowWidth())

    local index = 0
    for _, key in ipairs(barOrder) do
        local row = bars[key]
        if row and row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(index * (ROW_HEIGHT + ROW_SPACING)))
            index = index + 1
        end
    end

    updateContainerHeight()
end

local function renderPlaceholderRows()
    if not uiModel or not uiModel.formatTimerRows then return false end
    timerbars:updateSorted(uiModel:formatTimerRows({ sorted = {} }))
    return true
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
        if not seen[key] then stale[#stale + 1] = key end
    end
    for _, key in ipairs(stale) do
        timerbars:remove(key)
    end

    if #sorted == 0 then
        timerbars:hideContainer()
        return
    end

    if not isMainVisible() then
        timerbars:hideContainer()
        return
    end

    barOrder = {}
    for _, display in ipairs(sorted) do
        if display and display.key then
            local row = getOrCreateBar(display.key)
            if row then
                barOrder[#barOrder + 1] = display.key
                renderRow(row, display)
            end
        end
    end

    repositionBars()

    local c = getContainer()
    if c and #sorted > 0 then c:Show() end
end

function timerbars:update(key, zoneName, shardID, remaining, total)
    if not key then return end
    if not isMainVisible() then
        timerbars:hideContainer()
        return
    end

    local row = uiModel and uiModel.formatTimerRow and uiModel:formatTimerRow({
        key = key,
        zoneName = zoneName,
        shardID = shardID,
        remaining = remaining,
        freq = total or CrateRush.DEFAULT_ZONE_FREQUENCY,
    }) or nil
    if not row then return end

    local bar = getOrCreateBar(key)
    if not bar then return end
    local inOrder = false
    for _, existingKey in ipairs(barOrder) do
        if existingKey == key then
            inOrder = true
            break
        end
    end
    if not inOrder then
        barOrder[#barOrder + 1] = key
    end
    renderRow(bar, row)
    repositionBars()

    local c = getContainer()
    if c then c:Show() end
end

function timerbars:remove(key)
    if not key or not bars[key] then return end
    stopUrgentFlash(bars[key])
    bars[key]:Hide()
    bars[key] = nil
    activeLifecycleByKey[key] = nil
    for i, existingKey in ipairs(barOrder) do
        if existingKey == key then
            table.remove(barOrder, i)
            break
        end
    end
    repositionBars()
end

function timerbars:showContainer()
    if not isMainVisible() then return end
    if timerbars:getCount() == 0 then
        renderPlaceholderRows()
    end
    local c = getContainer()
    if c and timerbars:getCount() > 0 then c:Show() end
end

function timerbars:hideContainer()
    if container then container:Hide() end
end

function timerbars:getCount()
    local count = 0
    for _, row in pairs(bars) do
        if row and row:IsShown() then count = count + 1 end
    end
    return count
end

function timerbars:onActiveTimerChanged(payload)
    if type(payload) ~= "table" then return end
    if uiModel and uiModel.formatTimerRows then
        timerbars:updateSorted(uiModel:formatTimerRows(payload))
    else
        timerbars:updateSorted(payload.sorted or {})
    end
end

function timerbars:onActiveTimerRemoved(payload)
    if type(payload) ~= "table" then return end
    timerbars:remove(payload.key)
    if timerbars:getCount() == 0 and isMainVisible() then
        renderPlaceholderRows()
    end
end

function timerbars:onZoneShardStatusChanged(payload)
    if type(payload) ~= "table" then return end
    selectedZoneID = payload.zoneID
    if timerbars:getCount() == 0 and isMainVisible() then
        renderPlaceholderRows()
        return
    end
    for _, row in pairs(bars) do
        if row and row.display then
            applyRowVisual(row, row.display)
        end
    end
end

function timerbars:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    local key = CrateRush.crateKeys and CrateRush.crateKeys.make and CrateRush.crateKeys:make(payload.zoneID, payload.shardID) or nil
    if key then activeLifecycleByKey[key] = true end
    for _, row in pairs(bars) do
        if row and row.display then
            applyRowVisual(row, row.display)
        end
    end
end

function timerbars:applyTheme()
    for _, row in pairs(bars) do
        if row and row.display then
            applyRowVisual(row, row.display)
        end
    end
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
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED,
        timerbars,
        "onZoneShardStatusChanged"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.CRATE_STATE_CHANGED,
        timerbars,
        "onCrateStateChanged"
    )
end
