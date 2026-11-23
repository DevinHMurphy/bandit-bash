# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     partner_map_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Units on a partner's map for tests/sessions/run_all.gd, sent units and swap visitors alike: a
## sent unit's timed modifiers stay on its won map while it travels and land with it, keeping the
## phases they had left; its owner's Your Unit heirlooms act on it there, one instance and one
## counter for every map, and on nobody else, while phase-triggered and Any Ally ones stay home;
## a visitor's owner's heirlooms on its partner's map, its Pouch item weight as at home;
## Commander's Standard skipping a teammate's unit; a save mid-transfer and after the landing
## keeping both; and a mirror applying every batch with matching hashes.
##
## Each map is its seat's fixture map with a Drengr at (0, 3) and a Brute at (3, 2); seat 0's map
## also has an Archer at (2, 3), the unit sent.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const PLAYER_TILE: Vector2i = Vector2i(0, 3)
const ENEMY_TILE: Vector2i = Vector2i(3, 2)
const SECOND_TILE: Vector2i = Vector2i(2, 3)

# Any fixed seed for the visitor's campaign run.
const VISIT_SEED: int = 0x0C03

# Each test modifier's AddTimedModifier index, so a mirror tells them apart.
const HIT_INDEX: int = 0
const MOVE_INDEX: int = 1
const AVOID_INDEX: int = 2

# The heirlooms the cases give seat 0: two that follow its units, one that stays on its map.
const FOLLOWING: Array[String] = ["warhorse_lineage", "breakers_maul"]
const STAYING: Array[String] = ["iron_rations"]

# Warhorse Lineage's Movement and the fixture's base.
const BASE_MOVEMENT: int = 5
const LINEAGE_MOVEMENT: int = 1

# Commander's Standard's Block.
const STANDARD_BLOCK: int = 2


func run() -> void:
	_run(_test_timed_modifiers_travel)
	_run(_test_heirlooms_follow)
	_run(_test_visitor_heirlooms)
	_run(_test_standard_counts_your_units)
	_run(_test_save_mid_transfer)
	_run(_test_save_after_landing)
	_run(_test_mirror_follows)


# The won map keeps the timed modifiers while the unit travels; at the landing they join it with
# the phases they had left, counted from there, not from the send: "until Phase End" ends at the
# player Phase End it landed in, "until the end of the next phase" at the enemy Phase End after,
# and "next attack this combat" at its first attack there.
func _test_timed_modifiers_travel() -> bool:
	var battle: Battle = _coop(2)
	var home: CombatSession = battle.encounter.get_session(0)
	var target: CombatSession = battle.encounter.get_session(1)
	var sent: String = home.state.units_of(PLAYER)[1]
	_open(battle)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_give_modifiers(home.engine, sent)
	_resolve(battle, EndMapFixture.new(), 0)
	_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	_check("timed: kept on the won map while it is on its way", (
			home.engine.get_timed_modifiers(sent).size() == 3
			and target.engine.get_timed_modifiers(sent).is_empty()
			and battle.encounter.units_in_transit() == PackedStringArray([sent])
	))
	_resolve(battle, EndTurnCommand.new(1), 1)
	_check("timed: still on its way a turn later, nothing counted down", (
			not target.state.has_unit(sent)
			and home.engine.get_timed_modifiers(sent).size() == 3
	))
	_resolve(battle, EndTurnCommand.new(1), 1)
	_check("timed: they land with it, none left on the won map", (
			target.state.has_unit(sent)
			and _indexes_of(target.engine, sent) == PackedInt32Array([
				HIT_INDEX, MOVE_INDEX, AVOID_INDEX,
			])
			and home.engine.get_timed_modifiers(sent).is_empty()
			and target.stats(sent).get_int(CombatValue.Key.MOVEMENT) == BASE_MOVEMENT + 1
	), str(_indexes_of(target.engine, sent)))
	var hit: CombatSession.FactBatch = _resolve(
			battle, HitFixture.new(0, sent, _enemy_of(target)), 1
	)
	_check("timed: the next attack there spends it", (
			_indexes_of(target.engine, sent) == PackedInt32Array([MOVE_INDEX, AVOID_INDEX])
			and _expired_in(hit) == PackedInt32Array([HIT_INDEX])
	), str(_indexes_of(target.engine, sent)))
	_resolve(battle, EndTurnCommand.new(1), 1)
	var ended: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(0), 1)
	_check("timed: each ends at the phase end it had left", (
			target.engine.get_timed_modifiers(sent).is_empty()
			and _expiry_side(ended, MOVE_INDEX) == PLAYER
			and _expiry_side(ended, AVOID_INDEX) == ENEMY
			and target.engine.diagnostics.is_empty()
	), _kinds_of(ended.facts))
	return true


