-- CrateRush
-- ui/frames.lua - Main header frame. Fixed size. Renders only, no logic.

local frames = {}
CrateRush.frames = frames

local FRAME_WIDTH   = 312
local HEADER_HEIGHT = 32
local BUTTON_SIZE   = 26
local ICON_SIZE     = 16
local INDICATOR_WIDTH = 15
local INDICATOR_HEIGHT = 22

local WHITE_TEXTURE = "Interface/Buttons/WHITE8X8"
local INDICATOR_WARMODE_ON  = "Interface/AddOns/CrateRush/media/icons/indicator_warmode_on"
local INDICATOR_WARMODE_OFF = "Interface/AddOns/CrateRush/media/icons/indicator_warmode_off"
local ICON_SETTINGS = "Interface/AddOns/CrateRush/media/icons/icon_settings"
local ICON_CLOSE    = "Interface/AddOns/CrateRush/media/icons/icon_close"

local SHARD_STATUS = CrateRush.SHARD_STATUS

local COLORS = {
    bg           = { 0.035, 0.040, 0.045, 0.50 },
    iconHover    = { 1.000, 1.000, 1.000, 0.82 },
    matched      = { 0.220, 0.950, 0.460, 1.00 },
    checking     = { 1.000, 0.780, 0.180, 1.00 },
    mismatch     = { 1.000, 0.250, 0.250, 1.00 },
    unknown      = { 0.900, 0.920, 0.940, 1.00 },
}

local frame
local currentStatus = SHARD_STATUS.UNKNOWN
local lastZoneShardPayload = nil

local function colorForStatus(status)
    if status == SHARD_STATUS.MATCHED or status == "match" or status == "confirmed" then
        return COLORS.matched
    elseif status == SHARD_STATUS.CHECKING or status == "pending" then
        return COLORS.checking
    elseif status == SHARD_STATUS.MISMATCH or status == "different" or status == "failed" then
        return COLORS.mismatch
    end
    return COLORS.unknown
end

local function setTextureColor(texture, color)
    if not texture or not color then return end
    texture:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function setTextColor(fontString, color)
    if not fontString or not color then return end
    fontString:SetTextColor(color[1], color[2], color[3], color[4])
end

local function createFlatButton(parent, name, iconPath)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexture(iconPath)
    setTextureColor(icon, { 1, 1, 1, 1 })
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        setTextureColor(self.icon, COLORS.iconHover)
    end)
    button:SetScript("OnLeave", function(self)
        setTextureColor(self.icon, { 1, 1, 1, 1 })
    end)

    return button
end

local function updateAccentLines()
    if not frame or not frame.label or not frame.labelBox then return end

    local boxWidth = frame.labelBox:GetWidth() or 0
    local textWidth = frame.label:GetStringWidth() or 0
    local lineWidth = math.ceil(textWidth + 22)

    if boxWidth > 0 then
        lineWidth = math.min(lineWidth, math.max(40, boxWidth - 8))
    end

    lineWidth = math.max(40, lineWidth)
    frame.labelTopLine:SetWidth(lineWidth)
    frame.labelBottomLine:SetWidth(lineWidth)
end

local function applyZoneStatus(status)
    if not frame then return end

    currentStatus = status or SHARD_STATUS.UNKNOWN
    local color = colorForStatus(currentStatus)

    setTextColor(frame.label, color)
    frame.labelTopLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    frame.labelBottomLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    updateAccentLines()
end

