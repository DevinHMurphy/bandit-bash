# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cleave_cases.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

extends RefCounted
## Cleave's cases for tests/enemies/roster/run_all.gd, on the real catalog's Brute, Brigand
## Captain and Powder Baron: each hit splashes 2 on every other adjacent unit, friend or foe, never
## the unit it struck, and no one with nothing else adjacent; the preview of the same attack (the
## enemy's, and a player's struck by the counter) shows the same splash and HP as the attack
## itself; the intent's forecast, kill and area agree; each class's text says "every other".
## Reports each case through the check callable it is given.
##
## Boards are Plain, walled so the enemy has no other tile to strike from, and every hit lands
## ([ForecastRolls]). Player units have 20 HP and a sword.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const ENEMY_SEAT: int = -1
const PLAYER_SEAT: int = 0
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

# The classes with Cleave as their trait (enemy-roster.md).
const CLEAVERS: Array[String] = ["brute", "brigand_captain", "powder_baron"]

# Cleave's splash per hit (enemy-roster.md, the Brute).
const SPLASH_PER_HIT: int = 2

# Cleave's line as each class's text reads it.
const CLEAVE_TEXT: String = (
		"Whenever this unit lands a hit, deal 2 splash damage to every other adjacent unit, friend"
		+ " or foe."
)

# One row: a unit at (0, 0), the enemy at (1, 0), its target at (2, 0).
const ROW: Array[String] = ["plain plain plain"]

# The row, and one tile below the enemy between walls.
const ROW_AND_BELOW: Array[String] = ["plain plain plain", "wall plain wall"]

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	for class_id: String in CLEAVERS:
		_test_text(class_id)
		_test_spares_the_target(class_id)
		_test_nothing_else_adjacent(class_id)
		_test_friend_or_foe(class_id)
		_test_no_false_kill(class_id)
		_test_counter_spares_the_attacker(class_id)


# The class's text names every other adjacent unit.
func _test_text(class_id: String) -> void:
	var enemy_class: EnemyClassDefinition = _catalog.enemy_class(class_id)
	var lines: PackedStringArray = []
	if enemy_class != null:
		lines = enemy_class.describe()
	_check.call("cleave %s: the text says every other adjacent unit" % [class_id], (
			lines.has(CLEAVE_TEXT)
	), " | ".join(lines))


# p2 at (0, 0), the enemy at (1, 0), p1 at (2, 0). The intent, on whichever it strikes, spares
# that one and splashes the other; its attack on p1 splashes p2 only, 2 per hit, in the preview as
# in the attack.
func _test_spares_the_target(class_id: String) -> void:
	var label: String = "cleave %s: beside the target" % [class_id]
	var world: AiWorld = _world(ROW, class_id)
	world.add_player("p2", Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 0))
	_check_intent(world, label, [Vector2i(0, 0), Vector2i(2, 0)])
	_check_attack(world, label, "p1", {"p2": true})


# The enemy at (1, 0), p1 at (2, 0), nothing else: no splash at all, shown or done; the intent's
# area is the empty tile.
func _test_nothing_else_adjacent(class_id: String) -> void:
	var label: String = "cleave %s: alone with the target" % [class_id]
	var world: AiWorld = _world(ROW, class_id)
	world.add_player("p1", Vector2i(2, 0))
	_check_intent(world, label, [Vector2i(0, 0), Vector2i(2, 0)])
	_check_attack(world, label, "p1", {})


# A Hedge Healer (the enemy's ally, which deals no damage before it) at (0, 0), the enemy at
# (1, 0), p1 at (2, 0) and p2 at (1, 1): its attack on p1 splashes its ally and p2, friend or foe,
# and spares p1.
func _test_friend_or_foe(class_id: String) -> void:
	var label: String = "cleave %s: ally and foe beside" % [class_id]
	var world: AiWorld = _world(ROW_AND_BELOW, class_id)
	world.add_enemy("e2", "hedge_healer", Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 0))
	world.add_player("p2", Vector2i(1, 1))
	_check_intent(world, label, [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1)])
	_check_attack(world, label, "p1", {"e2": true, "p2": true})


