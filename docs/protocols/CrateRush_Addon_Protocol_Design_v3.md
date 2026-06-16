# CrateRush Addon to Addon Protocol Design

## 1. Purpose

The CrateRush addon to addon protocol exists to synchronise crate hunting information inside the currently active party or raid group.

The protocol is not an encryption system, anti hacker system, or protection against malicious players. Its purpose is practical group isolation and clean group coordination.

The protocol must prevent accidental contamination from old groups, old raids, stale sessions, wrong rosters, previous tokens, or unrelated crate hunting data.

CrateRush synchronisation is about group crate hunting coordination, not about broadcasting UI text or debug messages.

The leader keeps the authoritative group truth. Member state is a convenience copy. Members may help improve shared state when they have useful information, but the protocol must not depend on members having complete, current, or reliable state.

## 2. Design Principles

```text
Keep it simple.
Fail closed.
Leader owns protocol authority.
Leader keeps the authoritative group timer state.
Members follow leader controlled protocol state.
Member updates are helpful, not mandatory.
Leader updates to members are convenience sync, not required for leader truth.
No token means no sync.
War Mode must be active.
Only PARTY, RAID, and WHISPER are valid channels.
Use senderGUID for technical sender identity.
Do not use player or realm names for protocol logic.
Do not use message IDs in v1.
Do not use timestamps in the protocol envelope.
Do not use duplicate message caches in v1.
Do not use signatures or encryption.
Do not use fallback leaders.
Do not use AceSerializer for protocol payload format.
CrateRush owns its own message encoding and decoding.
No pipe character is used anywhere as protocol separator.
```

If the addon cannot clearly prove that a received message belongs to the current valid protocol context, the message is ignored.

## 3. Transport Layer

CrateRush uses addon to addon communication through the current addon communication transport layer.

The current implementation may use AceComm, but the protocol format must remain independent from AceComm or any other transport library.

The transport layer only sends and receives a CrateRush encoded string.

The addon prefix is fixed:

```text
CRATERUSH
```

Only the following channels are valid:

```text
PARTY
RAID
WHISPER
```

All other channels are excluded:

```text
GUILD
OFFICER
INSTANCE_CHAT
SAY
YELL
CHANNEL
BATTLEGROUND
```

Group wide communication uses `PARTY` or `RAID`.

One to one communication uses `WHISPER`.

## 4. CrateRush Message Encoding

CrateRush owns its own protocol encoding.

The protocol does not use AceSerializer.

The protocol does not use the pipe character as a separator.

The protocol payload is one CrateRush encoded string using key value fields.

Field separator:

```text
;
```

Key value separator:

```text
=
```

Example:

```text
v=1;type=TOKEN_UPDATE;senderGUID=<encodedSenderGUID>;token=<encodedToken>
```

Rules:

```text
; separates fields
= separates key and value
all values must be encoded before sending
all values must be decoded after parsing
```

CrateRush must provide its own encode and decode functions.

The encoding must ensure that separator characters inside values cannot break parsing.

At minimum, values must safely handle:

```text
;
=
.
,
:
%
spaces
special characters
future unexpected characters
```

### Nil Handling Contract

Nil handling is part of the protocol contract.

Rules:

```text
nil values are not transmitted.
missing key means nil or default.
empty string is transmitted as an encoded empty string.
zero is transmitted as value 0.
false is transmitted as value false.
```

This avoids ambiguity between:

```text
missing value
empty string
zero
false
```

No raw free text payload values are allowed without CrateRush encoding.

The exact implementation of `CrateRushEncode()` and `CrateRushDecode()` will be defined during implementation, but it must follow this contract.

## 5. Normal Sync Message Envelope

Normal CrateRush sync messages require a valid `groupToken`.

Required fields:

```text
v
type
senderGUID
groupToken
message specific fields
```

Example:

```text
v=1;type=TIMER_DELETE;senderGUID=<encodedSenderGUID>;groupToken=<encodedToken>;zoneId=<encodedZoneId>
```

Fields:

```text
v          = protocol format version
type       = message name
senderGUID = technical identity of the sending player
groupToken = current group session token
other keys = message specific fields
```

Initial protocol version:

```text
1
```

Messages with unsupported protocol versions are ignored.

