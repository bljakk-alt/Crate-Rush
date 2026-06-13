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
    CLAIMED_BY_MY_FACTION = "CLAIMED_BY_MY_FACTION",
    CLAIMED_BY_OPPOSITE_FACTION = "CLAIMED_BY_OPPOSITE_FACTION",
}

CrateRush.CRATE_SOURCE = {
    UNKNOWN             = "UNKNOWN",
    ZONE_CHECK          = "ZONE_CHECK",
    CRATE_CYCLE_ANCHOR  = "CRATE_CYCLE_ANCHOR",
    FLYING              = CrateRush.CRATE_STATE.FLYING,
    DROPPING            = CrateRush.CRATE_STATE.DROPPING,
    LANDED              = CrateRush.CRATE_STATE.LANDED,
    CLAIMED_BY_ALLIANCE = CrateRush.CRATE_STATE.CLAIMED_BY_ALLIANCE,
    CLAIMED_BY_HORDE    = CrateRush.CRATE_STATE.CLAIMED_BY_HORDE,
    CLAIMED_BY_MY_FACTION = CrateRush.CRATE_STATE.CLAIMED_BY_MY_FACTION,
    CLAIMED_BY_OPPOSITE_FACTION = CrateRush.CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION,
    LANDED_GONE_WHILE_FLYING = "LANDED_GONE_WHILE_FLYING",
    LANDED_GONE_EXPIRY = "LANDED_GONE_EXPIRY",
    REMOTE_TIMER_SYNC   = "REMOTE_TIMER_SYNC",
}

CrateRush.VIGNETTE_TYPE = {
    UNKNOWN                   = "UNKNOWN",
    OTHER                     = "OTHER",
    PLANE_FLYING              = "PLANE_FLYING",
    CRATE_DROPPING            = "CRATE_DROPPING",
    CRATE_LANDED              = "CRATE_LANDED",
    CRATE_CLAIMED_MARKER_ALLIANCE = "CRATE_CLAIMED_MARKER_ALLIANCE",
    CRATE_CLAIMED_MARKER_HORDE    = "CRATE_CLAIMED_MARKER_HORDE",
    UNKNOWN_6072              = "UNKNOWN_6072",
}

CrateRush.SCAN_TRIGGER = {
    ZONE_POLL          = "ZONE_POLL",
    ZONE_SETTLED       = "ZONE_SETTLED",
    ZONE_SHARD_GRACE   = "ZONE_SHARD_GRACE",
    VIGNETTES_UPDATED  = "VIGNETTES_UPDATED",
    CRATE_CYCLE_ANCHOR = "CRATE_CYCLE_ANCHOR",
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
    RAID         = "RAID",
    PARTY        = "PARTY",
}

CrateRush.TIMER_ANCHOR_REASON = {
    CRATE_CYCLE_ANCHOR      = "crate_cycle_anchor",
    NO_TIMER                = "no_timer",
    EARLIER_THAN_ROLLOVER   = "earlier_than_rollover",
    GUARDIAN                = "guardian",
}

CrateRush.TIMER_REMOVE_REASON = {
    MANUAL              = "manual",
    STALE_NO_SIGHTINGS  = "stale_no_sightings",
    ZONE_SHARD_REPLACED = "zone_shard_replaced",
    GROUP_TIMER_DELETE  = "group_timer_delete",
}

CrateRush.CRATE_DEFAULTS = {
    SHARD_CONFIRM_COUNT           = 2,
    AMBIGUOUS_SHARD_CONFIRM_COUNT = 4,
}

function CrateRush.isCrateStateClaimed(state)
    return state == CrateRush.CRATE_STATE.CLAIMED_BY_ALLIANCE
        or state == CrateRush.CRATE_STATE.CLAIMED_BY_HORDE
        or state == CrateRush.CRATE_STATE.CLAIMED_BY_MY_FACTION
        or state == CrateRush.CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION
end

function CrateRush.isCrateStateClaimedByMyFaction(state)
    return state == CrateRush.CRATE_STATE.CLAIMED_BY_MY_FACTION
end

function CrateRush.isCrateStateClaimedByOppositeFaction(state)
    return state == CrateRush.CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION
end

function CrateRush.isCrateVignetteClaimed(vignetteType)
    return vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_ALLIANCE
        or vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_HORDE
end

function CrateRush.getClaimedFactionForVignette(vignetteType)
    if vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_ALLIANCE then
        return CrateRush.FACTION.ALLIANCE
    elseif vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_HORDE then
        return CrateRush.FACTION.HORDE
    end
    return nil
end

function CrateRush.getClaimedStateForVignette(vignetteType)
    if vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_ALLIANCE then
        return CrateRush.CRATE_STATE.CLAIMED_BY_ALLIANCE, CrateRush.CRATE_SOURCE.CLAIMED_BY_ALLIANCE
    elseif vignetteType == CrateRush.VIGNETTE_TYPE.CRATE_CLAIMED_MARKER_HORDE then
        return CrateRush.CRATE_STATE.CLAIMED_BY_HORDE, CrateRush.CRATE_SOURCE.CLAIMED_BY_HORDE
    end
    return nil, nil
end

function CrateRush.getPlayerRelativeClaimedStateForVignette(vignetteType)
    local claimedFaction = CrateRush.getClaimedFactionForVignette(vignetteType)
    if not claimedFaction then return nil, nil, nil end

    local playerFaction = CrateRush.playerContext
        and CrateRush.playerContext.getFactionKey
        and CrateRush.playerContext:getFactionKey()
        or CrateRush.resolveFactionKey(nil)

    if playerFaction == claimedFaction then
        return CrateRush.CRATE_STATE.CLAIMED_BY_MY_FACTION,
            CrateRush.CRATE_SOURCE.CLAIMED_BY_MY_FACTION,
            claimedFaction
    end

    return CrateRush.CRATE_STATE.CLAIMED_BY_OPPOSITE_FACTION,
        CrateRush.CRATE_SOURCE.CLAIMED_BY_OPPOSITE_FACTION,
        claimedFaction
end
