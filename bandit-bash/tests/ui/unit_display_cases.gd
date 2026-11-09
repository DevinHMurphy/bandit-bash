# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_display_cases.gd
# Author:
# Created:  November 5, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## The unit display's cases for the ui/display suite (combat UI plan, UI7 row): each M1 unit's
## sprite or letters and its side's outline; the HP and Stance bars and the Block badge following
## played facts, and agreeing with the session through an M1 battle; grayscale once a unit can't
## act, and colour again at its side's next phase; the range-tracked icon following the enemy
## range toggle. No autoload is named or needed.
##
## [b]The battle driver[/b] works from turn input's own model ([TurnInputModel]): each acting
## unit takes, from the first of its move tiles in row-major order that offers one, a Staff
## (so Block staves give Block) or else an Attack on its first target; with neither, it waits
## where it stands. Then the seat ends its turn. The board is settled after every command and
## must then agree with the state ([method BattleView.mismatches]), Block, Stance and turn
## included.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const SPRITE_TABLE: String = "res://assets/sprites/units/unit_sprites.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://ui/battle/forecast/forecast_panel.tscn")

# The unit types and enemy classes of M1's battle: the Mercenary army and the M1 pack.
const M1_TYPES: Array[String] = [
	"archer", "battle_medic", "brute", "crossbowman", "drengr", "hakkapel", "hedge_healer",
]

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Player phases the battle may take: past what the M1 battle needs, so only a stall reaches it.
const MAX_PHASES: int = 40

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const STAFF: TurnInputModel.ActionKind = TurnInputModel.ActionKind.STAFF

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("unit display: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_sprites()
	_test_values_follow_facts()
	_test_values_through_battle()
	_test_spent()
	_test_range_tracked()


# Every M1 type has a sprite in the table, and every M1 token draws its own with its side's
# outline; a type the table lacks keeps its letters.
func _test_sprites() -> void:
	var table: UnitSpriteTable = load(SPRITE_TABLE) as UnitSpriteTable
	var unmapped: PackedStringArray = []
	for unit_type: String in M1_TYPES:
		if table == null or table.sprite_for(unit_type) == null:
			unmapped.append(unit_type)
	_check.call("sprites: the table maps every M1 unit type and enemy class", (
			table != null and unmapped.is_empty()
	), "unmapped %s" % [unmapped])

	var board: BattleViewCases.Board = _board("sprites: the M1 battle begins")
	if board == null:
		return
	var state: CombatState = board.session.state
	var wrong: PackedStringArray = []
	var seen: Dictionary[String, bool] = {}
	for unit_id: String in state.unit_ids():
		var token: UnitToken = board.view.token_of(unit_id)
		var unit_type: String = state.unit_type_of(unit_id)
		seen[unit_type] = true
		if token == null:
			wrong.append("%s: no token" % [unit_id])
			continue
		var expected: Texture2D = token.sprite_for(unit_type)
		if expected == null:
			if token.has_sprite() or not token.is_showing_letters():
				wrong.append("%s (%s): no sprite, yet the letters are hidden" % [unit_id, unit_type])
		elif token.get_sprite() != expected or token.is_showing_letters():
			wrong.append("%s (%s): not its sprite" % [unit_id, unit_type])
		if not token.get_outline().is_equal_approx(token.outline_of(state.side_of(unit_id))):
			wrong.append("%s: outline %s" % [unit_id, token.get_outline()])
	var types: Array[String] = []
	types.assign(seen.keys())
	types.sort()
	_check.call("sprites: every M1 unit shows its mapped sprite, outlined by side", (
			wrong.is_empty() and types == M1_TYPES
	), "%s; types %s" % ["; ".join(wrong), types])

	var first: String = state.units_of(PLAYER)[0]
	var token: UnitToken = board.view.token_of(first)
	var view: BoardViewModel.UnitView = BoardViewModel.unit_view(board.session, first)
	view.unit_type = "nobody_known"
	token.show_unit(view)
	var lettered: bool = (
			token.is_showing_letters() and not token.has_sprite() and token.get_letters() == "NO"
	)
	token.show_unit(BoardViewModel.unit_view(board.session, first))
	_check.call("sprites: a type with no sprite keeps its letters", (
			lettered and token.has_sprite()
	))
	_check.call("sprites: players outlined navy, enemies dark red (Godot_FE)", (
			token.outline_of(PLAYER).is_equal_approx(Color.NAVY_BLUE)
			and token.outline_of(ENEMY).is_equal_approx(Color.DARK_RED)
	))
	board.close()


# Facts played to one token move its Block badge, Stance bar and HP bar by their amounts, and a
# refresh empties Block and fills Stance; the turn facts gray it and a refresh clears it.
func _test_values_follow_facts() -> void:
	var board: BattleViewCases.Board = _board("follow: the M1 battle begins")
	if board == null:
		return
	var unit_id: String = board.session.state.units_of(PLAYER)[0]
	var token: UnitToken = board.view.token_of(unit_id)
	var stance_max: int = board.session.stats(unit_id).get_int(CombatValue.Key.STANCE_MAX)
	var hp: int = token.hp
	var badge: BlockBadge = token.get_block_badge()
	var problems: PackedStringArray = []

	_play(board, [_fact(CombatFact.Kind.BLOCK_GAINED, unit_id, 4)])
	if token.block != 4 or not badge.visible or badge.get_text() != "4":
		problems.append("gain 4: block %d, badge %s %s" % [token.block, badge.visible, badge.get_text()])
	var hit: CombatFact = _fact(CombatFact.Kind.DAMAGE_TAKEN, unit_id, 5)
	hit.hp_amount = 2
	hit.block_amount = 3
	_play(board, [hit])
	if token.block != 1 or token.hp != hp - 2:
		problems.append("hit 2 + 3 Block: block %d, hp %d" % [token.block, token.hp])
	_play(board, [_fact(CombatFact.Kind.BLOCK_LOST, unit_id, 1)])
	if token.block != 0 or badge.visible:
		problems.append("lose 1: block %d, badge shown %s" % [token.block, badge.visible])
	_play(board, [_fact(CombatFact.Kind.STANCE_CHANGED, unit_id, -1)])
	var lowered: Vector2i = token.get_stance_bar()
	if token.stance != stance_max - 1 or lowered != Vector2i(stance_max - 1, maxi(stance_max, 1)):
		problems.append("stance -1: %d, bar %s" % [token.stance, lowered])
	_play(board, [
		_fact(CombatFact.Kind.BLOCK_GAINED, unit_id, 2),
		_fact(CombatFact.Kind.BLOCK_STANCE_REFRESHED, unit_id, 0),
	])
	if token.block != 0 or token.stance != stance_max or badge.visible:
		problems.append("refresh: block %d, stance %d of %d" % [token.block, token.stance, stance_max])
	_check.call("follow: the Block badge, Stance bar and HP bar move by each fact's amounts", (
			stance_max > 0 and problems.is_empty()
	), "; ".join(problems))

	var turn: PackedStringArray = []
	_play(board, [_fact(CombatFact.Kind.UNIT_WAITED, unit_id, 0)])
	if not token.is_spent() or not is_equal_approx(token.get_gray(), token.spent_gray):
		turn.append("a Wait: spent %s, gray %s" % [token.is_spent(), token.get_gray()])
	_play(board, [_fact(CombatFact.Kind.BLOCK_STANCE_REFRESHED, unit_id, 0)])
	if token.is_spent() or token.get_gray() != 0.0:
		turn.append("a refresh: spent %s, gray %s" % [token.is_spent(), token.get_gray()])
	var acted: CombatFact = _fact(CombatFact.Kind.USED_STAFF_ON_ALLY, unit_id, 0)
	acted.flags = CombatFact.Flag.SECOND_MOVE_PENDING
	_play(board, [acted])
	var after_action: bool = token.is_spent()
	var walked: CombatFact = _fact(CombatFact.Kind.UNIT_MOVED, unit_id, 1)
	walked.tile = token.tile
	_play(board, [walked])
	if after_action or not token.is_spent():
		turn.append("a second move: spent %s after acting, %s after it" % [
			after_action, token.is_spent(),
		])
	_check.call("follow: acting grays a token, a second move waits, the refresh clears it", (
			turn.is_empty()
	), "; ".join(turn))
	board.close()


# An M1 battle driven by Staff, Attack and Wait: after every command the board agrees with the
# state, Block, Stance and turn included, and the battle gained Block, lost Block to hits and
# changed Stance.
func _test_values_through_battle() -> void:
	var board: BattleViewCases.Board = _board("battle: the M1 battle begins")
	if board == null:
		return
	var played: Dictionary[int, int] = {}
	var blocked_hits: Array[int] = [0]
	var on_played: Callable = func(fact: CombatFact) -> void:
		played[fact.kind] = played.get(fact.kind, 0) + 1
		if fact.kind == CombatFact.Kind.DAMAGE_TAKEN and fact.block_amount > 0:
			blocked_hits[0] += 1
	board.session.bus.fact_played.connect(on_played)
	var disagreements: PackedStringArray = []
	var rejected: PackedStringArray = []
	for _phase: int in MAX_PHASES:
		if board.session.is_finished:
			break
		for unit_id: String in board.session.state.units_of(PLAYER):
			if board.session.is_finished:
				break
			if TurnInputModel.can_act(board.session, unit_id):
				_send(board, _driver_command(board.session, unit_id), disagreements, rejected)
		if not board.session.is_finished:
			_send(board, EndTurnCommand.new(0), disagreements, rejected)
	board.session.bus.fact_played.disconnect(on_played)
	_check.call("battle: after every command the tokens agree with the state", (
			board.session.is_finished and disagreements.is_empty() and rejected.is_empty()
	), "finished %s; %s; rejected %s" % [
		board.session.is_finished, "; ".join(disagreements.slice(0, 3)), rejected,
	])
	_check.call("battle: Block was gained and absorbed hits, and Stance changed", (
			played.get(CombatFact.Kind.BLOCK_GAINED, 0) > 0
			and blocked_hits[0] > 0
			and played.get(CombatFact.Kind.STANCE_CHANGED, 0) > 0
	), "%d Block gains, %d hits into Block, %d Stance changes" % [
		played.get(CombatFact.Kind.BLOCK_GAINED, 0), blocked_hits[0],
		played.get(CombatFact.Kind.STANCE_CHANGED, 0),
	])
	board.close()


# A unit that waits turns gray and the rest of its side doesn't; enemies that acted are gray once
# their phase ends; at each side's next Phase Start its units are in colour again.
func _test_spent() -> void:
	var board: BattleViewCases.Board = _board("spent: the M1 battle begins")
	if board == null:
		return
	var state: CombatState = board.session.state
	var players: PackedStringArray = state.units_of(PLAYER)
	var waiter: String = players[0]
	var problems: PackedStringArray = []
	_send(board, UnitTurnCommand.new(0, waiter, UnitTurnCommand.Action.WAIT), problems, problems)
	for unit_id: String in players:
		var token: UnitToken = board.view.token_of(unit_id)
		var should_gray: bool = unit_id == waiter
		if token.is_spent() != should_gray or (token.get_gray() > 0.0) != should_gray:
			problems.append("%s: spent %s, gray %s" % [unit_id, token.is_spent(), token.get_gray()])

	# Each side's units are read the moment that side's Phase Start plays, after its refresh.
	var at_phase_start: Dictionary[int, PackedStringArray] = {}
	var on_phase: Callable = func(fact: CombatFact) -> void:
		var gray: PackedStringArray = []
		for unit_id: String in state.units_of(fact.side):
			var token: UnitToken = board.view.token_of(unit_id)
			if token != null and (token.is_spent() or token.get_gray() > 0.0):
				gray.append(unit_id)
		at_phase_start[fact.side] = gray
	board.session.bus.flow.phase_started.connect(on_phase)
	_send(board, EndTurnCommand.new(0), problems, problems)
	board.session.bus.flow.phase_started.disconnect(on_phase)
	var gray_enemies: int = 0
	for unit_id: String in state.units_of(ENEMY):
		if board.view.token_of(unit_id).is_spent():
			gray_enemies += 1
	_check.call("spent: a unit that waits turns gray, the rest of its side doesn't", (
			problems.is_empty()
	), "; ".join(problems))
	_check.call("spent: enemies that acted are gray after their phase", gray_enemies > 0, (
			"%d gray" % [gray_enemies]
	))
	_check.call("spent: each side is in colour again at its next Phase Start", (
			at_phase_start.has(ENEMY)
			and at_phase_start.has(PLAYER)
			and at_phase_start[ENEMY].is_empty()
			and at_phase_start[PLAYER].is_empty()
			and not board.view.token_of(waiter).is_spent()
	), "gray at Phase Start: %s" % [at_phase_start])
	board.close()


# Accept on an enemy in IDLE shows its token's range-tracked icon, on that token only, with the
# sprite untinted (question 28 (e): the tint defaults to white); a second enemy adds its own;
# accept again on the first hides its icon alone.
func _test_range_tracked() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var enemies: PackedStringArray = h.session.state.units_of(ENEMY)
	var first: String = enemies[0]
	var second: String = enemies[1]
	_key_to(h, h.session.state.tile_of(first))
	_press(&"ui_accept")
	var one: PackedStringArray = _tracked_icons(h)
	var tint: Color = h.view.token_of(first).range_tracked_tint
	var is_untinted: bool = h.view.token_of(first).is_range_tracked and tint == Color.WHITE
	_key_to(h, h.session.state.tile_of(second))
	_press(&"ui_accept")
	var both: PackedStringArray = _tracked_icons(h)
	_key_to(h, h.session.state.tile_of(first))
	_press(&"ui_accept")
	var after: PackedStringArray = _tracked_icons(h)
	var expected_both: PackedStringArray = PackedStringArray([first, second])
	expected_both.sort()
	_check.call("range icon: it follows the enemy range toggle, token by token", (
			one == PackedStringArray([first])
			and is_untinted
			and both == expected_both
			and after == PackedStringArray([second])
			and h.controller.get_shown_enemies() == PackedStringArray([second])
	), "one %s, both %s, after %s" % [one, both, after])
	h.close()


# --- Fixtures --------------------------------------------------------------------------------


# A new M1 battle on a board, past Start; null, with case_name reported, when it can't begin.
func _board(case_name: String) -> BattleViewCases.Board:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = BattleViewCases.begin_m1(_catalog, _map, run)
	if battle == null:
		_check.call(case_name, false, "begin_battle gave no battle")
		run.close()
		return null
	var board: BattleViewCases.Board = BattleViewCases.Board.new()
	board.run = run
	board.battle = battle
	board.session = battle.get_session(0)
	board.view = VIEW_SCENE.instantiate()
	_root.add_child(board.view)
	board.view.bind(board.session)
	if board.session.state.map.opening_swap_open:
		board.battle.submit(StartCommand.new(0), board.session.session_id)
		board.battle.resolve_queued()
		BattleViewCases.settle(board.view)
	return board


# Sends command, settles the board, and notes a rejection or a disagreement with the state.
func _send(
		board: BattleViewCases.Board,
		command: Command,
		disagreements: PackedStringArray,
		rejected: PackedStringArray
) -> void:
	board.battle.submit(command, board.session.session_id)
	for batch: CombatSession.FactBatch in board.battle.resolve_queued():
		if batch.is_rejected():
			rejected.append("%s: %s" % [batch.label, batch.rejected_reason])
	if not BattleViewCases.settle(board.view):
		disagreements.append("%s never settled" % [command.get_label()])
		return
	var found: PackedStringArray = board.view.mismatches()
	if not found.is_empty():
		disagreements.append("after %s: %s" % [command.get_label(), ", ".join(found)])


# Plays facts through the board's playback, as a resolved batch would, and settles it.
func _play(board: BattleViewCases.Board, facts: Array[CombatFact]) -> void:
	board.session.playback.enqueue(facts)
	BattleViewCases.settle(board.view)


func _fact(kind: CombatFact.Kind, actor_id: String, amount: int) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor_id)
	fact.amount = amount
	return fact