## 6. Protocol Management Message Envelope

Protocol management messages establish or replace the group token.

They do not require an existing `groupToken`.

Required fields:

```text
v
type
senderGUID
message specific fields
```

Example:

```text
v=1;type=TOKEN_REQUEST;senderGUID=<encodedSenderGUID>
```

Protocol management messages:

```text
TOKEN_REQUEST
TOKEN_UPDATE
```

There is no:

```text
TOKEN_DELETE
messageId
timestamp
duplicate cache
groupToken requirement for token management messages
cached leaderGUID
full roster GUID cache
```

## 7. Sender Identity

The protocol uses `senderGUID` as technical sender identity.

Player names and realm names are not used for protocol logic because they can contain special characters, non Latin alphabets, spacing differences, casing differences, or localisation details.

Player name may be used for display or debug only.

```text
senderGUID = protocol identity
player name = display/debug only
```

Transport sender name is not protocol identity.

WoW addon communication delivers the transport sender as a name string. CrateRush may use that name only as a temporary lookup handle to find the matching current party or raid unit. The resolved `UnitGUID(unit)` must match the payload `senderGUID`. If the sender cannot be resolved to a current group unit, or if the resolved GUID differs from `senderGUID`, the message is ignored.

## 8. War Mode Requirement

War Mode is the first protocol condition.

If War Mode is off:

```text
protocol inactive
groupToken = nil
no token request
no token update
no sync messages
incoming protocol traffic ignored
```

CrateRush sync only works when War Mode is active.

## 9. Group Requirement

The protocol works only inside an active party or raid.

If the player is not grouped:

```text
protocol inactive
groupToken = nil
no token request
no token update
no sync messages
```

Valid group states:

```text
PARTY
RAID
```

## 10. Group Token

The group token identifies the current active CrateRush group session.

Its purpose is group session isolation.

It is not encryption.

The token prevents the addon from accepting messages from old groups, wrong raids, previous sessions, stale group state, or unrelated crate hunts.

Normal sync messages are accepted only if the incoming token matches the current local token.

## 11. Token Format

The group token is generated by the current WoW party or raid leader.

Token formula:

```text
groupToken = hash(leaderGUID .. ":" .. CrateRush.clock:serverTime() .. ":" .. math.random())
```

`math.random()` is included to improve uniqueness during quick reloads or rapid token recreation.

The token is still not security. It is a group session marker.

The exact hash implementation must be centralised in one Lua function.

All token creation must call that function.

No other code path may manually build group tokens.

Implementation contract:

```lua
function CrateRush.comms:CreateGroupToken()
    local leaderGUID = UnitGUID("player")
    local raw = tostring(leaderGUID) .. ":" .. tostring(CrateRush.clock:serverTime()) .. ":" .. tostring(math.random())
    return CrateRush.comms:HashToken(raw)
end
```

The final hash implementation will be decided during implementation.

## 12. Token Authority

Only the current World of Warcraft party or raid leader owns the token lifecycle.

The leader is the only authority allowed to:

```text
create token
replace token
broadcast token
respond with token
```

Members never create tokens.

Raid assistants do not create tokens.

There is no fallback coordinator.

There is no backup leader logic.

If the current group or raid leader does not have the addon, no valid token is created and group synchronisation remains inactive.

## 13. Token Lifecycle

There is no fixed token lifetime.

There is no expiry timer.

There is no periodic token refresh.

The token lives until replaced by a valid leader token update or wiped locally because the protocol context became invalid.

Rules:

```text
No fixed lifetime.
No expiry timer.
New leader token replaces old token.
Ordinary member join/leave does not replace the token.
No token means no sync.
```

There is only one local token variable.

Old tokens are not stored as valid alternatives.

## 14. Startup, Reload, and Entering World Behaviour

On addon start, reload, or entering world:

```text
if War Mode ON
and player is grouped in PARTY or RAID:
    wipe local groupToken

    if player is current party/raid leader:
        create new groupToken
        broadcast TOKEN_UPDATE

    else:
        send TOKEN_REQUEST to current leader
```

If War Mode is off, the protocol is inactive.

If the player is not grouped, the protocol is inactive.

## 15. Group Context Changes

The leader manages token replacement only when protocol authority changes.

Authority context changes include:

```text
player became grouped and is the current leader
leader changed and this player became the new leader
leader reloads or reconnects while grouped
```

When the current player is leader and detects an authority context change while War Mode is active, the leader creates a new token and broadcasts it through `TOKEN_UPDATE`.

Ordinary roster membership changes are not authority changes.

Examples of ordinary roster membership changes:

```text
member joined
member left
member rejoined
raid member changed subgroup
party converted to raid while leader stayed the same
raid converted to party while leader stayed the same
```

Ordinary roster membership changes do not create a new token.

Ordinary roster membership changes do not cause the leader to broadcast `TOKEN_UPDATE` to the group.

Members do not manage token lifecycle themselves.

Members do not wipe the token on roster change by themselves.

Members do not request a token on every roster change.

For existing non-leaders, `GROUP_ROSTER_UPDATE` is passive. It must not reset token request attempts, wipe an existing token, or send `TOKEN_REQUEST` just because another member joined or left.

If the local player changes from solo to grouped and is not leader, the player has no valid local group token for that group. The member may send `TOKEN_REQUEST` to the current leader if the request throttle and retry cap allow it.

If the current leader changes, members wipe the old local token because the old token belonged to the previous leader authority context.

After a leader change:

```text
new leader creates new groupToken
new leader broadcasts TOKEN_UPDATE to PARTY or RAID
members accept only if TOKEN_UPDATE senderGUID is the current leader GUID
```

Members keep the current token until a valid leader `TOKEN_UPDATE` replaces it, or until local state invalidates the protocol.

Token requests are capped per current group/leader request context.
After `TOKEN_REQUEST_MAX_ATTEMPTS` is reached, the member stops requesting and stops logging repeated max-attempt blocks until the protocol request context changes or a valid token update resets the request state.

## 16. Local Token Wipe Rules

Token deletion is local state logic.

There is no `TOKEN_DELETE` message in protocol version 1.

A client wipes its local token when:

```text
War Mode turns OFF
player is no longer grouped in PARTY or RAID
addon starts, reloads, or enters world while grouped before requesting or creating fresh token
```

After local token wipe:

```text
leader creates and broadcasts TOKEN_UPDATE if this player is the current leader
member sends TOKEN_REQUEST to leader if this player is not leader and needs a token
```

depending on player role.

## 17. Leader Without CrateRush

If the current WoW party or raid leader does not have CrateRush installed or active, `TOKEN_REQUEST` will not receive a `TOKEN_UPDATE` response.

This is intended behaviour in protocol version 1.

In this case:

```text
member sends TOKEN_REQUEST to current leader
leader does not answer because CrateRush is not available
member keeps groupToken = nil
protocol remains inactive
member does not send normal sync messages
no fallback leader is selected
no backup token authority is created
no user notification is shown in v1
```

The member treats this as:

```text
CrateRush group communication is not available in this group right now.
```

This follows the fail closed rule. If no valid leader controlled token is available, the addon does not attempt to synchronise.

## 18. TOKEN_REQUEST

### Purpose

`TOKEN_REQUEST` is sent by a non leader member who has no valid local token and needs the current leader to provide one.

It means:

```text
Leader, please send me the current group token.
```

### Sender

```text
Non leader member only
```

### Receiver

```text
Current WoW party or raid leader only
```

### Channel

```text
WHISPER
```

### Sender Conditions

A member may send `TOKEN_REQUEST` only when:

```text
War Mode ON
player is grouped in PARTY or RAID
player is not leader
local groupToken is missing
current leader can be resolved
```

Common send triggers:

```text
local player joins a party or raid and has no groupToken
addon starts, reloads, or enters world while grouped as non-leader and has no groupToken
before sending a normal sync message when local groupToken is missing
```

Ordinary roster updates caused by other members joining or leaving are not token request triggers for existing members.

### Receiver Validation

The leader accepts `TOKEN_REQUEST` only if:

```text
War Mode ON
receiver is grouped in PARTY or RAID
receiver is current WoW party or raid leader
message arrived via WHISPER
sender is not the leader
protocol version is supported
```

If valid, the leader replies with `TOKEN_UPDATE` via `WHISPER`.

If invalid, the request is ignored.

### Throttle and Retry

`TOKEN_REQUEST` must be throttled.

