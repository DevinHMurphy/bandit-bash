# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objective_hud_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## Every objective's HUD for the ui/display suite (combat UI plan, UI11 row): on a fixture map per
## objective, the [ObjectivePanel] shows that objective's scene and no other, and its lines follow
## the session as enemies fall and turns pass: Rout's enemies left, the Leader's and the Boss's
## marked enemies left, Seize's tiles, Survive's turns left, Defend's turns left and its warning
## while an enemy stands on its tile, and the open reinforcement points with the next arrival. On
## the M1 battle (Rout) the board draws a [LeaderMark] on each marked enemy's token through the
## HUD's refresh, and the seize, defend and point overlays draw exactly the view's tiles.[br]
## [b]Fixture maps[/b] are the map suite's ([code]tests/map/objective_cases.gd[/code]'s
## ObjectiveWorld: 6 × 4 plain with the markers each case needs, [Objectives] registered); defeats
## come from its DefeatFixture, so no case depends on a roll. The HUD is bound with no board or
## controller there, as only its objective is read. No autoload is named or needed.

const ObjectiveCases = preload("res://tests/map/objective_cases.gd")
const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_hud.tscn")

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0B7EC7

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const LEADER: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEAT_LEADER
const BOSS: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEAT_BOSS
const SEIZE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SEIZE
const SURVIVE: CombatMapDefinition.Objective = CombatMapDefinition.Objective.SURVIVE
const DEFEND: CombatMapDefinition.Objective = CombatMapDefinition.Objective.DEFEND

var _check: Callable
var _root: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the HUD and board are added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	_test_rout()
	_test_marked(LEADER, "leader")
	_test_marked(BOSS, "boss")
	_test_seize()
	_test_survive()
	_test_defend()
	_test_reinforcements()
	_test_m1_board()


# Rout: the enemies left, one fewer after each falls.
func _test_rout() -> void:
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.add_unit("e2", ENEMY, Vector2i(5, 1))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var before: String = _shown(hud)
	world.send(ObjectiveCases.DefeatFixture.new(["e1"], "p1"))
	hud.refresh()
	var after: String = _shown(hud)
	_check.call("objective hud: Rout shows its enemies left, one fewer as one falls", (
			before == "RoutObjective: Enemies left: 2"
			and after == "RoutObjective: Enemies left: 1"
			and hud.get_objective().get_text() == "Rout: defeat every enemy"
	), "%s, then %s" % [before, after])
	_free(hud, world)


