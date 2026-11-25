# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     attacker_area_cases.gd
# Author:
# Created:  November 25, 2026
# Modified: November 25, 2026
# ==============================================================================

extends RefCounted
## The cases for an attacker beside its own target-centered area, for
## tests/enemies/roster/run_all.gd, on the real catalog's Raider (Trample), Hexer and Hex Matron
## (Curse): striking from range 1 or range 2, with an ally and a foe beside the target, the area
## catches both and never the attacker, in the preview as in the attack; the intent's forecast and
## area leave the attacker out; each class's text says "except this unit". Reports each case
## through the check callable it is given.
##
## Boards are Plain and every hit lands ([ForecastRolls]). The target p1 stands at (5, 0), the
## attacker's ally (a Hedge Healer) at (6, 0) and p2 at (5, 1).
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const ENEMY_SEAT: int = -1
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

const BOARD: Array[String] = [
	"plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain",
]

# The Raider's intent board: one row to ride along, (3, 0) held by its Hound so it can't stop at
# range 2, and below the target the only open tile, for its ally.
const RIDE_BOARD: Array[String] = [
	"plain plain plain plain plain plain",
	"wall wall wall wall wall plain",
]

# The Hexer's intent board: it, p1 and its ally fill the row, so it strikes from where it stands.
const STUCK_BOARD: Array[String] = ["plain plain plain"]

const TARGET_TILE: Vector2i = Vector2i(5, 0)
const ALLY_TILE: Vector2i = Vector2i(6, 0)
const FOE_TILE: Vector2i = Vector2i(5, 1)

# Where the attacker starts. The Raider walks from here, as Trample needs 3+ tiles moved.
const START_TILE: Vector2i = Vector2i(0, 0)

# Who the area catches in every case: the ally and the foe beside the target, never the attacker.
const CAUGHT: String = "e2, p2"

# Each class's text line for its area effect, as enemy-roster.md and the effect text style read.
const TEXT: Dictionary[String, String] = {
	"raider": (
		"Whenever this unit lands a hit, while this unit moved 3+ tiles this turn, deal 3 splash"
		+ " damage to adjacent units of the other unit, friend or foe, except this unit."
	),
	"hexer": (
		"Whenever this unit lands a hit, remove 1 Stance from the other unit and adjacent units of"
		+ " the other unit, friend or foe, except this unit."
	),
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	for class_id: String in TEXT:
		_test_text(class_id)
	for range_tiles: int in [1, 2]:
		_test_trample(range_tiles)
		for class_id: String in ["hexer", "hex_matron"]:
			_test_curse(class_id, range_tiles)
	_test_intent("raider")
	_test_intent("hexer")
	_test_intent("hex_matron")


func _test_text(class_id: String) -> void:
	var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
	var lines: PackedStringArray = []
	if enemy_class != null:
		lines = enemy_class.describe()
	_check.call("own area %s: the text spares this unit" % [class_id], (
			lines.has(TEXT[class_id])
	), " | ".join(lines))


# The Raider walks from START_TILE along row 0 to strike p1 from range_tiles away (3 or 4 tiles
# moved, so Trample is on): the splash catches the ally and p2, never the Raider.
func _test_trample(range_tiles: int) -> void:
	var world: AiWorld = _world("raider", START_TILE)
	var end: Vector2i = TARGET_TILE - Vector2i(range_tiles, 0)
	var path: Array[Vector2i] = []
	for x: int in range(START_TILE.x, end.x + 1):
		path.append(Vector2i(x, 0))
	var command: UnitTurnCommand = UnitTurnCommand.new(ENEMY_SEAT, "e1", ATTACK, "p1", path)
	_check_preview_and_attack(world, "own area raider at range %d" % [range_tiles], command)


# The Hexer or Hex Matron strikes p1 from range_tiles away without moving: the Curse catches the
# ally and p2 (and p1, its center), never the attacker. p1 holds a bow, so at range 1 no counter
# takes the attacker's Stance before the Curse resolves.
func _test_curse(class_id: String, range_tiles: int) -> void:
	var world: AiWorld = _world(class_id, TARGET_TILE - Vector2i(range_tiles, 0), "bow")
	var command: UnitTurnCommand = UnitTurnCommand.new(ENEMY_SEAT, "e1", ATTACK, "p1")
	_check_preview_and_attack(
			world, "own area %s at range %d" % [class_id, range_tiles], command, "e2, p1, p2"
	)


# The class's intent on a board where its one way to strike p1 is from beside it, its ally e2 on
# p1's other side: its forecast's area catches e2, never the attacker, and its area leaves out the
# tile it acts from. The Raider rides 4 tiles past its Hound ally e3 to the only tile in reach
# (Trample on); the Hexer and Hex Matron can't move, and p1's bow never counters.
func _test_intent(class_id: String) -> void:
	var label: String = "own area %s: the intent" % [class_id]
	var world: AiWorld = null
	if class_id == "raider":
		world = AiWorld.new(_catalog, RIDE_BOARD, ForecastRolls.new())
		world.add_enemy("e1", class_id, Vector2i(0, 0))
		world.add_enemy("e3", "hound", Vector2i(3, 0))
		world.add_player("p1", Vector2i(5, 0))
		world.add_enemy("e2", "hedge_healer", Vector2i(5, 1))
	else:
		world = AiWorld.new(_catalog, STUCK_BOARD, ForecastRolls.new())
		world.add_enemy("e1", class_id, Vector2i(0, 0))
		world.add_player("p1", Vector2i(1, 0), "bow")
		world.add_enemy("e2", "hedge_healer", Vector2i(2, 0))
	_check.call("%s: loads" % [label], world.problems.is_empty(), str(world.problems))
	var intent: EnemyIntent = Intents.compute(world.session, _catalog).intent_of("e1")
	if intent == null or intent.plan == null or intent.plan.forecast == null:
		_check.call("%s attacks" % [label], false, "no intent")
		return
	var target_tile: Vector2i = world.state().tile_of("p1")
	_check.call("%s: strikes p1 from beside it" % [label], (
			intent.kind == EnemyIntent.Kind.ATTACK
			and intent.target_id == "p1"
			and world.state().grid.distance(intent.tile, target_tile) == 1
	), intent.describe())
	var caught: String = _caught_text(intent.plan.forecast.facts)
	var expected: String = "e2" if class_id == "raider" else "e2, p1"
	_check.call("%s: its forecast catches the area but not e1" % [label], (
			caught == expected
	), "%s / expected %s; %s" % [caught, expected, intent.describe()])
	_check.call("%s: its area leaves out its own tile" % [label], (
			not intent.area.is_empty() and not intent.area.has(intent.tile)
	), "%s from %s" % [intent.area, intent.tile])


# Previews command on world, then resolves it: both catch exactly expected in the area's splash or
# Stance loss, and the preview's HP and Stance are the attack's.
func _check_preview_and_attack(
		world: AiWorld, label: String, command: UnitTurnCommand, expected: String = CAUGHT
) -> void:
	var preview: CombatForecast.ExchangeForecast = CombatForecast.exchange(world.engine(), command)
	var done: Array[CombatFact] = _resolve(world, command)
	_check.call("%s: e1 lands a hit" % [label], _hits(done, "e1") > 0, preview.reason)
	_check.call("%s: the attack spares the attacker" % [label], (
			_caught_text(done) == expected
	), "%s / expected %s" % [_caught_text(done), expected])
	_check.call("%s: the preview shows the same" % [label], (
			_caught_text(preview.facts) == expected
	), "%s / expected %s" % [_caught_text(preview.facts), expected])
	_check.call("%s: the preview's HP and Stance are the attack's" % [label], (
			_outcome_text(preview) == _state_text(world, preview)
	), "%s / %s" % [_outcome_text(preview), _state_text(world, preview)])


# A board with the class's enemy e1 on tile, p1 holding p1_weapon as its target, its ally e2 and
# p2 beside p1.
func _world(class_id: String, tile: Vector2i, p1_weapon: String = "sword") -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, BOARD, ForecastRolls.new())
	world.add_enemy("e1", class_id, tile)
	world.add_enemy("e2", "hedge_healer", ALLY_TILE)
	world.add_player("p1", TARGET_TILE, p1_weapon)
	world.add_player("p2", FOE_TILE)
	_check.call("own area %s: loads" % [class_id], world.problems.is_empty(), str(world.problems))
	return world