# p1 alone beside the enemy with 1 HP more than its hits deal: the AI counts no kill on it, as the
# splash no longer reaches it; with exactly that HP, it does.
func _test_no_false_kill(class_id: String) -> void:
	var label: String = "cleave %s: kill estimate" % [class_id]
	var world: AiWorld = _world(ROW, class_id)
	world.add_player("p1", Vector2i(2, 0))
	var preview: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			world.engine(), UnitTurnCommand.new(ENEMY_SEAT, "e1", ATTACK, "p1")
	)
	var hit_damage: int = _hp_lost_to_attacks(preview.facts, "p1")
	if hit_damage <= 0 or hit_damage + 1 > world.state().get_hp("p1"):
		_check.call("%s: its hits deal some damage short of 20" % [label], false, str(hit_damage))
		return
	world.wound("p1", hit_damage + 1)
	var spared: EnemyIntent = Intents.compute(world.session, _catalog).intent_of("e1")
	_check.call("%s: 1 HP past the hits is no kill" % [label], (
			spared != null
			and spared.target_id == "p1"
			and not spared.is_kill
			and spared.defeats.is_empty()
			and spared.plan.kill_chance == 0.0
	), "" if spared == null else spared.describe())
	world.wound("p1", hit_damage)
	var killed: EnemyIntent = Intents.compute(world.session, _catalog).intent_of("e1")
	_check.call("%s: exactly the hits is a kill" % [label], (
			killed != null and killed.is_kill and killed.defeats == PackedStringArray(["p1"])
	), "" if killed == null else killed.describe())


# p2 at (0, 0), the enemy at (1, 0), and p1 at (2, 0) attacks it: the enemy's counter splashes p2
# and spares p1, the unit it struck, in the player's preview as in the attack.
func _test_counter_spares_the_attacker(class_id: String) -> void:
	var world: AiWorld = _world(ROW, class_id)
	world.add_player("p2", Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 0))
	var label: String = "cleave %s: countering a player" % [class_id]
	var command: UnitTurnCommand = UnitTurnCommand.new(PLAYER_SEAT, "p1", ATTACK, "e1")
	_check_preview_and_attack(world, label, command, {"p2": true})


# The enemy's attack on target on world: its preview and the attack itself each splash exactly the
# units in splashed, 2 per enemy hit, and end on the same HP.
func _check_attack(
		world: AiWorld, label: String, target: String, splashed: Dictionary[String, bool]
) -> void:
	var command: UnitTurnCommand = UnitTurnCommand.new(ENEMY_SEAT, "e1", ATTACK, target)
	_check_preview_and_attack(world, label, command, splashed)


# Previews command on world, then resolves it: both splash exactly the units in splashed, 2 per
# hit e1 lands, and the preview's HP are the attack's.
func _check_preview_and_attack(
		world: AiWorld,
		label: String,
		command: UnitTurnCommand,
		splashed: Dictionary[String, bool],
) -> void:
	var preview: CombatForecast.ExchangeForecast = CombatForecast.exchange(world.engine(), command)
	var done: Array[CombatFact] = _resolve(world, command)
	var hits: int = _hits(done, "e1")
	var expected: String = _splash_text(splashed, hits)
	_check.call("%s: e1 lands a hit" % [label], hits > 0, str(hits))
	_check.call("%s: the attack spares the unit struck" % [label], (
			_splash_text_of(done) == expected
	), "%s / expected %s" % [_splash_text_of(done), expected])
	_check.call("%s: the preview shows the same splash" % [label], (
			_splash_text_of(preview.facts) == expected
	), "%s / expected %s" % [_splash_text_of(preview.facts), expected])
	_check.call("%s: the preview's HP are the attack's" % [label], (
			_outcome_text(preview) == _hp_text(world, preview)
	), "%s / %s" % [_outcome_text(preview), _hp_text(world, preview)])


