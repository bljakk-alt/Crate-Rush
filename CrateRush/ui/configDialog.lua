-- CrateRush
-- ui/configDialog.lua - Faction-themed configuration dialog.

local dialog = {}
CrateRush.configDialog = dialog

local WHITE_TEXTURE = "Interface/Buttons/WHITE8X8"

local WIDTH = 980
local HEIGHT = 620
local HEADER_HEIGHT = 118
local NAV_WIDTH = 170
local FOOTER_HEIGHT = 54
local CONTENT_WIDTH = WIDTH - NAV_WIDTH - 62
local CONTENT_PAGE_HEIGHT = 760
local CONTROL_SIZE = 18
local BUTTON_CLOSE_SIZE = 20

local CONFIG_CLOSE_TEXCOORDS = {
    normal = { 0.000000, 0.410423, 0.000000, 1.000000 },
    disabled = { 0.586319, 1.000000, 0.000000, 1.000000 },
}

local frame
local navButtons = {}
local pages = {}
local controls = {}
local themedTexts = {}
local themedButtons = {}
local activeSection = "general"
local pendingValues = {}

local function hasPendingValue(key)
    return key and pendingValues[key] ~= nil
end

local function getPendingOrConfig(key, fallback)
    if hasPendingValue(key) then
        return pendingValues[key]
    end
    return CrateRush.config:get(key, fallback)
end

local function getPendingBoolean(key, fallback)
    local value = getPendingOrConfig(key, fallback)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "string" then
        local lower = value:lower()
        if lower == "true" or lower == "1" or lower == "yes" or lower == "on" then return true end
        if lower == "false" or lower == "0" or lower == "no" or lower == "off" then return false end
    end
    return fallback
end

local function getPendingNumber(key, fallback)
    return tonumber(getPendingOrConfig(key, fallback)) or fallback
end

local function setPendingValue(key, value)
    if key then
        pendingValues[key] = value
    end
end

local function clearPendingValues()
    pendingValues = {}
end

local function applyPendingValues()
    if CrateRush.config and CrateRush.config.apply then
        CrateRush.config:apply(pendingValues, "configDialog")
    else
        for key, value in pairs(pendingValues) do
            CrateRush.config:set(key, value, "configDialog")
        end
    end
    clearPendingValues()
end

local SECTIONS = {
    { id = "general",      title = "General",       icon = "Interface/Icons/inv_misc_home_01" },
    { id = "notifications", title = "Notifications", icon = "Interface/Icons/inv_misc_bell_01" },
    { id = "appearance",   title = "Appearance",    icon = "Interface/Icons/inv_misc_paintbrush_01" },
    { id = "addons",       title = "Addons",        icon = "Interface/Icons/inv_misc_gear_01" },
    { id = "integrations", title = "Integrations",  icon = "Interface/Icons/inv_misc_linkedgauntlets" },
    { id = "advanced",     title = "Advanced",      icon = "Interface/Icons/trade_engineering" },
    { id = "about",        title = "About",         icon = "Interface/Icons/inv_misc_questionmark" },
}

local SECTION_KEYS = {
    general = {
        "activationMode",
        "warnWhenWarModeOff",
    },
    notifications = {
        "echoAnnouncementsToDefaultChatFrame",
    },
    appearance = {
        "framesLocked",
        "showWarmodeIndicator",
        "showTimerbars",
    },
    addons = {
        "modulePredictionEnabled",
        "moduleBountyEnabled",
        "moduleQueueEnabled",
        "moduleEnemyPresenceEnabled",
        "enemyPresenceRadiusYards",
    },
    integrations = {
        "integrationHatedCrateTrackerEnabled",
        "integrationHatedCrateTrackerReceive",
        "integrationHatedCrateTrackerSend",
    },
    advanced = {
        "shardConfirmCount",
        "ambiguousShardConfirmCount",
        "zoneShardMismatchGraceSeconds",
        "zoneShardPollIntervalSeconds",
        "zoneShardPollDurationSeconds",
        "lifecycleDetectionGuardianSeconds",
        "timerMaxUnseenCycles",
    },
}

