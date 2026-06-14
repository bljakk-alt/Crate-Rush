# CrateRush Feature Module Guidelines

Status: Locked baseline for new feature modules.

This document defines how CrateRush feature modules are designed, documented, implemented, and reviewed.

Feature modules include optional or semi-independent addon features such as:

- Prediction
- Enemy Presence
- Queue Detection
- Bounty Detection
- RCT compatibility
- future crate hunting helpers

Core lifecycle, timer, guardian, shard confirmation, and current-zone truth are not feature modules. They are core domain systems.

## 1. Purpose

Every feature module must fit the CrateRush architecture instead of becoming a second hidden architecture.

The goal is:

- predictable ownership
- no duplicated domain truth
- no accidental lifecycle or timer mutation
- clean event flow
- easy testing
- clear design documents before implementation

## 2. Required Design Document Format

Every feature module must have a Markdown design document before implementation starts.

Use this exact section structure unless the user explicitly approves an exception:

```text
# CrateRush <Feature Name> Design v1

## 1. Purpose
## 2. Player Goal
## 3. Scope For v1
## 4. Out Of Scope For v1
## 5. User Rules
## 6. Domain Rules
## 7. Data Model
## 8. Activation And Lifecycle
## 9. Integration With Existing CrateRush Systems
## 10. Protocol And Sync
## 11. Architecture Placement
## 12. Configuration
## 13. Performance
## 14. Known Limitations
## 15. Implementation Phases
## 16. Acceptance Criteria
## 17. Open Questions
```

If a feature needs a different structure, update this guideline first and get explicit approval.

## 3. Feature Module Definition

A feature module may:

- subscribe to internal CrateRush events
- request translated WoW event input from the input layer
- keep feature-local runtime state
- publish feature-specific facts
- send output through approved output routers
- use approved protocol APIs when the feature design allows sync
- read configuration through the config gateway

A feature module must not:

- own crate lifecycle truth
- own timer truth
- own shard confirmation truth
- mutate `domainState` directly
- directly call UI frames to force state
- directly call `SendChatMessage`
- directly write SavedVariables except through approved storage/config boundaries
- duplicate constants that already exist in `constants` or `gamedata`
- create new global state outside the CrateRush addon table

## 4. Architecture Boundary

Feature modules sit outside the core crate domain.

Preferred flow:

```text
WoW event
  -> input adapter
  -> internal event translation
  -> feature module
  -> feature-local state
  -> feature event or output request
  -> output router / UI / protocol service
```

Core lifecycle flow stays separate:

```text
WoW crate signal
  -> input adapter
  -> shard confirmation / lifecycle / timer domain
  -> domain event bus
  -> UI / announcements / prediction / comms / other consumers
```

Feature modules may consume core facts, but they must not rewrite core facts unless a design document explicitly defines a domain command and that command is approved.

## 5. WoW Event Declaration

Feature modules should declare which WoW events they need.

The top-level event/input layer owns actual frame registration and raw event receipt.

Feature modules receive translated internal events, not raw frame ownership, unless an exception is approved.

Example:

```text
Queue Detection requests:
- LFG_UPDATE
- UPDATE_BATTLEFIELD_STATUS
- GROUP_ROSTER_UPDATE
```

The input layer translates these into feature-facing events such as:

```text
QUEUE_STATUS_CHANGED
QUEUE_SCAN_REQUESTED
```

This keeps feature modules testable and prevents every module from building its own event system.

## 6. Zone Policy

Each feature design must state its zone policy.

Possible zone policies:

- crate allowed zones only
- current player zone only
- any War Mode outdoor zone
- group-wide, not zone-bound
- explicit feature-specific zone list

Do not blindly reuse crate-core allowed-zone filtering for every feature.

Crate lifecycle events are strict crate-zone facts.

Feature modules may need different rules. For example:

- Prediction is crate-zone and active-lifecycle bound.
- Enemy Presence may be current-location bound.
- Queue Detection is group-state bound and not crate-zone bound.
- Bounty Detection may be current-zone or map-vignette bound depending on the final design.

The design document must say this clearly before code exists.

## 7. Activation And Lifecycle

Every feature module must define:

- when it starts
- when it stops
- what resets its runtime state
- whether it survives `/reload`
- whether it is War Mode dependent
- whether it is group dependent
- whether it is active only during a crate lifecycle

Feature-local state should be wiped when the feature is disabled unless the design explicitly requires persistence.

If a feature has a detection cycle, the design must define what starts and ends that cycle.

## 8. Data Ownership

Feature modules own only their own feature data.

Examples:

- Enemy Presence owns observed enemy GUIDs for its active detection cycle.
- Queue Detection owns recent queue warnings and cooldown state.
- Prediction owns route candidates and last announced prediction for the active crate lifecycle.

They do not own:

- active crate lifecycle
- timer anchors
- shard confirmation
- current zone shard
- group token authority

## 9. Storage Rules

