# CrateRush Documentation

Welcome to the central documentation hub for CrateRush.

This documentation defines the architecture, contracts, protocols, UI rules, feature modules, and development guidelines that govern the project.

---

# Reading Order

New contributors should read the following documents before making changes:

1. [Architecture Rules](architecture/CrateRush_Architecture_Rules_v5.md)
2. [Lifecycle & Timer Contract](architecture/Lifecycle_Timer_Contract.md)
3. [Crate Timer Guardian Logic](architecture/Crate_Timer_Guardian_Logic.md)
4. [Addon Protocol Design](protocols/CrateRush_Addon_Protocol_Design_v3.md)
5. [UI Implementation Hard Rules](ui/CrateRush_UI_Implementation_Hard_Rules.md)
6. [Feature Module Guidelines](features/CrateRush_Feature_Module_Guidelines.md)

These documents form the core project contract.

---

# Documentation Map

```text
Architecture
├── Architecture Rules
├── Lifecycle & Timer Contract
└── Crate Timer Guardian Logic

Protocols
└── Addon Synchronisation Protocol

UI
├── UI Design
├── Configuration UI
└── UI Implementation Rules

Features
├── Prediction
├── Enemy Presence
├── Queue Detection
├── Bounty Detection
└── Feature Module Guidelines

Project
├── TODO
├── UI TODO
└── Ambiguity Parking Lot
```

---

# Architecture

## Architecture Rules

Defines:

- System architecture
- Ownership boundaries
- Allowed dependencies
- Runtime invariants
- Development rules

Documents:

- [Architecture Rules](architecture/CrateRush_Architecture_Rules_v5.md)
- [Architecture Diagram](architecture/craterush_architecture_v5.svg)

---

## Lifecycle, Timer & Guardian

Defines:

- Lifecycle ownership
- Guardian behaviour
- Timer correction rules
- State transitions
- Announcement boundaries

Documents:

- [Lifecycle & Timer Contract](architecture/Lifecycle_Timer_Contract.md)
- [Crate Timer Guardian Logic](architecture/Crate_Timer_Guardian_Logic.md)
- [Guardian Logic Diagram](architecture/Crate_Timer_Guardian_Logic.svg)

---

# Protocols

## Addon Synchronisation Protocol

Defines:

- Group token lifecycle
- Session isolation
- Message format
- Encoding rules
- Authority model
- Communication channels

Documents:

- [Addon Protocol Design](protocols/CrateRush_Addon_Protocol_Design_v3.md)

---

# User Interface

## UI Design

Documents:

- [UI Design Specification](ui/CrateRush_UI_Design_Map_v1.md)
- [UI Design Diagram](ui/CrateRush_UI_Design_Map_v1.svg)

---

## Configuration UI

Documents:

- [Configuration UI Design](ui/CrateRush_Configuration_UI_Design.md)
- [Configuration UI Diagram](ui/CrateRush_Configuration_UI_Diagram.svg)

---

## UI Implementation Rules

Documents:

- [UI Implementation Hard Rules](ui/CrateRush_UI_Implementation_Hard_Rules.md)

---

# Feature Modules

## Feature Module Guidelines

Documents:

- [Feature Module Guidelines](features/CrateRush_Feature_Module_Guidelines.md)

---

## Prediction

Documents:

- [Prediction Design](features/CrateRush_Prediction_Design.md)

Purpose:

Predict crate drop location and timing during the flying phase.

---

## Enemy Presence

Documents:

- [Enemy Presence Design](features/CrateRush_EnemyPresence_Design_v1.md)

Purpose:

Estimate visible enemy force and healer pressure near active crates.

---

## Queue Detection

Documents:

- [Queue Detection Design](features/CrateRush_Queue_Detection_Design_v1.md)

Purpose:

Identify queued group members that may impact shard stability.

---

## Bounty Detection

Documents:

- [Bounty Detection Design](features/CrateRush_Bounty_Detection_Design_v1.md)

Purpose:

Detect enemy bounty targets and provide location awareness.

---

# Project Notes

## Current Status

Documents:

- [Addon TODO](project/CrateRush_Addon_TODO.md)
- [UI TODO](project/CrateRush_UI_v1_TODO.md)

---

## Ambiguity Parking Lot

Documents:

- [Ambiguity Parking Lot](project/ambiguous.md)

Contains intentionally deferred design decisions and unresolved topics.

---

# Contribution Rules

## Preferred Contributions

- Bug fixes
- Performance improvements
- Documentation improvements
- Verified game data
- Testing and validation
- UI improvements that respect architecture boundaries

## Avoid

- Unrequested rewrites
- Architecture changes without discussion
- Protocol changes without documentation updates
- Style only pull requests
- Logic moved into UI layers
- Duplicate ownership of domain truth

## Documentation Rule

If a change affects architecture, lifecycle behaviour, timer behaviour, protocols, UI contracts, or feature ownership, the relevant design document should be updated as part of the same change.

Documentation and implementation should remain aligned.
