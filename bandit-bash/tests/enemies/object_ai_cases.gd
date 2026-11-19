# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     object_ai_cases.gd
# Author:
# Created:  November 15, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The map-object AI cases for tests/enemies/roster/run_all.gd, on the real catalog's classes
## ([EnemyAI], map-objects.md, Enemy AI): a powder keg blown only to kill, friendly fire ignored,
## its intent, danger zone and phase; Cutthroat looting (a kill beats it, an attack doesn't; none
## after the darkness), its drop when defeated and its save; a lever sealing a Seize map's route
## and left alone elsewhere; a Brazier doused only while it lights a foe, never by a Guard; and an
## attack on an object forecast as a certain hit. Reports each case through its check callable.
##
## Boards are plain, with walls where a case says. Every enemy has 5 movement. The Brute's Simple
## Axe hits a player unit (20 HP, DEF 2) for 12; a keg's blast deals 5 to every unit beside it.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

# Preloaded scripts used as types (gdscript.md, Naming): the helpers have no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const KEG: MapLayout.ObjectKind = MapLayout.ObjectKind.POWDER_KEG
const CHEST: MapLayout.ObjectKind = MapLayout.ObjectKind.CHEST
const LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const BRAZIER: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER

# A chest's contents, as setup step 7 rolls one.
const CHEST_LOOT: Dictionary = {"kind": "item", "rarity": "rare"}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_object_attack_forecast()
	_test_keg_kill()
	_test_keg_not_for_damage()
	_test_keg_intent_and_phase()
	_test_cutthroat_loots()
	_test_cutthroat_kill_beats_loot()
	_test_cutthroat_after_darkness()
	_test_looter_marked_in_data()
	_test_cutthroat_denies_and_drops()
	_test_cutthroat_loot_saved()
	_test_lever_seals_seize()
	_test_lever_unused_on_rout()
	_test_brazier_doused()
	_test_brazier_left_lit()


# An attack on a powder keg forecasts with no hit roll and no error: a certain hit (P04: objects
# take no hit roll), so a keg kill's chance is 1.
func _test_object_attack_forecast() -> void:
	var world: AiWorld = _keg_world(3)
	var keg_id: String = _object_at(world, Vector2i(5, 1))
	var path: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
	]
	var command: UnitTurnCommand = UnitTurnCommand.new(
			-1, "e1", UnitTurnCommand.Action.ATTACK, keg_id, path
	)
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			world.engine(), command, ForecastRolls.new(), false
	)
	var first: CombatForecast.AttackForecast = (
			forecast.attacks[0] if not forecast.attacks.is_empty() else null
	)
	_check.call("object attack: forecast as a certain hit, no hit roll", (
			forecast.is_legal
			and first != null
			and first.hit_probability == 1.0
			and first.hit_roll == -1
			and first.is_hit
	), "legal %s, %s" % [forecast.is_legal, _attack_text(first)])


# A Brute with a healthy foe in reach and a keg beside a wounded one it can't reach blows the keg:
# the kill comes first, with certainty, though its own ally stands beside the keg too.
func _test_keg_kill() -> void:
	var world: AiWorld = _keg_world(3)
	var plan: EnemyPlan = world.decide("e1")
	var keg_id: String = _object_at(world, Vector2i(5, 1))
	_check.call("keg: a Brute blows the keg whose blast kills", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == keg_id
			and plan.is_kill
			and plan.kill_chance == 1.0
			and plan.decided_by == EnemyPlan.Step.KILL
	), _describe(plan))
	var is_ally_hit: bool = false
	for outcome: CombatForecast.UnitOutcome in plan.forecast.units:
		if outcome.unit_id == "e2" and outcome.hp_after < outcome.hp_before:
			is_ally_hit = true
	_check.call("keg: friendly fire on its ally beside the keg doesn't stop it", is_ally_hit)


# With the wounded foe healthy, the keg's blast kills nobody: the Brute attacks its foe instead,
# and no option on the keg is kept.
func _test_keg_not_for_damage() -> void:
	var world: AiWorld = _keg_world(20)
	var plan: EnemyPlan = world.decide("e1")
	_check.call("keg: never blown for damage alone", (
			plan.kind == EnemyPlan.Kind.ATTACK and plan.target_id == "p_near"
	), _describe(plan))


