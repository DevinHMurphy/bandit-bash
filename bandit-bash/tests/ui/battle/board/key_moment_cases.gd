# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_moment_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The key moments' stops for the ui/board suite (game-vision.md, fast-forward: boss combats and
## any player unit's death), on the Powder Keep (Defeat the Boss) with a [BattleView] and a bound
## [BattleController]: a solo skip stops before a player unit's defeat and before the first attack
## of an exchange with the Boss, which then play at normal speed, and a skip again goes on; a solo
## held fast-forward lets go as either plays, a press fast-forwards again, and a grunt's attack or
## an enemy's defeat stops neither; a co-op map's skip stops the same; unbinding drops the hook.
##
## [b]The facts[/b] are made here and queued straight into the map's playback after the real
## battle begins, with its units' ids, so each case plays exactly the moment it names; the session
## never recorded them, so no case compares the board with the state. A skip plays on under its
## fade out, and facts with no animation take no time, so each skipped run leads with an enemy's
## defeat, whose fade holds playback past the fade out at [constant SKIP_SPEED].

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")

# tests/net/fast_forward_cases.gd's battle: the keep at the Boss floor, a fixed seed.
const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"
const BOSS_FLOOR: int = 18
const NODE: int = 0
const RUN_SEED: int = 1515

# One frame at 30 frames per second, and a minute of them, as battle_view_cases.gd steps a board.
const FRAME: float = 1.0 / 30.0
const MAX_FRAMES: int = 1800

# The game speed a skipped run plays at: a quarter, so the leading defeat's fade outlasts the
# skip's fade out whatever their tuning.
const SKIP_SPEED: float = 0.25

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK_MADE: CombatFact.Kind = CombatFact.Kind.ATTACK_MADE
const DEFEATED: CombatFact.Kind = CombatFact.Kind.DEFEATED
const BEFORE_COMBAT: CombatFact.Kind = CombatFact.Kind.BEFORE_COMBAT

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _keep: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_keep = load(KEEP_PATH) as CombatMapDefinition
	if _catalog == null or _keep == null:
		_check.call("key moments: the catalog and the Powder Keep load", false, KEEP_PATH)
		return
	_test_skip_death()
	_test_skip_boss()
	_test_hold_stops()
	_test_coop_skip()
	_test_unbind()


# A solo skip over an enemy's defeat, an attack on it and a player unit's defeat: at black it
# has stopped before the player's defeat alone, which plays once the fade clears.
func _test_skip_death() -> void:
	var board: Board = _solo_board("skip, a death")
	if board == null:
		return
	var facts: Array[CombatFact] = [
		_fact(DEFEATED, board.grunt, board.player),
		_fact(ATTACK_MADE, board.other_player, board.grunt),
		_fact(DEFEATED, board.player, board.grunt),
		_fact(ATTACK_MADE, board.boss, board.other_player),
	]
	var watch: Watch = _skip(board, facts)
	_check.call("key moments: a solo skip stops before a player unit's defeat, not an enemy's", (
			watch.started
			and watch.stopped_only(facts[2])
			and watch.paused_at_black
			and watch.pending_at_black == 2
			and watch.settled
			and board.session.playback.pending() == 0
			and not board.session.playback.is_paused
	), "%s; black: paused %s, %d left; settled %s" % [
		_kinds(watch.stops), watch.paused_at_black, watch.pending_at_black, watch.settled,
	])
	_free(board)


