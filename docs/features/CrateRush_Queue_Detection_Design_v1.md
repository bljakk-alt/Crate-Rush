# CrateRush Queue Detection Design v1

Status: Accepted baseline.

Controlling guideline: [CrateRush_Feature_Module_Guidelines.md](CrateRush_Feature_Module_Guidelines.md)

## 1. Purpose

Queue Detection is a CrateRush feature that detects when a party or raid member is queued for activities that may disturb crate shard stability.

The feature is based on the practical belief that group members queued for battleground or LFG content may cause shard changes or shard instability for the group. Queue Detection treats queueing as a risk condition, not as proven causation.

Queue Detection warns the player or group so the group can decide whether to remove, warn, or ask the queued member to leave queue.

## 2. Player Goal

The player goal is:

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
- broadcasting local queue risk to party or raid
- receiving queue-risk messages from RCT-compatible addons
- announcing queued group members through CrateRush output routing
- validating that sender belongs to the current group or raid
- configurable output cooldown
- default output cooldown of 120 seconds
- disabling queue detection behavior inside PvP instances

Queue Detection v1 is intentionally simple and compatible with the existing RCT queue message format.

## 4. Out Of Scope For v1

The following are out of scope for v1:

- preventing the player from queueing
- intercepting Blizzard queue signup buttons
- showing a confirmation dialog before queue signup
- detecting exact battleground name
- detecting exact dungeon, raid, or scenario name
- proving that queueing caused a shard change
- punishing or automatically removing queued members
- CrateRush-native queue protocol beyond RCT compatibility
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

Inbound RCT-compatible queue messages do not require a CrateRush group token, but the sender must be a current party or raid member.

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
        source         = "LOCAL" or "RCTQ",
    },
}
```

Alert throttle state:

```lua
lastQueueAlert = {
    [senderKey .. ":" .. queueType] = serverTime,
}
```

Sender identity should prefer player GUID when available.

For RCT-compatible messages, sender name may be the only available identity. In that case, the receiver must match the sender name against the current group roster before accepting the message.

## 8. Activation And Lifecycle

Queue Detection is active when:

```text
feature enabled
player grouped
not inside PvP instance
```

Zone policy:

```text
group-wide, not zone-bound
```

Queue Detection must not require the player to be in a crate allowed zone.

Queue Detection observes local queue state through WoW events:

```text
UPDATE_BATTLEFIELD_STATUS
LFG_UPDATE
```

Local battleground detection:

```lua
for i = 1, GetMaxBattlefieldID() do
    if GetBattlefieldStatus(i) == "queued" then
        -- BG queue risk
    end
end
```

Local LFG detection:

```lua
local mode = GetLFGMode()
if mode == "queued" then
    -- LFG queue risk
end
```

Queue Detection does not need crate lifecycle, timer lifecycle, or shard state to operate.

If the player leaves group, runtime queue state may be wiped.

## 9. Integration With Existing CrateRush Systems

Queue Detection integrates with:

- player/group context for grouped state
- group roster validation for inbound sender checks
- config gateway for enable state and cooldown
- announcement/output routing for user-facing messages
- comms layer for RCT-compatible messages

Feature event declarations:

```text
UPDATE_BATTLEFIELD_STATUS
LFG_UPDATE
GROUP_ROSTER_UPDATE
```

Feature-facing internal events:

```text
QUEUE_STATUS_SCAN_REQUESTED
QUEUE_RISK_DETECTED
```

Queue Detection must not change:

- crate lifecycle
- timer lifecycle
- guardian behavior
- shard confirmation
- prediction state
- Enemy Presence state

Queue Detection is an independent optional feature.

Queue Detection follows the feature-module rule:

```text
WoW queue events
  -> input adapter
  -> queue detection service
  -> queue-risk feature event
  -> output router and optional RCT-compatible comms
```

It must not be routed through crate allowed-zone filtering because queue risk is group-state bound, not crate-zone bound.

## 10. Protocol And Sync

Queue Detection v1 uses RCT-compatible addon-to-addon communication.

This is an explicit compatibility exception to the normal CrateRush group-token protocol.

Reason:

- queue risk is simple
- queue risk is useful across addons
- compatibility with RCT increases coverage
- RCT queue messages already exist and are easy to interoperate with

RCT-compatible prefix:

```text
RCTQ
```

Messages:

```text
QUEUED:BG
QUEUED:LFG
```

Channel:

```text
PARTY or RAID
```

Sender behavior:

```text
If local player is grouped and queued for BG:
  send RCTQ / QUEUED:BG

