-- CrateRush
-- ui/tooltips.lua - Shared UI tooltip helper. Display-only.

local tooltips = {}
CrateRush.tooltips = tooltips

local DEFAULT_DELAY_SECONDS = 0.125
local CURSOR_OFFSET_X = 8
local CURSOR_OFFSET_Y = 8
local pendingToken = 0

local function titleColor()
    local theme = CrateRush.theme
    local color = theme and theme.getTitleColor and theme:getTitleColor() or nil
    if type(color) == "table" then
        return color[1] or 1, color[2] or 1, color[3] or 1
    end

    local factionKey = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or nil

    if factionKey == "ALLIANCE" then
        return 0.25, 0.65, 1.00
    end
    return 1.00, 0.20, 0.18
end

local function targetText()
    if IsInRaid and IsInRaid() then
        return "raid"
    end
    if IsInGroup and IsInGroup() then
        return "party"
    end
    return nil
end

function tooltips:shiftClickText()
    local target = targetText()
    if not target then return nil end
    return "SHIFT+Left click to announce to " .. target
end

local function renderTooltip(owner, title, body, options)
    if not owner or not GameTooltip then return end
    options = type(options) == "table" and options or {}

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()

    local r, g, b = titleColor()
    GameTooltip:AddLine(tostring(title or "CrateRush"), r, g, b)

    if type(options.lines) == "table" and #options.lines > 0 then
        for _, line in ipairs(options.lines) do
            if type(line) == "table" then
                local color = line.color or { 1, 1, 1, 1 }
                local rightColor = line.rightColor or color
                if line.rightText ~= nil then
                    GameTooltip:AddDoubleLine(
                        tostring(line.text or ""),
                        tostring(line.rightText or ""),
                        color[1] or 1,
                        color[2] or 1,
                        color[3] or 1,
                        rightColor[1] or 1,
                        rightColor[2] or 1,
                        rightColor[3] or 1
                    )
                else
                    GameTooltip:AddLine(tostring(line.text or ""), color[1] or 1, color[2] or 1, color[3] or 1, true)
                end
                if line.bold then
                    local textLine = _G["GameTooltipTextLeft" .. tostring(GameTooltip:NumLines())]
                    if textLine and textLine.SetFontObject then
                        textLine:SetFontObject(GameFontNormal)
                    end
                end
            elseif line ~= "" then
                GameTooltip:AddLine(tostring(line), 1, 1, 1, true)
            end
        end
    elseif body and body ~= "" then
        local color = options.bodyColor or { 1, 1, 1, 1 }
        GameTooltip:AddLine(tostring(body), color[1] or 1, color[2] or 1, color[3] or 1, true)
    elseif options.emptyText then
        GameTooltip:AddLine(tostring(options.emptyText), 0.72, 0.76, 0.80, true)
    end

    local shiftClickText = options.showShiftClick ~= false and tooltips:shiftClickText() or nil
    if shiftClickText then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(shiftClickText, r, g, b, true)
    end

    GameTooltip:Show()

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    local tooltipWidth = GameTooltip:GetWidth() or 0
    local tooltipHeight = GameTooltip:GetHeight() or 0

    local x = ((cursorX or 0) / scale) + CURSOR_OFFSET_X
    local y = ((cursorY or 0) / scale) + CURSOR_OFFSET_Y

    if screenWidth > 0 and x + tooltipWidth > screenWidth then
        x = math.max(0, screenWidth - tooltipWidth)
    end
    if screenHeight > 0 and y + tooltipHeight > screenHeight then
        y = math.max(0, screenHeight - tooltipHeight)
    end

    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function tooltips:show(owner, title, body, options)
    if not owner or not GameTooltip then return end
    options = type(options) == "table" and options or {}
    pendingToken = pendingToken + 1
    local token = pendingToken
    local delay = tonumber(options.delaySeconds or DEFAULT_DELAY_SECONDS) or DEFAULT_DELAY_SECONDS

    if delay <= 0 or not C_Timer or not C_Timer.After then
        renderTooltip(owner, title, body, options)
        return
    end

    C_Timer.After(delay, function()
        if token ~= pendingToken then return end
        if owner.IsShown and not owner:IsShown() then return end
        if owner.IsMouseOver and not owner:IsMouseOver() then return end
        renderTooltip(owner, title, body, options)
    end)
end

function tooltips:hide()
    pendingToken = pendingToken + 1
    if GameTooltip then
        GameTooltip:Hide()
    end
end
