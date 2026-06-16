# RCT Addon Protocol Reverse Engineering

## Scope

This document describes the RCT addon-to-addon protocol layer only.

It covers:

```text
TOKEN_REQ
TOKEN~<token>
TOKEN_ACK~<token>
token lifetime
token broadcasts
token validation
```

It does not describe crate payload message behavior.

The token-protected message envelope is mentioned only because token validation is part of the protocol layer.

Excluded from this document:

```text
RCTUPD version checks
RCTQ queue messages
HGLOG1 log sharing
HELLO guild message
application payload meaning
```

Source inspected:

```text
_rct_extract/RCT/coms.lua
RCT addon version 12.0.4 from RCT.zip
```

## Prefix

Main RCT crate-sync prefix:

```text
RCT
```

RCT uses AceComm for transport.

## Core Protocol Idea

RCT uses a group token.

The token acts like a shared group session marker.

Normal protected messages must contain the current token.

If the receiver's local token check fails, the protected message is ignored.

There is no protocol message meaning:

```text
your token is wrong
your token expired
please refresh token
```

Token repair happens only through normal token request/update paths.

## Protocol Control Messages

### TOKEN_REQ

Meaning:

```text
Leader, send the group token.
```

Message:

```text
TOKEN_REQ
```

Sender:

```text
group member without a locally valid token
```

Receiver:

```text
current party or raid leader
```

Channel:

```text
PARTY or RAID
```

Important detail:

```text
TOKEN_REQ is not whispered to the leader.
It is sent to the group channel.
The leader sees it and responds.
```

### TOKEN

Meaning:

```text
Here is the group token.
```

Message:

```text
TOKEN~<token>
```

Sender:

```text
current party or raid leader
```

Receiver:

```text
all group members on PARTY or RAID
```

Channel:

```text
PARTY or RAID
```

When a member receives `TOKEN~<token>`, it accepts the token only if the sender is the current group leader.

If accepted, member stores:

```text
raidToken = <token>
raidTokenOwner = sender
raidTokenExpiry = now + 300 seconds
```

Then the member whispers `TOKEN_ACK~<token>` back to the leader.

### TOKEN_ACK

Meaning:

```text
I received the token.
```

Message:

```text
TOKEN_ACK~<token>
```

Sender:

```text
member that accepted TOKEN~<token>
```

Receiver:

```text
leader who sent TOKEN~<token>
```

Channel:

```text
WHISPER
```

Leader behavior:

```text
If ACK token matches leader's current token:
    secureRoster[sender] = true
```

Observed note:

```text
In the inspected paths, secureRoster is written by TOKEN_ACK handling.
No later authorization use was observed in the inspected protocol paths.
```

## Token Creation

Only the leader creates tokens in normal protocol flow.

Token creation:

```text
token = tostring(time()) .. tostring(math.random(100000, 999999))
expiry = GetServerTime() + 300
```

Constant:

```text
TOKEN_TTL = 300
```

Token expiry is local state.

`TOKEN~<token>` does not include an expiry timestamp.

Each receiver starts its own local 300 second lifetime when it accepts the token.

## Token Validity Check

Token validity is checked by local Lua code, not by a network message.

Local check:

```text
token exists
token equals local raidToken
local raidTokenExpiry exists
GetServerTime() is before raidTokenExpiry
```

There is no outgoing message for:

```text
is my token valid?
```

## Full Group TOKEN Broadcast Triggers

The leader broadcasts `TOKEN~<token>` to the whole party or raid in these cases.

### PLAYER_ENTERING_WORLD

WoW event:

```text
PLAYER_ENTERING_WORLD
```

Leader behavior:

```text
if grouped:
    if local token missing or expired:
        generate token
    if token exists and last broadcast was at least 3 seconds ago:
        broadcast TOKEN~<token> to PARTY or RAID
```

### GROUP_ROSTER_UPDATE

WoW event:

```text
GROUP_ROSTER_UPDATE
```

Leader behavior is the same as `PLAYER_ENTERING_WORLD`:

```text
if grouped:
    if local token missing or expired:
        generate token
    if token exists and last broadcast was at least 3 seconds ago:
        broadcast TOKEN~<token> to PARTY or RAID
```

Important detail:

```text
This broadcast path has a 3 second throttle.
Multiple roster/world events close together may not each broadcast.
```

### TOKEN_REQ Received By Leader

When leader receives:

```text
TOKEN_REQ
```

leader responds by broadcasting:

```text
TOKEN~<token>
```

to:

```text
PARTY or RAID
```

Important detail:

```text
One member can send TOKEN_REQ.
Leader response still goes to the entire group.
```

Implementation detail:

```text
OnTokenReq creates a token only if self.raidToken is missing.
It does not call HasValidRaidToken(self.raidToken) before responding.
```

## Member TOKEN_REQ Triggers

A member sends `TOKEN_REQ` when local code notices that the member has no valid token.

There is no automatic timer that sends `TOKEN_REQ` exactly when the token expires.

### PLAYER_ENTERING_WORLD or GROUP_ROSTER_UPDATE

On these events, a non-leader member does:

```text
if grouped:
    if local token missing or expired:
        send TOKEN_REQ to PARTY or RAID
```

This is the clean protocol repair path for members on group/world events.

### Local Send Attempt Before Protected Message

In the inspected send paths:

```text
crateSpotted()
```

checks for a valid token before attempting group send.

If member has no valid token, it sends:

```text
TOKEN_REQ
```

to:

```text
PARTY or RAID
```

This path has a local limiter:

```text
tokenRequestCount is reset after 180 seconds
implementation sends TOKEN_REQ while tokenRequestCount <= 2
```

### Wire_Send()

`Wire_Send()` also checks token validity before sending a protected message.

If token is invalid:

```text
leader:
    generate token
    return without sending original protected message

member:
    return without sending TOKEN_REQ
```

So `Wire_Send()` is a local validity gate, but it is not a member token request path.

## Receiving A Protected Message

Protocol envelope shape:

```text
<token>~<TAG>~<encodedPayload>~<sig>
```

This document does not define the application meaning of `<TAG>` or `<encodedPayload>`.

Receiver protocol validation:

```text
prefix must be RCT
sender must be in current party or raid
token must pass local HasValidRaidToken(token)
sig must be present
sig must equal Adler32(token .. encodedPayload)
```

If token check fails:

```text
message is ignored
no TOKEN_REQ is sent
no bad-token response is sent
```

## Leader And Member Role Summary

Leader:

```text
creates token
broadcasts TOKEN~<token> on PLAYER_ENTERING_WORLD / GROUP_ROSTER_UPDATE
responds to TOKEN_REQ by broadcasting TOKEN~<token> to group
receives TOKEN_ACK~<token>
```

Member:

```text
accepts TOKEN~<token> only from current leader
stores token locally for 300 seconds
whispers TOKEN_ACK~<token> to leader
sends TOKEN_REQ when group/world event or selected send path notices no valid local token
```

Raid assistant:

```text
not token authority in the inspected protocol paths
```

## Important Timing Consequence

Because expiry is local and not transmitted:

```text
leader and member can hold the same token value
but disagree about whether it is expired
```

Example:

```text
leader token has 10 seconds left
leader broadcasts TOKEN~ABC
member accepts ABC and starts local 300 second expiry
10 seconds pass
leader considers ABC expired
member still considers ABC valid
member sends protected message using ABC
leader drops message because local token check fails
member receives no protocol response
```

This is a consequence of:

```text
TOKEN~<token> does not include leader expiry
expiry is local
bad token has no response message
TOKEN_REQ is lazy, not automatic on expiry
```

## Protocol-Only Message List

For protocol/session management only:

```text
TOKEN_REQ
TOKEN~<token>
TOKEN_ACK~<token>
```

For protected message envelope only:

```text
<token>~<TAG>~<encodedPayload>~<sig>
```

Payload tags and payload behavior are outside the scope of this protocol document.
