# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_bridge_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 14, 2026
# ==============================================================================

extends RefCounted
## Battle bridge cases for tests/campaign/run_all.gd, on the real content and M1: the map pools
## and the no-repeat rule; the run's battle request (its node, pool and living army); a result
## applied to a copy (HP, a fall with its items, Hit and growth deltas, heirloom lanes, grants,
## used maps, the node's results, a fallen commander kept at critical HP; the run itself
## unchanged); a real battle whose fallen unit is gone
## from the next request, whose HP carries over and whose Hit delta is on the roster; a curse held
## twice bringing two carriers, each with its own campaign lane (BUG-009); and the XP tally, its
## counting rules and both save sections. Touches no save files.

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const M1_ID: String = "m1_greybox"
const RUN_SEED: int = 0x3F9A12C077E1A
const MERCENARY: String = "mercenary"
const COMMANDER_HEIRLOOM: String = "iron_heart"

# A fixture curse with one effect, which the shipped content doesn't have yet.
const CURSE_ID: String = "test_curse"
const CURSE_EFFECT_ID: String = "test_curse_mark"
const RUNE_ID: String = "test_rune"

# The hit fixture's Hit booster: +5 Hit (items.md, Stat boosters).
const HIT_GAIN: float = 5.0

const SessionsCaseBase = preload("res://tests/sessions/sessions_case_base.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _report: Callable
var _rules: CampaignMapRules = null
var _catalog: EffectCatalog.Index = null
var _pools: CombatMapPools = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_rules = load(RULES_PATH) as CampaignMapRules
	_catalog = EffectCatalog.index()
	_pools = CombatMapPools.load_default()
	_check("bridge: the map rules, catalog and map pools load", (
			_rules != null and _catalog != null and _pools != null
	))
	if _rules == null or _catalog == null or _pools == null:
		return
	_test_pools()
	_test_request()
	_test_apply()
	_test_apply_loss_and_commander()
	_test_real_battle_carries_over()
	_test_curse_twice()
	_test_tally_counts()
	_test_tally_sections()


## A solo session with a new run built as [code]CampaignService[/code] builds it.
func new_session(catalog: EffectCatalog.Index = null) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			_rules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog if catalog == null else catalog,
			factions,
			session.ids
	)
	session.run = start.run
	return session


func _test_pools() -> void:
	var standard: CombatMapPool = _pools.pool_for(CampaignGraph.NodeType.STANDARD, 1)
	_check("pools: every combat step has a pool of M1, and nothing else has one", (
			standard != null
			and standard.map_ids() == PackedStringArray([M1_ID])
			and _pools.pool_for(CampaignGraph.NodeType.STANDARD, 6) != standard
			and _pools.pool_for(CampaignGraph.NodeType.STANDARD, 17) != null
			and _pools.pool_for(CampaignGraph.NodeType.KEY, 3) == null
			and _pools.pool_for(CampaignGraph.NodeType.KEY, 6) != null
			and _pools.pool_for(CampaignGraph.NodeType.KEY, 12) != null
			and _pools.pool_for(CampaignGraph.NodeType.BOSS, 18) != null
			and _pools.pool_for(CampaignGraph.NodeType.CAMP, 7) == null
	))
	var pool: CombatMapPool = CombatMapPool.new()
	pool.maps = SessionsCaseBase.Battle.pool(["map_a", "map_b"])
	var none_used: Array[CombatMapDefinition] = CombatMapPools.available(pool, [])
	var one_used: Array[CombatMapDefinition] = CombatMapPools.available(pool, ["map_a"])
	var all_used: Array[CombatMapDefinition] = CombatMapPools.available(pool, ["map_b", "map_a"])
	_check("pools: a used map isn't offered until its whole pool is used, then it refills", (
			_ids(none_used) == PackedStringArray(["map_a", "map_b"])
			and _ids(one_used) == PackedStringArray(["map_b"])
			and _ids(all_used) == PackedStringArray(["map_a", "map_b"])
	), "%s / %s / %s" % [_ids(none_used), _ids(one_used), _ids(all_used)])