# Seat 0's Your Unit heirlooms join the map its unit is sent to, the same instances as at home, and
# act on that unit there and on no unit of seat 1: Warhorse Lineage's Movement, Breaker's Maul
# counting its hits on one counter for both maps. A phase-triggered one (Iron Rations) and an Any
# Ally one with a position condition, which is no cross-map effect, stay on seat 0's map.
func _test_heirlooms_follow() -> bool:
	var battle: Battle = _coop(2)
	var home: CombatSession = battle.encounter.get_session(0)
	var target: CombatSession = battle.encounter.get_session(1)
	var sent: String = home.state.units_of(PLAYER)[1]
	var own_unit: String = _player_of(target)
	var owned: Dictionary[String, EffectInstance] = _own(battle, 0, FOLLOWING + STAYING)
	var positional: EffectInstance = battle.army_effect(0, _adjacent_ally_block())
	home.engine.register(positional)
	_open(battle)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("follow: none on the partner's map before a send", (
			target.engine.get_instance(owned["warhorse_lineage"].instance_id) == null
	))
	_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	var problems: PackedStringArray = []
	for heirloom_id: String in FOLLOWING:
		var instance: EffectInstance = owned[heirloom_id]
		if target.engine.get_instance(instance.instance_id) != instance:
			problems.append("%s isn't the home instance" % [heirloom_id])
	for heirloom_id: String in STAYING:
		if target.engine.get_instance(owned[heirloom_id].instance_id) != null:
			problems.append("%s followed" % [heirloom_id])
	if (
			CombatEncounter.is_cross_map(positional)
			or target.engine.get_instance(positional.instance_id) != null
	):
		problems.append("the positional Any Ally effect followed")
	_check("follow: Your Unit ones join at the send, the same instances; the rest stay", (
			problems.is_empty()
	), str(problems))
	_resolve(battle, EndTurnCommand.new(1), 1)
	_check("follow: it acts on the sent unit there and not on the map's own", (
			target.state.has_unit(sent)
			and target.stats(sent).get_int(CombatValue.Key.MOVEMENT)
			== BASE_MOVEMENT + LINEAGE_MOVEMENT
			and target.stats(own_unit).get_int(CombatValue.Key.MOVEMENT) == BASE_MOVEMENT
	))
	var maul: EffectInstance = owned["breakers_maul"]
	_resolve(battle, HitFixture.new(0, sent, _enemy_of(target)), 1)
	var after_sent: int = maul.get_counter(EffectTerms.Lane.COMBAT)
	_resolve(battle, HitFixture.new(1, own_unit, _enemy_of(target)), 1)
	_check("follow: one counter, counting the sent unit's hits only", (
			after_sent == 1
			and maul.get_counter(EffectTerms.Lane.COMBAT) == 1
			and home.engine.get_instance(maul.instance_id) == maul
			and target.engine.diagnostics.is_empty()
	), "%d %d" % [after_sent, maul.get_counter(EffectTerms.Lane.COMBAT)])
	return true


