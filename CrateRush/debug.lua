-- CrateRush
-- debug.lua — Standalone debug output window. Removable without breaking anything.
-- Toggle via /cr debug. One-way sink — no other module depends on this.

local DEBUG_NAME        = "CrateRushDebug"
local MIN_FONT_SIZE     = 8
local MAX_FONT_SIZE     = 20
local DEFAULT_FONT_SIZE = 11
local MAX_LINES         = 4000
local MAX_SAVED_LINES   = 100000
local WINDOW_WIDTH      = 700
local WINDOW_HEIGHT     = 400
local BOTTOM_FOLLOW_THRESHOLD = 2

local COLOR_DEFAULT  = "|cffeeeeee"
local COLOR_ANNOUNCE = "|cffff70c8"
local COLOR_SHARDMAP = "|cff00ccff"
local COLOR_DUMP     = "|cff8fa8bb"
local COLOR_STATUS_YELLOW = "|cffffcc33"
local COLOR_STATUS_RED    = "|cffff5555"
local COLOR_STATUS_GREEN  = "|cff3adf77"
local COLOR_CONFIRM       = "|cff6fbfac"
local COLOR_RESET    = "|r"

local debug = {}
CrateRush.debug = debug

local frame
local scrollFrame
local editBox
local lines = {}
local currentFontSize = DEFAULT_FONT_SIZE
local fontSizeLabel
local filteredIDs = {}
local savedState  = {}
local onSaveState = nil
local timestampOffset = nil

local function getPreciseTime()
    if GetTimePreciseSec then
        return GetTimePreciseSec()
    end
    if debugprofilestop then
        return debugprofilestop() / 1000
    end
    if CrateRush.clock and CrateRush.clock.serverTime then
        return CrateRush.clock:serverTime()
    end
    return 0
end

local function getTimestamp()
    local preciseNow = getPreciseTime()

    if not timestampOffset then
        local serverNow = CrateRush.clock and CrateRush.clock.serverTime and CrateRush.clock:serverTime() or 0
        timestampOffset = serverNow - preciseNow
    end

    local wallNow = timestampOffset + preciseNow
    local seconds = math.floor(wallNow)
    local milliseconds = math.floor((wallNow - seconds) * 1000)
    milliseconds = math.max(0, math.min(milliseconds, 999))

    if date then
        return date("%H:%M:%S", seconds) .. string.format(".%03d", milliseconds)
    end

    return string.format("%.3f", preciseNow)
end

local function safeText(value)
    local ok, text = pcall(tostring, value)
    if ok then return text end
    return "<restricted>"
end

local function safeFind(text, pattern, init, plain)
    local ok, result = pcall(string.find, text, pattern, init, plain)
    return ok and result ~= nil
end

local function applyColor(msg)
    msg = safeText(msg or "")

    if safeFind(msg, "%-> yellow") then
        return COLOR_STATUS_YELLOW .. msg .. COLOR_RESET
    elseif safeFind(msg, "%-> red") then
        return COLOR_STATUS_RED .. msg .. COLOR_RESET
    elseif safeFind(msg, "%-> green") then
        return COLOR_STATUS_GREEN .. msg .. COLOR_RESET
    elseif safeFind(msg, "^ZONECHECK | CONFIRM_LOCK")
        or safeFind(msg, "^ZONECHECK | APPLY_CONFIRMED")
    then
        return COLOR_CONFIRM .. msg .. COLOR_RESET
    elseif safeFind(msg, "^ANNOUNCE") then
        return COLOR_ANNOUNCE .. msg .. COLOR_RESET
    elseif safeFind(msg, "^SHARDMAP") then
        return COLOR_SHARDMAP .. msg .. COLOR_RESET
    elseif safeFind(msg, "^  DUMP") then
        return COLOR_DUMP .. msg .. COLOR_RESET
    elseif safeFind(msg, "^|c") then
        -- already colored
        return msg
    end
    return COLOR_DEFAULT .. msg .. COLOR_RESET
end

local function buildText()
    return table.concat(lines, "\n")
end

local function getScrollBar()
    if not scrollFrame then return nil end
    return scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
end

local function getScrollValue()
    local scrollBar = getScrollBar()
    if scrollBar and scrollBar.GetValue then
        return scrollBar:GetValue() or 0
    end
    if scrollFrame and scrollFrame.GetVerticalScroll then
        return scrollFrame:GetVerticalScroll() or 0
    end
    return 0
