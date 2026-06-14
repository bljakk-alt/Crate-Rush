# CrateRush Bounty Detection Design v1

Status: Initial design baseline.

Controlling guideline: [CrateRush_Feature_Module_Guidelines.md](CrateRush_Feature_Module_Guidelines.md)

## 1. Purpose

Bounty Detection is a CrateRush feature module that detects enemy bounty player markers visible to the local player and announces that a bounty target is present on the current map.

The feature is inspired by the RCT/HatedCrateTracker bounty hunter addon behavior, but it must be implemented as a separate CrateRush feature module, not as core crate lifecycle logic.

Bounty Detection is not crate detection.

Bounty Detection is not enemy presence estimation.

Bounty Detection is a simple map-signal feature:

```text
enemy bounty marker seen -> tell the player/group where it is
```

## 2. Player Goal

The player goal is:

```text
Tell me when an enemy bounty player is visible in my current area, and give me the coordinates.
```

The practical use is:

- warn the crate group that a dangerous or interesting enemy target is nearby
- help the player decide whether to avoid, engage, or move differently
- provide a quick map pin/coordinate message when possible

## 3. Scope For v1

Bounty Detection v1 includes:

- listen for bounty-related vignette updates
- detect enemy bounty markers from map vignettes
- identify bounty faction from vignette identity
- compare bounty faction against local player faction
- ignore friendly-faction bounty markers
- read bounty map position when available
- announce enemy bounty location through CrateRush output routing
- de-duplicate by vignette GUID for the active detection window
- reset runtime state when the feature is disabled or the player context is reset

RCT baseline behavior observed:

```text
VIGNETTES_UPDATED
C_Map.GetBestMapForUnit("player")
C_VignetteInfo.GetVignettes()
C_VignetteInfo.GetVignetteInfo(vignetteGUID)
C_VignetteInfo.GetVignettePosition(vignetteGUID, mapID)
CrateRush.playerContext local faction
```

RCT parses the vignette GUID and treats:

```text
2901 = Alliance bounty
2902 = Horde bounty
```

CrateRush v1 may use the same IDs as the starting rule. If live testing proves different IDs or additional IDs, update this document before changing implementation.

Local player faction must come from player context. Bounty Detection must not call `UnitFactionGroup("player")` directly or choose a local faction fallback.

## 4. Out Of Scope For v1

The following are out of scope for v1:

- proving the bounty target is still alive
- tracking bounty movement over time
- estimating fight strength
- removing bounty observations when the target disappears
- building a full bounty history
- ranking bounty danger
- auto-targeting
- automatic raid marking
- whispering players
- CrateRush-native bounty addon-to-addon sync
- RCT-compatible bounty addon-to-addon sync
- changing crate lifecycle, timer lifecycle, guardian, shard, or prediction truth

## 5. User Rules

Bounty Detection must announce only enemy-faction bounty markers.

Faction rule:

```text
local Horde player sees Alliance bounty -> announce
local Alliance player sees Horde bounty -> announce
local Horde player sees Horde bounty -> ignore
local Alliance player sees Alliance bounty -> ignore
```

For the user’s current testing reality, Horde characters are the primary test path.

Recommended message shape:

```text
Enemy bounty spotted in <zone> at <coords> <map pin>
```

If coordinates are not available:

```text
Enemy bounty spotted in <zone> (location not available)
```

Bounty Detection must not spam repeated alerts for the same vignette GUID.

## 6. Domain Rules

Bounty Detection recognizes bounty observations, not crate states.

Accepted bounty observation:

```text
vignette exists
vignette faction marker is known
vignette faction is enemy faction
feature is enabled
player context allows the feature
```

Bounty observation key:

```text
vignetteGUID
```

The same `vignetteGUID` should be announced once per detection window.

If the same bounty is reported again with the same GUID, do not announce it again.

If a new GUID appears, treat it as a new observation.

Bounty Detection must not infer crate lifecycle state from a bounty marker.

Bounty Detection must not start, correct, or delete crate timers.

## 7. Data Model

Runtime state:

```lua
bountyObservationsByGUID = {
    [vignetteGUID] = {
        vignetteGUID = "Vignette-...",
        mapID        = 2405,
        factionID    = 2901,
        enemyFaction = "Alliance",
        localFaction = "Horde",
        x            = 0.451,
        y            = 0.630,
        zoneName     = "Slayer's Rise",
        firstSeenAt  = serverTime,
        lastSeenAt   = serverTime,
        announcedAt  = serverTime,
        source       = "VIGNETTE",
    },
}
```

Optional alert throttle:

```lua
lastBountyAlertAt = {
    [vignetteGUID] = serverTime,
}
```

Coordinate display:

```text
raw map coordinates: 0.0 to 1.0
display coordinates: x * 100, y * 100
```

## 8. Activation And Lifecycle

Bounty Detection is active when:

```text
feature enabled
player faction known
player map known
War Mode state allows CrateRush feature operation
```

Zone policy:

```text
current player map/zone, not crate allowed-zone bound
```

Bounty Detection must not require the player to be in a crate allowed zone.

It uses current player map context because bounty markers are map/vignette facts, not crate-zone facts.

Feature event declaration:

```text
VIGNETTES_UPDATED
PLAYER_ENTERING_WORLD
ZONE_CHANGED
ZONE_CHANGED_NEW_AREA
```

`PLAYER_ENTERING_WORLD`, `ZONE_CHANGED`, and `ZONE_CHANGED_NEW_AREA` refresh player map context and may reset stale bounty observations when the current map/zone changes.

Feature-facing internal events:

```text
BOUNTY_SCAN_REQUESTED
BOUNTY_OBSERVED
```

Runtime state is wiped when:

- feature is disabled
- addon reloads
- player context resets
- optional future detection-cycle reset fires

## 9. Integration With Existing CrateRush Systems

Bounty Detection integrates with:

- input adapter for vignette scan requests
- player context for faction and map context
- config gateway for enable state
- announcement/output router for user-facing messages
- map pin helper for clickable location links when coordinates exist

Bounty Detection must not change:

- crate lifecycle
- timer lifecycle
- guardian state
- shard confirmation
- prediction route state
- Enemy Presence state
- Queue Detection state

Bounty Detection follows the feature-module rule:

```text
VIGNETTES_UPDATED
  -> input adapter
  -> bounty detection service
  -> bounty observed feature event
  -> output router
```

It must not be routed through crate allowed-zone filtering.

## 10. Protocol And Sync

Bounty Detection v1 is local-output only.

No CrateRush-native addon-to-addon bounty message is included in v1.

No RCT-compatible bounty message is included in v1.

Reason:

- the RCT bounty file inspected does not send addon messages
- local map visibility is enough for first implementation
- protocol behavior should be designed separately if group sharing becomes desired

Future protocol support may add:

```text
BOUNTY_OBSERVED
```

If added later, that protocol message must follow CrateRush native protocol rules:

- no pipe separator
- sender GUID identity
- valid group token for normal CrateRush sync
- current group validation
- fail closed on malformed data

## 11. Architecture Placement

Input adapter:

```text
receives VIGNETTES_UPDATED and requests a bounty scan
```

Feature service:

```text
logic/bountyDetection.lua owns bounty scan interpretation,
enemy-faction filtering, GUID dedupe, and feature events.
```

Output adapter:

```text
announcement/output routing owns chat, warning frame, debug, party/raid,
and map-pin display text.
```

Bounty Detection service must not call:

```text
SendChatMessage directly
UI frames directly
timer lifecycle services
crate lifecycle transition functions
shard services
prediction route services
Enemy Presence aggregation services
```

Proposed feature event:

```text
BOUNTY_OBSERVED
```

Event payload:

```text
vignetteGUID
mapID
zoneName
factionID
enemyFaction
localFaction
x
y
mapPinLink if available
observedAt
source
```

## 12. Configuration

Planned config keys:

```text
bountyDetectionEnabled
bountyDetectionOutputDefaultChat
bountyDetectionOutputWarningFrame
bountyDetectionOutputParty
bountyDetectionIncludeMapPin
```

Defaults:

```text
bountyDetectionEnabled = false
bountyDetectionOutputDefaultChat = true
bountyDetectionOutputWarningFrame = true
bountyDetectionOutputParty = false
bountyDetectionIncludeMapPin = true
```

Default is disabled until the feature is implemented and tested.

## 13. Performance

Bounty Detection is event-driven.

It scans vignettes only when requested by relevant input events.

Expected cost:

- iterate current vignette list
- inspect vignette info
- inspect vignette position for candidate bounty IDs
- dedupe by GUID

Do not poll continuously.

Do not run expensive work outside bounty scan requests.

## 14. Known Limitations

Bounty Detection relies on map/vignette visibility.

If Blizzard does not expose the bounty marker to the local client, CrateRush cannot detect it.

Bounty Detection v1 does not know whether the bounty target is still near the crate.

Bounty Detection v1 does not remove stale observations except through detection-window reset.

Faction IDs are based on RCT behavior and must be confirmed with live CrateRush telemetry during implementation.

The user primarily tests Horde characters, so Alliance-path testing may need later confirmation.

## 15. Implementation Phases

Phase 1: design and constants

- create bounty feature design
- define bounty vignette IDs in one shared feature constant location
- define feature config defaults

Phase 2: input translation

- declare required WoW events
- route `VIGNETTES_UPDATED` to feature scan request
- avoid crate allowed-zone filtering

Phase 3: bounty scan service

- scan current vignettes
- identify bounty faction
- compare against local faction
- collect coordinates
- dedupe by vignette GUID
- publish `BOUNTY_OBSERVED`

Phase 4: output routing

- add bounty output template
- include map pin when available
- include `(location not available)` when coordinates are missing
- route through configured output sinks

Phase 5: in-game testing

- verify `2901` and `2902` against live vignette data before marking the feature complete
- record at least one observed debug sample for each confirmed bounty marker ID
- Horde detects Alliance bounty
- Horde ignores Horde/friendly bounty if ever exposed
- repeated same GUID does not spam
- no crate lifecycle/timer/shard state changes happen

## 16. Acceptance Criteria

Bounty Detection v1 is complete when:

- enemy bounty vignette is detected from `VIGNETTES_UPDATED`
- local player faction is respected
- bounty vignette IDs have been verified from live data
- friendly bounty marker is ignored
- enemy bounty marker is announced once per GUID per detection window
- coordinates are included when available
- map pin is included when available
- missing coordinates still produce useful output with `(location not available)`
- feature does not require crate allowed zone
- feature does not alter crate lifecycle, timer lifecycle, guardian, shard, prediction, enemy presence, or queue state
- feature output goes through CrateRush output routing
- service does not call `SendChatMessage` directly

## 17. Open Questions

Open questions before or during implementation:

```text
Should bountyDetectionEnabled default to true after first successful testing?
Should bounty alerts go to party by default or stay local by default?
Should observations reset on zone switch, timer, or manual clear?
Do faction IDs 2901 and 2902 remain stable across all relevant zones?
Should future CrateRush protocol share bounty observations with group members?
```