func _test_request() -> void:
	var session: CampaignSession = new_session()
	var run: CampaignRunState = session.run
	print("    (an error about a run that isn't inside a node follows)")
	var on_map: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var seat_run: SeatRun = run.seat_run(0)
	var lost: UnitInstance = seat_run.army.pop_back()
	seat_run.fallen.append(lost)
	var request: CampaignSession.BattleRequest = run.battle_request(_pools, _catalog)
	var army: CampaignSession.Army = null if request == null else request.armies.get(0, null)
	_check("request: none outside a node", on_map == null)
	_check("request: the node's floor and id, and its pool's map", (
			request != null
			and request.floor_number == 1
			and request.node == run.node
			and _ids(request.pool) == PackedStringArray([M1_ID])
			and request.catalog == _catalog
	))
	_check("request: the seat's living army, as the run's own instances, without the fallen", (
			army != null
			and army.unit_instances.size() == 3
			and army.unit_instances[0] == seat_run.army[0]
			and not army.unit_instances.has(lost)
			and army.item_instances.has(seat_run.army[0].weapon_id)
			and army.heirloom_ids == PackedStringArray([COMMANDER_HEIRLOOM])
	))


func _test_apply() -> void:
	var session: CampaignSession = new_session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var seat_run: SeatRun = run.seat_run(0)
	var hit_unit: UnitInstance = seat_run.army[1]
	var grown: UnitInstance = seat_run.army[2]
	var faller: UnitInstance = seat_run.army[3]
	var before: String = _run_text(run)

	var result: CampaignSession.BattleResult = _won_result(run)
	result.units[hit_unit.instance_id] = _outcome(7, false)
	result.units[hit_unit.instance_id].stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.HIT, HIT_GAIN, "item:900", "Hit Booster"
	))
	result.units[faller.instance_id] = _outcome(0, true)
	result.units[grown.instance_id] = _outcome(UnitInstance.FULL_HP, false)
	result.growth_changes[grown.instance_id] = {CombatValue.Stat.MGT: 5}
	var lane: CampaignSession.HeirloomLane = CampaignSession.HeirloomLane.new(
			0, COMMANDER_HEIRLOOM, 0
	)
	lane.counters = {"iron_heart_strike": 3}
	result.heirlooms.append(lane)
	result.grants.assign([
		_grant(CampaignGrant.Grant.GOLD, 40, ""),
		_grant(CampaignGrant.Grant.HEIRLOOM, 0, CURSE_ID),
		_grant(CampaignGrant.Grant.RUNE, 0, RUNE_ID),
		_grant(CampaignGrant.Grant.RECRUIT, 0, "archer"),
	])
	print("    (a warning about a recruit grant that isn't applied yet follows)")
	var next: CampaignRunState = _apply(run, result, session)
	_check("apply: the run itself is unchanged; the copy shares no unit", (
			next != null
			and _run_text(run) == before
			and next.seat_run(0).army[0] != seat_run.army[0]
	))
	if next == null:
		return
	var after: SeatRun = next.seat_run(0)
	var hit_after: UnitInstance = after.unit(hit_unit.instance_id)
	var fallen_after: UnitInstance = after.unit(faller.instance_id)
	var grown_after: UnitInstance = after.unit(grown.instance_id)
	_check("apply: HP and the Hit delta are on the unit", (
			hit_after.hp == 7
			and hit_after.stat_deltas.size() == 1
			and hit_after.stat_deltas[0].key == CombatValue.Key.HIT
			and is_equal_approx(hit_after.stat_deltas[0].amount, HIT_GAIN)
			and hit_after.stats(_catalog).get_int(CombatValue.Key.HIT)
					== hit_unit.stats(_catalog).get_int(CombatValue.Key.HIT) + int(HIT_GAIN)
	))
	_check("apply: a growth change becomes a growth delta with an empty source", (
			grown_after.growth_deltas.size() == 1
			and grown_after.growth_deltas[0].key == CombatValue.Stat.MGT
			and is_equal_approx(grown_after.growth_deltas[0].amount, 5.0)
			and grown_after.growth_deltas[0].source_id.is_empty()
	))
	_check("apply: the fallen unit is in the fallen list with its items (permadeath)", (
			after.army.size() == 3
			and not after.army.has(fallen_after)
			and after.fallen == [fallen_after]
			and fallen_after.hp == 0
			and not fallen_after.item_ids().is_empty()
			and after.items.has(fallen_after.weapon_id)
			and SeatRun.new(0).restore_roster(after.capture_roster()) == OK
	))
	_check("apply: the heirloom copy's campaign lane is saved on its entry", (
			(after.heirlooms[0].counters.get("iron_heart_strike", 0) as int) == 3
	))
	var rune: SeatRun.RuneSlot = after.rune_slots[0]
	_check("apply: gold, a named curse and a rune are granted; the recruit isn't", (
			after.gold == seat_run.gold + 40
			and after.heirloom_ids() == PackedStringArray([COMMANDER_HEIRLOOM, CURSE_ID])
			and rune.definition_id == RUNE_ID
			and not rune.instance_id.is_empty()
			and after.army.size() == 3
	), "%d gold, %s" % [after.gold, after.heirloom_ids()])
	var kinds: PackedStringArray = []
	for fact: CampaignFact in next.fact_log.slice(run.fact_log.size()):
		kinds.append("%s %d" % [CampaignFact.Kind.find_key(fact.kind), fact.amount])
	_check("apply: a won node battle uses its map and moves to the node's results", (
			next.flow.used_maps == PackedStringArray([M1_ID])
			and next.flow.stage == RunFlow.Stage.RESULTS
			and not next.is_on_map()
			and next.node == run.node
			and kinds == PackedStringArray(["GAINED 0", "GAINED 0", "COMBAT_ENDED 1"])
	), str(kinds))

	# The second battle on the one-map pool refills it: M1 is used once, not twice.
	next.enter_node(next.graph.children_of(next.node)[0])
	var again: CampaignSession.BattleResult = _won_result(next)
	var refilled: CampaignRunState = _apply(next, again, session)
	_check("apply: a refilled pool forgets its used maps first", (
			refilled.flow.used_maps == PackedStringArray([M1_ID])
	), str(refilled.flow.used_maps))