Rule:

```text
A member must not send TOKEN_REQUEST more than once every 10 seconds.
```

There is no automatic background retry loop.

However, lazy retry is allowed when the addon actually needs to send a normal sync message and has no token.

`GROUP_ROSTER_UPDATE` caused only by other members joining or leaving is not a lazy retry trigger for existing non-leaders.

Before sending a normal sync message:

```text
if local groupToken is missing:
    attempt TOKEN_REQUEST if throttle allows and retry cap is not reached
    do not send the original normal sync message
```

Retry cap:

```text
maximum 3 TOKEN_REQUEST attempts
```

The retry counter resets only when one of these explicit conditions happens:

```text
valid TOKEN_UPDATE is received
leader changes
group changes
player leaves group and joins another group
player leaves group and rejoins the same group
War Mode turns off and then on again
addon reloads or enters world again
```

After 3 failed attempts without receiving `TOKEN_UPDATE`:

```text
member treats CrateRush sync as unavailable for the current leader/group
member remains protocol inactive
member does not keep retrying
```

The 10 second throttle still applies to retry attempts.

## 19. TOKEN_UPDATE

### Purpose

`TOKEN_UPDATE` gives receivers the current active group token.

It means:

```text
Update your local groupToken to this token.
```

`TOKEN_UPDATE` contains the token value.

Example:

```text
v=1;type=TOKEN_UPDATE;senderGUID=<leaderGUID>;token=<groupToken>
```

It covers both cases:

```text
nil token → new token
old token → replacement token
```

### Sender

```text
Current WoW party or raid leader only
```

### Receiver

```text
One member via WHISPER
All group members via PARTY or RAID
```

### Channel

```text
WHISPER
PARTY
RAID
```

### Sender Behaviour

Leader sends `TOKEN_UPDATE` when:

```text
new token is created
token is replaced
valid TOKEN_REQUEST is received
leader authority changes
leader enters/reloads while War Mode ON and grouped
```

Leader does not broadcast `TOKEN_UPDATE` only because an ordinary member joined, left, or rejoined.

When a valid `TOKEN_REQUEST` is received, the leader replies with `TOKEN_UPDATE` via `WHISPER` to the requester.

When the local player becomes the new leader, the leader sends `TOKEN_UPDATE` via `PARTY` or `RAID` to the group.

### Fire and Forget

`TOKEN_UPDATE` is fire and forget.

It is a broadcast mechanism, not guaranteed delivery.

There is no acknowledgement.

There is no retry.

There is no forced synchronisation.

If a member misses `TOKEN_UPDATE`, only that member remains tokenless or stale.

The leader keeps the authoritative state.

A member who misses `TOKEN_UPDATE` remains protocol inactive until it later receives a valid `TOKEN_UPDATE` or triggers a valid `TOKEN_REQUEST` path.

### Receiver Validation

Receiver accepts `TOKEN_UPDATE` only if:

```text
War Mode ON
receiver is grouped in PARTY or RAID
message arrived via WHISPER, PARTY, or RAID
senderGUID belongs to the current WoW party or raid leader
protocol version is supported
```

The receiver resolves the current leader GUID on demand from current WoW group state.

The receiver does not cache `currentLeaderGUID` as protocol state.

The receiver does not maintain a full roster GUID cache for protocol validation.

If the sender is not the current leader, the message is ignored.

### Receiver Behaviour

If valid:

```text
local groupToken = received groupToken
```

The previous token is overwritten.

There is only one active local group token.

## 20. Normal Sync Message Validation

Normal CrateRush sync messages require a valid token.

Before processing normal sync message content, the receiver validates:

```text
prefix is CRATERUSH
channel is PARTY, RAID, or WHISPER
protocol version is supported
War Mode is ON
player is grouped
groupToken matches current local token
content is parseable for the given message type
```

If any check fails, the message is ignored.

## 21. Fail Closed Rule

The protocol fails closed.

That means:

```text
If something is missing, wrong, unsupported, unclear, or invalid, ignore the message.
```

Examples:

```text
wrong prefix → ignore
wrong channel → ignore
unsupported protocol version → ignore
missing token on normal sync message → ignore
wrong token → ignore
War Mode off → ignore
not grouped → ignore
malformed message → ignore
invalid sender authority → ignore
```

