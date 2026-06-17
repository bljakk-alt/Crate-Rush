# CrateRush Queue Detection Design v1

Status: Accepted baseline.

Controlling guideline: [CrateRush_Feature_Module_Guidelines.md](CrateRush_Feature_Module_Guidelines.md)

## 1. Purpose

Queue Detection is a CrateRush feature that detects when a party or raid member is queued for activities that may disturb crate shard stability.

The feature treats queueing as a risk condition, not as proven causation.

Queue Detection warns the player or group so the group can decide whether to remove, warn, or ask the queued member to leave queue.

## 2. Player Goal

```text
Tell me if someone in my crate group is queued for content that may disturb the crate shard.
```

For the local player, the longer-term product goal is:

```text
Warn me before I accidentally queue while I am in a crate group.
```

v1 focuses on detecting and sharing queue state after it happens. Pre-queue prevention is future work unless safe Blizzard UI hooks are confirmed.

## 3. Scope For v1

Queue Detection v1 includes:

- detecting local battleground queue state
- detecting local LFG queue state
- broadcasting local queue risk through CrateRush-native communication
- receiving CrateRush-native queue-risk messages
- announcing queued group members through CrateRush output routing
- validating that sender belongs to the current group or raid
- configurable output cooldown
- default output cooldown of 120 seconds
- disabling queue detection behavior inside PvP instances

Queue Detection v1 is intentionally simple and CrateRush-owned.

## 4. Out Of Scope For v1

The following are out of scope for v1:

- preventing the player from queueing
- intercepting Blizzard queue signup buttons
- showing a confirmation dialog before queue signup
- detecting exact battleground name
- detecting exact dungeon, raid, or scenario name
- proving that queueing caused a shard change
- punishing or automatically removing queued members
- third-party addon protocol compatibility
- historical queue behavior tracking

## 5. User Rules

Queue Detection must warn about queue risk, not claim certainty.

Recommended wording should communicate risk:

```text
<player> is in queue (BG). This may disturb crate shard stability.
<player> is in queue (LFG). This may disturb crate shard stability.
```

Queue Detection must not spam the group.

The same player and same queue type should not produce another user-facing alert until the cooldown expires.

Default cooldown:

```text
120 seconds
```

Queue Detection should be active only while grouped.

Queue Detection should be disabled inside PvP instances.

Queue Detection should prefer informing the group leader or group, not silently hiding risk.

## 6. Domain Rules

Queue Detection recognizes queue states:

```text
BG
LFG
```

BG means the player is queued for battleground-style content detected through battlefield queue status.

LFG means the player is queued through LFG mode.

Queue Detection treats queue state as a risk signal.

Queue Detection does not attempt to determine whether shard instability actually occurred.

Queue Detection de-duplicates alerts by:

```text
sender identity + queue type
```

Output cooldown is applied to user-facing alerts, not to the internal fact that queue state was detected.

Inbound messages require CrateRush-native protocol validation and current group membership validation.

## 7. Data Model

Queue Detection runtime state:

```lua
queueRiskBySender = {
    [senderKey] = {
        senderName     = "Player",
        senderGUID     = "Player-...",
        queueType      = "BG",
        firstSeenAt    = serverTime,
        lastSeenAt     = serverTime,
        lastAlertAt    = serverTime,
        source         = "LOCAL" or "CRATERUSH",
    },
}
```

Alert throttle state:

```lua
lastQueueAlert = {
    [senderKey .. ":" .. queueType] = serverTime,
}
```

## 8. Required Events

Queue Detection may request these WoW events through the CrateRush event boundary:

- `UPDATE_BATTLEFIELD_STATUS`
- `LFG_UPDATE`
- `GROUP_ROSTER_UPDATE`
- `PLAYER_ENTERING_WORLD`

The module must not own core event dispatch. It receives events through CrateRush-owned event routing.

## 9. CrateRush Event Flow

```text
WoW queue event
  -> CrateRush event boundary
  -> Queue Detection module
  -> queue-risk state
  -> CrateRush-native communication
  -> announcement router
```

Inbound communication:

```text
CrateRush comms
  -> protocol decode and validation
  -> Queue Detection module
  -> queue-risk state
  -> announcement router
```

## 10. Communication

Queue Detection v1 uses CrateRush-native addon-to-addon communication only.

Messages must use the normal CrateRush protocol validation path.

Sender identity must be validated against the current group roster before accepting a queue-risk message.

## 11. Configuration

Planned settings:

```lua
queueDetectionEnabled = true
queueDetectionCooldownSeconds = 120
queueDetectionBroadcastEnabled = true
queueDetectionAnnounceEnabled = true
```

## 12. Acceptance Checks

- local BG queue state creates one queue-risk observation
- local LFG queue state creates one queue-risk observation
- local queue state broadcasts only while grouped
- inbound queue message from current group member is accepted
- inbound queue message from non-group sender is ignored
- repeated same sender and queue type is throttled for 120 seconds by default
- feature is inactive inside PvP instances
- no crate lifecycle, timer lifecycle, guardian, shard, or prediction state is changed

## 13. Implementation Notes

Queue Detection must live outside core crate logic.

It may publish feature-level events or route announcements, but it must not mutate crate lifecycle, timer, shard, prediction, or current-zone truth.

Any future third-party compatibility requires explicit design approval before implementation.
