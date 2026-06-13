-- CrateRush
-- ui/rounded.lua - Reusable rounded UI helper. Visual only.
--
-- Two systems:
-- 1) createPill() for fixed-height horizontal badges/status chips.
--    Uses 3-slice: left cap, stretching middle, right cap.
--
-- 2) create() for larger rectangular panels.
--    Uses 9-slice families and clamps slice size to frame dimensions,
--    so corners never explode outside the frame.

local rounded = {}
CrateRush.rounded = rounded

local ADDON_MEDIA = "Interface/AddOns/CrateRush/media/"

local PILL = {
    left = ADDON_MEDIA .. "pill_left",
    middle = ADDON_MEDIA .. "pill_middle",
    right = ADDON_MEDIA .. "pill_right",
}

local FAMILY = {
    small = {
        fill = ADDON_MEDIA .. "rounded_small_fill",
        border = ADDON_MEDIA .. "rounded_small_border",
        slice = 12,
    },
    medium = {
        fill = ADDON_MEDIA .. "rounded_medium_fill",
        border = ADDON_MEDIA .. "rounded_medium_border",
        slice = 14,
    },
    large = {
        fill = ADDON_MEDIA .. "rounded_large_fill",
        border = ADDON_MEDIA .. "rounded_large_border",
        slice = 16,
    },
}

local function colorOrDefault(color, fallback)
    if type(color) == "table" then
        return color
    end
    return fallback
end

local function setTextureColor(texture, color)
    if not texture or not color then return end
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function createTexture(parent, layer, texturePath)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture(texturePath)
    return texture
end

local function familyOrDefault(size)
    return FAMILY[size] or FAMILY.medium
end

local function getSafeSlice(width, height, wantedSlice)
    local maxSlice = math.floor(math.min(tonumber(width) or 1, tonumber(height) or 1) / 2)
    local slice = tonumber(wantedSlice) or maxSlice
    if slice < 1 then return 1 end
    if maxSlice > 0 and slice > maxSlice then return maxSlice end
    return slice
end

local function makeLayer(frame, layer, texturePath)
    local pieces = {
        topLeft = createTexture(frame, layer, texturePath),
        top = createTexture(frame, layer, texturePath),
        topRight = createTexture(frame, layer, texturePath),
        left = createTexture(frame, layer, texturePath),
        center = createTexture(frame, layer, texturePath),
        right = createTexture(frame, layer, texturePath),
        bottomLeft = createTexture(frame, layer, texturePath),
        bottom = createTexture(frame, layer, texturePath),
        bottomRight = createTexture(frame, layer, texturePath),
    }

    pieces.topLeft:SetTexCoord(0.00, 0.25, 0.00, 0.25)
    pieces.top:SetTexCoord(0.25, 0.75, 0.00, 0.25)
    pieces.topRight:SetTexCoord(0.75, 1.00, 0.00, 0.25)

    pieces.left:SetTexCoord(0.00, 0.25, 0.25, 0.75)
    pieces.center:SetTexCoord(0.25, 0.75, 0.25, 0.75)
    pieces.right:SetTexCoord(0.75, 1.00, 0.25, 0.75)

    pieces.bottomLeft:SetTexCoord(0.00, 0.25, 0.75, 1.00)
    pieces.bottom:SetTexCoord(0.25, 0.75, 0.75, 1.00)
    pieces.bottomRight:SetTexCoord(0.75, 1.00, 0.75, 1.00)

    return pieces
end

local function layoutLayer(layer, frame, slice)
    if not layer then return end
    local s = math.max(1, slice or 1)

    layer.topLeft:SetSize(s, s)
    layer.topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    layer.topRight:SetSize(s, s)
    layer.topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    layer.bottomLeft:SetSize(s, s)
    layer.bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    layer.bottomRight:SetSize(s, s)
    layer.bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    layer.top:SetHeight(s)
    layer.top:SetPoint("TOPLEFT", layer.topLeft, "TOPRIGHT", 0, 0)
    layer.top:SetPoint("TOPRIGHT", layer.topRight, "TOPLEFT", 0, 0)

    layer.bottom:SetHeight(s)
    layer.bottom:SetPoint("BOTTOMLEFT", layer.bottomLeft, "BOTTOMRIGHT", 0, 0)
    layer.bottom:SetPoint("BOTTOMRIGHT", layer.bottomRight, "BOTTOMLEFT", 0, 0)

    layer.left:SetWidth(s)
    layer.left:SetPoint("TOPLEFT", layer.topLeft, "BOTTOMLEFT", 0, 0)
    layer.left:SetPoint("BOTTOMLEFT", layer.bottomLeft, "TOPLEFT", 0, 0)

    layer.right:SetWidth(s)
    layer.right:SetPoint("TOPRIGHT", layer.topRight, "BOTTOMRIGHT", 0, 0)
    layer.right:SetPoint("BOTTOMRIGHT", layer.bottomRight, "TOPRIGHT", 0, 0)

    layer.center:SetPoint("TOPLEFT", layer.topLeft, "BOTTOMRIGHT", 0, 0)
    layer.center:SetPoint("BOTTOMRIGHT", layer.bottomRight, "TOPLEFT", 0, 0)
end

local function setLayerColor(layer, color)
    if not layer then return end
    for _, piece in pairs(layer) do
        setTextureColor(piece, color)
    end
