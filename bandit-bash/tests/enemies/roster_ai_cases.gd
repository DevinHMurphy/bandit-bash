# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roster_ai_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 15, 2026
# ==============================================================================

extends RefCounted
## The roster's AI cases for tests/enemies/run_all.gd, on the real catalog's classes ([EnemyAI]):
## each behavior (Guard, the Shieldbearer, the Skirmishers, the Hound's pack, the Warcaller) and
## target rule, Trample kills (a killing hit's included), kills first for every new class, each
## pack's phase playing as its intents showed, and move previews equal to the real move. Reports
## each case through the check callable it is given.
##
## Boards are plain. Level 1 hits: the Duelist's Simple Sword 5 + 4, the Shieldbearer's Simple
## Lance 7 + 2, the Warcaller's 7 + 6, the Cutthroat's Simple Dagger 2 + 5 (Backstab +2), the
## Raider's Javelin 5 + 6, the Hexer's Shade 7 + 8 magic, less DEF or RES; player units have
## 20 HP, DEF 2, RES 1.

# Preloaded scripts used as types (gdscript.md, Naming): the helpers have no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

# The roster's new classes, for the kills-first case.
const NEW_CLASSES: Array[String] = [
	"cutthroat", "duelist", "shieldbearer", "hexer", "warcaller", "raider", "hound",
]

# The roster's packs, for the phase and preview cases.
const PACKS: Array[String] = [
	"shield_and_bolt", "hex_and_knife", "field_hospital", "war_band", "hunting_party",
]

# The preview case tries every this-many-th reachable tile: enough to cross every enemy's zone,
# few enough for the suite's time limit.
const PREVIEW_STRIDE: int = 4

# Where a pack board's enemies stand, in pack order, and its four player units.
const PACK_TILES: Array[Vector2i] = [
	Vector2i(8, 1), Vector2i(8, 3), Vector2i(8, 5), Vector2i(9, 2), Vector2i(9, 4),
]

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_guard_attacks_in_reach()
	_test_guard_stays_put()
	_test_shieldbearer_beside_ally()
	_test_shieldbearer_attacks_from_its_post()
	_test_shieldbearer_kill_first()
	_test_shieldbearer_nearest_ally()
	_test_shieldbearer_without_ally()
	_test_hexer_most_cursed()
	_test_raider_back_line()
	_test_raider_trample_kill()
	_test_raider_killing_trample()
	_test_skirmisher_advances()
	_test_hound_follows_its_pack()
	_test_hound_beside_allies()
	_test_warcaller_rallies()
	_test_warcaller_attacks_only_from_a_rally_tile()
	_test_cutthroat_exposed_first()
	_test_kills_first()
	_test_phases_as_shown()
	_test_previews_match_real_moves()


# Guard: a foe within move plus range is attacked, from the tile reached with the least movement.
func _test_guard_attacks_in_reach() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "duelist", Vector2i(0, 0))
	world.add_player("p1", Vector2i(3, 0))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("guard: attacks a foe it reaches this turn, moving the least", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.behavior == EnemyClassDefinition.Behavior.GUARD
			and plan.target_id == "p1"
			and plan.tile == Vector2i(2, 0)
	), _describe(plan))


# Guard with nobody in reach waits where it stands; a Hold enemy on the same board advances.
func _test_guard_stays_put() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "duelist", Vector2i(0, 0))
	world.add_enemy("e2", "crossbowman", Vector2i(0, 1))
	world.add_player("p1", Vector2i(7, 7))
	var guard: EnemyPlan = world.decide("e1")
	var hold: EnemyPlan = world.decide("e2")
	_check.call("guard: with nobody in reach it stays put", (
			guard.kind == EnemyPlan.Kind.WAIT and guard.tile == Vector2i(0, 0)
	), _describe(guard))
	_check.call("guard: unlike Hold, which advances", (
			hold.kind == EnemyPlan.Kind.ADVANCE and hold.tile != Vector2i(0, 1)
	), _describe(hold))


