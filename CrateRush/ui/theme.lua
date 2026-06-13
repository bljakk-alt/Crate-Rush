-- CrateRush
-- ui/theme.lua - Faction-aware visual theme for CrateRush UI.

local theme = {}
CrateRush.theme = theme

local ADDON_MEDIA = "Interface/AddOns/CrateRush/media/"
local FACTION = CrateRush.FACTION

local UI_COLORS = {
    neutral = {
        iconNormal    = { 1.000, 1.000, 1.000, 1.00 },
        iconHover     = { 1.000, 1.000, 1.000, 0.82 },
        textPrimary   = { 0.92, 0.94, 0.96, 1.00 },
        textSecondary = { 0.82, 0.84, 0.87, 1.00 },
        textMuted     = { 0.48, 0.53, 0.58, 1.00 },
        textTimer     = { 0.98, 0.98, 0.98, 1.00 },
    },
    header = {
        bg = { 0.035, 0.040, 0.045, 0.50 },
    },
    shardStatus = {
        matched  = { 0.220, 0.950, 0.460, 1.00 },
        checking = { 1.000, 0.920, 0.050, 1.00 },
        mismatch = { 1.000, 0.250, 0.250, 1.00 },
        unknown  = { 0.900, 0.920, 0.940, 1.00 },
    },
    timerRows = {
        normal  = { 0.16, 0.58, 0.86, 1.00 },
        warning = { 1.00, 0.92, 0.05, 1.00 },
        urgent  = { 1.00, 0.24, 0.24, 1.00 },
        bg      = { 0.04, 0.05, 0.06, 0.86 },
    },
    cockpit = {
        bg     = { 0.025, 0.030, 0.036, 0.72 },
        border = { 0.28, 0.32, 0.38, 0.55 },
        label  = { 0.55, 0.66, 0.78, 1.00 },
        value  = { 0.92, 0.94, 0.96, 1.00 },
        muted  = { 0.48, 0.53, 0.58, 1.00 },
    },
    zone = {
        default = { 0.16, 0.58, 0.86, 1.00 },
        byName = {
            ["zul'aman"] = { 1.00, 0.60, 0.00, 1.00 },
            ["harandar"] = { 0.45, 0.84, 0.23, 1.00 },
            ["eversong woods"] = { 0.13, 0.85, 1.00, 1.00 },
            ["voidstorm"] = { 1.00, 0.28, 0.55, 1.00 },
            ["slayer's rise"] = { 0.55, 0.30, 1.00, 1.00 },
        },
    },
    sync = {
        active      = { 0.22, 0.95, 0.46, 1.00 },
        unavailable = { 0.48, 0.53, 0.58, 1.00 },
        rejected    = { 1.00, 0.25, 0.25, 1.00 },
    },
}

