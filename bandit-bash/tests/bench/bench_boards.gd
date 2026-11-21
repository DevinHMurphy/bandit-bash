# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bench_boards.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## The move preview's four benchmark boards (move-preview.md, Where it stands), for
## [code]preview_bench.gd[/code] and the preview's zone cases: M1 turn 1, M1 engaged, a 9-enemy
## 6-unit key board on the Hall, and the Powder Keep engaged, each in its open player phase.
## "Engaged" is the first player phase in which at least a third of the enemies show an attack
## intent, every acting unit walking toward the enemies onto tiles outside the danger zone until
## then. [method close] ends the runs the boards were built in.
##
## @tutorial(The move preview): docs/design/move-preview.md

# A preloaded script used as a type (gdscript.md, Naming): the test helper has no class name.
const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const M1_PATH: String = "res://maps/standard/m1_greybox.tres"
const HALL_PATH: String = "res://maps/key/hall.tres"
const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"

## Every board, in the order the bench runs them.
const BOARDS: Array[String] = ["m1_turn_1", "m1_engaged", "key_engaged", "boss_engaged"]

## move-preview.md's benchmark size (its decision 3).
const BENCH_ENEMIES: int = 9
const BENCH_UNITS: int = 6

# tests/ui's seed, so the M1 boards are the one the UI cases play.
const M1_SEED: int = 0x0C0FFEE
# The key and boss runs' seed: its first mini-boss is the Bloodhound (mini_boss_cases.gd's).
const RUN_SEED: int = 8080
# Step 3, whose key packs field the most escorts (5); the boss floor.
const KEY_FLOOR: int = 12
const BOSS_FLOOR: int = 18
const NODE: int = 3

# A key map draws at most 5 escorts and its mini-boss; the 3 more the benchmark size needs are one
# of each M1 behavior (Aggressive, Hold, Support), at the key level.
const KEY_EXTRA_CLASSES: Array[String] = ["brute", "crossbowman", "hedge_healer"]
# The Mercenary army (4 units) plus two recruits with their starting weapons.
const RECRUITS: Array[String] = ["fighter", "mage"]

const MAX_ENGAGE_TURNS: int = 10

# How far from the enemy slots the key board's extra enemies may stand, in tiles.
const MAX_SPOT_REACH: int = 8

## What went wrong building a board, one line each; empty when every board was the intended one.
var failures: PackedStringArray = []

## Whether building prints its progress (the turns played to engage); off for tests.
var is_verbose: bool = true

var _catalog: EffectCatalog.Index = null
var _runs: Array[CampaignSession] = []


func _init(catalog: EffectCatalog.Index) -> void:
	_catalog = catalog


## The session of [param board], one of [constant BOARDS], in its open player phase; null with a
## line in [member failures] when it couldn't be built.
func build(board: String) -> CombatSession:
	var battle: CombatEncounter = null
	match board:
		"m1_turn_1", "m1_engaged":
			var run: CampaignSession = _new_run(M1_SEED)
			battle = BattleViewCases.begin_m1(_catalog, load(M1_PATH) as CombatMapDefinition, run)
			if battle != null:
				_send(battle, StartCommand.new(0))
		"key_engaged":
			battle = _begin(load(HALL_PATH) as CombatMapDefinition, KEY_FLOOR)
		"boss_engaged":
			battle = _begin(load(KEEP_PATH) as CombatMapDefinition, BOSS_FLOOR)
	if battle == null:
		failures.append("%s: the battle didn't begin" % [board])
		return null
	var session: CombatSession = battle.get_session(0)
	session.playback.play_all()
	if board == "key_engaged":
		_add_key_extras(session)
	if board.ends_with("_engaged"):
		var turns: int = _engage(battle, session)
		if turns < 0:
			failures.append("%s: not engaged within %d turns" % [board, MAX_ENGAGE_TURNS])
			return null
	return session