# The keg kill shows as the Brute's attack intent on the keg, naming the foe it defeats, with the
# blast as its area; the danger zone reaches the blast past the Brute's range; and the enemy phase
# blows it.
func _test_keg_intent_and_phase() -> void:
	var world: AiWorld = _keg_world(3)
	_register(world)
	var keg_id: String = _object_at(world, Vector2i(5, 1))
	var shown: EnemyIntent = (
			null if world.session.intents == null else world.session.intents.intent_of("e1")
	)
	# The keg's blast around (5, 1), and Cleave around the Brute at (4, 1): its hit on the keg is
	# a hit dealt like any other.
	var blast: Array[Vector2i] = [
		Vector2i(4, 0), Vector2i(5, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(6, 1), Vector2i(4, 2), Vector2i(5, 2),
	]
	_check.call("keg intent: an attack on the keg, its blast the area, the foe it fells", (
			shown != null
			and shown.kind == EnemyIntent.Kind.ATTACK
			and shown.target_id == keg_id
			and shown.is_kill
			and shown.defeats.has("p_weak")
			and shown.area == blast
	), "none" if shown == null else "%s area %s" % [shown.describe(), shown.area])
	var zone: DangerZone = world.session.intents.danger if world.session.intents != null else null
	_check.call("keg danger zone: the blast past the Brute's reach is threatened", (
			zone != null and zone.tiles_of("e1").has(Vector2i(6, 1))
	))
	_send(world, EndTurnCommand.new(0))
	var keg: MapState.ObjectState = world.state().map.object(keg_id)
	_check.call("keg phase: the Brute blows it, felling the wounded foe", (
			keg.is_destroyed and not world.state().has_unit("p_weak")
	), _rejections(world))


# A Cutthroat with a chest in reach and a healthy foe it could stab loots the chest: only a kill
# beats looting. Its intent shows the chest, with no area.
func _test_cutthroat_loots() -> void:
	var world: AiWorld = _chest_world(20)
	var chest_id: String = _object_at(world, Vector2i(4, 1))
	var plan: EnemyPlan = world.decide("c1")
	_check.call("cutthroat: loots a chest over an attack that doesn't kill", (
			plan.kind == EnemyPlan.Kind.LOOT
			and plan.target_id == chest_id
			and plan.tile == Vector2i(4, 1)
			and plan.decided_by == EnemyPlan.Step.ACTION
	), _describe(plan))
	_register(world)
	var shown: EnemyIntent = (
			null if world.session.intents == null else world.session.intents.intent_of("c1")
	)
	_check.call("cutthroat intent: uses the chest", (
			shown != null
			and shown.kind == EnemyIntent.Kind.USE_OBJECT
			and shown.target_id == chest_id
			and shown.area.is_empty()
	), "none" if shown == null else shown.describe())


# The same Cutthroat with the foe wounded to a kill takes the kill instead.
func _test_cutthroat_kill_beats_loot() -> void:
	var world: AiWorld = _chest_world(1)
	var plan: EnemyPlan = world.decide("c1")
	_check.call("cutthroat: a kill beats looting", (
			plan.kind == EnemyPlan.Kind.ATTACK and plan.target_id == "p1" and plan.is_kill
	), _describe(plan))


# Once the darkness arrives, the Cutthroat only fights.
func _test_cutthroat_after_darkness() -> void:
	var world: AiWorld = _chest_world(20)
	world.state().map.has_darkness_arrived = true
	var plan: EnemyPlan = world.decide("c1")
	_check.call("cutthroat: no looting after the darkness arrives", (
			plan.kind == EnemyPlan.Kind.ATTACK and plan.target_id == "p1"
	), _describe(plan))


# Looting is read from enemy data: the Cutthroat's class grants CAN_LOOT; a Brute's doesn't, so a
# Brute on a chest can't open it.
func _test_looter_marked_in_data() -> void:
	var world: AiWorld = _chest_world(20)
	world.add_enemy("e1", "brute", Vector2i(4, 3))
	var engine: EffectEngine = world.engine()
	var state: CombatState = world.state()
	_check.call("looter: the Cutthroat's class grants it", (
			MapObjects.is_looter(engine, state, "c1")
			and engine.stats("c1").is_allowed(CombatValue.Permission.CAN_LOOT)
	))
	_check.call("looter: a Brute is no looter", not MapObjects.is_looter(engine, state, "e1"))


# A Cutthroat denies the chest in the enemy phase, carrying its contents; the player's unit that
# defeats it takes them.
func _test_cutthroat_denies_and_drops() -> void:
	var world: AiWorld = _chest_world(20)
	_register(world)
	var chest_id: String = _object_at(world, Vector2i(4, 1))
	_send(world, EndTurnCommand.new(0))
	var state: CombatState = world.state()
	var found: Array = state.map.found.get(0, [])
	_check.call("cutthroat phase: opens the chest and carries its loot", (
			state.map.object(chest_id).is_used
			and str(state.map.carried.get("c1", [])) == str([CHEST_LOOT])
			and found.is_empty()
	), "carried %s, found %s %s" % [state.map.carried, state.map.found, _rejections(world)])
	state.defeat(world.engine(), "c1", "p1")
	world.engine().drain()
	_check.call("cutthroat: drops the loot to the seat that defeats it", (
			str(state.map.found.get(0, [])) == str([CHEST_LOOT]) and state.map.carried.is_empty()
	), str(state.map.found))


# A battle saved after the Cutthroat loots restores what it carries and its looting, and it still
# drops the loot when defeated.
func _test_cutthroat_loot_saved() -> void:
	var world: AiWorld = _chest_world(20)
	_register(world)
	_send(world, EndTurnCommand.new(0))
	var taken: Variant = JSON.parse_string(JSON.stringify(world.session.snapshot()))
	var resumed: AiWorld = _chest_world(20, false)
	var loaded: Error = (
			resumed.session.load_snapshot(taken as Dictionary)
			if taken is Dictionary else ERR_INVALID_DATA
	)
	var state: CombatState = resumed.state()
	_check.call("cutthroat save: the loot it carries restores", (
			loaded == OK
			and str(state.map.carried.get("c1", [])) == str([CHEST_LOOT])
			and MapObjects.is_looter(resumed.engine(), state, "c1")
			and resumed.session.state_hash() == world.session.state_hash()
	), error_string(loaded))
	state.defeat(resumed.engine(), "c1", "p1")
	resumed.engine().drain()
	_check.call("cutthroat save: and drops to the seat that defeats it", (
			str(state.map.found.get(0, [])) == str([CHEST_LOOT])
	), str(state.map.found))


# On a Seize map whose only route to the seize tile is an open door, a Brute with nothing to
# attack pulls its lever, sealing the route; its intent shows the lever and the door, and the
# phase closes the door.
func _test_lever_seals_seize() -> void:
	var world: AiWorld = _lever_world(CombatMapDefinition.Objective.SEIZE)
	var lever_id: String = _object_at(world, Vector2i(6, 4))
	var door_id: String = _object_at(world, Vector2i(3, 2))
	var plan: EnemyPlan = world.decide("e1", {}, EnemyAI.objective_tiles(world.session))
	_check.call("lever: a Brute seals the seize tile's route", (
			plan.kind == EnemyPlan.Kind.USE_OBJECT
			and plan.target_id == lever_id
			and plan.tile == Vector2i(6, 4)
	), _describe(plan))
	_register(world)
	var shown: EnemyIntent = (
			null if world.session.intents == null else world.session.intents.intent_of("e1")
	)
	var doors: Array[Vector2i] = [Vector2i(3, 2)]
	_check.call("lever intent: uses the lever, the door as its area", (
			shown != null
			and shown.kind == EnemyIntent.Kind.USE_OBJECT
			and shown.target_id == lever_id
			and shown.area == doors
	), "none" if shown == null else "%s area %s" % [shown.describe(), shown.area])
	_send(world, EndTurnCommand.new(0))
	_check.call("lever phase: the door is closed", (
			not world.state().map.object(door_id).is_open
	), _rejections(world))


# The same board on a Rout map: the lever seals nothing the player must reach, so it advances.
func _test_lever_unused_on_rout() -> void:
	var world: AiWorld = _lever_world(CombatMapDefinition.Objective.ROUT)
	var plan: EnemyPlan = world.decide("e1", {}, EnemyAI.objective_tiles(world.session))
	_check.call("lever: left alone off a Seize or Defend map", (
			plan.kind == EnemyPlan.Kind.ADVANCE
	), _describe(plan))


# A Brute with nothing to attack douses a lit Brazier whose light covers a player unit, from beside
# it; the phase douses it.
func _test_brazier_doused() -> void:
	var world: AiWorld = _brazier_world(Vector2i(8, 1))
	var brazier_id: String = _object_at(world, Vector2i(6, 1))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("brazier: a Brute douses the one lighting a foe", (
			plan.kind == EnemyPlan.Kind.USE_OBJECT
			and plan.target_id == brazier_id
			and plan.tile == Vector2i(5, 1)
	), _describe(plan))
	var guard: EnemyPlan = world.decide("g1")
	_check.call("brazier: a Guard never douses", guard.kind == EnemyPlan.Kind.WAIT, (
			_describe(guard)
	))
	_register(world)
	_send(world, EndTurnCommand.new(0))
	_check.call("brazier phase: doused", (
			not world.state().map.object(brazier_id).is_lit
	), _rejections(world))


# With no player unit in its light, the lit Brazier is left alone: the Brute advances.
func _test_brazier_left_lit() -> void:
	var world: AiWorld = _brazier_world(Vector2i(13, 1))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("brazier: left lit when it lights no foe", (
			plan.kind == EnemyPlan.Kind.ADVANCE
	), _describe(plan))


# 8 by 4 Plain: a keg at (5, 1); the Brute e1 at (0, 1), its Hedge Healer ally e2 beside the keg
# at (5, 0) (it never attacks); p_near at (0, 3), in the Brute's reach; p_weak at (6, 1), beside
# the keg, at weak_hp. The Brute strikes the keg from (4, 1), 4 tiles away; every tile it could
# strike p_weak from is 7 away.
func _keg_world(weak_hp: int) -> AiWorld:
	var world: AiWorld = _object_world(_plain(8, 4), [[Vector2i(5, 1), KEG]])
	world.add_enemy("e1", "brute", Vector2i(0, 1))
	world.add_enemy("e2", "hedge_healer", Vector2i(5, 0))
	world.add_player("p_near", Vector2i(0, 3))
	world.add_player("p_weak", Vector2i(6, 1))
	world.wound("p_weak", weak_hp)
	return world


# 8 by 3 Plain: a chest holding CHEST_LOOT at (4, 1), the Cutthroat c1 at (1, 1) and the player's
# p1 at (1, 0), beside it, at foe_hp. placed: whether the units are placed (a save loads them).
func _chest_world(foe_hp: int, placed: bool = true) -> AiWorld:
	var world: AiWorld = _object_world(_plain(8, 3), [[Vector2i(4, 1), CHEST]])
	world.state().map.contents[0] = CHEST_LOOT.duplicate()
	if not placed:
		return world
	world.add_enemy("c1", "cutthroat", Vector2i(1, 1))
	world.add_player("p1", Vector2i(1, 0))
	world.wound("p1", foe_hp)
	return world


# 10 by 5: a wall down column 3 but for an open door at (3, 2) (lever group 0), its lever at
# (6, 4); the player's p1 at (0, 2), the Brute e1 at (8, 4), a seize tile at (9, 2). The battle's
# objective is objective, so EnemyAI.objective_tiles reads the seize tile only on a Seize map.
func _lever_world(objective: CombatMapDefinition.Objective) -> AiWorld:
	var rows: Array[String] = []
	for y: int in 5:
		var cells: PackedStringArray = []
		for x: int in 10:
			cells.append("wall" if x == 3 and y != 2 else "plain")
		rows.append(" ".join(cells))
	var world: AiWorld = _object_world(rows, [
		[Vector2i(3, 2), DOOR, 0],
		[Vector2i(6, 4), LEVER, 0],
	], [Vector2i(9, 2)])
	var door: MapState.ObjectState = world.state().map.object(_object_at(world, Vector2i(3, 2)))
	door.is_open = true
	world.state().map.set_blocking(door.tile, MapState.Blocking.NONE)
	var setup: CombatEncounter.EncounterSetup = CombatEncounter.EncounterSetup.new()
	setup.map = CombatMapDefinition.new()
	setup.map.objective = objective
	setup.layout = world.session.layout
	world.session.setup = setup
	world.add_enemy("e1", "brute", Vector2i(8, 4))
	world.add_player("p1", Vector2i(0, 2))
	return world


# 14 by 3 Plain: a lit Brazier at (6, 1); the Brute e1 at (0, 1) and a Duelist g1 at (1, 0),
# each able to reach (5, 1) beside it; the player's p1 at foe_tile. Every tile either enemy could
# strike (8, 1) or (13, 1) from is beyond its 5 movement.
func _brazier_world(foe_tile: Vector2i) -> AiWorld:
	var world: AiWorld = _object_world(_plain(14, 3), [[Vector2i(6, 1), BRAZIER]])
	world.state().map.object(_object_at(world, Vector2i(6, 1))).is_lit = true
	world.add_enemy("e1", "brute", Vector2i(0, 1))
	world.add_enemy("g1", "duelist", Vector2i(1, 0))
	world.add_player("p1", foe_tile)
	return world


# A world on rows with spots ([tile, ObjectKind, group id]) placed as object spots and seize
# markers on seize, objects placed before any unit.
func _object_world(
		rows: Array[String], spots: Array, seize: Array[Vector2i] = []
) -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, rows, ForecastRolls.new())
	var layout: MapLayout = world.session.layout
	# Untyped: each spot is an array literal.
	for spot: Variant in spots:
		var entry: Array = spot
		var marker: MapLayout.Marker = layout.add_marker(
				MapLayout.MarkerKind.OBJECT_SPOT, entry[0] as Vector2i, entry[1] as int
		)
		marker.group_id = entry[2] if entry.size() > 2 else -1
	for tile: Vector2i in seize:
		layout.add_marker(MapLayout.MarkerKind.SEIZE, tile)
	layout.index_markers()
	MapObjects.place(world.session)
	return world