# A solo skip over an enemy's defeat and an exchange with the Boss stops before the exchange's
# first attack, not its BEFORE_COMBAT facts; when the fade clears the rest plays at normal speed.
func _test_skip_boss() -> void:
	var board: Board = _solo_board("skip, the Boss")
	if board == null:
		return
	var facts: Array[CombatFact] = [
		_fact(DEFEATED, board.grunt, board.player),
		_fact(BEFORE_COMBAT, board.player, board.boss),
		_fact(BEFORE_COMBAT, board.boss, board.player),
		_fact(ATTACK_MADE, board.player, board.boss),
		_fact(ATTACK_MADE, board.boss, board.player),
	]
	var watch: Watch = _skip(board, facts)
	_check.call("key moments: a solo skip stops before the first attack with the Boss", (
			watch.started
			and watch.stopped_only(facts[3])
			and watch.paused_at_black
			and watch.pending_at_black == 2
			and watch.settled
	), "%s; black: paused %s, %d left" % [
		_kinds(watch.stops), watch.paused_at_black, watch.pending_at_black,
	])
	_free(board)


# A solo hold: fast through a grunt's attack and an enemy's defeat; a player unit's defeat plays
# with the hold let go (normal speed); a press is fast again; the first attack with the Boss lets
# it go the same; and a press after it is fast again. The Boss's exchange is with the other
# Archer, whose token the defeat left on the board.
func _test_hold_stops() -> void:
	var board: Board = _solo_board("hold")
	if board == null:
		return
	var seen: Dictionary[CombatFact, bool] = {}
	var on_played: Callable = func(fact: CombatFact) -> void:
		seen[fact] = board.view.is_fast_forward()
	board.session.bus.fact_played.connect(on_played)
	var death: Array[CombatFact] = [
		_fact(ATTACK_MADE, board.grunt, board.player),
		_fact(DEFEATED, board.grunt, board.player),
		_fact(DEFEATED, board.player, board.grunt),
		_fact(ATTACK_MADE, board.grunt, board.other_player),
	]
	_hold(board, true)
	var held: bool = board.view.is_fast_forward()
	board.session.playback.enqueue(death)
	var settled: bool = _settle(board.view)
	var death_stop: bool = (
			seen.get(death[0], false) and seen.get(death[1], false)
			and not seen.get(death[2], true) and not seen.get(death[3], true)
			and not board.view.is_fast_forward()
	)
	_check.call("key moments: a solo hold lets go as a player unit's defeat plays, not before", (
			held and settled and death_stop
	), "held %s; fast at each: %s" % [held, _speeds(death, seen)])
	_hold(board, false)
	_hold(board, true)
	var again: bool = board.view.is_fast_forward()
	var boss: Array[CombatFact] = [
		_fact(BEFORE_COMBAT, board.boss, board.other_player),
		_fact(BEFORE_COMBAT, board.other_player, board.boss),
		_fact(ATTACK_MADE, board.boss, board.other_player),
		_fact(ATTACK_MADE, board.other_player, board.boss),
	]
	board.session.playback.enqueue(boss)
	settled = _settle(board.view)
	var boss_stop: bool = (
			seen.get(boss[0], false) and seen.get(boss[1], false)
			and not seen.get(boss[2], true) and not seen.get(boss[3], true)
	)
	_check.call("key moments: a press is fast again; the first attack with the Boss lets it go", (
			again and settled and boss_stop
	), "fast again %s; fast at each: %s" % [again, _speeds(boss, seen)])
	_hold(board, false)
	_hold(board, true)
	_check.call("key moments: after the Boss's stop, a press fast-forwards again", (
			board.view.is_fast_forward()
	))
	_hold(board, false)
	board.session.bus.fact_played.disconnect(on_played)
	_free(board)


# A co-op map's skip (seat 0's map, a seat-1 visitor on it) stops before a player unit's defeat
# as a solo one does.
func _test_coop_skip() -> void:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var request: CampaignSession.BattleRequest = _request([0, 1])
	request.armies[0] = _army(run, 2, 1)
	request.armies[1] = _army(run, 1, -1)
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check.call("key moments: the co-op battle begins", false)
		run.close()
		return
	var board: Board = _board(run, battle, battle.session_of_seat(0), 0, "co-op skip")
	if board == null:
		return
	var facts: Array[CombatFact] = [
		_fact(DEFEATED, board.grunt, board.player),
		_fact(DEFEATED, board.player, board.grunt),
	]
	var watch: Watch = _skip(board, facts)
	_check.call("key moments: a co-op map's skip stops before a player unit's defeat", (
			watch.started
			and watch.stopped_only(facts[1])
			and watch.paused_at_black
			and watch.settled
	), "%s; paused at black %s" % [_kinds(watch.stops), watch.paused_at_black])
	_free(board)


