# CrateRush UI Design Spec v1

Status: Locked for first implementation. Fine tuning will happen live in addon.

Companion artifact:

```text
CrateRush_UI_Design_Map_v1.svg
```

## 1. Design Goals

- Keep the UI compact and readable during active gameplay.
- Use the left side for fast scanning of all zones.
- Use the right side for focused detail of the selected zone.
- Keep zone identity and warning state separate.
- Use a modern clean visual style on a dark semi-transparent background.
- Keep the UI as a renderer of prepared state, not an owner of crate/timer/domain logic.

## 2. Layout

### 2.1 Shared Header

- One shared header across the full UI width.
- Selected zone name sits left of center, shifted clearly toward the left border.
- Zone name uses the selected zone color.
- Header is taller than content rows.
- Right side of header contains the shard badge, settings icon, and close icon.

### 2.2 Left Panel, Zone List

Each zone row contains:

- top label: zone name + shard ID in brackets
- bottom element: horizontal timer bar
- right-aligned timer value
- thin colored lifecycle strip on the far left

Row rules:

- Keep current row height.
- Timer bars are thicker vertically than normal bars.
- Selected row gets a subtle border glow in zone color.
- Active lifecycle strip appears only when lifecycle is active, not simply because a timer exists.

### 2.3 Right Panel, Cockpit

Sections:

```text
State
Timing
Prediction
Enemy
Sync strip
```

### 2.4 Bottom Sync Strip

- Stays only inside the right panel footprint.
- Left-aligned leader name in leader class color.
- Right-aligned fixed text `Sync`, then the status dot on the far right.
- The dot color indicates active, rejected, or unavailable state.
- Do not include the status word in the text; preserve space for longer player/realm names.

## 3. Right Panel Content Behavior

### 3.1 State

The State box has two display modes.

Progress mode is used from accepted detection until landed:

```text
FLYING -> DROP -> LAND
```

- The default rail, labels, and circles are muted grey.
- When `DETECTED` is accepted, the `FLYING` circle and label use faction accent color.
- If prediction timing is available, the line from `FLYING` to `DROP` fills gradually toward the predicted drop time.
- If `DETECTED`/flying is active but no drop timing is available, the `FLYING` to `DROP` rail segment is dotted instead of animated solid.
- When `DROPPING` is accepted, the `DROP` circle and label use faction accent color, drop ETA disappears from Timing, and the line from `DROP` to `LAND` fills toward approximate landing time.
- If `DROPPING` is active but no land timing is available, the `DROP` to `LAND` rail segment is dotted instead of animated solid.
- When `LANDED` is accepted, progress mode ends.

Action mode replaces the progress rail:

- `LANDED`: left aligned `Landed`, right aligned `Open NOW` plus the configured action countdown.
- Fresh own-faction claim after directly observed `LANDED`: top label `Claimed`, full-row left content `by <Own Faction>`, and right-aligned loot countdown `Loot xx`; only the faction name is colored in its faction color.
- When the own-faction loot countdown expires, the State box content becomes empty/muted until the next lifecycle state.

Lost mode:

- Top label: `Claimed`
- Full-row left content: `by <Opposite Faction>`, with only the faction name colored in its faction color.
- This comes from prepared lifecycle state `CLAIMED_BY_OPPOSITE_FACTION`; UI must not infer it.

Idle mode:

- Left aligned: `Idle`
- Right aligned: `Waiting`
- Both values use muted text color.

### 3.2 Timing

Two columns:

- Drop
- Land

Rules:

- Values are shown beneath each label.
- If already passed, show `--:--` and grey them out.
- Once `DROPPING` is accepted, Drop is considered passed and must show placeholder.
- Once `LANDED` or claimed/lost is accepted, both Drop and Land are considered passed and must show placeholders.
- Loot timing is not a separate timing row; it belongs to State when lootable.

### 3.3 Prediction

Keep compact:

- coordinates
- confidence percentage

Example:

```text
46.2, 38.7
92%
```

Location name is not required in v1.

If prediction is unavailable, keep the section visible and show muted placeholder values.

### 3.4 Enemy

Keep simplified for v1.

Two fields:

- opposite faction total
- healers confirmed / possible

Example:

```text
Alliance        12-16
Healers         2 / 5
```

This example follows the locked two-column layout from section 13.4.

Do not include healer class breakdown in v1.

If Enemy Presence is unavailable, off, or not scanning, keep the section visible and show muted placeholder values.

## 4. Typography

Use a modern clean font style.

Do not use decorative fantasy text.

Hierarchy:

- Header zone name: large
- Row zone labels: medium large
- Row timers: medium large
- Right panel section labels: medium
- Right panel content values: medium, equal sizing across State, Timing, Prediction, and Enemy
- Helper text such as `confirmed / possible`: smaller muted text
- Bottom sync strip text stays as currently approved

## 5. Color System

### 5.1 Core Rule

