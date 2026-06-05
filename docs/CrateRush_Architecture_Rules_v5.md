# CrateRush Architecture & Development Rules v5

World of Warcraft addon - War Mode crate tracker

## Companion Artifacts

- SVG diagram: `docs/craterush_architecture_v5.svg`
- Word document: `docs/CrateRush_Architecture_Rules_v5.docx`
- Source notes: `docs/CrateRush_Architecture_Rules_v5.md`
- Lifecycle/timer contract: `docs/Lifecycle_Timer_Contract.md`
- Contract checker: `tools/lifecycle_timer_contract_check.py`

## Architecture Contract

This document is the design contract for future CrateRush work.

Every future code change must fit this architecture and ruleset. If a requested change cannot fit without violating the architecture, pause before coding, explain the conflict, propose the architecture/rules adjustment, update this document and the diagram after approval, and only then implement the code.

Existing legacy violations are allowed only as refactor targets. New work must not introduce new violations. Refactor steps may add a short-lived bridge only when it removes an existing violation, and the bridge must be named and removed in the same step or the next agreed step.

## Temporary Debug Exception

The current debug window and direct debug logging are intentionally excluded from architecture violation checks for now. The debug feature is temporary and will be deleted or replaced later.

While this exception exists, debug must remain a one-way observer. It must not own domain truth, make crate decisions, change timers, affect shard confirmation, or become required for normal addon behavior.

## Target Layer Model

| Layer | Modules | Responsibility |
| --- | --- | --- |
| Bootstrap | `main.lua` | Owns load order, module init, slash commands, and top-level wiring only. |
| Static data | `locale`, `constants`, `gamedata` | Provides named strings, states, timings, allowed crate zones, crate zone mappings, vignettes, NPC names, and expansion data. No runtime decisions. |
| Config gateway | `config.lua`, `data/db.lua` | Provides settings through `config:get/set`. SavedVariables are accessed only through `data/db.lua`. |
| Input adapters | `events.lua`, inbound comms, inbound integrations | Receive outside signals and delegate immediately to domain commands/services. |
| Domain services | crate scanning, zone resolver, live shard service, crate lifecycle service, timer service, prediction, map logic | Interpret game input, resolve crate zones, confirm live shards, apply crate lifecycle rules, and compute active timer facts. |
| Domain state | `domainState.lua`, current zone/shard index, active timer index, observation records | Owns in-memory truth: one current shard per zone, one current lifecycle per zone, one active timer per zone, optional historical observations by `zone:shard`. |
| Boundary | domain event bus / state publisher | Publishes finalized facts after state/storage changes. Output modules subscribe. |
| Output adapters | UI header, timerbars, announcement service/router/sinks, outbound comms, external integrations | Render, send, or broadcast from published state. They never own domain truth. |

## Allowed Dependencies

- Bootstrap may initialize and wire modules.
- Static data may be read by any layer, but must not call runtime logic.
- Input adapters may call domain services only.
- Domain services may read constants, gamedata, config, storage gateway, and domain state.
- Domain services must not call UI, timerbars, announce, outbound comms, or integration outputs directly.
- Domain services publish facts through the domain event bus after state/storage has been updated.
- Output adapters subscribe to published facts and render/send only.
- UI actions call domain commands; UI must not mutate timer or shard state directly.

## Core Invariants

- `zone:shard` identifies observations, sightings, and lifecycle evidence.
- A crate zone owns one current shard at a time.
- A crate zone owns one active timer at a time.
- Runtime may keep historical observation detail by `zone:shard`, but current UI/timer state is zone-scoped.
- `domainState.lua` is the runtime owner for lifecycle records, active timer records, current lifecycle indexes, and active timer indexes.
- `shardmap` may apply lifecycle, guardian, and timer policy rules, but it must store lifecycle records through `domainState`.
- `timers` may tick, restore, roll over, and publish timer facts, but it must store active timer records through `domainState`.
- Storage persists crate history records by `zoneID + shardID`; only one current record may remain active per crate zone.
- Header UI displays live game-derived zone/shard state. It must not substitute a stored shard from another zone or old observation.
- Timer rows may display the shard attached to the active timer record.
- State/storage updates happen before UI/timer/announce events are published.
- Only domain state decides whether a shard or timer is current.

## Zone And Shard Rules