local function addResetKey(target, key)
    if key then
        target[#target + 1] = key
    end
end

local function collectAnnouncementConfigKeys(target)
    for _, definition in ipairs(CrateRush.ANNOUNCEMENT_MESSAGE_CATALOG or {}) do
        if definition.configurable ~= false then
            local keys = definition.keys or {}
            addResetKey(target, keys.enabled)
            addResetKey(target, keys.template)
            addResetKey(target, keys.defaultChatFrame)
            addResetKey(target, keys.warningFrame)
            addResetKey(target, keys.partyRaid)
            addResetKey(target, keys.raidWarning)
            addResetKey(target, keys.leadSeconds)
        end
    end
end

local function getSectionResetKeys(sectionID)
    local resetKeys = {}
    for _, key in ipairs(SECTION_KEYS[sectionID] or {}) do
        addResetKey(resetKeys, key)
    end

    if sectionID == "notifications" then
        collectAnnouncementConfigKeys(resetKeys)
    end

    return resetKeys
end

local function resetCurrentSection()
    if not CrateRush.config or not CrateRush.config.reset then return end

    CrateRush.config:reset(getSectionResetKeys(activeSection))
    clearPendingValues()
    dialog:refresh()

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("CrateRush configuration page reset.")
    end
end
local function getTheme()
    return CrateRush.theme and CrateRush.theme:get() or {
        accent = { 0.22, 0.58, 1, 1 },
        accentSoft = { 0.08, 0.30, 0.72, 0.72 },
        accentDark = { 0.03, 0.13, 0.32, 0.94 },
        selected = { 0.04, 0.20, 0.48, 0.94 },
        selectedBorder = { 0.10, 0.34, 0.78, 0.95 },
        title = { 0.12, 0.45, 0.95, 1 },
        version = { 0.24, 0.60, 1, 1 },
        configBackgroundTexture = nil,
        buttonTexture = nil,
    }
end

local function setColorTexture(texture, color)
    if texture and color then
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

local function setFontColor(fontString, color)
    if fontString and color then
        fontString:SetTextColor(color[1], color[2], color[3], color[4])
    end
end

local function getAddonVersionLabel()
    return CrateRush.versionLabel
        or ((CrateRush.displayName or "CrateRush") .. " " .. tostring(CrateRush.version or "unknown"))
end

local function getAddonDisplayName()
    return CrateRush.displayName or CrateRush.addonName or "CrateRush"
end

local function getDialogTitle()
    return getAddonDisplayName() .. " Configuration"
end

local function isControlDisabled(button)
    return button and button.IsEnabled and not button:IsEnabled()
end

local function setControlTexture(button, controlType, checked)
    if not button or not button.icon or not CrateRush.controlAtlas then return end
    CrateRush.controlAtlas:apply(
        button,
        controlType,
        checked,
        button.isHovered and true or false,
        isControlDisabled(button)
    )
end

local function bindControlTextureEvents(button, controlType, getChecked)
    button:SetScript("OnEnter", function(self)
        self.isHovered = true
        setControlTexture(self, controlType, getChecked(self))
    end)

    button:SetScript("OnLeave", function(self)
        self.isHovered = false
        setControlTexture(self, controlType, getChecked(self))
    end)

    button:SetScript("OnDisable", function(self)
        setControlTexture(self, controlType, getChecked(self))
    end)

    button:SetScript("OnEnable", function(self)
        setControlTexture(self, controlType, getChecked(self))
    end)
end

local function registerThemedText(fontString)
    themedTexts[#themedTexts + 1] = fontString
    return fontString
end

local function addControl(updater)
    controls[#controls + 1] = updater
    updater()
end

local function makePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.015, 0.018, 0.021, 0.92)
    panel:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.90)
    return panel
end

local function makeButton(parent, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(140, 35)

    button:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(text)
    button.label = label

    local function applyState(self, state)
        local colors = CrateRush.theme:get().buttonColors
        local c = colors[state] or colors.normal
        local b = colors.border

        self:SetBackdropColor(c[1], c[2], c[3], c[4])
        self:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
    end

    function button:applyTheme()
        applyState(self, "normal")
    end

    button:SetScript("OnEnter", function(self)
        applyState(self, "hover")
    end)

    button:SetScript("OnLeave", function(self)
        applyState(self, "normal")
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER")
    end)

    button:SetScript("OnMouseDown", function(self)
        applyState(self, "pressed")
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER", 1, -1)
    end)

    button:SetScript("OnMouseUp", function(self)
        applyState(self, "hover")
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER")
    end)

    button:applyTheme()
    return button
end

local function markUnavailableControl(control, labelText, key)
    local function update()
        if not control then return end
        if key then
            setPendingValue(key, false)
        end
        control:SetChecked(false)
        control:SetEnabled(false)
        control:SetAlpha(0.55)
        if control.label then
            control.label:SetText(labelText)
            control.label:SetTextColor(0.48, 0.50, 0.54, 1)
        end
        setControlTexture(control, "checkbox", false)
    end

    addControl(update)
end
local function markDisabledControl(control, labelText)
    local function update()
        if not control then return end
        control:SetEnabled(false)
        control:SetAlpha(0.55)
        if control.label then
            if labelText then control.label:SetText(labelText) end
            control.label:SetTextColor(0.48, 0.50, 0.54, 1)
        end
        if control.GetChecked then
            setControlTexture(control, "checkbox", control:GetChecked() and true or false)
        end
    end

    addControl(update)
end
local function makeHeader(parent, title, subtitle)
    local theme = getTheme()
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -24)
    header:SetText(title)
    setFontColor(registerThemedText(header), theme.title)

    local sub = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    sub:SetText(subtitle or "")
    sub:SetTextColor(0.82, 0.84, 0.87, 1)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18)
    line:SetPoint("RIGHT", parent, "RIGHT", -28, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.22, 0.22, 0.22, 0.9)

    return line
end

local function makeSubHeader(parent, text, anchor, yOffset)
    local theme = getTheme()
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -22)
    label:SetText(text)
    setFontColor(registerThemedText(label), theme.title)
    return label
end