## Whether [param session] is [param board] as intended: intents shown, units to act, the
## benchmark size on the key and boss boards, turn 1 on M1 turn 1; a line in [member failures]
## otherwise. With [member is_verbose], prints the board.
func is_intended(board: String, session: CombatSession) -> bool:
	var state: CombatState = session.state
	var enemies: PackedStringArray = []
	for enemy_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		enemies.append(state.unit_type_of(enemy_id))
	var acting: PackedStringArray = TurnInputModel.acting_units(session, 0)
	if is_verbose:
		var intents: PackedStringArray = []
		if session.intents != null:
			for intent: EnemyIntent in session.intents.enemies:
				intents.append(str(EnemyIntent.Kind.find_key(intent.kind)))
		print("\n===== %s: turn %d, %d enemies (%s), %d acting units, %d player units =====" % [
			board, state.turn, enemies.size(), ", ".join(enemies), acting.size(),
			state.units_of(CombatFact.CombatSide.PLAYER).size(),
		])
		print("Intents: %s" % [", ".join(intents)])
	var wants_size: bool = board == "key_engaged" or board == "boss_engaged"
	var is_right: bool = (
			session.intents != null
			and not acting.is_empty()
			and (not wants_size or enemies.size() == BENCH_ENEMIES)
			and (not wants_size or acting.size() == BENCH_UNITS)
			and (board != "m1_turn_1" or state.turn == 1)
	)
	if not is_right:
		failures.append("%s: not the intended board" % [board])
	return is_right


## Ends every run a board was built in.
func close() -> void:
	for run: CampaignSession in _runs:
		run.close()
	_runs.clear()


# A battle on map at floor_number for seat 0's six units, turn 1 at once (no opening swap).
func _begin(map: CombatMapDefinition, floor_number: int) -> CombatEncounter:
	var run: CampaignSession = _new_run(RUN_SEED)
	var mercenary: StartingArmy = StartingArmy.build(_catalog, "mercenary", run.ids)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = mercenary.heirloom_ids.duplicate()
	for type_id: String in RECRUITS:
		var unit: UnitInstance = UnitInstance.new(run.ids.next_unit_id(type_id), type_id)
		var definition: UnitTypeDefinition = unit.definition(_catalog)
		var weapon_id: String = definition.starting_weapon_id if definition != null else ""
		if not weapon_id.is_empty():
			unit.weapon_id = run.ids.next_item_id(weapon_id)
			army.item_instances[unit.weapon_id] = ItemInstance.new(unit.weapon_id, weapon_id)
		army.unit_instances.append(unit)
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = floor_number
	request.node = NODE
	request.pool = [map]
	request.catalog = _catalog
	request.opening_swap[0] = false
	request.armies[0] = army
	return run.begin_battle(request)


func _new_run(run_seed: int) -> CampaignSession:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
	)
	_runs.append(run)
	return run


# KEY_EXTRA_CLASSES at the key level, on the enemy slots setup left free and then the free tiles
# nearest them, in MapLayout order; then the intents again, since adding records no fact.
func _add_key_extras(session: CombatSession) -> void:
	var state: CombatState = session.state
	var level: int = EnemySetup.level_for(KEY_FLOOR, true)
	var slots: Array[Vector2i] = session.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var spots: Array[Vector2i] = _free_tiles_near(state, slots, KEY_EXTRA_CLASSES.size())
	for index: int in mini(spots.size(), KEY_EXTRA_CLASSES.size()):
		var class_id: String = KEY_EXTRA_CLASSES[index]
		var definition: EnemyClassDefinition = _catalog.enemy_class(class_id)
		var unit: UnitInstance = UnitInstance.new(session.ids.next_unit_id(class_id), class_id)
		unit.level = level
		var items: Dictionary[String, ItemInstance] = {}
		unit.weapon_id = session.ids.next_item_id(definition.starting_weapon_id)
		items[unit.weapon_id] = ItemInstance.new(unit.weapon_id, definition.starting_weapon_id)
		if not definition.starting_equipment_id.is_empty():
			unit.equipment_id = session.ids.next_item_id(definition.starting_equipment_id)
			items[unit.equipment_id] = ItemInstance.new(
					unit.equipment_id, definition.starting_equipment_id
			)
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(
				_catalog, unit, items, CombatFact.CombatSide.ENEMY, -1, session.ids
		)
		for problem: String in loaded.problems:
			failures.append("key extra %s: %s" % [class_id, problem])
		for weapon: CombatState.WeaponStats in loaded.weapons:
			state.add_weapon(weapon)
		for instance: EffectInstance in loaded.effects:
			session.engine.register(instance)
		loaded.state.tile = spots[index]
		session.add_unit(loaded.state, loaded.bases)
	session.intents = null
	Intents.refresh(session, _catalog)


