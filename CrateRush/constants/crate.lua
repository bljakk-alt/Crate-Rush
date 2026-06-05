-- CrateRush
-- constants/crate.lua - Named constants for crate states, sources, triggers, and channels.

CrateRush.CRATE_STATE = {
    IDLE                = "IDLE",
    DETECTED            = "DETECTED",
    FLYING              = "FLYING",
    DROPPING            = "DROPPING",
    LANDED              = "LANDED",
    CLAIMED_BY_ALLIANCE = "CLAIMED_BY_ALLIANCE",
    CLAIMED_BY_HORDE    = "CLAIMED_BY_HORDE",
}

CrateRush.CRATE_SOURCE = {
    UNKNOWN             = "UNKNOWN",
    ZONE_CHECK          = "ZONE_CHECK",
    MONSTER_SAY         = "MONSTER_SAY",
    FLYING              = CrateRush.CRATE_STATE.FLYING,
    DROPPING            = CrateRush.CRATE_STATE.DROPPING,
    LANDED              = CrateRush.CRATE_STATE.LANDED,
    CLAIMED_BY_ALLIANCE = CrateRush.CRATE_STATE.CLAIMED_BY_ALLIANCE,
    CLAIMED_BY_HORDE    = CrateRush.CRATE_STATE.CLAIMED_BY_HORDE,
}

CrateRush.VIGNETTE_TYPE = {
    UNKNOWN                   = "UNKNOWN",
    OTHER                     = "OTHER",
    PLANE_FLYING              = "PLANE_FLYING",
    CRATE_DROPPING            = "CRATE_DROPPING",
    CRATE_LANDED              = "CRATE_LANDED",
    CRATE_CLAIMED_BY_ALLIANCE = "CRATE_CLAIMED_BY_ALLIANCE",
    CRATE_CLAIMED_BY_HORDE    = "CRATE_CLAIMED_BY_HORDE",
    UNKNOWN_6072              = "UNKNOWN_6072",
}

CrateRush.SCAN_TRIGGER = {
    ZONE_POLL          = "ZONE_POLL",
    ZONE_SETTLED       = "ZONE_SETTLED",
    ZONE_SHARD_GRACE   = "ZONE_SHARD_GRACE",
    VIGNETTES_UPDATED  = "VIGNETTES_UPDATED",
    MONSTER_SAY        = "MONSTER_SAY",
    GROUP_ROSTER_UPDATE = "GROUP_ROSTER_UPDATE",
}

CrateRush.SHARD_STATUS = {
    UNKNOWN  = "unknown",
    MATCHED  = "matched",
    MISMATCH = "mismatch",
    CHECKING = "checking",
}

CrateRush.CHAT_CHANNEL = {
    RAID_WARNING = "RAID_WARNING",
    PARTY        = "PARTY",
}

CrateRush.TIMER_ANCHOR_REASON = {
    MONSTER_SAY             = "monster_say",
    NO_TIMER                = "no_timer",
    EARLIER_THAN_ROLLOVER   = "earlier_than_rollover",
    GUARDIAN                = "guardian",
}

CrateRush.TIMER_REMOVE_REASON = {
    MANUAL              = "manual",
    STALE_NO_SIGHTINGS  = "stale_no_sightings",
    ZONE_SHARD_REPLACED = "zone_shard_replaced",
}

CrateRush.CRATE_DEFAULTS = {
    SHARD_CONFIRM_COUNT           = 2,
    AMBIGUOUS_SHARD_CONFIRM_COUNT = 4,
}