local function makeCheckbox(parent, labelText, key, default, anchor, yOffset, indent)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", indent or 0, yOffset or -14)

    local icon = check:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(check)
    check.icon = icon

    bindControlTextureEvents(check, "checkbox", function(self)
        return self:GetChecked() and true or false
    end)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    label:SetText(labelText)
    label:SetTextColor(0.92, 0.92, 0.94, 1)

    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        setPendingValue(key, checked)
        setControlTexture(self, "checkbox", checked)
    end)

    addControl(function()
        local checked = getPendingBoolean(key, default)
        check:SetChecked(checked)
        setControlTexture(check, "checkbox", checked)
    end)

    check.label = label
    return check
end

local function makeRadio(parent, labelText, key, value, default, anchor, yOffset, indent)
    local radio = CreateFrame("CheckButton", nil, parent)
    radio:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    radio:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", indent or 0, yOffset or -14)

    local icon = radio:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(radio)
    radio.icon = icon

    bindControlTextureEvents(radio, "radio", function(self)
        return self:GetChecked() and true or false
    end)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", radio, "RIGHT", 8, 0)
    label:SetText(labelText)
    label:SetTextColor(0.92, 0.92, 0.94, 1)

    radio:SetScript("OnClick", function()
        setPendingValue(key, value)
        dialog:refresh()
    end)

    addControl(function()
        local checked = getPendingOrConfig(key, default) == value
        radio:SetChecked(checked)
        setControlTexture(radio, "radio", checked)
    end)

    return radio
end

local function saveNumber(editBox, key, fallback)
    local value = tonumber(editBox:GetText())
    if value then
        setPendingValue(key, value)
    else
        editBox:SetText(tostring(getPendingNumber(key, fallback)))
    end
    editBox:ClearFocus()
end

local function makeNumber(parent, labelText, key, fallback, anchor, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -12)
    row:SetPoint("RIGHT", parent, "RIGHT", -28, 0)
    row:SetHeight(28)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -122, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    label:SetTextColor(0.88, 0.90, 0.92, 1)

    local wrapper = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    wrapper:SetSize(96, 24)
    wrapper:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    wrapper:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 2,
    })
    wrapper:SetBackdropColor(0.015, 0.018, 0.022, 0.94)
    do
        local t = getTheme()
        local border = t.selectedBorder or t.selected
        wrapper:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end

    row.label = label
    row.wrapper = wrapper

    local edit = CreateFrame("EditBox", nil, wrapper)
    edit:SetPoint("LEFT", wrapper, "LEFT", 6, 0)
    edit:SetPoint("RIGHT", wrapper, "RIGHT", -6, 0)
    edit:SetHeight(16)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetJustifyH("CENTER")
    edit:SetFontObject("GameFontHighlight")
    edit:SetTextColor(0.92, 0.92, 0.94, 1)
    edit:SetScript("OnEnterPressed", function(self) saveNumber(self, key, fallback) end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dialog:refresh() end)
    edit:SetScript("OnEditFocusLost", function(self) saveNumber(self, key, fallback) end)
    edit:SetScript("OnEditFocusGained", function()
        local t = getTheme()
        local focus = t.accent or t.selectedBorder or t.selected
        wrapper:SetBackdropBorderColor(focus[1], focus[2], focus[3], focus[4] or 1)
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        saveNumber(self, key, fallback)
        local t = getTheme()
        local border = t.selectedBorder or t.selected
        wrapper:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end)
    row.edit = edit

    addControl(function()
        if not edit:HasFocus() then
            edit:SetText(tostring(getPendingNumber(key, fallback)))
        end

        local t = getTheme()
        local border = t.selectedBorder or t.selected
        wrapper:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end)

    return row
end

local function bindNumberEnabled(row, isEnabledFn)
    addControl(function()
        local enabled = isEnabledFn and isEnabledFn() == true
        if row.edit then
            row.edit:SetEnabled(enabled)
            row.edit:SetTextColor(enabled and 0.92 or 0.45, enabled and 0.92 or 0.45, enabled and 0.94 or 0.46, 1)
        end
        if row.label then
            row.label:SetTextColor(enabled and 0.88 or 0.45, enabled and 0.90 or 0.45, enabled and 0.92 or 0.46, 1)
        end
        if row.wrapper then
            row.wrapper:SetAlpha(enabled and 1 or 0.45)
        end
    end)