# Binding sets the map's pause hook; unbinding lets it go, so a skip of an unbound map stops
# for nothing.
func _test_unbind() -> void:
	var board: Board = _solo_board("unbind")
	if board == null:
		return
	var playback: FactPlayback = board.session.playback
	var bound: bool = playback.pause_hook.is_valid()
	board.controller.unbind()
	_check.call("key moments: binding sets the map's pause hook, unbinding lets it go", (
			bound and not playback.pause_hook.is_valid()
	))
	_free(board)


# Queues facts on board's playback and skips them, stepping frame by frame until it settles.
func _skip(board: Board, facts: Array[CombatFact]) -> Watch:
	var watch: Watch = Watch.new()
	var playback: FactPlayback = board.session.playback
	var on_paused: Callable = func(fact: CombatFact) -> void:
		watch.stops.append(fact)
	playback.paused_before.connect(on_paused)
	playback.speed = SKIP_SPEED
	playback.enqueue(facts)
	watch.started = board.view.skip_playback()
	var fade: SkipFade = board.view.get_skip_fade()
	for _frame: int in MAX_FRAMES:
		board.view.advance(FRAME)
		if watch.pending_at_black < 0 and fade.get_opacity() >= 1.0:
			watch.pending_at_black = playback.pending()
			watch.paused_at_black = playback.is_paused
		if board.view.is_settled():
			watch.settled = true
			break
	playback.paused_before.disconnect(on_paused)
	return watch


# A solo battle on the keep with two Archers; null, reported as label, when it can't begin.
func _solo_board(label: String) -> Board:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request([0])
	request.armies[0] = _army(run, 2, -1)
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check.call("key moments (%s): the solo battle begins" % [label], false)
		run.close()
		return null
	return _board(run, battle, battle.get_session(0), 0, label)


# A request on the keep at the Boss floor, turn 1 at once for every seat.
func _request(seats: Array[int]) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BOSS_FLOOR
	request.node = NODE
	request.pool = [_keep]
	request.catalog = _catalog
	for seat: int in seats:
		request.opening_swap[seat] = false
	return request


# count Archers with Simple Bows and, unless visitor_seat is -1, one more owned by visitor_seat.
func _army(run: CampaignSession, count: int, visitor_seat: int) -> CampaignSession.Army:
	var army: CampaignSession.Army = CampaignSession.Army.new()
	var total: int = count + (0 if visitor_seat < 0 else 1)
	for index: int in total:
		var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "archer")
		var bow_id: String = run.ids.next_item_id("Simple Bow")
		archer.weapon_id = bow_id
		army.unit_instances.append(archer)
		army.item_instances[bow_id] = ItemInstance.new(bow_id, "simple_bow")
		if index == count:
			army.visitor_seats[archer.instance_id] = visitor_seat
	return army


