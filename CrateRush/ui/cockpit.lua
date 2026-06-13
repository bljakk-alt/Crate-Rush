-- CrateRush
-- ui/cockpit.lua - Right-side display cockpit. Consumes domain events, renders only.

local cockpit = {}
CrateRush.cockpit = cockpit

local uiModel = CrateRush.uiModel
local uiActions = CrateRush.uiActions
local surface = CrateRush.surface
local COLORS = CrateRush.theme:getUIColors()
local COCKPIT_COLORS = CrateRush.theme:getUIColors().cockpit

local LAYOUT = (CrateRush.layout and CrateRush.layout.cockpit) or {}
local WIDTH = LAYOUT.width or 330
local GAP_FROM_HEADER = LAYOUT.gapFromHeader or 14
local CARD_HEIGHT = LAYOUT.cardHeight or 72
local TIMING_HEIGHT = LAYOUT.timingCardHeight or 92
local SYNC_HEIGHT = LAYOUT.syncHeight or 52
local SECTION_GAP = LAYOUT.sectionGap or 10
local PADDING = LAYOUT.padding or 16
local COLUMN_EDGE_PADDING = math.max(8, PADDING - 4)
local CONTENT_LABEL_TOP = -20
local CONTENT_VALUE_BOTTOM = 7
local CONTENT_LABEL_COLOR = { 0.72, 0.76, 0.80, 0.92 }
local STATE_LABEL_TOP = -14
local ENEMY_WARNING_BG = { 0.24, 0.02, 0.02, 0.76 }
local ENEMY_WARNING_BORDER = { 1.00, 0.16, 0.16, 0.88 }
local ENEMY_WARNING_TEXT = { 1.00, 0.34, 0.34, 1.00 }
local CLAIMED_LOOT_WINDOW_SECONDS = (CrateRush.TIMING and CrateRush.TIMING.CLAIMED_LOOT_WINDOW_SECONDS) or 58

local frame
local cards = {}
local selectedZoneID
local selectedShardID
local selectedKey
local stateByKey = {}
local predictionByKey = {}
local predictionByZone = {}
local enemyByKey = {}

local function getPlaceholder()
    if uiModel and uiModel.getCockpitPlaceholder then
        return uiModel:getCockpitPlaceholder()
    end
    return {}
end

local function applyFontSize(fontString, delta)
    if not fontString then return end
    local font, size, flags = fontString:GetFont()
    font = font or STANDARD_TEXT_FONT
    size = math.max(8, (tonumber(size) or 12) + (delta or -1))
    if font then
        fontString:SetFont(font, size, flags)
    end
end

local function setTextColor(fontString, color, alpha)
    if not fontString or not color then return end
    fontString:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function makeKey(zoneID, shardID)
    if CrateRush.crateKeys and CrateRush.crateKeys.make then
        return CrateRush.crateKeys:make(zoneID, shardID)
    end
    if zoneID and shardID then
        return tostring(zoneID) .. ":" .. tostring(shardID)
    end
    return nil
end

local function nowSeconds()
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function isClaimedState(state)
    if CrateRush.cockpitDisplay and CrateRush.cockpitDisplay.isClaimedState then
        return CrateRush.cockpitDisplay:isClaimedState(state)
    end
    return false
end

local function payloadMatchesConfirmedSelection(payload)
    if CrateRush.cockpitDisplay and CrateRush.cockpitDisplay.payloadMatchesConfirmedSelection then
        return CrateRush.cockpitDisplay:payloadMatchesConfirmedSelection(payload, selectedZoneID, selectedShardID, selectedKey)
    end
    return false, "display_adapter_missing"
end

local function claimedStateIsFresh(payload)
    if not isClaimedState(payload and payload.state) then return true end
    local timestamp = tonumber(payload.claimedAt or payload.lastSeenAt)
    if not timestamp then return false, "claimed_missing_time" end
    if nowSeconds() - timestamp > CLAIMED_LOOT_WINDOW_SECONDS then return false, "claimed_expired" end
    return true
end