# A swap visitor's owner's Your Unit heirlooms and curses join its partner's map at Begin, before
# deployment: they act on the visitor and on none of the partner's units, and its Pouch item
# weight is its army's (Heavy Pack), as at home; Iron Rations stays on the owner's map.
func _test_visitor_heirlooms() -> bool:
	var made: CampaignSession = Fixture.session(VISIT_SEED, 2)
	var run: CampaignRunState = made.run
	var mine: String = _army_unit(run, 0)
	var theirs: String = _army_unit(run, 1)
	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	made.submit(AnswerSwapCommand.new(1, 0, true, mine, theirs))
	var request: CampaignSession.BattleRequest = _combat_request(made)
	var battle: CombatEncounter = null
	if request != null:
		request.armies[0].heirloom_ids.append_array(
				PackedStringArray(["warhorse_lineage", "heavy_pack", "iron_rations"])
		)
		request.opening_swap = {0: false, 1: false}
		battle = made.begin_battle(request)
	if battle == null:
		_check("visitor: the battle begins", false)
		made.close()
		return true
	var home: CombatSession = battle.session_of_seat(0)
	var host: CombatSession = battle.session_of_seat(1)
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var lineage: EffectInstance = _army_instance(home, 0, catalog, "warhorse_lineage")
	var pack: EffectInstance = _army_instance(home, 0, catalog, "heavy_pack")
	var rations: EffectInstance = _army_instance(home, 0, catalog, "iron_rations")
	var host_unit: String = _seat_unit(host, 1)
	var home_unit: String = _seat_unit(home, 0)
	_check("visitor: its owner's heirloom and curse on the partner's map, Iron Rations not", (
			lineage != null and pack != null and rations != null
			and host.engine.get_instance(lineage.instance_id) == lineage
			and host.engine.get_instance(pack.instance_id) == pack
			and host.engine.get_instance(rations.instance_id) == null
	))
	_check("visitor: they act on the visitor, not on the partner's units", (
			host.state.has_unit(mine)
			and lineage != null
			and host.engine.applies_to(lineage, mine)
			and not host.engine.applies_to(lineage, host_unit)
	))
	var weights: String = "%d %d %d" % [
		host.state.unit(mine).pouch_item_weight,
		home.state.unit(home_unit).pouch_item_weight,
		host.state.unit(host_unit).pouch_item_weight,
	]
	_check("visitor: its Pouch item weight is its army's, as at home", (
			host.state.unit(mine).pouch_item_weight == home.state.unit(home_unit).pouch_item_weight
			and host.state.unit(mine).pouch_item_weight
			!= host.state.unit(host_unit).pouch_item_weight
	), weights)
	made.close()
	return true


# Seat 0's Commander's Standard at its Phase Start: seat 0's commander and Archer within 2 tiles
# gain its Block; seat 1's unit, sent there and landed beside the commander, gains none.
func _test_standard_counts_your_units() -> bool:
	var battle: Battle = _coop(2)
	var home: CombatSession = battle.encounter.get_session(0)
	var commander: String = _player_of(home)
	var archer: String = home.state.units_of(PLAYER)[1]
	home.commander_ids[0] = commander
	home.state.commander_ids = home.commander_ids.duplicate()
	_own(battle, 0, ["commanders_standard"])
	var teammate: String = _player_of(battle.encounter.get_session(1))
	_open(battle)
	_resolve(battle, EndMapFixture.new(), 1)
	_reason_of(battle, SendUnitsCommand.new(1, PackedStringArray([teammate]), 0), 1)
	_resolve(battle, EndTurnCommand.new(0), 0)
	var distance: int = _distance(home.state.tile_of(teammate), home.state.tile_of(commander))
	_check("standard: Your Units near the commander, never a teammate's", (
			home.state.has_unit(teammate)
			and distance <= 2
			and home.state.get_block(commander) == STANDARD_BLOCK
			and home.state.get_block(archer) == STANDARD_BLOCK
			and home.state.get_block(teammate) == 0
	), "%d %d %d, %d away" % [
		home.state.get_block(commander), home.state.get_block(archer),
		home.state.get_block(teammate), distance,
	])
	return true