# The Shieldbearer with nothing to attack walks beside its Crossbowman, on the nearer of its two
# reachable posts, (3, 0) and (4, 1).
func _test_shieldbearer_beside_ally() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "shieldbearer", Vector2i(0, 0))
	world.add_enemy("e2", "crossbowman", Vector2i(4, 0))
	world.add_player("p1", Vector2i(7, 7))
	world.add_player("p2", Vector2i(0, 2))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("shieldbearer: walks beside its back-line ally", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and plan.tile == Vector2i(3, 0)
			and plan.progress == 0
	), _describe(plan))
	_check.call("shieldbearer: and leaves the foe it could reach elsewhere", (
			plan.target_id.is_empty()
	), _describe(plan))
	_check.call("shieldbearer: it carries its Iron Shield", (
			not world.state().unit("e1").equipment_id.is_empty() and world.problems.is_empty()
	), str(world.problems))


# Beside its ally, the Shieldbearer attacks a foe in reach of its post.
func _test_shieldbearer_attacks_from_its_post() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "shieldbearer", Vector2i(0, 0))
	world.add_enemy("e2", "crossbowman", Vector2i(4, 0))
	world.add_player("p3", Vector2i(3, 1))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("shieldbearer: attacks from its post beside the ally", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p3"
			and plan.tile == Vector2i(3, 0)
	), _describe(plan))


# A kill anywhere in reach comes before its post (Ruthless AI).
func _test_shieldbearer_kill_first() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "shieldbearer", Vector2i(0, 0))
	world.add_enemy("e2", "crossbowman", Vector2i(4, 0))
	world.add_player("p2", Vector2i(0, 2))
	world.wound("p2", 5)
	var plan: EnemyPlan = world.decide("e1")
	_check.call("shieldbearer: a kill away from its post comes first", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p2"
			and plan.is_kill
			and plan.decided_by == EnemyPlan.Step.KILL
	), _describe(plan))


# Of a Hedge Healer 4 tiles away and a Crossbowman 5 away, it guards the Healer.
func _test_shieldbearer_nearest_ally() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "shieldbearer", Vector2i(0, 0))
	world.add_enemy("e2", "crossbowman", Vector2i(5, 0))
	world.add_enemy("e3", "hedge_healer", Vector2i(0, 4))
	world.add_player("p1", Vector2i(7, 7))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("shieldbearer: guards the nearest back-line ally, a Support one too", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and world.state().grid.distance(plan.tile, Vector2i(0, 4)) == 1
	), _describe(plan))


# With only a Brute beside it (no ranged weapon, no Support), it plays Guard: nobody in reach,
# so it stays.
func _test_shieldbearer_without_ally() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "shieldbearer", Vector2i(0, 0))
	world.add_enemy("e2", "brute", Vector2i(4, 0))
	world.add_player("p1", Vector2i(7, 7))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("shieldbearer: with no back-line ally it acts as a Guard", (
			plan.kind == EnemyPlan.Kind.WAIT and plan.tile == Vector2i(0, 0)
	), _describe(plan))


# The Hexer passes the nearer lone foe for the one whose Curse catches three player units, its own
# Cutthroat beside that target or not.
func _test_hexer_most_cursed() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "hexer", Vector2i(0, 1))
	world.add_enemy("e2", "cutthroat", Vector2i(2, 4))
	world.add_player("p_alone", Vector2i(2, 0))
	world.add_player("p_a", Vector2i(3, 4))
	world.add_player("p_b", Vector2i(4, 4))
	world.add_player("p_c", Vector2i(3, 5))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hexer: the foe whose curse catches the most player units", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.behavior == EnemyClassDefinition.Behavior.SKIRMISHER
			and plan.target_id == "p_a"
			and plan.target_rule_key == -3.0
			and plan.decided_by == EnemyPlan.Step.TARGET_RULE
	), _describe(plan))


