# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_equality_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The move preview's equality cases (move-preview.md, Correctness): on seeded random boards of the
## real catalog's enemy classes, mini-bosses, boss and player unit types, every tile each player
## unit can end its move on is previewed ([method Intents.preview], checking mode on) and re-planned
## in full ([method Intents.compute] on a copy with the unit walked there). Each intent's enemy,
## kind, target, tile, order, path, weapon, area, kills and forecast must match, so must the danger
## zone, and checking mode must find no kept decision or reused attack forecast changed, in the
## preview or the re-plan, which reuses forecasts across its own steps. Then checking mode itself:
## it reports a kept decision made stale behind the intents' back, and changes no result. New
## content joins the draw on its own. Reports each case through the check callable it is given.
##
## @tutorial(The move preview): docs/design/move-preview.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/preview"

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

# Boards and the seed of the first; board n draws from BASE_SEED + n.
const BOARDS: int = 10
const BASE_SEED: int = 1320

const MIN_WIDTH: int = 10
const MAX_WIDTH: int = 18
const MIN_HEIGHT: int = 6
const MAX_HEIGHT: int = 9
const MIN_ENEMIES: int = 2
const MAX_ENEMIES: int = 5
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4
# Enemy phases played before the board is checked, at most, so cooldowns and positions vary.
const MAX_TURNS: int = 2
# Tries to find a free tile for one unit before it is left out.
const PLACE_TRIES: int = 40
# Of every 100 boards or units: wounded units, boards with flooded tiles, and boards where the
# darkness has arrived (every enemy not holding a post turns Aggressive).
const WOUND_PERCENT: int = 35
const FLOOD_PERCENT: int = 25
const ARRIVED_PERCENT: int = 20
const MAX_FLOODED: int = 5

# Mostly open ground, with cover, walls, water and forts (Phase Start healing) among it.
const TERRAIN: Array[String] = [
	"plain", "plain", "plain", "plain", "plain", "plain", "plain", "plain", "plain", "plain",
	"forest", "forest", "thicket", "wall", "fort", "river", "road",
]

# Every player unit type of the catalog but the commanders, which a run fields only once.
const PLAYER_TYPES: Array[String] = [
	"archer", "battle_medic", "brawler", "fighter", "freewing", "hakkapel", "lance_armor",
	"lancer", "mage", "sellsword", "shaman", "suncaster", "thief", "ward",
]

const BRUTE: String = "brute"
const CROSSBOWMAN: String = "crossbowman"

const PLAIN_12X8: Array[String] = [
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
]

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null
var _enemy_classes: PackedStringArray = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()
	_enemy_classes = EnemySetup.standard_classes(_catalog)
	_enemy_classes.append_array(EnemySetup.mini_boss_ids(_catalog))
	_enemy_classes.append("powder_baron")


## Runs every case. Checking mode is a static switch, so it is restored before returning.
func run() -> void:
	var was_checking: bool = Intents.is_checking
	_test_random_boards()
	_test_checking_reports_stale()
	_test_checking_changes_nothing()
	Intents.is_checking = was_checking


