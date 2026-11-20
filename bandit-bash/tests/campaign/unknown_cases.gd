# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unknown_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Unknown node for tests/campaign/run_all.gd, on real runs from the real map rules: over many
## seeds each roll's share of combat, shop, treasure and event matches the rising-odds model worked
## out exactly (game-vision.md, Unknown (?) rolls), shops split evenly and never a Camp; the odds'
## update rule, the squeeze past 100 and the base data; a new run's odds reset; the command's
## refusals and its fact; the outcome and odds kept through a quit and Continue, before and after
## the roll, and an older save without one; each outcome playing as its node (the Armory's,
## Guildhall's and Treasure's commands, a combat's Standard pool, the event's hand-off); leaving
## clearing the outcome and keeping the odds; and the event fallback when no event can be drawn.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0A10

# Runs rolled for the odds, Unknowns rolled in a row in each, and how far a share may stray from
# the model's. Units: runs; Unknowns; share (0 to 1).
const ODDS_RUNS: int = 5000
const ODDS_ROLLS: int = 8
const ODDS_TOLERANCE: float = 0.025

# Rolls for the squeeze case. Units: rolls.
const SQUEEZE_ROLLS: int = 2000

# The model's outcome buckets: a shop counts once, whichever it became.
const BUCKETS: PackedStringArray = ["combat", "shop", "treasure", "event"]

const PERCENT: float = 100.0

var _report: Callable
var _rules: CampaignMapRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = CampaignMapRules.load_default()
	_check("unknown: the map rules load", _rules != null)
	if _rules == null:
		return
	_test_base_data()
	_test_odds_match_the_model()
	_test_update_rule()
	_test_squeeze()
	_test_reset_each_run()
	_test_command()
	_test_save_and_resume()
	_test_outcomes_play_as_their_node()
	_test_leave()
	_test_event_fallback()


func _test_base_data() -> void:
	var flow: RunFlow = RunFlow.new()
	_check("data: base odds are combat 10 / shop 3 / treasure 2 (game-vision.md)", (
			_rules.unknown_combat_chance == 10 and _rules.unknown_shop_chance == 3
			and _rules.unknown_treasure_chance == 2
			and UnknownResolution.chances(flow, _rules) == UnknownResolution.base_chances(_rules)
	), str(UnknownResolution.chances(flow, _rules)))


# The Done-when: across ODDS_RUNS runs of ODDS_ROLLS Unknowns each, every roll's share of each
# outcome is the model's, the shop splits evenly, and no roll is a Camp.
func _test_odds_match_the_model() -> void:
	var model: Array[Dictionary] = _model(ODDS_ROLLS)
	var counts: Array[Dictionary] = []
	for index: int in ODDS_ROLLS:
		counts.append({"combat": 0, "shop": 0, "treasure": 0, "event": 0})
	var shops: Dictionary[String, int] = {
		UnknownResolution.ARMORY: 0,
		UnknownResolution.GUILDHALL: 0,
	}
	var strays: PackedStringArray = []
	for run_seed: int in ODDS_RUNS:
		var flow: RunFlow = RunFlow.new()
		for index: int in ODDS_ROLLS:
			# One Unknown per floor from floor 2, as a route meets them; the stream is the game's.
			var stream: RngStream = RngStream.new(RngKey.derive_seed(
					run_seed, RngKey.RngPurpose.UNKNOWN_RESOLUTION, index + 2, index, -1, -1
			))
			var outcome: String = UnknownResolution.roll(flow, _rules, stream)
			var type: CampaignGraph.NodeType = UnknownResolution.type_of(outcome)
			if not UnknownResolution.OUTCOMES.has(outcome) or type == CampaignGraph.NodeType.CAMP:
				strays.append(outcome)
				continue
			if shops.has(outcome):
				shops[outcome] += 1
			var bucket: String = _bucket(outcome)
			counts[index][bucket] = (counts[index][bucket] as int) + 1
	var off: PackedStringArray = []
	for index: int in ODDS_ROLLS:
		for bucket: String in BUCKETS:
			var share: float = float(counts[index][bucket] as int) / ODDS_RUNS
			var expected: float = model[index][bucket]
			if absf(share - expected) > ODDS_TOLERANCE:
				off.append("roll %d %s %.3f, model %.3f" % [index + 1, bucket, share, expected])
	_check("odds: over %d runs of %d Unknowns each share matches the rising-odds model" % [
		ODDS_RUNS, ODDS_ROLLS,
	], off.is_empty(), ", ".join(off.slice(0, 4)))
	var shop_total: int = shops[UnknownResolution.ARMORY] + shops[UnknownResolution.GUILDHALL]
	var armory_share: float = (
			float(shops[UnknownResolution.ARMORY]) / shop_total if shop_total > 0 else 0.0
	)
	_check("odds: a shop is an Armory or a Guildhall at even odds", (
			shop_total > 0 and absf(armory_share - 0.5) <= ODDS_TOLERANCE * 2.0
	), "%d Armory of %d shops" % [shops[UnknownResolution.ARMORY], shop_total])
	_check("odds: every roll is a known outcome and never a Camp", (
			strays.is_empty()
			and not UnknownResolution.OUTCOMES.has("camp")
	), ", ".join(strays.slice(0, 4)))