local function logManualBlock(reason, payload)
    if not (CrateRush.debug and CrateRush.debug.log) then return end
    CrateRush.debug:log("COCKPIT | MANUAL_BLOCKED reason=" .. tostring(reason)
        .. " zone=" .. tostring(payload and payload.zoneID or selectedZoneID)
        .. " shard=" .. tostring(payload and payload.shardID or selectedShardID))
end

local function getManualStatePayload(logBlocked)
    local payload = selectedKey and stateByKey[selectedKey] or nil
    local ok, reason = payloadMatchesConfirmedSelection(payload)
    if ok then ok, reason = claimedStateIsFresh(payload) end
    if ok then return payload end
    if reason == "claimed_expired" and selectedKey then stateByKey[selectedKey] = nil end
    if logBlocked then logManualBlock(reason, payload) end
    return nil
end

local function getManualPredictionPayload(logBlocked)
    local payload = selectedKey and predictionByKey[selectedKey] or nil
    if not payload and selectedZoneID then
        payload = predictionByZone[tostring(selectedZoneID)]
    end
    local ok, reason = payloadMatchesConfirmedSelection(payload)
    if ok then return payload end
    if logBlocked then logManualBlock(reason, payload) end
    return nil
end

local function getManualEnemyPayload(logBlocked)
    local payload = selectedKey and enemyByKey[selectedKey] or nil
    local ok, reason = payloadMatchesConfirmedSelection(payload)
    if ok then return payload end
    if logBlocked then logManualBlock(reason, payload) end
    return nil
end

local function getAnchor()
    return CrateRush.frames and CrateRush.frames.getFrame and CrateRush.frames:getFrame() or nil
end

local function cardTop(index, heights)
    local y = 0
    for i = 1, index - 1 do
        y = y + heights[i] + SECTION_GAP
    end
    return -y
end

local function surfaceBorder(name, alpha)
    local color = CrateRush.theme and CrateRush.theme.getSurfaceBorder and CrateRush.theme:getSurfaceBorder(name) or nil
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], alpha or color[4] or 1 }
end

local function setTextureColor(texture, color, alpha)
    if not texture or type(color) ~= "table" then return end
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function getDividerColor()
    return surfaceBorder("card", 0.62) or { 0.18, 0.20, 0.22, 0.55 }
end

local function getTitleColor()
    return (CrateRush.theme and CrateRush.theme.getColor and CrateRush.theme:getColor("title"))
        or { 0.10, 0.85, 1.00, 1.00 }
end

local function createTitle(card, text)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PADDING, -5)
    title:SetJustifyH("RIGHT")
    title:SetText(text)
    applyFontSize(title, -3)
    setTextColor(title, getTitleColor())
    card.title = title
    return title
end

local function createColumnText(card, text, side, topOffset, justify)
    local fontString = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local colWidth = math.floor((WIDTH - (COLUMN_EDGE_PADDING * 2) - 12) / 2)
    if side == "right" then
        fontString:SetPoint("TOPRIGHT", card, "TOPRIGHT", -COLUMN_EDGE_PADDING, topOffset)
    else
        fontString:SetPoint("TOPLEFT", card, "TOPLEFT", COLUMN_EDGE_PADDING, topOffset)
    end
    fontString:SetWidth(colWidth)
    fontString:SetJustifyH(justify or (side == "right" and "RIGHT" or "LEFT"))
    fontString:SetText(text or "")
    return fontString
end

local function createColumnValue(card, side, bottomOffset, justify)
    local fontString = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local colWidth = math.floor((WIDTH - (COLUMN_EDGE_PADDING * 2) - 12) / 2)
    if side == "right" then
        fontString:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -COLUMN_EDGE_PADDING, bottomOffset)
    else
        fontString:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", COLUMN_EDGE_PADDING, bottomOffset)
    end
    fontString:SetWidth(colWidth)
    fontString:SetJustifyH(justify or "RIGHT")
    fontString:SetText("--")
    applyFontSize(fontString, 1)
    setTextColor(fontString, COCKPIT_COLORS.value)
    return fontString
end

local function createDivider(card)
    local separator = card:CreateTexture(nil, "ARTWORK")
    separator:SetTexture("Interface/Buttons/WHITE8X8")
    separator:SetWidth(1)
    separator:SetPoint("TOP", card, "TOP", 0, -24)
    separator:SetPoint("BOTTOM", card, "BOTTOM", 0, 7)
    setTextureColor(separator, getDividerColor())
    card.divider = separator
    return separator