# A board on session for seat: the view, the HUD widgets and a controller, under the root, with
# the ids the facts name. Null, reported as label, when the keep lacks a Boss, a grunt or two
# player units.
func _board(
		run: CampaignSession,
		battle: CombatEncounter,
		session: CombatSession,
		seat: int,
		label: String
) -> Board:
	var board: Board = Board.new()
	board.run = run
	board.session = session
	var bosses: PackedStringArray = Objectives.marked_ids(session)
	var players: PackedStringArray = session.state.units_of(PLAYER)
	for enemy_id: String in session.state.units_of(ENEMY):
		if not bosses.has(enemy_id):
			board.grunt = enemy_id
			break
	if bosses.is_empty() or board.grunt.is_empty() or players.size() < 2:
		_check.call("key moments (%s): the keep has a Boss, a grunt and two player units" % [
			label,
		], false, "%s / %s / %s" % [bosses, board.grunt, players])
		run.close()
		return null
	board.boss = bosses[0]
	board.player = players[0]
	board.other_player = players[1]
	board.view = VIEW_SCENE.instantiate()
	_root.add_child(board.view)
	board.hud = CanvasLayer.new()
	_root.add_child(board.hud)
	var bar: TurnBar = TURN_BAR_SCENE.instantiate()
	var swap: SwapWindow = SWAP_WINDOW_SCENE.instantiate()
	var host: PanelHost = PANEL_HOST_SCENE.instantiate()
	var message: BattleMessage = MESSAGE_SCENE.instantiate()
	for widget: Control in [bar, swap, host, message]:
		board.hud.add_child(widget)
	board.controller = BattleController.new()
	board.controller.action_menu_scene = ACTION_MENU_SCENE
	board.controller.target_picker_scene = TARGET_PICKER_SCENE
	board.controller.confirm_dialog_scene = CONFIRM_SCENE
	board.controller.view = board.view
	board.controller.panel_host = host
	board.controller.turn_bar = bar
	board.controller.swap_window = swap
	board.controller.message = message
	_root.add_child(board.controller)
	board.view.bind(session)
	board.controller.bind(battle, session, seat)
	return board


func _free(board: Board) -> void:
	board.controller.unbind()
	board.view.unbind()
	for node: Node in [board.controller, board.view, board.hud]:
		_root.remove_child(node)
		node.free()
	board.run.close()


# Presses or releases fast_forward as the key does.
func _hold(board: Board, is_down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"fast_forward"
	event.pressed = is_down
	board.controller._unhandled_input(event)


# Steps view a frame at a time until it settles. Returns whether it did.
static func _settle(view: BattleView) -> bool:
	for _frame: int in MAX_FRAMES:
		if view.is_settled():
			return true
		view.advance(FRAME)
	return view.is_settled()


static func _fact(kind: CombatFact.Kind, actor_id: String, target_id: String) -> CombatFact:
	return CombatFact.new(kind, actor_id, target_id)


static func _kinds(facts: Array[CombatFact]) -> String:
	var names: PackedStringArray = []
	for fact: CombatFact in facts:
		names.append("%s %s>%s" % [
			CombatFact.Kind.find_key(fact.kind), fact.actor_id, fact.target_id,
		])
	return "stops [%s]" % [", ".join(names)]


static func _speeds(facts: Array[CombatFact], seen: Dictionary[CombatFact, bool]) -> String:
	var marks: PackedStringArray = []
	for fact: CombatFact in facts:
		marks.append("%s %s" % [CombatFact.Kind.find_key(fact.kind), seen.get(fact, "unplayed")])
	return ", ".join(marks)


# A keep battle's board: its run, the map shown, the view, the HUD and the controller, and the
# ids its facts name.
class Board:
	extends RefCounted

	var run: CampaignSession = null
	var session: CombatSession = null
	var view: BattleView = null
	var hud: CanvasLayer = null
	var controller: BattleController = null
	var boss: String = ""
	var grunt: String = ""
	var player: String = ""
	var other_player: String = ""


# What a watched skip did: whether it started, the facts it stopped before, what playback held
# when the fade turned black (-1 left: it never did), and whether the board settled.
class Watch:
	extends RefCounted

	var started: bool = false
	var stops: Array[CombatFact] = []
	var pending_at_black: int = -1
	var paused_at_black: bool = false
	var settled: bool = false

	# Whether the skip stopped before fact and nothing else.
	func stopped_only(fact: CombatFact) -> bool:
		return stops.size() == 1 and stops[0] == fact