func _test_update_rule() -> void:
	var stream: RngStream = RngStream.new(RUN_SEED)
	var cases: Array[Array] = [
		# Staged odds (combat, shop, treasure) forcing one outcome; the odds after it.
		[[100, 9, 4], "combat", [10, 12, 6]],
		[[0, 100, 4], "shop", [10, 3, 6]],
		[[0, 0, 100], "treasure", [10, 3, 2]],
		[[0, 0, 0], "event", [10, 3, 2]],
	]
	var wrong: PackedStringArray = []
	for entry: Array in cases:
		var flow: RunFlow = RunFlow.new()
		flow.unknown_odds = _odds(entry[0] as Array)
		var outcome: String = UnknownResolution.roll(flow, _rules, stream)
		var is_right: bool = (
				_bucket(outcome) == (entry[1] as String) and flow.unknown == outcome
				and flow.unknown_odds == _odds(entry[2] as Array)
		)
		if not is_right:
			wrong.append("%s -> %s %s" % [entry[0], outcome, flow.unknown_odds])
	_check("update: the type that came up drops to base, every other one gains its base", (
			wrong.is_empty()
	), ", ".join(wrong))


func _test_squeeze() -> void:
	var counts: Dictionary[String, int] = {"combat": 0, "shop": 0, "treasure": 0, "event": 0}
	for roll_seed: int in SQUEEZE_ROLLS:
		var flow: RunFlow = RunFlow.new()
		flow.unknown_odds = _odds([60, 30, 30])
		var outcome: String = UnknownResolution.roll(flow, _rules, RngStream.new(roll_seed))
		counts[_bucket(outcome)] += 1
	var treasure: float = float(counts["treasure"]) / SQUEEZE_ROLLS
	var combat: float = float(counts["combat"]) / SQUEEZE_ROLLS
	_check("squeeze: odds past 100 check combat, shop, treasure in order and leave no event", (
			counts["event"] == 0
			and absf(combat - 0.6) <= ODDS_TOLERANCE * 2.0
			and absf(treasure - 0.1) <= ODDS_TOLERANCE
	), str(counts))


func _test_reset_each_run() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var first: bool = Fixture.enter(session.run, CampaignGraph.NodeType.UNKNOWN)
	var resolved: CampaignBatch = session.submit(ResolveUnknownCommand.for_session(session))
	var rolled: bool = (
			first and resolved != null and not resolved.is_rejected()
			and not session.run.flow.unknown_odds.is_empty()
	)
	var next_run: CampaignSession = Fixture.session(RUN_SEED)
	_check("reset: a new run starts every Unknown chance at base", (
			rolled and next_run.run.flow.unknown_odds.is_empty()
			and next_run.run.flow.unknown.is_empty()
			and (
				UnknownResolution.chances(next_run.run.flow, _rules)
				== UnknownResolution.base_chances(_rules)
			)
	), str(session.run.flow.unknown_odds))


