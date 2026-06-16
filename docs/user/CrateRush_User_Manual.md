# CrateRush User Manual

This manual describes how to use CrateRush, how announcements work, and how to customize message templates.

CrateRush tracks War Supply Crates in supported War Within crate zones. It watches crate lifecycle events, shard information, timers, prediction data, and enemy presence, then displays the useful hunting information in the main UI and optional announcements.

---

# Quick Start

1. Enable the addon.
2. Enter War Mode if CrateRush is configured to run only in War Mode.
3. Use `/cr display` to show or hide the main UI.
4. Use `/cr config` to open the configuration window.
5. Watch the zone timers and selected-zone cockpit.
6. Use Shift + Left Click on supported UI tiles to manually announce useful information.

---

# Slash Commands

| Command | Description |
|---|---|
| `/cr config` | Opens the configuration window. |
| `/cr display` | Shows or hides the main display. |
| `/cr debug` | Opens the debug window. Intended for testing and troubleshooting. |
| `/cr auto` | Returns faction theme detection to automatic mode. |

Development or live-test builds may also include faction override commands:

| Command | Description |
|---|---|
| `/cr horde` | Forces Horde visual theme for testing. |
| `/cr alliance` | Forces Alliance visual theme for testing. |

These faction override commands are visual/testing helpers and should not be used as gameplay truth.

---

# Main UI

The main UI is split into two parts:

- Zone timer list
- Selected-zone cockpit

## Zone Timer List

The left side lists crate zones and their next known timer.

Each row may show:

- zone name
- shard ID
- time until expected next crate cycle
- timer progress bar
- unseen cycle count
- zone color strip

If no usable timer exists for a zone, the row shows `NO DATA`.

## Selected-Zone Cockpit

The right side shows detailed information for the selected or current zone:

- State
- Timing
- Prediction
- Enemy
- Sync

The cockpit is display-only. It renders information already prepared by CrateRush logic.

---

# Crate States

CrateRush uses these crate lifecycle states:

| State | Meaning |
|---|---|
| Flying / Detected | The crate cycle has started and the plane is active. |
| Dropping | The crate is falling. |
| Landed | The crate is on the ground and should be opened quickly. |
| Claimed by my faction | The crate is lootable by you for a short time. |
| Claimed by opposite faction | The crate is no longer useful to you. |

Only directly observed states are treated as real. If the first observed state is dropping, landed, or claimed, CrateRush implicitly creates the detected state first, then records the observed state.

---

# Manual UI Announcements

Manual UI announcements are triggered with Shift + Left Click.

Manual announcements use the same message templates as configured announcements, but they are user-triggered. They may send to party or raid based on group state and do not use Raid Warning.

| UI Element | Action |
|---|---|
| Timer row | Shift + Left Click announces the upcoming crate timer using the `Upcoming Crate` message. |
| Prediction tile | Shift + Left Click announces the prediction using the `Prediction` message. |
| Timing tile | Shift + Left Click announces the prediction/timing using the `Prediction` message. |
| State tile | Shift + Left Click repeats the relevant state message for the current state. |
| Enemy tile | Shift + Left Click announces enemy presence using the `Enemy Presence` message. |

Prediction tile also supports:

| UI Element | Action |
|---|---|
| Prediction tile | Shift + Right Click sets or opens the map pin if prediction location is available. |

---

# Automatic Announcements

Automatic announcements are triggered by crate events, prediction events, timer thresholds, shard changes, and enemy presence depending on configuration.

Automatic group messages are authority-aware:

- In raid, automatic raid output should require raid authority where configured.
- In party, automatic party output follows the configured message rules.
- Manual Shift + Click output is intentionally separate from automatic leader-gated output.

---

# Notification Configuration

Open configuration with:

```text
/cr config
```

The Notifications tab contains configurable message rows.

Each message row may have:

- enabled checkbox
- output targets
- threshold seconds for timer-based messages
- message template

Common output targets:

| Output | Description |
|---|---|
| Chat Frame | Echoes the message locally into your default chat frame. |
| Notification | Sends the message to the local notification/warning display. |
| Party/Raid | Sends to group chat when allowed. |
| Raid Warning | Sends raid warning when allowed and when the player has authority. |

The default chat frame echo uses a faction-colored `CrateRush` prefix without a colon.

---

# Configurable Messages

## Crate Detected

Default template:

```text
War Supply Crate detected flying in %zone% [shard %shard%]
```

Used when a crate cycle is accepted as detected/flying.