end

function rounded:setColors(frame, backgroundColor, borderColor)
    if not frame then return end

    local bg = colorOrDefault(backgroundColor, frame.roundedBackgroundColor)
    local border = colorOrDefault(borderColor, frame.roundedBorderColor)

    frame.roundedBackgroundColor = bg
    frame.roundedBorderColor = border

    setLayerColor(frame.roundedFillLayer, bg)
    setLayerColor(frame.roundedBorderLayer, border)

    if frame.pillLeft then setTextureColor(frame.pillLeft, bg) end
    if frame.pillMiddle then setTextureColor(frame.pillMiddle, bg) end
    if frame.pillRight then setTextureColor(frame.pillRight, bg) end

    if frame.pillBorderLeft then setTextureColor(frame.pillBorderLeft, border) end
    if frame.pillBorderMiddle then setTextureColor(frame.pillBorderMiddle, border) end
    if frame.pillBorderRight then setTextureColor(frame.pillBorderRight, border) end
end

function rounded:create(parent, options)
    options = options or {}

    local width = tonumber(options.width) or 100
    local height = tonumber(options.height) or 24
    local family = familyOrDefault(options.size)
    local slice = getSafeSlice(width, height, options.radius or family.slice)
    local filled = options.filled ~= false
    local borderSize = tonumber(options.borderSize) or 1

    local frame = CreateFrame("Frame", options.name, parent)
    frame:SetSize(width, height)
    frame:EnableMouse(false)

    frame.roundedBackgroundColor = colorOrDefault(options.backgroundColor, { 0, 0, 0, 0.5 })
    frame.roundedBorderColor = colorOrDefault(options.borderColor, frame.roundedBackgroundColor)

    if filled then
        frame.roundedFillLayer = makeLayer(frame, "BACKGROUND", family.fill)
        layoutLayer(frame.roundedFillLayer, frame, slice)
    end

    if borderSize > 0 then
        frame.roundedBorderLayer = makeLayer(frame, "BORDER", family.border)
        layoutLayer(frame.roundedBorderLayer, frame, slice)
    end

    function frame:setColors(backgroundColor, borderColor)
        rounded:setColors(self, backgroundColor, borderColor)
    end

    rounded:setColors(frame, frame.roundedBackgroundColor, frame.roundedBorderColor)
    return frame
end

function rounded:createPill(parent, options)
    options = options or {}

    local width = tonumber(options.width) or 120
    local height = tonumber(options.height) or 24
    local borderSize = tonumber(options.borderSize) or 1

    local cap = height
    if width < (cap * 2) then
        width = cap * 2
    end

    local frame = CreateFrame("Frame", options.name, parent)
    frame:SetSize(width, height)
    frame:EnableMouse(false)

    frame.roundedBackgroundColor = colorOrDefault(options.backgroundColor, { 0, 0, 0, 0.5 })
    frame.roundedBorderColor = colorOrDefault(options.borderColor, frame.roundedBackgroundColor)

    if borderSize > 0 then
        frame.pillBorderLeft = createTexture(frame, "BACKGROUND", PILL.left)
        frame.pillBorderLeft:SetSize(cap, height)
        frame.pillBorderLeft:SetPoint("LEFT", frame, "LEFT", 0, 0)

        frame.pillBorderRight = createTexture(frame, "BACKGROUND", PILL.right)
        frame.pillBorderRight:SetSize(cap, height)
        frame.pillBorderRight:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

        frame.pillBorderMiddle = createTexture(frame, "BACKGROUND", PILL.middle)
        frame.pillBorderMiddle:SetPoint("LEFT", frame.pillBorderLeft, "RIGHT", -1, 0)
        frame.pillBorderMiddle:SetPoint("RIGHT", frame.pillBorderRight, "LEFT", 1, 0)
        frame.pillBorderMiddle:SetHeight(height)
    end

    local inset = math.max(0, borderSize)
    local innerHeight = math.max(1, height - (inset * 2))
    local innerCap = innerHeight

    frame.pillLeft = createTexture(frame, "BORDER", PILL.left)
    frame.pillLeft:SetSize(innerCap, innerHeight)
    frame.pillLeft:SetPoint("LEFT", frame, "LEFT", inset, 0)

    frame.pillRight = createTexture(frame, "BORDER", PILL.right)
    frame.pillRight:SetSize(innerCap, innerHeight)
    frame.pillRight:SetPoint("RIGHT", frame, "RIGHT", -inset, 0)

    frame.pillMiddle = createTexture(frame, "BORDER", PILL.middle)
    frame.pillMiddle:SetPoint("LEFT", frame.pillLeft, "RIGHT", -1, 0)
    frame.pillMiddle:SetPoint("RIGHT", frame.pillRight, "LEFT", 1, 0)
    frame.pillMiddle:SetHeight(innerHeight)

    function frame:setColors(backgroundColor, borderColor)
        rounded:setColors(self, backgroundColor, borderColor)
    end

    rounded:setColors(frame, frame.roundedBackgroundColor, frame.roundedBorderColor)
    return frame
end

function rounded:createRoundedEdgesSquare(parent, options)
    return rounded:create(parent, options)
end

function rounded:createRoundedFrame(parent, options)
    return rounded:create(parent, options)
end
