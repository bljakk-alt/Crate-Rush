# CrateRush 0.9.1 Release Tracker

Baseline release: `0.9.0`

Release date for baseline: `2026-06-14`

Purpose: track every meaningful fix or change made after `0.9.0`, so the next release notes are not reconstructed from memory.

## Fixed Since 0.9.0

- Main UI position now persists after dragging and reload/relog.
- Slow shard polling continues after the fast shard scan window ends.
- Pending crate cycle anchor is queued when the NPC announcement happens before shard confirmation.
- Pending crate cycle anchor is replayed after shard confirmation.
- Claimed-message placeholder timing was adjusted so `%time_to_loot%` and `%time_to_claim%` are available more reliably.
- Startup no longer crashes if the debug module is absent or disabled in the release package.
- Prediction route selection can lock earlier when one route angle is clearly better than the other candidates; strong angle second-route separation is configurable in Advanced and defaults to `> 1.85` degrees.
- Prediction strong-angle evidence now survives same-cell plane holds, so a clearly winning route can reach the 2-tick stability rule instead of resetting to `stable=1`.
- Flying confirmation at anchor was tightened after the false 2-tick anchor case.

## Changed Since 0.9.0

- Live build keeps debug logging and `/cr horde` / `/cr alliance` test switches.
- Working build keeps debug output disabled and removes faction override slash switches.
- Local sync script moved to `tools/` so it stays outside Git.
- Faction display names now resolve through locale keys, with canonical `HORDE` / `ALLIANCE` keys kept as logic truth.
- English zone names are now available from static map-ID data in addition to localized WoW client zone names.
- Announcement placeholders now include English display variants: `%zone_en%`, `%zone_english%`, `%state_en%`, `%claimed_by_faction_en%`, `%my_faction_en%`, and `%opposite_faction_en%`.
- User manual and architecture rules were updated to document localized and English announcement placeholders.
- Localization and English-placeholder implementation was synced into the live test addon without replacing live-only debug logging or `/cr horde` / `/cr alliance` switches.
- Prediction route lookup data is now generated from compact route polyline data instead of relying on sparse observed route cells or a simple start-to-drop line.
- Prediction design and architecture rules now require route cell data to be generated offline from ordered route points; runtime prediction remains table lookup only.
- Prediction data generator now supports the compact `zones[] -> routes[] -> routePoints[]` route-data format and generates centerline route cells by default.
- Prediction now survives raw subzone changes when the mapped crate zone stays the same, and ignores route matching from raw subzone coordinate space.

## Needs Verification

- Drag main UI, reload, and confirm the window restores to the dragged position.
- Confirm slow shard polling catches shard ID after the fast scan times out.
- Confirm NPC announcement before shard confirmation becomes a valid `CRATE_CYCLE_ANCHOR` once shard is confirmed.
- Confirm prediction route locks earlier in the previously slow route-match case.
- Confirm the Voidstorm early-route case no longer waits until late route cells before seeing route candidates.
- Confirm 3-tick anchor rule prevents the false flying detection seen with 2 ticks.
- Confirm message templates using `%zone_en%`, `%claimed_by_faction_en%`, `%my_faction_en%`, and `%opposite_faction_en%` render English text on a non-English client.
- Confirm the Eversong `EW_R03` / `EW_R04` / `EW_R05` early-route case no longer produces a single wrong route from sparse route-cell data.
- Confirm moving between Zul'Aman and Atal'Aman no longer clears an active Zul'Aman prediction, and raw Atal'Aman coordinates do not produce route matches.

## Known Issues / Watch List

- Working and live folders intentionally differ in debug/test-switch behavior.
- Enemy presence still needs broader live validation with nameplates enabled.
- Prediction can still be ambiguous when multiple route candidates remain valid; keep examples in `ambiguous.md`.
