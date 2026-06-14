-- CrateRush
-- ui/frames.lua - Main shared header frame. Fixed UI shell, no domain logic.

local frames = {}
CrateRush.frames = frames

local HEADER_LAYOUT = (CrateRush.layout and CrateRush.layout.header) or {}
local FRAME_WIDTH = HEADER_LAYOUT.width or 820
local HEADER_HEIGHT = HEADER_LAYOUT.height or 92
local BUTTON_SIZE = HEADER_LAYOUT.buttonSize or 42
local ICON_SIZE = HEADER_LAYOUT.iconSize or 18
local INDICATOR_WIDTH = HEADER_LAYOUT.warModeIndicatorWidth or 20
local INDICATOR_HEIGHT = HEADER_LAYOUT.warModeIndicatorHeight or 48
local LEFT_PADDING = HEADER_LAYOUT.leftPadding or 22
local TITLE_LEFT_GAP = HEADER_LAYOUT.titleLeftGap or 26
local TITLE_RIGHT_GAP = HEADER_LAYOUT.titleRightGap or 20
local CLOSE_RIGHT_PADDING = HEADER_LAYOUT.closeRightPadding or 16
local SETTINGS_CLOSE_GAP = HEADER_LAYOUT.settingsCloseGap or 10
local SHARD_SETTINGS_GAP = HEADER_LAYOUT.shardSettingsGap or 16
local SHARD_BADGE_WIDTH = HEADER_LAYOUT.shardBadgeWidth or 230
local SHARD_BADGE_HEIGHT = HEADER_LAYOUT.shardBadgeHeight or 34

local ICON_SETTINGS = "Interface/AddOns/CrateRush/media/icons/icon_settings"
local ICON_CLOSE = "Interface/AddOns/CrateRush/media/icons/icon_close"
local WHITE_TEXTURE = "Interface/Buttons/WHITE8X8"

local SHARD_STATUS = CrateRush.SHARD_STATUS
local uiModel = CrateRush.uiModel
local uiActions = CrateRush.uiActions
local surface = CrateRush.surface
local uiColors = CrateRush.theme:getUIColors()

local frame
local currentStatus = SHARD_STATUS.UNKNOWN
local lastHeaderModel
local DEFAULT_POSITION = {
    point         = "CENTER",
    relativePoint = "CENTER",
    x             = 0,
    y             = 0,
}

local function withAlpha(color, alpha)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], alpha }
end

local function surfaceBorder(name, alpha)
    local color = CrateRush.theme and CrateRush.theme.getSurfaceBorder and CrateRush.theme:getSurfaceBorder(name) or nil
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], alpha or color[4] or 1 }
end

local function setTextColor(fontString, color, alpha)
    if not fontString or not color then return end
    fontString:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function setTextureColor(texture, color, alpha)
    if not texture or not color then return end
    texture:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function getHeaderBannerTexture()
    if CrateRush.theme and CrateRush.theme.getHeaderBannerTexture then
        return CrateRush.theme:getHeaderBannerTexture()
    end
    return nil
end

local function updateHeaderBanner()
    if not frame or not frame.headerBanner then return end
    local texture = getHeaderBannerTexture()
    if texture then
        frame.headerBanner:SetTexture(texture)
        frame.headerBanner:SetAlpha(0.72)
        frame.headerBanner:Show()
    else
        frame.headerBanner:Hide()
    end
end

local function setIndicatorGradient(texture, color)
    if not texture or type(color) ~= "table" then return end
    local r, g, b = color[1], color[2], color[3]
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha("HORIZONTAL", r, g, b, 0.95, r, g, b, 0.02)
    else
        texture:SetColorTexture(r, g, b, 0.70)
    end
end

local function colorForStatus(status)
    if status == SHARD_STATUS.MATCHED or status == "match" or status == "confirmed" then
        return uiColors.shardStatus.matched
    elseif status == SHARD_STATUS.CHECKING or status == "pending" then
        return uiColors.shardStatus.checking
    elseif status == SHARD_STATUS.MISMATCH or status == "different" or status == "failed" then
        return uiColors.shardStatus.mismatch
    end
    return uiColors.shardStatus.unknown
end

local function statusText(status)
    if status == SHARD_STATUS.MATCHED or status == "match" or status == "confirmed" then
        return "Confirmed"
    elseif status == SHARD_STATUS.CHECKING or status == "pending" then
        return "Scanning"
    elseif status == SHARD_STATUS.MISMATCH or status == "different" or status == "failed" then
        return "Mismatch"
    end
    return "Unknown"
end

local function applyFontSize(fontString, size, flags)
    if not fontString then return end
    local font = STANDARD_TEXT_FONT or select(1, fontString:GetFont())
    if font then
        fontString:SetFont(font, size, flags)
    end
