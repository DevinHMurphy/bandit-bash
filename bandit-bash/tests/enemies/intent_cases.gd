# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_cases.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

extends RefCounted
## The intents and danger zone cases for tests/enemies/run_all.gd ([Intents], [EnemyIntent],
## [DangerZone]): the first enemy to act carries out its shown intent when nothing changed (and,
## with every hit landing, the whole phase does), a chained intent shows the follow-up a kill
## opens, a splash kill names the unit that falls, a preview equals the intents after the unit
## really moves there (a far move reusing every decision, a move that hands a later enemy a kill
## moving it up the order), intents refresh after a player command and only then, the danger zone
## matches reach plus range for each M1 behavior, and the same board gives the same intents.
## Reports each case through the check callable it is given.

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const BRUTE: String = "loadout_brute"
const CROSSBOWMAN: String = "loadout_crossbowman"
const HEALER: String = "loadout_hedge_healer"

const PLAIN_8X8: Array[String] = [
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
]

# Twelve tiles across, so the 8 × 8 boards' far corner is out of every enemy's options.
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

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param catalog]: the loadout fixture tree.
func _init(check: Callable, catalog: EffectCatalog.Index) -> void:
	_check = check
	_catalog = catalog


## Runs every case.
func run() -> void:
	_test_register()
	_test_first_enemy_keeps_its_intent()
	_test_whole_phase_as_shown()
	_test_chained_follow_up()
	_test_splash_kill_named()
	_test_preview_matches_real_move()
	_test_preview_reuses_far_from_enemies()
	_test_preview_moves_kill_up()
	_test_refresh_after_command()
	_test_danger_zone_per_behavior()
	_test_danger_zone_blocked()
	_test_same_board_same_intents()


func _test_register() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	Intents.register(world.session, _catalog)
	var hooks: CombatHooks = world.session.hooks
	_check.call("intents: registered on INTENTS and AFTER_STEP", (
			hooks.has_registered(CombatHooks.Hook.INTENTS)
			and hooks.has_registered(CombatHooks.Hook.AFTER_STEP)
	))


# A seeded battle: the player units wait, then the first enemy to act in the real phase acts as
# its intent showed, whatever its rolls do to the rest.
func _test_first_enemy_keeps_its_intent() -> void:
	var world: AiWorld = _battle(null)
	for unit_id: String in world.state().units_of(AiWorld.PLAYER):
		_send(world, UnitTurnCommand.new(0, unit_id))
	var shown: Intents = world.session.intents
	_send(world, EndTurnCommand.new(0))
	var played: PackedStringArray = _enemy_turns(world)
	var expected: String = "" if shown == null or shown.enemies.is_empty() else _turn_of(
			shown.enemies[0]
	)
	_check.call("intents: the first enemy carries out its shown intent", (
			not played.is_empty() and played[0] == expected
	), "shown %s, played %s" % [expected, played])


# With every hit landing in the real phase too, every enemy plays as the chain showed.
func _test_whole_phase_as_shown() -> void:
	var world: AiWorld = _battle(ForecastRolls.new())
	var shown: Intents = world.session.intents
	var expected: PackedStringArray = []
	if shown != null:
		for intent: EnemyIntent in shown.enemies:
			expected.append(_turn_of(intent))
	_send(world, EndTurnCommand.new(0))
	var played: PackedStringArray = _enemy_turns(world)
	_check.call("intents: with every hit landing, the phase plays as shown", (
			expected.size() == 3 and played == expected
	), "shown %s, played %s" % [expected, played])


# One corridor: the Crossbowman at the end can't reach p_back past p_front, which the Brute
# beside it can defeat. The chain shows the Brute's kill first, then the shot it opens.
func _test_chained_follow_up() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain plain plain",
	])
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_front", Vector2i(1, 0))
	world.add_enemy("e1", BRUTE, Vector2i(2, 0))
	world.add_player("p_back", Vector2i(6, 0))
	world.wound("p_front", 1)
	var alone: EnemyPlan = world.decide("e2")
	var shown: Intents = Intents.compute(world.session, _catalog)
	var first: EnemyIntent = shown.intent_of("e1")
	var second: EnemyIntent = shown.intent_of("e2")
	_check.call("chain: on today's board the Crossbowman has no shot", (
			alone.kind != EnemyPlan.Kind.ATTACK
	), _plan_text(alone))
	_check.call("chain: the Brute's kill comes first", (
			first != null
			and first.order == 0
			and first.target_id == "p_front"
			and first.reason() == EnemyPlan.Step.KILL
			and first.defeats == PackedStringArray(["p_front"])
	), _intents_text(shown))
	_check.call("chain: then the Crossbowman shoots the unit the kill exposed", (
			second != null
			and second.order == 1
			and second.kind == EnemyIntent.Kind.ATTACK
			and second.target_id == "p_back"
			and second.tile.x < 6
			and second.path.size() > 1
	), _intents_text(shown))


