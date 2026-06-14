# CrateRush Enemy Presence Design v1

## 1. Purpose

Enemy Presence is a CrateRush feature that estimates visible enemy force near an active crate location.

It is a supporting intelligence feature. It collects local and group-observed enemy player data, estimates total enemy count, estimates healer pressure, and prepares a compact summary for the player.

Enemy Presence does not decide whether the player should fight. It only provides information.

## 2. Player Goal

The player goal is:

```text
Is the enemy force near this crate probably fightable?
```

The feature should help the player, party, or raid leader quickly understand:

- how many enemy players have been observed near the crate
- how many healers are confirmed
- how many additional healers are possible
- which classes make up the enemy force
- whether the estimate is based only on local visibility or also confirmed by other CrateRush users

Enemy Presence v1 is an engagement estimate. It is not a full live battlefield truth system.

## 3. Scope For v1

Enemy Presence v1 includes:

- automatic activation near an active crate location
- War Mode-only operation
- local nameplate-based enemy player detection
- one snapshot of currently visible nameplates when scanning starts
- additive enemy estimate during the active scan window
- enemy class and healer classification from class plus primary power type
- local confidence calculation from self sighting plus distinct remote reporters
- group or raid sync between CrateRush users
- one-second outbound sync batching
- summary data suitable for a later UI

Enemy Presence v1 does not try to be perfectly current after the fight starts. It estimates what enemy force has been observed around the crate.

## 4. Out Of Scope For v1

The following are out of scope for v1:

- individual enemy removal on `NAME_PLATE_UNIT_REMOVED`
- death tracking
- stealth tracking
- enemy retreat tracking
- enemy health tracking
- combat-state tracking
- combat log analysis
- async inspect
- automatic fight recommendation
- historical enemy presence across crate cycles
- UI layout and rendering

These can be considered later if Enemy Presence v2 becomes a live battlefield tracker.

## 5. User Rules

Enemy Presence must be automatic. The player must not manually start or stop scanning.

Enemy Presence must be disabled by default.

Enemy Presence must be fully inactive when War Mode is off.

Enemy Presence must only scan when the player is near the active crate location for the current zone.

Enemy Presence must continue to announce or display estimates as estimates, not as guaranteed live truth.

Enemy Presence should produce a compact summary like:

```text
Enemies: 38
Healers: 12 - 16
  Priests: 3  Druids: 2  Monks: 1
  Possible: Shamans 2  Paladins 4  Evokers 2
```

Meaning:

- `Enemies` is the count of unique enemy player GUIDs observed during the active scan window.
- `Healers` is a range from confirmed healers to confirmed plus possible healers.
- confirmed healer classes are shown separately from possible healer classes
- possible healer classes add pressure context without pretending spec certainty

## 6. Domain Rules

Enemy Presence is based on enemy player GUID identity.

The same enemy GUID must count as one enemy, even if multiple CrateRush users report it.

Enemy Presence v1 is additive during the active scan window:

- newly observed enemies are added
- repeated observations update the entry
- individual disappearances do not remove enemies
- the whole table is wiped when scan context ends

An active scan window is also called an Enemy Presence detection cycle.

Enemy Presence detection cycle starts when scan becomes active near the current crate location.

Enemy Presence detection cycle ends when scan becomes inactive and runtime data is wiped.

An enemy entry is wiped only when:

- scan becomes inactive because the player leaves proximity radius
- player leaves the crate zone
- current crate lifecycle changes
- feature is turned off
- War Mode turns off
- player leaves group while sync is active

Confidence is local derived data. It is not transmitted.

Repeated messages from the same sender must not increase confidence. They only refresh that sender's report for that enemy.

Each locally observed enemy GUID may be broadcast only once per Enemy Presence detection cycle.

After the local client sends an enemy GUID in an `ENEMY_PRESENCE_REPORT`, that GUID is marked as broadcasted for the current detection cycle. Seeing the same enemy again in the same detection cycle must not queue another outbound report for that GUID.

When scan turns off and the detection cycle ends, the broadcasted GUID table is wiped with the rest of the runtime data.

Confidence levels:

```text
LOW
  I do not see the enemy.
  Exactly one remote source reported the enemy.

MEDIUM
  I see the enemy myself.
  OR I see the enemy and exactly one remote source also reported it.
  OR I do not see the enemy, but two remote sources reported it.

HIGH
  I see the enemy and two or more remote sources reported it.
  OR I do not see the enemy, but three or more remote sources reported it.
```

