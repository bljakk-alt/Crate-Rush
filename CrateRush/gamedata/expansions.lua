-- CrateRush
-- gamedata/expansions.lua — Static data per expansion: zones, spawn points, drop routes.
-- Also contains known vignette IDs and crate announcement NPC data.

local EXPANSIONS = {}
CrateRush.EXPANSIONS = EXPANSIONS

-- Known crate-related vignette IDs
CrateRush.VIGNETTE_IDS = {
    [3689] = CrateRush.VIGNETTE_TYPE.PLANE_FLYING,
    [2967] = CrateRush.VIGNETTE_TYPE.CRATE_DROPPING,
    [6066] = CrateRush.VIGNETTE_TYPE.CRATE_LANDED,
    [6067] = CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_ALLIANCE,
    [6068] = CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_HORDE,
    [6072] = CrateRush.VIGNETTE_TYPE.UNKNOWN_6072,
}

-- NPCs and phrases that turn a raw NPC announcement into an accepted crate cycle anchor.
-- NPC names are zone-specific but phrases may overlap.
CrateRush.CRATE_CYCLE_ANCHOR_NPC_NAMES = {
    ["Vidious"]  = true,
    ["Ziadan"]   = true,
    ["Ruffious"] = true,
}

-- Trigger phrases — any substring match means crate incoming
CrateRush.CRATE_CYCLE_ANCHOR_PHRASES = {
    "opportunity",
    "opportunities",
    "opportunities for loot",
    "valuable resources",
    "treasure nearby",
    "cache of resources",
    "you like goods",
    "early advantage",
    "spoils",
}

-- Zone respawn frequencies in seconds
CrateRush.ZONE_FREQUENCY = {
    [2023] = 2700, -- Ohn'ahran Plains
    [2024] = 2700, -- Azure Span
    [2025] = 2700, -- Thaldraszus
    [2255] = 1092, -- Azj-Kahet
    [2215] = 1093, -- Hallowfall
    [2248] = 1100, -- Isle of Dorn
    [2371] = 1100, -- K'aresh
    [2214] = 1096, -- Ringing Deeps
    [2346] = 1100, -- Undermine
    [2369] = 1100, -- Siren Isle
    [2022] = 2700, -- Waking Shores
    [2395] = 1099, -- Eversong Woods
    [2437] = 1098, -- Zul'Aman
    [2405] = 1097, -- VoidStorm
    [2444] = 1091, -- Slayer's Rise
    [2413] = 1099, -- Harandar
}

local DEFAULT_ZONE_FREQUENCY = 1100
CrateRush.DEFAULT_ZONE_FREQUENCY = DEFAULT_ZONE_FREQUENCY
-- EXPANSIONS["TWW"] = {
--     name   = "The War Within",
--     zones  = {},
--     spawns = {},
--     routes = {},
-- }
