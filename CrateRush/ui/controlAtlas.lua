-- CrateRush
-- ui/controlAtlas.lua - Texture atlas helper for themed checkbox and radio controls.

local controlAtlas = {}
CrateRush.controlAtlas = controlAtlas

local CONTROL_COORDS = {
    checkbox = {
        unchecked = {
            normal   = { 0.006784, 0.138399, 0.019841, 0.404762 },
            hover    = { 0.177748, 0.309362, 0.019841, 0.404762 },
            disabled = { 0.348711, 0.480326, 0.019841, 0.404762 },
        },
        checked = {
            normal   = { 0.519674, 0.651289, 0.019841, 0.404762 },
            hover    = { 0.690638, 0.822252, 0.019841, 0.404762 },
            disabled = { 0.861601, 0.993216, 0.019841, 0.404762 },
        },
    },
    radio = {
        unchecked = {
            normal   = { 0.010855, 0.132972, 0.619048, 0.976190 },
            hover    = { 0.181818, 0.303935, 0.619048, 0.976190 },
            disabled = { 0.352782, 0.474898, 0.619048, 0.976190 },
        },
        checked = {
            normal   = { 0.523745, 0.645862, 0.619048, 0.976190 },
            hover    = { 0.694708, 0.816825, 0.619048, 0.976190 },
            disabled = { 0.865672, 0.987788, 0.619048, 0.976190 },
        },
    },
}

local function getStateKey(checked)
    return checked and "checked" or "unchecked"
end

local function getInteractionKey(hovered, disabled)
    if disabled then return "disabled" end
    if hovered then return "hover" end
    return "normal"
end

function controlAtlas:getAtlasTexture()
    return CrateRush.theme:getControlsAtlas()
end

function controlAtlas:getTexCoords(controlType, checked, hovered, disabled)
    local byType = CONTROL_COORDS[controlType]
    if not byType then return nil end

    local byState = byType[getStateKey(checked)]
    if not byState then return nil end

    return byState[getInteractionKey(hovered, disabled)]
end

function controlAtlas:apply(button, controlType, checked, hovered, disabled)
    if not button or not button.icon then return end

    local coords = self:getTexCoords(controlType, checked, hovered, disabled)
    if not coords then return end

    button.icon:SetTexture(self:getAtlasTexture())
    button.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end