## 7. Data Model

Enemy Presence stores runtime state only.

The main table is keyed by enemy player GUID:

```lua
enemyPresence[enemyGUID] = {
    guid            = enemyGUID,
    classNum        = 1,
    healerBit       = 0,
    faction         = "Alliance",
    level           = 80,
    localSeen       = true,
    localLastSeen   = serverTime,
    remoteReporters = {
        [senderGUID] = {
            lastSeen  = serverTime,
            classNum  = 1,
            healerBit = 0,
        },
    },
}
```

A separate per-cycle table tracks which local enemy GUIDs were already sent:

```lua
broadcastedEnemyGUIDs[enemyGUID] = true
```

This table is runtime-only and is wiped when scan turns off.

Enemy player GUID is treated as a normal player GUID string for CrateRush purposes:

- it may be used as a Lua table key
- it may be transmitted through the existing CrateRush protocol encoding
- it is used as enemy identity
- it is not shown in normal UI output

Collected local fields:

```text
guid       = UnitGUID(unitToken)
class      = UnitClass(unitToken)
faction    = UnitFactionGroup(unitToken)
level      = UnitLevel(unitToken)
power1     = UnitPowerType(unitToken)
```

`UnitFactionGroup(unitToken)` here is for the observed unit only. Local player faction must come from player context, not from a feature-local `UnitFactionGroup("player")` call.

Class number encoding:

```text
1  = WARRIOR
2  = PALADIN
3  = HUNTER
4  = ROGUE
5  = PRIEST
6  = DEATHKNIGHT
7  = SHAMAN
8  = MAGE
9  = WARLOCK
10 = MONK
11 = DRUID
12 = DEMONHUNTER
13 = EVOKER
```

Healer bit encoding:

```text
0 = CONFIRMED_DPS
1 = CONFIRMED_HEALER
2 = POSSIBLE_HEALER
```

Role classification:

```text
WARRIOR      power1=RAGE          -> CONFIRMED_DPS
ROGUE        power1=ENERGY        -> CONFIRMED_DPS
HUNTER       power1=FOCUS         -> CONFIRMED_DPS
MAGE         power1=MANA          -> CONFIRMED_DPS
WARLOCK      power1=SOUL_SHARDS   -> CONFIRMED_DPS
DEATHKNIGHT  power1=RUNIC_POWER   -> CONFIRMED_DPS
DEMONHUNTER  power1=FURY          -> CONFIRMED_DPS

PRIEST       power1=INSANITY      -> CONFIRMED_DPS
PRIEST       power1=MANA          -> CONFIRMED_HEALER

DRUID        power1=ENERGY        -> CONFIRMED_DPS
DRUID        power1=RAGE          -> CONFIRMED_DPS
DRUID        power1=LUNAR_POWER   -> CONFIRMED_DPS
DRUID        power1=MANA          -> CONFIRMED_HEALER

MONK         power1=ENERGY        -> CONFIRMED_DPS
MONK         power1=MANA          -> CONFIRMED_HEALER

SHAMAN       power1=MAELSTROM     -> CONFIRMED_DPS
SHAMAN       power1=MANA          -> POSSIBLE_HEALER

PALADIN      power1=MANA          -> POSSIBLE_HEALER

EVOKER       power1=MANA          -> POSSIBLE_HEALER
```

These role rules are based on collected testing data and are accepted as the v1 classification contract.

Healer estimate:

```text
Total enemies     = count of unique enemy GUIDs
Confirmed healers = count of CONFIRMED_HEALER
Possible healers  = count of POSSIBLE_HEALER
Minimum healers   = confirmed healers
Maximum healers   = confirmed healers + possible healers
```

## 8. Activation And Lifecycle

Activation is driven by crate location and player proximity.

Lifecycle:

```text
Zone entered                       -> no scan
Plane flying, no drop location     -> no scan
Predicted drop location available  -> proximity watch starts
Real dropping location available   -> proximity watch starts or updates
Real landed location available     -> proximity watch starts or updates
Player enters proximity radius     -> scan active
Player leaves proximity radius     -> scan inactive and table wiped
```

Location priority:

```text
Real landed location
Real dropping location
Predicted drop location
```

If prediction exists first, it may drive proximity awareness.

Once a real dropping or landed location exists, the real location replaces prediction for the current lifecycle.

If prediction changes before a real location exists, the proximity target updates.

If no usable location exists, proximity watch does not start.

When scan becomes active, Enemy Presence immediately scans currently visible nameplates once. After that, it continues collecting enemies from nameplate-added events.

### 8.1 Proximity Check Mechanism

Enemy Presence uses a configurable proximity radius. The current default is 250 yards.

The feature module owns the proximity loop. UI may display scan state and warning state, but must not decide whether scanning is active.

Current v1 behavior:

- proximity is checked by the Enemy Presence module
- prediction location can start proximity watch before a real drop/landed location exists
- real dropping or landed location replaces prediction as the proximity target
- the radius config is active only when Enemy Presence is enabled
- Enemy Presence enablement controls both local contribution and receiving shared data
- there is no separate "share enemy presence" toggle in v1

This mechanism must live in the Enemy Presence feature service, not UI code. It must not create crate lifecycle, timer, guardian, shard, or prediction facts.

Primary WoW event:

```text
NAME_PLATE_UNIT_ADDED
```

Local filter:

```lua
if not UnitIsPlayer(unitToken) then return end
if not UnitIsEnemy("player", unitToken) then return end
```

`NAME_PLATE_UNIT_REMOVED` is not used to remove enemies in v1.

When scan turns off, Enemy Presence wipes all runtime data for the detection cycle:

- local enemy entries
- remote enemy reports
- reporter/confidence data
- pending sync batch
- already-broadcast GUID table
- active target location
- summary state

## 9. Integration With Existing CrateRush Systems

Enemy Presence integrates with:

- player context for War Mode state
- config gateway for feature toggle and radius
- crate lifecycle state for real dropping and landed location
- prediction state for predicted drop location
- group/protocol state for group token and sender validation
- domain events for summary publication

Enemy Presence must not change:

- crate lifecycle
- timer lifecycle
- guardian behavior
- shard confirmation
- prediction route selection

Enemy Presence consumes crate and prediction facts. It does not create crate facts.

## 10. Protocol And Sync

Enemy Presence sync is sent only between CrateRush users in the same party or raid.

There is no central aggregator.

Each client:

- scans what it can see
- sends local observations
- receives remote observations
- builds its own combined estimate

Message type:

```text
ENEMY_PRESENCE_REPORT
```

Send interval:

```text
1 second
```

Send condition:

```text
Send only if new local enemy data was collected since the last send.
Send only local enemy GUIDs that have not already been broadcast in this detection cycle.
```

After a sync batch is sent, all enemy GUIDs included in that batch are marked as broadcasted for the current detection cycle.

Sender validation:

```text
War Mode ON
Enemy Presence enabled
Player grouped
Valid group token
Scan active
Current zone known
Active drop shard known
Batch contains at least one enemy entry
```

Receiver validation:

```text
Valid group token
Sender GUID belongs to current group member
Message received via PARTY or RAID
War Mode ON
Grouped
Supported protocol version
Enemy Presence enabled
Scan active
Message zone matches current crate zone
Message shard matches active crate shard
```

Payload fields:

```text
v
type
senderGUID
groupToken
zoneID
shardID
entries
```

`entries` is one encoded list of enemy entries.

Decoded enemy entry format:

```text
g:<enemyGUID>,c:<classNum>,h:<healerBit>
```

Separators:

```text
entry separator = .
field separator = ,
key-value separator = :
```

Example decoded entries:

```text
g:Player-1,c:5,h:1.g:Player-2,c:2,h:2.g:Player-3,c:1,h:0
```

Enemy Presence protocol payloads must not use the vertical-bar character.

All values are encoded and decoded through the existing CrateRush protocol encoding contract.

Receiver behavior:

```text
If enemy GUID is new:
  create enemy entry.

If enemy GUID exists:
  update enemy entry.

If sender GUID has not reported this enemy before:
  add sender as distinct remote reporter.

If sender GUID already reported this enemy:
  refresh that sender's lastSeen time.
```

## 11. Architecture Placement

Enemy Presence must follow CrateRush architecture rules.

Input adapter:

```text
events.lua forwards nameplate and relevant game events.
```