end
local function createScrollPage(id, title, subtitle, scrollHeight)
    local page = CreateFrame("Frame", nil, frame.contentPanel)
    page:SetPoint("TOPLEFT", frame.contentPanel, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", frame.contentPanel, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    pages[id] = page

    local scrollFrame = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(CONTENT_WIDTH - 8, scrollHeight or CONTENT_PAGE_HEIGHT)

    scrollFrame:SetScrollChild(scrollChild)

    page.scrollFrame = scrollFrame
    page.scrollChild = scrollChild

    local line = makeHeader(scrollChild, title, subtitle)
    return scrollChild, line
end

local function createPage(id, title, subtitle)
    local page = CreateFrame("Frame", nil, frame.contentPanel)
    page:SetPoint("TOPLEFT", frame.contentPanel, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", frame.contentPanel, "BOTTOMRIGHT", 0, 0)
    page:Hide()

    pages[id] = page

    local line = makeHeader(page, title, subtitle)
    return page, line
end

local function buildGeneralPage()
    local page, line = createPage("general", "General", "Global addon behaviour and activation.")
    local activation = makeSubHeader(page, "CrateRush Activation", line, -22)
    local r1 = makeRadio(page, "Enable CrateRush only when War Mode is active", "activationMode", "warMode", "warMode", activation, -18)
    local r2 = makeRadio(page, "Always enable CrateRush", "activationMode", "always", "warMode", r1, -14)
    local warn = makeCheckbox(page, "Warn me when War Mode is off", "warnWhenWarModeOff", false, r2, -8, 30)
    local r3 = makeRadio(page, "Disable CrateRush", "activationMode", "disabled", "warMode", r2, -50)
end


local function makeNotificationText(parent, text, anchor, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -10)
    label:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    label:SetTextColor(0.74, 0.76, 0.80, 1)
    return label
end

local function makeNotificationCheckbox(parent, labelText, anchor, xOffset, checked)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    check:SetPoint("LEFT", anchor, "LEFT", xOffset or 0, 0)
    check:SetChecked(checked and true or false)

    local icon = check:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(check)
    check.icon = icon

    bindControlTextureEvents(check, "checkbox", function(self)
        return self:GetChecked() and true or false
    end)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    label:SetText(labelText)
    label:SetTextColor(0.90, 0.91, 0.94, 1)
    check.label = label

    check:SetScript("OnClick", function(self)
        setControlTexture(self, "checkbox", self:GetChecked() and true or false)
    end)

    addControl(function()
        setControlTexture(check, "checkbox", check:GetChecked() and true or false)
    end)

    return check
end

local function setNotificationBlockEnabled(block, enabled)
    enabled = enabled and true or false

    for _, body in ipairs(block.bodyFrames or {}) do
        if enabled then
            body:Show()
        else
            body:Hide()
        end
    end

    block:SetHeight(enabled and (block.expandedHeight or 130) or 44)

    for _, control in ipairs(block.controls or {}) do
        if control.SetEnabled then
            control:SetEnabled(enabled)
        end
        if control.label then
            control.label:SetTextColor(enabled and 0.90 or 0.42, enabled and 0.91 or 0.42, enabled and 0.94 or 0.44, 1)
        end
    end

    if block.messageEdit then
        block.messageEdit:SetEnabled(enabled)
        block.messageEdit:SetTextColor(enabled and 0.92 or 0.45, enabled and 0.92 or 0.45, enabled and 0.94 or 0.46, 1)
    end

    if block.messageLabel then
        block.messageLabel:SetTextColor(enabled and 0.80 or 0.42, enabled and 0.82 or 0.42, enabled and 0.86 or 0.44, 1)
    end
end

local function makeNotificationEditBox(parent, anchor, defaultText)
    local wrapper = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    wrapper:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    wrapper:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    wrapper:SetHeight(26)
    wrapper:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 2,
    })
    wrapper:SetBackdropColor(0.015, 0.018, 0.022, 0.94)
    do
        local t = getTheme()
        local border = t.selectedBorder or t.selected
        wrapper:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end

    local edit = CreateFrame("EditBox", nil, wrapper)
    edit:SetPoint("LEFT", wrapper, "LEFT", 8, 0)
    edit:SetPoint("RIGHT", wrapper, "RIGHT", -8, 0)
    edit:SetHeight(16)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(false)
    edit:SetFontObject("GameFontHighlight")
    edit:SetTextColor(0.92, 0.92, 0.94, 1)
    edit:SetJustifyH("LEFT")
    edit:SetText(defaultText or "")
    edit:SetCursorPosition(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    wrapper.edit = edit
    return wrapper, edit
end

local function makeNotificationEventBlock(parent, definition, anchor, yOffset)
    local theme = getTheme()
    definition = definition or {}
    local keys = definition.keys or {}
    local outputs = definition.defaultOutputs or {}

    local block = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    block:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -18)
    block:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    block.expandedHeight = definition.timerLeadSeconds and 164 or 130
    block:SetHeight(block.expandedHeight)
    block:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    block:SetBackdropColor(0.018, 0.020, 0.024, 0.88)
    block:SetBackdropBorderColor(theme.selected[1], theme.selected[2], theme.selected[3], theme.selected[4])

    local function getBlockEnabled()
        return getPendingBoolean(keys.enabled, definition.defaultEnabled ~= false)
    end

    local function getOutputEnabled(outputKey, fallback)
        return getPendingBoolean(outputKey, fallback)
    end

    local function setChecked(control, value)
        control:SetChecked(value and true or false)
        setControlTexture(control, "checkbox", control:GetChecked() and true or false)
    end

    local enable = CreateFrame("CheckButton", nil, block)
    enable:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    enable:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -12)

    local enableIcon = enable:CreateTexture(nil, "ARTWORK")
    enableIcon:SetAllPoints(enable)
    enable.icon = enableIcon
    bindControlTextureEvents(enable, "checkbox", function(self)
        return self:GetChecked() and true or false
    end)

    local header = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("LEFT", enable, "RIGHT", 8, 0)
    header:SetText(definition.title or "Announcement")
    header:SetTextColor(1, 1, 1, 1)
    do
        local font, size = header:GetFont()
        header:SetFont(font, (size or 12) + 1, "OUTLINE")
    end

    local underline = block:CreateTexture(nil, "ARTWORK")
    underline:SetTexture(WHITE_TEXTURE)
    underline:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    underline:SetSize(150, 1)
    underline:SetColorTexture(theme.selectedBorder[1], theme.selectedBorder[2], theme.selectedBorder[3], theme.selectedBorder[4])
    block.titleUnderline = underline

    local row = CreateFrame("Frame", nil, block)
    row:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -35)
    row:SetPoint("RIGHT", block, "RIGHT", -12, 0)
    row:SetHeight(20)

    local chat = makeNotificationCheckbox(row, "Chat Frame", row, 0, true)
    local warning = makeNotificationCheckbox(row, "Notification", row, 0, true)
    local partyRaid = makeNotificationCheckbox(row, "Party/Raid", row, 0, false)
    local raidWarning = makeNotificationCheckbox(row, "Raid Warning", row, 0, false)

    local channelControls = { chat, warning, partyRaid, raidWarning }
    local function layoutChannelControls()
        local width = row:GetWidth() or 0
        if width <= 0 then return end

        local firstCheckboxX = 190
        local lastCheckboxX = width - 120

        if lastCheckboxX < firstCheckboxX then
            lastCheckboxX = firstCheckboxX
        end

        local gap = (lastCheckboxX - firstCheckboxX) / 3

        for index, control in ipairs(channelControls) do
            control:ClearAllPoints()
            control:SetPoint("LEFT", row, "LEFT", firstCheckboxX + ((index - 1) * gap), 0)
        end
    end

    row:SetScript("OnSizeChanged", layoutChannelControls)
    C_Timer.After(0, layoutChannelControls)

    local messageAnchor = row
    local leadRow
    if definition.timerLeadSeconds and keys.leadSeconds then
        leadRow = makeNumber(block, "Threshold seconds", keys.leadSeconds, definition.timerLeadSeconds, row, -8)
        messageAnchor = leadRow
    end

    local messageLabel = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageLabel:SetPoint("TOPLEFT", messageAnchor, "BOTTOMLEFT", 0, -8)
    messageLabel:SetText("Message")
    messageLabel:SetTextColor(0.80, 0.82, 0.86, 1)

    local editWrapper, edit = makeNotificationEditBox(block, messageLabel, definition.defaultTemplate or "")

    block.controls = { chat, warning, partyRaid, raidWarning }
    block.bodyFrames = { row }
    if leadRow then
        block.bodyFrames[#block.bodyFrames + 1] = leadRow
        if leadRow.label then block.bodyFrames[#block.bodyFrames + 1] = leadRow.label end
        if leadRow.wrapper then block.bodyFrames[#block.bodyFrames + 1] = leadRow.wrapper end
        if leadRow.edit then block.controls[#block.controls + 1] = leadRow.edit end
    end
    block.bodyFrames[#block.bodyFrames + 1] = messageLabel
    block.bodyFrames[#block.bodyFrames + 1] = editWrapper
    block.messageEdit = edit
    block.messageLabel = messageLabel
    block.editWrapper = editWrapper

    local function updateRaidWarningState()
        local enabled = enable:GetChecked() and true or false
        local groupEnabled = partyRaid:GetChecked() and true or false
        raidWarning:SetEnabled(enabled and groupEnabled)
        if raidWarning.label then
            if enabled and groupEnabled then
                raidWarning.label:SetTextColor(0.90, 0.91, 0.94, 1)
            else
                raidWarning.label:SetTextColor(0.42, 0.42, 0.44, 1)
            end
        end
        setControlTexture(raidWarning, "checkbox", raidWarning:GetChecked() and true or false)
    end

    local function setOutputPending(control, key)
        if key then
            setPendingValue(key, control:GetChecked() and true or false)
        end
    end

    enable:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() and true or false
        setPendingValue(keys.enabled, enabled)
        setControlTexture(self, "checkbox", enabled)
        setNotificationBlockEnabled(block, enabled)
        updateRaidWarningState()
    end)

    chat:SetScript("OnClick", function(self)
        setOutputPending(self, keys.defaultChatFrame)
        setControlTexture(self, "checkbox", self:GetChecked() and true or false)
    end)

    warning:SetScript("OnClick", function(self)
        setOutputPending(self, keys.warningFrame)
        setControlTexture(self, "checkbox", self:GetChecked() and true or false)
    end)

    partyRaid:SetScript("OnClick", function(self)
        setOutputPending(self, keys.partyRaid)
        setControlTexture(self, "checkbox", self:GetChecked() and true or false)
        if not self:GetChecked() then
            raidWarning:SetChecked(false)
            setPendingValue(keys.raidWarning, false)
        end
        updateRaidWarningState()
    end)

    raidWarning:SetScript("OnClick", function(self)
        setOutputPending(self, keys.raidWarning)
        setControlTexture(self, "checkbox", self:GetChecked() and true or false)
    end)

    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            setPendingValue(keys.template, self:GetText() or "")
        end
    end)

    addControl(function()
        local selectedBorder = getTheme().selectedBorder
        editWrapper:SetBackdropBorderColor(selectedBorder[1], selectedBorder[2], selectedBorder[3], selectedBorder[4])
        local selected = getTheme().selected
        block:SetBackdropBorderColor(selected[1], selected[2], selected[3], selected[4])
        if block.titleUnderline then
            block.titleUnderline:SetColorTexture(selectedBorder[1], selectedBorder[2], selectedBorder[3], selectedBorder[4])
        end

        setChecked(enable, getBlockEnabled())
        setChecked(chat, getOutputEnabled(keys.defaultChatFrame, outputs.defaultChatFrame ~= false))
        setChecked(warning, getOutputEnabled(keys.warningFrame, outputs.warningFrame ~= false))
        setChecked(partyRaid, getOutputEnabled(keys.partyRaid, outputs.partyRaid ~= false))
        setChecked(raidWarning, getOutputEnabled(keys.raidWarning, outputs.raidWarning == true))

        if not edit:HasFocus() then
            edit:SetText(getPendingOrConfig(keys.template, definition.defaultTemplate or ""))
            edit:SetCursorPosition(0)
        end

        setNotificationBlockEnabled(block, enable:GetChecked() and true or false)
        updateRaidWarningState()
    end)

    return block
end
local function buildNotificationsPage()
    local page, line = createScrollPage("notifications", "Notifications", "Event based message templates and delivery channels.", 1480)

    local placeholders = CrateRush.announcementMessageConfig
        and CrateRush.announcementMessageConfig.getPlaceholders
        and CrateRush.announcementMessageConfig:getPlaceholders()
        or CrateRush.ANNOUNCEMENT_PLACEHOLDERS
        or {}

    local help = makeNotificationText(
        page,
        "Use placeholders inside messages: " .. table.concat(placeholders, ", ") .. ".",
        line,
        -18
    )

    local delivery = makeSubHeader(page, "Global Delivery", help, -18)
    local chatOutput = makeCheckbox(page, "Echo announcements to default chat frame", "echoAnnouncementsToDefaultChatFrame", true, delivery, -12)

    local anchor = chatOutput
    for _, definition in ipairs(CrateRush.ANNOUNCEMENT_MESSAGE_CATALOG or {}) do
        if definition.configurable ~= false then
            anchor = makeNotificationEventBlock(page, definition, anchor, -12)
        end
    end
end
local function buildAppearancePage()
    local page, line = createPage("appearance", "Appearance", "Visual presentation of frames and alerts.")
    local global = makeSubHeader(page, "Global Appearance", line, -22)
    local a1 = makeCheckbox(page, "Lock all frames (coming later)", "framesLocked", false, global, -14)
    local a2 = makeCheckbox(page, "Display War Mode indicator (coming later)", "showWarmodeIndicator", true, a1, -8)
    local a3 = makeCheckbox(page, "Show timer bars (coming later)", "showTimerbars", true, a2, -8)
    markDisabledControl(a1)
    markDisabledControl(a2)
    markDisabledControl(a3)

    local themeLine = makeSubHeader(page, "Faction Theme", a3, -72)
    local faction = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    faction:SetPoint("TOPLEFT", themeLine, "BOTTOMLEFT", 0, -14)
    faction:SetTextColor(0.88, 0.90, 0.92, 1)

    addControl(function()
        faction:SetText("Active theme: " .. tostring((CrateRush.theme and CrateRush.theme:getFaction()) or "Unknown"))
    end)
end

local function buildAddonsPage()
    local page, line = createPage("addons", "Addons", "Optional CrateRush modules.")
    local modules = makeSubHeader(page, "Modules", line, -22)
    local m1 = makeCheckbox(page, "Crate drop prediction", "modulePredictionEnabled", true, modules, -14)
    local m2 = makeCheckbox(page, "Bounty (coming later)", "moduleBountyEnabled", false, m1, -8)
    local m3 = makeCheckbox(page, "Queue (coming later)", "moduleQueueEnabled", false, m2, -8)
    local m4 = makeCheckbox(page, "Enemy presence", "moduleEnemyPresenceEnabled", false, m3, -8)
    m4:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() and true or false
        setPendingValue("moduleEnemyPresenceEnabled", enabled)
        setControlTexture(self, "checkbox", enabled)
        dialog:refresh()
    end)
    markUnavailableControl(m2, "Bounty (coming later)", "moduleBountyEnabled")
    markUnavailableControl(m3, "Queue (coming later)", "moduleQueueEnabled")
    local radius = makeNumber(page, "Enemy presence radius yards", "enemyPresenceRadiusYards", 250, m4, -14)
    bindNumberEnabled(radius, function()
        return getPendingBoolean("moduleEnemyPresenceEnabled", false)
    end)
end

local function buildIntegrationsPage()
    local page, line = createPage("integrations", "Integrations", "External addon connections.")
    local hct = makeSubHeader(page, "Hated Crate Tracker", line, -22)
    local i1 = makeCheckbox(page, "Enable integration (coming later)", "integrationHatedCrateTrackerEnabled", false, hct, -14)
    local i2 = makeCheckbox(page, "Receive data from Hated Crate Tracker (coming later)", "integrationHatedCrateTrackerReceive", false, i1, -8)
    local i3 = makeCheckbox(page, "Send data to Hated Crate Tracker (coming later)", "integrationHatedCrateTrackerSend", false, i2, -8)
    markUnavailableControl(i1, "Enable integration (coming later)", "integrationHatedCrateTrackerEnabled")
    markUnavailableControl(i2, "Receive data from Hated Crate Tracker (coming later)", "integrationHatedCrateTrackerReceive")
    markUnavailableControl(i3, "Send data to Hated Crate Tracker (coming later)", "integrationHatedCrateTrackerSend")
end

local function buildAdvancedPage()
    local page, line = createScrollPage("advanced", "Advanced", "Expert tuning for detection and timing.", 720)
    local shard = makeSubHeader(page, "Shard Detection", line, -20)
    local n1 = makeNumber(page, "Required shard confirmations", "shardConfirmCount", CrateRush.CRATE_DEFAULTS.SHARD_CONFIRM_COUNT, shard, -16)
    local n2 = makeNumber(page, "Ambiguous shard confirmations", "ambiguousShardConfirmCount", CrateRush.CRATE_DEFAULTS.AMBIGUOUS_SHARD_CONFIRM_COUNT, n1, -14)
    local n3 = makeNumber(page, "Mismatch grace seconds", "zoneShardMismatchGraceSeconds", CrateRush.TIMING.ZONE_SHARD_MISMATCH_GRACE_SECONDS, n2, -14)
    local n4 = makeNumber(page, "Poll interval seconds", "zoneShardPollIntervalSeconds", CrateRush.TIMING.ZONE_SHARD_POLL_INTERVAL_SECONDS, n3, -14)
    local n5 = makeNumber(page, "Poll duration seconds", "zoneShardPollDurationSeconds", CrateRush.TIMING.ZONE_SHARD_POLL_DURATION_SECONDS, n4, -14)

    local lifecycle = makeSubHeader(page, "Lifecycle And Timer", n5, -24)
    local n6 = makeNumber(page, "Lifecycle guardian seconds", "lifecycleDetectionGuardianSeconds", CrateRush.TIMING.LIFECYCLE_DETECTION_GUARDIAN_SECONDS, lifecycle, -16)
    makeNumber(page, "Maximum unseen cycles", "timerMaxUnseenCycles", CrateRush.TIMING.TIMER_MAX_UNSEEN_CYCLES, n6, -14)
end

local function buildAboutPage()
    local page, line = createPage("about", "About", "CrateRush information.")
    local about = makeSubHeader(page, "CrateRush", line, -22)

    local version = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    version:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -16)
    version:SetText("Version: " .. tostring(CrateRush.version or "unknown"))
    version:SetTextColor(0.88, 0.90, 0.92, 1)

    local faction = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    faction:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -12)
    faction:SetTextColor(0.88, 0.90, 0.92, 1)

    addControl(function()
        faction:SetText("Theme: " .. tostring((CrateRush.theme and CrateRush.theme:getFaction()) or "Unknown"))
    end)

    local modules = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modules:SetPoint("TOPLEFT", faction, "BOTTOMLEFT", 0, -12)
    modules:SetText("Installed modules: base tracker, announcements, timers")
    modules:SetTextColor(0.88, 0.90, 0.92, 1)
end

local function buildPages()
    buildGeneralPage()
    buildNotificationsPage()
    buildAppearancePage()
    buildAddonsPage()
    buildIntegrationsPage()
    buildAdvancedPage()
    buildAboutPage()
end

function dialog:refresh()
    for _, updater in ipairs(controls) do
        updater()
    end

    local theme = getTheme()

    if frame and frame.title then
        frame.title:SetText(getDialogTitle())
    end

    if frame and frame.applyButton and frame.applyButton.applyTheme then
        frame.applyButton:applyTheme()
    end
    if frame and frame.resetButton and frame.resetButton.applyTheme then
        frame.resetButton:applyTheme()
    end

    for id, button in pairs(navButtons) do
        local selected = id == activeSection
        if selected then
            button:SetBackdropColor(theme.selected[1], theme.selected[2], theme.selected[3], theme.selected[4])
            button:SetBackdropBorderColor(theme.selectedBorder[1], theme.selectedBorder[2], theme.selectedBorder[3], theme.selectedBorder[4])
            setFontColor(button.label, { 1, 1, 1, 1 })
        else
            button:SetBackdropColor(0.02, 0.025, 0.03, 0.20)

            if button.isMouseOver then
                local selectedBorder = theme.selectedBorder or theme.selectedBorder
                button:SetBackdropBorderColor(selectedBorder[1], selectedBorder[2], selectedBorder[3], selectedBorder[4])
            else
                button:SetBackdropBorderColor(0, 0, 0, 0)
            end

            button.label:SetTextColor(0.90, 0.90, 0.92, 1)
        end
    end
end

function dialog:selectSection(sectionID)
    activeSection = sectionID or "general"

    for id, page in pairs(pages) do
        if id == activeSection then
            page:Show()

            if page.scrollFrame then
                page.scrollFrame:SetVerticalScroll(0)
            end
        else
            page:Hide()
        end
    end

    dialog:refresh()
end

local function createNavButton(parent, section, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(NAV_WIDTH - 20, 42)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -14 - ((index - 1) * 52))
    button:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", button, "LEFT", 14, 0)
    label:SetText(section.title)
    button.label = label

    button:SetScript("OnEnter", function(self)
        self.isMouseOver = true
        dialog:refresh()
    end)

    button:SetScript("OnLeave", function(self)
        self.isMouseOver = false
        dialog:refresh()
    end)

    button:SetScript("OnMouseDown", function(self)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", 15, -1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", 14, 0)
    end)

    button:SetScript("OnClick", function()
        dialog:selectSection(section.id)
    end)

    navButtons[section.id] = button