# Every board, every player unit yet to act, every tile it can end on: the preview with checking
# mode on equals the full re-plan, and checking mode found nothing. Overall, previews must have
# kept decisions and checking mode must have checked them, or the suite proves nothing.
func _test_random_boards() -> void:
	Intents.is_checking = true
	var kept_total: int = 0
	var tiles_total: int = 0
	var reused_total: int = 0
	var made_total: int = 0
	for board: int in BOARDS:
		var board_seed: int = BASE_SEED + board
		var world: AiWorld = _board(board_seed)
		var session: CombatSession = world.session
		if session.is_finished or session.intents == null:
			_check.call("equality: board %d still has a player phase" % [board_seed], false, (
					"finished %s, intents %s" % [session.is_finished, session.intents != null]
			))
			continue
		var tiles: int = 0
		var checked: int = 0
		var mismatch: String = ""
		var flagged: String = ""
		for unit_id: String in session.state.units_of(PLAYER):
			if session.state.unit(unit_id).has_acted:
				continue
			var walker: EnemyAI.Board = EnemyAI.Board.new(session.engine, unit_id, {})
			for tile: Vector2i in walker.reach:
				tiles += 1
				var preview: Intents = Intents.preview(session, unit_id, tile)
				var full: Intents = _full_replan(session, unit_id, walker.path_to(tile))
				var seen: String = _intents_text(preview)
				var expected: String = _intents_text(full)
				if mismatch.is_empty() and seen != expected:
					mismatch = "%s to %s: preview %s / full %s" % [unit_id, tile, seen, expected]
				# The full re-plan reuses forecasts across its own steps, so checking mode checks
				# it too.
				for shown: Intents in [preview, full]:
					if shown == null:
						continue
					checked += shown.checked
					reused_total += shown.forecasts_reused
					made_total += shown.forecasts_made
					var flags: String = _check_lines(shown)
					if flagged.is_empty() and not flags.is_empty():
						flagged = "%s to %s: %s" % [unit_id, tile, flags]
		kept_total += checked
		tiles_total += tiles
		var about: String = "board %d (%s)" % [board_seed, _board_text(world)]
		_check.call("equality: %s, %d tiles, every preview equals a full re-plan" % [
			about, tiles,
		], tiles > 0 and mismatch.is_empty(), mismatch)
		_check.call("equality: %s, checking mode finds none of %d kept decisions and reused" % [
			about, checked,
		] + " forecasts changed", flagged.is_empty(), flagged)
	Intents.is_checking = false
	_check.call("equality: previews kept decisions and checking mode checked them", (
			kept_total > 0
	), "%d tiles, %d kept decisions and reused forecasts checked" % [tiles_total, kept_total])
	_check.call("equality: the previews and re-plans reused attack forecasts", (
			reused_total > 0
	), "%d reused, %d made" % [reused_total, made_total])


# A far move keeps the Brute's decision to strike p1; p1 then drops to 1 HP with no fact, so the
# latest intents still look current. Checking mode reports the kept decision a re-plan changes.
func _test_checking_reports_stale() -> void:
	var world: AiWorld = _far_move_world()
	world.wound("p1", 1)
	Intents.is_checking = true
	var preview: Intents = Intents.preview(world.session, "p_far", Vector2i(10, 6))
	Intents.is_checking = false
	var flags: String = "" if preview == null else _check_lines(preview)
	_check.call("checking: a kept decision made stale behind the intents' back is reported", (
			preview != null and preview.checked > 0 and flags.contains("e1")
	), "checked %d; %s" % [-1 if preview == null else preview.checked, flags])


# The same previews with checking mode off and on give the same intents; off, nothing is checked.
func _test_checking_changes_nothing() -> void:
	var world: AiWorld = _far_move_world()
	var off: Intents = Intents.preview(world.session, "p_far", Vector2i(10, 6))
	Intents.is_checking = true
	var on: Intents = Intents.preview(world.session, "p_far", Vector2i(10, 6))
	Intents.is_checking = false
	_check.call("checking: off by default and changes no result", (
			off != null
			and on != null
			and off.checked == 0
			and on.checked > 0
			and _check_lines(on).is_empty()
			and _intents_text(off) == _intents_text(on)
			and off.decisions == on.decisions
	), "off %s / on %s" % [_intents_text(off), _intents_text(on)])


# Two enemies with p1 and p2 in their options and p_far out of every enemy's: a move of p_far keeps
# every decision (intent_cases.gd's far move, on the real catalog).
func _far_move_world() -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_12X8)
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.add_enemy("e1", BRUTE, Vector2i(1, 1))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(1, 5))
	_add_player(world, "p1", "fighter", Vector2i(3, 1))
	_add_player(world, "p2", "archer", Vector2i(4, 5))
	_add_player(world, "p_far", "fighter", Vector2i(11, 7))
	world.session.open_battle()
	return world