func _test_command() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var run_state: CampaignRunState = session.run
	var on_map: CampaignBatch = session.submit(ResolveUnknownCommand.for_session(session))
	Fixture.enter(run_state, CampaignGraph.NodeType.STANDARD)
	var at_combat: CampaignBatch = session.submit(ResolveUnknownCommand.for_session(session))
	_check("command: refused on the map and inside a node that isn't an Unknown", (
			on_map.is_rejected() and at_combat.is_rejected()
			and run_state.flow.unknown_odds.is_empty()
	), "%s / %s" % [on_map.rejected_reason, at_combat.rejected_reason])

	run_state.flow.stage = RunFlow.Stage.MAP
	var entered: bool = Fixture.enter(run_state, CampaignGraph.NodeType.UNKNOWN)
	var due: bool = ResolveUnknownCommand.is_due(run_state)
	var batch: CampaignBatch = session.submit(ResolveUnknownCommand.for_session(session))
	var fact: CampaignFact = (
			batch.facts[0] if batch != null and batch.facts.size() == 1 else null
	)
	_check("command: rolls once in an Unknown, recording UNKNOWN_RESOLVED (outcome, node)", (
			entered and due and not batch.is_rejected() and fact != null
			and fact.kind == CampaignFact.Kind.UNKNOWN_RESOLVED
			and fact.seat == CampaignFact.NO_SEAT
			and fact.definition_id == run_state.flow.unknown
			and fact.amount == run_state.node
			and UnknownResolution.OUTCOMES.has(run_state.flow.unknown)
			and not ResolveUnknownCommand.is_due(run_state)
	), batch.rejected_reason if batch != null else "no batch")
	var odds_before: Dictionary[String, int] = run_state.flow.unknown_odds.duplicate()
	var again: CampaignBatch = session.submit(ResolveUnknownCommand.for_session(session))
	_check("command: a second roll at the same node is refused and changes nothing", (
			again.is_rejected() and run_state.flow.unknown_odds == odds_before
	), again.rejected_reason)

	var other: CampaignSession = Fixture.session(RUN_SEED + 1)
	Fixture.enter(other.run, CampaignGraph.NodeType.UNKNOWN)
	var opened: CampaignBatch = other.submit(EventNode.open(other))
	var after_event: CampaignBatch = other.submit(ResolveUnknownCommand.for_session(other))
	_check("command: refused where an event is already open (it is one already)", (
			not opened.is_rejected() and after_event.is_rejected()
			and other.run.flow.unknown.is_empty()
			and not ResolveUnknownCommand.is_due(other.run)
	), "%s / %s" % [opened.rejected_reason, after_event.rejected_reason])
	var fresh: CampaignSession = Fixture.session(RUN_SEED + 2)
	Fixture.enter(fresh.run, CampaignGraph.NodeType.UNKNOWN)
	var missing: CampaignBatch = fresh.submit(ResolveUnknownCommand.new(CampaignData.HOST_SEAT))
	_check("command: refused without the map rules or the stream", (
			missing.is_rejected() and ResolveUnknownCommand.is_due(fresh.run)
	), missing.rejected_reason)


func _test_save_and_resume() -> void:
	# A quit after the node is entered, before the roll is saved: the roll on Continue is the same.
	var straight: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(straight.run, CampaignGraph.NodeType.UNKNOWN)
	straight.run.flow.unknown_odds = _odds([20, 6, 4])
	var resumed: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(resumed.run, CampaignGraph.NodeType.UNKNOWN)
	resumed.run.flow.unknown_odds = _odds([20, 6, 4])
	var reloaded: CampaignRunState = Fixture.through_json(resumed.run)
	if reloaded != null:
		resumed.run = reloaded
	straight.submit(ResolveUnknownCommand.for_session(straight))
	resumed.submit(ResolveUnknownCommand.for_session(resumed))
	_check("resume (before the roll): Continue rolls the same outcome and odds", (
			reloaded != null and not straight.run.flow.unknown.is_empty()
			and resumed.run.flow.unknown == straight.run.flow.unknown
			and resumed.run.flow.unknown_odds == straight.run.flow.unknown_odds
	), "%s / %s" % [straight.run.flow.unknown, resumed.run.flow.unknown])

	var kept: CampaignRunState = Fixture.through_json(straight.run)
	_check("resume (after the roll): the outcome and the new odds come back, not rolled again", (
			kept != null and kept.flow.unknown == straight.run.flow.unknown
			and kept.flow.unknown_odds == straight.run.flow.unknown_odds
			and kept.node_type() == straight.run.node_type()
			and not ResolveUnknownCommand.is_due(kept)
	))

	var older: Dictionary = straight.run.flow.capture()
	older.erase("unknown")
	var read_older: RunFlow = RunFlow.new()
	var bad: Dictionary = straight.run.flow.capture()
	bad["unknown"] = "camp"
	_check("restore: a save without the outcome reads as not rolled; a camp or bad id is refused", (
			read_older.restore(Fixture.json(older)) == OK and read_older.unknown.is_empty()
			and RunFlow.new().restore(Fixture.json(bad)) == ERR_INVALID_DATA
	))