# The id of the object on tile; empty when none.
func _object_at(world: AiWorld, tile: Vector2i) -> String:
	for object_id: String in world.state().map.objects:
		if world.state().map.objects[object_id].tile == tile:
			return object_id
	return ""


# The AI and intents registered and turn 1 open, as a battle has them.
func _register(world: AiWorld) -> void:
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()


func _send(world: AiWorld, command: Command) -> void:
	world.session.submit(command)
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


# Every enemy plan the AI rejected into a Wait, as its diagnostics name them.
func _rejections(world: AiWorld) -> String:
	var rejected: PackedStringArray = []
	for line: String in world.engine().diagnostics:
		if line.begins_with("EnemyAI"):
			rejected.append(line)
	return "; ".join(rejected)


static func _attack_text(attack: CombatForecast.AttackForecast) -> String:
	if attack == null:
		return "no attack"
	return "p %s roll %d hit %s" % [attack.hit_probability, attack.hit_roll, attack.is_hit]


static func _describe(plan: EnemyPlan) -> String:
	if plan == null:
		return "null"
	return "%s %s -> %s at %s (%s, kill %s %s)" % [
		plan.actor_id,
		EnemyPlan.Kind.find_key(plan.kind),
		plan.target_id,
		plan.tile,
		EnemyPlan.Step.find_key(plan.decided_by),
		plan.is_kill,
		plan.kill_chance,
	]


# Rows of Plain, width tiles by height, as AiWorld reads them.
static func _plain(width: int, height: int) -> Array[String]:
	var cells: PackedStringArray = []
	cells.resize(width)
	cells.fill("plain")
	var rows: Array[String] = []
	for _y: int in height:
		rows.append(" ".join(cells))
	return rows