end

local function getScrollMax()
    local scrollBar = getScrollBar()
    if scrollBar and scrollBar.GetMinMaxValues then
        local _, maxValue = scrollBar:GetMinMaxValues()
        return maxValue or 0
    end
    if scrollFrame and scrollFrame.GetVerticalScrollRange then
        return scrollFrame:GetVerticalScrollRange() or 0
    end
    return 0
end

local function updateScrollRange()
    if scrollFrame and scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end

local function setScrollValue(value)
    value = tonumber(value) or 0

    local scrollBar = getScrollBar()
    if scrollBar and scrollBar.SetValue then
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        value = math.max(minValue or 0, math.min(value, maxValue or value))
        scrollBar:SetValue(value)
        return
    end

    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollFrame:SetVerticalScroll(math.max(0, value))
    end
end

local function isLastLineVisible()
    if not scrollFrame then return true end

    local viewportHeight = scrollFrame:GetHeight() or 0
    local viewportBottom = getScrollValue() + viewportHeight
    local contentHeight = math.max((editBox and editBox:GetHeight() or 0), getScrollMax() + viewportHeight)
    local lastLineThreshold = (currentFontSize or DEFAULT_FONT_SIZE) + 8

    return contentHeight <= 0 or (contentHeight - viewportBottom) <= lastLineThreshold
end

local function isScrolledToBottom()
    local maxValue = getScrollMax()
    return maxValue <= 0 or (maxValue - getScrollValue()) <= BOTTOM_FOLLOW_THRESHOLD
end

local function applyScrollPosition(followBottom, previousScroll)
    updateScrollRange()
    setScrollValue(followBottom and getScrollMax() or previousScroll)

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not scrollFrame then return end
            updateScrollRange()
            setScrollValue(followBottom and getScrollMax() or previousScroll)
        end)
        C_Timer.After(0.05, function()
            if not scrollFrame then return end
            updateScrollRange()
            setScrollValue(followBottom and getScrollMax() or previousScroll)
        end)
    end
end

local function refreshDisplay(forceBottom)
    if not editBox then return end
    local previousScroll = getScrollValue()
    local followBottom = forceBottom or isScrolledToBottom() or isLastLineVisible()

    editBox:SetText(buildText())
    applyScrollPosition(followBottom, previousScroll)
end

local function applyFilterIDs(text)
    filteredIDs = {}
    if not text then return end
    for id in text:gmatch("%d+") do
        filteredIDs[tonumber(id)] = true
    end
end

local function saveState()
    if not onSaveState or not frame then return end
    local point, _, _, x, y = frame:GetPoint()
    onSaveState({
        fontSize = currentFontSize,
        x        = x,
        y        = y,
        width    = frame:GetWidth(),
        height   = frame:GetHeight(),
    })
end

