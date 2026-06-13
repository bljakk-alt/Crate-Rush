-- CrateRush
-- ui/surface.lua - Generic visual surface factory for UI panels, rows, pills, and buttons.

local surface = {}
CrateRush.surface = surface

local WHITE_TEXTURE = "Interface/Buttons/WHITE8X8"

local function colorOr(color, fallback)
    if type(color) == "table" then return color end
    return fallback
end

local function withAlpha(color, alpha)
    if type(color) ~= "table" then return nil end
    return { color[1] or 1, color[2] or 1, color[3] or 1, alpha }
end

local function getColors()
    return CrateRush.theme and CrateRush.theme.getUIColors and CrateRush.theme:getUIColors() or {}
end

local function surfaceBorder(name, fallback)
    if CrateRush.theme and CrateRush.theme.getSurfaceBorder then
        return CrateRush.theme:getSurfaceBorder(name) or fallback
    end
    return fallback
end

local function styleFor(variant, options)
    local colors = getColors()
    local cockpit = colors.cockpit or {}
    local header = colors.header or {}
    local timerRows = colors.timerRows or {}
    local shardStatus = colors.shardStatus or {}

    local styles = {
        header = {
            family = "large",
            radius = 8,
            bg = withAlpha(header.bg or { 0.02, 0.03, 0.04, 1 }, 0.68),
            border = surfaceBorder("header", { 0.14, 0.16, 0.18, 0.58 }),
        },
        row = {
            family = "medium",
            radius = 8,
            bg = { 0.035, 0.035, 0.070, 0.88 },
            border = surfaceBorder("row", { 0.12, 0.14, 0.16, 0.52 }),
        },
        rowSelected = {
            family = "medium",
            radius = 8,
            bg = { 0.030, 0.040, 0.070, 0.92 },
            border = { 0.08, 0.86, 1.00, 1.00 },
        },
        card = {
            family = "medium",
            radius = 8,
            bg = cockpit.bg or { 0.025, 0.030, 0.036, 0.72 },
            border = surfaceBorder("card", cockpit.border or { 0.18, 0.20, 0.22, 0.50 }),
        },
        badge = {
            pill = true,
            bg = { 0.02, 0.10, 0.04, 0.82 },
            border = shardStatus.matched or { 0.22, 0.95, 0.46, 1 },
        },
        button = {
            family = "small",
            radius = 7,
            bg = { 0.040, 0.055, 0.075, 0.86 },
            border = surfaceBorder("button", { 0.25, 0.32, 0.40, 0.75 }),
        },
        progressTrack = {
            family = "small",
            radius = 5,
            bg = { 0.10, 0.15, 0.18, 0.92 },
            border = { 0.10, 0.15, 0.18, 0.00 },
        },
        progressFill = {
            family = "small",
            radius = 5,
            bg = timerRows.normal or { 0.16, 0.58, 0.86, 1 },
            border = { 0.00, 0.00, 0.00, 0.00 },
        },
    }

    local style = styles[variant] or styles.card
    if options then
        if options.backgroundColor then style.bg = options.backgroundColor end
        if options.borderColor then style.border = options.borderColor end
        if options.radius then style.radius = options.radius end
        if options.family then style.family = options.family end
        if options.pill ~= nil then style.pill = options.pill end
    end
    return style
end

local function applyBackdrop(frame, backgroundColor, borderColor)
    if not frame then return end
    frame:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    backgroundColor = colorOr(backgroundColor, { 0, 0, 0, 0.45 })
    borderColor = colorOr(borderColor, { 0, 0, 0, 0 })
    frame:SetBackdropColor(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4])
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
end

function surface:create(parent, variant, options)
    options = options or {}
    local width = tonumber(options.width) or 100
    local height = tonumber(options.height) or 24
    local style = styleFor(variant, options)
    local rounded = CrateRush.rounded

    local frame
    if rounded and style.pill and rounded.createPill then
        frame = rounded:createPill(parent, {
            name = options.name,
            width = width,
            height = height,
            radius = style.radius,
            borderSize = options.borderSize or 1,
            backgroundColor = style.bg,
            borderColor = style.border,
        })
    elseif rounded and rounded.create then
        frame = rounded:create(parent, {
            name = options.name,
            width = width,
            height = height,
            size = style.family,
            radius = style.radius,
            borderSize = options.borderSize or 1,
            backgroundColor = style.bg,
            borderColor = style.border,
        })
    else
        frame = CreateFrame("Frame", options.name, parent, "BackdropTemplate")
        frame:SetSize(width, height)
        applyBackdrop(frame, style.bg, style.border)
    end

    frame:EnableMouse(options.mouseEnabled == true)
    frame.surfaceVariant = variant
    return frame
end

function surface:setColors(frame, backgroundColor, borderColor)
    if not frame then return end
    if frame.setColors then
        frame:setColors(backgroundColor, borderColor)
    elseif CrateRush.rounded and CrateRush.rounded.setColors then
        CrateRush.rounded:setColors(frame, backgroundColor, borderColor)
    else
        applyBackdrop(frame, backgroundColor, borderColor)
    end
end

function surface:withAlpha(color, alpha)
    return withAlpha(color, alpha)
end