# The Raider rides past a swordsman beside it to a foe carrying only a bow.
func _test_raider_back_line() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "raider", Vector2i(0, 0))
	world.add_player("p_sword", Vector2i(2, 0))
	world.add_player("p_bow", Vector2i(5, 3), "bow")
	var plan: EnemyPlan = world.decide("e1")
	_check.call("raider: goes for the back-line foe", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p_bow"
			and plan.decided_by == EnemyPlan.Step.TARGET_RULE
	), _describe(plan))


# Every tile the Raider can strike p_a from is 3+ tiles away, so Trample splashes 3 on p_b beside
# it: too armored to wound directly, but at 3 HP the splash defeats it. That kill beats the
# back-line archer it could shoot without moving, and the intent names p_b and the area.
func _test_raider_trample_kill() -> void:
	var world: AiWorld = _world(_plain(8, 3))
	world.add_enemy("e1", "raider", Vector2i(0, 0))
	world.add_player("p_a", Vector2i(5, 0))
	world.add_player("p_b", Vector2i(6, 0), "sword", {CombatValue.Key.DEF: 20.0})
	world.add_player("p_c", Vector2i(0, 2), "bow")
	world.wound("p_b", 3)
	var plan: EnemyPlan = world.decide("e1")
	var falls: bool = false
	if plan.forecast != null:
		for outcome: CombatForecast.UnitOutcome in plan.forecast.units:
			falls = falls or (outcome.unit_id == "p_b" and outcome.is_defeated)
	_check.call("raider: a Trample splash kill counts, ahead of its back-line rule", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p_a"
			and plan.is_kill
			and falls
			and plan.decided_by == EnemyPlan.Step.KILL
			and plan.path.size() >= 4
	), _describe(plan))
	var shown: Intents = Intents.compute(world.session, _catalog)
	var intent: EnemyIntent = shown.intent_of("e1")
	_check.call("raider: the intent names p_b falling and the area around p_a", (
			intent != null
			and intent.defeats.has("p_b")
			and intent.area.has(Vector2i(6, 0))
			and intent.area.has(Vector2i(5, 1))
	), "" if intent == null else intent.describe())


# The Raider's hit defeats p_a (1 HP), and Trample still splashes p_b beside it from p_a's last
# tile: the intent names both falling, and the real phase (every hit landing) defeats both.
func _test_raider_killing_trample() -> void:
	var world: AiWorld = _world(_plain(8, 3), ForecastRolls.new())
	world.add_enemy("e1", "raider", Vector2i(0, 0))
	world.add_player("p_a", Vector2i(5, 0))
	world.add_player("p_b", Vector2i(6, 0), "sword", {CombatValue.Key.DEF: 20.0})
	world.wound("p_a", 1)
	world.wound("p_b", 3)
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()
	var intent: EnemyIntent = (
			null if world.session.intents == null else world.session.intents.intent_of("e1")
	)
	_check.call("raider: a killing hit's Trample shows both units falling", (
			intent != null
			and intent.target_id == "p_a"
			and intent.defeats == PackedStringArray(["p_a", "p_b"])
			and intent.area.has(Vector2i(6, 0))
	), "" if intent == null else intent.describe())
	_send(world, EndTurnCommand.new(0))
	_check.call("raider: and the real phase defeats both", (
			not world.state().has_unit("p_a") and not world.state().has_unit("p_b")
	))


# A Skirmisher with no foe in reach advances as Aggressive does.
func _test_skirmisher_advances() -> void:
	var world: AiWorld = _world(_plain(16, 3))
	world.add_enemy("e1", "hexer", Vector2i(0, 1))
	world.add_player("p1", Vector2i(15, 1))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("skirmisher: with nothing in reach it advances", (
			plan.kind == EnemyPlan.Kind.ADVANCE and plan.target_id == "p1"
	), _describe(plan))