local THEMES = {
    [FACTION.HORDE] = {
        faction = CrateRush.getFactionName(FACTION.HORDE),
        key = FACTION.HORDE,
        accent = { 0.82, 0.06, 0.04, 1.00 },
        accentSoft = { 0.48, 0.03, 0.02, 0.72 },
        accentDark = { 0.22, 0.01, 0.01, 0.94 },
        selected = { 0.15, 0.02, 0.02, 0.95 },
        selectedBorder = { 0.28, 0.02, 0.02, 1.00 },
        surfaceBorders = {
            header = { 0.38, 0.08, 0.07, 0.62 },
            row    = { 0.42, 0.08, 0.07, 0.54 },
            card   = { 0.36, 0.07, 0.06, 0.54 },
            button = { 0.42, 0.08, 0.07, 0.66 },
        },
        title = { 0.92, 0.08, 0.06, 1.00 },
        version = { 0.92, 0.08, 0.06, 1.00 },
        headerTopTexture = ADDON_MEDIA .. "horde_top",
        headerBannerTexture = ADDON_MEDIA .. "UI_Banner_Horde",
        configBackgroundTexture = ADDON_MEDIA .. "config_background_horde",
        buttonTexture = ADDON_MEDIA .. "button_horde",
        controlsAtlas = ADDON_MEDIA .. "icons/controls_horde",
        configCloseButtonAtlas = ADDON_MEDIA .. "icons/config_button_close_horde",
        buttonColors = {
            normal = { 0.15, 0.02, 0.02, 0.95 },
            hover = { 0.10, 0.01, 0.01, 1.00 },
            pressed = { 0.05, 0.00, 0.00, 1.00 },
            border = { 0.28, 0.02, 0.02, 1.00 },
        },
    },
    [FACTION.ALLIANCE] = {
        faction = CrateRush.getFactionName(FACTION.ALLIANCE),
        key = FACTION.ALLIANCE,
        accent = { 0.10, 0.45, 0.95, 1 },
        accentSoft = { 0.05, 0.22, 0.58, 0.72 },
        accentDark = { 0.02, 0.08, 0.22, 0.94 },
        selected = { 0.02, 0.08, 0.15, 0.95 },
        selectedBorder = { 0.08, 0.22, 0.45, 1.00 },
        surfaceBorders = {
            header = { 0.10, 0.30, 0.55, 0.64 },
            row    = { 0.10, 0.28, 0.52, 0.56 },
            card   = { 0.10, 0.26, 0.48, 0.56 },
            button = { 0.10, 0.28, 0.52, 0.68 },
        },
        title = { 0.12, 0.45, 0.95, 1.00 },
        version = { 0.12, 0.45, 0.95, 1.00 },
        headerTopTexture = ADDON_MEDIA .. "alliance_top",
        headerBannerTexture = ADDON_MEDIA .. "UI_Banner_Alliance",
        configBackgroundTexture = ADDON_MEDIA .. "config_background_alliance",
        buttonTexture = ADDON_MEDIA .. "button_alliance",
        controlsAtlas = ADDON_MEDIA .. "icons/controls_alliance",
        configCloseButtonAtlas = ADDON_MEDIA .. "icons/config_button_close_alliance",
        buttonColors = {
            normal  = { 0.02, 0.08, 0.15, 0.95 },
            hover   = { 0.03, 0.10, 0.18, 1.00 },
            pressed = { 0.01, 0.05, 0.10, 1.00 },
            border  = { 0.08, 0.22, 0.45, 1.00 },
        },
    },
}

local activeTheme

local function getResolvedFactionKey()
    if CrateRush.playerContext and CrateRush.playerContext.getFactionKey then
        return CrateRush.playerContext:getFactionKey()
    end
    return nil
end

function theme:init()
    activeTheme = THEMES[getResolvedFactionKey()]
    return activeTheme
end

function theme:get()
    activeTheme = THEMES[getResolvedFactionKey()]
    return activeTheme
end

function theme:getFaction()
    local current = theme:get()
    return current and current.faction or nil
end

function theme:getKey()
    local current = theme:get()
    return current and current.key or nil
end

function theme:getColor(name)
    local current = theme:get()
    return current and current[name] or nil
end

function theme:getFactionColor(factionKey)
    factionKey = CrateRush.resolveFactionKey(factionKey)
    local factionTheme = THEMES[factionKey]
    return factionTheme and (factionTheme.title or factionTheme.accent) or nil
end

function theme:getUIColors()
    return UI_COLORS
end

function theme:getUIColor(groupName, colorName)
    local group = UI_COLORS[groupName]
    if not group then return nil end
    return group[colorName]
end

function theme:getSurfaceBorder(name)
    local current = theme:get()
    local borders = current and current.surfaceBorders or nil
    return borders and borders[name] or nil
end

function theme:getZoneColor(zoneName)
    local zoneColors = UI_COLORS.zone or {}
    local byName = zoneColors.byName or {}
    local key = zoneName and string.lower(tostring(zoneName)) or nil
    return (key and byName[key]) or zoneColors.default
end

function theme:getHeaderBannerTexture()
    local current = theme:get()
    return current and current.headerBannerTexture or nil
end

function theme:getHeaderTopTexture()
    local current = theme:get()
    return current and current.headerTopTexture or nil
end

function theme:getConfigBackgroundTexture()
    local current = theme:get()
    return current and current.configBackgroundTexture or nil
end

function theme:getButtonTexture()
    local current = theme:get()
    return current and current.buttonTexture or nil
end

function theme:getControlsAtlas()
    local current = theme:get()
    return current and current.controlsAtlas or nil
end

function theme:getConfigCloseButtonAtlas()
    local current = theme:get()
    return current and current.configCloseButtonAtlas or nil
end