# Saved and Continued with the unit on its way: its timed modifiers on its won map, its owner's
# heirlooms on both maps as one instance; then it lands with them, the same as on the host.
func _test_save_mid_transfer() -> bool:
	var host: Battle = _coop(2)
	var sent: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	var owned: Dictionary[String, EffectInstance] = _own(host, 0, FOLLOWING)
	_open(host)
	_resolve(host, EndTurnCommand.new(0), 0)
	_give_modifiers(host.encounter.get_session(0).engine, sent)
	_resolve(host, EndMapFixture.new(), 0)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	var copy: Battle = _coop(2)
	var load_error: Error = _continue(host, copy)
	var lineage_id: String = owned["warhorse_lineage"].instance_id
	var copy_home: CombatSession = copy.encounter.get_session(0)
	var copy_target: CombatSession = copy.encounter.get_session(1)
	_check("save mid-transfer: loads as saved, one heirloom instance for both maps", (
			load_error == OK
			and _maps_match(host, copy)
			and copy.encounter.state_hash() == host.encounter.state_hash()
			and copy_home.engine.get_timed_modifiers(sent).size() == 3
			and copy_target.engine.get_instance(lineage_id) != null
			and copy_target.engine.get_instance(lineage_id)
			== copy_home.engine.get_instance(lineage_id)
	), error_string(load_error))
	for battle: Battle in [host, copy]:
		_resolve(battle, EndTurnCommand.new(1), 1)
		_resolve(battle, EndTurnCommand.new(1), 1)
	_check("save mid-transfer: it lands with its modifiers, the same as on the host", (
			copy_target.state.has_unit(sent)
			and _indexes_of(copy_target.engine, sent)
			== _indexes_of(host.encounter.get_session(1).engine, sent)
			and _indexes_of(copy_target.engine, sent).size() == 3
			and copy_home.engine.get_timed_modifiers(sent).is_empty()
			and _maps_match(host, copy)
	))
	return true


# Saved and Continued after the landing: the modifiers on the partner's map with their phases,
# the heirloom one instance whose counter goes on for both maps.
func _test_save_after_landing() -> bool:
	var host: Battle = _coop(2)
	var sent: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	var owned: Dictionary[String, EffectInstance] = _own(host, 0, FOLLOWING)
	_open(host)
	_resolve(host, EndTurnCommand.new(0), 0)
	_give_modifiers(host.encounter.get_session(0).engine, sent)
	_resolve(host, EndMapFixture.new(), 0)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	_resolve(host, EndTurnCommand.new(1), 1)
	_resolve(host, EndTurnCommand.new(1), 1)
	var copy: Battle = _coop(2)
	var load_error: Error = _continue(host, copy)
	var maul_id: String = owned["breakers_maul"].instance_id
	var copy_maul: EffectInstance = copy.encounter.get_session(1).engine.get_instance(maul_id)
	_check("save after landing: loads as saved", (
			load_error == OK
			and _maps_match(host, copy)
			and _indexes_of(copy.encounter.get_session(1).engine, sent).size() == 3
			and copy_maul != null
			and copy.encounter.get_session(0).engine.get_instance(maul_id) == copy_maul
	), error_string(load_error))
	for battle: Battle in [host, copy]:
		var map: CombatSession = battle.encounter.get_session(1)
		_resolve(battle, HitFixture.new(0, sent, _enemy_of(map)), 1)
		_resolve(battle, EndTurnCommand.new(1), 1)
		_resolve(battle, EndTurnCommand.new(0), 1)
	_check("save after landing: it plays on the same as the host", (
			copy_maul != null
			and copy_maul.get_counter(EffectTerms.Lane.COMBAT)
			== owned["breakers_maul"].get_counter(EffectTerms.Lane.COMBAT)
			and copy.encounter.get_session(1).engine.get_timed_modifiers(sent).is_empty()
			and _maps_match(host, copy)
	))
	return true