# Cleave finishes p_b beside the tile the Brute strikes p_a from: the intent names p_b among the
# fallen and the splash area around that tile, though the step that chose it is the kill chance.
func _test_splash_kill_named() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
		"forest plain plain plain plain plain",
		"plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_cleave("e1")
	world.add_player("p_a", Vector2i(2, 2), "bow")
	world.add_player("p_b", Vector2i(0, 2), "bow")
	world.wound("p_b", 2)
	var shown: Intents = Intents.compute(world.session, _catalog)
	var intent: EnemyIntent = shown.intent_of("e1")
	var around: Array[Vector2i] = [Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2), Vector2i(1, 3)]
	_check.call("splash: the intent strikes p_a and names p_b as falling", (
			intent != null
			and intent.target_id == "p_a"
			and intent.tile == Vector2i(1, 2)
			and intent.defeats.has("p_b")
			and intent.is_kill
			and intent.reason() == EnemyPlan.Step.KILL
			and intent.decided_by == EnemyPlan.Step.KILL_CHANCE
	), _intents_text(shown))
	_check.call("splash: the area is the four tiles around the Brute", (
			intent != null and intent.area == around
	), "" if intent == null else str(intent.area))


# A preview of p2 stepping next to the Brute equals the intents once p2 really moves there and
# waits; so does the danger zone.
func _test_preview_matches_real_move() -> void:
	var world: AiWorld = _battle(null)
	var path: Array[Vector2i] = [Vector2i(2, 4), Vector2i(3, 4), Vector2i(3, 3)]
	var preview: Intents = Intents.preview(world.session, "p2", Vector2i(3, 3))
	_send(world, UnitTurnCommand.new(0, "p2", UnitTurnCommand.Action.WAIT, "", path))
	var real: Intents = world.session.intents
	_check.call("preview: equals the intents after the real move", (
			preview != null
			and real != null
			and _intents_text(preview) == _intents_text(real)
			and preview.moved_unit_id == "p2"
			and preview.moved_to == Vector2i(3, 3)
	), "preview %s / real %s" % [_intents_text(preview), _intents_text(real)])
	_check.call("preview: the danger zone too", (
			preview != null
			and real != null
			and preview.danger.combined.keys() == real.danger.combined.keys()
	))


# With no Support on the map, a move far from every enemy's options decides nothing again, and
# still equals the real move.
func _test_preview_reuses_far_from_enemies() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_12X8)
	world.add_enemy("e1", BRUTE, Vector2i(1, 1))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(1, 5))
	world.add_player("p1", Vector2i(3, 1))
	world.add_player("p2", Vector2i(4, 5), "bow")
	world.add_player("p_far", Vector2i(11, 7))
	_open(world)
	var base: Intents = world.session.intents
	var path: Array[Vector2i] = [Vector2i(11, 7), Vector2i(11, 6), Vector2i(10, 6)]
	var preview: Intents = Intents.preview(world.session, "p_far", Vector2i(10, 6))
	_send(world, UnitTurnCommand.new(0, "p_far", UnitTurnCommand.Action.WAIT, "", path))
	var real: Intents = world.session.intents
	_check.call("preview: a far move reuses every decision", (
			base != null and base.decisions > 0 and preview != null and preview.decisions == 0
	), "base %d, preview %d" % [
		0 if base == null else base.decisions, -1 if preview == null else preview.decisions,
	])
	_check.call("preview: and still equals the real move", (
			preview != null and real != null and _intents_text(preview) == _intents_text(real)
	), "preview %s / real %s" % [_intents_text(preview), _intents_text(real)])