end

local function updateDivider(card)
    if card and card.divider then
        setTextureColor(card.divider, getDividerColor())
    end
end

local function createCard(parent, name, topOffset, height)
    local card = surface:create(parent, "card", {
        width = WIDTH,
        height = height,
        name = name,
    })
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, topOffset)
    card:EnableMouse(true)
    return card
end

local function createLifecycleStrip(card)
    local strip = CreateFrame("Frame", nil, card)
    strip:SetPoint("TOPLEFT", card, "TOPLEFT", PADDING, -22)
    strip:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PADDING, 3)
    card.lifecycleStrip = strip

    local labels = { "FLYING", "DROP", "LAND" }
    local railWidth = math.max(112, WIDTH - (PADDING * 2) - 42)
    local dotCenterX = 16
    local dotY = -18
    local dotRadius = 7
    local lineGap = 3
    local lineHeight = 4
    strip.dots = {}
    strip.labels = {}
    strip.lines = {}

    for i, labelText in ipairs(labels) do
        local x = ((i - 1) / 2) * railWidth

        local label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", strip, "TOPLEFT", x, 0)
        label:SetText(labelText)
        applyFontSize(label, -1)
        setTextColor(label, COCKPIT_COLORS.muted)
        strip.labels[i] = label

        local dot = surface:create(strip, "progressFill", {
            width = dotRadius * 2,
            height = dotRadius * 2,
            borderSize = 1,
            radius = dotRadius,
            backgroundColor = { 0, 0, 0, 0 },
            borderColor = COCKPIT_COLORS.muted,
        })
        dot:SetPoint("CENTER", strip, "TOPLEFT", x + dotCenterX, dotY)
        strip.dots[i] = dot

        if i < #labels then
            local nextX = (i / 2) * railWidth
            local lineX = x + dotCenterX + dotRadius + lineGap
            local lineEndX = nextX + dotCenterX - dotRadius - lineGap
            local lineWidth = math.max(16, lineEndX - lineX)

            local line = strip:CreateTexture(nil, "BACKGROUND")
            line:SetTexture("Interface/Buttons/WHITE8X8")
            line:SetPoint("LEFT", strip, "TOPLEFT", lineX, dotY)
            line:SetSize(lineWidth, lineHeight)
            line:SetColorTexture(0.25, 0.32, 0.38, 0.70)

            local fill = strip:CreateTexture(nil, "ARTWORK")
            fill:SetTexture("Interface/Buttons/WHITE8X8")
            fill:SetPoint("LEFT", line, "LEFT", 0, 0)
            fill:SetSize(0, lineHeight)
            fill:SetColorTexture(COLORS.shardStatus.matched[1], COLORS.shardStatus.matched[2], COLORS.shardStatus.matched[3], 1)

            local dots = {}
            local dashWidth = 3
            local dashGap = 3
            local count = math.max(1, math.floor((lineWidth + dashGap) / (dashWidth + dashGap)))
            for dotIndex = 1, count do
                local segment = strip:CreateTexture(nil, "ARTWORK")
                segment:SetTexture("Interface/Buttons/WHITE8X8")
                segment:SetPoint("LEFT", line, "LEFT", (dotIndex - 1) * (dashWidth + dashGap), 0)
                segment:SetSize(dashWidth, lineHeight)
                segment:Hide()
                dots[#dots + 1] = segment
            end

            strip.lines[i] = {
                background = line,
                fill = fill,
                dots = dots,
                width = lineWidth,
            }
        end
    end
end

local function createStateCard(parent, topOffset)
    local card = createCard(parent, "CrateRushCockpitStateCard", topOffset, CARD_HEIGHT)
    createTitle(card, "STATE")

    local stateText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stateText:SetPoint("TOPLEFT", card, "TOPLEFT", PADDING, STATE_LABEL_TOP)
    stateText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PADDING, STATE_LABEL_TOP)
    stateText:SetJustifyH("LEFT")
    stateText:SetJustifyV("TOP")
    stateText:SetText("--")
    applyFontSize(stateText, -1)
    setTextColor(stateText, COCKPIT_COLORS.value)
    card.stateText = stateText

    local remainingText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    remainingText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", PADDING, CONTENT_VALUE_BOTTOM)
    remainingText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PADDING, CONTENT_VALUE_BOTTOM)
    remainingText:SetJustifyH("LEFT")
    remainingText:SetJustifyV("MIDDLE")
    if remainingText.SetWordWrap then remainingText:SetWordWrap(false) end
    remainingText:SetText("")
    applyFontSize(remainingText, 1)
    setTextColor(remainingText, COCKPIT_COLORS.value)
    card.remainingText = remainingText

    local actionTimerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionTimerText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PADDING, CONTENT_VALUE_BOTTOM)
    actionTimerText:SetWidth(72)
    actionTimerText:SetJustifyH("RIGHT")
    actionTimerText:SetJustifyV("MIDDLE")
    if actionTimerText.SetWordWrap then actionTimerText:SetWordWrap(false) end
    actionTimerText:SetText("")
    applyFontSize(actionTimerText, 1)
    setTextColor(actionTimerText, COLORS.shardStatus.matched)
    card.actionTimerText = actionTimerText

    createLifecycleStrip(card)
    return card