## Crate Dropping

Default template:

```text
War Supply Crate dropping in %zone% [shard %shard%] at %coords% %map_pin%
```

Used when a dropping crate is accepted.

## Crate Landed

Default template:

```text
War Supply Crate LANDED in %zone% [shard %shard%] - GO NOW! at %coords% %map_pin%
```

Used when a landed crate is accepted.

## Crate Claimed

Default template:

```text
War Supply Crate claimed by %claimed_by_faction% in %zone% [shard %shard%]%if_claimed_by_my_faction% lootable %time_to_loot%%endif%
```

Used when a crate is claimed.

If your faction claimed it, the loot timer text is included. If the opposite faction claimed it, the loot text is removed.

## Prediction

Default template:

```text
Predicted drop in %zone%%if_location_available% at %coords% %map_pin%%endif%%if_time_to_drop% drop %time_to_drop%%endif%%if_time_to_land% land %time_to_land%%endif%
```

Used when CrateRush has a usable prediction and when Shift + Left Click is used on the Prediction or Timing tile.

## Enemy Presence

Default template:

```text
Enemy presence in %zone%: %enemy_total% enemies, %healers% healers
```

`%healers%` is a subset of `%enemy_total%`.

Enemy presence counts visible enemy players detected near the active/predicted crate area. During an active detection cycle, counts are intended to increase as more enemies are seen.

## Upcoming Crate

Default template:

```text
Next Crate in %zone% in %time_to_next%
```

Used for timer-based upcoming crate announcements and Shift + Left Click on timer rows.

This message has a configurable threshold in seconds.

## Shard Changed

Default template:

```text
Shard changed in %zone%: old %old_shard%, new %new_shard%
```

Used when CrateRush detects a shard change for a zone.

---

# Placeholders

Placeholders are replaced when a message is built.

Use placeholders exactly as written, including `%`.

## Zone And Shard

| Placeholder | Meaning | Example |
|---|---|---|
| `%zone%` | Crate zone name from the WoW client locale. | `Eversong Woods` |
| `%zone_en%` | English crate zone name. | `Eversong Woods` |
| `%zone_english%` | Alias for `%zone_en%`. | `Eversong Woods` |
| `%shard%` | Current shard ID. | `5277` |
| `%old_shard%` | Previous shard ID for shard-change messages. | `12012` |
| `%new_shard%` | New shard ID for shard-change messages. | `5277` |

## State

| Placeholder | Meaning | Example |
|---|---|---|
| `%state%` | Human-readable crate state. | `landed`, `lootable`, `dropping` |
| `%state_en%` | English crate state. | `landed`, `lootable`, `dropping` |
| `%claimed_by_faction%` | Localized faction that claimed the crate. | `Horde`, `Alliance` |
| `%claimed_by_faction_en%` | English faction that claimed the crate. | `Horde`, `Alliance` |
| `%my_faction%` | Your localized resolved faction. | `Horde` |
| `%my_faction_en%` | Your resolved faction in English. | `Horde` |
| `%opposite_faction%` | Localized opposite faction from your resolved faction. | `Alliance` |
| `%opposite_faction_en%` | Opposite faction in English. | `Alliance` |

## Location

| Placeholder | Meaning | Example |
|---|---|---|
| `%coords%` | Compact crate coordinates. | `45.1/63.0` |
| `%map_pin%` | Clickable Blizzard map pin link. | `[Map Pin Location]` |

Preferred placeholders are `%coords%` and `%map_pin%`.

Compatibility aliases may exist internally, but new templates should use the preferred names above.

## Time

| Placeholder | Meaning | Example |
|---|---|---|
| `%time_to_next%` | Time until next expected crate cycle. | `30s`, `1m12s` |
| `%time_to_drop%` | Approximate time until predicted drop. | `~45s` |
| `%time_to_land%` | Approximate time until predicted landing. | `~2m20s` |
| `%time_to_claim%` | Approximate action window after landed state. | `4m58s` |
| `%time_to_loot%` | Loot window after your faction claims the crate. | `58s` |

Prediction times are approximate.

## Enemy Presence

| Placeholder | Meaning | Example |
|---|---|---|
| `%enemy_total%` | Total detected enemy presence. | `12-16` |
| `%healers%` | Detected healer count or healer range. This is part of total. | `2/5`, `6+2` |

---

# Conditional Blocks

Conditional blocks include or remove a part of a message.

Syntax:

```text
%if_condition_name%text to include%endif%
```