# The Crossbowman would act first with its shot while the Brute, out of reach, advances; a 1-HP
# unit stepping within the Brute's reach (and out of the Crossbowman's) hands the Brute a kill,
# which moves it up the order, as the real move shows.
func _test_preview_moves_kill_up() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_12X8)
	world.add_enemy("e1", BRUTE, Vector2i(11, 7))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(1, 5))
	world.add_player("p1", Vector2i(4, 5), "bow")
	world.add_player("p_weak", Vector2i(10, 0), "bow")
	world.wound("p_weak", 1)
	_open(world)
	var base: Intents = world.session.intents
	var path: Array[Vector2i] = [Vector2i(10, 0), Vector2i(10, 1), Vector2i(10, 2)]
	var preview: Intents = Intents.preview(world.session, "p_weak", Vector2i(10, 2))
	_send(world, UnitTurnCommand.new(0, "p_weak", UnitTurnCommand.Action.WAIT, "", path))
	var real: Intents = world.session.intents
	var first: EnemyIntent = null if preview == null else preview.intent_of("e1")
	_check.call("preview: before the move the Brute is not first", (
			base != null and base.intent_of("e1") != null and base.intent_of("e1").order != 0
	), _intents_text(base))
	_check.call("preview: the handed kill moves the Brute first", (
			first != null and first.order == 0 and first.defeats.has("p_weak")
	), _intents_text(preview))
	_check.call("preview: and equals the real move", (
			preview != null and real != null and _intents_text(preview) == _intents_text(real)
	), "preview %s / real %s" % [_intents_text(preview), _intents_text(real)])


# A player command that records facts brings new intents and one intents_changed; a refresh with
# nothing new keeps them; the intents never record a fact on the map.
func _test_refresh_after_command() -> void:
	var world: AiWorld = _battle(null)
	var seen: Array[Intents] = []
	var on_changed: Callable = func(latest: Intents) -> void:
		seen.append(latest)
	world.session.intents_changed.connect(on_changed)
	var before: Intents = world.session.intents
	var path: Array[Vector2i] = [Vector2i(1, 2), Vector2i(1, 1)]
	_send(world, UnitTurnCommand.new(0, "p1", UnitTurnCommand.Action.WAIT, "", path))
	var after: Intents = world.session.intents
	_check.call("refresh: new intents after a player command", (
			before != null
			and after != null
			and after != before
			and after.based_on_seq == world.session.last_seq()
			and seen.size() == 1
			and seen[0] == after
	), "%d signals" % [seen.size()])
	var facts: int = world.engine().fact_log.size()
	Intents.refresh(world.session, _catalog)
	_check.call("refresh: nothing new keeps them and records nothing", (
			world.session.intents == after
			and seen.size() == 1
			and world.engine().fact_log.size() == facts
	))
	world.session.intents_changed.disconnect(on_changed)


# Each M1 behavior on an empty plain map: every tile within movement plus range of its own tile
# (plain costs 1), none for the healer, whose staff attacks nothing.
func _test_danger_zone_per_behavior() -> void:
	for row: Array in [[BRUTE, "Aggressive"], [CROSSBOWMAN, "Hold"], [HEALER, "Support"]]:
		var class_id: String = row[0]
		var world: AiWorld = AiWorld.new(_catalog, PLAIN_12X8)
		var origin: Vector2i = Vector2i(5, 4)
		world.add_enemy("e1", class_id, origin)
		var zone: DangerZone = DangerZone.compute(world.engine())
		var expected: Array[Vector2i] = []
		var held: CombatState.WeaponStats = world.state().equipped_weapon("e1")
		if not held.is_staff():
			var movement: int = world.engine().stats("e1").get_int(CombatValue.Key.MOVEMENT)
			var sheet: StatSheet = world.engine().stats("e1")
			var shortest: int = sheet.get_int(CombatValue.Key.RANGE_MIN)
			var longest: int = sheet.get_int(CombatValue.Key.RANGE_MAX)
			for y: int in 8:
				for x: int in 12:
					var tile: Vector2i = Vector2i(x, y)
					var distance: int = absi(x - origin.x) + absi(y - origin.y)
					# Some end tile within movement lies at a range distance from it.
					if distance <= movement + longest and distance + movement >= shortest:
						expected.append(tile)
		_check.call("danger zone: %s is reach plus range" % [row[1]], (
				zone.tiles_of("e1") == expected
				and zone.combined.size() == expected.size()
		), "%d tiles, expected %d" % [zone.tiles_of("e1").size(), expected.size()])