end

local function createTimingCard(parent, topOffset)
    local card = createCard(parent, "CrateRushCockpitTimingCard", topOffset, TIMING_HEIGHT)
    createTitle(card, "TIMING")

    local leftLabel = createColumnText(card, "Drop", "left", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(leftLabel, -1)
    setTextColor(leftLabel, CONTENT_LABEL_COLOR)
    card.dropLabel = leftLabel

    local leftValue = createColumnValue(card, "left", CONTENT_VALUE_BOTTOM, "RIGHT")
    leftValue:SetText("--")
    setTextColor(leftValue, COCKPIT_COLORS.muted)
    card.dropValue = leftValue

    createDivider(card)

    local rightLabel = createColumnText(card, "Land", "right", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(rightLabel, -1)
    setTextColor(rightLabel, CONTENT_LABEL_COLOR)
    card.landLabel = rightLabel

    local rightValue = createColumnValue(card, "right", CONTENT_VALUE_BOTTOM, "RIGHT")
    rightValue:SetText("--")
    setTextColor(rightValue, COCKPIT_COLORS.muted)
    card.landValue = rightValue

    return card
end

local function createPredictionCard(parent, topOffset)
    local card = createCard(parent, "CrateRushCockpitPredictionCard", topOffset, CARD_HEIGHT)
    createTitle(card, "PREDICTION")

    local locationLabel = createColumnText(card, "Location", "left", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(locationLabel, -1)
    setTextColor(locationLabel, CONTENT_LABEL_COLOR)
    card.locationLabel = locationLabel

    local coords = createColumnValue(card, "left", CONTENT_VALUE_BOTTOM, "RIGHT")
    coords:SetText("--")
    setTextColor(coords, COCKPIT_COLORS.value)
    card.coords = coords

    createDivider(card)

    local confidenceLabel = createColumnText(card, "Confidence", "right", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(confidenceLabel, -1)
    setTextColor(confidenceLabel, CONTENT_LABEL_COLOR)
    card.confidenceLabel = confidenceLabel

    local confidence = createColumnValue(card, "right", CONTENT_VALUE_BOTTOM, "RIGHT")
    confidence:SetText("--")
    setTextColor(confidence, COCKPIT_COLORS.value)
    card.confidence = confidence

    return card
end

local function createEnemyCard(parent, topOffset)
    local card = createCard(parent, "CrateRushCockpitEnemyCard", topOffset, CARD_HEIGHT)
    createTitle(card, "ENEMY")

    local factionLabel = createColumnText(card, "Total", "left", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(factionLabel, -1)
    setTextColor(factionLabel, CONTENT_LABEL_COLOR)
    card.factionLabel = factionLabel

    local faction = createColumnValue(card, "left", CONTENT_VALUE_BOTTOM, "RIGHT")
    faction:SetText("--")
    setTextColor(faction, COCKPIT_COLORS.value)
    card.faction = faction

    createDivider(card)

    local healersLabel = createColumnText(card, "Healers", "right", CONTENT_LABEL_TOP, "LEFT")
    applyFontSize(healersLabel, -1)
    setTextColor(healersLabel, CONTENT_LABEL_COLOR)
    card.healersLabel = healersLabel

    local healers = createColumnValue(card, "right", CONTENT_VALUE_BOTTOM, "RIGHT")
    healers:SetText("--")
    setTextColor(healers, COCKPIT_COLORS.value)
    card.healers = healers

    return card
end

local function getUnitRealmLabel(unit)
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    elseif UnitName then
        name = UnitName(unit)
    end

    if not realm or realm == "" then
        if GetNormalizedRealmName then
            realm = GetNormalizedRealmName()
        elseif GetRealmName then
            realm = GetRealmName()
        end
    end

    name = name or "Player"
    realm = realm or "Realm"
    realm = tostring(realm):gsub("%s+", "")
    return tostring(name) .. "-" .. tostring(realm)
end

local function getUnitClassColor(unit)
    local classFile
    if UnitClass then
        local _, detectedClass = UnitClass(unit)
        classFile = detectedClass
    end
    if not classFile then return COCKPIT_COLORS.value end

    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or nil
    if color then
        return { color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1 }
    end

    return COCKPIT_COLORS.value
end

local function getLeaderUnit()
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return "player"
    end

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. tostring(i)
            if UnitExists and UnitExists(unit) and UnitIsGroupLeader and UnitIsGroupLeader(unit) then
                return unit
            end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. tostring(i)
            if UnitExists and UnitExists(unit) and UnitIsGroupLeader and UnitIsGroupLeader(unit) then
                return unit
            end
        end
    end

    return "player"
end

local function getSyncPlayerDisplay()
    local unit = getLeaderUnit()
    return getUnitRealmLabel(unit), getUnitClassColor(unit)
end

local function getSyncDisplay()
    if CrateRush.syncDisplay and CrateRush.syncDisplay.getDisplay then
        return CrateRush.syncDisplay:getDisplay()
    end
    return { status = "unavailable" }
end

local function getSyncDotColor()
    local syncColors = COLORS.sync or {}
    local display = getSyncDisplay()
    local status = display and display.status or "unavailable"

    if status == "active" then
        return syncColors.active or { 0.22, 0.95, 0.46, 1.00 }
    elseif status == "rejected" then
        return syncColors.rejected or { 1.00, 0.25, 0.25, 1.00 }
    end

    return syncColors.unavailable or { 0.48, 0.53, 0.58, 1.00 }
end
local function createSyncCard(parent, topOffset)
    local card = surface:create(parent, "card", {
        width = WIDTH,
        height = SYNC_HEIGHT,
        name = "CrateRushCockpitSyncCard",
    })
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, topOffset)
    card:EnableMouse(true)

    local playerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerText:SetPoint("LEFT", card, "LEFT", PADDING, 0)
    playerText:SetPoint("RIGHT", card, "RIGHT", -72, 0)
    playerText:SetJustifyH("LEFT")
    local playerLabel, playerColor = getSyncPlayerDisplay()
    playerText:SetText(playerLabel)
    applyFontSize(playerText, -1)
    setTextColor(playerText, playerColor)
    card.playerText = playerText

    local syncText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncText:SetPoint("RIGHT", card, "RIGHT", -31, 0)
    syncText:SetText("Sync")
    applyFontSize(syncText, -1)
    setTextColor(syncText, COCKPIT_COLORS.value)
    card.syncText = syncText

    local dot = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dot:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    dot:SetText("\226\151\143")
    applyFontSize(dot, -1)
    local dotColor = getSyncDotColor()
    dot:SetTextColor(dotColor[1], dotColor[2], dotColor[3], dotColor[4] or 1)
    card.dot = dot

    return card
end

local function repaintCards()
    local border = surfaceBorder("card", 0.56)
    for _, card in pairs(cards) do
        if card then
            surface:setColors(card, COCKPIT_COLORS.bg, border)
            updateDivider(card)
            setTextColor(card.title, getTitleColor())
        end
    end
end

local function createFrame()
    if frame then return frame end

    local anchor = getAnchor()
    if not anchor then return nil end

    local heights = { CARD_HEIGHT, TIMING_HEIGHT, CARD_HEIGHT, CARD_HEIGHT, SYNC_HEIGHT }
    local totalHeight = CARD_HEIGHT + TIMING_HEIGHT + (CARD_HEIGHT * 2) + SYNC_HEIGHT + (SECTION_GAP * 4)

    frame = CreateFrame("Frame", "CrateRushCockpitFrame", UIParent)
    frame:SetSize(WIDTH, totalHeight)
    frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP_FROM_HEADER)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)

    cards.state = createStateCard(frame, cardTop(1, heights))
    cards.timing = createTimingCard(frame, cardTop(2, heights))
    cards.prediction = createPredictionCard(frame, cardTop(3, heights))
    cards.enemy = createEnemyCard(frame, cardTop(4, heights))
    cards.sync = createSyncCard(frame, cardTop(5, heights))

    cards.state:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsShiftKeyDown() and uiActions and uiActions.announceState then
            local statePayload = getManualStatePayload(true)
            if statePayload then
                uiActions:announceState(statePayload, getManualPredictionPayload(false))
            else
                logManualBlock("missing_fresh_state_payload", nil)
            end
        end
    end)
    cards.timing:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsShiftKeyDown() and uiActions and uiActions.announceTiming then
            local statePayload = getManualStatePayload(false)
            local predictionPayload = getManualPredictionPayload(false)
            if statePayload or predictionPayload then
                uiActions:announceTiming(statePayload, predictionPayload)
            else
                logManualBlock("missing_fresh_payload", nil)
            end
        end
    end)
    cards.prediction:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsShiftKeyDown() and uiActions and uiActions.announcePrediction then
            uiActions:announcePrediction(getManualPredictionPayload(true))
        elseif button == "RightButton" and IsShiftKeyDown() and uiActions and uiActions.pinPrediction then
            uiActions:pinPrediction(getManualPredictionPayload(true))
        end
    end)
    cards.enemy:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsShiftKeyDown() and uiActions and uiActions.announceEnemy then
            uiActions:announceEnemy(getManualEnemyPayload(true))
        end
    end)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.accum = (self.accum or 0) + elapsed
        if self.accum >= 1 then
            self.accum = 0
            cockpit:render()
        end
    end)

    anchor:HookScript("OnDragStop", function()
        if not frame then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP_FROM_HEADER)
    end)

    cockpit:render()
    frame:Hide()
    return frame