local function createWindow()
    if frame then return end

    -- Build saved text for filter input display only
    local savedText = {}
    for id, _ in pairs(filteredIDs) do
        savedText[#savedText + 1] = tostring(id)
    end

    -- Main frame
    frame = CreateFrame("Frame", DEBUG_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(savedState.width or WINDOW_WIDTH, savedState.height or WINDOW_HEIGHT)
    if savedState.x and savedState.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedState.x, savedState.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(300, 200)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveState()
    end)
    frame:SetFrameStrata("DIALOG")

    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    title:SetText("|cff00ff00CrateRush|r Debug")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Toolbar row 1
    local toolbarY = -24

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, toolbarY)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        lines = {}
        refreshDisplay()
    end)

    local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllBtn:SetSize(72, 22)
    selectAllBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        if editBox then
            editBox:SetFocus()
            editBox:HighlightText()
        end
    end)

    local fontMinusBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    fontMinusBtn:SetSize(26, 22)
    fontMinusBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 8, 0)
    fontMinusBtn:SetText("-")
    fontMinusBtn:SetScript("OnClick", function()
        currentFontSize = math.max(MIN_FONT_SIZE, currentFontSize - 1)
        if editBox then editBox:SetFont("Fonts\\FRIZQT__.TTF", currentFontSize, "") end
        if fontSizeLabel then fontSizeLabel:SetText(currentFontSize .. "pt") end
        saveState()
    end)

    fontSizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeLabel:SetPoint("LEFT", fontMinusBtn, "RIGHT", 4, 0)
    fontSizeLabel:SetText(currentFontSize .. "pt")
    fontSizeLabel:SetWidth(28)

    local fontPlusBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    fontPlusBtn:SetSize(26, 22)
    fontPlusBtn:SetPoint("LEFT", fontSizeLabel, "RIGHT", 4, 0)
    fontPlusBtn:SetText("+")
    fontPlusBtn:SetScript("OnClick", function()
        currentFontSize = math.min(MAX_FONT_SIZE, currentFontSize + 1)
        if editBox then editBox:SetFont("Fonts\\FRIZQT__.TTF", currentFontSize, "") end
        if fontSizeLabel then fontSizeLabel:SetText(currentFontSize .. "pt") end
        saveState()
    end)

    -- Resize grip
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp",   function()
        frame:StopMovingOrSizing()
        saveState()
    end)

    -- Toolbar row 2: filter
    local filterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, toolbarY - 28)
    filterLabel:SetText("Filter IDs:")
    filterLabel:SetTextColor(0.7, 0.7, 0.7)

    local filterInput = CreateFrame("EditBox", DEBUG_NAME .. "Filter", frame, "InputBoxTemplate")
    filterInput:SetSize(200, 20)
    filterInput:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
    filterInput:SetAutoFocus(false)
    filterInput:SetText(table.concat(savedText, " "))
    filterInput:SetScript("OnEscapePressed", function() filterInput:ClearFocus() end)

    local filterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    filterBtn:SetSize(40, 22)
    filterBtn:SetPoint("LEFT", filterInput, "RIGHT", 4, 0)
    filterBtn:SetText("OK")
    filterBtn:SetScript("OnClick", function()
        local text = filterInput:GetText()
        applyFilterIDs(text)
        if onSaveState then
            saveState()
        end
        -- Notify main to persist filter IDs via callback
        if CrateRush.onDebugFilterChanged then
            CrateRush.onDebugFilterChanged(filteredIDs)
        end
        filterInput:ClearFocus()
    end)

    -- Scroll frame
    scrollFrame = CreateFrame("ScrollFrame", DEBUG_NAME .. "Scroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     8,  toolbarY - 52)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    editBox = CreateFrame("EditBox", DEBUG_NAME .. "EditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetAutoFocus(false)
    editBox:SetFont("Fonts\\FRIZQT__.TTF", currentFontSize, "")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)

    scrollFrame:SetScrollChild(editBox)

    frame:SetScript("OnSizeChanged", function()
        if editBox then editBox:SetWidth(scrollFrame:GetWidth()) end
    end)

    frame:Hide()
end


function debug:applyState(state)
    if not state then return end
    savedState = state
    if state.fontSize then currentFontSize = state.fontSize end
end

function debug:setSaveCallback(fn)
    onSaveState = fn
end


function debug:applyFilters(idTable)
    if not idTable then return end
    filteredIDs = {}
    for id, _ in pairs(idTable) do
        filteredIDs[tonumber(id)] = true
    end
end

function debug:log(msg)
    return

    if msg == nil then return end
    msg = safeText(msg)

    -- Filter by vignette ID
    for id, _ in pairs(filteredIDs) do
        if safeFind(msg, tostring(id), 1, true) then return end
    end

    local timestamp = getTimestamp()
    local colored = applyColor(msg)
    local line = "[" .. timestamp .. "] " .. colored

    -- Persist the same debug line that appears in the debug window.
    -- Keep the window behaviour unchanged, this only adds SavedVariables history.
    CrateRushDebugDB = CrateRushDebugDB or {}
    table.insert(CrateRushDebugDB, {
        epoch = CrateRush.clock and CrateRush.clock:serverTime() or nil,
        uptime = getPreciseTime(),
        timestamp = timestamp,
        line = msg,
        displayLine = line,
    })
    if #CrateRushDebugDB > MAX_SAVED_LINES then
        table.remove(CrateRushDebugDB, 1)
    end

    table.insert(lines, line)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end

    if frame and frame:IsShown() then
        refreshDisplay()
    end
end

function debug:toggle()
    createWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        refreshDisplay(true)
    end
end

function debug:clear()
    lines = {}
    if frame and frame:IsShown() then
        refreshDisplay()
    end
end