# A player unit in a corridor stops the Brute's reach: the tiles past it are out of its zone.
func _test_danger_zone_blocked() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 0))
	var zone: DangerZone = DangerZone.compute(world.engine())
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_check.call("danger zone: a player unit blocks the reach past it", (
			zone.tiles_of("e1") == expected and zone.is_threatened(Vector2i(2, 0))
	), str(zone.tiles_of("e1")))


# The same board gives the same intents twice, and computing them records nothing.
func _test_same_board_same_intents() -> void:
	var world: AiWorld = _battle(null)
	var facts: int = world.engine().fact_log.size()
	var first: String = _intents_text(Intents.compute(world.session, _catalog))
	var second: String = _intents_text(Intents.compute(world.session, _catalog))
	_check.call("determinism: the same intents twice", (
			first == second and not first.is_empty()
	), "%s / %s" % [first, second])
	_check.call("determinism: computing recorded nothing", (
			world.engine().fact_log.size() == facts and world.engine().diagnostics.is_empty()
	))


# The bench board with the AI and the intents registered and turn 1 open. rolls: null for the
# world's seeded LiveRolls.
func _battle(rolls: RollSource) -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8, rolls)
	world.add_enemy("e1", BRUTE, Vector2i(4, 2))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(6, 4))
	world.add_enemy("e3", HEALER, Vector2i(6, 2))
	world.add_player("p1", Vector2i(1, 2))
	world.add_player("p2", Vector2i(2, 4), "bow")
	world.add_player("p3", Vector2i(3, 6), "sword", {CombatValue.Key.DEF: 4.0})
	world.wound("e1", 12)
	_open(world)
	return world


func _open(world: AiWorld) -> void:
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()


func _send(world: AiWorld, command: Command) -> void:
	world.session.submit(command)
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


# Each enemy turn of the last enemy phase, in the order they acted, as _turn_of words an intent:
# "unit action target at tile".
func _enemy_turns(world: AiWorld) -> PackedStringArray:
	var facts: Array[CombatFact] = world.engine().fact_log
	var start: int = -1
	for i: int in facts.size():
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.PHASE_START and fact.side == AiWorld.ENEMY:
			start = i
	var turns: PackedStringArray = []
	if start < 0:
		return turns
	var tiles: Dictionary[String, Vector2i] = {}
	var acted: Dictionary[String, bool] = {}
	for i: int in range(start + 1, facts.size()):
		var fact: CombatFact = facts[i]
		if fact.kind == CombatFact.Kind.PHASE_END:
			break
		var actor: String = fact.actor_id
		if world.state().side_of(actor) != AiWorld.ENEMY or acted.has(actor):
			continue
		if fact.kind == CombatFact.Kind.UNIT_MOVED:
			tiles[actor] = fact.tile
			continue
		var action: String = ""
		match fact.kind:
			CombatFact.Kind.ATTACK_MADE:
				action = "attack %s" % [fact.target_id]
			CombatFact.Kind.USED_STAFF_ON_ALLY:
				action = "heal %s" % [fact.target_id]
			CombatFact.Kind.UNIT_WAITED:
				action = "wait"
		if action.is_empty():
			continue
		acted[actor] = true
		var tile: Vector2i = tiles.get(actor, world.state().tile_of(actor))
		turns.append("%s %s at %s" % [actor, action, tile])
	return turns


func _turn_of(intent: EnemyIntent) -> String:
	var action: String = "wait"
	if intent.kind == EnemyIntent.Kind.ATTACK:
		action = "attack %s" % [intent.target_id]
	elif intent.kind == EnemyIntent.Kind.HEAL:
		action = "heal %s" % [intent.target_id]
	return "%s %s at %s" % [intent.unit_id, action, intent.tile]


func _intents_text(shown: Intents) -> String:
	if shown == null:
		return "null"
	var lines: PackedStringArray = []
	for intent: EnemyIntent in shown.enemies:
		lines.append(intent.describe())
	return " | ".join(lines)


func _plan_text(plan: EnemyPlan) -> String:
	return "%s %s -> %s at %s" % [
		plan.actor_id, EnemyPlan.Kind.find_key(plan.kind), plan.target_id, plan.tile,
	]