- Allowed crate zones and crate zone mappings live in `gamedata/zones.lua`.
- Expansion-specific vignettes, NPC names, phrases, and zone frequencies live in `gamedata/expansions.lua` until a later split is needed.
- Use the term "crate zone mapping" for subzone-to-crate-zone resolution. Do not call this normalization in code or docs.
- Raw player subzones such as "The Den" must be mapped to their crate zone, such as Harandar, before domain processing and before header display.
- Header text is based on the current live game zone/shard scan.
- If the shard is being checked and no confirmed live shard should be displayed yet, the header shows `[checking shard]`.
- If a live shard matches the current stored/current shard for that crate zone, status is matched.
- If a live shard is being settled or confirmed, status is checking.
- If a live shard is confirmed and differs from the current shard for that crate zone, status is mismatch.
- If there is no previous/current shard information for that crate zone, status is unknown.
- When a new live shard is accepted for a zone, the domain updates the current zone shard first, persists through the storage gateway when applicable, then publishes UI and timer refresh events.

## Crate Lifecycle Rules

- Crate lifecycle, timer lifecycle, guardian, and announcements are four separate concepts.
- Do not mix crate lifecycle reset logic with timer lifecycle correction logic.
- A crate state may be valid for the crate lifecycle without being allowed to reset the timer.
- Crate lifecycle is identified by `zoneID + shardID`.
- The crate lifecycle state order is `DETECTED -> DROPPING -> LANDED -> CLAIMED`.
- `DETECTED` is the only mandatory state. If the first observed event is `DROPPING`, `LANDED`, or `CLAIMED`, create `DETECTED` implicitly first.
- Do not invent `DROPPING`, `LANDED`, or `CLAIMED`. They only exist if directly observed.
- Accepted lifecycle start always creates or resets `DETECTED` and resets the guardian for that exact `zoneID + shardID`.
- After guardian has elapsed, an observed crate state starts a new lifecycle for that `zoneID + shardID`, even if the state order would otherwise look like forward progress.
- If a new accepted lifecycle is detected for the same zone but a different shard, delete the old lifecycle for that zone and replace it with the new `zoneID + shardID`.
- `FLYING` is a source/vignette concept, not the lifecycle state name. Accepted monster say or confirmed flying creates `DETECTED`.
- Base crate states are `IDLE`, `DETECTED`, `DROPPING`, `LANDED`, `CLAIMED_BY_ALLIANCE`, and `CLAIMED_BY_HORDE`.
- `CLAIMED_BY_ALLIANCE` and `CLAIMED_BY_HORDE` mean the crate is lootable by that faction.
- `LOOTABLE_BY_ME` is a derived fact based on player faction and the claimed state. It is not a replacement for the base claimed states.

## Timer Lifecycle Rules

- Timers are stored by `zoneID + shardID`, but only one timer is displayed per `zoneID`.
- If a new accepted timer appears for the same zone but a different shard, remove the old timer key and create the new `zoneID + shardID` timer.
- The goal is always to keep the best available timer.
- The timer represents the best known approximation of the monster say moment, because monster say is chronologically the first crate lifecycle event.
- When monster say is missed, accepted non-monster evidence should pull the timer earlier toward the missed monster say whenever possible.
- Monster say always resets the timer because it is the best cycle anchor.
- For every accepted non-monster lifecycle start after guardian, the previous timer source/quality does not decide replacement.
- A non-monster lifecycle start replaces the timer only when the current timer cycle is guardian-aged and `now` is earlier than that cycle's pending rollover.
- If a non-monster lifecycle start is observed after the old timer has already rolled over, do not move the timer later; keep the earlier rolled-over timestamp.
- If no usable timer exists for the current `zoneID + shardID`, the accepted lifecycle start creates one.
- If a timer expires, roll it over by adding the configured zone duration to the previous expected timestamp, not by using `now`.
- Timer history is not created from zone switching alone. A crate lifecycle signal is required.
- A crate sighting may update last-seen state for stale cleanup without changing the timer anchor.
- If a zone timer is not seen for the configured maximum number of cycles, the active timer is removed and a notification placeholder event is published.

## Guardian Rules

- Guardian is keyed by `zoneID + shardID`.
- Guardian protects against premature or duplicate lifecycle resets.
- Guardian should block false lifecycle starts caused by noisy events, for example a single flying signal when nothing is actually flying.
- Guardian does not directly block announcements.
- Guardian blocks state creation or lifecycle reset. Since announcements are triggered by accepted states, guardian controls announcements indirectly through state control.
- Guardian for `zoneID + oldShardID` must not block `zoneID + newShardID`.

## Flying Vignette Confirmation

- Plane/flying vignette events are noisy and must be confirmed before they anchor a timer or trigger announce/comms behavior.
- Flying is accepted only after the configured number of sightings inside the configured window.
- While the lifecycle detection guard is active for a `zone:shard`, plane/flying sightings are ignored before confirmation counting and must not advance the plane counter.
- Current target: 3 flying sightings with consecutive gaps no greater than 3 seconds.
- Dropping, landed, and claimed crate states supersede flying for the same crate lifecycle.
- Once a crate object state is observed, the plane is no longer relevant for that lifecycle.
- First-seen vignette de-duplication may suppress raw dumps, but it must not prevent a live crate object state from recovering missing lifecycle or timer runtime state.