func _test_apply_loss_and_commander() -> void:
	var session: CampaignSession = new_session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var commander_id: String = run.seat_run(0).commander_id
	var result: CampaignSession.BattleResult = _won_result(run)
	result.is_won = false
	result.units[commander_id] = _outcome(0, true)
	result.units[commander_id].max_hp = 20
	var next: CampaignRunState = _apply(run, result, session)
	var last: CampaignFact = next.fact_log[next.fact_log.size() - 1]
	_check("apply: a loss stays in the node and records the loss", (
			not next.is_on_map()
			and next.flow.stage == RunFlow.Stage.NODE
			and last.kind == CampaignFact.Kind.COMBAT_ENDED
			and last.amount == 0
	))
	_check("apply: a fallen commander stays in the army at critical HP; the roster stays valid", (
			next.seat_run(0).commander_id == commander_id
			and next.seat_run(0).fallen.is_empty()
			and next.seat_run(0).unit(commander_id).hp == 2
			and SeatRun.new(0).restore_roster(next.seat_run(0).capture_roster()) == OK
	))

	var unfinished: CampaignSession.BattleResult = _won_result(run)
	unfinished.is_finished = false
	unfinished.is_won = false
	var stays: CampaignRunState = _apply(run, unfinished, session)
	_check("apply: an unfinished battle uses its map and records no end", (
			not stays.is_on_map()
			and stays.fact_log.size() == run.fact_log.size()
			and stays.flow.used_maps == PackedStringArray([M1_ID])
	))