# The intent of e1 on world: an attack whose forecast splashes every unit beside its tile but the
# one it strikes, 2 per hit, and whose area is around less the struck unit's tile. The struck unit
# must survive the forecast, or the splash would miss it whatever the rule.
func _check_intent(world: AiWorld, label: String, around: Array[Vector2i]) -> void:
	var intent: EnemyIntent = Intents.compute(world.session, _catalog).intent_of("e1")
	if intent == null or intent.plan == null or intent.plan.forecast == null:
		_check.call("%s: the intent attacks" % [label], false, "no intent")
		return
	var state: CombatState = world.state()
	var struck: String = intent.target_id
	_check.call("%s: the intent's target survives its hits" % [label], (
			not intent.defeats.has(struck)
	), intent.describe())
	var beside: Dictionary[String, bool] = {}
	for unit_id: String in state.unit_ids():
		var tile: Vector2i = state.tile_of(unit_id)
		if unit_id != "e1" and unit_id != struck and state.grid.distance(tile, intent.tile) == 1:
			beside[unit_id] = true
	var facts: Array[CombatFact] = intent.plan.forecast.facts
	var expected: String = _splash_text(beside, _hits(facts, "e1"))
	var area: Array[Vector2i] = []
	for tile: Vector2i in around:
		if tile != state.tile_of(struck):
			area.append(tile)
	area.sort_custom(EnemyPlan.tile_precedes)
	_check.call("%s: the intent's forecast spares %s" % [label, struck], (
			intent.kind == EnemyIntent.Kind.ATTACK
			and intent.tile == Vector2i(1, 0)
			and _splash_text_of(facts) == expected
	), "%s / expected %s; %s" % [_splash_text_of(facts), expected, intent.describe()])
	_check.call("%s: the intent's area leaves out %s" % [label, struck], (
			intent.area == area
	), "%s / expected %s" % [intent.area, area])


# A board of rows with the class's enemy e1 at (1, 0), every hit landing.
func _world(rows: Array[String], class_id: String) -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, rows, ForecastRolls.new())
	world.add_enemy("e1", class_id, Vector2i(1, 0))
	_check.call("cleave %s: loads" % [class_id], world.problems.is_empty(), str(world.problems))
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


# How many hits attacker landed in facts.
func _hits(facts: Array[CombatFact], attacker: String) -> int:
	var count: int = 0
	for fact: CombatFact in facts:
		if fact.kind == CombatFact.Kind.HIT_DEALT and fact.actor_id == attacker:
			count += 1
	return count


# The HP unit_id lost to attacks in facts, splash left out.
func _hp_lost_to_attacks(facts: Array[CombatFact], unit_id: String) -> int:
	var lost: int = 0
	for fact: CombatFact in facts:
		var is_attack: bool = (
				fact.kind == CombatFact.Kind.DAMAGE_TAKEN
				and fact.source == CombatFact.Source.ATTACK
				and fact.actor_id == unit_id
		)
		if is_attack:
			lost += fact.hp_amount
	return lost


# "id amount" for each unit in splashed taking SPLASH_PER_HIT per hit, sorted by id; empty for none.
func _splash_text(splashed: Dictionary[String, bool], hits: int) -> String:
	var ids: Array[String] = []
	ids.assign(splashed.keys())
	ids.sort()
	var parts: PackedStringArray = []
	for unit_id: String in ids:
		parts.append("%s %d" % [unit_id, SPLASH_PER_HIT * hits])
	return ", ".join(parts)


# "id amount" for each unit facts deal splash to, its total, sorted by id; empty for none.
func _splash_text_of(facts: Array[CombatFact]) -> String:
	var totals: Dictionary[String, int] = {}
	for fact: CombatFact in facts:
		if fact.kind == CombatFact.Kind.DAMAGE_TAKEN and fact.source == CombatFact.Source.SPLASH:
			var prior: int = totals.get(fact.actor_id, 0)
			totals[fact.actor_id] = prior + fact.amount
	var ids: Array[String] = []
	ids.assign(totals.keys())
	ids.sort()
	var parts: PackedStringArray = []
	for unit_id: String in ids:
		parts.append("%s %d" % [unit_id, totals[unit_id]])
	return ", ".join(parts)


# "id hp" after the preview, for each unit it changes.
func _outcome_text(preview: CombatForecast.ExchangeForecast) -> String:
	var parts: PackedStringArray = []
	for outcome: CombatForecast.UnitOutcome in preview.units:
		parts.append("%s %d" % [outcome.unit_id, outcome.hp_after])
	return ", ".join(parts)


# "id hp" on world now, for each unit preview names.
func _hp_text(world: AiWorld, preview: CombatForecast.ExchangeForecast) -> String:
	var parts: PackedStringArray = []
	for outcome: CombatForecast.UnitOutcome in preview.units:
		parts.append("%s %d" % [outcome.unit_id, world.state().get_hp(outcome.unit_id)])
	return ", ".join(parts)