end

local function shouldShowWarmodeIndicator()
    if uiModel and uiModel.shouldShowWarmodeIndicator then
        return uiModel:shouldShowWarmodeIndicator()
    end
    return true
end

local function getSavedPosition()
    local position = CrateRush.config
        and CrateRush.config.get
        and CrateRush.config:get("mainFramePosition", DEFAULT_POSITION)
        or DEFAULT_POSITION

    if type(position) ~= "table" or type(position.point) ~= "string" then
        return DEFAULT_POSITION
    end

    return position
end

local function applySavedPosition()
    if not frame then return end

    local position = getSavedPosition()
    frame:ClearAllPoints()
    frame:SetPoint(
        position.point or DEFAULT_POSITION.point,
        UIParent,
        position.relativePoint or position.point or DEFAULT_POSITION.relativePoint,
        tonumber(position.x) or DEFAULT_POSITION.x,
        tonumber(position.y) or DEFAULT_POSITION.y
    )
end

local function savePosition()
    if not frame or not CrateRush.config or not CrateRush.config.set then return end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end

    CrateRush.config:set("mainFramePosition", {
        point         = point,
        relativePoint = relativePoint or point,
        x             = tonumber(x) or 0,
        y             = tonumber(y) or 0,
    }, "mainFrame")
end

local function createButton(parent, iconPath)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameLevel(parent:GetFrameLevel() + 2)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexture(iconPath)
    setTextureColor(icon, uiColors.neutral.iconNormal)
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        setTextureColor(self.icon, uiColors.neutral.iconHover)
    end)
    button:SetScript("OnLeave", function(self)
        setTextureColor(self.icon, uiColors.neutral.iconNormal)
    end)

    return button
end

local function updateShardBadge(status, shardID)
    if not frame or not frame.shardBadge then return end

    local resolvedStatus = status or currentStatus or SHARD_STATUS.UNKNOWN
    local color = colorForStatus(resolvedStatus)
    local shardText = shardID ~= nil and shardID ~= "" and tostring(shardID) or "--"

    frame.shardBadgeText:SetText("Shard " .. shardText .. " - " .. statusText(resolvedStatus))
    setTextColor(frame.shardBadgeText, uiColors.neutral.textPrimary)
    setTextColor(frame.shardBadgeDot, color)
    surface:setColors(frame.shardBadge, withAlpha(color, 0.14), withAlpha(color, 0.70))
end

local function createFrame()
    if frame then return end

    frame = CreateFrame("Frame", "CrateRushMainFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, HEADER_HEIGHT)
    applySavedPosition()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")

    local headerSurface = surface:create(frame, "header", {
        width = FRAME_WIDTH,
        height = HEADER_HEIGHT,
        borderSize = 1,
    })
    headerSurface:SetAllPoints(frame)
    headerSurface:SetFrameLevel(frame:GetFrameLevel())
    frame.headerSurface = headerSurface

    local headerBanner = headerSurface:CreateTexture(nil, "BACKGROUND")
    headerBanner:SetDrawLayer("BACKGROUND", 1)
    headerBanner:SetAllPoints(headerSurface)
    headerBanner:SetHorizTile(false)
    headerBanner:SetVertTile(false)
    headerBanner:SetBlendMode("BLEND")
    frame.headerBanner = headerBanner
    updateHeaderBanner()

    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetAllPoints(frame)
    contentFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.contentFrame = contentFrame

    local closeButton = createButton(contentFrame, ICON_CLOSE)
    closeButton:SetPoint("RIGHT", contentFrame, "RIGHT", -CLOSE_RIGHT_PADDING, 0)
    closeButton:SetScript("OnClick", function()
        frames:hide()
    end)
    frame.closeButton = closeButton

    local settingsButton = createButton(contentFrame, ICON_SETTINGS)
    settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -SETTINGS_CLOSE_GAP, 0)
    settingsButton:SetScript("OnClick", function()
        if uiActions and uiActions.openSettings then
            uiActions:openSettings()
        end
    end)
    frame.settingsButton = settingsButton

    local shardBadge = surface:create(contentFrame, "badge", {
        width = SHARD_BADGE_WIDTH,
        height = SHARD_BADGE_HEIGHT,
        pill = false,
        family = "small",
        radius = 6,
    })
    shardBadge:SetPoint("RIGHT", settingsButton, "LEFT", -SHARD_SETTINGS_GAP, 0)
    frame.shardBadge = shardBadge

    local shardBadgeDot = shardBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shardBadgeDot:SetPoint("LEFT", shardBadge, "LEFT", 10, 0)
    shardBadgeDot:SetText("\226\151\143")
    applyFontSize(shardBadgeDot, 13, nil)
    shardBadgeDot:SetShadowColor(0, 0, 0, 0)
    frame.shardBadgeDot = shardBadgeDot

    local shardBadgeText = shardBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shardBadgeText:SetPoint("LEFT", shardBadgeDot, "RIGHT", 6, 0)
    shardBadgeText:SetPoint("RIGHT", shardBadge, "RIGHT", -9, 0)
    shardBadgeText:SetJustifyH("LEFT")
    applyFontSize(shardBadgeText, 9, nil)
    frame.shardBadgeText = shardBadgeText

    local title = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("LEFT", contentFrame, "LEFT", LEFT_PADDING + 10, 0)
    title:SetPoint("RIGHT", shardBadge, "LEFT", -TITLE_RIGHT_GAP, 0)
    title:SetJustifyH("LEFT")
    title:SetText("CrateRush")
    applyFontSize(title, 20, "THICKOUTLINE")
    title:SetTextColor(0.92, 0.96, 1.00, 1)
    title:SetShadowColor(0, 0, 0, 0.55)
    title:SetShadowOffset(1, -1)
    frame.title = title
    frame.label = title

    updateShardBadge(currentStatus, nil)

    if lastHeaderModel then
        frames:renderHeader(lastHeaderModel)
    end

    frame:Hide()