Conditional blocks should not be nested.

## Available Conditions

| Condition | Included when |
|---|---|
| `%if_claimed_by_my_faction%...%endif%` | `%claimed_by_faction%` matches your faction. |
| `%if_claimed_by_opposite_faction%...%endif%` | `%claimed_by_faction%` matches the opposite faction. |
| `%if_location_available%...%endif%` | `%coords%` is available. |
| `%if_time_to_drop%...%endif%` | `%time_to_drop%` is available. |
| `%if_time_to_land%...%endif%` | `%time_to_land%` is available. |

There is intentionally no `%if_time_to_next%` condition.

---

# Placeholder Examples

## Claimed By My Faction

Template:

```text
War Supply Crate claimed by %claimed_by_faction% in %zone%%if_claimed_by_my_faction% lootable %time_to_loot%%endif%
```

If Horde is your faction and Horde claimed it:

```text
War Supply Crate claimed by Horde in Eversong Woods lootable 58s
```

If Alliance claimed it:

```text
War Supply Crate claimed by Alliance in Eversong Woods
```

## Claimed By Opposite Faction

Template:

```text
War Supply Crate claimed by %claimed_by_faction% in %zone%%if_claimed_by_opposite_faction% - lost%endif%
```

Output when the opposite faction claimed it:

```text
War Supply Crate claimed by Alliance in Eversong Woods - lost
```

## Prediction With Optional Location And Times

Template:

```text
Predicted drop in %zone%%if_location_available% at %coords% %map_pin%%endif%%if_time_to_drop% drop %time_to_drop%%endif%%if_time_to_land% land %time_to_land%%endif%
```

Output with full data:

```text
Predicted drop in Slayer's Rise at 45.4/62.8 [Map Pin Location] drop ~54s land ~2m20s
```

Output without location:

```text
Predicted drop in Slayer's Rise drop ~54s land ~2m20s
```

## Enemy Presence

Template:

```text
Enemy presence in %zone%: %enemy_total% enemies, %healers% healers
```

Output:

```text
Enemy presence in Zul'Aman: 12-16 enemies, 2/5 healers
```

---

# Chat Template Rules

Avoid the pipe character in chat message templates:

```text
|
```

World of Warcraft chat links and `SendChatMessage` handling are sensitive to pipe characters. Use commas, dashes, or normal words instead.

Recommended:

```text
Predicted drop in %zone% at %coords% %map_pin% drop %time_to_drop% land %time_to_land%
```

Avoid:

```text
Predicted drop in %zone% at %coords% %map_pin% | drop %time_to_drop% | land %time_to_land%
```

Keep party/raid messages compact. Long messages can wrap badly or lose readability during crate hunting.

---

# Map Pins

`%map_pin%` creates a clickable Blizzard map pin link when location data is available.

Map pins are useful in:

- Dropping messages
- Landed messages
- Prediction messages
- Manual prediction/timing announcements

If no valid coordinates are available, `%map_pin%` becomes empty.

---

# Enemy Presence Notes

Enemy Presence estimates visible enemy pressure near the crate area.

Important notes:

- It depends on nameplate visibility.
- If enemy nameplates are disabled, CrateRush cannot reliably scan enemies.
- Healer count is part of total enemy count.
- During a detection cycle, seen enemies are accumulated rather than treated as a perfect live combat roster.

This feature is intended to help decide whether a crate fight is worth taking. It is not a full battleground-style truth source.

---

# Troubleshooting

## I do not see timers

Possible reasons:

- The zone has no stored timer yet.
- The timer expired and was removed after too many unseen cycles.
- You are not in a supported crate zone.
- CrateRush has not observed a useful crate state for that zone/shard yet.

## I do not see prediction

Possible reasons:

- The plane route is still ambiguous.
- CrateRush does not yet have route data for that path.
- The crate has already dropped, landed, or been claimed.
- Shard/zone confirmation was not ready when the event arrived.

## I do not see enemy counts

Possible reasons:

- Enemy Presence is disabled.
- Enemy nameplates are disabled.
- You are outside the configured enemy scan radius.
- No enemies have been detected during the current cycle.

## My custom message did not show map pin

Check:

- Your template includes `%map_pin%`.
- Location is available.
- The message is for an event that has coordinates or prediction data.

## My conditional text disappeared

The condition was false or the required data was unavailable.

Example:

```text
%if_location_available% at %coords% %map_pin%%endif%
```

This block disappears when coordinates are missing.
