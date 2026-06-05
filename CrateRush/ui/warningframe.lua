-- CrateRush
-- ui/warningframe.lua — Floating alert overlay shown when not in a group or raid.

local warningframe = {}
CrateRush.warningframe = warningframe

local frame
local text
local currentToken = 0

local function isEnabled()
    if CrateRush.config and CrateRush.config.getBoolean then
        return CrateRush.config:getBoolean("showWarningFrame", true)
    end
    return true
end

function warningframe:init()
    if frame then return frame end

    frame = CreateFrame("Frame", "CrateRushWarningFrame", UIParent)
    frame:SetSize(720, 72)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- set transaprent background explicitly
    bg:SetColorTexture(0, 0, 0, 0)

    text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetWidth(680)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    if text.SetWordWrap then text:SetWordWrap(true) end
    text:SetTextColor(1, 0.86, 0.28, 1)

    frame:Hide()
    return frame
end

function warningframe:show(msg)
    if not isEnabled() then return end
    local f = warningframe:init()
    if not f or not text then return end

    currentToken = currentToken + 1
    local token = currentToken

    text:SetText(tostring(msg or ""))
    f:Show()

    if C_Timer and C_Timer.After then
        C_Timer.After(8, function()
            if token == currentToken then
                warningframe:hide()
            end
        end)
    end
end

function warningframe:hide()
    if frame then frame:Hide() end
end