# A seeded random board in an open player phase: terrain, enemies on the right, player units on
# the left, some wounded, sometimes flooded tiles or the darkness arrived, then up to MAX_TURNS
# enemy phases played with every player unit waiting.
func _board(board_seed: int) -> AiWorld:
	var stream: RngStream = RngStream.new(board_seed)
	var width: int = stream.randi_range(MIN_WIDTH, MAX_WIDTH)
	var height: int = stream.randi_range(MIN_HEIGHT, MAX_HEIGHT)
	var rows: Array[String] = []
	for _y: int in height:
		var row: PackedStringArray = []
		for _x: int in width:
			row.append(TERRAIN[stream.pick_index(TERRAIN.size())])
		rows.append(" ".join(row))
	var world: AiWorld = AiWorld.new(_catalog, rows)
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	var third: int = maxi(floori(width / 3.0), 1)
	for index: int in stream.randi_range(MIN_ENEMIES, MAX_ENEMIES):
		var tile: Vector2i = _free_tile(world, stream, width - third, width - 1, height)
		if tile != CombatFact.NO_TILE:
			var class_id: String = _enemy_classes[stream.pick_index(_enemy_classes.size())]
			world.add_enemy("e%d" % [index + 1], class_id, tile)
	for index: int in stream.randi_range(MIN_PLAYERS, MAX_PLAYERS):
		var tile: Vector2i = _free_tile(world, stream, 0, third - 1, height)
		if tile != CombatFact.NO_TILE:
			var type_id: String = PLAYER_TYPES[stream.pick_index(PLAYER_TYPES.size())]
			_add_player(world, "p%d" % [index + 1], type_id, tile)
	for unit_id: String in world.state().unit_ids():
		if stream.roll_percent(WOUND_PERCENT):
			world.wound(unit_id, stream.randi_range(1, world.state().get_hp(unit_id)))
	if stream.roll_percent(FLOOD_PERCENT):
		for _tile: int in stream.randi_range(1, MAX_FLOODED):
			var flooded: Vector2i = Vector2i(stream.pick_index(width), stream.pick_index(height))
			world.state().map.darkness.layers[flooded] = WhileLayerCondition.Layer.DUSK
	world.state().map.has_darkness_arrived = stream.roll_percent(ARRIVED_PERCENT)
	world.session.open_battle()
	for _turn: int in stream.randi_range(0, MAX_TURNS):
		if world.session.is_finished:
			break
		world.session.submit(EndTurnCommand.new(0))
		world.session.resolve_next()
	return world


# A tile in columns from_x..to_x a default walker may stand on with nobody on it; NO_TILE when
# PLACE_TRIES draws find none.
func _free_tile(
		world: AiWorld, stream: RngStream, from_x: int, to_x: int, height: int
) -> Vector2i:
	for _try: int in PLACE_TRIES:
		var tile: Vector2i = Vector2i(stream.randi_range(from_x, to_x), stream.pick_index(height))
		var state: CombatState = world.state()
		if state.can_stand(tile, CombatGrid.MovementType.DEFAULT) and state.occupant_at(
				tile
		).is_empty():
			return tile
	return CombatFact.NO_TILE


# Loads a real player unit of type_id for seat 0, holding its type's starting weapon, onto tile.
func _add_player(world: AiWorld, unit_id: String, type_id: String, tile: Vector2i) -> void:
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	var items: Dictionary[String, ItemInstance] = {}
	var definition: UnitTypeDefinition = unit.definition(_catalog)
	if definition != null and not definition.starting_weapon_id.is_empty():
		var item_id: String = "item:%s" % [unit_id]
		unit.weapon_id = item_id
		items[item_id] = ItemInstance.new(item_id, definition.starting_weapon_id)
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			_catalog, unit, items, PLAYER, 0, world.session.ids
	)
	world.problems.append_array(loaded.problems)
	for weapon: CombatState.WeaponStats in loaded.weapons:
		world.state().add_weapon(weapon)
	for instance: EffectInstance in loaded.effects:
		world.engine().register(instance)
	loaded.state.tile = tile
	world.session.add_unit(loaded.state, loaded.bases)