Persistent data must go through approved storage boundaries.

Use storage only when the feature genuinely needs state across reloads or sessions.

Runtime-only observations should remain runtime-only.

Temporary telemetry/debug data is allowed only while explicitly marked temporary.

## 10. Configuration Rules

Feature configuration must go through `config.lua` or the approved config gateway.

Feature modules must not read or write raw SavedVariables for settings.

Configuration defaults should live in one place.

Do not duplicate a default in the feature module and again in the config UI.

## 10.1 Faction Context Rules

Feature modules must consume local player faction through player context.

The local effective faction returned by player context is no-fail (`NO_FAIL_RETURN`). Unknown or invalid real faction falls back to the approved addon fallback, Horde, inside player context only.

Feature modules must not call `UnitFactionGroup("player")` directly.

Feature modules must not choose Horde/Alliance fallback locally.

If a feature needs to compare an observed unit or vignette faction against the local player faction, it must:

- read the local effective faction from player context
- keep observed-game faction facts as feature data
- avoid fallback/defaulting outside player context

## 11. Timing Rules

All gameplay-significant timestamps must use:

```lua
CrateRush.clock:serverTime()
```

This applies to:

- lifecycle-related observations
- protocol sync
- detection cycle windows
- cooldowns
- telemetry
- persisted timing data

`GetTime()` may be used only for local UI animation or non-authoritative visual timing.

## 12. Protocol And Sync Rules

Feature protocol behavior must be documented before implementation.

The design must state:

- whether the feature syncs at all
- whether it uses CrateRush native protocol
- whether it supports an RCT/HatedCrateTracker compatibility message
- whether token validation is required
- who may send
- who may receive
- whether group membership must be verified
- whether messages are leader-authoritative or peer-observed

CrateRush native protocol rules:

- no pipe character as protocol separator
- sender identity uses player GUID, not player name
- normal sync messages require a valid token unless the design explicitly defines a compatibility exception
- malformed or uncertain messages are ignored

Chat output rules:

- do not use pipe characters in any chat message sent through `SendChatMessage`
- clickable map-pin links must be kept short enough for chat delivery
- output must go through the announcement/output router, not direct feature calls

## 13. Output Rules

Feature modules do not directly send user-facing output.

Allowed output path:

```text
feature event or output request
  -> announcement/output router
  -> configured sinks
```

Output sinks include:

- debug log
- default chat frame
- warning frame
- party chat
- raid chat
- addon-to-addon sync
- future UI surfaces

Feature modules should publish facts. The output layer decides where and how to show them.

## 14. UI Rules

Feature modules do not directly mutate UI frames.

UI should render prepared state.

If a feature needs UI, it should expose a small feature state model or publish feature events consumed by UI adapters.

UI must not become the owner of feature logic.

## 15. Constants And Shared Data

Do not duplicate constants.

If a feature needs shared data such as zone cycle durations, allowed zones, route data, or thresholds:

- use the existing constants/gamedata module when it exists
- add one shared source when it does not exist
- do not create a second private copy inside the feature module

If a constant is feature-specific, place it in the feature's approved constants area and document why it is feature-specific.

## 16. Debug And Telemetry

Debug and telemetry are observers.

They must not:

- change lifecycle truth
- change timer truth
- make shard decisions
- become required for normal addon behavior

Temporary telemetry or SavedVariables debug storage must be clearly marked temporary and removable.

## 17. Implementation Phases

Feature implementation should be split into small phases.

Recommended order:

1. Design document accepted.
2. Event declarations and internal input translation.
3. Feature-local state model.
4. Feature domain logic.
5. Feature events/output request.
6. Protocol sync if required.
7. UI integration if required.
8. Config integration if required.
9. Focused tests and in-game test checklist.

Do not combine core architecture refactors with feature implementation unless the design explicitly requires it and the architecture docs are updated first.

## 18. Acceptance Criteria

Every feature design must include acceptance criteria that can be tested.

Acceptance criteria should cover:

- activation
- deactivation/reset
- duplicate prevention
- relevant edge cases
- output behavior
- protocol behavior when applicable
- performance expectations
- interaction with core lifecycle/timer/shard truth

## 19. Change Control

If implementing a feature requires violating the current architecture or rules:

1. stop implementation
2. explain the violation
3. propose the architecture/rule change
4. update the design/rule document after approval
5. continue only after the document matches the intended code

This rule applies to future changes as well as first implementation.

## 20. Current Accepted Feature Documents

Accepted or active feature documents:

- `docs/CrateRush_EnemyPresence_Design_v1.md`
- `docs/CrateRush_Queue_Detection_Design_v1.md`
- `docs/CrateRush_Bounty_Detection_Design_v1.md`
- `docs/CrateRush_Prediction_Design.md`
- `docs/CrateRush_Addon_Protocol_Design_v3.md`

Missing or pending feature documents:

- RCT compatibility design, if implemented separately from native protocol
