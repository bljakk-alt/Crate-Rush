# CrateRush UI v1 TODO

Status: current UI blockers only.

## Current Blockers

No current UI cleanup blockers are tracked here.

Visual tuning remains user-directed and should be handled in the live UI files without changing lifecycle, timer, shard, prediction, enemy, sync, config, comms, or storage truth.

## Boundary Rule

UI renders prepared display state only.

UI must not own timer, shard, lifecycle, prediction, enemy, sync, config, comms, or storage truth.
