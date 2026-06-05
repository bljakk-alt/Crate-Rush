-- CrateRush
-- logic/crateHandler/prediction.lua — Route matching and drop location calculation.
-- Matches a mid-flight plane against known static routes to predict drop location.

local prediction = {}
CrateRush.prediction = prediction

function prediction:matchRoute(zoneID, x, y, angle)
    -- Match current plane position and angle against static routes in EXPANSIONS.
    -- Returns the best matching route and predicted drop coordinates, or nil if no match.
end

function prediction:getPredictedDrop(route)
    -- Returns predicted x, y drop coordinates for a given route.
end