# A client's mirror, loaded with the modifiers already given, follows every batch in the host's
# order: the send, the landing with its modifiers, a hit counted by the following heirloom, and
# each expiry; every map's and the encounter's hash matching after each batch.
func _test_mirror_follows() -> bool:
	var host: Battle = _coop(2)
	var mirror: Battle = _coop(2)
	var sent: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	var owned: Dictionary[String, EffectInstance] = _own(host, 0, FOLLOWING)
	_open(host)
	_give_modifiers(host.encounter.get_session(0).engine, sent)
	var loaded: Error = mirror.encounter.load_snapshot(
			WireCases.Kit.through_json(host.encounter.snapshot()) as Dictionary
	)
	var sent_batches: Array[CombatSession.FactBatch] = []
	var is_encounter: Array[bool] = []
	host.encounter.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		sent_batches.append(batch)
		is_encounter.append(true)
	)
	for session: CombatSession in host.encounter.get_sessions():
		session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
			sent_batches.append(batch)
			is_encounter.append(false)
		)
	var target: CombatSession = host.encounter.get_session(1)
	_resolve(host, EndMapFixture.new(), 0)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	_resolve(host, EndTurnCommand.new(1), 1)
	_resolve(host, HitFixture.new(0, sent, _enemy_of(target)), 1)
	_resolve(host, EndTurnCommand.new(1), 1)
	_resolve(host, EndTurnCommand.new(0), 1)

	var results: Array[Error] = []
	for index: int in sent_batches.size():
		var batch: CombatSession.FactBatch = WireCases.Kit.batch_through_json(sent_batches[index])
		if is_encounter[index]:
			results.append(mirror.encounter.apply_batch(batch))
		else:
			results.append(mirror.encounter.get_session(batch.session_id).apply_batch(batch))
	var maul_id: String = owned["breakers_maul"].instance_id
	var mirror_target: CombatSession = mirror.encounter.get_session(1)
	_check("mirror: every batch applies, every hash matching", (
			loaded == OK and results.count(OK) == results.size()
	), "%s %s" % [error_string(loaded), results])
	_check("mirror: the battle as the host has it", (
			_maps_match(host, mirror)
			and mirror.encounter.state_hash() == host.encounter.state_hash()
			and mirror_target.state.has_unit(sent)
			and mirror_target.engine.get_timed_modifiers(sent).is_empty()
			and mirror.encounter.get_session(0).engine.get_timed_modifiers(sent).is_empty()
			and mirror_target.engine.get_instance(maul_id)
			== mirror.encounter.get_session(0).engine.get_instance(maul_id)
			and mirror_target.engine.get_instance(maul_id).get_counter(EffectTerms.Lane.COMBAT)
			== owned["breakers_maul"].get_counter(EffectTerms.Lane.COMBAT)
	))
	return true


# Gives unit_id three timed modifiers from no effect, told apart by their operation index:
# +15 Hit on its next attack this combat (Momentum's shape), +1 Movement until Phase End, and +10
# Avoid until the end of the next phase.
func _give_modifiers(engine: EffectEngine, unit_id: String) -> void:
	engine.add_timed_modifier(
			unit_id, _modifier(CombatValue.Key.HIT, 15.0), AddTimedModifier.End.THIS_COMBAT, 1,
			"", HIT_INDEX
	)
	engine.add_timed_modifier(
			unit_id, _modifier(CombatValue.Key.MOVEMENT, 1.0),
			AddTimedModifier.End.UNTIL_PHASE_END, 0, "", MOVE_INDEX
	)
	engine.add_timed_modifier(
			unit_id, _modifier(CombatValue.Key.AVOID, 10.0),
			AddTimedModifier.End.END_OF_NEXT_PHASE, 0, "", AVOID_INDEX
	)


