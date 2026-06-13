# CrateRush UI Implementation Hard Rules

Status: locked handoff rules for UI implementation.

Purpose:

This document defines what a UI implementer must not touch, what must be strictly preserved, and how UI changes must stay inside the CrateRush architecture.

The UI may render prepared display state. The UI must not own gameplay truth.

## 1. Do Not Touch Core Systems

Do not edit or refactor any of these systems while implementing UI:

- crate lifecycle
- timer lifecycle
- guardian
- shard detection or shard confirmation
- zone allowance or zone bucketing
- prediction logic
- comms or addon-to-addon protocol
- announcements
- queue detection
- bounty detection
- enemy presence
- config logic
- storage or SavedVariables logic

Do not change:

- crate detection rules
- timer rollover or reset rules
- shard confirmation rules
- lifecycle acceptance rules
- addon-to-addon protocol rules
- announcement text
- announcement channels
- saved data format

If a UI change appears to require one of these changes, stop and ask for architecture approval first.

## 2. UI Must Only Render Prepared State

UI files may:

- place frames
- size frames
- color frames
- show or hide frames
- render labels
- render icons
- render progress bars
- render placeholders when data is unavailable
- route approved user commands through the UI action boundary

UI files must not:

- decide which shard is correct
- decide which timer is active
- decide crate lifecycle state
- reset a crate lifecycle
- reset a timer
- update shard truth
- calculate prediction truth
- calculate enemy presence truth
- calculate sync authority
- read or write SavedVariables directly
- search through core modules to invent missing display data

If data is missing, show a placeholder. Do not make the UI repair or infer backend truth.

## 3. No Hidden Domain Layer In UI

`ui/model.lua` is a display adapter only.

It may format and combine already available display facts.

It must not become a hidden domain layer.

It must not:

- own timer lifecycle logic
- own shard truth
- own crate lifecycle logic
- own prediction route selection
- own enemy confidence rules
- own comms authority
- write to storage

## 4. Allowed UI Work Area

Prefer touching only:

- `CrateRush/ui/frames.lua`
- `CrateRush/ui/timerbars.lua`
- `CrateRush/ui/cockpit.lua`
- `CrateRush/ui/theme.lua`
- `CrateRush/ui/layout.lua`
- `CrateRush/ui/model.lua`
- `CrateRush/ui/actions.lua`
- visual media under `CrateRush/Media`

Only touch `ui/model.lua` when a display-only field is missing.

Only touch `ui/actions.lua` when adding an approved UI command request.

Do not edit core files unless the architecture owner explicitly approves it first.

## 5. Preserve Existing UI Entry Points

Preserve:

- `/cr display`
- `/cr config`
- main frame show behavior
- main frame hide behavior
- close button behavior
- settings button behavior
- drag behavior
- header refresh behavior
- timer row refresh behavior
- timer row removal request behavior
- cockpit visibility behavior

Important:

- Closing the main UI must also hide timer rows and cockpit.
- Timer rows must not remain visible by themselves after the main UI is hidden.
- Shift-right-click timer removal must still route through `ui/actions.lua`.

## 6. Strict File Responsibilities

`ui/frames.lua`:

- owns the main UI shell
- owns the header shell
- owns show/hide behavior
- owns drag behavior
- renders prepared header display state

`ui/timerbars.lua`:

- renders prepared timer row display models
- must not own timer lifecycle rules
- must not directly remove timers
- must route removal requests through `ui/actions.lua`

`ui/cockpit.lua`:

- renders the right cockpit panel
- renders prepared cockpit display state from `ui/model.lua`
- must not query core services to decide truth

`ui/theme.lua`:

- owns visual color tokens
- owns theme tokens
- avoids duplicated colors in renderers

`ui/layout.lua`:

- owns visual sizes and spacing
- avoids duplicated dimensions in renderers

`ui/actions.lua`:

- routes UI command requests to approved boundaries
- must not perform domain decisions itself

## 7. No Duplicate Constants

Do not duplicate:

- colors
- panel sizes
- row heights
- icon sizes
- timing values
- zone IDs
- shard status values
- lifecycle state names
- timer constants
- protocol constants

Use existing central files.

If a needed constant does not exist, ask where it belongs before adding it.

## 8. Visual Rules

The UI should be:

- flat
- lean
- modern
- readable
- data-first
- stable while values update

Avoid:

- nested cards
- oversized decorative elements
- text overlap
- unstable row heights
- layout shifts during timer updates
- one-off colors inside renderer files
- visual effects that obscure information

Use stable dimensions for:

- header
- timer rows
- progress bars
- cockpit tiles
- icon buttons
- shard badges

## 9. Faction Theme Rules

Horde and Alliance themes are visual only.

Faction keys, names, and fallback are not owned by UI.

Faction resolution is owned by player context:

```text
override -> real player faction -> approved fallback
```

The resolved/effective faction is a no-fail value (`NO_FAIL_RETURN`). If real faction is unknown, player context returns the approved fallback, Horde.

UI consumes the resolved faction or prepared display values. UI code must not repair, replace, or re-fallback the faction value.

Faction theme may affect:

- colors
- textures
- icons
- decorative accents

Faction theme must not affect:

- crate detection
- shard detection
- timer logic
- announcements
- comms
- enemy logic
- storage truth

Only `ui/theme.lua` may declare faction-specific theme asset tables. Other UI files must not define, compare, default, or fallback Horde/Alliance values.

Forbidden outside `ui/theme.lua`:

- Horde/Alliance media fallback constants
- renderer-level Horde/Alliance branching
- display-adapter Horde/Alliance fallback
- config-dialog Horde/Alliance fallback text
- direct calls to `UnitFactionGroup`

`ui/theme.lua` maps a resolved faction key to theme media. It must not decide fallback faction.

## 10. Placeholder Rules

When a display value is unavailable, render a clear placeholder.

Examples:

- unknown shard
- unavailable prediction
- unavailable enemy count
- unavailable sync status
- missing map pin location

Do not suppress valid state announcements or valid state display just because optional details are missing.

## 11. Event And Refresh Rules

UI renderers may subscribe to approved display/domain events for refresh.

UI renderers must not:

- register new WoW gameplay events
- poll random domain modules during paint
- trigger lifecycle state changes
- trigger timer corrections
- trigger shard confirmations

Preferred flow:

```text
domain or UI event
  -> prepared display state
  -> render header
  -> render timer rows
  -> render cockpit
```

## 12. Acceptance Checks

After UI work, verify:

- addon loads without Lua errors
- `/reload` works
- `/cr display` works
- `/cr config` works
- main close button hides header, cockpit, and timer rows
- settings button still opens configuration
- main frame drag still works
- header zone, shard, and status still update
- timer rows still update
- timer rows do not appear while main UI is hidden
- no duplicate timers per zone are created by UI work
- shift-right-click timer removal still routes through UI actions
- crate detection still works
- timer lifecycle still works
- shard confirmation still works
- prediction announcements still work
- no core files were changed without explicit approval
- UI still renders prepared display state only

## 13. Stop Conditions

Stop and ask before continuing if:

- UI implementation requires changing core logic
- a renderer needs data that does not exist in prepared display state
- a visual change requires changing timer or lifecycle behavior
- a visual change requires changing announcement behavior
- an implementation would duplicate constants
- an implementation would add direct SavedVariables access to UI
- an implementation would register gameplay events inside UI files