# A real M1 battle from the run's request: a unit is hurt, one falls, one gains +5 Hit and hits
# twice; the map is won. The next battle's request leaves the fallen unit out, loads the hurt
# unit's HP, and the roster unit has the Hit delta.
func _test_real_battle_carries_over() -> void:
	var session: CampaignSession = new_session()
	var run: CampaignRunState = session.run
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var seat_run: SeatRun = run.seat_run(0)
	var hit_id: String = seat_run.army[1].instance_id
	var hurt_id: String = seat_run.army[2].instance_id
	var fall_id: String = seat_run.army[3].instance_id
	var hit_before: int = seat_run.army[1].stats(_catalog).get_int(CombatValue.Key.HIT)
	var battle: CombatEncounter = session.begin_battle(run.battle_request(_pools, _catalog))
	_check("battle: the run's request begins a battle on M1", (
			battle != null and battle.setup.map.id == M1_ID
	))
	if battle == null:
		return
	var map: CombatSession = battle.get_session(0)
	var enemies: PackedStringArray = map.state.units_of(ENEMY)
	_check("battle: the drawn enemies are on the map", not enemies.is_empty())
	if enemies.is_empty():
		session.close()
		return
	map.state.unit(hurt_id).hp = 4
	map.engine.add_delta(hit_id, Modifier.new(
			CombatValue.Key.HIT, Modifier.Mode.ADD, HIT_GAIN, Modifier.SourceKind.POUCH_ITEM,
			"item:900", "Hit Booster"
	))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, hit_id, enemies[0]))
	map.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, hit_id, enemies[0]))
	map.state.defeat(map.engine, fall_id, enemies[0])
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	map.engine.record(ended)
	_check("battle: the tally counted the two hits", (
			session.tally.count(hit_id, BattleTally.Action.HIT) == 2
	), str(session.tally.capture()))

	var result: CampaignSession.BattleResult = session.collect_battle()
	_check("battle: the result has the win, HP, the fall and the Hit delta", (
			result.is_finished
			and result.is_won
			and result.map_id == M1_ID
			and result.units[hurt_id].hp == 4
			and result.units[fall_id].is_fallen
			and result.units[hit_id].stat_deltas.size() == 1
			and result.units[hit_id].stat_deltas[0].key == CombatValue.Key.HIT
			and session.collect_battle() == result
	))
	var next: CampaignRunState = _apply(run, result, session)
	session.end_battle()
	session.run = next
	var after: SeatRun = next.seat_run(0)
	_check("battle: after it, the Hit delta is on the roster", (
			after.unit(hit_id).stats(_catalog).get_int(CombatValue.Key.HIT)
					== hit_before + int(HIT_GAIN)
	))

	session.submit(ItemPickCommand.new(0, ItemPickCommand.SKIP))
	session.submit(LeaveNodeCommand.new(0))
	var child: int = _combat_child(next)
	next.enter_node(child)
	var second: CampaignSession.BattleRequest = next.battle_request(_pools, _catalog)
	var loaded: CombatEncounter = session.begin_battle(second)
	var second_map: CombatSession = null if loaded == null else loaded.get_session(0)
	var unit_ids: PackedStringArray = []
	for unit: UnitInstance in second.armies[0].unit_instances:
		unit_ids.append(unit.instance_id)
	_check("battle: the fallen unit is absent from the next request, its items kept", (
			not unit_ids.has(fall_id)
			and unit_ids.size() == 3
			and after.fallen.size() == 1
			and after.items.has(after.fallen[0].weapon_id)
	), str(unit_ids))
	_check("battle: HP carries into the next battle", (
			second_map != null
			and second_map.state.unit(hurt_id).hp == 4
			and not second_map.state.has_unit(fall_id)
	))
	session.close()


