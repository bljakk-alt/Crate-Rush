# CrateRush Prediction Design

## Purpose

CrateRush prediction is split into two capabilities:

1. **Location prediction**, where the addon predicts where the crate will drop.
2. **Dropping time prediction**, where the addon predicts when the crate will drop and when it will land.

Prediction is active only during the **plane flying phase**.

Prediction must not start before the plane is flying. Prediction must stop when the crate starts dropping, lands, or is claimed. After that, the addon switches from prediction to observed lifecycle tracking until the next lifecycle.

Plane flying itself is confirmed before prediction starts. The flying confirmation gate uses route metadata, but it is not allowed to publish predictions or change timers. It only decides whether a noisy `PLANE_FLYING` vignette becomes accepted lifecycle state `DETECTED`.

The target is a practical gameplay estimate, not flight planning level precision. If the addon predicts a drop in about 67 seconds and the real drop happens at 63 or 73 seconds, that is acceptable.

---

# 1. Business Design

## 1.1 Location Prediction

### Player problem

Players often enter a zone after the monster say, after the plane anchor appeared, or while the plane is already flying. Static drop points are not enough because the player still does not know which drop point is active.

Location prediction answers:

> Where will this crate drop?

### Player value

CrateRush helps the player or group move towards the correct drop area before the crate becomes visible as dropping or landed.

This is the main product difference against a static waypoint tracker. Static waypoints show possible locations. CrateRush predicts the currently active location.

### Prediction window

Location prediction starts only when the plane is flying:

```text
PLANE_FLYING
```

Route/location selection stops when one of these appears:

```text
CRATE_DROPPING
CRATE_LANDED
CRATE_CLAIMED_BY_ALLIANCE
CRATE_CLAIMED_BY_HORDE
```

After the crate has dropped, route selection is no longer needed because the real drop point is known or nearly known. The selected prediction may still be kept as UI context until the lifecycle closes.

### Prediction behaviour

The addon should normally predict only once during the flying phase.

It may correct the prediction only if the current prediction is materially wrong, for example:

```text
the route candidate changes with higher confidence
the observed plane cells contradict the selected route
the predicted drop location is clearly off
the ETA changes by more than the correction threshold
```

Small differences should not trigger repeated updates. Prediction must be stable.

### Confidence levels

```text
Low:
Plane seen, but route not identified.

Medium:
Candidate route exists, but more than one route still fits.

High:
Route cell lookup identifies one dominant route.

Certain:
Drop or landed vignette appeared, prediction stops.
```

### Expected output

Example user facing output:

```text
Predicted drop: 45.3 / 63.1
Confidence: High
Drop in ~1m10s
```

The addon should avoid fake precision. The player needs a useful estimate, not decimal perfect timing.

---

## 1.2 Dropping Time Prediction

### Player problem

Players need to know whether they can still reach the crate before it drops or lands.

Dropping time prediction answers:

> When will the crate drop?

Secondary question:

> When will the crate land?

### Player value

The player can decide whether to chase, redirect, wait, or call group members.

### Prediction window

Dropping time prediction uses the same lifecycle guard as location prediction.

It is active only during:

```text
PLANE_FLYING
```

It is inactive:

```text
before plane flying
after crate landed
after crate claimed
```

After `CRATE_DROPPING`, the addon no longer predicts drop time. The drop has already happened, so Drop displays as passed and the selected prediction is reused only to track approximate land timing. After `CRATE_LANDED`, both Drop and Land displays are passed, but the predicted/known location may remain visible until the lifecycle closes.

### Accuracy expectation

Acceptable display:

```text
Drop in ~1m10s
Drop in ~45s
Drop soon
```

Not acceptable as user facing precision:

```text
Drop in 67.342s
```

### Time concepts

CrateRush must keep these concepts separate:

```text
Cycle time:
Time between crate lifecycle starts in one zone.

Plane to drop:
Time from plane detection or first moving plane point to the drop event.

Drop to landed:
Time from dropping to landed.

Claimed visible:
Time after faction claim until the claimed crate disappears for that player.
```

Known observed zone cycle timers:

```text
Harandar        ~1099s
Eversong Woods  ~1099s
Zul'Aman        ~1098s
Voidstorm       ~1097s
Slayer's Rise   ~1091s
```

These are zone specific. `1099s` can be a fallback, but it must not be a universal constant.

### Claimed timer

Claimed visibility is strongly supported around:

```text
~68 seconds
```

However, claimed visibility may stop early after the player loots. Short claimed observations must not automatically be treated as global crate expiry.

---

# 2. Technical Design

## 2.1 Location Prediction

### Core principle

Heavy processing happens outside WoW. Runtime logic inside WoW must stay cheap.

The addon should not calculate expensive route geometry during gameplay. It should use precomputed route intelligence.

### Runtime flow

During `VIGNETTES_UPDATED`:

```text
1. Confirm current zone/map.
2. Confirm plane/flying as accepted lifecycle state `DETECTED`.
3. Read current plane x/y.
4. Convert x/y into 100 x 100 map degree space.
5. Calculate rough 4 x 4 grid cell.
6. Calculate fine 1 x 1 grid cell.
7. Look up candidate routes.
8. If one route matches, predict drop location.
9. If multiple routes match, wait for next plane point and resolve with cell movement or angle.
10. Lock prediction for this lifecycle.
11. Stop prediction at dropping, landed, or claimed.
```

### Plane confirmation route metadata

The route-data query layer owns cheap map-coordinate facts shared by lifecycle and prediction:

```text
zone anchor point
known drop clusters
route cell index
one map-degree position tolerance
```

The lifecycle service uses these facts only to decide whether a plane vignette is real pre-drop flying:

```text
same GUID moved beyond tolerance -> accept flying
same GUID held at zone anchor for 2 ticks -> accept flying
same GUID held on high-confidence known route and not near drop -> accept flying
same GUID held near known drop -> do not accept flying
same GUID held at unknown/ambiguous point -> do not accept flying
```

### Grid model

WoW map coordinates are converted:

```text
X = x * 100
Y = y * 100
```

Rough grid:

```text
roughX = floor(X / 4)
roughY = floor(Y / 4)
roughKey = roughX .. ":" .. roughY
```

Fine grid:

```text
fineX = floor(X)
fineY = floor(Y)
fineKey = fineX .. ":" .. fineY
```

Runtime Lua:

```lua
local gx = x * 100
local gy = y * 100

local roughX = math.floor(gx / 4)
local roughY = math.floor(gy / 4)

local fineX = math.floor(gx)
local fineY = math.floor(gy)

local roughKey = roughX .. ":" .. roughY
local fineKey = fineX .. ":" .. fineY
```

### Route cell index

The addon should use a precomputed lookup table:

```lua
CrateRushRouteCellIndex = {
    [2444] = {
        ["11:15"] = {
            ["45:63"] = {
                {
                    routeID = "SR_203_455_630",
                    dropX = 0.4553,
                    dropY = 0.6310,
                    secondsToDrop = 62,
                    angle = 203.31,
                    samples = 4,
                    confidence = 0.82,
                },
            },
        },
    },
}
```

Runtime asks:

> Which known route usually passes through this rough and fine cell?

This avoids live route geometry.

### Route definitions

```lua
CrateRushRoutes = {
    ["SR_203_455_630"] = {
        zoneID = 2444,

        startX = 0.56779,
        startY = 0.35915,

        endX = 0.45193,
        endY = 0.62803,

        angle = 203.31,

        dropClusterID = "SR_DROP_455_630",
        dropX = 0.4553,
        dropY = 0.6310,

        avgMovingToDropSeconds = 86.8,
        avgDropToLandedSeconds = 86.9,

        samples = 4,
        confidence = 0.82,
    },
}
```