# Up to count free standing tiles: the slots first, then the nearest others by grid distance to
# any slot, each group in MapLayout order.
func _free_tiles_near(
		state: CombatState, slots: Array[Vector2i], count: int
) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for slot: Vector2i in slots:
		if found.size() < count and _is_free(state, slot):
			found.append(slot)
	var reach: int = 1
	while found.size() < count and reach <= MAX_SPOT_REACH:
		var ring: Array[Vector2i] = []
		for slot: Vector2i in slots:
			for tile: Vector2i in DangerZone.tiles_within(slot, Vector2i(reach, reach)):
				if not ring.has(tile) and not found.has(tile) and _is_free(state, tile):
					ring.append(tile)
		ring.sort_custom(MapLayout.is_before)
		for tile: Vector2i in ring:
			if found.size() < count:
				found.append(tile)
		reach += 1
	return found


func _is_free(state: CombatState, tile: Vector2i) -> bool:
	return (
			state.can_stand(tile, CombatGrid.MovementType.DEFAULT)
			and state.occupant_at(tile).is_empty()
	)


# Plays player phases, each acting unit walking toward the enemies (_toward_enemies) and waiting,
# until a player phase opens engaged (_is_engaged). Returns the turns ended; -1 if none did.
func _engage(battle: CombatEncounter, session: CombatSession) -> int:
	for turn: int in MAX_ENGAGE_TURNS:
		if session.is_finished:
			return -1
		if _is_engaged(session):
			return turn
		if is_verbose:
			print("engaging: turn %d, %d of %d enemies attack, %d player units" % [
				session.state.turn, _attacks(session), session.state.units_of(
						CombatFact.CombatSide.ENEMY
				).size(), session.state.units_of(CombatFact.CombatSide.PLAYER).size(),
			])
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			var tile: Vector2i = _toward_enemies(session, unit_id)
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			_send(battle, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", path))
		_send(battle, EndTurnCommand.new(0))
		session.playback.play_all()
	return MAX_ENGAGE_TURNS if _is_engaged(session) else -1


# Whether at least a third of session's enemies show an attack intent.
func _is_engaged(session: CombatSession) -> bool:
	var enemies: int = session.state.units_of(CombatFact.CombatSide.ENEMY).size()
	return enemies > 0 and _attacks(session) * 3 >= enemies


# How many of session's intents are attacks; 0 with no intents.
func _attacks(session: CombatSession) -> int:
	var attacks: int = 0
	if session.intents == null:
		return attacks
	for intent: EnemyIntent in session.intents.enemies:
		if intent.kind == EnemyIntent.Kind.ATTACK:
			attacks += 1
	return attacks


# unit_id's end tile nearest any enemy by grid distance among those no enemy can attack next
# phase, the first in MapLayout order on a tie; its own tile when none is safe.
func _toward_enemies(session: CombatSession, unit_id: String) -> Vector2i:
	var state: CombatState = session.state
	var best: Vector2i = state.tile_of(unit_id)
	var best_distance: int = -1
	var danger: DangerZone = null if session.intents == null else session.intents.danger
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		if danger != null and danger.is_threatened(tile):
			continue
		var nearest: int = -1
		for enemy_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
			var distance: int = state.grid.distance(tile, state.tile_of(enemy_id))
			if nearest < 0 or distance < nearest:
				nearest = distance
		if best_distance < 0 or nearest < best_distance:
			best = tile
			best_distance = nearest
	return best


func _send(battle: CombatEncounter, command: Command) -> void:
	battle.submit(command, 0)
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		if batch.is_rejected():
			failures.append("%s rejected: %s" % [batch.label, batch.rejected_reason])