# BUG-009: a curse held twice brings two carriers into battle, each with its own campaign lane.
func _test_curse_twice() -> void:
	var catalog: EffectCatalog.Index = _catalog_with_curse()
	var session: CampaignSession = new_session(catalog)
	var run: CampaignRunState = session.run
	var seat_run: SeatRun = run.seat_run(0)
	seat_run.add_heirloom(CURSE_ID)
	seat_run.add_heirloom(CURSE_ID).counters[CURSE_EFFECT_ID] = 4
	session.submit(ChooseNodeCommand.new(0, run.graph.nodes_on_floor(1)[0]))
	var battle: CombatEncounter = session.begin_battle(run.battle_request(_pools, catalog))
	if battle == null:
		_check("curse twice: the battle begins", false)
		return
	var marks: Array[EffectInstance] = []
	for instance: EffectInstance in _battle_instances(battle):
		if instance.definition.id == CURSE_EFFECT_ID:
			marks.append(instance)
	var counts: Array[int] = []
	for mark: EffectInstance in marks:
		counts.append(mark.get_counter(EffectTerms.Lane.CAMPAIGN))
	_check("curse twice: two carriers in battle, the second copy's saved lane on it", (
			marks.size() == 2 and counts == [0, 4]
	), "%d carriers, counters %s" % [marks.size(), counts])
	if marks.size() != 2:
		session.close()
		return
	marks[0].set_counter(EffectTerms.Lane.CAMPAIGN, 2)
	marks[1].set_counter(EffectTerms.Lane.CAMPAIGN, 9)
	var next: CampaignRunState = _apply(run, session.collect_battle(), session)
	session.end_battle()
	var held: Array[SeatRun.OwnedHeirloom] = next.seat_run(0).heirlooms
	_check("curse twice: each copy's lane is written back to its own entry", (
			held.size() == 3
			and (held[1].counters.get(CURSE_EFFECT_ID, 0) as int) == 2
			and (held[2].counters.get(CURSE_EFFECT_ID, 0) as int) == 9
	), "%s / %s" % [held[1].counters, held[2].counters])
	session.close()


func _test_tally_counts() -> void:
	var world: SessionsCaseBase.World = SessionsCaseBase.World.new()
	var state: CombatState = world.session.state
	var striker: String = world.add_unit("Hakkapel", PLAYER, 0, Vector2i(0, 3))
	var medic: String = world.add_unit("Battle Medic", PLAYER, 0, Vector2i(1, 3))
	var enemy: String = world.add_unit("Brute", ENEMY, -1, Vector2i(3, 2))
	var chest: MapState.ObjectState = _object("object:1", MapLayout.ObjectKind.CHEST)
	var door: MapState.ObjectState = _object("object:2", MapLayout.ObjectKind.DOOR)
	state.map.objects[chest.id] = chest
	state.map.objects[door.id] = door
	var tally: BattleTally = BattleTally.new()
	var facts: Array[CombatFact] = [
		CombatFact.new(CombatFact.Kind.HIT_DEALT, striker, enemy),
		CombatFact.new(CombatFact.Kind.HIT_DEALT, striker, medic),
		CombatFact.new(CombatFact.Kind.HIT_DEALT, enemy, striker),
		CombatFact.new(CombatFact.Kind.DEFEATED_AN_ENEMY, striker, enemy),
		CombatFact.new(CombatFact.Kind.HEALED_AN_ALLY, medic, striker),
		CombatFact.new(CombatFact.Kind.HEALED_AN_ALLY, medic, medic),
		_amount(CombatFact.new(CombatFact.Kind.BLOCK_GAINED, striker, medic), 2),
		_amount(CombatFact.new(CombatFact.Kind.BLOCK_GAINED, striker, medic), 0),
		_amount(CombatFact.new(CombatFact.Kind.BLOCK_GAINED, striker, striker), 3),
		_change("point:0", striker, MapObjects.Change.POINT_CLOSED),
		_change("object:3", striker, MapObjects.Change.SEARCHED),
		_change(chest.id, medic, MapObjects.Change.OPENED),
		_change(door.id, medic, MapObjects.Change.OPENED),
		_change("object:4", enemy, MapObjects.Change.SEARCHED),
	]
	for fact: CombatFact in facts:
		tally.record(fact, state)
	_check("tally: hits and defeats count on enemies only", (
			tally.count(striker, BattleTally.Action.HIT) == 1
			and tally.count(striker, BattleTally.Action.DEFEAT) == 1
			and tally.count(enemy, BattleTally.Action.HIT) == 0
	))
	_check("tally: heals and Block count when given to another player unit, above 0", (
			tally.count(medic, BattleTally.Action.HEAL) == 1
			and tally.count(medic, BattleTally.Action.BLOCK) == 1
			and tally.count(striker, BattleTally.Action.BLOCK) == 0
	))
	_check("tally: a point closed, a search and a chest count; a door doesn't", (
			tally.count(striker, BattleTally.Action.NON_COMBAT) == 2
			and tally.count(medic, BattleTally.Action.NON_COMBAT) == 1
			and tally.count(enemy, BattleTally.Action.NON_COMBAT) == 0
			and tally.unit_ids().size() == 2
	), str(tally.capture()))
	_check("tally: a killing blow is two actions", (
			tally.total(striker) == 4 and tally.total(medic) == 3
	), "%d, %d" % [tally.total(striker), tally.total(medic)])

	var text: String = JSON.stringify(tally.capture())
	var parsed: Variant = JSON.parse_string(text)
	var reloaded: BattleTally = BattleTally.new()
	var restored: Error = reloaded.restore(parsed as Dictionary)
	_check("tally: it round-trips through JSON", (
			restored == OK and JSON.stringify(reloaded.capture()) == text
	), text)
	print("    (errors about unusable tally data follow)")
	var bad: Dictionary[String, Dictionary] = {
		"a negative count": {"units": {striker: _counts(-1)}},
		"an unknown action": {"units": {striker: {"hit": 1, "dance": 2}}},
		"a fractional count": {"units": {striker: _counts(1.5)}},
		"no units": {},
	}
	for case_name: String in bad:
		var target: BattleTally = BattleTally.new()
		target.restore({"units": {"unit:1": _counts(1)}})
		_check("tally: %s is refused and changes nothing" % [case_name], (
				target.restore(bad[case_name]) == ERR_INVALID_DATA
				and target.count("unit:1", BattleTally.Action.HIT) == 1
		))