### Drop clusters

A drop cluster is a practical drop location.

```lua
CrateRushDropClusters = {
    [2444] = {
        ["SR_DROP_455_630"] = {
            x = 0.4553,
            y = 0.6310,
            samples = 4,
            routes = {
                "SR_203_455_630",
            },
        },
    },
}
```

A drop cluster may later have multiple route variants if data proves that different routes lead to the same practical drop location.

### Candidate resolution

If the route cell lookup returns one route, predict immediately.

If several routes match, do not predict from that single 1 x 1 cell.
Store the route IDs as pending evidence for this `zoneID + shardID`, then resolve with cheap evidence from later plane points:

```text
next fine cell
cell movement direction
movement angle
angle bucket
```

The addon should not check every route or run line distance calculations live.

Implemented runtime rule:

```text
1. Plane point received.
2. Convert x/y to rough and fine cells.
3. Look up candidate routes.
4. If one route candidate exists, publish prediction.
5. If multiple route candidates exist, keep them pending and publish nothing.
6. On the next plane point, calculate movement angle from previous point to current point.
7. On a different fine cell, intersect previous route candidates with current route candidates.
8. If intersection has one route, publish prediction.
9. If multiple routes remain, filter by movement angle against stored route angles.
10. If angle filtering leaves one route, publish prediction.
11. If several routes remain, apply the strong angle tie-break rule.
12. If strong angle tie-break does not pass, keep waiting.
13. If intersection is empty, reset pending candidates from the current cell.
14. If the same ambiguous fine cell repeats, use movement angle if enough plane movement exists; otherwise keep waiting.
```

Confidence and sample count may describe candidates, but must not select a prediction when multiple routes still match. The only approved exception is the strong angle tie-break rule below.

### Angle Based Candidate Resolution

When more than one route candidate remains after rough/fine cell lookup or fine cell sequence matching, the addon calculates live movement angle from two observed plane points and compares it against the stored route angle.

Angle calculation uses the telemetry convention:

```text
0,0 -> 1,1 = 135 degrees
```

Runtime helper:

```lua
local function GetAngleDeg(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1

    local angle = math.deg(math.atan2(dx, -dy))
    if angle < 0 then
        angle = angle + 360
    end

    return angle
end
```

Tolerance:

```text
default:  +/- 5 degrees
fallback: +/- 8 degrees if no route remains
```

Movement angle is an ambiguity resolver, not a replacement for cell lookup.
The addon must still start from `zoneID -> roughCell -> fineCell -> route candidates`.

Strong angle tie-break:

```text
If several route candidates remain after angle filtering, the addon may accept the closest angle candidate before the cell lookup reaches a single route only when all of these are true:

1. at least two plane points exist and a movement angle exists
2. the closest candidate route angle differs from observed movement by less than 1.0 degree
3. the second closest candidate route angle differs from observed movement by more than 2.0 degrees
4. the same closest route wins for 2 consecutive prediction ticks
```

This rule exists to avoid unnecessary late route locks when telemetry already shows a stable and clearly separated angle winner.

### Prediction Output

Accepted predictions are announced through the normal announcement router using `PREDICTION_UPDATED`.

Prediction announcements use the same announcement router and configured sinks as other crate announcements:

```text
debug window
default chat frame
warning frame
party/raid chat when configured and allowed by sink authority rules
```

Addon-to-addon prediction output remains sink-controlled and must not bypass the announcement router.

Prediction chat output is de-duplicated by crate lifecycle and rounded drop location.
The first accepted location is announced.
Later ETA-only changes are silent.
If the predicted drop location changes, a new prediction announcement is sent.
De-duplication happens before map-pin message building, so suppressed ETA updates do not reset the player's waypoint.

