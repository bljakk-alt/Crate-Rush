# CrateRush Release Fix Tracker

Baseline release: `0.9.4`

Purpose: track every meaningful fix or change made after `0.9.4`, so the next release notes are not reconstructed from memory.

## Fixed Since 0.9.4

- Prediction cockpit now shows the accepted confidence label when route data has no positive numeric confidence, instead of displaying `0%`.
- Prediction cockpit now prefers observed crate coordinates from DROPPING/LANDED/CLAIMED state and shows `100%` confidence once the location is observed.

## Changed Since 0.9.4

- Added hover tooltips for timer rows and cockpit tiles, previewing the configured Shift+Click announcement where available.
- Tooltips now appear at the cursor after a short delay, hide immediately on mouse leave, and omit Shift+Click instructions when the player is solo.
- Sync tooltip now shows the leader/player name using WoW class color.
- Shard badge now has a tooltip and supports Shift+Left click group announcement for the current zone shard.

## Needs Verification

- None yet.

## Known Issues / Watch List

- None yet.