func _test_tally_sections() -> void:
	var section: BattleTallySection = BattleTallySection.new()
	var tally_data: Dictionary = {"units": {"unit:5": _counts(2)}}
	var grants_data: Dictionary = {"grants": [{
		"seat": 0.0, "grant": "gold", "amount": 50.0, "definition_id": "",
		"source_effect_id": "effect:3",
	}]}
	var restored: Error = section.restore(tally_data)
	var grants_restored: Error = section.grants.restore(grants_data)
	_check("tally sections: version 1 under their keys", (
			section.get_key() == "battle_tally"
			and section.get_version() == 1
			and section.grants.get_key() == "battle_grants"
			and section.grants.get_version() == 1
	))
	var session: CampaignSession = new_session()
	section.attach(session)
	var held_capture: String = JSON.stringify(section.capture())
	var loaded: Error = section.load_into(session)
	_check("tally sections: held data loads into the session's tally and grants", (
			restored == OK
			and grants_restored == OK
			and held_capture == JSON.stringify(tally_data)
			and loaded == OK
			and session.tally.count("unit:5", BattleTally.Action.HIT) == 2
			and session.battle_grants.size() == 1
			and session.battle_grants[0].amount == 50
			and session.battle_grants[0].grant == CampaignGrant.Grant.GOLD
			and not section.is_holding()
	))
	print("    (errors about unusable battle grants follow)")
	var fresh: BattleTallySection = BattleTallySection.new()
	_check("tally sections: bad data is refused", (
			fresh.restore({"units": {"unit:5": {"hit": -1}}}) == ERR_INVALID_DATA
			and fresh.grants.restore({"grants": [{"seat": 0, "grant": "hug"}]}) == ERR_INVALID_DATA
			and fresh.restore({}) == OK
			and fresh.capture().is_empty()
			and fresh.grants.capture().is_empty()
	))
	section.detach()


# run with result applied as CampaignService applies it: the session's reward streams, the
# shipped reward rules and the loaded catalog.
func _apply(
		run: CampaignRunState, result: CampaignSession.BattleResult, session: CampaignSession
) -> CampaignRunState:
	return run.apply_battle(
			result, session.ids, session.reward_rolls(result), CombatRewardRules.load_default(),
			_catalog
	)


# A won result for the run's current node on M1. It names no seat's map, so it pays no reward.
func _won_result(run: CampaignRunState) -> CampaignSession.BattleResult:
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = run.floor_number
	result.node = run.node
	result.map_id = M1_ID
	result.pool_ids = PackedStringArray([M1_ID])
	result.is_finished = true
	result.is_won = true
	return result