# "Hit dealt by Any Ally Unit while adjacent to an ally: that unit gains 2 Block": an Any Ally
# army effect whose position condition keeps it off the encounter's cross-map list.
func _adjacent_ally_block() -> EffectDefinition:
	var definition: EffectDefinition = _hit_dealt_block("adjacent_ally_block", 2.0)
	definition.scope = EffectTerms.Scope.ANY_ALLY_UNIT
	var adjacent: WhilePositionCondition = WhilePositionCondition.new()
	adjacent.kind = WhilePositionCondition.Kind.ADJACENT_TO
	definition.conditions.append(adjacent)
	(definition.operations[0] as GainResource).target = FactActor.new()
	return definition


func _modifier(key: int, value: float) -> Modifier:
	return Modifier.new(key, Modifier.Mode.ADD, value, Modifier.SourceKind.UNIT_TRAIT, "", "test")


# The operation indexes of the timed modifiers unit_id holds in engine, in the order gained.
func _indexes_of(engine: EffectEngine, unit_id: String) -> PackedInt32Array:
	var indexes: PackedInt32Array = []
	for timed: TimedModifier in engine.get_timed_modifiers(unit_id):
		indexes.append(timed.operation_index)
	return indexes


# The operation indexes batch's MODIFIER_EXPIRED facts name, in order.
func _expired_in(batch: CombatSession.FactBatch) -> PackedInt32Array:
	var indexes: PackedInt32Array = []
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.MODIFIER_EXPIRED:
			indexes.append(fact.key)
	return indexes


# The side of the Phase End right before the modifier with operation index expired in batch;
# NONE when it didn't.
func _expiry_side(batch: CombatSession.FactBatch, index: int) -> CombatFact.CombatSide:
	var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.PHASE_END:
			side = fact.side
		elif fact.kind == CombatFact.Kind.MODIFIER_EXPIRED and fact.key == index:
			return side
	return CombatFact.CombatSide.NONE


# Registers each heirloom's effects for seat's army as Begin does: in the encounter when
# cross-map, else on its seat's map. Returns the last instance of each heirloom by id.
func _own(
		battle: Battle, seat: int, heirloom_ids: Array[String]
) -> Dictionary[String, EffectInstance]:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var home: CombatSession = battle.encounter.session_of_seat(seat)
	var owned: Dictionary[String, EffectInstance] = {}
	for heirloom_id: String in heirloom_ids:
		for instance: EffectInstance in Loadout.heirloom_effects(
				catalog, heirloom_id, seat, battle.ids
		):
			if not battle.encounter.add_cross_map(instance):
				home.engine.register(instance)
			owned[heirloom_id] = instance
	return owned


# The instance of heirloom_id's first effect that seat's army holds on map; null when none.
func _army_instance(
		map: CombatSession, seat: int, catalog: EffectCatalog.Index, heirloom_id: String
) -> EffectInstance:
	var heirloom: HeirloomDefinition = catalog.heirloom(heirloom_id)
	if heirloom == null or heirloom.effects.is_empty():
		return null
	for instance: EffectInstance in map.engine.get_instances():
		if (
				instance.owner.kind == EffectOwner.Kind.ARMY
				and instance.owner.seat == seat
				and instance.definition == heirloom.effects[0]
		):
			return instance
	return null


# Loads host's battle, saved as saving writes it, into copy. Returns the load's error.
func _continue(host: Battle, copy: Battle) -> Error:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, host.encounter.seats
	)
	run.encounter = host.encounter
	var section: CombatStateSection = CombatStateSection.new()
	section.attach(run)
	var state_data: Dictionary = WireCases.Kit.through_json(section.capture()) as Dictionary
	var effects_data: Dictionary = (
			WireCases.Kit.through_json(section.effects.capture()) as Dictionary
	)
	section.detach()
	var loader: CombatStateSection = CombatStateSection.new()
	loader.restore(state_data)
	loader.effects.restore(effects_data)
	return loader.load_into(copy.encounter)