local function createFrame()
    if frame then return end

    frame = CreateFrame("Frame", "CrateRushMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, HEADER_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")

    frame:SetBackdrop({
        bgFile = WHITE_TEXTURE,
    })
    frame:SetBackdropColor(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], COLORS.bg[4])

    local warModeIndicator = frame:CreateTexture(nil, "ARTWORK")
    warModeIndicator:SetSize(INDICATOR_WIDTH, INDICATOR_HEIGHT)
    warModeIndicator:SetPoint("LEFT", frame, "LEFT", 6, 0)
    warModeIndicator:SetTexture(INDICATOR_WARMODE_OFF)
    frame.warModeIndicator = warModeIndicator

    local closeBtn = createFlatButton(frame, nil, ICON_CLOSE)
    closeBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function()
        frames:hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        setTextureColor(self.icon, COLORS.iconHover)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        setTextureColor(self.icon, { 1, 1, 1, 1 })
    end)
    frame.closeButton = closeBtn

    local settingsBtn = createFlatButton(frame, nil, ICON_SETTINGS)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    settingsBtn:SetScript("OnClick", function()
        if CrateRush.onSettingsClicked then
            CrateRush.onSettingsClicked()
        elseif CrateRush.debug then
            CrateRush.debug:log("SETTINGS | settings panel is not implemented yet")
        end
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        setTextureColor(self.icon, COLORS.iconHover)
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        setTextureColor(self.icon, { 1, 1, 1, 1 })
    end)
    frame.settingsButton = settingsBtn

    local labelBox = CreateFrame("Frame", nil, frame)
    labelBox:SetPoint("LEFT", warModeIndicator, "RIGHT", 9, 0)
    labelBox:SetPoint("RIGHT", settingsBtn, "LEFT", -8, 0)
    labelBox:SetHeight(HEADER_HEIGHT)
    labelBox:SetScript("OnSizeChanged", updateAccentLines)
    frame.labelBox = labelBox

    local topLine = labelBox:CreateTexture(nil, "ARTWORK")
    topLine:SetPoint("TOP", labelBox, "TOP", 0, -5)
    topLine:SetHeight(1)
    topLine:SetWidth(60)
    frame.labelTopLine = topLine

    local bottomLine = labelBox:CreateTexture(nil, "ARTWORK")
    bottomLine:SetPoint("BOTTOM", labelBox, "BOTTOM", 0, 5)
    bottomLine:SetHeight(1)
    bottomLine:SetWidth(60)
    frame.labelBottomLine = bottomLine

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", labelBox, "LEFT", 4, 0)
    label:SetPoint("RIGHT", labelBox, "RIGHT", -4, 0)
    label:SetJustifyH("CENTER")
    label:SetText("CrateRush")
    local font, size, flags = label:GetFont()
    label:SetFont(font, (size or 10) + 2, flags)
    frame.label = label

    if lastZoneShardPayload then
        frames:setZoneShard(lastZoneShardPayload.zoneName, lastZoneShardPayload.shardID, lastZoneShardPayload.status)
    else
        applyZoneStatus(currentStatus)
    end

    frame:Hide()
end

function frames:show()
    createFrame()
    frames:updateIndicator()
    frame:Show()
    if CrateRush.timerbars then
        CrateRush.timerbars:showContainer()
    end
end

function frames:hide()
    if frame then frame:Hide() end
    if CrateRush.timerbars then
        CrateRush.timerbars:hideContainer()
    end
end

function frames:toggle()
    createFrame()
    if frame:IsShown() then
        frames:hide()
    else
        frames:show()
    end
end

function frames:updateIndicator()
    if not frame then return end

    local ok, inWarMode = pcall(C_PvP.IsWarModeDesired)
    if ok and inWarMode then
        frame.warModeIndicator:SetTexture(INDICATOR_WARMODE_ON)
    else
        frame.warModeIndicator:SetTexture(INDICATOR_WARMODE_OFF)
    end
end

local indicatorEventFrame = CreateFrame("Frame")
indicatorEventFrame:RegisterEvent(CrateRush.EVT.PLAYER_ENTERING_WORLD)
indicatorEventFrame:RegisterEvent(CrateRush.EVT.ZONE_CHANGED_NEW_AREA)
indicatorEventFrame:SetScript("OnEvent", function()
    frames:updateIndicator()
end)

function frames:setLabel(text, status)
    if not frame then return end
    frame.label:SetText(text or "CrateRush")
    applyZoneStatus(status or currentStatus)
    updateAccentLines()
end

function frames:setZoneShard(zoneName, shardID, status)
    if not frame then return end

    local zone = zoneName or "Unknown"
    local shard = shardID and tostring(shardID) or nil

    if shard then
        frame.label:SetText(zone .. " [" .. shard .. "]")
    elseif status == SHARD_STATUS.CHECKING then
        frame.label:SetText(zone .. " [checking shard]")
    else
        frame.label:SetText(zone)
    end
    applyZoneStatus(status)
    updateAccentLines()
end

function frames:setShardStatus(status)
    applyZoneStatus(status)
end

function frames:getFrame()
    return frame
end

function frames:isShown()
    return frame and frame:IsShown()
end

-- No height adjustment needed - timers frame handles its own height.
function frames:adjustHeight(barCount)
end

local function onZoneShardStatusChanged(payload)
    if type(payload) ~= "table" then return end

    lastZoneShardPayload = payload
    frames:setZoneShard(payload.zoneName, payload.shardID, payload.status)
end

if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT then
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED,
        onZoneShardStatusChanged
    )
end
