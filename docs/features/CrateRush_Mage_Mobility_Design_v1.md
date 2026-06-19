# CrateRush Mage Mobility Design v1

## 1. Purpose

Mage Mobility is a CrateRush feature module that identifies mage portal support available in the player's party or raid.

Crate hunting is a movement problem as much as a detection problem. A mage who can create portals can significantly improve group mobility between crate zones.

Mage Mobility provides compact information about whether portal support is available and who can provide it.

## 2. Player Goal

The player goal is:

```text
Do we have a mage available who can help move the group to the next crate?
```

The feature should help the player or raid leader quickly understand:

- whether the current group contains one or more mages
- which mage players are available
- whether the mage is online and in the group
- whether a mobility reminder should be shown near an upcoming crate
- whether an announcement can ask for a portal without manual typing

## 3. Scope For v1

Mage Mobility v1 includes:

- party and raid roster scanning
- mage detection from roster class data
- online/offline status tracking
- optional AFK/dead status display if available from roster APIs
- feature-local mage list
- compact UI facts for the cockpit or config preview
- announcement placeholder data for future message templates
- optional manual announcement support
- no direct chat sending; all output must go through existing announcement routers

The initial useful output is:

```text
Mage available: Player-Realm
```

or:

```text
Mages available: PlayerOne-Realm, PlayerTwo-Realm
```

## 4. Out Of Scope For v1

The following are out of scope for v1:

- detecting whether a mage knows a specific portal spell
- detecting portal spell cooldowns
- detecting whether a portal object was actually created
- automatic whispering mages
- automatic assignment of a portal mage
- automatic raid leadership decisions
- route optimization based on mage availability
- cross-addon synchronization of mage availability
- non-mage mobility tools such as warlock summons, engineering wormholes, hearthstones, toys, or guild cloaks
- UI redesign

These can be considered later as a broader Mobility module.

## 5. User Rules

Mage Mobility must never imply that a mage is obligated to create a portal.

Mage Mobility must present mage availability as support information, not a command.

The feature must not spam chat.

Automatic announcements, if enabled later, must follow the same leader-gated rules as other automatic announcements.

Manual Shift+Click announcements may bypass leader checks in the same way other manual cockpit broadcasts do.

If no mage is found, the feature should remain quiet by default.

## 6. Domain Rules

Mage Mobility is feature-local roster intelligence.

It must not:

- change crate lifecycle state
- change timer state
- change shard confirmation state
- change prediction state
- write directly to UI frames
- send chat directly
- write SavedVariables directly

Mage identity is based on group roster unit plus normalized player name when available.

The feature should prefer stable player identity:

- full player name with realm when available
- unit token as temporary runtime reference only
- class token `MAGE` as the class truth

Mage availability is derived from current roster state and is not historical.

When the player leaves the group, the mage list is cleared.

## 7. Data Model

Feature-local runtime state:

```lua
MageMobilityState = {
    active = true,
    groupType = "solo" | "party" | "raid",
    mageCount = 0,
    onlineMageCount = 0,
    mages = {
        {
            name = "Player-Realm",
            shortName = "Player",
            realm = "Realm",
            class = "MAGE",
            online = true,
            dead = false,
            afk = false,
            unit = "raid7",
        },
    },
    updatedAt = serverTime,
}
```

Display facts prepared for UI:

```lua
MageMobilityDisplay = {
    available = true,
    count = 2,
    onlineCount = 2,
    label = "Mage available",
    names = "PlayerOne-Realm, PlayerTwo-Realm",
    shortText = "2 mages",
}
```

Announcement placeholder candidates:

```text
%mage_count%
%mage_names%
%mage_available%
%mage_short_text%
```

Placeholder values are display strings only. They must not become domain truth.

## 8. Activation And Lifecycle

Mage Mobility is active when:

- the feature is enabled in configuration
- the player is in a party or raid

Mage Mobility is inactive when:

- the feature is disabled
- the player is solo
- the addon is disabled by global activation rules

Lifecycle:

```text
GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD
  -> input layer observes roster change
  -> Mage Mobility refreshes roster-derived state
  -> Mage Mobility publishes display facts
  -> UI or message services consume display facts
```