If local player is grouped and queued for LFG:
  send RCTQ / QUEUED:LFG
```

Receiver validation:

```text
message prefix is RCTQ
message is QUEUED:BG or QUEUED:LFG
sender is not local player
sender belongs to current party or raid
player is grouped
player is not inside PvP instance
feature is enabled
```

No CrateRush group token is required for `RCTQ`.

Queue Detection may later add a CrateRush-native queue message, but v1 does not require it.

## 11. Architecture Placement

Queue Detection must follow CrateRush architecture rules.

Input adapter:

```text
events.lua forwards UPDATE_BATTLEFIELD_STATUS and LFG_UPDATE to queue detection service.
comms layer forwards RCTQ queue messages to queue detection service after basic prefix dispatch.
```

Domain service:

```text
logic/queueDetection.lua owns local queue state, inbound queue risk state,
dedupe, cooldown decisions, and queue-risk domain events.
```

Comms adapter:

```text
comms layer owns RCTQ registration, sending, receiving, and channel selection.
```

Output adapter:

```text
announcement/output routing owns chat, warning frame, raid warning, party, or local output.
```

Queue Detection service must not call:

```text
SendChatMessage directly
UI frames directly
timer lifecycle services
crate lifecycle transition functions
shard services
prediction services
```

Proposed domain event:

```text
QUEUE_RISK_DETECTED
```

The event payload should contain:

```text
senderName
senderGUID if known
queueType
source
detectedAt
```

## 12. Configuration

Planned config keys:

```text
queueDetectionEnabled
queueDetectionAlertCooldownSeconds
queueDetectionSendRctCompatible
queueDetectionReceiveRctCompatible
```

Defaults:

```text
queueDetectionEnabled = true
queueDetectionAlertCooldownSeconds = 120
queueDetectionSendRctCompatible = true
queueDetectionReceiveRctCompatible = true
```

Pre-queue guard settings are not part of v1.

## 13. Performance

Queue Detection is lightweight.

Local checks run only on queue-related WoW events:

```text
UPDATE_BATTLEFIELD_STATUS
LFG_UPDATE
```

The feature does not poll.

The outbound message is a tiny fixed string.

The inbound message parser only accepts two known values:

```text
QUEUED:BG
QUEUED:LFG
```

User-facing output is cooldown-protected.

## 14. Known Limitations

Queue Detection v1 detects queue risk after the player has entered queue.

Queue Detection v1 does not prevent queue signup.

Queue Detection v1 does not identify exact queued content.

Queue Detection v1 does not prove queueing caused a shard change.

RCT-compatible messages use sender name identity. CrateRush should validate the sender against the current group roster before accepting the message.

Other players without CrateRush or RCT cannot be detected through addon comms unless their local client sends compatible messages.

## 15. Implementation Phases

Phase 1: local queue detection

- add queue detection service
- handle `UPDATE_BATTLEFIELD_STATUS`
- handle `LFG_UPDATE`
- detect local `BG`
- detect local `LFG`
- publish local queue-risk event

Phase 2: RCT-compatible comms

- register `RCTQ`
- send `QUEUED:BG`
- send `QUEUED:LFG`
- receive `QUEUED:BG`
- receive `QUEUED:LFG`
- validate sender belongs to current group

Phase 3: output routing

- route queue-risk event through CrateRush output layer
- apply 120-second default cooldown by sender and queue type
- avoid direct chat calls from queue detection service

Phase 4: future pre-queue guard research

- investigate safe Blizzard UI hooks
- determine whether queue signup can be warned before it happens
- document coverage and limitations before implementation

## 16. Acceptance Criteria

Queue Detection v1 is complete when:

- local BG queue state is detected
- local LFG queue state is detected
- local queued state sends RCT-compatible message when grouped
- inbound RCTQ `QUEUED:BG` is accepted from current group members
- inbound RCTQ `QUEUED:LFG` is accepted from current group members
- inbound RCTQ messages from non-group senders are ignored
- local player's own inbound echoed messages are ignored
- no behavior runs inside PvP instances
- user-facing output is throttled by sender and queue type
- default output cooldown is 120 seconds
- queue detection service does not call `SendChatMessage` directly
- queue detection service does not touch crate lifecycle, timer lifecycle, guardian, shard, or prediction state

## 17. Open Questions

Open questions before or during implementation:

```text
Should local player receive a private warning even before group output?
Should output go to warning frame, party, raid warning, default chat, or multiple sinks?
Should CrateRush later add a native queue message in addition to RCTQ?
Can pre-queue warning be implemented safely through Blizzard UI hooks?
```