end

local function getSelectedStatePayload()
    return getManualStatePayload(false)
end

local function getSelectedPredictionPayload()
    return getManualPredictionPayload(false)
end

local function getSelectedStateDisplay()
    local payload = getSelectedStatePayload()
    local predictionPayload = getSelectedPredictionPayload()
    if uiModel and uiModel.formatCrateState then
        return uiModel:formatCrateState(payload, predictionPayload)
    end
    local placeholder = getPlaceholder()
    local state = placeholder.state or {}
    return {
        lifecycleActive = false,
        mode = "idle",
        label = state.label or "Waiting",
        detail = state.detail or "--",
        activeStep = 0,
    }
end

local function getSelectedPredictionDisplay()
    local payload = getSelectedPredictionPayload()
    local statePayload = getSelectedStatePayload()
    if uiModel and uiModel.formatPrediction then
        return uiModel:formatPrediction(payload, statePayload)
    end
    local placeholder = getPlaceholder()
    local prediction = placeholder.prediction or {}
    return {
        coords = prediction.detail or "--",
        confidenceText = "--",
        dropText = "--",
        landText = "--",
    }
end

local function renderLifecycleStrip(display)
    local card = cards.state
    if not card or not card.lifecycleStrip then return end

    local mode = display and display.mode or "idle"
    local active = mode == "progress" and (display.activeStep or 0) > 0
    local showText = not active and mode ~= "empty"

    card.stateText:SetShown(showText)
    card.remainingText:SetShown(showText)
    if card.actionTimerText then
        card.actionTimerText:SetShown(showText)
    end
    card.lifecycleStrip:SetShown(active)

    if not active then return end

    local accent = getTitleColor()
    local activeStep = display.activeStep or 0

    for i = 1, #card.lifecycleStrip.labels do
        local reached = i <= activeStep
        setTextColor(card.lifecycleStrip.labels[i], reached and accent or COCKPIT_COLORS.muted)
        surface:setColors(
            card.lifecycleStrip.dots[i],
            reached and accent or { 0, 0, 0, 0 },
            reached and accent or COCKPIT_COLORS.muted
        )
    end

    for i, line in ipairs(card.lifecycleStrip.lines or {}) do
        local progress = 0
        local dotted = false
        if i == 1 then
            progress = activeStep > 1 and 1 or (display.progressToDrop or 0)
            dotted = activeStep == 1 and display.dropTimingAvailable ~= true
        elseif i == 2 then
            progress = activeStep > 2 and 1 or (activeStep == 2 and (display.progressToLand or 0) or 0)
            dotted = activeStep == 2 and display.landTimingAvailable ~= true
        end

        progress = math.max(0, math.min(1, progress))
        if line.background then line.background:SetShown(not dotted) end
        if line.fill then
            local fillWidth = math.max(0, line.width * progress)
            line.fill:SetShown(not dotted and fillWidth > 0.5)
            if fillWidth > 0.5 then
                line.fill:SetWidth(fillWidth)
            end
            setTextureColor(line.fill, accent)
        end
        for _, dot in ipairs(line.dots or {}) do
            dot:SetShown(dotted)
            setTextureColor(dot, accent)
        end
    end