# The Hound's own nearest foe is p_a, but p_b stands 3 tiles from its Brute: the Hound advances on
# p_b, the foe nearest its pack.
func _test_hound_follows_its_pack() -> void:
	var world: AiWorld = _world(_plain(16, 3))
	world.add_enemy("e1", "hound", Vector2i(0, 1))
	world.add_enemy("e2", "brute", Vector2i(15, 1))
	world.add_player("p_a", Vector2i(9, 0))
	world.add_player("p_b", Vector2i(13, 2))
	var plan: EnemyPlan = world.decide("e1")
	var alone: AiWorld = _world(_plain(16, 3))
	alone.add_enemy("e1", "hound", Vector2i(0, 1))
	alone.add_player("p_a", Vector2i(9, 0))
	alone.add_player("p_b", Vector2i(13, 2))
	var lone: EnemyPlan = alone.decide("e1")
	_check.call("hound: advances on the foe nearest its pack", (
			plan.kind == EnemyPlan.Kind.ADVANCE and plan.target_id == "p_b"
	), _describe(plan))
	_check.call("hound: alone, on its own nearest foe", (
			lone.kind == EnemyPlan.Kind.ADVANCE and lone.target_id == "p_a"
	), _describe(lone))


# Three end tiles leave the same movement to the foe: (5, 0), (6, 1) and (7, 2). The fixed order
# would take (5, 0); the Hound takes (7, 2), beside the other Hound.
func _test_hound_beside_allies() -> void:
	var world: AiWorld = _world(_plain(16, 3))
	world.add_enemy("e1", "hound", Vector2i(0, 2))
	world.add_enemy("e2", "hound", Vector2i(8, 2))
	world.add_player("p1", Vector2i(15, 0))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hound: among equal tiles, the one beside an ally", (
			plan.kind == EnemyPlan.Kind.ADVANCE
			and plan.tile == Vector2i(7, 2)
			and plan.allies_beside == 1
			and plan.progress == 9
			and plan.decided_by == EnemyPlan.Step.ALLIES_BESIDE
	), _describe(plan))


# With its Brute at (4, 0) and Hound at (4, 2), the Warcaller regroups where both are within 2
# tiles: (3, 1) or (4, 1), the nearer to them both.
func _test_warcaller_rallies() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "warcaller", Vector2i(0, 0))
	world.add_enemy("e2", "brute", Vector2i(4, 0))
	world.add_enemy("e3", "hound", Vector2i(4, 2))
	world.add_player("p1", Vector2i(7, 7))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("warcaller: stays within 2 tiles of the most allies", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and plan.behavior == EnemyClassDefinition.Behavior.SUPPORT
			and plan.tile == Vector2i(4, 1)
			and plan.target_rule_key == -2.0
	), _describe(plan))


# A foe it can only reach away from its allies is left alone, unless it can defeat it; a foe in
# reach of a rally tile is attacked from there.
func _test_warcaller_attacks_only_from_a_rally_tile() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "warcaller", Vector2i(0, 0))
	world.add_enemy("e2", "brute", Vector2i(4, 0))
	world.add_enemy("e3", "hound", Vector2i(4, 2))
	world.add_player("p1", Vector2i(0, 3))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("warcaller: leaves a foe it reaches only away from its allies", (
			plan.kind == EnemyPlan.Kind.REGROUP and plan.tile == Vector2i(4, 1)
	), _describe(plan))
	world.wound("p1", 5)
	var kill: EnemyPlan = world.decide("e1")
	_check.call("warcaller: unless it can defeat it", (
			kill.kind == EnemyPlan.Kind.ATTACK and kill.target_id == "p1" and kill.is_kill
	), _describe(kill))

	var near: AiWorld = _world(_plain(8, 8))
	near.add_enemy("e1", "warcaller", Vector2i(0, 0))
	near.add_enemy("e2", "brute", Vector2i(4, 0))
	near.add_enemy("e3", "hound", Vector2i(4, 2))
	near.add_player("p2", Vector2i(2, 1))
	var attack: EnemyPlan = near.decide("e1")
	_check.call("warcaller: attacks from the tile that keeps its allies near", (
			attack.kind == EnemyPlan.Kind.ATTACK
			and attack.target_id == "p2"
			and attack.tile == Vector2i(3, 1)
	), _describe(attack))