Domain service:

```text
logic/enemyPresence.lua owns scan state, active target location, local enemy table,
remote reporter table, classification, and summary calculation.
```

Comms adapter:

```text
comms layer owns ENEMY_PRESENCE_REPORT encoding, batching, validation, sending,
receiving, and protocol version checks.
```

UI:

```text
future UI subscribes to Enemy Presence summary events and renders display only.
```

Enemy Presence service must not call:

```text
UI frames
timerbars
announce
SendChatMessage
storage directly
timer lifecycle services
crate lifecycle transition functions
```

Proposed domain events:

```text
ENEMY_PRESENCE_SCAN_STATE_CHANGED
ENEMY_PRESENCE_CHANGED
```

`ENEMY_PRESENCE_CHANGED` is published after the local summary changes.

The event data should contain summary values, not raw implementation tables.

## 12. Configuration

Planned config keys:

```text
enemyPresenceEnabled
enemyPresenceRadius
enemyPresenceSyncEnabled
```

Defaults:

```text
enemyPresenceEnabled = false
enemyPresenceSyncEnabled = true
enemyPresenceRadius = undecided
```

War Mode still overrides these settings. If War Mode is off, Enemy Presence is inactive.

## 13. Performance

Observed test data:

```text
Non-player nameplate events: 1-2 microseconds
Player nameplate events:     20-40 microseconds
Peak observed:               about 150 microseconds
Total addon CPU over 10 min: about 45ms with logging enabled
```

Production rules:

- no debug string building on each event
- no UI refresh on each nameplate event
- table writes only during event handling
- summary updates are batched
- outbound sync is batched
- outbound sync interval is 1 second

## 14. Known Limitations

Enemy Presence v1 is an engagement estimate, not live battlefield truth.

Enemies are not individually removed when nameplates disappear.

Deaths, stealth, retreat, phasing, combat state, and enemy health are not tracked.

Shadow Priest briefly out of Shadowform may be misclassified as healer.

Paladin spec cannot be determined from primary power alone. Paladins contribute to possible healer count.

Evoker spec cannot be determined from primary power alone. Evokers contribute to possible healer count.

Shaman with mana primary cannot be distinguished as Resto or Elemental. Enhancement Shaman with Maelstrom primary is confirmed DPS.

Secondary power type is not used in v1.

## 15. Implementation Phases

Phase 1: local scan domain service

- add feature toggle reads
- add War Mode guard
- add crate-location proximity watch
- add scan activation snapshot
- collect local enemy entries from visible nameplates
- calculate local-only summary

Phase 2: local summary event

- publish `ENEMY_PRESENCE_SCAN_STATE_CHANGED`
- publish `ENEMY_PRESENCE_CHANGED`
- expose summary without UI coupling

Phase 3: protocol and sync

- add `ENEMY_PRESENCE_REPORT`
- batch local changes every 1 second
- send each local enemy GUID only once per detection cycle
- validate sender and receiver context
- aggregate distinct remote reporters

Phase 4: UI

- render compact summary
- show confidence level
- show confirmed and possible healer breakdown

## 16. Acceptance Criteria

Enemy Presence v1 is complete when:

- feature is off by default
- feature does nothing when War Mode is off
- feature does not scan outside proximity radius
- scan activates near prediction, dropping, or landed location
- real dropping or landed location replaces prediction target
- scan activation snapshots already-visible nameplates
- local enemy player nameplates create enemy entries
- non-player nameplates are ignored
- friendly players are ignored
- same enemy GUID counts once
- same local enemy GUID is broadcast only once per detection cycle
- scan-off wipes local enemies, remote reports, pending sync, and broadcasted GUIDs
- same remote sender cannot increase confidence repeatedly
- distinct remote senders increase confidence as defined
- summary includes total enemies
- summary includes confirmed healer count
- summary includes possible healer range
- sync sends only while grouped and scan active
- sync batches at 1 second
- incoming sync is ignored when group token, zone, shard, War Mode, or feature state is invalid
- Enemy Presence does not call UI, chat, announce, timers, or crate lifecycle transition functions directly

## 17. Open Questions

```text
Decide whether future v2 should add removal, TTL, death, or combat-state tracking.
Tune proximity radius after live testing.
Tune nameplate-off warning behavior after live testing.
```