end

local function positionStateContent(hasRightTimer)
    local card = cards.state
    if not card or not card.remainingText then return end

    card.remainingText:ClearAllPoints()
    card.remainingText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", PADDING, CONTENT_VALUE_BOTTOM)
    card.remainingText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", hasRightTimer and -86 or -PADDING, CONTENT_VALUE_BOTTOM)
    card.remainingText:SetJustifyH("LEFT")
    card.remainingText:SetJustifyV("MIDDLE")
end

local function renderStateText(display)
    if not cards.state then return end

    local mode = display and display.mode or "idle"
    positionStateContent(false)
    setTextColor(cards.state.remainingText, COCKPIT_COLORS.value)
    if cards.state.actionTimerText then
        setTextColor(cards.state.actionTimerText, COLORS.shardStatus.matched)
    end

    if mode == "empty" then
        cards.state.stateText:SetText("")
        cards.state.remainingText:SetText("")
        if cards.state.actionTimerText then
            cards.state.actionTimerText:SetText("")
        end
        return
    end

    if mode == "action" then
        local timerText = display.remainingText or ""
        positionStateContent(timerText ~= "")
        cards.state.stateText:SetText(display.label or "")
        cards.state.remainingText:SetText(display.detail or "")
        if cards.state.actionTimerText then
            cards.state.actionTimerText:SetText(timerText)
        end
        return
    end

    cards.state.stateText:SetText(display.detail or display.label or "--")
    cards.state.remainingText:SetText(display.remainingText or "")
    if cards.state.actionTimerText then
        cards.state.actionTimerText:SetText("")
    end
