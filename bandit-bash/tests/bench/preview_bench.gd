# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_bench.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends Node
## The move preview's baseline (move-preview.md, build step A): on four boards (M1 turn 1, M1
## engaged, a 9-enemy 6-unit key board on the Hall, the Powder Keep engaged), every tile each
## acting unit can end on is hovered through a threaded [MovePreview.Queue] as the battle runs it,
## giving the latency per hover and per sweep (all of one unit's tiles in turn), and the frame that
## starts each; then a per-phase profile of sampled hovers on the main thread.[br]
## Run from the repo root, with board names after [code]--[/code] to run only those:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/preview_bench.tscn -- key_engaged
## [/code][br]
## A release build runs it through [code]tests/bench/release_bench.sh[/code]. Measures only;
## exits with code 1 if a board is not the intended one.
##
## @tutorial(The move preview): docs/design/move-preview.md

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const PreviewProfile = preload("res://tests/bench/preview_profile.gd")

const M1_PATH: String = "res://maps/standard/m1_greybox.tres"
const HALL_PATH: String = "res://maps/key/hall.tres"
const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"

const BOARDS: Array[String] = ["m1_turn_1", "m1_engaged", "key_engaged", "boss_engaged"]

# tests/ui's seed, so the M1 boards are the one the UI cases play.
const M1_SEED: int = 0x0C0FFEE
# The key and boss runs' seed: its first mini-boss is the Bloodhound (mini_boss_cases.gd's).
const RUN_SEED: int = 8080
# Step 3, whose key packs field the most escorts (5); the boss floor.
const KEY_FLOOR: int = 12
const BOSS_FLOOR: int = 18
const NODE: int = 3

# move-preview.md's benchmark size (its question 3).
const BENCH_ENEMIES: int = 9
const BENCH_UNITS: int = 6
# a key map draws at most 5 escorts and its mini-boss; the 3 more the benchmark size
# needs are one of each M1 behavior (Aggressive, Hold, Support), at the key level.
const KEY_EXTRA_CLASSES: Array[String] = ["brute", "crossbowman", "hedge_healer"]
# the Mercenary army (4 units) plus two recruits with their starting weapons.
const RECRUITS: Array[String] = ["fighter", "mage"]

# "engaged" is the first player phase in which at least a third of the enemies show an
# attack intent; until then every unit walks to the tile nearest an enemy outside the danger zone.
const MAX_ENGAGE_TURNS: int = 10

# How far from the enemy slots the key board's extra enemies may stand, in tiles.
const MAX_SPOT_REACH: int = 8

# P05 question 10's target per hover, in microseconds (move-preview.md, its question 4: p95, debug).
const TARGET_USEC: float = 50000.0

# The wait between polls of the worker: finer than a 60 Hz frame, so a latency is the worker's own
# to within a millisecond, without a busy loop taking a core from it.
const POLL_USEC: int = 1000

var _failures: PackedStringArray = []
var _catalog: EffectCatalog.Index = null
var _runs: Array[CampaignSession] = []


func _ready() -> void:
	_catalog = EffectCatalog.index()
	_print_header()
	var chosen: PackedStringArray = _chosen_boards()
	for board: String in chosen:
		var session: CombatSession = _build(board)
		if session != null and _check_fixture(board, session):
			_bench_worker(session)
			PreviewProfile.new(session, _catalog).run()
	for run: CampaignSession in _runs:
		run.close()
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== EN13 move preview baseline ===")
	print("Godot %s, %s build; verify mode off in every preview sandbox, as the preview sets it" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores; previews on one worker thread (WorkerThreadPool)" % [
		OS.get_processor_name(), OS.get_processor_count(),
	])
	print("Times in microseconds. One hover per move tile of every acting unit; one warm-up first.")


# The boards named after "--", in BOARDS order; every board when none is named.
func _chosen_boards() -> PackedStringArray:
	var named: PackedStringArray = OS.get_cmdline_user_args()
	var chosen: PackedStringArray = []
	for board: String in BOARDS:
		if named.is_empty() or named.has(board):
			chosen.append(board)
	for named_board: String in named:
		if not BOARDS.has(named_board):
			_failures.append("no board named %s (boards: %s)" % [named_board, ", ".join(BOARDS)])
	return chosen