func _outcome(hp: int, is_fallen: bool) -> CampaignSession.UnitOutcome:
	var outcome: CampaignSession.UnitOutcome = CampaignSession.UnitOutcome.new()
	outcome.seat = 0
	outcome.hp = hp
	outcome.is_fallen = is_fallen
	return outcome


func _grant(kind: CampaignGrant.Grant, amount: int, definition_id: String) -> CampaignSession.Grant:
	var grant: CampaignSession.Grant = CampaignSession.Grant.new()
	grant.seat = 0
	grant.grant = kind
	grant.amount = amount
	grant.definition_id = definition_id
	return grant


# The first combat node the run's node leads to; any combat node on the next floor when none does.
func _combat_child(run: CampaignRunState) -> int:
	var combat_types: Array[CampaignGraph.NodeType] = [
		CampaignGraph.NodeType.STANDARD, CampaignGraph.NodeType.KEY,
	]
	for child: int in run.graph.children_of(run.node):
		if combat_types.has(run.graph.type_of(child)):
			return child
	for node_id: int in run.graph.nodes_on_floor(run.floor_number + 1):
		if combat_types.has(run.graph.type_of(node_id)):
			return node_id
	return run.graph.children_of(run.node)[0]


# The real catalog with a fixture curse added: one counted effect ("Hit dealt: gain 1 Block").
func _catalog_with_curse() -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	for id: String in _catalog.ids():
		index.add(_catalog.path_of(id), _catalog.definition(id))
	var mark: EffectDefinition = EffectDefinition.new()
	mark.id = CURSE_EFFECT_ID
	mark.trigger = EffectTerms.Trigger.HIT_DEALT
	mark.scope = EffectTerms.Scope.ANY_ALLY_UNIT
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.BLOCK
	var amount: Constant = Constant.new()
	amount.value = 1.0
	gain.amount = amount
	mark.operations.append(gain)
	var curse: CurseDefinition = CurseDefinition.new()
	curse.id = CURSE_ID
	curse.display_name = "Test Curse"
	curse.effects.append(mark)
	index.add("res://tests/campaign/%s.tres" % [CURSE_ID], curse)
	index.finish()
	return index


# Every effect instance of the battle, each once: each map's and the cross-map ones (which a map's
# engine may list too).
func _battle_instances(battle: CombatEncounter) -> Array[EffectInstance]:
	var by_id: Dictionary[String, EffectInstance] = {}
	for instance: EffectInstance in battle.get_cross_map_instances():
		by_id[instance.instance_id] = instance
	for map: CombatSession in battle.get_sessions():
		for instance: EffectInstance in map.engine.get_instances():
			by_id[instance.instance_id] = instance
	var instances: Array[EffectInstance] = []
	instances.assign(by_id.values())
	return instances


func _object(id: String, kind: MapLayout.ObjectKind) -> MapState.ObjectState:
	var placed: MapState.ObjectState = MapState.ObjectState.new()
	placed.id = id
	placed.kind = kind
	return placed


func _change(object_id: String, unit_id: String, change: MapObjects.Change) -> CombatFact:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, object_id, unit_id)
	fact.key = change
	return fact


func _amount(fact: CombatFact, amount: int) -> CombatFact:
	fact.amount = amount
	return fact


# Every action at value, as a tally's entry.
func _counts(value: Variant) -> Dictionary:
	return {"hit": value, "defeat": value, "heal": value, "block": value, "non_combat": value}


static func _ids(maps: Array[CombatMapDefinition]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for map: CombatMapDefinition in maps:
		ids.append(map.id)
	return ids


static func _run_text(run: CampaignRunState) -> String:
	var parts: Array = [run.capture_map(), run.flow.capture()]
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		parts.append_array([
			seat_run.capture_roster(),
			seat_run.capture_heirlooms(),
			seat_run.capture_runes(),
			seat_run.capture_economy(),
		])
	return JSON.stringify(parts)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
