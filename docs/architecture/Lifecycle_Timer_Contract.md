# Crate Lifecycle / Timer Contract

This is the behavior lock for the fragile crate lifecycle logic. Run the contract
checker before and after refactoring lifecycle, timer, guardian, storage, or
announcement code.

## Concepts

- Crate Lifecycle, Timer Lifecycle, Guardian, and Announcements are separate.
- Guardian controls lifecycle starts/resets, not state progress.
- Timer policy decides whether a valid state may change the timer.
- The timer approximates the crate cycle anchor moment. When the crate cycle anchor is missed, accepted fallback evidence may only pull that approximation earlier toward the missed anchor.
- Announcements are driven by accepted states, not by timer changes.
- A directly observed `LANDED` state must close. If the landed crate disappears without an own-faction claimed marker, CrateRush treats the player-facing outcome as `CLAIMED_BY_OPPOSITE_FACTION`; there is no separate expired crate outcome in the lifecycle.
- A fresh own-faction claim is only marked when `CLAIMED_BY_MY_FACTION` follows a directly observed `LANDED` state inside the same lifecycle. A claimed marker seen without that prior `LANDED` is still a claimed state, but it must not be treated as proof of the just-opened loot window.
- Vignette ownership is zone-scoped. A crate GUID, and its state-independent context key such as `Vignette-0-3892-0-102`, first seen in one crate zone must not later create shard, lifecycle, timer, or announcement state for another zone.
- During a zone transition, evidence for the previous zone's shard may be counted for current-zone shard confirmation, but it must not create lifecycle/timer state until that shard is confirmed for the current zone.
- Crate lifecycle/timer/announcement success requires the event shard to be confirmed for the current zone at the start of the scan. A scan may confirm a shard, but it may not spend that same scan as crate state success.
- `domainState` owns runtime lifecycle records, active timer records, current lifecycle indexes, and active timer indexes.
- `shardmap` applies crate lifecycle/guardian/timer policy rules against `domainState`; it must not keep a second private lifecycle table.
- `timers` ticks, restores, rolls over, and publishes active timer facts against `domainState`; it must not keep a second private active timer table.
- All lifecycle, timer, shard confirmation, storage, telemetry, and future comms timestamps use shared server time through `CrateRush.clock:serverTime()`.
- Raw `GetServerTime()` and `GetTime()` calls must not appear in lifecycle/timer/shard/storage/comms-ready logic; they stay centralized behind `utils/clock.lua`.
- Diagnostics, while present, are debug-only observers and must only log mismatches.

## Locked Scenarios

| Scenario | Required behavior |
| --- | --- |
| Monster say | Accept `DETECTED`, announce detected once, create/replace authoritative timer. |
| Confirmed flying | Accept `DETECTED` only after plane confirmation and only if guardian allows lifecycle start. Flying confirmation gates lifecycle acceptance only; timer policy remains unchanged. |
| Plane during guardian | Do not advance plane confirmation candidate tracking. |
| Plane moved | For the same `zoneID + shardID + plane GUID`, if consecutive coordinates move more than the configured map-degree tolerance, accept `DETECTED` from `FLYING`. |
| Plane held at anchor | For the same `zoneID + shardID + plane GUID`, two consecutive observations at the configured zone anchor accept `DETECTED` from `FLYING`. |
| Plane held on known route | For the same `zoneID + shardID + plane GUID`, a non-moving plane point accepts `DETECTED` only if route data says the point is high-confidence en-route and not near a known drop location. |
| Plane held near drop | Do not accept `DETECTED` from `FLYING`; wait for crate object evidence. |
| Plane held unknown | Do not accept `DETECTED` from `FLYING`; log pending only. |
| Dropping after detected | Accept `DROPPING` inside guardian, announce falling, do not reset authoritative timer. |
| Landed after dropping | Accept `LANDED` inside guardian, announce landed, do not reset authoritative timer. |
| Landed still visible | Keep `LANDED`; reset any pending landed-gone closure counter for that `zoneID + shardID`. |
| Own-faction claim after landed | Accept `CLAIMED_BY_MY_FACTION`, mark it as a fresh claim, publish claim timestamp/faction fields, and do not reset timer. |
| Own-faction claim without prior landed | Accept `CLAIMED_BY_MY_FACTION`, but do not mark it as a fresh claim. |
| Landed gone, plane still visible | After the configured number of real `VIGNETTES_UPDATED` scans with `FLYING` and no `LANDED` for the same confirmed `zoneID + shardID`, accept `CLAIMED_BY_OPPOSITE_FACTION`, announce claimed once, do not reset timer. |
| Landed gone, no own-faction marker | After the configured landed-gone expiry window, accept `CLAIMED_BY_OPPOSITE_FACTION`, announce claimed once, do not reset timer. |
| Non-map rescan after landed | Group roster, zone poll, shard grace, and debug-style rescans must not advance landed-gone closure counters. |
| Duplicate state | Do not announce duplicate `DROPPING`, `LANDED`, or `CLAIMED` inside the same lifecycle. |
| First event is fallback | Create `DETECTED` implicitly, then accept the observed fallback state. |
| Seen crate object | A live `DROPPING`, `LANDED`, or `CLAIMED` object may recover missing lifecycle/timer state even if its vignette GUID was seen before. |
| Same GUID changes zone | Reject it as stale transition evidence before shard confirmation, lifecycle, timer, or announcements. |
| Same vignette context changes zone | Reject it even if the state changed and the full GUID is different, for example `DROPPING` becoming `LANDED`. |
| Previous-zone shard during transition | Require current-zone shard confirmation before the crate object may create lifecycle/timer state. |
| Shard confirmed by this scan | Defer crate lifecycle/timer/announcement success until a later scan where that shard was already confirmed at scan start. |
| Post-guardian state | After guardian, an observed crate state starts a new lifecycle even if it would look like forward state progress. |
| Non-monster timer | Accepted non-monster lifecycle starts replace the timer only when the timer cycle is guardian-aged and `now` is earlier than that cycle's pending rollover, regardless of previous timer source/quality. |
| Post-rollover event | If the old timer already rolled over, a later non-monster event must not move the timer later. |
| Monster say | Monster say always replaces the timer. |
| Same zone new shard | Accepted new shard replaces old lifecycle/timer for that zone. Old shard guardian must not block it. |
| Timer rollover | Rollover uses previous expected timestamp plus zone duration, never `now` as the new base. |

## Nice To Have

- Pending crate cycle anchor buffer: if `CRATE_CYCLE_ANCHOR` is seen during a zone transition before `zoneID + shardID` is confirmed, queue the anchor timestamp and source. Once the current zone/shard is confirmed, assign the queued authoritative anchor only if it can be proven to belong to that confirmed `zoneID + shardID`; otherwise discard it. This would recover the best timer in the rare edge case where the first crate evidence is heard exactly while changing zones, without risking assignment to the wrong zone.

## Debug Telemetry Contract

Timer anchor debug lines are part of the test/debug workflow while this addon is being calibrated. Do not remove these fields during refactors:

- `oldStart`
- `newStart`
- `elapsed`
- `cycles`
- `cycleTime`

## Command

From the workspace root:

```powershell
python tools/lifecycle_timer_contract_check.py
```

Codex can run it with the bundled Python runtime if system Python is not
available.