# The Cutthroat takes an Exposed foe over a weaker one, and the lowest HP when none is Exposed.
func _test_cutthroat_exposed_first() -> void:
	var world: AiWorld = _world(_plain(8, 8))
	world.add_enemy("e1", "cutthroat", Vector2i(0, 0))
	world.add_player("p_low", Vector2i(3, 0))
	world.add_player("p_exposed", Vector2i(0, 3))
	world.wound("p_low", 8)
	world.wound("p_exposed", 18)
	var steady: EnemyPlan = world.decide("e1")
	world.state().set_stance("p_exposed", 0)
	var exposed: EnemyPlan = world.decide("e1")
	_check.call("cutthroat: the lowest HP while nobody is Exposed", (
			steady.target_id == "p_low" and steady.decided_by == EnemyPlan.Step.TARGET_RULE
	), _describe(steady))
	_check.call("cutthroat: an Exposed foe first", (
			exposed.target_id == "p_exposed" and exposed.decided_by == EnemyPlan.Step.TARGET_RULE
	), _describe(exposed))


# Every new class defeats a 1 HP foe in reach ahead of what its target rule prefers.
func _test_kills_first() -> void:
	var wrong: PackedStringArray = []
	for class_id: String in NEW_CLASSES:
		var world: AiWorld = _world(_plain(8, 8))
		world.add_enemy("e1", class_id, Vector2i(0, 0))
		world.add_player("p_rule", Vector2i(2, 0))
		world.add_player("p_weak", Vector2i(0, 4))
		world.wound("p_weak", 1)
		var plan: EnemyPlan = world.decide("e1")
		var killed: bool = (
				plan.kind == EnemyPlan.Kind.ATTACK
				and plan.target_id == "p_weak"
				and plan.is_kill
				and plan.decided_by == EnemyPlan.Step.KILL
		)
		if not killed:
			wrong.append("%s: %s" % [class_id, _describe(plan)])
	_check.call("ruthless: every new class takes a kill in reach first", wrong.is_empty(), (
			"; ".join(wrong)
	))


# Each pack against four player units, every hit landing in the real phase too: every enemy plays
# as the intents showed, with no command rejected.
func _test_phases_as_shown() -> void:
	for pack_id: String in PACKS:
		var world: AiWorld = _pack_world(pack_id, ForecastRolls.new())
		var shown: Intents = world.session.intents
		var expected: PackedStringArray = []
		if shown != null:
			for intent: EnemyIntent in shown.enemies:
				expected.append(_turn_of(intent))
		_send(world, EndTurnCommand.new(0))
		var played: PackedStringArray = _enemy_turns(world)
		var rejected: PackedStringArray = []
		for line: String in world.engine().diagnostics:
			if line.begins_with("EnemyAI"):
				rejected.append(line)
		_check.call("intents %s: the phase plays as shown" % [pack_id], (
				not expected.is_empty() and played == expected and rejected.is_empty()
		), "shown %s, played %s %s" % [expected, played, rejected])