The protocol does not guess.

The protocol does not repair invalid messages.

The protocol does not accept uncertain data.

## 22. Core CrateRush Message Set

The currently defined core CrateRush messages are:

```text
TIMER_SYNC_REQUEST
TIMER_SYNC_RESPONSE
TIMER_DELETE
CRATE_CYCLE_ANCHOR
```

`TIMER_UPDATE` is intentionally not yet finalised and will be defined later together with timer and shard update rules.

Current implementation status:

```text
Implemented:
TOKEN_REQUEST
TOKEN_UPDATE
TIMER_SYNC_REQUEST
TIMER_SYNC_RESPONSE
TIMER_DELETE
CRATE_CYCLE_ANCHOR

Not implemented yet:
TIMER_UPDATE
```

## 23. TIMER_SYNC_REQUEST

### Purpose

A member asks the leader to send all currently known zone timers.

This is used for catch up after joining, reload, or missing local timer state.

### Sender

```text
Member only
```

### Receiver

```text
Leader only
```

### Channel

```text
WHISPER
```

### Requires groupToken

```text
yes
```

### Sender Behaviour

Member sends `TIMER_SYNC_REQUEST` when:

```text
War Mode ON
grouped
valid groupToken exists
player is not leader
member needs leader timer state
```

### Receiver Validation

Leader accepts only if:

```text
valid groupToken
War Mode ON
grouped
receiver is current leader
received via WHISPER
sender is not leader
protocol version is supported
```

If valid, leader replies with `TIMER_SYNC_RESPONSE`.

### Parameters

```text
v
type = TIMER_SYNC_REQUEST
senderGUID
groupToken
```

No zone specific request in v1.

The request means:

```text
send all known timers
```

### Throttle

`TIMER_SYNC_REQUEST` must be throttled.

Rule:

```text
A member must not send TIMER_SYNC_REQUEST more than once every 30 seconds.
```

## 24. TIMER_SYNC_RESPONSE

### Purpose

The leader sends all currently known timers to one requesting member.

### Sender

```text
Leader only
```

### Receiver

```text
Requesting member only
```

### Channel

```text
WHISPER
```

### Requires groupToken

```text
yes
```

### Sender Behaviour

Leader sends all known timers.

### Receiver Validation

Receiver accepts only if:

```text
valid groupToken
senderGUID belongs to current leader
received via WHISPER
War Mode ON
grouped
protocol version is supported
```

### Parameters

```text
v
type = TIMER_SYNC_RESPONSE
senderGUID
groupToken
timerList
```

`timerList` is a single encoded field value.

After decoding, `timerList` uses this internal structure:

```text
timerEntry.timerEntry.timerEntry
```

Each timer entry uses comma separated fields:

```text
zoneId:<zoneId>,shardId:<shardId>,nextTimerStart:<nextTimerStart>,dirty:false
```

Example decoded `timerList` value:

```text
zoneId:1,shardId:AAA,nextTimerStart:1000,dirty:false.zoneId:2,shardId:BBB,nextTimerStart:2000,dirty:false.zoneId:3,shardId:CCC,nextTimerStart:3000,dirty:false
```

Timer list separators:

```text
. separates timer entries
, separates fields inside one timer entry
: separates timer field key and value
```

All timer field values must still be CrateRush encoded and decoded.

No pipe character is used.

### Receiver Behaviour

Receiver applies the leader timer state as follows:

```text
replace local timers for all zones included in response
keep local timers for zones not included in response
mark kept local timers as dirty
```

Example:

```text
leader sends zones A, B, C
member has zones A, B, C, D

A, B, C are replaced by leader data
D is kept locally but marked dirty
```

Dirty means:

```text
local timer exists but is not confirmed by current leader sync
```

Dirty timers may remain visible to the local user, but they must be visually distinguishable, for example with a different colour.

Dirty timer lifecycle, cleanup, announcement behaviour, and resolution rules are not defined yet.

They will be defined in the `TIMER_UPDATE`, timer state, and shard state design section.

## 25. TIMER_DELETE

### Purpose

The leader removes a zone timer from group planning.

This is used when the group will not visit a zone, for example because multiple zone timers are too close together and the leader decides to skip one.

### Sender