# The intents Intents.compute gives on a copy of session with unit_id walked along path (its own
# tile when empty): a full re-plan, keeping nothing from the latest intents.
func _full_replan(session: CombatSession, unit_id: String, path: Array[Vector2i]) -> Intents:
	var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
	var engine: EffectEngine = sandbox.engine
	# Verify mode checks stat caches, not the intents, and changes no result; off for speed.
	engine.verify = false
	var moved: CombatState = engine.state
	if not path.is_empty():
		engine.begin_step()
		UnitTurnCommand.walk_path(engine, moved, unit_id, path)
		engine.drain()
	return Intents.compute(_moved_copy(session, engine), _catalog)


# A session over engine, a sandbox of session's, sharing its hooks, map and setup, as
# PhaseRunner's stand-in does, so Intents.compute reads the moved board through every
# registration session has.
func _moved_copy(session: CombatSession, engine: EffectEngine) -> CombatSession:
	var grid: MapGrid = MapGrid.new(session.layout)
	var copy: CombatSession = CombatSession.new(
			session.session_id, session.seats, grid, engine.rolls, session.ids
	)
	var moved: CombatState = engine.state
	copy.state = moved
	copy.engine = engine
	copy.hooks = session.hooks
	copy.setup = session.setup
	copy.seat_setup = session.seat_setup
	copy.commander_ids = session.commander_ids.duplicate()
	copy.run_seed = session.run_seed
	return copy


# Every intent as one line each (enemy, order, kind, target, tile, path, weapon, area, kills,
# signature and its plan's forecast), then the danger zone's tiles; "null" for none.
func _intents_text(shown: Intents) -> String:
	if shown == null:
		return "null"
	var lines: PackedStringArray = []
	for intent: EnemyIntent in shown.enemies:
		lines.append("%d %s %s %s %s %s %s %s %s %s %s {%s}" % [
			intent.order, intent.unit_id, EnemyIntent.Kind.find_key(intent.kind),
			intent.target_id, intent.tile, intent.path, intent.weapon_id, intent.area,
			intent.defeats, intent.allies_defeated, intent.signature_name,
			_forecast_text(intent.plan.forecast if intent.plan != null else null),
		])
	var danger: Array[Vector2i] = []
	if shown.danger != null:
		danger.assign(shown.danger.combined.keys())
		danger.sort_custom(EnemyPlan.tile_precedes)
	lines.append("danger %s" % [danger])
	return " | ".join(lines)


# A forecast's legality, every unit's outcome and, for an exchange, each attack; "" for none.
func _forecast_text(forecast: CombatForecast.Forecast) -> String:
	if forecast == null:
		return ""
	var parts: PackedStringArray = [str(forecast.is_legal), forecast.actor_id, forecast.target_id]
	for outcome: CombatForecast.UnitOutcome in forecast.units:
		parts.append("%s %d>%d b%d>%d s%d>%d %s>%s %s" % [
			outcome.unit_id, outcome.hp_before, outcome.hp_after, outcome.block_before,
			outcome.block_after, outcome.stance_before, outcome.stance_after, outcome.tile_before,
			outcome.tile_after, outcome.is_defeated,
		])
	var exchange: CombatForecast.ExchangeForecast = forecast as CombatForecast.ExchangeForecast
	if exchange != null:
		for attack: CombatForecast.AttackForecast in exchange.attacks:
			parts.append("%s>%s %d %s %d" % [
				attack.attacker_id, attack.defender_id, attack.hit, attack.is_hit,
				attack.crit_chance,
			])
	return " ".join(parts)


# The checking-mode lines in shown's diagnostics, joined; "" for none.
func _check_lines(shown: Intents) -> String:
	var lines: PackedStringArray = []
	for line: String in shown.diagnostics:
		if line.begins_with(Intents.CHECK_PREFIX):
			lines.append(line)
	return "; ".join(lines)


# The board's size and units, by class, for the case name.
func _board_text(world: AiWorld) -> String:
	var state: CombatState = world.state()
	var units: PackedStringArray = []
	for unit_id: String in state.unit_ids():
		units.append(state.unit_type_of(unit_id))
	return "turn %d, %s" % [state.turn, ", ".join(units)]