Prediction chat text must stay compact because clickable map pin links count against practical chat message length.
The user-facing message includes zone, compact coordinates without spaces, map pin, drop ETA, and land ETA.
It does not include the words `War Crate`, shard ID, or route ID.
Shard ID and route ID remain available in payload, tokens, and debug data.

The prediction service itself treats the accepted prediction as location state.
After the first accepted prediction for a lifecycle, route-only or ETA-only changes must not publish another `PREDICTION_UPDATED`.

Addon-to-addon prediction output remains controlled by the addon communication sink configuration.

### Location prediction guards

Prediction may start only if:

```text
current state is PLANE_FLYING
no drop/landed/claimed state exists for this lifecycle
prediction has not already been accepted
```

Prediction stops if:

```text
CRATE_DROPPING detected
CRATE_LANDED detected
CRATE_CLAIMED detected
zone changes
shard context changes
session/reload invalidates lifecycle
```

Prediction correction is allowed only under explicit mismatch conditions.

---

## 2.2 Dropping Time Prediction

### Core principle

Dropping time prediction also uses precomputed route/cell data.

Do not use:

```text
global plane speed
global drop to landed time
one route average for all plane positions
```

Use:

```text
route + current cell = seconds to drop
```

### Runtime flow

After the current plane point is converted into rough and fine cells:

```lua
local candidates =
    CrateRushRouteCellIndex[zoneID]
    and CrateRushRouteCellIndex[zoneID][roughKey]
    and CrateRushRouteCellIndex[zoneID][roughKey][fineKey]
```

If a candidate exists:

```text
dropX/dropY = candidate drop location
secondsToDrop = candidate cell based timing
```

User facing output should round the result:

```text
Drop in ~1m10s
Drop in ~45s
```

### Cell based seconds to drop

The converter should generate route/cell timing from telemetry.

For every observed plane point before drop, calculate and store:

```text
zoneID
routeID
roughCell
fineCell
x/y
secondsToDrop
dropX/dropY
samples
confidence
```

Example:

```lua
CrateRushRouteCellIndex[2405]["9:14"]["38:56"] = {
    {
        routeID = "VS_326_382_567",
        dropX = 0.38248,
        dropY = 0.56730,
        secondsToDrop = 42,
        angle = 326.71,
        samples = 6,
        confidence = 0.90,
    },
}
```

This supports mid flight entry. The player does not need to see the monster say or first plane point.

### Zone cycle timers

`CrateRushZoneCycleSeconds` is a compatibility/model name only.
It must alias the real timer source:

```lua
CrateRushZoneCycleSeconds = CrateRush.ZONE_FREQUENCY or {}
```

The single runtime source of zone cycle seconds is:

```text
CrateRush.ZONE_FREQUENCY in gamedata/expansions.lua
```

Cycle timers support next cycle estimation. They do not replace flying phase route prediction.

### Drop to landed timing

After `CRATE_DROPPING`, drop prediction stops.

The addon should then estimate landed time using route/drop timing:

```lua
secondsToLanded = route.avgDropToLandedSeconds
```

This must be route specific.

Observed timing families:

```text
Slayer's Rise:
mostly ~85 to 91s

Voidstorm:
some routes ~2s
some routes ~42 to 45s
some routes ~59s

Harandar:
mostly ~42 to 45s, with a fast ~20s route

Eversong Woods:
one near instant route around ~4s, others longer

Zul'Aman:
route specific, including long ~85s fall routes
```

### Claimed timer

After claim:

```text
CRATE_CLAIMED_BY_ALLIANCE
CRATE_CLAIMED_BY_HORDE
```

the addon may display a claimed loot window estimate:

```text
~68 seconds
```

But telemetry must mark short claimed durations carefully because player loot can truncate the claimed vignette for that player.

Suggested fields:

```lua
claimedDurationUsable = true
claimedDurationTruncated = false
truncationReason = nil
```

or:

```lua
claimedDurationUsable = false
claimedDurationTruncated = true
truncationReason = "PLAYER_LOOTED"
```