func _test_outcomes_play_as_their_node() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var run_state: CampaignRunState = session.run
	if not Fixture.enter(run_state, CampaignGraph.NodeType.UNKNOWN):
		_check("outcomes: the map has an Unknown", false)
		return
	var wrong: PackedStringArray = []
	var pools: CombatMapPools = CombatMapPools.load_default()
	for outcome: String in UnknownResolution.OUTCOMES:
		run_state.flow.unknown = outcome
		var armory: String = OpenArmoryCommand.for_session(session, catalog).validate(run_state)
		var guildhall: String = OpenGuildhallCommand.for_session(session, catalog).validate(
				run_state
		)
		var treasure: String = OpenTreasureCommand.for_session(session, catalog).validate(run_state)
		var event: String = EventNode.open(session).validate(run_state)
		var is_armory: bool = outcome == UnknownResolution.ARMORY
		var is_guildhall: bool = outcome == UnknownResolution.GUILDHALL
		var is_treasure: bool = outcome == UnknownResolution.TREASURE
		var is_event: bool = outcome == UnknownResolution.EVENT
		if (
				armory.is_empty() != is_armory or guildhall.is_empty() != is_guildhall
				or treasure.is_empty() != is_treasure
				or Camp.is_at_camp(run_state)
				or run_state.node_type() != UnknownResolution.type_of(outcome)
		):
			wrong.append("%s: %s / %s / %s" % [outcome, armory, guildhall, treasure])
		if is_event and not (event.is_empty() and UnknownResolution.needs_event(run_state)):
			wrong.append("event: %s" % [event])
		if outcome == UnknownResolution.COMBAT:
			var request: CampaignSession.BattleRequest = run_state.battle_request(pools, catalog)
			var is_standard: bool = request != null and not request.pool.is_empty()
			if request != null:
				for map: CombatMapDefinition in request.pool:
					is_standard = (
							is_standard
							and map.combat_type == CombatMapDefinition.CombatType.STANDARD
					)
			if not is_standard:
				wrong.append("combat: not the Standard pool")
	_check("outcomes: each plays as its node (Armory, Guildhall, Treasure, Standard pool, event)", (
			wrong.is_empty()
	), ", ".join(wrong))


func _test_leave() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(session.run, CampaignGraph.NodeType.UNKNOWN)
	session.submit(ResolveUnknownCommand.for_session(session))
	var outcome: String = session.run.flow.unknown
	var odds: Dictionary[String, int] = session.run.flow.unknown_odds.duplicate()
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("leave: leaving clears the node's outcome and keeps the odds for the next Unknown", (
			not left.is_rejected() and session.run.flow.unknown.is_empty()
			and session.run.flow.unknown_odds == odds
			and UnknownResolution.chances(session.run.flow, _rules) == odds
	), "%s: %s" % [outcome, left.rejected_reason])


func _test_event_fallback() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(session.run, CampaignGraph.NodeType.UNKNOWN)
	session.run.flow.unknown = UnknownResolution.EVENT
	var refused: CampaignBatch = session.submit(EventNode.open(session, EventPool.new()))
	_check("fallback: with no event to draw the event is refused and the node waits on none", (
			refused.is_rejected() and UnknownResolution.needs_event(session.run)
			and not session.run.events.is_open_at(session.run.floor_number, session.run.node)
			and session.run.node_type() == CampaignGraph.NodeType.UNKNOWN
	), refused.rejected_reason)


# The rising-odds model from the base chances, worked out exactly: each outcome bucket's chance
# at each of rolls Unknowns in a row, summed over every state the odds can reach. One d100 is
# checked against combat, then shop, then treasure, each capped where the total reaches 100.
func _model(rolls: int) -> Array[Dictionary]:
	var base: Vector3i = Vector3i(
			_rules.unknown_combat_chance, _rules.unknown_shop_chance,
			_rules.unknown_treasure_chance
	)
	var states: Dictionary[Vector3i, float] = {base: 1.0}
	var shares: Array[Dictionary] = []
	for _roll: int in rolls:
		var share: Dictionary = {"combat": 0.0, "shop": 0.0, "treasure": 0.0, "event": 0.0}
		var next: Dictionary[Vector3i, float] = {}
		for state: Vector3i in states:
			var weight: float = states[state]
			var combat: float = minf(state.x, PERCENT) / PERCENT
			var to_shop: float = minf(state.x + state.y, PERCENT) / PERCENT
			var to_treasure: float = minf(state.x + state.y + state.z, PERCENT) / PERCENT
			var chances: Dictionary = {
				"combat": combat,
				"shop": to_shop - combat,
				"treasure": to_treasure - to_shop,
				"event": 1.0 - to_treasure,
			}
			var after: Dictionary = {
				"combat": Vector3i(base.x, state.y + base.y, state.z + base.z),
				"shop": Vector3i(state.x + base.x, base.y, state.z + base.z),
				"treasure": Vector3i(state.x + base.x, state.y + base.y, base.z),
				"event": state + base,
			}
			for bucket: String in BUCKETS:
				var chance: float = chances[bucket]
				share[bucket] = (share[bucket] as float) + weight * chance
				var reached: Vector3i = after[bucket]
				next[reached] = next.get(reached, 0.0) + weight * chance
		shares.append(share)
		states = next
	return shares


# The model's bucket of outcome: a shop counts once, whichever it became.
func _bucket(outcome: String) -> String:
	if outcome == UnknownResolution.ARMORY or outcome == UnknownResolution.GUILDHALL:
		return "shop"
	return outcome


# Odds as RunFlow keeps them from [combat, shop, treasure].
func _odds(values: Array) -> Dictionary[String, int]:
	return {
		UnknownResolution.ODDS_COMBAT: values[0] as int,
		UnknownResolution.ODDS_SHOP: values[1] as int,
		UnknownResolution.ODDS_TREASURE: values[2] as int,
	}


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