# Defeat the Leader and the Boss: the enemy that appeared on the leader slot, named and counted,
# another enemy's fall changing nothing, its own winning the map with the count at 0.
func _test_marked(objective: CombatMapDefinition.Objective, label: String) -> void:
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(
			objective, 0, [[MapLayout.MarkerKind.LEADER_SLOT, Vector2i(5, 2)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.add_unit("e2", ENEMY, Vector2i(5, 2))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var name: String = BattleText.name_of(world.session, "e2")
	var first: String = _shown(hud)
	var view: HudViewModel.ObjectiveView = hud.get_objective().get_view()
	var marked: PackedStringArray = view.marked_left_ids
	world.send(ObjectiveCases.DefeatFixture.new(["e1"], "p1"))
	hud.refresh()
	var other_fell: String = _shown(hud)
	world.send(ObjectiveCases.DefeatFixture.new(["e2"], "p1"))
	hud.refresh()
	var won: String = _shown(hud)
	_check.call("objective hud: Defeat the %s names and counts the marked enemy as it falls" % [
		label,
	], (
			marked == PackedStringArray(["e2"])
			and first == "LeaderObjective: Marked left: 1 of 1 | %s | Outlined on the map" % [name]
			and other_fell == first
			and won == "LeaderObjective: Marked left: 0 of 1"
			and world.session.is_won
	), "%s / %s / %s" % [first, other_fell, won])
	_free(hud, world)


# Seize: its tiles, counted, and in the view the board draws.
func _test_seize() -> void:
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(
			SEIZE, 0, [[MapLayout.MarkerKind.SEIZE, Vector2i(2, 0)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var view: HudViewModel.ObjectiveView = hud.get_objective().get_view()
	var shown: String = _shown(hud)
	_check.call("objective hud: Seize shows its tiles, marked on the map", (
			shown == "SeizeObjective: Seize tiles: 1, marked on the map | %s" % [
				"End a unit's turn on one to win"
			]
			and _is_tiles(view.seize_tiles, [Vector2i(2, 0)])
	), shown)
	_free(hud, world)


# Survive 3: 3 turns left on turn 1, one fewer as each turn's enemy phase ends.
func _test_survive() -> void:
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(SURVIVE, 3)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var seen: PackedStringArray = [_shown(hud)]
	for _turn: int in 2:
		world.send(EndTurnCommand.new(0))
		hud.refresh()
		seen.append(_shown(hud))
	_check.call("objective hud: Survive counts its turns left down as turns pass", (
			seen == PackedStringArray([
				"SurviveObjective: Turns left: 3 of 3",
				"SurviveObjective: Turns left: 2 of 3",
				"SurviveObjective: Turns left: 1 of 3",
			])
			and world.state().turn == 3
	), " / ".join(seen))
	_free(hud, world)


# Defend 2: turns left as Survive, its tiles, and the warning only while an enemy stands on one.
func _test_defend() -> void:
	var marks: Array = [[MapLayout.MarkerKind.DEFEND, Vector2i(5, 3)]]
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(DEFEND, 2, marks)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var held: String = _shown(hud)
	world.send(EndTurnCommand.new(0))
	hud.refresh()
	var next_turn: String = _shown(hud)
	var tiles: Array[Vector2i] = hud.get_objective().get_view().defend_tiles
	_free(hud, world)

	var taken_world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(
			DEFEND, 2, marks
	)
	taken_world.add_unit("p1", PLAYER, Vector2i(0, 0))
	taken_world.add_unit("e1", ENEMY, Vector2i(5, 3))
	taken_world.session.open_battle()
	var taken_hud: BattleHud = _hud(taken_world)
	var taken: String = _shown(taken_hud)
	var lines: String = "Defend tiles: 1, marked on the map"
	_check.call("objective hud: Defend counts its turns down, and warns while its tile is taken", (
			held == "DefendObjective: Turns left: 2 of 2 | %s" % [lines]
			and next_turn == "DefendObjective: Turns left: 1 of 2 | %s" % [lines]
			and taken == (
					"DefendObjective: Turns left: 2 of 2 | %s | An enemy stands on a defend tile!"
					% [lines]
			)
			and _is_tiles(tiles, [Vector2i(5, 3)])
	), "%s / %s / %s" % [held, next_turn, taken])
	_free(taken_hud, taken_world)


# A map with a reinforcement point shows it under its objective: open, with its next wave's turn,
# the next after the first arrives; a point with no waves reads closed.
func _test_reinforcements() -> void:
	var point: Array = [MapLayout.MarkerKind.REINFORCEMENT_POINT, Vector2i(5, 3)]
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(
			SURVIVE, 5, [point]
	)
	world.set_waves({"0": [{"turn": 2}, {"turn": 4}]})
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	var hud: BattleHud = _hud(world)
	var seen: PackedStringArray = [_shown(hud)]
	var open_tiles: Array[Vector2i] = hud.get_objective().get_view().open_point_tiles()
	for _turn: int in 2:
		world.send(EndTurnCommand.new(0))
		hud.refresh()
		seen.append(_shown(hud))
	_free(hud, world)

	var closed_world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(
			ROUT, 0, [point]
	)
	closed_world.set_waves({})
	closed_world.add_unit("p1", PLAYER, Vector2i(0, 0))
	closed_world.add_unit("e1", ENEMY, Vector2i(5, 0))
	closed_world.session.open_battle()
	var closed_hud: BattleHud = _hud(closed_world)
	var closed: String = _shown(closed_hud)
	var survive: String = "SurviveObjective: Turns left: %d of 5"
	var points: String = (
			"ReinforcementStatus: Reinforcement points open: 1 of 1 | Next arrival: end of turn %d"
	)
	_check.call("objective hud: open reinforcement points show with the next arrival, then close", (
			seen == PackedStringArray([
				"%s || %s" % [survive % [5], points % [2]],
				"%s || %s" % [survive % [4], points % [2]],
				"%s || %s" % [survive % [3], points % [4]],
			])
			and _is_tiles(open_tiles, [Vector2i(5, 3)])
			and closed == (
					"RoutObjective: Enemies left: 1 || ReinforcementStatus: No more reinforcements"
			)
	), " / ".join(seen) + " / " + closed)
	_free(closed_hud, closed_world)


# The M1 battle is Rout, with no point: only Rout's scene shows, its count the M1 enemies. A
# marked enemy (as a loaded battle holds them) gets a LeaderMark on its token through the HUD's
# refresh, gone once unmarked; the seize, defend and point overlays draw a view's tiles and clear
# for none.
func _test_m1_board() -> void:
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	var run_session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = BattleViewCases.begin_m1(EffectCatalog.index(), map, run_session)
	if battle == null:
		_check.call("objective hud: the M1 battle begins", false)
		run_session.close()
		return
	var session: CombatSession = battle.get_session(0)
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)
	var layer: CanvasLayer = CanvasLayer.new()
	_root.add_child(layer)
	var hud: BattleHud = HUD_SCENE.instantiate()
	layer.add_child(hud)
	hud.bind(session, null, view)
	var enemies: PackedStringArray = session.state.units_of(ENEMY)
	var rout: String = _shown(hud)

	var marked_id: String = enemies[0]
	session.state.map.leader_ids = PackedStringArray([marked_id])
	hud.refresh()
	var marked: PackedStringArray = view.get_leader_marked()
	var mark_parent: Node = null
	for child: Node in view.token_of(marked_id).get_children():
		if child is LeaderMark:
			mark_parent = child.get_parent()
	session.state.map.leader_ids = PackedStringArray()
	hud.refresh()
	var unmarked: PackedStringArray = view.get_leader_marked()

	var marks: Array = [
		[MapLayout.MarkerKind.SEIZE, Vector2i(1, 1)],
		[MapLayout.MarkerKind.DEFEND, Vector2i(2, 1)],
		[MapLayout.MarkerKind.REINFORCEMENT_POINT, Vector2i(3, 1)],
	]
	var world: ObjectiveCases.ObjectiveWorld = ObjectiveCases.ObjectiveWorld.new(SEIZE, 0, marks)
	world.set_waves({"0": [{"turn": 3}]})
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.session.open_battle()
	var fixture: HudViewModel.ObjectiveView = HudViewModel.objective_view(world.session)
	view.show_objective(fixture)
	var seize_drawn: Array[Vector2i] = view.get_seize_overlay().shown_tiles()
	var defend_drawn: Array[Vector2i] = view.get_defend_overlay().shown_tiles()
	var points_drawn: Array[Vector2i] = view.get_point_overlay().shown_tiles()
	view.show_objective(null)
	var cleared: bool = (
			view.get_seize_overlay().shown_tiles().is_empty()
			and view.get_defend_overlay().shown_tiles().is_empty()
			and view.get_point_overlay().shown_tiles().is_empty()
	)
	_check.call("objective hud: M1 is Rout, its count the enemies on the map", (
			rout == "RoutObjective: Enemies left: %d" % [enemies.size()]
	), rout)
	_check.call("objective hud: a marked enemy is outlined on its token, and not once unmarked", (
			marked == PackedStringArray([marked_id])
			and mark_parent == view.token_of(marked_id)
			and unmarked.is_empty()
	), "marked %s, unmarked %s" % [marked, unmarked])
	_check.call("objective hud: the seize, defend and open point tiles are drawn, cleared for none", (
			_is_tiles(seize_drawn, [Vector2i(1, 1)])
			and _is_tiles(defend_drawn, [Vector2i(2, 1)])
			and _is_tiles(points_drawn, [Vector2i(3, 1)])
			and cleared
	), "%s %s %s" % [seize_drawn, defend_drawn, points_drawn])
	hud.unbind()
	view.unbind()
	layer.free()
	view.free()
	run_session.close()


# A HUD on the root, bound to world's session with no board or controller.
func _hud(world: ObjectiveCases.ObjectiveWorld) -> BattleHud:
	var hud: BattleHud = HUD_SCENE.instantiate()
	_root.add_child(hud)
	hud.bind(world.session, null, null)
	return hud


func _free(hud: BattleHud, _world: ObjectiveCases.ObjectiveWorld) -> void:
	hud.unbind()
	hud.free()


# The objective details shown, each "Name: its lines", joined by " || ".
static func _shown(hud: BattleHud) -> String:
	var parts: PackedStringArray = []
	for detail: ObjectiveDetail in hud.get_objective().get_shown_details():
		parts.append("%s: %s" % [detail.name, detail.get_text()])
	return " || ".join(parts)


# Whether tiles holds exactly expected's tiles, in order.
static func _is_tiles(tiles: Array[Vector2i], expected: Array) -> bool:
	if tiles.size() != expected.size():
		return false
	for i: int in tiles.size():
		if tiles[i] != expected[i]:
			return false
	return true