- Zone colors represent identity.
- Warning colors represent urgency.
- Do not mix the two.

### 5.2 Locked Zone Colors

| Zone | Purpose | Hex |
|---|---|---|
| Zul'Aman | Zone identity | `#FF9800` |
| Harandar | Zone identity | `#73D63B` |
| Slayer's Rise | Zone identity | `#FF4F86` |
| Eversong Woods | Zone identity | `#22D9FF` |
| Voidstorm | Zone identity | `#8B4DFF` |

### 5.3 Neutral Colors

| Token | Hex | Usage |
|---|---|---|
| Primary text | `#FFFFFF` | Main readable text |
| Secondary text | `#B8C0CC` | Secondary values |
| Muted labels | `#8A93A3` | Section labels, helper text |
| Bar track | `#2A3442` | Inactive timer track |
| Border subtle | `#243040` | Subtle outlines |
| Background base | `#000000` | With 70 to 80% transparency |

### 5.4 Warning And Urgency Colors

| State | Hex | Usage |
|---|---|---|
| Normal | `#FFFFFF` | Default timer text |
| Warning | `#FFC247` | Configurable pre-warning threshold |
| Urgent | `#FF4D4D` | Configurable urgent threshold, may flash |

### 5.5 Shard Badge Colors

| Badge state | Hex |
|---|---|
| Confirmed | `#38D64A` |
| Scanning | `#F2C94C` |
| Mismatch | `#FF4D4F` |

## 6. Timer Text Rule

Default recommendation:

- Left timers: white
- Right timing values: white

Reason:

- Cleaner hierarchy.
- Stronger warning behavior.
- Zone colors stay reserved for identity.

Optional future setting:

```text
Use zone colored timer text
```

## 7. Behavioral Rules

### 7.1 Warning Thresholds

Configurable:

- Warning threshold, example less than 2 minutes.
- Urgent threshold, example less than 10 to 20 seconds.

Recommended behavior:

- Warning: row background/border uses amber warning treatment while timer text remains readable.
- Urgent: row background/border uses red warning treatment and may pulse while timer text remains readable.
- Selected/current rows must still show warning or urgent treatment; selection must not suppress urgency.
- Optional subtle pulse for urgent state.
- Avoid harsh full-row flashing in v1.

### 7.2 Selected Row

Selected zone row should show:

- zone-colored border glow
- stronger row emphasis than non-selected rows

### 7.3 Active Lifecycle Strip

Show on the far left of a row only when lifecycle is active.

Examples:

- flying
- drop
- landed
- claimed by my faction / lootable window
- claimed by opposite faction / lost

## 8. Shard Presentation

Shard ID should be associated with shard state, not split conceptually.

### 8.1 Header Badge Format

```text
Shard 11170 - Confirmed
Shard 11170 - Scanning
Shard 11170 - Mismatch
```

### 8.2 Row Format

- Zone list rows still keep `Zone Name [ShardId]`.
- This is useful for fast scanning.
- Header badge communicates status of the selected zone's current shard.

## 9. UI Data Contract

The UI consumes prepared display state.

The UI must not calculate:

- timer lifecycle
- crate lifecycle
- shard truth
- shard confirmation
- prediction route selection
- enemy presence counts
- sync authority

The UI may format and render values that are already prepared by domain services or UI adapter models.

UI adapter models may combine display facts and provide placeholders. They must not ask lifecycle, timer, shard, prediction, enemy, sync, comms, announcement, or storage services to decide truth.

Required display model shape:

```lua
uiModel = {
    selectedZoneID = 2395,
    selectedZoneName = "Eversong Woods",
    selectedZoneColor = "#22D9FF",

    shard = {
        id = "11170",
        status = "CONFIRMED", -- CONFIRMED, SCANNING, MISMATCH, UNKNOWN
        text = "Shard 11170 - Confirmed",
    },

    zoneRows = {
        {
            zoneID = 2395,
            zoneName = "Eversong Woods",
            shardID = "11170",
            zoneColor = "#22D9FF",
            selected = true,
            timerText = "03:12",
            timerPercent = 0.31,
            timerUrgency = "NORMAL", -- NORMAL, WARNING, URGENT
            lifecycleActive = true,
            lifecycleState = "LANDED",
        },
    },

    cockpit = {
        state = {
            label = "Lootable",
            value = "03:12 left",
            muted = false,
        },
        timing = {
            dropText = "--:--",
            dropMuted = true,
            landText = "--:--",
            landMuted = true,
        },
        prediction = {
            coordinatesText = "46.2, 38.7",
            confidenceText = "92%",
            available = true,
        },
        enemy = {
            factionLabel = "Alliance",
            totalText = "12-16",
            healerText = "2 / 5",
            helperText = "confirmed / possible",
            available = true,
        },
        sync = {
            leaderText = "Player-Realm",
            leaderClassColor = "#B366FF",
            statusText = "Sync",
            status = "ACTIVE", -- ACTIVE, REJECTED, UNAVAILABLE
        },
    },
}
```

