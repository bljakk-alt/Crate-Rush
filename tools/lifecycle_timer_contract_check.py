#!/usr/bin/env python3
"""Contract checks for CrateRush lifecycle/timer behavior.

This script intentionally lives outside the WoW addon load path. It is a
refactor gate: it simulates the core lifecycle/timer contract and scans the Lua
source for patterns that previously broke announcements or timer ownership.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import math
import sys


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "CrateRush"
GUARDIAN_SECONDS = 900
ZONE_DURATION = 1100
PLANE_CONFIRM_GAP_SECONDS = 3
PLANE_POSITION_TOLERANCE_DEGREES = 0.05

ZONE_ANCHORS = {
    2395: (0.34157, 0.65242),
    2413: (0.47352, 0.15128),
    2444: (0.58756, 0.31229),
    2405: (0.62207, 0.93466),
    2437: (0.38122, 0.21003),
}

KNOWN_DROP_POINTS = {
    2405: [(0.5380, 0.6550)],
}

KNOWN_ROUTE_POINTS = {
    2405: [(0.5000, 0.5000)],
}


STATE_ORDER = {
    "IDLE": 0,
    "DETECTED": 1,
    "DROPPING": 2,
    "LANDED": 3,
    "CLAIMED_BY_ALLIANCE": 4,
    "CLAIMED_BY_HORDE": 4,
    "CLAIMED_BY_MY_FACTION": 4,
    "CLAIMED_BY_OPPOSITE_FACTION": 4,
}

AUTHORITATIVE_SOURCES = {"CRATE_CYCLE_ANCHOR"}


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
    last_x: float
    last_y: float
    same_position_ticks: int = 1


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
        if source == "CRATE_CYCLE_ANCHOR":
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

    def plane_seen(self, now: int, zone_id: int, shard_id: int, guid: str, x: float, y: float) -> bool:
        key = self.key(zone_id, shard_id)
        record = self.records.get(key)
        if record and not self.guardian_allows_start(record, "FLYING", now):
            self.plane_by_key.pop(key, None)
            return False

        counter = self.plane_by_key.get(key)
        if counter is None or counter.guid != guid or now - counter.last_seen_at > PLANE_CONFIRM_GAP_SECONDS:
            self.plane_by_key[key] = PlaneCounter(guid=guid, count=1, last_seen_at=now, last_x=x, last_y=y)
            return False

        counter.count += 1
        counter.last_seen_at = now

        distance = self.distance_degrees((counter.last_x, counter.last_y), (x, y))
        if distance > PLANE_POSITION_TOLERANCE_DEGREES:
            self.plane_by_key.pop(key, None)
            return self.accept_state(now, zone_id, shard_id, "DETECTED", "FLYING")

        counter.last_x = x
        counter.last_y = y
        counter.same_position_ticks += 1
        point = self.classify_plane_point(zone_id, x, y)
        if counter.same_position_ticks >= 2 and point["near_anchor"]:
            self.plane_by_key.pop(key, None)
            return self.accept_state(now, zone_id, shard_id, "DETECTED", "FLYING")
        if counter.same_position_ticks >= 2 and point["known_en_route"]:
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

    def distance_degrees(self, a: tuple[float, float], b: tuple[float, float]) -> float:
        dx = (a[0] - b[0]) * 100
        dy = (a[1] - b[1]) * 100
        return math.sqrt((dx * dx) + (dy * dy))

    def is_near(self, point: tuple[float, float], target: tuple[float, float] | None) -> bool:
        return target is not None and self.distance_degrees(point, target) <= PLANE_POSITION_TOLERANCE_DEGREES

    def point_is_near_any(self, point: tuple[float, float], targets: list[tuple[float, float]]) -> bool:
        return any(self.is_near(point, target) for target in targets)

    def classify_plane_point(self, zone_id: int, x: float, y: float) -> dict[str, bool]:
        point = (x, y)
        near_anchor = self.is_near(point, ZONE_ANCHORS.get(zone_id))
        near_drop = self.point_is_near_any(point, KNOWN_DROP_POINTS.get(zone_id, []))
        known_route = self.point_is_near_any(point, KNOWN_ROUTE_POINTS.get(zone_id, []))
        return {
            "near_anchor": near_anchor,
            "near_drop": near_drop,
            "known_en_route": known_route and not near_drop,
        }


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def assert_equal(actual, expected, message: str) -> None:
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected!r}, got {actual!r}")


def run_scenario_checks() -> list[str]:
    passed: list[str] = []

    model = ContractModel()
    require(model.accept_state(1000, 2405, 404, "DETECTED", "CRATE_CYCLE_ANCHOR"), "crate cycle anchor should start lifecycle")
    rec = model.records[(2405, 404)]
    assert_equal(rec.state, "DETECTED", "crate cycle anchor state")
    assert_equal(rec.timer and rec.timer.start, 1000, "crate cycle anchor timer anchor")
    assert_equal(rec.timer and rec.timer.quality, "anchor", "crate cycle anchor timer quality")
    assert_equal(model.announcements, [(2405, 404, "DETECTED")], "crate cycle anchor announcements")
    passed.append("crate cycle anchor anchors detected lifecycle")

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

    require(model.accept_state(2910, 2405, 501, "DETECTED", "CRATE_CYCLE_ANCHOR"), "authoritative anchor should replace fallback")
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
    require(model.accept_state(8000, 2395, 11065, "DETECTED", "CRATE_CYCLE_ANCHOR"), "crate cycle anchor setup should be accepted")
    require(model.accept_state(9043, 2395, 11065, "DROPPING", "DROPPING"), "non-monster earlier than rollover should replace previous timer regardless of old source")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.state, "DROPPING", "new post-guardian lifecycle should progress to dropping")
    assert_equal(rec.timer and rec.timer.start, 9043, "earlier non-monster lifecycle replaces previous timer")
    assert_equal(rec.timer and rec.timer.quality, "fallback", "non-monster replacement keeps fallback quality")
    passed.append("non-anchor evidence pulls timer earlier toward missed crate cycle anchor")

    require(model.accept_state(10153, 2395, 11065, "DROPPING", "DROPPING"), "post-rollover lifecycle should be accepted")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.timer and rec.timer.start, 9043, "post-rollover non-monster event must not move timer later")
    require(model.accept_state(11220, 2395, 11065, "DROPPING", "DROPPING"), "next pre-rollover lifecycle should be accepted")
    rec = model.records[(2395, 11065)]
    assert_equal(rec.timer and rec.timer.start, 11220, "later cycle can still move timer earlier once guardian age is reached")
    passed.append("non-anchor timer keeps pulling earlier toward crate cycle anchor when possible")

    model = ContractModel()
    require(model.accept_state(3000, 2405, 1, "DETECTED", "CRATE_CYCLE_ANCHOR"), "old shard lifecycle should start")
    require(model.accept_state(3010, 2405, 2, "DROPPING", "DROPPING"), "new shard fallback should not be blocked by old shard guardian")
    require((2405, 1) not in model.records, "new shard should remove old lifecycle for same zone")
    require((2405, 2) in model.records, "new shard lifecycle missing")
    assert_equal(model.active_timer_by_zone[2405], (2405, 2), "new shard should own visible timer")
    passed.append("new shard replaces old shard lifecycle and timer")

    model = ContractModel()
    require(model.accept_state(4000, 2405, 3, "DETECTED", "CRATE_CYCLE_ANCHOR"), "detected should start before plane guard test")
    require(not model.plane_seen(4002, 2405, 3, "plane-a", 0.62207, 0.93466), "guarded plane sighting 1 should be ignored")
    require(not model.plane_seen(4004, 2405, 3, "plane-a", 0.62207, 0.93466), "guarded plane sighting 2 should be ignored")
    require((2405, 3) not in model.plane_by_key, "guarded plane should not leave a counter")
    assert_equal(model.announcements, [(2405, 3, "DETECTED")], "guarded plane should not announce duplicate detected")
    passed.append("guardian blocks plane counter before confirmation")

    require(not model.plane_seen(4901, 2405, 3, "plane-b", 0.62207, 0.93466), "plane movement candidate starts after guardian")
    require(model.plane_seen(4903, 2405, 3, "plane-b", 0.62307, 0.93466), "same-guid movement should accept detected")
    assert_equal(model.records[(2405, 3)].timer and model.records[(2405, 3)].timer.start, 4903, "confirmed moving plane accepted timer")
    passed.append("same-guid plane movement confirms flying")

    model = ContractModel()
    require(not model.plane_seen(1000, 2405, 4, "plane-anchor", 0.62207, 0.93466), "anchor hold candidate starts")
    require(model.plane_seen(1002, 2405, 4, "plane-anchor", 0.62207, 0.93466), "two anchor ticks should accept flying")
    passed.append("same-guid anchor hold confirms flying")

    model = ContractModel()
    require(not model.plane_seen(1000, 2405, 5, "plane-drop", 0.5380, 0.6550), "drop hold candidate starts")
    require(not model.plane_seen(1002, 2405, 5, "plane-drop", 0.5380, 0.6550), "known drop hold should not accept flying")
    require((2405, 5) not in model.records, "known drop hold must not create lifecycle")
    passed.append("known drop hold waits for crate object evidence")

    model = ContractModel()
    require(not model.plane_seen(1000, 2405, 6, "plane-route", 0.5000, 0.5000), "known route hold candidate starts")
    require(model.plane_seen(1002, 2405, 6, "plane-route", 0.5000, 0.5000), "known en-route hold should accept flying")
    passed.append("known route hold confirms flying")

    model = ContractModel()
    require(not model.plane_seen(1000, 2405, 7, "plane-unknown", 0.7000, 0.7000), "unknown hold candidate starts")
    require(not model.plane_seen(1002, 2405, 7, "plane-unknown", 0.7000, 0.7000), "unknown hold should not accept flying")
    require((2405, 7) not in model.records, "unknown hold must not create lifecycle")
    passed.append("unknown plane hold stays pending")

    model = ContractModel()
    require(model.accept_state(5000, 2405, 9, "DETECTED", "CRATE_CYCLE_ANCHOR"), "rollover setup should start timer")
    assert_equal(model.next_expected(2405, 6101), 7200, "rollover should use previous expected timestamp plus duration")
    passed.append("timer rollover is based on previous expected timestamp")

    return passed


def read_source(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def read_source_optional(relative: str) -> str | None:
    path = ADDON / relative
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def source_section(source: str, start: str, end: str | None = None) -> str:
    start_idx = source.find(start)
    require(start_idx != -1, f"source section start not found: {start}")
    end_idx = len(source) if end is None else source.find(end, start_idx + len(start))
    require(end_idx != -1, f"source section end not found: {end}")
    return source[start_idx:end_idx]


def run_source_shape_checks() -> list[str]:
    passed: list[str] = []
    crate = read_source("constants/crate.lua")
    factions = read_source("constants/factions.lua")
    keys = read_source("constants/keys.lua")
    timing = read_source("constants/timing.lua")
    clock = read_source("utils/clock.lua")
    shardmap = read_source("logic/crateHandler/shardmap.lua")
    handler = read_source("logic/crateHandler/crateHandler.lua")
    expansions = read_source("gamedata/expansions.lua")
    prediction_model = read_source("gamedata/prediction.lua")
    route_metadata = read_source("gamedata/routeMetadata.lua")
    route_data = read_source("logic/routeData.lua")
    prediction_service = read_source("logic/prediction.lua")
    announce = read_source("logic/announce.lua")
    prediction_announce = read_source("logic/predictionAnnounce.lua")
    timers = read_source("logic/timers.lua")
    events = read_source("constants/events.lua")
    protocol = read_source("constants/protocol.lua")
    event_dispatch = read_source("events.lua")
    db = read_source("data/db.lua")
    config = read_source("config.lua")
    main = read_source("main.lua")
    comms = read_source("comms.lua")
    toc = (ADDON / "CrateRush.toc").read_text(encoding="utf-8")
    message_constants = read_source("constants/messages.lua")
    domain_state = read_source("logic/domainState.lua")
    diagnostics = read_source("logic/domainStateDiagnostics.lua")
    timerbars = read_source("ui/timerbars.lua")
    zone_resolver = read_source("logic/zoneResolver.lua")
    vignette_scanner = read_source("logic/vignetteScanner.lua")
    timer_policy = read_source("logic/timerPolicy.lua")
    shard_service = read_source("logic/shardService.lua")
    crate_lifecycle = read_source("logic/crateLifecycle.lua")
    transition_guard = read_source("logic/transitionGuard.lua")
    crate_cycle_anchor = read_source("logic/crateCycleAnchorService.lua")
    map_module = read_source("logic/crateHandler/map.lua")
    announcement_templates = read_source("logic/announcements/templates.lua")
    announcement_router = read_source("logic/announcements/router.lua")
    announcement_debug_sink = read_source("logic/announcements/sinks/debug.lua")
    announcement_chat_sink = read_source("logic/announcements/sinks/defaultChatFrame.lua")
    announcement_warning_sink = read_source("logic/announcements/sinks/warningFrame.lua")
    announcement_party_raid_sink = read_source("logic/announcements/sinks/partyRaid.lua")
    announcement_addon_comm_sink = read_source("logic/announcements/sinks/addonComm.lua")
    frames = read_source("ui/frames.lua")
    ui_layout = read_source("ui/layout.lua")
    ui_model = read_source("ui/model.lua")
    ui_actions = read_source("ui/actions.lua")
    cockpit = read_source("ui/cockpit.lua")
    theme = read_source("ui/theme.lua")
    config_dialog = read_source("ui/configDialog.lua")
    control_atlas = read_source("ui/controlAtlas.lua")
    player_context = read_source("logic/playerContext.lua")
    prediction_generator = (ROOT / "tools" / "generate_prediction_data.py").read_text(encoding="utf-8")

    libstub_idx = toc.find("Libs/LibStub/LibStub.lua")
    callback_idx = toc.find("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    ace_locale_idx = toc.find("Libs/AceLocale-3.0/AceLocale-3.0.lua")
    chat_throttle_idx = toc.find("Libs/AceComm-3.0/ChatThrottleLib.lua")
    ace_comm_idx = toc.find("Libs/AceComm-3.0/AceComm-3.0.lua")
    require(
        -1 not in (libstub_idx, callback_idx, ace_locale_idx, chat_throttle_idx, ace_comm_idx)
        and libstub_idx < callback_idx < ace_locale_idx < chat_throttle_idx < ace_comm_idx,
        "embedded Ace libraries must load self-contained dependencies before AceComm",
    )
    passed.append("embedded Ace libraries load without relying on another addon")

    main_idx = toc.find("main.lua")
    clock_idx = toc.find("utils/clock.lua")
    debug_idx = toc.find("debug.lua")
    data_idx = toc.find("data/db.lua")
    logic_idx = toc.find("logic/domainEvents.lua")
    require(
        -1 not in (main_idx, clock_idx, debug_idx, data_idx, logic_idx)
        and main_idx < clock_idx < debug_idx < data_idx < logic_idx,
        "clock helper must load before debug, data, and logic modules",
    )
    require("CrateRush.clock = clock" in clock and "function clock:serverTime" in clock, "clock helper must expose serverTime")
    clock_checked_sources = [
        ("crateLifecycle", crate_lifecycle),
        ("timers", timers),
        ("shardService", shard_service),
        ("vignetteScanner", vignette_scanner),
        ("transitionGuard", transition_guard),
        ("comms", comms),
        ("prediction", prediction_service),
    ]

    telemetry = read_source_optional("data/telemetry.lua")
    if telemetry is not None:
        clock_checked_sources.append(("telemetry", telemetry))

    for module_name, source in clock_checked_sources:
        require("GetServerTime(" not in source, f"{module_name} must use CrateRush.clock instead of raw GetServerTime")
        require("GetTime(" not in source, f"{module_name} must use CrateRush.clock instead of raw GetTime")
    passed.append("server-time clock is centralized for domain, storage, and comms-ready timestamps")

    factions_idx = toc.find("constants/factions.lua")
    crate_idx = toc.find("constants/crate.lua")
    player_context_idx = toc.find("logic/playerContext.lua")
    ui_theme_idx = toc.find("ui/theme.lua")
    require(
        -1 not in (factions_idx, crate_idx, player_context_idx, ui_theme_idx)
        and factions_idx < crate_idx
        and factions_idx < player_context_idx
        and factions_idx < ui_theme_idx,
        "canonical faction constants must load before crate constants, playerContext, and UI theme",
    )
    require("CrateRush.FACTION =" in factions and 'HORDE    = "HORDE"' in factions and 'ALLIANCE = "ALLIANCE"' in factions, "faction constants must declare canonical Horde/Alliance keys")
    require("CrateRush.FACTION_INFO" in factions and "CrateRush.normalizeFactionKey" in factions, "faction constants must own faction validation")
    require("CrateRush.FACTION_FALLBACK_KEY = CrateRush.FACTION.HORDE" in factions, "approved faction fallback must be Horde")
    require("function CrateRush.getFallbackFactionKey()" in factions, "fallback faction key must be exposed through a single helper")
    require("function CrateRush.resolveFactionKey(value)" in factions and "CrateRush.normalizeFactionKey(value) or CrateRush.getFallbackFactionKey()" in factions, "faction constants must expose one NO_FAIL_RETURN faction resolver")
    require("function CrateRush.resolveFactionName(value)" in factions, "faction constants must expose one no-fail faction name resolver")
    passed.append("faction constants own canonical keys, names, validation, fallback key, and no-fail resolver")

    keys_idx = toc.find("constants/keys.lua")
    db_idx = toc.find("data/db.lua")
    domain_state_idx = toc.find("logic/domainState.lua")
    require(
        -1 not in (keys_idx, db_idx, domain_state_idx)
        and keys_idx < db_idx < domain_state_idx,
        "shared crate key helper must load before storage and domainState",
    )
    require(
        "CrateRush.crateKeys = crateKeys" in keys
        and "function crateKeys:make" in keys
        and "function crateKeys:parseZone" in keys
        and "function crateKeys:sameShard" in keys,
        "shared crate key helper must expose make/parseZone/sameShard",
    )
    for module_name, source in (
        ("crateHandler", handler),
        ("shardService", shard_service),
        ("crateLifecycle", crate_lifecycle),
        ("timers", timers),
        ("prediction", prediction_service),
        ("domainState", domain_state),
        ("storage", db),
    ):
        require("local function sameShard" not in source, f"{module_name} must use shared crateKeys:sameShard")
    passed.append("shared crate key helper owns zone/shard key formatting")

    require('DETECTED            = "DETECTED"' in crate, "CRATE_STATE.DETECTED must exist")
    vignette_type_section = source_section(crate, "CrateRush.VIGNETTE_TYPE", "CrateRush.SCAN_TRIGGER")
    require("CRATE_CLAIMED_MARKER_ALLIANCE" in vignette_type_section and "CRATE_CLAIMED_MARKER_HORDE" in vignette_type_section, "claimed vignette constants must be named as scanner markers")
    require("CRATE_CLAIMED_BY_ALLIANCE" not in vignette_type_section and "CRATE_CLAIMED_BY_HORDE" not in vignette_type_section, "vignette marker names must stay distinct from lifecycle claimed state names")
    require("function CrateRush.isCrateStateClaimed" in crate and "function CrateRush.isCrateVignetteClaimed" in crate, "claimed state and vignette marker checks must be centralized")
    require("function CrateRush.getClaimedStateForVignette" in crate, "scanner claimed markers must convert to exact faction claimed states through one helper")
    require("function CrateRush.getPlayerRelativeClaimedStateForVignette" in crate, "scanner claimed markers must convert to player-relative claimed states through one helper")
    require("CRATE_CLAIMED_MARKER_ALLIANCE" in expansions and "CRATE_CLAIMED_MARKER_HORDE" in expansions, "vignette ID data must use scanner marker constants")
    require("CrateRush.getPlayerRelativeClaimedStateForVignette" in handler, "crateHandler must use the central scanner-to-lifecycle claimed conversion helper")
    for module_name, source in (
        ("shardService", shard_service),
        ("crateLifecycle", crate_lifecycle),
    ):
        require("CrateRush.isCrateVignetteClaimed" in source, f"{module_name} must use the central claimed-vignette helper")
    for module_name, source in (
        ("announce", announce),
        ("prediction", prediction_service),
        ("announcementTemplates", announcement_templates),
    ):
        require("CrateRush.isCrateStateClaimed" in source, f"{module_name} must use the central claimed-state helper")
    require(
        "LANDED_GONE_FLYING_CONFIRM_COUNT" in timing
        and "LANDED_GONE_EXPIRY_SECONDS" in timing,
        "landed-gone closure thresholds must be named timing constants",
    )
    require(
        "recordScanObservation" in handler
        and "crateLifecycle:onVignetteScanComplete" in handler,
        "crateHandler must pass scan observations to lifecycle for landed-gone closure",
    )
    require(
        "function lifecycle:onVignetteScanComplete" in crate_lifecycle
        and "trigger ~= CrateRush.SCAN_TRIGGER.VIGNETTES_UPDATED" in crate_lifecycle
        and "STATE_CLAIMED_BY_OPPOSITE_FACTION" in crate_lifecycle,
        "crateLifecycle must own landed-gone opposite-faction state closure from real vignette scans",
    )
    passed.append("CRATE_STATE.DETECTED exists")

    require("shouldAcceptLifecycleDetection" not in shardmap, "old mixed guardian function must not return")
    require("early_correction" not in crate.lower(), "old early_correction timer policy must not return")
    passed.append("old mixed lifecycle/timer policy names are absent")

    require("CRATE_STATE.DETECTED" in handler, "crate cycle anchor must transition to DETECTED")
    require("transition(crateZoneID, confirmedShardID, CRATE_STATE.FLYING" not in handler, "crate cycle anchor must not transition to FLYING")
    passed.append("crate cycle anchor creates DETECTED, not FLYING state")

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
    plane_log_idx = crate_lifecycle.find('zoneLog("PLANE_CANDIDATE zone="')
    require(guard_idx != -1 and plane_log_idx != -1 and guard_idx < plane_log_idx, "plane guardian check must happen before plane candidate logs")
    passed.append("plane guardian check precedes plane candidate tracking")

    map_idx = toc.find("logic/crateHandler/map.lua")
    announcement_templates_idx = toc.find("logic/announcements/templates.lua")
    announcement_router_idx = toc.find("logic/announcements/router.lua")
    announcement_debug_sink_idx = toc.find("logic/announcements/sinks/debug.lua")
    announcement_chat_sink_idx = toc.find("logic/announcements/sinks/defaultChatFrame.lua")
    announcement_warning_sink_idx = toc.find("logic/announcements/sinks/warningFrame.lua")
    announcement_party_raid_sink_idx = toc.find("logic/announcements/sinks/partyRaid.lua")
    announcement_addon_comm_sink_idx = toc.find("logic/announcements/sinks/addonComm.lua")
    announce_idx = toc.find("logic/announce.lua")
    prediction_announce_idx = toc.find("logic/predictionAnnounce.lua")
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
            prediction_announce_idx,
        )
        and map_idx
        < announcement_templates_idx
        < announcement_router_idx
        < announcement_debug_sink_idx
        < announcement_chat_sink_idx
        < announcement_warning_sink_idx
        < announcement_party_raid_sink_idx
        < announcement_addon_comm_sink_idx
        < announce_idx
        < prediction_announce_idx,
        "announcement modules must load map -> templates -> router -> sinks -> service",
    )
    require("CrateRush.announcementTemplates:build(payload)" in announce, "announce service must delegate message building to templates")
    require("CrateRush.announcementRouter:route(announcement)" in announce, "announce service must route finalized announcement through router")
    for forbidden in ("DEFAULT_CHAT_FRAME", "SendChatMessage", "CrateRush.warningframe", "CrateRush.comms"):
        require(forbidden not in announce, f"announce service must not call output sink {forbidden}")
    require("CRATE_STATE.DETECTED or state == CRATE_STATE.FLYING" in announcement_templates, "detected announcement must key from DETECTED")
    require("lifecycleStartedAt" in announce, "announcement cycle key must use lifecycle identity")
    require("includeMapPinInDropAndLandedAnnouncements" in announcement_templates and '"%coordinates%"' in announcement_templates, "dropping/landed announcements must append configurable map pin links and expose coordinate placeholder")
    require("appendLocation" in announcement_templates and '"%mappin%"' in announcement_templates, "dropping/landed announcements must build one finalized coordinate plus map-pin location segment")
    require("buildPrediction" in announcement_templates and "includeMapPinInPredictionAnnouncements" in announcement_templates, "prediction announcements must use templates and map pin output")
    require("localOnly = false" in announcement_templates, "prediction announcements must be eligible for configured output sinks")
    prediction_message_template = source_section(
        message_constants,
        "MESSAGE_ID.PREDICTION,",
        "cockpitTriggers = {",
    )
    require('"Predicted drop in %zone%' in prediction_message_template and "Predicted War Crate" not in prediction_message_template, "prediction chat message must omit the words War Crate")
    require("[shard" not in prediction_message_template and (chr(124) + " route") not in prediction_message_template, "prediction chat message must stay compact and omit shard/route text")
    require(chr(124) not in prediction_message_template and " / drop " not in prediction_message_template and " / land " not in prediction_message_template, "prediction chat message must not use pipe or slash separators")
    build_prediction_template = source_section(
        announcement_templates,
        "function templates:buildPrediction",
        None,
    )
    require('formatCoord(payload.dropX) .. "/" .. formatCoord(payload.dropY)' in build_prediction_template, "prediction chat coordinates must be compact without spaces")
    require("PREDICTION_UPDATED" in prediction_announce and "CrateRush.announcementRouter:route(announcement)" in prediction_announce, "prediction announce service must subscribe and route finalized prediction output")
    require("PREDICTION_CLEARED" in prediction_announce and "onPredictionCleared" in prediction_announce, "prediction announcement cache must clear with prediction lifecycle")
    require("shouldAnnouncePrediction" in prediction_announce and "getLocationSignature" in prediction_announce, "prediction announcements must de-dupe by lifecycle and drop location")
    require("buildPrediction(payload)" in prediction_announce and prediction_announce.find("shouldAnnouncePrediction(payload)") < prediction_announce.find("buildPrediction(payload)"), "prediction announcements must de-dupe before building map-pin output")
    require("localOnly" in announcement_party_raid_sink and "localOnly" in announcement_addon_comm_sink, "announcement sinks must still support future local-only messages")
    require("setWaypointAndCreateLink" in map_module and "UiMapPoint.CreateFromCoordinates" in map_module, "map helper must expose explicit waypoint-setting link generation")
    require("Side effect: keep the waypoint active" in map_module and "ClearUserWaypoint" not in map_module, "map pin helper must leave the player's waypoint active")
    require("getMapPinLocation" not in map_module and "getMapPinLocation" not in announcement_templates, "map pin helper name must not imply read-only behavior")
    require("setWaypointAndCreateLink" not in crate_lifecycle and "worldmap:" not in crate_lifecycle, "lifecycle must not build map pin links")
    require("registerSink" in announcement_router and "function router:route" in announcement_router, "announcement router must own sink fan-out")
    announce_state_change = source_section(
        announce,
        "function announce:onStateChange",
        "if CrateRush.domainEvents",
    )
    require(
        "isNotificationEnabled" in announce
        and "CrateRush.announcementMessageConfig:isEnabled(messageID)" in announce
        and announce_state_change.find("isNotificationEnabled(state)") < announce_state_change.find("shouldAnnounce(zoneID, shardID, state, payload)"),
        "announce service must apply notification toggles before de-duplication",
    )
    require("wasCrateStateAnnounced" in db and "recordCrateStateAnnouncement" in db, "storage must persist per-lifecycle announcement memory")
    require("wasPersistedAnnouncement" in announce and "persistAnnouncement" in announce, "announce service must use persisted announcement memory across reloads")
    require("recordCrateStateAnnouncement(payload, cycleKey, state" in announce, "announce service must persist accepted state announcements")
    require("ANNOUNCE |" in announcement_debug_sink, "debug announcement sink must own debug output")
    require("DEFAULT_CHAT_FRAME:AddMessage" in announcement_chat_sink, "default chat frame sink must own local clickable chat output")
    require("CrateRush.warningframe:show" in announcement_warning_sink and "showWarningFrame" in announcement_warning_sink, "warning frame sink must own configurable warning output")
    require("SendChatMessage" in announcement_party_raid_sink, "party/raid sink must own chat send output")
    require("SendChatMessage, announcement.message" in announcement_party_raid_sink, "party/raid sink must send finalized announcement text including map pin links")
    require("chatMessage" not in announcement_templates and "chatMessage" not in announcement_party_raid_sink, "party/raid output must not use a stripped chat-only message variant")
    require("announcement.forcePartyRaid" in announcement_party_raid_sink, "party/raid sink must honor forced group-chat prediction output")
    require("if not manualForced and not hasRaidAuthority() then" in announcement_party_raid_sink and 'return nil, "raid_not_leader_or_assistant"' in announcement_party_raid_sink, "party/raid sink must not spam automatic RAID when player is not lead or assist")
    require("return CHAT_CHANNEL.RAID_WARNING" in announcement_party_raid_sink, "party/raid sink should use raid warning for lead or assist")
    require("return CHAT_CHANNEL.RAID" in announcement_party_raid_sink and "return CHAT_CHANNEL.PARTY" in announcement_party_raid_sink, "party/raid sink should support forced raid output and party fallback")
    require("CrateRush.comms.send" in announcement_addon_comm_sink, "addon comm sink must own future addon-to-addon output")
    require("crateKeys:make" in announce and "local function getCrateKey" not in announce, "announce service must use shared crate key helper")
    require("C_Map.GetMapInfo" not in announcement_templates and "CrateRush.zoneResolver:getCrateZoneName" in announcement_templates, "announcement templates must use zoneResolver for zone names")
    passed.append("announcements are lifecycle keyed")

    require("crateKeys:make" in db and "makeCrateKey" not in db, "storage must use the shared crate key helper")
    require("removeOtherCratesForZone" in db, "storage must retain one active shard per zone")
    require("keysToRemove" in db, "storage must collect keys before deleting records during iteration")
    require("byZone" in db and "zoneShards" in db and "getRecordTimestamp" in db, "storage migration must collapse old duplicate zone timers")
    require("DEFAULT_PROFILE" in db and "applyDefaults" in db, "storage must own SavedVariables profile defaults")
    require("CrateRushDB.profile" not in main and "profile = {" not in main, "main must not create or mutate SavedVariables profile defaults")
    require("CrateRush.storage:init(CrateRushDB)" in main, "main may only pass the SavedVariables root to storage")
    passed.append("storage contract is zone/shard keyed, deduped by zone, and owns profile bootstrap")

    protocol_idx = toc.find("constants/protocol.lua")
    comms_idx = toc.find("comms.lua")
    events_idx = toc.find("\nevents.lua")
    require(
        -1 not in (protocol_idx, comms_idx, events_idx)
        and protocol_idx < comms_idx < events_idx,
        "protocol constants must load before comms, and comms before WoW event dispatch",
    )
    require('PROTO.PREFIX = "CRATERUSH"' in protocol, "CrateRush native protocol prefix must be CRATERUSH")
    require('PROTO.VERSION = "1"' in protocol, "CrateRush protocol version must be explicit")
    require("TOKEN_REQUEST" in protocol and "TOKEN_UPDATE" in protocol, "protocol management must define token request/update")
    for timer_message in ("TIMER_SYNC_REQUEST", "TIMER_SYNC_RESPONSE", "TIMER_DELETE"):
        require(timer_message in protocol, f"{timer_message} must be defined for timer sync/delete phase")
    require("CRATE_CYCLE_ANCHOR" in protocol, "crate cycle anchor must be defined for remote anchor phase")
    for future_message in ("TIMER_UPDATE",):
        require(future_message not in protocol, f"{future_message} must not be wired before its implementation phase")
    require("AceSerializer" not in comms, "CrateRush protocol payloads must not use AceSerializer")
    require('FIELD_SEPARATOR = ";"' in comms and 'KEY_VALUE_SEPARATOR = "="' in comms, "CrateRush must own key/value protocol encoding")
    require("function comms:Encode" in comms and "function comms:Decode" in comms, "comms must expose encode/decode helpers")
    require("function comms:CreateGroupToken" in comms and "function comms:HashToken" in comms, "token creation and hashing must be centralized")
    require("CrateRush.clock:serverTime()" in comms, "token management must use the shared clock helper")
    require("CrateRush:RegisterComm(PROTO.PREFIX" in comms, "comms must register the CrateRush prefix")
    require("CrateRush.comms:init()" in main and "CrateRush.comms:onReceive" in main, "main must initialize and delegate AceComm to comms")
    require("CrateRush.EVT.NPC_ANNOUNCEMENT" in event_dispatch, "raw NPC announcement dispatch must stay separate from comms")
    require("CrateRush.comms:onPlayerEnteringWorld" in event_dispatch, "protocol context must refresh on entering world")
    require("CrateRush.comms:onGroupRosterUpdate" in event_dispatch, "protocol context must refresh on group roster changes")
    require("PLAYER_FLAGS_CHANGED" in events and "player_flags_changed" in event_dispatch, "protocol context must refresh when player PvP/War Mode flags change")
    require("CrateRush.playerContext:isWarModeEnabled()" in comms and "C_PvP" not in comms, "protocol War Mode gating must consume playerContext")
    require("IsInGroup" in comms and "IsInRaid" in comms, "protocol must require party/raid group context")
    require("UnitIsGroupLeader" in comms and "TOKEN_REQUEST" in comms and "TOKEN_UPDATE" in comms, "protocol management must be leader-token based")
    require("TOKEN_REQUEST_THROTTLE_SECONDS" in protocol and "TOKEN_REQUEST_MAX_ATTEMPTS" in protocol, "token request throttle and retry cap must be named constants")
    require("tokenRequestExhausted" in comms, "token request max attempts must become terminal for the current request context")
    require("self.tokenRequestExhausted then" in comms and "self.tokenRequestExhausted = true" in comms, "token request exhaustion must stop repeated max-attempt tries")
    require("comms.tokenRequestExhausted = false" in comms, "token request exhaustion must reset when protocol request context resets")
    require("TIMER_SYNC_REQUEST_THROTTLE_SECONDS" in protocol and "sendTimerSyncRequest" in comms, "timer sync request throttle must be named and implemented")
    require("senderGUID" in comms and "UnitGUID" in comms and "resolveSenderGUID" in comms, "protocol identity must validate senderGUID against current group units")
    require("groupToken" in comms and "TOKEN_WIPE" in comms, "protocol must keep and wipe one local group token")
    refresh_context = source_section(
        comms,
        "function comms:refreshProtocolContext",
        "function comms:onPlayerEnteringWorld",
    )
    member_roster_idx = refresh_context.find('if reason == "group_roster_update" then')
    member_context_idx = refresh_context.find("ensureRequestContext(reason)", member_roster_idx)
    member_request_idx = refresh_context.find("self:sendTokenRequest(reason)", member_roster_idx)
    require(
        -1 not in (member_roster_idx, member_context_idx, member_request_idx)
        and member_roster_idx < member_context_idx < member_request_idx,
        "non-leader group roster updates must return before request context reset and token request",
    )
    require("lastMemberRosterContextKey" in comms and "return self.groupToken ~= nil" in refresh_context, "member group roster updates must be passive and not request tokens")
    require('wipeToken("context_changed")' not in comms, "members must not wipe tokens on roster context changes")
    require("lastGroupRosterLogAt" in handler and ">= 60" in handler, "group roster debug logging must be throttled")
    require("NORMAL_TYPES" in comms and "validateNormalMessage" in comms and "group_token_mismatch" in comms, "normal sync messages must validate current group token")
    require("encodeTimerList" in comms and "decodeTimerList" in comms, "timer sync response must use owned timer-list encoding")
    require("handleTimerSyncRequest" in comms and "sendTimerSyncResponse" in comms, "leader must answer timer sync requests")
    require("TIMER_SYNC_RECEIVED" in events and "TIMER_SYNC_RECEIVED" in comms and "applyRemoteSnapshot" in timers, "timer sync response must enter timer service through a domain event")
    require("handleTimerDelete" in comms and "GROUP_TIMER_DELETE" in crate and "removeZone" in timers, "timer delete must route zone removal through the timer service")
    require("sendCrateCycleAnchor" in comms and "handleCrateCycleAnchor" in comms, "crate cycle anchor must have send/receive protocol handlers")
    require("serverEventTime" in comms and "serverEventTime" in crate_lifecycle, "remote crate cycle anchors must use the sender server event time")
    require("accepted and CrateRush.comms and CrateRush.comms.sendCrateCycleAnchor" in handler, "local accepted crate cycle anchors must broadcast through comms")
    require("CrateRush.crateLifecycle:transition(" in comms and "CrateRush.CRATE_SOURCE.CRATE_CYCLE_ANCHOR" in comms, "remote crate cycle anchors must enter the crate lifecycle as CRATE_CYCLE_ANCHOR")
    anchor_handler = source_section(
        comms,
        "function comms:handleCrateCycleAnchor",
        "function comms:onReceive",
    )
    require("shardService" not in anchor_handler and "acceptCrateEventShard" not in anchor_handler, "remote crate cycle anchors must not mutate current-zone shard confirmation directly")
    require("SEND_UNSUPPORTED" in comms and "timer_sync_protocol" in comms, "messages outside implemented timer sync/delete phase must stay unsupported")
    passed.append("CrateRush protocol owns token management, timer sync/delete, and crate cycle anchors")

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
    require("function config:apply(" in config, "config gateway must expose batch apply for staged UI edits")
    require("CONFIG_CHANGED" in events and "configChanged" in events, "config changed domain event must be named")
    require("publishConfigChanged" in config and "CrateRush.domainEvents:publish(CrateRush.DOMAIN_EVENT.CONFIG_CHANGED" in config, "config gateway must publish config changes after storage writes")
    require("previousValue" in config and "defaultValue" in config and "source" in config, "config changed payload must include previous/default/source context")
    require("subscribeConfigChanged" in main and "OnConfigChanged" in main, "main must subscribe to configChanged through the domain event bus")
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

    ui_theme_idx = toc.find("ui/theme.lua")
    ui_control_atlas_idx = toc.find("ui/controlAtlas.lua")
    ui_layout_idx = toc.find("ui/layout.lua")
    ui_model_idx = toc.find("ui/model.lua")
    ui_actions_idx = toc.find("ui/actions.lua")
    ui_config_idx = toc.find("ui/configDialog.lua")
    ui_cockpit_idx = toc.find("ui/cockpit.lua")
    ui_frames_idx = toc.find("ui/frames.lua")
    player_context_idx = toc.find("logic/playerContext.lua")
    zone_resolver_idx = toc.find("logic/zoneResolver.lua")
    require(
        -1 not in (player_context_idx, zone_resolver_idx, ui_theme_idx, ui_control_atlas_idx, ui_layout_idx, ui_model_idx, ui_actions_idx, ui_config_idx, ui_cockpit_idx, ui_frames_idx)
        and player_context_idx < zone_resolver_idx
        and ui_theme_idx < ui_control_atlas_idx < ui_layout_idx < ui_model_idx < ui_actions_idx < ui_config_idx < ui_cockpit_idx < ui_frames_idx,
        "playerContext and UI theme/control/layout/model/action/config/cockpit modules must load in dependency order",
    )
    require("UnitFactionGroup" in player_context, "playerContext must derive the real player faction")
    require("setFactionOverride" in player_context and "clearFactionOverride" in player_context, "playerContext must own faction debug override")
    require("getFactionKey" in player_context and "isFactionOverridden" in player_context, "playerContext must expose faction context")
    require("getEffectiveFactionKey" in player_context and "CrateRush.resolveFactionKey(overrideFactionKey or actualFactionKey)" in player_context, "playerContext must return a NO_FAIL_RETURN effective faction key")
    require("CrateRush.resolveFactionName" in player_context, "playerContext effective faction name must be NO_FAIL_RETURN")
    require("actualFactionKey = nil" in player_context, "real player faction must start unknown until WoW supplies it")
    require("CrateRush.normalizeFactionKey" in player_context and "local FACTIONS" not in player_context, "playerContext must consume canonical faction validation instead of local faction tables")
    require('or "ALLIANCE"' not in player_context and 'or "HORDE"' not in player_context and "FACTIONS.ALLIANCE" not in player_context, "playerContext must not contain local raw faction fallback logic")
    require("PLAYER_CONTEXT_CHANGED" in events and "playerContextChanged" in events, "player context change event must be named")
    require("publishIfChanged" in player_context and "PLAYER_CONTEXT_CHANGED" in player_context, "playerContext must publish context changes")
    require("function playerContext:onPlayerEnteringWorld" in player_context, "playerContext must expose player entering world refresh")
    require("function playerContext:onPlayerFlagsChanged" in player_context and "function playerContext:onZoneChanged" in player_context, "playerContext must expose War Mode refresh boundaries")
    require("C_PvP.IsWarModeDesired" in player_context and "function playerContext:isWarModeEnabled" in player_context, "playerContext must own War Mode state")
    require("CrateRush.playerContext:onPlayerEnteringWorld" in event_dispatch, "events.lua must dispatch PLAYER_ENTERING_WORLD to playerContext")
    require("CrateRush.playerContext:onPlayerFlagsChanged" in event_dispatch and "CrateRush.playerContext:onZoneChanged" in event_dispatch, "events.lua must dispatch War Mode relevant events to playerContext")
    require("subscribePlayerContextChanged" in main and "OnPlayerContextChanged" in main, "main must wire playerContextChanged to UI/theme refresh")
    require("UnitFactionGroup" not in theme, "theme must not read raw player faction")
    require("setDebugOverride" not in theme and "function theme:setFaction" not in theme, "theme must not own faction overrides")
    require("fallbackTheme" not in theme and "CrateRush.getFallbackFactionKey" not in theme, "theme must not own fallback policy")
    require('return "ALLIANCE"' not in theme and 'return "HORDE"' not in theme, "theme must not return raw faction fallback keys")
    require("local FACTION = CrateRush.FACTION" in theme and "THEMES[getResolvedFactionKey()]" in theme, "theme must map resolved canonical faction keys to visual theme tables")
    require("CrateRush.playerContext:getFactionKey()" in theme, "theme must consume playerContext faction key")
    require("CrateRush.theme:init()" in main, "main must resolve faction theme during initialization")
    require("applyAddonMetadata(addonName)" in main and "C_AddOns.GetAddOnMetadata" in main and "GetAddOnMetadata" in main, "main must read addon title/version metadata from TOC")
    require('cmd == "horde"' not in main and 'cmd == "alliance"' not in main and "CrateRush:SetFactionOverride" in main, "working slash commands must not expose faction override testing")
    set_override_idx = main.find("function CrateRush:SetFactionOverride")
    clear_override_idx = main.find("function CrateRush:ClearFactionOverride")
    slash_idx = main.find("function CrateRush:SlashCommand")
    require(
        -1 not in (set_override_idx, clear_override_idx, slash_idx)
        and "theme:init" not in main[set_override_idx:clear_override_idx]
        and "applyThemeToUI" not in main[set_override_idx:clear_override_idx]
        and "theme:init" not in main[clear_override_idx:slash_idx]
        and "applyThemeToUI" not in main[clear_override_idx:slash_idx],
        "slash faction override commands must not apply theme/UI directly",
    )
    require("getHeaderTopTexture" in theme and "getConfigBackgroundTexture" in theme, "theme must expose header and config media")
    require("horde_top" in theme and "alliance_top" in theme, "theme must expose faction header artwork")
    require("config_background_horde" in theme and "config_background_alliance" in theme, "theme must expose faction config backgrounds")
    require("controls_horde" in theme and "controls_alliance" in theme, "theme must expose faction control atlases")
    for module_name, source in (
        ("frames", frames),
        ("model", ui_model),
        ("configDialog", config_dialog),
        ("timerbars", timerbars),
        ("cockpit", cockpit),
        ("layout", ui_layout),
        ("controlAtlas", control_atlas),
        ("actions", ui_actions),
    ):
        lower_source = source.lower()
        require("horde" not in lower_source and "alliance" not in lower_source, f"{module_name} must not contain faction-specific decision/fallback text")
        require("unitfactiongroup" not in lower_source, f"{module_name} must not read raw player faction")
        require("alliance_top" not in lower_source and "horde_top" not in lower_source, f"{module_name} must not own faction media fallback constants")
    require("local UI_COLORS" in theme and "function theme:getUIColors" in theme and "function theme:getUIColor" in theme, "theme must expose shared UI color tokens")
    for color_group in ("neutral", "header", "shardStatus", "timerRows", "cockpit", "zone", "sync"):
        require(color_group in theme, f"theme UI colors must include {color_group}")
    require("CrateRush.controlAtlas = controlAtlas" in control_atlas and "SetTexCoord" in control_atlas, "controlAtlas must own themed control atlas coordinates")
    require("CrateRush.layout = layout" in ui_layout and "layout.header" in ui_layout and "layout.timerRows" in ui_layout and "layout.cockpit" in ui_layout, "UI layout must expose visual layout groups")
    for forbidden in ("CrateRush.crateLifecycle", "CrateRush.shardService", "CrateRush.timers", "CrateRush.prediction", "CrateRush.comms", "CrateRush.storage", "CrateRush.domainState", "CrateRush.config"):
        require(forbidden not in ui_layout, f"UI layout must not call runtime service: {forbidden}")
    require("CrateRush.layout.header" in frames and "CrateRush.layout.timerRows" in timerbars and "CrateRush.layout.cockpit" in cockpit, "renderers must consume shared UI layout constants")
    require("CrateRush.theme:getUIColors()" in frames and "uiColors.shardStatus" in frames, "header renderer must consume shared theme colors")
    require("CrateRush.theme:getUIColors()" in timerbars and "uiColors.timerRows" in timerbars, "timerbar renderer must consume shared theme colors")
    require("CrateRush.theme:getUIColors().cockpit" in cockpit, "cockpit renderer must consume shared theme colors")
    require("local COLORS = {" not in frames and "local COLORS = {" not in cockpit, "renderers must not duplicate local color tables")
    require("BAR_COLOR" not in timerbars and "WARN_COLOR" not in timerbars and "URGENT_COLOR" not in timerbars and "BAR_BG" not in timerbars, "timerbars must not duplicate local color constants")
    require("CrateRush.uiModel = model" in ui_model and "function model:formatHeader" in ui_model and "function model:formatTimerRows" in ui_model, "UI model must expose prepared display formatters")
    require("function model:getCockpitPlaceholder" in ui_model, "UI model must expose safe cockpit placeholders")
    require("C_PvP" not in ui_model and "IsWarModeDesired" not in ui_model and "CrateRush.playerContext:isWarModeEnabled()" in ui_model, "UI model must consume War Mode from playerContext")
    require("CrateRush.crateLifecycle" not in ui_model and "CrateRush.prediction" not in ui_model and "CrateRush.comms" not in ui_model and "CrateRush.storage" not in ui_model, "UI model must not become a hidden domain layer")
    require("CrateRush.uiActions = actions" in ui_actions and "function actions:requestTimerRemoval" in ui_actions, "UI actions must own UI command requests")
    require("CrateRush.timers" not in ui_actions and "CrateRush.storage" not in ui_actions and "CrateRush.crateLifecycle" not in ui_actions, "UI actions must not mutate domain state directly")
    require("CrateRush.cockpit = cockpit" in cockpit and "uiModel:getCockpitPlaceholder()" in cockpit, "cockpit must render display placeholder data through uiModel")
    for forbidden in ("CrateRush.crateLifecycle", "CrateRush.shardService", "CrateRush.timers", "CrateRush.prediction", "CrateRush.comms", "CrateRush.storage", "CrateRush.domainState"):
        require(forbidden not in cockpit, f"cockpit renderer must not call core service: {forbidden}")
    require("CrateRush.cockpit:show()" in frames and "CrateRush.cockpit:hide()" in frames, "main frame show/hide must own cockpit visibility")
    require("function frames:show()" in frames and "CrateRush.timerbars:showContainer()" in frames, "main frame show must preserve timer container visibility")
    require("function frames:hide()" in frames and "CrateRush.timerbars:hideContainer()" in frames, "main frame hide must hide timer container")
    require("function frames:toggle()" in frames and "frames:hide()" in frames and "frames:show()" in frames, "main frame toggle entry point must remain")
    close_button_section = source_section(frames, "local closeButton", "local settingsButton")
    require("closeButton:SetScript(\"OnClick\"" in frames and "frames:hide()" in close_button_section, "close button must hide the main UI")
    require("frame:RegisterForDrag(\"LeftButton\")" in frames and "frame:SetScript(\"OnDragStart\", frame.StartMoving)" in frames and "frame:SetScript(\"OnDragStop\", frame.StopMovingOrSizing)" in frames, "main frame drag behavior must remain")
    require("RegisterEvent" not in frames, "UI frames must not register raw WoW gameplay events")
    require("HookScript(\"OnDragStop\"" in timerbars and "HookScript(\"OnDragStop\"" in cockpit, "attached timer/cockpit frames must stay anchored after main-frame drag")
    require("local uiModel = CrateRush.uiModel" in frames and "uiModel:formatHeader" in frames, "header frame must consume prepared UI header display")
    require("local uiActions = CrateRush.uiActions" in frames and "uiActions:openSettings()" in frames, "settings button must route through UI actions")
    require("CrateRush.configDialog = dialog" in config_dialog, "config dialog must be registered as a UI adapter")
    require("CrateRush.onSettingsClicked" in config_dialog and "dialog:toggle()" in config_dialog and "CrateRush.configDialog:toggle()" in ui_actions, "settings button must open config dialog through UI actions")
    require('cmd == "config"' in main and "CrateRush.configDialog:toggle()" in main, "slash command must open config dialog")
    require('cmd == "display"' in main and "CrateRush.frames:toggle()" in main, "slash display command must toggle main UI")
    for forbidden in ("CrateRush.storage", "storage:get(", "storage:set("):
        require(forbidden not in config_dialog, f"config dialog must not access storage directly: {forbidden}")
    require("CrateRush.config:set" in config_dialog and "CrateRush.config:get(" in config_dialog, "config dialog must read/write through config gateway")
    require("CrateRush.config:apply" in config_dialog, "config dialog must batch staged edits through the config gateway")
    require("CrateRush.frames" not in config_dialog and "domainEvents:publish" not in config_dialog, "config dialog must not directly mutate UI/runtime through config apply")
    require("pendingValues" in config_dialog and "applyPendingValues" in config_dialog, "config dialog must stage edits before applying settings")
    require("UIPanelScrollFrameTemplate" in config_dialog, "config dialog must support scrollable pages")
    require("announceToPartyRaid" in announcement_party_raid_sink, "party/raid announcement sink must honor config")
    passed.append("player context, faction theme, and config dialog follow UI/config ownership")

    require("CrateRush.frames" not in handler, "crateHandler must not call UI frames directly")
    require("CrateRush.timerbars" not in handler, "crateHandler must not call timerbars directly")
    require("ZONE_SHARD_STATUS_CHANGED" not in handler, "crateHandler must not publish header state directly")
    require("ZONE_SHARD_STATUS_CHANGED" in shard_service, "shardService should publish header state through domain events")
    require("onZoneShardStatusChanged" in frames, "header UI must subscribe to zone shard status events")
    require("CrateRush.DOMAIN_EVENT.ZONE_SHARD_STATUS_CHANGED" in frames and "frames:setZoneShard" in frames, "header refresh must remain event-driven")
    require("CrateRush.DOMAIN_EVENT.ACTIVE_TIMER_CHANGED" in timerbars and "onActiveTimerChanged" in timerbars, "timer row refresh must remain event-driven")
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

    prediction_model_idx = toc.find("gamedata/prediction.lua")
    zones_idx = toc.find("gamedata/zones.lua")
    require(
        -1 not in (zones_idx, prediction_model_idx, db_idx)
        and zones_idx < prediction_model_idx < db_idx,
        "prediction model data must load with gamedata before runtime services",
    )
    for required_table in (
        "CrateRushZoneCycleSeconds",
        "CrateRushDropClusters",
        "CrateRushRoutes",
        "CrateRushRouteCellIndex",
        "CrateRushClaimedTimerDefaults",
    ):
        require(required_table in prediction_model, f"prediction model data must define {required_table}")
    require(
        "CrateRushZoneCycleSeconds = CrateRush.ZONE_FREQUENCY or {}" in prediction_model
        and "CrateRushZoneCycleSeconds = {" not in prediction_model,
        "prediction model must alias cycle seconds from CrateRush.ZONE_FREQUENCY instead of duplicating values",
    )
    require("cycleSeconds" not in prediction_model, "prediction model must not emit duplicate zone cycle seconds")
    require("secondsToLanded" not in prediction_model and "secondsToLand" in prediction_model, "prediction model must normalize landed ETA field names")
    require("CrateRushPredictionModelInfo" in prediction_model, "prediction model must expose generated model metadata")
    require(
        "generate_prediction_data.py" in prediction_model
        and "CrateRush.ZONE_FREQUENCY" in prediction_generator
        and "secondsToLanded" in prediction_generator
        and "secondsToLand" in prediction_generator,
        "prediction data must be generated repeatably without owning timer cycle values",
    )

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
    require(
        "VIGNETTE_SEEN_CACHE_MAX_AGE_SECONDS" in timing
        and "VIGNETTE_SEEN_CACHE_MAX_ENTRIES" in timing
        and "pruneSeenGUIDs" in vignette_scanner
        and "seenGUIDCount" in vignette_scanner,
        "vignetteScanner seen-GUID cache must be bounded by named timing constants",
    )
    passed.append("vignetteScanner owns raw vignette reading and classification")

    timer_policy_idx = toc.find("logic/timerPolicy.lua")
    shard_service_idx = toc.find("logic/shardService.lua")
    route_data_idx = toc.find("logic/routeData.lua")
    crate_lifecycle_idx = toc.find("logic/crateLifecycle.lua")
    transition_guard_idx = toc.find("logic/transitionGuard.lua")
    crate_cycle_anchor_idx = toc.find("logic/crateCycleAnchorService.lua")
    prediction_service_idx = toc.find("logic/prediction.lua")
    shardmap_idx = toc.find("logic/crateHandler/shardmap.lua")
    require(
        -1 not in (timer_policy_idx, shard_service_idx, route_data_idx, crate_lifecycle_idx, transition_guard_idx, crate_cycle_anchor_idx, prediction_service_idx, shardmap_idx, crate_handler_idx)
        and vignette_scanner_idx < timer_policy_idx < shard_service_idx < route_data_idx < crate_lifecycle_idx < transition_guard_idx < crate_cycle_anchor_idx < prediction_service_idx < shardmap_idx < crate_handler_idx,
        "Step 7 services must load before crateHandler orchestration",
    )
    require("zoneShardCheck" not in handler and "zoneConfirm" not in handler, "crateHandler must not own shard confirmation state")
    require("zoneShardCheck" in shard_service and "zoneConfirm" in shard_service, "shardService must own shard confirmation state")
    require("shardService:processShardEvidence" in handler, "crateHandler must delegate shard evidence to shardService")
    require("crateKeys:sameShard" in handler, "crateHandler must use shared shard comparison")
    require("crateKeys:sameShard" in shard_service, "shardService must use shared shard comparison")
    require("recentPlane" not in handler and "recentPlane" in crate_lifecycle, "crateLifecycle must own plane confirmation state")
    require("gamedata/routeMetadata.lua" in toc and "CrateRushZoneAnchors" in route_metadata, "route metadata must define zone anchors in the addon load path")
    require("PLANE_POSITION_TOLERANCE_DEGREES" in timing and "PLANE_CONFIRM_REQUIRED_SIGHTINGS" not in timing, "flying confirmation must use position tolerance, not raw sighting count")
    require("CrateRush.routeData = routeData" in route_data, "routeData service must register as CrateRush.routeData")
    for required_api in (
        "mapDistanceDegrees",
        "getZoneAnchor",
        "getCellKeys",
        "getCellCandidates",
        "isNearKnownDrop",
        "classifyPlanePoint",
    ):
        require(required_api in route_data, f"routeData must expose {required_api}")
    require("CrateRush.routeData" in crate_lifecycle and "classifyPlanePoint" in crate_lifecycle, "crateLifecycle must use routeData for plane confirmation")
    require("PLANE_CONFIRM_REQUIRED_SIGHTINGS" not in crate_lifecycle and "count=3" not in crate_lifecycle, "crateLifecycle must not restore the old 3x flying counter")
    plane_handler = source_section(
        handler,
        "local function processPlaneSighting",
        "local function processObjectSighting",
    )
    non_map_guard_idx = plane_handler.find("trigger ~= SCAN_TRIGGER.VIGNETTES_UPDATED")
    plane_seen_idx = plane_handler.find("crateLifecycle:onPlaneSeen")
    prediction_idx = plane_handler.find("prediction:onPlaneSighting")
    require(
        -1 not in (non_map_guard_idx, plane_seen_idx, prediction_idx)
        and non_map_guard_idx < plane_seen_idx < prediction_idx,
        "plane confirmation and prediction must only run for real VIGNETTES_UPDATED map updates",
    )
    require("sighting.guid, sighting.x, sighting.y" in plane_handler, "crateHandler must pass plane coordinates into lifecycle confirmation")
    require("CrateRush.CRATE_CYCLE_ANCHOR_PHRASES" not in handler and "CrateRush.CRATE_CYCLE_ANCHOR_PHRASES" in crate_cycle_anchor, "crateCycleAnchorService must own phrase matching")
    require("crateCycleAnchorService:isCrateCycleAnchor" in handler, "crateHandler must delegate crate cycle anchor matching")
    require("logic/crateHandler/prediction.lua" not in toc, "prediction must be a standalone domain service, not a crateHandler submodule")
    require("CrateRush.prediction = prediction" in prediction_service, "prediction service must register as CrateRush.prediction")
    require("modulePredictionEnabled" in prediction_service, "prediction service must be gated by the prediction module setting")
    require("function prediction:onPlaneSighting" in prediction_service and "planeConfirmed" in prediction_service, "prediction must start from confirmed plane/flying lifecycle sightings")
    require("isFlyingLifecycle" in prediction_service and "CRATE_STATE.DETECTED" in prediction_service, "prediction must only run during the flying/detected lifecycle phase")
    require(
        "payload.state == CRATE_STATE.DETECTED" in prediction_service
        and "isTerminalState(payload.state)" in prediction_service
        and "CrateRush.isCrateStateClaimed(state)" in prediction_service,
        "prediction must reset on lifecycle start and clear only on claimed/closed states",
    )
    require("CrateRushRouteCellIndex" in prediction_service and "roughKey" in prediction_service and "fineKey" in prediction_service, "prediction runtime must use route cell table lookups")
    require("CrateRush.routeData:getCellCandidates" in prediction_service and "CrateRush.routeData:getCellKeys" in prediction_service, "prediction must share routeData cell helpers")
    require("crateKeys:sameShard" in prediction_service, "prediction service must use shared shard comparison")
    require("routeCandidateStateByKey" in prediction_service and "intersectRouteSets" in prediction_service, "prediction service must keep multi-point route candidate state")
    require("cell_intersection" in prediction_service and "same_cell_ambiguous" in prediction_service, "prediction service must wait/intersect when a cell maps to multiple routes")
    require("calculateMovementAngle" in prediction_service and "filterRouteSetByAngle" in prediction_service, "prediction service must resolve ambiguous routes with movement angle")
    require("ANGLE_TOLERANCE_DEGREES = 5" in prediction_service and "ANGLE_FALLBACK_TOLERANCE_DEGREES = 8" in prediction_service, "prediction service must keep named angle tolerances")
    require(
        "STRONG_ANGLE_BEST_MAX_DEGREES = 1" in prediction_service
        and "STRONG_ANGLE_SECOND_MIN_DEGREES = 2" in prediction_service
        and "STRONG_ANGLE_STABLE_TICKS = 2" in prediction_service,
        "prediction service must keep named strong angle tie-break thresholds",
    )
    require(
        "strongAngleRouteID" in prediction_service
        and "strongAngleTicks" in prediction_service
        and "angle_strong_tiebreak" in prediction_service,
        "prediction service must require a stable strong angle winner before resolving ambiguous routes early",
    )
    require("observedAngle" in prediction_service and "routeAngle" in prediction_service, "prediction debug payload must expose observed and route angles")
    require("lifecycleStartedAt" in prediction_service, "prediction payload must carry lifecycle identity for announcement de-dupe")
    require("ETA_CORRECTION_SECONDS" not in prediction_service and "eta_changed" not in prediction_service, "prediction service must not publish ETA-only updates")
    require("route_changed" not in prediction_service, "prediction service must not publish route-only updates without a location change")
    require("dominant_confidence" not in prediction_service and "dominant_samples" not in prediction_service and "CONFIDENCE_CORRECTION_DELTA" not in prediction_service, "prediction service must not guess from ambiguous cells by score")
    require("PREDICTION_UPDATED" in events and "PREDICTION_CLEARED" in events, "prediction domain events must be named")
    require("PREDICTION_UPDATED" in prediction_service and "PREDICTION_CLEARED" in prediction_service, "prediction service must publish prediction update/clear events")
    require("prediction:onPlaneSighting" in handler and "planeConfirmed" in handler, "crateHandler must feed confirmed plane sightings to prediction")
    require("prediction:onZoneChanged" in handler and "prediction:onPlayerEnteringWorld" in handler, "crateHandler must clear prediction on zone/session changes")
    for forbidden in ("crateLifecycle:transition", "CrateRush.timers", "CrateRush.storage", "SendChatMessage", "DEFAULT_CHAT_FRAME", "CrateRush.frames"):
        require(forbidden not in prediction_service, f"prediction service must not own lifecycle/timer/storage/UI/output behavior: {forbidden}")
    require("CrateRush.crateLifecycle" in shardmap and "CrateRush.shardService" in shardmap, "shardmap must be a compatibility facade")
    require(
        "TRANSITION_GUARD_CACHE_MAX_AGE_SECONDS" in timing
        and "TRANSITION_GUARD_CACHE_MAX_ENTRIES" in timing
        and "pruneOwners" in transition_guard
        and "vignetteZoneOwnerCount" in transition_guard
        and "vignetteContextZoneOwnerCount" in transition_guard,
        "transitionGuard ownership caches must be bounded by named timing constants",
    )
    passed.append("Step 7 services own shard, lifecycle, timer, transition, crate-cycle-anchor, and prediction logic")

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
    require("crateKeys:make" in domain_state and "local function makeKey" not in domain_state, "domainState must use shared crate key helper")
    crate_state_handler = source_section(
        domain_state,
        "function domainState:onCrateStateChanged",
        "function domainState:onCrateSightingSeen",
    )
    crate_seen_handler = source_section(
        domain_state,
        "function domainState:onCrateSightingSeen",
        "function domainState:onActiveTimerChanged",
    )
    for handler_name, handler_source in (
        ("onCrateStateChanged", crate_state_handler),
        ("onCrateSightingSeen", crate_seen_handler),
    ):
        require("setTimer(" not in handler_source, f"domainState:{handler_name} must not write timer records")
        require(
            "removeOtherTimersForZone" not in handler_source,
            f"domainState:{handler_name} must not delete timer records",
        )
    passed.append("domainState owns lifecycle and timer runtime indexes")

    require("local records" not in shardmap, "shardmap must not keep a private lifecycle records table")
    require("records[" not in shardmap, "shardmap must not index private lifecycle records directly")
    require("CrateRush.domainState:getOrCreateLifecycle" in crate_lifecycle, "crateLifecycle must create lifecycle records through domainState")
    require("CrateRush.domainState:getLifecycleRecords" in crate_lifecycle, "crateLifecycle getAll must read domainState records")
    require("crateKeys:make" in crate_lifecycle and "local function makeKey" not in crate_lifecycle, "crateLifecycle must use shared crate key helper")
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
    require("requestTimerRemoval" in timerbars and "uiActions:requestTimerRemoval" in timerbars, "timerbars must route timer removal through UI actions")
    require("TIMER_REMOVAL_REQUESTED" not in timerbars and "domainEvents:publish" not in timerbars, "timerbars must not publish domain commands directly")
    require("crateKeys:make" in timers and "local function sameShard" not in timers, "timers must use shared crate key helper")
    require("C_Map.GetMapInfo" not in timers and "CrateRush.zoneResolver:getCrateZoneName" in timers, "timers must use zoneResolver for display names")
    timer_seen_handler = source_section(
        timers,
        "function timers:onTimerSeen",
        "function timers:onCrateStateChanged",
    )
    get_timer_idx = timer_seen_handler.find("CrateRush.domainState:getTimer(zoneID, shardID)")
    remove_other_idx = timer_seen_handler.find("removeOtherTimersForZone(zoneID, shardID)")
    restore_idx = timer_seen_handler.find("timers:onStateChange")
    require(
        -1 not in (get_timer_idx, remove_other_idx, restore_idx)
        and get_timer_idx < remove_other_idx,
        "timers:onTimerSeen must remove other zone timers only after proving/restoring the current timer",
    )
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