# On the Hunting Party's and Hex and Knife's boards, a preview of the archer moving to every
# PREVIEW_STRIDE-th tile it can reach, in row-major order, equals the intents after it really
# moves there. Each tile rebuilds the board, so every tile would take minutes.
func _test_previews_match_real_moves() -> void:
	for pack_id: String in ["hunting_party", "hex_and_knife"]:
		var first: AiWorld = _pack_world(pack_id, null)
		var reach: Dictionary[Vector2i, int] = Pathing.reach(
				first.engine(), first.state(), "p_bow"
		)
		var tiles: Array[Vector2i] = []
		tiles.assign(reach.keys())
		tiles.sort_custom(EnemyPlan.tile_precedes)
		var differ: PackedStringArray = []
		var tried: int = 0
		for i: int in tiles.size():
			var tile: Vector2i = tiles[i]
			if i % PREVIEW_STRIDE != 0 or tile == first.state().tile_of("p_bow"):
				continue
			tried += 1
			var world: AiWorld = _pack_world(pack_id, null)
			var preview: Intents = Intents.preview(world.session, "p_bow", tile)
			var path: Array[Vector2i] = _path_to(world.session, "p_bow", tile)
			_send(world, UnitTurnCommand.new(0, "p_bow", UnitTurnCommand.Action.WAIT, "", path))
			var real: Intents = world.session.intents
			if _intents_text(preview) != _intents_text(real):
				differ.append("%s: %s / %s" % [tile, _intents_text(preview), _intents_text(real)])
		_check.call("preview %s: each sampled tile equals the real move (%d of %d)" % [
			pack_id, tried, tiles.size(),
		], tried > 1 and differ.is_empty(), "; ".join(differ))


func _world(rows: Array[String], rolls: RollSource = null) -> AiWorld:
	return AiWorld.new(_catalog, rows, rolls)


# pack_id's step-1 units at PACK_TILES against four player units,
# with the AI and intents registered and turn 1 open. rolls: null for the world's LiveRolls.
func _pack_world(pack_id: String, rolls: RollSource) -> AiWorld:
	var world: AiWorld = _world(_plain(10, 7), rolls)
	var pack: PackDefinition = _catalog.pack(pack_id)
	var units: PackedStringArray = [] if pack == null else pack.units(1)
	for i: int in units.size():
		world.add_enemy("e%d" % [i + 1], units[i], PACK_TILES[i])
	world.add_player("p_front", Vector2i(2, 2))
	world.add_player("p_bow", Vector2i(1, 3), "bow")
	world.add_player("p_tough", Vector2i(2, 4), "sword", {CombatValue.Key.DEF: 4.0})
	world.add_player("p_side", Vector2i(3, 6))
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()
	return world


func _send(world: AiWorld, command: Command) -> void:
	world.session.submit(command)
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


# Each enemy turn of the last enemy phase, in the order they acted, as _turn_of words an intent.
func _enemy_turns(world: AiWorld) -> PackedStringArray:
	var facts: Array[CombatFact] = world.engine().fact_log
	var start: int = -1
	for i: int in facts.size():
		if facts[i].kind == CombatFact.Kind.PHASE_START and facts[i].side == AiWorld.ENEMY:
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


# A cheapest walk from unit_id's tile to tile, as the AI and the preview walk: each step back to
# the first neighbor, in CombatGrid.DIRECTIONS order, whose cost leads to it.
static func _path_to(session: CombatSession, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = session.state
	var mover: CombatUnitState = state.unit(unit_id)
	var path: Array[Vector2i] = []
	if tile == mover.tile:
		return path
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	path.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var came_from: Vector2i = CombatFact.NO_TILE
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var before: Vector2i = state.grid.step(at, direction)
			if walked.has(before) and walked[before] + entry == walked[at]:
				came_from = before
				break
		if came_from == CombatFact.NO_TILE:
			path.clear()
			return path
		path.push_front(came_from)
		at = came_from
	return path


# Rows of Plain, width tiles by height, as AiWorld reads them.
static func _plain(width: int, height: int) -> Array[String]:
	var cells: PackedStringArray = []
	cells.resize(width)
	cells.fill("plain")
	var rows: Array[String] = []
	for _y: int in height:
		rows.append(" ".join(cells))
	return rows


static func _describe(plan: EnemyPlan) -> String:
	if plan == null:
		return "null"
	return "%s %s -> %s at %s (path %d, %s, rule %s, beside %d, progress %d)" % [
		plan.actor_id,
		EnemyPlan.Kind.find_key(plan.kind),
		plan.target_id,
		plan.tile,
		plan.path.size(),
		EnemyPlan.Step.find_key(plan.decided_by),
		plan.target_rule_key,
		plan.allies_beside,
		plan.progress,
	]