The exact Lua structure can be refined during implementation, but these fields define ownership and responsibility.

## 10. Required Render States

The UI must handle:

- no timer
- timer active
- lifecycle active
- idle selected zone
- lootable
- lost to opposite faction
- shard confirmed
- shard scanning
- shard mismatch
- shard unknown
- prediction unavailable
- prediction available
- enemy data unavailable
- enemy data available
- sync active
- sync rejected
- sync unavailable

Render-state placeholders:

```text
Prediction unavailable: muted "--"
Enemy unavailable: muted "--"
No timer: muted "--:--"
Idle state: "Idle" / "Waiting"
```

## 11. Architecture Boundaries

UI renders state only.

UI must not call:

- timer lifecycle services for calculation
- crate lifecycle transition functions
- shard services for confirmation decisions
- prediction services for route decisions
- enemy presence services for raw aggregation
- comms services for protocol authority
- storage directly

Allowed UI responsibilities:

- render prepared state
- handle drag/positioning
- handle close/settings click
- publish UI intent events, if needed
- display selected zone
- request selected-zone changes, if zone selection becomes clickable

UI selection must not alter crate lifecycle or timer ownership.

## 12. Locked Implementation Direction

### 12.1 Left Side

- Zone label above timer bar.
- Thick timer bar.
- Right-aligned timer value.
- Selected row outline.
- Lifecycle strip only when active.

### 12.2 Right Side

- State.
- Timing in two columns.
- Prediction as coordinates + confidence.
- Enemy as total + healers.
- Bottom sync strip only inside right panel.

### 12.3 Header

- Shared full-width header.
- Zone name large and zone-colored.
- Shard badge right-aligned before settings.

## 13. Locked Clarifications

### 13.1 Header Spacing

The settings and close buttons must not sit directly on the outer border.

Minimum right padding:

- close button to outer panel edge: 18 px
- spacing between settings and close: 14 px
- spacing between shard badge and settings: 24 px

Live tuning may increase these values if the UI feels cramped.

### 13.2 Default Selected Zone

A zone is always selected.

Selection priority:

1. Active lifecycle zone, if one exists.
2. Next expiring timer.
3. Player current crate zone, if no timer exists.
4. First available configured crate zone as fallback.

The right cockpit panel should never be empty unless there is no zone data at all.

### 13.3 Enemy Faction Label

Enemy label is a prepared display value. The display adapter may derive it from player context or Enemy Presence output state, but renderers must not derive faction truth.

Rules:

- Alliance player sees `Horde`.
- Horde player sees `Alliance`.
- If no trustworthy player/enemy faction display value exists, show `Enemy`.

The UI does not decide faction and must not use theme fallback as faction truth.

### 13.4 Enemy Section Layout

Enemy section uses two columns with a vertical divider.

Left column:

- opposite faction label
- total range

Right column:

- `Healers`
- confirmed / possible count
- helper text `confirmed / possible`

This two-column layout is the locked visual layout.

### 13.5 Window Size And Resizing

v1 cockpit is fixed size.

Rules:

- Not resizable in v1.
- Movable if frames are unlocked.
- Clamped to screen.
- Minimum size equals designed size.

Future option:

- Compact mode may become a separate layout, not a manually resizable version of this cockpit.

## 14. Implementation Phases

Phase 1: shell and static layout

- create shared header
- create left zone rows
- create right cockpit sections
- create sync strip
- preserve current main UI visibility behavior

Phase 2: display model adapter

- create UI-facing display model
- keep timer/shard/lifecycle calculations outside UI
- render selected zone and row list from prepared state

Phase 3: state rendering

- render shard badge states
- render selected row
- render lifecycle strip
- render idle/lootable/timing/prediction/enemy states
- render sync states

Phase 4: live tuning

- tune WoW-scale font sizes
- tune spacing
- tune row height and bar thickness
- tune selected row glow
- tune warning/urgent behavior

## 15. Acceptance Criteria

UI v1 is complete when:

- selected row always matches right cockpit panel
- right cockpit is never empty when zone data exists
- active lifecycle strip appears only for active lifecycle
- timers remain white by default unless warning/urgent
- zone colors are used for identity
- warning colors are used for urgency
- shard badge shows shard ID and shard status together
- prediction unavailable state renders cleanly
- enemy unavailable state renders cleanly
- sync strip stays inside right panel footprint
- header buttons respect minimum spacing
- UI does not calculate timer lifecycle
- UI does not calculate shard truth
- UI does not calculate prediction route
- UI does not aggregate enemy presence
- UI text does not overlap at supported WoW UI scales
- main UI close behavior still prevents timer rows from appearing alone

## 16. Notes For Live Tuning

Expected live tweaks after first patch:

- exact padding and spacing
- font sizes in real WoW UI scale
- timer color default vs optional zone-colored mode
- selected row glow intensity
- right panel section spacing
- warning behavior intensity