The feature should refresh on:

- `GROUP_ROSTER_UPDATE`
- `PLAYER_ENTERING_WORLD`
- `PLAYER_ROLES_ASSIGNED`, if useful
- `READY_CHECK`, only if later needed for UI refresh

Actual event registration remains owned by the top-level event/input layer.

## 9. Integration With Existing CrateRush Systems

Mage Mobility consumes:

- player context for group type
- configuration for enabled/disabled state
- internal event bus for roster refresh triggers
- clock service for `updatedAt`

Mage Mobility publishes:

- `MAGE_MOBILITY_UPDATED`, if a new domain event is added
- display facts through a feature display service
- placeholder facts for announcement formatting

UI integration:

- cockpit may show a compact mobility hint
- config may show feature enablement and message options
- tooltip may show mage names

Announcement integration:

- future upcoming-crate messages may include mage placeholders
- manual announcement may ask for a portal to the next crate
- all output must route through the existing announcement router

## 10. Protocol And Sync

Mage Mobility v1 has no addon-to-addon protocol.

The feature only uses local group roster information already available to the player.

Future sync is not planned unless a concrete need appears.

## 11. Architecture Placement

Proposed file location:

```text
CrateRush/integrations/mageMobility.lua
```

Reason:

- it is an optional support feature
- it is independent from core crate lifecycle
- it belongs beside Enemy Presence, Queue Detection, and Bounty Detection

Allowed dependencies:

- `CrateRush.config`
- `CrateRush.clock`
- `CrateRush.domainEvents`
- player context / group context helpers
- announcement formatter/router for output requests

Disallowed dependencies:

- direct lifecycle mutation
- direct timer mutation
- direct shard mutation
- direct frame manipulation
- direct `SendChatMessage`

## 12. Configuration

Suggested v1 configuration:

```text
Enable mage mobility helper: true/false
Show mage mobility in cockpit: true/false
Allow manual mage portal announcement: true/false
```

Automatic announcement settings should not be added until we decide exact message behavior.

If added later, suggested message:

```text
Mage portal available for %zone%? Next crate in %time_to_next%.
```

This must be routed through the existing message configuration system.

## 13. Performance

Roster scanning is cheap.

The feature should:

- scan only on roster-relevant events
- avoid polling
- store only current roster facts
- clear state when leaving group
- avoid repeated string building unless display facts changed

No per-frame update is allowed.

## 14. Known Limitations

Mage Mobility cannot prove that a mage:

- is willing to create a portal
- has the required portal spell
- has reagents if any future game version requires them
- is near the player
- is out of combat
- noticed the request

The feature only answers:

```text
Is there a mage in the current party or raid roster?
```

Anything beyond that is player coordination.

## 15. Implementation Phases

Phase 1:

- create `integrations/mageMobility.lua`
- scan party/raid roster on group update
- detect class token `MAGE`
- keep feature-local runtime state
- expose simple getter for display facts

Phase 2:

- publish `MAGE_MOBILITY_UPDATED`
- wire display facts into UI model or cockpit placeholder area
- add tooltip detail if a UI tile/hint exists

Phase 3:

- add message placeholders
- add manual announcement support
- ensure output uses existing announcement router

Phase 4:

- consider automatic upcoming-crate portal reminder
- decide whether it is leader-gated
- add configuration only after message behavior is approved

## 16. Acceptance Criteria

Mage Mobility v1 is accepted when:

- joining a party with no mage reports no mage available
- joining a party with one mage reports one mage available
- joining a raid with multiple mages reports all online mages
- leaving group clears mage state
- offline mage state does not count as online availability
- feature does not mutate lifecycle, timer, shard, or prediction state
- feature does not send chat directly
- feature does not poll per frame
- feature follows feature module guidelines

## 17. Open Questions

- Should offline mages be shown separately or hidden?
- Should dead mages count as available for display?
- Should AFK mages be marked separately?
- Should v1 show only online mages, or all roster mages with status?
- Should mage mobility appear in the main cockpit, tooltip only, or configuration preview only?
- Should future automatic portal reminder be tied to upcoming-crate threshold messages?