### Dropping time guards

Dropping time prediction is valid only during `PLANE_FLYING`.

Prediction stops at:

```text
CRATE_DROPPING
CRATE_LANDED
CRATE_CLAIMED
zone change
reload/session reset
shard context change
```

After drop appears, the addon switches to landed timing. After landed appears, it switches to landed/claim tracking. After claimed appears, it switches to claimed timer tracking.

---

## 2.3 Data Storage

### Runtime model data

The addon should load generated model tables:

```text
CrateRushZoneCycleSeconds aliasing CrateRush.ZONE_FREQUENCY
CrateRushDropClusters
CrateRushRoutes
CrateRushRouteCellIndex
CrateRushClaimedTimerDefaults
```

The generated prediction model is produced by:

```text
tools/generate_prediction_data.py
```

The generator consumes `CrateRush_RouteData.json` and emits runtime Lua route/drop/cell tables.
It must not emit `cycleSeconds`; those remain owned by `CrateRush.ZONE_FREQUENCY`.

### Route cell index fields

Each cell entry should store:

```text
zoneID
roughCell
fineCell
routeID
dropClusterID
dropX/dropY
secondsToDrop
angle
samples
confidence
secondsToLand
```

Optional future fields:

```text
avgDropToLandedSeconds
minSecondsToDrop
maxSecondsToDrop
standardDeviation
lastUpdatedBuild
```

### Telemetry storage

Telemetry should remain raw enough for future model improvement.

Store:

```text
sessionID
timestamp
real timestamp if available
event type
zoneID/mapID
zone text
sub zone
shardID
vignetteID
vignette type
x/y
guid
monster say text
monster say NPC
valid crate say flag
lifecycle state
```

Valid crate monster say texts:

```text
That looks like a treasure out in the distance. Don't miss this opportunity!

You like goods don't you? Then find them.

Take the early advantage and get your spoils.

Keep an eye out for opportunities for loot when they arise, like now!
```

The parser must use only this allowlist for lifecycle anchoring.

### Debug storage

The debug UI window may stay capped, but persistent debug storage should be longer.

Purpose:

```text
prove why the addon made a decision
review dirty transitions
debug route prediction
debug wrong lifecycle assumptions
debug zone/shard/session transitions
```

Debug storage should capture:

```text
timestamp
event
zoneID
shardID
previous state
new state
reason for state change
prediction state
matched routeID
matched rough/fine cell
candidate routes
selected route
seconds to drop
prediction confidence
correction reason if prediction changed
```

### Clean and unclean data

Exporter should split:

```text
clean lifecycles
unclean / partial evidence
```

Clean data is used directly for model generation.

Unclean data can still be useful for:

```text
drop location confirmation
route cell confirmation
debugging live behaviour
parser resilience
edge case review
```

Unclean data should not blindly pollute timing averages.

### Model generation process

```text
1. Collect telemetry SavedVariables.
2. Export lifecycle and raw event XLSX.
3. Build clean lifecycle dataset.
4. Build route/drop clusters.
5. Build route cell timing table.
6. Export Lua model tables.
7. Load generated tables in addon.
8. Use cheap runtime lookup.
```

### Runtime performance rule

Runtime should do only:

```text
coordinate scaling
floor calculation
table lookup
small candidate comparison
simple confidence decision
```

Runtime should avoid:

```text
checking every route
heavy geometry
line distance calculations
large neighbour scans
live clustering
```

---

# Final Design Position

CrateRush prediction is based on this split:

```text
Offline:
heavy analysis, clustering, route cell timing, Lua table generation

Runtime:
cheap cell lookup, candidate resolution, stable one time prediction
```

Prediction is limited to the plane flying phase.

Location prediction tells the player where the crate will drop.

Dropping time prediction tells the player when the crate is expected to drop and later when it is expected to land.

Prediction stops when the real lifecycle state becomes known.