end

function cockpit:render()
    if not frame then return end

    local stateDisplay = getSelectedStateDisplay()
    local predictionDisplay = getSelectedPredictionDisplay()

    renderStateText(stateDisplay)
    renderLifecycleStrip(stateDisplay)

    cards.timing.dropValue:SetText(predictionDisplay.dropText or "--:--")
    cards.timing.landValue:SetText(predictionDisplay.landText or "--:--")
    setTextColor(cards.timing.dropValue, predictionDisplay.dropText == "--" and COCKPIT_COLORS.muted or COCKPIT_COLORS.value)
    setTextColor(cards.timing.landValue, predictionDisplay.landText == "--" and COCKPIT_COLORS.muted or COCKPIT_COLORS.value)

    cards.prediction.coords:SetText(predictionDisplay.coords or "--")
    cards.prediction.confidence:SetText(predictionDisplay.confidenceText or "--")

    if cards.sync then
        local playerLabel, playerColor = getSyncPlayerDisplay()
        cards.sync.playerText:SetText(playerLabel)
        setTextColor(cards.sync.playerText, playerColor)
        cards.sync.syncText:SetText("Sync")
        local dotColor = getSyncDotColor()
        cards.sync.dot:SetTextColor(dotColor[1], dotColor[2], dotColor[3], dotColor[4] or 1)
    end
    local enemyPayload = selectedKey and enemyByKey[selectedKey] or nil
    local enemyWarning = enemyPayload and enemyPayload.warning == "enemy_nameplates_off"
    if enemyWarning then
        cards.enemy.faction:SetText("Nameplates OFF")
        cards.enemy.healers:SetText("--")
        surface:setColors(cards.enemy, ENEMY_WARNING_BG, ENEMY_WARNING_BORDER)
        setTextColor(cards.enemy.title, ENEMY_WARNING_TEXT)
        setTextColor(cards.enemy.faction, ENEMY_WARNING_TEXT)
        setTextColor(cards.enemy.healers, COCKPIT_COLORS.muted)
        if cards.enemy.divider then
            setTextureColor(cards.enemy.divider, ENEMY_WARNING_BORDER)
        end
    else
        cards.enemy.faction:SetText(enemyPayload and enemyPayload.totalRange or "--")
        cards.enemy.healers:SetText(enemyPayload and enemyPayload.healerRange or "--")
        surface:setColors(cards.enemy, COCKPIT_COLORS.bg, surfaceBorder("card", 0.56))
        updateDivider(cards.enemy)
        setTextColor(cards.enemy.title, getTitleColor())
        setTextColor(cards.enemy.faction, enemyPayload and COCKPIT_COLORS.value or COCKPIT_COLORS.muted)
        setTextColor(cards.enemy.healers, enemyPayload and COCKPIT_COLORS.value or COCKPIT_COLORS.muted)
    end