## Announcement Rules

- Announcements are state driven.
- `announce.lua` subscribes to `crateStateChanged`, performs per-lifecycle/state de-duplication, and delegates message building/routing.
- `logic/announcements/templates.lua` owns user-facing announcement text, future placeholder expansion, and coordinate/map-pin insertion.
- `logic/announcements/router.lua` owns fan-out to announcement sinks.
- Announcement sinks own output side effects only: debug logging, default chat frame echo, warning frame display, party/raid chat, and future addon-to-addon comms.
- Announcement sinks must not own crate lifecycle, timer lifecycle, guardian, shard confirmation, or storage truth.
- The same finalized announcement message should be routed to every enabled sink unless future configuration explicitly says otherwise.
- Placeholder-style configuration must be implemented in the announcement template layer, with tokens such as `%zone%`, `%shard%`, `%state%`, and `%coordinates%`.
- When `DETECTED` is accepted, announce once per lifecycle: `War Crate Detected Flying`.
- When `DROPPING` is accepted, announce once per lifecycle: `War Crate Falling`.
- When `LANDED` is accepted, announce once per lifecycle: `War Crate Landed`.
- Claimed announcements are allowed as state-driven placeholders, but the final user-facing behavior will depend on faction and notification settings.
- Do not announce duplicate states inside the same lifecycle.

## Domain Events

The domain event bus publishes finalized facts. Event payloads should be plain tables with named fields.

| Event | Meaning |
| --- | --- |
| `zoneShardStatusChanged` | Header-relevant live zone/shard status changed. |
| `currentZoneShardChanged` | Domain current shard for a crate zone changed. |
| `crateStateChanged` | Accepted crate lifecycle state changed for a zone/shard. |
| `crateSightingSeen` | Crate-related sighting touched last-seen state without necessarily changing lifecycle state. |
| `activeTimerChanged` | Active timer for a zone changed, corrected, or rolled over. |
| `activeTimerRemoved` | Active timer for a zone was removed or expired. |
| `syncRequested` | Future outbound comms should send current facts. |
| `notificationRequested` | Future user notification placeholder. |

## Persistence And Config Rules

- SavedVariables are accessed only by `data/db.lua`.
- Runtime settings are read through `config.lua`.
- Domain services must not call `storage:get(...)` directly for settings.
- `data/db.lua` validates and migrates persisted data.
- Crate timer history is keyed by `zoneID + shardID`, not by current UI row identity.
- Observations may be keyed by `zone:shard`, but active/current facts are zone-scoped.

## UI Rules

- UI renders ready-to-display state only.
- Header does not decide shard match/mismatch/checking.
- Timerbars do not decide lifecycle or timer correction.
- UI may request a domain command, such as remove timer, but must not mutate timer state directly.
- War Mode indicator is display state. If the domain needs War Mode later, it must be published as player context state.

## Development Rules

| Rule | v5 Interpretation |
| --- | --- |
| Architecture first | If a change violates this document, ask permission and update the document/diagram before coding. |
| No magic numbers or strings | Named constants are required outside constants, gamedata, locale, config defaults, and tightly scoped UI layout tokens. |
| Clean architecture | Dependencies move through the layer model. Domain publishes facts; adapters subscribe. |
| No uncontrolled global state | The addon table is the only global namespace. State must be owned by a module and accessed through an interface. |
| Single source of truth | Each fact has one owner. Derived views are allowed only when refreshed from the owner. |
| Fail silently | External calls must be nil-checked and protected where errors can surface to players. |
| No business logic in UI | UI receives ready-to-display values and renders them. |
| No logic in events | WoW event handlers dispatch only. |
| Defensive coding | Validate WoW API, comms, integrations, and SavedVariables inputs before use. |
| Consistent naming | camelCase functions/variables, PascalCase module types when used, UPPER_SNAKE_CASE constants. |
| No hardcoded faction assumptions | Faction behavior must be data-driven and derive `LOOTABLE_BY_ME` from player faction. |
| Debug exception | Temporary debug is ignored for violation checks, but must remain one-way and non-authoritative. |
| No print in addon code | Addon output goes through approved output/logging paths only. Vendored library code is exempt. |
| No goto or continue | Use early returns and function decomposition. |
| Verify before delivery | Every change gets a rule check, static check, and relevant in-game test guidance. |
| Lifecycle/timer contract | Changes touching lifecycle, timer, guardian, storage, or announcements must pass `tools/lifecycle_timer_contract_check.py` before delivery. |