# The driver's command for unit_id (class doc).
func _driver_command(session: CombatSession, unit_id: String) -> Command:
	var attack: Command = null
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				session, unit_id, path
		):
			if option.targets.is_empty():
				continue
			if option.kind == STAFF:
				return option.targets[0].command
			if option.kind == ATTACK and attack == null:
				attack = option.targets[0].command
	if attack != null:
		return attack
	return UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)


# The ids of the units whose token shows the range-tracked icon, sorted.
func _tracked_icons(h: TurnInputCases.Harness) -> PackedStringArray:
	var ids: PackedStringArray = []
	for unit_id: String in h.view.token_ids():
		if h.view.token_of(unit_id).is_range_icon_shown():
			ids.append(unit_id)
	return ids


# The M1 battle with turn input, past Start, as targeting_cases.gd builds it.
func _harness() -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("range icon: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.forecast_panel_scene = FORECAST_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	return h


func _press(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


# Moves the cursor to tile with the arrow keys.
func _key_to(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	var cursor: Vector2i = h.controller.get_cursor_tile()
	var dx: int = tile.x - cursor.x
	var dy: int = tile.y - cursor.y
	for _i: int in absi(dx):
		_press(&"ui_right" if dx > 0 else &"ui_left")
	for _i: int in absi(dy):
		_press(&"ui_down" if dy > 0 else &"ui_up")