end

function cockpit:applyTheme()
    repaintCards()
end

function cockpit:show()
    local f = createFrame()
    if not f then return end
    cockpit:render()
    f:Show()
end

function cockpit:hide()
    if frame then frame:Hide() end
end

function cockpit:isShown()
    return frame and frame:IsShown()
end

function cockpit:getFrame()
    return frame
end

function cockpit:onZoneShardStatusChanged(payload)
    if type(payload) ~= "table" then return end
    selectedZoneID = payload.zoneID
    selectedShardID = payload.shardID
    selectedKey = makeKey(selectedZoneID, selectedShardID)
    cockpit:render()
end

function cockpit:onCrateStateChanged(payload)
    if type(payload) ~= "table" then return end
    local key = makeKey(payload.zoneID, payload.shardID)
    if not key then return end
    stateByKey[key] = payload
    cockpit:render()
end

function cockpit:onActiveTimerChanged(payload)
    if type(payload) ~= "table" or type(payload.sorted) ~= "table" then return end
    cockpit:render()
end

function cockpit:onPredictionUpdated(payload)
    if type(payload) ~= "table" then return end
    local key = makeKey(payload.zoneID, payload.shardID)
    if not key then return end
    predictionByKey[key] = payload
    if payload.zoneID then
        predictionByZone[tostring(payload.zoneID)] = payload
    end
    cockpit:render()
end

function cockpit:onPredictionCleared(payload)
    if type(payload) ~= "table" then return end

    local key = makeKey(payload.zoneID, payload.shardID)
    if key then predictionByKey[key] = nil end
    if payload.zoneID then predictionByZone[tostring(payload.zoneID)] = nil end
    cockpit:render()
end

function cockpit:onEnemyPresenceChanged(payload)
    if type(payload) ~= "table" then return end
    local key = makeKey(payload.zoneID, payload.shardID)
    if not key then return end
    if payload.hasData or payload.warning then
        enemyByKey[key] = payload
    else
        enemyByKey[key] = nil
    end
    cockpit:render()
end

if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT then
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED,
        cockpit,
        "onZoneShardStatusChanged"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.CRATE_STATE_CHANGED,
        cockpit,
        "onCrateStateChanged"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ACTIVE_TIMER_CHANGED,
        cockpit,
        "onActiveTimerChanged"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.PREDICTION_UPDATED,
        cockpit,
        "onPredictionUpdated"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.PREDICTION_CLEARED,
        cockpit,
        "onPredictionCleared"
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ENEMY_PRESENCE_CHANGED,
        cockpit,
        "onEnemyPresenceChanged"
    )
end