# Resolves command on world's session as a turn does (one step, drained); returns its facts.
func _resolve(world: AiWorld, command: UnitTurnCommand) -> Array[CombatFact]:
	var engine: EffectEngine = world.engine()
	var from: int = engine.fact_log.size()
	engine.begin_step()
	command.resolve(world.session)
	engine.drain()
	var done: Array[CombatFact] = []
	for index: int in range(from, engine.fact_log.size()):
		done.append(engine.fact_log[index])
	return done


func _hits(facts: Array[CombatFact], attacker: String) -> int:
	var count: int = 0
	for fact: CombatFact in facts:
		if fact.kind == CombatFact.Kind.HIT_DEALT and fact.actor_id == attacker:
			count += 1
	return count


# The units facts show caught by an area: splash taken, or Stance an effect removed; sorted ids.
func _caught_text(facts: Array[CombatFact]) -> String:
	var caught: Dictionary[String, bool] = {}
	for fact: CombatFact in facts:
		var is_splash: bool = (
				fact.kind == CombatFact.Kind.DAMAGE_TAKEN
				and fact.source == CombatFact.Source.SPLASH
		)
		var is_curse: bool = (
				fact.kind == CombatFact.Kind.STANCE_CHANGED
				and fact.source == CombatFact.Source.EFFECT
				and fact.amount < 0
		)
		if is_splash or is_curse:
			caught[fact.actor_id] = true
	var ids: Array[String] = []
	ids.assign(caught.keys())
	ids.sort()
	return ", ".join(ids)


# "id hp/stance" after the preview, for each unit it changes.
func _outcome_text(preview: CombatForecast.ExchangeForecast) -> String:
	var parts: PackedStringArray = []
	for outcome: CombatForecast.UnitOutcome in preview.units:
		parts.append("%s %d/%d" % [outcome.unit_id, outcome.hp_after, outcome.stance_after])
	return ", ".join(parts)


# "id hp/stance" on world now, for each unit preview names.
func _state_text(world: AiWorld, preview: CombatForecast.ExchangeForecast) -> String:
	var parts: PackedStringArray = []
	var state: CombatState = world.state()
	for outcome: CombatForecast.UnitOutcome in preview.units:
		parts.append("%s %d/%d" % [
			outcome.unit_id, state.get_hp(outcome.unit_id), state.get_stance(outcome.unit_id),
		])
	return ", ".join(parts)