func _maps_match(one: Battle, other: Battle) -> bool:
	for session: CombatSession in one.encounter.get_sessions():
		if other.encounter.get_session(session.session_id).state_hash() != session.state_hash():
			return false
	return true


# A battle of seat_count seats on the fixture map, each map with its seat's Drengr and a Brute;
# seat 0's map also has an Archer.
func _coop(seat_count: int) -> Battle:
	var seats: PackedInt32Array = []
	for seat: int in seat_count:
		seats.append(seat)
	var battle: Battle = Battle.new(seats)
	battle.set_up()
	battle.open()
	for seat: int in seat_count:
		battle.add_unit(seat, "Drengr", PLAYER, seat, PLAYER_TILE)
		battle.add_unit(seat, "Brute", ENEMY, -1, ENEMY_TILE)
	battle.add_unit(0, "Archer", PLAYER, 0, SECOND_TILE)
	return battle


func _open(battle: Battle) -> void:
	for session: CombatSession in battle.encounter.get_sessions():
		session.open_battle()


# Submits command to session_id through the encounter and resolves the queue; returns the last
# map batch, or an empty one when there was none.
func _resolve(battle: Battle, command: Command, session_id: int) -> CombatSession.FactBatch:
	battle.encounter.submit(command, session_id)
	var batches: Array[CombatSession.FactBatch] = battle.encounter.resolve_queued()
	return CombatSession.FactBatch.new() if batches.is_empty() else batches[batches.size() - 1]


# Submits command through the encounter and returns why it was refused; empty when it resolved.
func _reason_of(battle: Battle, command: Command, session_id: int) -> String:
	var arrival: int = battle.encounter.submit(command, session_id)
	for batch: CombatSession.FactBatch in battle.encounter.resolve_queued():
		if batch.arrival == arrival and batch.is_rejected():
			return batch.rejected_reason
	return ""


# Moves made's run into its first floor-1 Standard combat node and returns its battle request;
# null when floor 1 has none.
func _combat_request(made: CampaignSession) -> CampaignSession.BattleRequest:
	var run: CampaignRunState = made.run
	for node: int in run.next_nodes():
		if run.graph.type_of(node) == CampaignGraph.NodeType.STANDARD:
			Fixture.choose(made, node)
			return run.battle_request(CombatMapPools.load_default(), EffectCatalog.index())
	return null


# The first living unit of seat's army that isn't its commander; empty when there is none.
func _army_unit(run: CampaignRunState, seat: int) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit.instance_id
	return ""


# A player unit of seat on map, its own, not a visitor.
func _seat_unit(map: CombatSession, seat: int) -> String:
	for unit_id: String in map.state.units_of(PLAYER):
		if map.state.seat_of(unit_id) == seat:
			return unit_id
	return ""


func _player_of(session: CombatSession) -> String:
	return session.state.units_of(PLAYER)[0]


func _enemy_of(session: CombatSession) -> String:
	return session.state.units_of(ENEMY)[0]


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# One attack by its unit on a target that hits, as an exchange records it, then the attack's end:
# ATTACK_MADE, HIT_DEALT, and the attacker's "next attack" uses spent. Needs no forecast.
class HitFixture:
	extends Command

	var target: String = ""

	func _init(sender: int, unit_id: String, target_id: String) -> void:
		seat = sender
		actor_id = unit_id
		target = target_id

	func get_label() -> String:
		return "hit"

	func resolve(session: CombatSession) -> void:
		var engine: EffectEngine = session.engine
		engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))
		engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, actor_id, target))
		engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, actor_id)