# The session of board, in its open player phase; null when it couldn't be built.
func _build(board: String) -> CombatSession:
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
		_failures.append("%s: the battle didn't begin" % [board])
		return null
	var session: CombatSession = battle.get_session(0)
	session.playback.play_all()
	if board == "key_engaged":
		_add_key_extras(session)
	if board.ends_with("_engaged"):
		var turns: int = _engage(battle, session)
		if turns < 0:
			_failures.append("%s: not engaged within %d turns" % [board, MAX_ENGAGE_TURNS])
			return null
	return session


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
			_failures.append("key extra %s: %s" % [class_id, problem])
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
			_failures.append("%s rejected: %s" % [batch.label, batch.rejected_reason])


func _check_fixture(board: String, session: CombatSession) -> bool:
	var state: CombatState = session.state
	var enemies: PackedStringArray = []
	for enemy_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		enemies.append(state.unit_type_of(enemy_id))
	var acting: PackedStringArray = TurnInputModel.acting_units(session, 0)
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
		_failures.append("%s: not the intended board" % [board])
	return is_right


# Every move tile of every acting unit through one threaded queue, a unit's tiles in turn: the
# latency of each hover (request to the preview returned), of each unit's sweep, and the
# main thread's frame that starts each hover (Intents.prepare_preview).
func _bench_worker(session: CombatSession) -> void:
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var hovers: PackedInt64Array = []
	var starts: PackedInt64Array = []
	var sweeps: PackedInt64Array = []
	var warm: Array[Vector2i] = TurnInputModel.move_tiles(session, units[0])
	_hover(queue, session, units[0], warm[warm.size() - 1], PackedInt64Array())
	for unit_id: String in units:
		var swept: int = Time.get_ticks_usec()
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			hovers.append(_hover(queue, session, unit_id, tile, starts))
		sweeps.append(Time.get_ticks_usec() - swept)
	print("\n-- On the worker thread, as the battle runs it --")
	_report("hover to preview (latency)", hovers)
	_report("  frame that starts it (main thread)", starts)
	_report("sweep: every move tile of one unit", sweeps)
	print("Target %.0f per hover: median %s, p95 %s" % [
		TARGET_USEC,
		"met" if _median(hovers) <= TARGET_USEC else "missed",
		"met" if _p95(hovers) <= TARGET_USEC else "missed",
	])


# One hover through queue: its latency; the frame that starts it is appended to starts.
func _hover(
		queue: MovePreview.Queue,
		session: CombatSession,
		unit_id: String,
		tile: Vector2i,
		starts: PackedInt64Array
) -> int:
	var requested: int = Time.get_ticks_usec()
	queue.request(unit_id, tile)
	var ready: MovePreview = queue.run_pending(session)
	starts.append(Time.get_ticks_usec() - requested)
	while ready == null:
		OS.delay_usec(POLL_USEC)
		ready = queue.run_pending(session)
	var latency: int = Time.get_ticks_usec() - requested
	# The queue drops a request repeating the preview it shows, which would wait forever here.
	queue.clear()
	return latency


func _report(label: String, samples: PackedInt64Array) -> void:
	samples.sort()
	print("%-44s n=%4d  median %9.0f  p95 %9.0f  max %9.0f" % [
		label, samples.size(), _median(samples), _p95(samples),
		0.0 if samples.is_empty() else float(samples[samples.size() - 1]),
	])


static func _median(sorted: PackedInt64Array) -> float:
	var count: int = sorted.size()
	if count == 0:
		return 0.0
	var middle: int = floori(count / 2.0)
	if count % 2 == 1:
		return float(sorted[middle])
	return (sorted[middle - 1] + sorted[middle]) / 2.0


# Nearest-rank 95th percentile.
static func _p95(sorted: PackedInt64Array) -> float:
	if sorted.is_empty():
		return 0.0
	var rank: int = ceili(0.95 * sorted.size())
	return float(sorted[clampi(rank, 1, sorted.size()) - 1])
