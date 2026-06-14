# Prediction Ambiguity Parking Lot

## Current Decision

Leave the current prediction correction behavior as-is for now.

Prediction may:

- publish an initial drop prediction
- correct the active prediction if a later candidate points to a different drop location
- update the UI when the active prediction changes

## Observed Issue

In Zul'Aman, prediction can alternate between two plausible routes/drop locations, for example:

- `47.0/62.2`
- `49.0/69.3`

This means the prediction system is sometimes exposing route ambiguity as repeated prediction corrections.

## Important Distinction

Prediction correction itself is not currently considered wrong.

The problem to revisit later is whether correction should:

- stay UI-only
- be throttled for announcements
- require stronger stability before announcing
- suppress repeated A/B/A/B route flips
- show an "ambiguous" or "confirming" state instead of a committed prediction

## Do Not Change Yet

Do not change prediction locking, correction, or route selection behavior until we explicitly revisit this.

Do not touch crate lifecycle, timer lifecycle, shard confirmation, or guardian logic for this topic.