## Known Legacy Gaps To Remove

Debug is intentionally excluded from this list.

| Gap | Target |
| --- | --- |
| None currently tracked | New gaps require approval and must be documented here before implementation. |

## Refactor Plan

| Step | Name | Outcome |
| --- | --- | --- |
| 0 | Architecture contract v5 | Update doc and diagram first; future changes use this as the gate. |
| 1 | Domain event bus | Add synchronous `emit/subscribe` boundary for finalized domain facts. |
| 2 | Header publisher | Completed: header zone/shard state is published via `zoneShardStatusChanged`; `crateHandler` no longer calls UI frames directly. |
| 3 | Timer publisher | Completed: timerbars subscribe to `activeTimerChanged` / `activeTimerRemoved`; timers no longer call timerbars directly. |
| 4 | Announce subscriber | Completed: announce is behind `crateStateChanged`; faction-derived `LOOTABLE_BY_ME` remains future state-decoration work when claimed-state UI needs it. |
| 4b | Timer subscriber | Completed: active timer refresh is behind `crateStateChanged` and `crateSightingSeen`; timer cleanup no longer calls the `shardmap` compatibility facade. |
| 4c | Lifecycle/timer contract lock | Completed: executable contract scenarios cover lifecycle, timer, guardian, and announcement behavior before further refactoring. |
| 5a | Passive domain state mirror | Completed: add `domainState.lua` as an event subscriber that mirrors lifecycle, timer, and zone/shard facts without owning decisions yet. |
| 5b | Mirror/runtime comparison | Completed: add debug-only diagnostics that compare `domainState` against current `shardmap` and `timers` runtime state without changing behavior. |
| 5 | Central domain state | Completed: `domainState` owns lifecycle records, current lifecycle indexes, timer records, and active timer indexes; `shardmap` and `timers` no longer keep private runtime truth tables. |
| 6 | Config gateway | Completed: `config.lua` owns runtime settings reads/writes; logic modules no longer call generic `storage:get` for settings. |
| 7a | Zone resolver service | Completed: `zoneResolver` owns raw map to crate-zone resolution, crate-zone names, and player zone context; `crateHandler` consumes it instead of keeping local zone-resolution helpers. |
| 7b | Vignette scanner service | Completed: `vignetteScanner` owns raw vignette API reads, vignette ID classification, position lookup, shard extraction, and context-key packaging; `crateHandler` consumes prepared sightings and still owns existing decisions. |
| 7c | Shard service | Completed: `shardService` owns live shard confirmation, zone-shard grace/polling, current-zone shard status publication, and previous-zone shard ambiguity handling. |
| 7d | Crate lifecycle service | Completed: `crateLifecycle` owns lifecycle state transitions, lifecycle guardian, duplicate state handling, plane confirmation, and lifecycle domain events. |
| 7e | Timer policy service | Completed: `timerPolicy` owns timer anchor quality, rollover comparison, guardian-aged fallback correction, and timer anchor debug fields. |
| 7f | Transition and monster-say services | Completed: `transitionGuard` owns stale cross-zone vignette ownership checks; `monsterSayService` owns NPC/phrase matching. |
| 7 | Split domain services | Completed: `crateHandler` is now an event orchestrator; `shardmap` is a compatibility facade over `shardService` and `crateLifecycle`. |
| 7g | Timer removal ownership cleanup | Completed: timerbars publish `timerRemovalRequested`; timer service owns removal, storage cleanup, and lifecycle reset through `crateLifecycle`. |
| 7h | Announcement subdomains | Completed: `announce.lua` is the state subscriber/de-duplicator; `announcementTemplates`, `announcementRouter`, and sinks own message building and output fan-out. |
| 8 | Future comms/integrations | Add party/raid sync and external integrations as subscribers/publishers that never own truth. |

## Pre-Code Gate

Before implementing any future change, answer these checks:

- Does this change keep domain logic from directly calling UI, timerbars, announce, outbound comms, or integrations?
- Does this change preserve one current shard per crate zone?
- Does this change preserve one active timer per crate zone?
- Does this change keep header state live-game-derived?
- Does this change keep timer/history state domain-owned?
- Does this change avoid adding new direct storage settings reads?
- Does this change avoid adding business logic to UI or event handlers?
- If any answer is no, stop and update the architecture/rules with approval before coding.

## Delivery Checklist

- No new architecture violation unless explicitly approved and documented first.
- No new inline behavior constants outside approved locations.
- No new domain-to-output direct calls.
- Storage remains the only SavedVariables gateway.
- Config values come through config gateway after step 6.
- State/storage is updated before published events.
- Refactor steps are synced to the live addon folder and tested with `/reload` guidance.