end

local function setConfigCloseButtonState(button, disabled)
    if not button or not button.icon then return end

    local atlas = CrateRush.theme:getConfigCloseButtonAtlas()
    local coords = disabled and CONFIG_CLOSE_TEXCOORDS.disabled or CONFIG_CLOSE_TEXCOORDS.normal

    button.icon:SetTexture(atlas)
    button.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

local function makeConfigCloseButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(BUTTON_CLOSE_SIZE, BUTTON_CLOSE_SIZE)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button.icon = icon

    setConfigCloseButtonState(button, false)

    button:SetScript("OnEnable", function(self)
        setConfigCloseButtonState(self, false)
    end)

    button:SetScript("OnDisable", function(self)
        setConfigCloseButtonState(self, true)
    end)

    return button
end

local function createDialog()
    if frame then return end

    local theme = getTheme()
    frame = CreateFrame("Frame", "CrateRushConfigDialog", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.01, 0.012, 0.015, 0.98)
    frame:SetBackdropBorderColor(0.30, 0.30, 0.32, 1)

    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetDrawLayer("ARTWORK", -8)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    header:SetHeight(HEADER_HEIGHT)
    header:SetTexture(CrateRush.theme:getConfigBackgroundTexture())
    header:SetTexCoord(0, 1, 0, 1)
    frame.header = header

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", frame, "TOP", 0, -30)
    title:SetText(getDialogTitle())
    title:SetTextColor(0.96, 0.96, 0.98, 1)
    frame.title = title

    local close = makeConfigCloseButton(frame)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -18)
    close:SetScript("OnClick", function() dialog:hide() end)
    frame.closeButton = close

    local navPanel = makePanel(frame)
    navPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_HEIGHT - 8)
    navPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, FOOTER_HEIGHT)
    navPanel:SetWidth(NAV_WIDTH)
    frame.navPanel = navPanel

    for index, section in ipairs(SECTIONS) do
        createNavButton(navPanel, section, index)
    end

    local content = makePanel(frame)
    content:SetPoint("TOPLEFT", navPanel, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, FOOTER_HEIGHT)
    frame.contentPanel = content

    buildPages()

    local footerVersion = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerVersion:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 21)
    footerVersion:SetText(getAddonVersionLabel())
    setFontColor(footerVersion, theme.version)
    frame.footerVersion = footerVersion

    local apply = makeButton(frame, "Apply")
    apply:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    frame.applyButton = apply
    apply:SetScript("OnClick", function()
        applyPendingValues()

        dialog:refresh()

        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("CrateRush configuration applied.")
        end
    end)

    local reset = makeButton(frame, "Reset")
    reset:SetPoint("RIGHT", apply, "LEFT", -12, 0)
    frame.resetButton = reset
    reset:SetScript("OnClick", resetCurrentSection)

    frame:Hide()
    dialog:selectSection(activeSection)
end

function dialog:applyTheme()
    if not frame then return end

    local theme = getTheme()

    if frame.header then
        frame.header:SetTexture(CrateRush.theme:getConfigBackgroundTexture())
    end

    if frame.footerVersion then
        setFontColor(frame.footerVersion, theme.version)
    end

    if frame.closeButton then
        setConfigCloseButtonState(frame.closeButton, not frame.closeButton:IsEnabled())
    end

    for _, fontString in ipairs(themedTexts) do
        setFontColor(fontString, theme.title)
    end

    for _, button in ipairs(themedButtons) do
        if button.applyTheme then
            button:applyTheme(false)
        end
    end

    dialog:refresh()
end

function dialog:show()
    createDialog()
    clearPendingValues()
    dialog:refresh()
    frame:Show()
end

function dialog:hide()
    clearPendingValues()
    if frame then frame:Hide() end
end

function dialog:toggle()
    createDialog()
    if frame:IsShown() then
        dialog:hide()
    else
        dialog:show()
    end
end

CrateRush.onSettingsClicked = function()
    dialog:toggle()
end