end

function frames:applyTheme()
    if not frame then return end
    if frame.headerSurface then
        surface:setColors(
            frame.headerSurface,
            withAlpha(uiColors.header.bg or { 0.02, 0.03, 0.04, 1 }, 0.68),
            surfaceBorder("header", 0.64)
        )
    end
    updateHeaderBanner()
    updateShardBadge(currentStatus, lastHeaderModel and lastHeaderModel.shardID or nil)
    frames:updateIndicator()
end

function frames:show()
    createFrame()
    frames:applyTheme()
    frames:updateIndicator()
    frame:Show()
    if CrateRush.timerbars then
        CrateRush.timerbars:showContainer()
    end
    if CrateRush.cockpit then
        CrateRush.cockpit:show()
    end
end

function frames:hide()
    if frame then frame:Hide() end
    if CrateRush.timerbars then
        CrateRush.timerbars:hideContainer()
    end
    if CrateRush.cockpit then
        CrateRush.cockpit:hide()
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
    if not frame or not frame.warModeIndicator then return end

    if shouldShowWarmodeIndicator() then
        frame.warModeIndicator:Show()
    else
        frame.warModeIndicator:Hide()
        return
    end

    local warModeDisplay = uiModel and uiModel.getWarModeDisplay and uiModel:getWarModeDisplay() or nil
    if warModeDisplay and warModeDisplay.active then
        setIndicatorGradient(frame.warModeIndicator, { 0.04, 0.95, 0.32, 1 })
    else
        setIndicatorGradient(frame.warModeIndicator, { 1.00, 0.18, 0.18, 1 })
    end
end

function frames:setLabel(text, status)
    if not frame then return end
    frame.title:SetText(text or "CrateRush")
    currentStatus = status or currentStatus or SHARD_STATUS.UNKNOWN
    updateShardBadge(currentStatus, nil)
end

function frames:renderHeader(headerModel)
    if type(headerModel) ~= "table" then return end

    lastHeaderModel = headerModel
    if not frame then return end

    currentStatus = headerModel.status or currentStatus or SHARD_STATUS.UNKNOWN
    frame.title:SetText(headerModel.zoneName or headerModel.label or "CrateRush")
    updateShardBadge(currentStatus, headerModel.shardID)
end

function frames:setZoneShard(zoneName, shardID, status)
    local headerModel
    if uiModel and uiModel.formatHeader then
        headerModel = uiModel:formatHeader({
            zoneName = zoneName,
            shardID = shardID,
            status = status,
        })
    else
        headerModel = {
            zoneName = zoneName or "Unknown",
            shardID = shardID,
            status = status,
        }
    end
    frames:renderHeader(headerModel)
end

function frames:setShardStatus(status)
    currentStatus = status or SHARD_STATUS.UNKNOWN
    updateShardBadge(currentStatus, lastHeaderModel and lastHeaderModel.shardID or nil)
end

function frames:getFrame()
    return frame
end

function frames:isShown()
    return frame and frame:IsShown()
end

function frames:adjustHeight(barCount)
end

local function onZoneShardStatusChanged(payload)
    if type(payload) ~= "table" then return end
    frames:setZoneShard(payload.zoneName, payload.shardID, payload.status)
end

if CrateRush.domainEvents and CrateRush.DOMAIN_EVENT then
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED,
        onZoneShardStatusChanged
    )
    CrateRush.domainEvents:subscribe(
        CrateRush.DOMAIN_EVENT.PLAYER_CONTEXT_CHANGED,
        function()
            frames:updateIndicator()
        end
    )
end