```text
Leader only
```

### Receiver

```text
All group members
```

### Channel

```text
PARTY
RAID
```

### Requires groupToken

```text
yes
```

### Sender Behaviour

Leader sends `TIMER_DELETE` when deciding that the group should not use or visit a zone timer.

Implementation note:

```text
TIMER_DELETE is implemented as a protocol API.
It is not yet connected to a normal UI action.
```

### Receiver Validation

Receiver accepts only if:

```text
valid groupToken
senderGUID belongs to current leader
received via PARTY or RAID
War Mode ON
grouped
protocol version is supported
```

### Parameters

```text
v
type = TIMER_DELETE
senderGUID
groupToken
zoneId
```

### Receiver Behaviour

Receiver removes or disables the local timer for the given zone.

`TIMER_DELETE` is zone based, not shard based.

Meaning:

```text
The group will not visit this zone.
```

## 26. CRATE_CYCLE_ANCHOR

### Purpose

`CRATE_CYCLE_ANCHOR` is the hard crate cycle anchor event.

It is triggered locally by the WoW `MONSTER_SAY` event, but the protocol and internal business event name is:

```text
CRATE_CYCLE_ANCHOR
```

`MONSTER_SAY` is only the implementation source.

`CRATE_CYCLE_ANCHOR` is the business event.

### Sender

```text
Any group member with valid token
```

### Receiver

```text
All group members
```

### Channel

```text
PARTY
RAID
```

### Requires groupToken

```text
yes
```

### Sender Behaviour

When local addon detects `MONSTER_SAY`, it converts it into the internal business event:

```text
CRATE_CYCLE_ANCHOR
```

Then it broadcasts `CRATE_CYCLE_ANCHOR` to the group.

### Receiver Validation

Receiver accepts only if:

```text
valid groupToken
received via PARTY or RAID
War Mode ON
grouped
protocol version is supported
```

### Parameters

```text
v
type = CRATE_CYCLE_ANCHOR
senderGUID
groupToken
zoneId
shardId
serverEventTime
```

`serverEventTime` must use the same canonical time source the addon uses for crate timers.

The implementation must verify that this is server based and used consistently everywhere.

No local clock and no UI selected time source may be used for synced timer logic.

### Receiver Behaviour

When received, `CRATE_CYCLE_ANCHOR` must mimic a real local `CRATE_CYCLE_ANCHOR` event.

The receiver behaves as if it detected the event itself.

Receiver flow:

```text
validate protocol
convert remote message into internal CRATE_CYCLE_ANCHOR event
run the same code path as local detection
let existing timer logic decide what changes
```

Implementation note:

```text
The receiver calls the same crate lifecycle transition used by local NPC
announcements:

state = DETECTED
source = CRATE_CYCLE_ANCHOR
time = serverEventTime from the message

Remote anchors must not update current-zone header confirmation state directly.
```

There must not be a separate remote timer logic path.

The same business logic handles both sources:

```text
source = LOCAL_MONSTER_SAY
source = REMOTE_PROTOCOL
```

Important implementation condition:

```text
The receiver may not currently be in the same zone as the event.
```

Therefore, the internal event handler must support anchors received for another zone, store or update the relevant timer state, and apply it correctly when the player enters that zone later.

## 27. Explicit Non Goals

The following are intentionally excluded from protocol version 1:

```text
encryption
anti hacker protection
message signatures
sender timestamps
server timestamps in envelope
message IDs
duplicate message cache
token expiry timer
fallback leader
assistant ownership
manual protocol reset
manual sync button
custom channel communication
guild communication
instance chat communication
full roster GUID cache
cached leaderGUID
TOKEN_DELETE protocol management message
AceSerializer based payload format
pipe separated envelope
pipe character as protocol separator
```

## 28. Future Extension Point

This document currently defines:

```text
protocol layer
CrateRush owned message encoding
token management system
locked core messages except TIMER_UPDATE
```

The next design section will define:

```text
TIMER_UPDATE
timer identity
shard identity
timer and shard replacement rules
timer conflict handling
timer dirty state lifecycle
dirty timer display behaviour
dirty timer cleanup rules
dirty timer announcement behaviour
```

Future CrateRush extensions such as enemy presence are not part of this core protocol and will be designed separately.
