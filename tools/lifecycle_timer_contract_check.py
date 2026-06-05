#!/usr/bin/env python3
"""Contract checks for CrateRush lifecycle/timer behavior.

This script intentionally lives outside the WoW addon load path. It is a
refactor gate: it simulates the core lifecycle/timer contract and scans the Lua
source for patterns that previously broke announcements or timer ownership.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "CrateRush"
GUARDIAN_SECONDS = 900
ZONE_DURATION = 1100
PLANE_CONFIRM_GAP_SECONDS = 3
PLANE_CONFIRM_REQUIRED = 3


STATE_ORDER = {
    "IDLE": 0,
    "DETECTED": 1,
    "DROPPING": 2,
    "LANDED": 3,
    "CLAIMED_BY_ALLIANCE": 4,
    "CLAIMED_BY_HORDE": 4,
}

AUTHORITATIVE_SOURCES = {"MONSTER_SAY"}


@dataclass
class Timer:
    zone_id: int
    shard_id: int
    start: int
    quality: str
    source: str


@dataclass
class Record:
    zone_id: int
    shard_id: int
    state: str = "IDLE"
    lifecycle_started_at: int | None = None
    last_seen_at: int | None = None
    timer: Timer | None = None
    announced: set[str] = field(default_factory=set)


@dataclass
class PlaneCounter:
    guid: str
    count: int
    last_seen_at: int


class ContractModel:
    def __init__(self) -> None:
        self.records: dict[tuple[int, int], Record] = {}
        self.active_timer_by_zone: dict[int, tuple[int, int]] = {}
        self.plane_by_key: dict[tuple[int, int], PlaneCounter] = {}
        self.announcements: list[tuple[int, int, str]] = []

    def key(self, zone_id: int, shard_id: int) -> tuple[int, int]:
        return (zone_id, shard_id)

    def get_or_create(self, zone_id: int, shard_id: int) -> Record:
        key = self.key(zone_id, shard_id)
        if key not in self.records:
            self.records[key] = Record(zone_id=zone_id, shard_id=shard_id)
        return self.records[key]

    def remove_other_zone_records(self, zone_id: int, shard_id: int) -> None:
        for key in list(self.records):
            if key[0] == zone_id and key[1] != shard_id:
                del self.records[key]
        if self.active_timer_by_zone.get(zone_id) not in (None, self.key(zone_id, shard_id)):
            self.active_timer_by_zone.pop(zone_id, None)

    def guardian_allows_start(self, record: Record, source: str, now: int) -> bool:
        if source == "MONSTER_SAY":
            return True
        if record.lifecycle_started_at is None:
            return True
        return now - record.lifecycle_started_at >= GUARDIAN_SECONDS

    def announce(self, record: Record, state: str) -> None:
        if state in record.announced:
            return
        record.announced.add(state)
        self.announcements.append((record.zone_id, record.shard_id, state))

    def apply_timer_policy(self, record: Record, source: str, now: int) -> None:
        is_anchor = source in AUTHORITATIVE_SOURCES
        has_zone_timer = self.active_timer_by_zone.get(record.zone_id) == self.key(record.zone_id, record.shard_id)

        if is_anchor:
            record.timer = Timer(record.zone_id, record.shard_id, now, "anchor", source)
            self.active_timer_by_zone[record.zone_id] = self.key(record.zone_id, record.shard_id)
            return

        if record.timer is None or not has_zone_timer:
            record.timer = Timer(record.zone_id, record.shard_id, now, "fallback", source)
            self.active_timer_by_zone[record.zone_id] = self.key(record.zone_id, record.shard_id)
            return

        next_expected = self.next_expected(record.zone_id, now)
        elapsed = now - record.timer.start
        cycle_age = elapsed % ZONE_DURATION if elapsed >= 0 else ZONE_DURATION
        if next_expected is not None and now < next_expected and cycle_age >= GUARDIAN_SECONDS:
            record.timer = Timer(record.zone_id, record.shard_id, now, "fallback", source)
            self.active_timer_by_zone[record.zone_id] = self.key(record.zone_id, record.shard_id)

    def start_lifecycle(self, now: int, zone_id: int, shard_id: int, source: str) -> Record | None:
        record = self.get_or_create(zone_id, shard_id)
        if not self.guardian_allows_start(record, source, now):
            return None

        self.remove_other_zone_records(zone_id, shard_id)
        record = self.get_or_create(zone_id, shard_id)
        record.state = "DETECTED"
        record.lifecycle_started_at = now
        record.last_seen_at = now
        record.announced = set()
        self.apply_timer_policy(record, source, now)
        self.announce(record, "DETECTED")
        return record

    def accept_state(self, now: int, zone_id: int, shard_id: int, state: str, source: str) -> bool:
        if state == "FLYING":
            state = "DETECTED"

        record = self.get_or_create(zone_id, shard_id)
        current_order = STATE_ORDER[record.state]
        new_order = STATE_ORDER[state]

        if state == "DETECTED":
            return self.start_lifecycle(now, zone_id, shard_id, source) is not None

        if current_order == 0:
            record = self.start_lifecycle(now, zone_id, shard_id, source)
            if record is None:
                return False

        record = self.get_or_create(zone_id, shard_id)
        if STATE_ORDER[record.state] > 0 and self.guardian_allows_start(record, source, now):
            record = self.start_lifecycle(now, zone_id, shard_id, source)
            if record is None:
                return False

        if new_order <= STATE_ORDER[record.state]:
            if self.guardian_allows_start(record, source, now):
                record = self.start_lifecycle(now, zone_id, shard_id, source)
                if record is None:
                    return False
            else:
                record.last_seen_at = now
                return False

        if new_order <= STATE_ORDER[record.state]:
            record.last_seen_at = now
            return False

        record.state = state
        record.last_seen_at = now
        if record.timer is None:
            self.apply_timer_policy(record, source, now)
        self.announce(record, state)
        return True

    def plane_seen(self, now: int, zone_id: int, shard_id: int, guid: str) -> bool:
        key = self.key(zone_id, shard_id)
        record = self.records.get(key)
        if record and not self.guardian_allows_start(record, "FLYING", now):
            self.plane_by_key.pop(key, None)
            return False

        counter = self.plane_by_key.get(key)
        if counter is None or counter.guid != guid or now - counter.last_seen_at > PLANE_CONFIRM_GAP_SECONDS:
            self.plane_by_key[key] = PlaneCounter(guid=guid, count=1, last_seen_at=now)
            return False

        counter.count += 1
        counter.last_seen_at = now
        if counter.count >= PLANE_CONFIRM_REQUIRED:
            self.plane_by_key.pop(key, None)
            return self.accept_state(now, zone_id, shard_id, "DETECTED", "FLYING")
        return False

    def next_expected(self, zone_id: int, now: int) -> int | None:
        key = self.active_timer_by_zone.get(zone_id)
        if key is None:
            return None
        timer = self.records[key].timer
        if timer is None:
            return None
        cycles = max(1, ((now - timer.start) // ZONE_DURATION) + 1)
        return timer.start + cycles * ZONE_DURATION


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def assert_equal(actual, expected, message: str) -> None:
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected!r}, got {actual!r}")


def run_scenario_checks() -> list[str]:
    passed: list[str] = []

    model = ContractModel()
    require(model.accept_state(1000, 2405, 404, "DETECTED", "MONSTER_SAY"), "monster say should start lifecycle")
    rec = model.records[(2405, 404)]
    assert_equal(rec.state, "DETECTED", "monster say state")
    assert_equal(rec.timer and rec.timer.start, 1000, "monster say timer anchor")
    assert_equal(rec.timer and rec.timer.quality, "anchor", "monster say timer quality")
    assert_equal(model.announcements, [(2405, 404, "DETECTED")], "monster say announcements")
    passed.append("monster say anchors detected lifecycle")

    require(model.accept_state(1030, 2405, 404, "DROPPING", "DROPPING"), "dropping should progress inside guardian")
    rec = model.records[(2405, 404)]
    assert_equal(rec.state, "DROPPING", "dropping state")
    assert_equal(rec.timer and rec.timer.start, 1000, "dropping must not reset authoritative timer")
    require((2405, 404, "DROPPING") in model.announcements, "dropping announcement missing")
    passed.append("dropping progresses and announces inside guardian")

    require(model.accept_state(1050, 2405, 404, "LANDED", "LANDED"), "landed should progress inside guardian")
    rec = model.records[(2405, 404)]
    assert_equal(rec.state, "LANDED", "landed state")
    assert_equal(rec.timer and rec.timer.start, 1000, "landed must not reset authoritative timer")
    require((2405, 404, "LANDED") in model.announcements, "landed announcement missing")
    passed.append("landed progresses and announces inside guardian")

    before = list(model.announcements)
    require(not model.accept_state(1060, 2405, 404, "DROPPING", "DROPPING"), "duplicate/backward dropping should be ignored")
    assert_equal(model.announcements, before, "duplicate dropping must not announce")
    passed.append("duplicate state does not announce")

    model = ContractModel()
    require(model.accept_state(2000, 2405, 501, "DROPPING", "DROPPING"), "first fallback dropping should be accepted")
    rec = model.records[(2405, 501)]
    assert_equal(rec.state, "DROPPING", "fallback dropping final state")
    assert_equal(rec.timer and rec.timer.quality, "fallback", "fallback dropping timer quality")
    assert_equal(
        model.announcements,
        [(2405, 501, "DETECTED"), (2405, 501, "DROPPING")],
        "fallback dropping should implicitly announce detected then dropping",
    )
    passed.append("fallback first event creates implicit detected and fallback timer")

    require(model.accept_state(2910, 2405, 501, "DETECTED", "MONSTER_SAY"), "authoritative anchor should replace fallback")
    rec = model.records[(2405, 501)]
    assert_equal(rec.timer and rec.timer.start, 2910, "authoritative anchor replaces fallback timer start")
    assert_equal(rec.timer and rec.timer.quality, "anchor", "authoritative anchor replaces fallback timer quality")
    passed.append("authoritative anchor replaces fallback timer")

    model = ContractModel()
    require(model.accept_state(6000, 2395, 11065, "LANDED", "LANDED"), "first fallback landed should be accepted")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.timer and rec.timer.start, 6000, "landed fallback timer setup")
    require(model.accept_state(7043, 2395, 11065, "DROPPING", "DROPPING"), "new fallback dropping after guardian should start a new lifecycle")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.state, "DROPPING", "new fallback lifecycle should progress to dropping")
    assert_equal(rec.timer and rec.timer.start, 7043, "new fallback lifecycle replaces older fallback timer")
    assert_equal(rec.timer and rec.timer.quality, "fallback", "replacement timer remains fallback quality")
    passed.append("new fallback lifecycle replaces older fallback timer")

    model = ContractModel()
    require(model.accept_state(8000, 2395, 11065, "DETECTED", "MONSTER_SAY"), "monster say setup should be accepted")
    require(model.accept_state(9043, 2395, 11065, "DROPPING", "DROPPING"), "non-monster earlier than rollover should replace previous timer regardless of old source")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.state, "DROPPING", "new post-guardian lifecycle should progress to dropping")
    assert_equal(rec.timer and rec.timer.start, 9043, "earlier non-monster lifecycle replaces previous timer")
    assert_equal(rec.timer and rec.timer.quality, "fallback", "non-monster replacement keeps fallback quality")
    passed.append("non-monster evidence pulls timer earlier toward missed monster say")

    require(model.accept_state(10153, 2395, 11065, "DROPPING", "DROPPING"), "post-rollover lifecycle should be accepted")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.timer and rec.timer.start, 9043, "post-rollover non-monster event must not move timer later")
    require(model.accept_state(11220, 2395, 11065, "DROPPING", "DROPPING"), "next pre-rollover lifecycle should be accepted")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.timer and rec.timer.start, 11220, "later cycle can still move timer earlier once guardian age is reached")
    passed.append("non-monster timer keeps pulling earlier toward monster say when possible")

    model = ContractModel()
    require(model.accept_state(3000, 2405, 1, "DETECTED", "MONSTER_SAY"), "old shard lifecycle should start")
    require(model.accept_state(3010, 2405, 2, "DROPPING", "DROPPING"), "new shard fallback should not be blocked by old shard guardian")
    require((2405, 1) not in model.records, "new shard should remove old lifecycle for same zone")
    require((2405, 2) in model.records, "new shard lifecycle missing")
    assert_equal(model.active_timer_by_zone[2405], (2405, 2), "new shard should own visible timer")
    passed.append("new shard replaces old shard lifecycle and timer")

    model = ContractModel()
    require(model.accept_state(4000, 2405, 3, "DETECTED", "MONSTER_SAY"), "detected should start before plane guard test")
    require(not model.plane_seen(4002, 2405, 3, "plane-a"), "guarded plane sighting 1 should be ignored")
    require(not model.plane_seen(4004, 2405, 3, "plane-a"), "guarded plane sighting 2 should be ignored")
    require(not model.plane_seen(4006, 2405, 3, "plane-a"), "guarded plane sighting 3 should be ignored")
    require((2405, 3) not in model.plane_by_key, "guarded plane should not leave a counter")
    assert_equal(model.announcements, [(2405, 3, "DETECTED")], "guarded plane should not announce duplicate detected")
    passed.append("guardian blocks plane counter before confirmation")

    require(not model.plane_seen(4901, 2405, 3, "plane-b"), "plane count 1 after guardian")
    require(not model.plane_seen(4903, 2405, 3, "plane-b"), "plane count 2 after guardian")
    require(model.plane_seen(4905, 2405, 3, "plane-b"), "plane count 3 after guardian should accept detected")
    assert_equal(model.records[(2405, 3)].timer and model.records[(2405, 3)].timer.start, 4905, "confirmed plane accepted timer")
    passed.append("confirmed plane starts detected after guardian")

    model = ContractModel()
    require(model.accept_state(5000, 2405, 9, "DETECTED", "MONSTER_SAY"), "rollover setup should start timer")
    assert_equal(model.next_expected(2405, 6101), 7200, "rollover should use previous expected timestamp plus duration")
    passed.append("timer rollover is based on previous expected timestamp")

    return passed


def read_source(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def run_source_shape_checks() -> list[str]:
    passed: list[str] = []
    crate = read_source("constants/crate.lua")
    shardmap = read_source("logic/crateHandler/shardmap.lua")
    handler = read_source("logic/crateHandler/crateHandler.lua")
    announce = read_source("logic/announce.lua")
    timers = read_source("logic/timers.lua")
    events = read_source("constants/events.lua")
    db = read_source("data/db.lua")
    config = read_source("config.lua")
    main = read_source("main.lua")
    toc = (ADDON / "CrateRush.toc").read_text(encoding="utf-8")
    domain_state = read_source("logic/domainState.lua")
    diagnostics = read_source("logic/domainStateDiagnostics.lua")
    timerbars = read_source("ui/timerbars.lua")
    zone_resolver = read_source("logic/zoneResolver.lua")
    vignette_scanner = read_source("logic/vignetteScanner.lua")
    timer_policy = read_source("logic/timerPolicy.lua")
    shard_service = read_source("logic/shardService.lua")
    crate_lifecycle = read_source("logic/crateLifecycle.lua")
    transition_guard = read_source("logic/transitionGuard.lua")
    monster_say = read_source("logic/monsterSayService.lua")
    map_module = read_source("logic/crateHandler/map.lua")
    announcement_templates = read_source("logic/announcements/templates.lua")
    announcement_router = read_source("logic/announcements/router.lua")
    announcement_debug_sink = read_source("logic/announcements/sinks/debug.lua")
    announcement_chat_sink = read_source("logic/announcements/sinks/defaultChatFrame.lua")
    announcement_warning_sink = read_source("logic/announcements/sinks/warningFrame.lua")
    announcement_party_raid_sink = read_source("logic/announcements/sinks/partyRaid.lua")
    announcement_addon_comm_sink = read_source("logic/announcements/sinks/addonComm.lua")

    require('DETECTED            = "DETECTED"' in crate, "CRATE_STATE.DETECTED must exist")
    passed.append("CRATE_STATE.DETECTED exists")

    require("shouldAcceptLifecycleDetection" not in shardmap, "old mixed guardian function must not return")
    require("early_correction" not in crate.lower(), "old early_correction timer policy must not return")
    passed.append("old mixed lifecycle/timer policy names are absent")

    require("CRATE_STATE.DETECTED" in handler, "monster say must transition to DETECTED")
    require("transition(crateZoneID, confirmedShardID, CRATE_STATE.FLYING" not in handler, "monster say must not transition to FLYING")
    passed.append("monster say creates DETECTED, not FLYING state")

    require("shouldProcessObjectState" in crate_lifecycle, "crate object state processing helper must exist")
    require("CRATE_OBJECT_REPROCESS" in handler, "seen crate object GUIDs must be able to reprocess missing runtime state")
    require("self:getRecord(zoneID, shardID) == nil" in crate_lifecycle and "CrateRush.domainState:getTimer(zoneID, shardID)" in crate_lifecycle, "crate object states must recover missing lifecycle/timer state")
    require("crateLifecycle:shouldProcessObjectState" in handler, "crate object processing must be delegated through crateLifecycle")
    passed.append("crate object states can recover missing runtime state")

    require("vignetteZoneOwners" in transition_guard, "vignette GUIDs must remember their first owning crate zone")
    require("vignetteContextZoneOwners" in transition_guard, "vignette GUID context keys must remember their first owning crate zone")
    require("getVignetteContextKey" in vignette_scanner, "scanner must extract the state-independent vignette context key")
    require("STALE_ZONE_GUID" in transition_guard, "cross-zone stale vignette GUIDs must be logged and rejected")
    require("STALE_ZONE_CONTEXT" in transition_guard, "cross-zone stale vignette context changes must be logged and rejected")
    require("transitionGuard:claimSighting" in handler, "crateHandler must call transition guard before shard/lifecycle success")
    require("confirmedShardAtScanStart" in handler, "crate lifecycle success must require shard confirmation from scan start")
    require("LIFECYCLE_DEFER_UNCONFIRMED_SHARD" in handler, "unconfirmed shard evidence must defer lifecycle/timer success")
    require("reason=shard_not_confirmed_at_scan_start" in handler, "unconfirmed shard deferral must be explicit in debug")
    require("CRATE_OBJECT_DEFER_PREVIOUS_SHARD" in handler, "previous-zone shard crate objects must defer until current zone confirmation")
    require("isPreviousZoneShardPending" in shard_service and "isPreviousZoneShardPending" in handler, "previous-zone shard must not fast-accept as stored match")
    passed.append("zone-transition stale crate evidence is rejected before lifecycle/timer state")

    require("newState ~= STATE_DETECTED" in crate_lifecycle, "state progress branch must remain separate from lifecycle start")
    require("applyTimerLifecycle" in timer_policy, "timer policy must remain separate from state progress")
    require("CrateRush.timerPolicy:applyTimerLifecycle" in crate_lifecycle, "crateLifecycle must use timerPolicy for timer decisions")
    require("EARLIER_THAN_ROLLOVER" in crate, "timer anchor reasons must include earlier-than-rollover")
    require("getNextRolloverTime" in timer_policy and "TIMER_ANCHOR_REASON.EARLIER_THAN_ROLLOVER" in timer_policy, "non-monster lifecycle starts must use earlier-than-rollover timer policy")
    require("cycleAge >= self:getLifecycleDetectionGuardianSeconds()" in timer_policy, "non-monster timer movement must wait for guardian-aged cycle window")
    passed.append("lifecycle start and timer policy are visibly separated")

    for debug_field in ("TIMER ANCHOR |", "oldStart=", "newStart=", "elapsed=", "cycles=", "cycleTime="):
        require(debug_field in timer_policy, f"timer anchor debug must keep {debug_field}")
    passed.append("timer anchor debug keeps old/new start and cycle timing fields")

    guard_idx = crate_lifecycle.find("local detectionAccepted = shouldAcceptLifecycleStart(guardRecord, CRATE_SOURCE.FLYING, now)")
    plane_log_idx = crate_lifecycle.find('zoneLog("PLANE_SEEN zone="')
    require(guard_idx != -1 and plane_log_idx != -1 and guard_idx < plane_log_idx, "plane guardian check must happen before PLANE_SEEN counter logs")
    passed.append("plane guardian check precedes plane counter")

    map_idx = toc.find("logic/crateHandler/map.lua")
    announcement_templates_idx = toc.find("logic/announcements/templates.lua")
    announcement_router_idx = toc.find("logic/announcements/router.lua")
    announcement_debug_sink_idx = toc.find("logic/announcements/sinks/debug.lua")
    announcement_chat_sink_idx = toc.find("logic/announcements/sinks/defaultChatFrame.lua")
    announcement_warning_sink_idx = toc.find("logic/announcements/sinks/warningFrame.lua")
    announcement_party_raid_sink_idx = toc.find("logic/announcements/sinks/partyRaid.lua")
    announcement_addon_comm_sink_idx = toc.find("logic/announcements/sinks/addonComm.lua")
    announce_idx = toc.find("logic/announce.lua")
    require(
        -1 not in (
            map_idx,
            announcement_templates_idx,
            announcement_router_idx,
            announcement_debug_sink_idx,
            announcement_chat_sink_idx,
            announcement_warning_sink_idx,
            announcement_party_raid_sink_idx,
            announcement_addon_comm_sink_idx,
            announce_idx,
        )
        and map_idx
        < announcement_templates_idx
        < announcement_router_idx
        < announcement_debug_sink_idx
        < announcement_chat_sink_idx
        < announcement_warning_sink_idx
        < announcement_party_raid_sink_idx
        < announcement_addon_comm_sink_idx
        < announce_idx,
        "announcement modules must load map -> templates -> router -> sinks -> service",
    )
    require("CrateRush.announcementTemplates:build(payload)" in announce, "announce service must delegate message building to templates")
    require("CrateRush.announcementRouter:route(announcement)" in announce, "announce service must route finalized announcement through router")
    for forbidden in ("DEFAULT_CHAT_FRAME", "SendChatMessage", "CrateRush.warningframe", "CrateRush.comms"):
        require(forbidden not in announce, f"announce service must not call output sink {forbidden}")
    require("CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING" in announcement_templates, "detected announcement must key from DETECTED")
    require("lifecycleStartedAt" in announce, "announcement cycle key must use lifecycle identity")
    require("includeMapPinInDropAndLandedAnnouncements" in announcement_templates and '"%coordinates%"' in announcement_templates, "dropping/landed announcements must append configurable map pin links and expose coordinate placeholder")
    require("getMapPinLocation" in map_module and "UiMapPoint.CreateFromCoordinates" in map_module, "map helper must expose Blizzard map pin location generation")
    require("Keep the waypoint active" in map_module and "ClearUserWaypoint" not in map_module, "map pin helper must leave the player's waypoint active")
    require("getMapPinLocation" not in crate_lifecycle and "worldmap:" not in crate_lifecycle, "lifecycle must not build map pin links")
    require("registerSink" in announcement_router and "function router:route" in announcement_router, "announcement router must own sink fan-out")
    require("ANNOUNCE |" in announcement_debug_sink, "debug announcement sink must own debug output")
    require("DEFAULT_CHAT_FRAME:AddMessage" in announcement_chat_sink, "default chat frame sink must own local clickable chat output")
    require("CrateRush.warningframe:show" in announcement_warning_sink, "warning frame sink must own warning output")
    require("SendChatMessage" in announcement_party_raid_sink, "party/raid sink must own chat send output")
    require("CrateRush.comms.send" in announcement_addon_comm_sink, "addon comm sink must own future addon-to-addon output")
    passed.append("announcements are lifecycle keyed")

    require("makeCrateKey" in db and "zoneID, shardID" in db, "crate history must be keyed by zoneID + shardID")
    require("removeOtherCratesForZone" in db, "storage must retain one active shard per zone")
    require("byZone" in db and "zoneShards" in db and "getRecordTimestamp" in db, "storage migration must collapse old duplicate zone timers")
    passed.append("storage contract is zone/shard keyed and deduped by zone")

    db_idx = toc.find("data/db.lua")
    config_idx = toc.find("config.lua")
    crate_handler_idx = toc.find("logic/crateHandler/crateHandler.lua")
    require(
        -1 not in (db_idx, config_idx, crate_handler_idx)
        and db_idx < config_idx < crate_handler_idx,
        "config gateway must load after storage and before logic modules",
    )
    require("CrateRush.config:init(CrateRush.storage)" in main, "main must initialize config with the storage gateway")
    require("function config:get(" in config and "function config:getNumber(" in config and "function config:set(" in config, "config gateway must expose get/getNumber/set")
    require("function config:getBoolean(" in config, "config gateway must expose boolean settings")
    require("config.storage:get(key)" in config and "config.storage:set(key, value)" in config, "only config gateway should proxy generic setting storage access")
    for module_name, source in (
        ("crateHandler", handler),
        ("shardmap", shardmap),
        ("shardService", shard_service),
        ("timerPolicy", timer_policy),
        ("timers", timers),
        ("main", main),
    ):
        require("storage:get(" not in source and "storage.get(" not in source, f"{module_name} must read settings through config, not storage:get")
    require("CrateRush.config:getNumber" in shard_service, "shardService setting numbers must come through config")
    require("CrateRush.config:getNumber" in timer_policy, "timerPolicy setting numbers must come through config")
    require("CrateRush.config:getNumber" in timers, "timer settings must come through config")
    passed.append("config gateway owns runtime settings reads")

    require("CrateRush.frames" not in handler, "crateHandler must not call UI frames directly")
    require("CrateRush.timerbars" not in handler, "crateHandler must not call timerbars directly")
    require("ZONE_SHARD_STATUS_CHANGED" not in handler, "crateHandler must not publish header state directly")
    require("ZONE_SHARD_STATUS_CHANGED" in shard_service, "shardService should publish header state through domain events")
    require("onZoneShardStatusChanged" in read_source("ui/frames.lua"), "header UI must subscribe to zone shard status events")
    passed.append("crateHandler does not call UI adapters directly")

    zone_resolver_idx = toc.find("logic/zoneResolver.lua")
    require(
        -1 not in (zone_resolver_idx, crate_handler_idx)
        and zone_resolver_idx < crate_handler_idx,
        "zoneResolver must load before crateHandler",
    )
    require("CrateRush.zoneResolver = zoneResolver" in zone_resolver, "zoneResolver service must be registered")
    for required_api in (
        "resolveCrateZoneID",
        "getCrateZoneName",
        "getPlayerMapID",
        "getPlayerZoneContext",
    ):
        require(required_api in zone_resolver, f"zoneResolver must expose {required_api}")
    require("CrateRush.zones:resolveCrateZoneID" in zone_resolver, "zoneResolver must delegate crate-zone mapping to gamedata zones")
    require("local zoneResolver = CrateRush.zoneResolver" in handler, "crateHandler must consume zoneResolver service")
    require("C_Map.GetBestMapForUnit" not in handler, "crateHandler must not own player map lookup")
    require("C_Map.GetMapInfo" not in handler, "crateHandler must not own map-name lookup")
    require("local function resolveCrateZoneID" not in handler, "crateHandler must not keep local zone resolver helper")
    passed.append("zoneResolver owns player map and crate zone resolution")

    vignette_scanner_idx = toc.find("logic/vignetteScanner.lua")
    require(
        -1 not in (zone_resolver_idx, vignette_scanner_idx, crate_handler_idx)
        and zone_resolver_idx < vignette_scanner_idx < crate_handler_idx,
        "vignetteScanner must load after zoneResolver and before crateHandler",
    )
    require("CrateRush.vignetteScanner = vignetteScanner" in vignette_scanner, "vignetteScanner service must be registered")
    for required_api in (
        "getVignettes",
        "getVignetteInfo",
        "getVignettePosition",
        "getVignetteType",
        "read",
    ):
        require(required_api in vignette_scanner, f"vignetteScanner must expose {required_api}")
    for wow_api in (
        "C_VignetteInfo.GetVignettes",
        "C_VignetteInfo.GetVignetteInfo",
        "C_VignetteInfo.GetVignettePosition",
    ):
        require(wow_api in vignette_scanner, f"vignetteScanner must own {wow_api}")
        require(wow_api not in handler, f"crateHandler must not own {wow_api}")
    require("CrateRush.VIGNETTE_IDS" in vignette_scanner, "vignetteScanner must own vignette ID classification")
    require("CrateRush.VIGNETTE_IDS" not in handler, "crateHandler must not classify vignette IDs directly")
    require("extractShardFromGUID" not in handler, "crateHandler must not extract shard IDs from vignette GUIDs directly")
    require("local vignetteScanner = CrateRush.vignetteScanner" in handler, "crateHandler must consume vignetteScanner service")
    require("vignetteScanner:read" in handler and "sighting.shardID" in handler, "crateHandler must process prepared vignette sightings")
    passed.append("vignetteScanner owns raw vignette reading and classification")

    timer_policy_idx = toc.find("logic/timerPolicy.lua")
    shard_service_idx = toc.find("logic/shardService.lua")
    crate_lifecycle_idx = toc.find("logic/crateLifecycle.lua")
    transition_guard_idx = toc.find("logic/transitionGuard.lua")
    monster_say_idx = toc.find("logic/monsterSayService.lua")
    shardmap_idx = toc.find("logic/crateHandler/shardmap.lua")
    require(
        -1 not in (timer_policy_idx, shard_service_idx, crate_lifecycle_idx, transition_guard_idx, monster_say_idx, shardmap_idx, crate_handler_idx)
        and vignette_scanner_idx < timer_policy_idx < shard_service_idx < crate_lifecycle_idx < transition_guard_idx < monster_say_idx < shardmap_idx < crate_handler_idx,
        "Step 7 services must load before crateHandler orchestration",
    )
    require("zoneShardCheck" not in handler and "zoneConfirm" not in handler, "crateHandler must not own shard confirmation state")
    require("zoneShardCheck" in shard_service and "zoneConfirm" in shard_service, "shardService must own shard confirmation state")
    require("shardService:processShardEvidence" in handler, "crateHandler must delegate shard evidence to shardService")
    require("recentPlane" not in handler and "recentPlane" in crate_lifecycle, "crateLifecycle must own plane confirmation state")
    require("CrateRush.CRATE_NPC_PHRASES" not in handler and "CrateRush.CRATE_NPC_PHRASES" in monster_say, "monsterSayService must own phrase matching")
    require("monsterSayService:isCrateAnnouncement" in handler, "crateHandler must delegate monster say matching")
    require("CrateRush.crateLifecycle" in shardmap and "CrateRush.shardService" in shardmap, "shardmap must be a compatibility facade")
    passed.append("Step 7 services own shard, lifecycle, timer, transition, and monster-say logic")

    domain_events_idx = toc.find("logic/domainEvents.lua")
    domain_state_idx = toc.find("logic/domainState.lua")
    require(
        -1 not in (domain_events_idx, domain_state_idx, crate_handler_idx)
        and domain_events_idx < domain_state_idx < crate_handler_idx,
        "domainState must load after domainEvents and before domain publishers",
    )
    require("CrateRush.domainEvents:subscribe" in domain_state, "domainState must subscribe to published facts")
    require(":publish(" not in domain_state and ".publish(" not in domain_state, "domainState must own state without publishing events")
    for forbidden in ("CrateRush.storage", "CrateRush.timers", "CrateRush.frames", "CrateRush.announce", "SendChatMessage"):
        require(forbidden not in domain_state, f"domainState must not call {forbidden}")
    for required_api in (
        "getOrCreateLifecycle",
        "setCurrentLifecycle",
        "removeOtherLifecyclesForZone",
        "setTimer",
        "removeOtherTimersForZone",
        "getActiveTimer",
    ):
        require(required_api in domain_state, f"domainState must expose {required_api}")
    passed.append("domainState owns lifecycle and timer runtime indexes")

    require("local records" not in shardmap, "shardmap must not keep a private lifecycle records table")
    require("records[" not in shardmap, "shardmap must not index private lifecycle records directly")
    require("CrateRush.domainState:getOrCreateLifecycle" in crate_lifecycle, "crateLifecycle must create lifecycle records through domainState")
    require("CrateRush.domainState:getLifecycleRecords" in crate_lifecycle, "crateLifecycle getAll must read domainState records")
    passed.append("crateLifecycle uses domainState for lifecycle records")

    require("local activeTimers" not in timers, "timers must not keep a private active timer table")
    require("activeTimers[" not in timers, "timers must not index private active timers directly")
    require("CrateRush.domainState:setTimer" in timers, "timers must write active timers through domainState")
    require("CrateRush.domainState:getTimerRecords" in timers, "timers tick must read active timers through domainState")
    require("CrateRush.domainState:getTimerRecordsSnapshot" in timers, "timer snapshots must read domainState")
    require("visibleByZone" in timers and "shouldPreferTimer" in timers, "active timer changed payload must be unique by zone")
    require("timers:onStateChange(" in timers and "function timers:restore()" in timers, "restore must use timer service entrypoint")
    require("CrateRush.shardmap" not in timers, "timers must not call the shardmap compatibility facade")
    require("CrateRush.crateLifecycle:reset" in timers, "timer removal must reset lifecycle through crateLifecycle service")
    require("TIMER_REMOVAL_REQUESTED" in events and "timerRemovalRequested" in events, "timer removal request event must be named")
    require("TIMER_REMOVAL_REQUESTED" in timers and "onTimerRemovalRequested" in timers, "timers must subscribe to timer removal requests")
    require("CrateRush.timers:removeByKey" not in timerbars, "timerbars must not remove timers directly")
    require("TIMER_REMOVAL_REQUESTED" in timerbars and "requestTimerRemoval" in timerbars, "timerbars must publish timer removal requests")
    passed.append("timers use domainState for unique active timer records")

    require("local seen = {}" in timerbars and "local stale = {}" in timerbars, "timerbar sorted refresh must prune keys missing from active timer payload")
    require("timerbars:remove(key)" in timerbars, "timerbar sorted refresh must remove stale visual rows")
    passed.append("timerbars prune stale visual rows")

    timers_idx = toc.find("logic/timers.lua")
    diagnostics_idx = toc.find("logic/domainStateDiagnostics.lua")
    comms_idx = toc.find("comms.lua")
    require(
        -1 not in (timers_idx, diagnostics_idx, comms_idx)
        and timers_idx < diagnostics_idx < comms_idx,
        "domainStateDiagnostics must load after timers and before comms",
    )
    require("getActiveTimersSnapshot" in timers and "getActiveTimerForZone" in timers, "timers must expose read-only snapshot methods for diagnostics")
    require("CrateRush.domainEvents:subscribe" in diagnostics, "domainStateDiagnostics must subscribe to published facts")
    require(":publish(" not in diagnostics and ".publish(" not in diagnostics, "domainStateDiagnostics must not publish events")
    for forbidden in ("CrateRush.storage", "CrateRush.frames", "CrateRush.announce", "SendChatMessage"):
        require(forbidden not in diagnostics, f"domainStateDiagnostics must not call {forbidden}")
    passed.append("domainState diagnostics are read-only")

    return passed


def main() -> int:
    try:
        scenario_passes = run_scenario_checks()
        source_passes = run_source_shape_checks()
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print("Lifecycle/timer contract checks passed:")
    for item in scenario_passes:
        print(f"  scenario: {item}")
    for item in source_passes:
        print(f"  source:   {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
