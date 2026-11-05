# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_view_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

extends RefCounted
## The battle board's cases for tests/ui/run_all.gd (combat UI plan, UI1 row): the view-model,
## the board built on the M1 map, a whole M1 battle's facts played through the session's
## playback, the darkness overlay, held fast-forward and the faded skip. No autoload is named or
## needed.
##
## [b]The battle:[/b] the Mercenary army ([method StartingArmy.build]) against the M1 pack on the
## greybox map, begun through [method CampaignSession.begin_battle] on the real catalog, as in
## [code]tests/enemies/m1_battle_cases.gd[/code], with a driver of the same shape: in the opening
## swap window it sends Start; each player unit attacks the first enemy it can hit from the first
## reachable tile (row-major), else walks to the reachable tile nearest an enemy and waits; then
## the seat ends its turn. After every command the board is stepped frame by frame until it
## settles, and it must then agree with the state.[br]
## [b]Twins:[/b] the fast-forward and skip cases begin the same battle more than once from the
## same seed, so the same command gives each board the same facts to compare their timing on.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Floor 1 is step 1, whose enemies are level 1 (game-vision.md, Run structure).
const FLOOR: int = 1
const NODE: int = 1

# Player phases the battle may take: past what the M1 battle needs, so only a stall reaches it.
const MAX_PHASES: int = 40

# One frame at 30 frames per second: the board is stepped as the game steps it.
const FRAME: float = 1.0 / 30.0

# Frames a board may take to settle after one command: a minute of playback.
const MAX_SETTLE_FRAMES: int = 1800

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if map == null:
		_check.call("board: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_view_model(map)
	_test_board_and_playback(map)
	_test_darkness_overlay(map)
	_test_fast_forward(map)
	_test_skip(map)
	_test_skip_stops(map)


## Begins the M1 battle for a new solo run; null, with the problem reported, when it can't.
static func begin_m1(
		catalog: EffectCatalog.Index, map: CombatMapDefinition, run: CampaignSession
) -> CombatEncounter:
	var mercenary: StartingArmy = StartingArmy.build(catalog, "mercenary", run.ids)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = mercenary.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = catalog
	request.armies[0] = army
	return run.begin_battle(request)


## Steps [param view] a frame at a time until it settles. Returns whether it did.
static func settle(view: BattleView) -> bool:
	for _frame: int in MAX_SETTLE_FRAMES:
		if view.is_settled():
			return true
		view.advance(FRAME)
	return view.is_settled()


func _test_view_model(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("view-model: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var model: BoardViewModel = BoardViewModel.build(session)
	var wrong: PackedStringArray = []
	var ids: PackedStringArray = []
	for view: BoardViewModel.UnitView in model.units:
		ids.append(view.id)
		var expected: Array = [
			state.side_of(view.id),
			state.seat_of(view.id),
			state.get_hp(view.id),
			session.stats(view.id).get_int(CombatValue.Key.HP),
			state.tile_of(view.id),
			state.unit_type_of(view.id).replace("_", "").left(2).to_upper(),
		]
		var shown: Array = [view.side, view.seat, view.hp, view.max_hp, view.tile, view.letter]
		if shown != expected:
			wrong.append("%s %s, not %s" % [view.id, shown, expected])
	_check.call("view-model: one view per unit, in the state's order", (
			ids == state.unit_ids()
	), "%s / %s" % [ids, state.unit_ids()])
	_check.call("view-model: side, seat, HP, max HP, tile and letter match the state", (
			wrong.is_empty() and not model.units.is_empty()
	), "; ".join(wrong))
	var players: int = 0
	for view: BoardViewModel.UnitView in model.units:
		if view.side == PLAYER and view.seat == 0 and view.max_hp > 0 and view.hp == view.max_hp:
			players += 1
	_check.call("view-model: the four Mercenaries start on seat 0 at full HP", (
			players == 4
	), str(players))
	_check.call("view-model: an empty unit type shows ?", BoardViewModel.letter_of("") == "?")
	var pairs: Array[PackedStringArray] = [
		PackedStringArray(["hakkapel", "hedge_healer"]),
		PackedStringArray(["brute", "battle_medic"]),
	]
	var same: PackedStringArray = []
	for pair: PackedStringArray in pairs:
		var left: String = BoardViewModel.letter_of(pair[0])
		var right: String = BoardViewModel.letter_of(pair[1])
		if left == right or left.length() != 2 or right.length() != 2:
			same.append("%s %s / %s %s" % [pair[0], left, pair[1], right])
	_check.call("view-model: two letters; Hakkapel, Hedge Healer and Brute, Battle Medic differ", (
			same.is_empty()
			and BoardViewModel.letter_of("hakkapel") == "HA"
			and BoardViewModel.letter_of("battle_medic") == "BA"
	), "; ".join(same))
	run.close()


func _test_board_and_playback(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("board: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)

	var sorted_ids: PackedStringArray = state.unit_ids()
	sorted_ids.sort()
	var step: Vector2 = (
			view.tile_to_position(Vector2i(1, 0)) - view.tile_to_position(Vector2i.ZERO)
	)
	_check.call("board: the M1 map is instanced, 32 px tiles", (
			step.is_equal_approx(Vector2(32.0, 0.0)) and view.map_rect().size.x > 0.0
	), "%s, %s" % [step, view.map_rect()])
	_check.call("board: one token per unit", view.token_ids() == sorted_ids, (
			"%s / %s" % [view.token_ids(), sorted_ids]
	))
	_check.call("board: every token on its unit's tile, at full HP", (
			view.mismatches().is_empty()
	), "; ".join(view.mismatches()))
	_check_token_letters(session, view)

	var played: Dictionary[int, int] = {}
	var on_played: Callable = func(fact: CombatFact) -> void:
		var count: int = played.get(fact.kind, 0)
		played[fact.kind] = count + 1
	session.bus.fact_played.connect(on_played)
	var result: Played = _play(battle, session, view)
	session.bus.fact_played.disconnect(on_played)

	_check.call("playback: the battle runs to its end with no rejected command", (
			session.is_finished and result.rejected.is_empty() and result.stalls.is_empty()
	), "finished %s after turn %d; rejected %s; stalls %s" % [
		session.is_finished, state.turn, result.rejected, result.stalls,
	])
	_check.call("playback: after every command the board agrees with the state", (
			result.disagreements.is_empty()
	), "; ".join(result.disagreements.slice(0, 3)))
	var defeated: PackedStringArray = []
	for unit_id: String in sorted_ids:
		if not state.has_unit(unit_id):
			defeated.append(unit_id)
	var leftover: PackedStringArray = []
	for unit_id: String in defeated:
		if view.token_of(unit_id) != null:
			leftover.append(unit_id)
	_check.call("playback: defeated units are gone from the board", (
			not defeated.is_empty() and leftover.is_empty()
	), "defeated %s, still shown %s" % [defeated, leftover])
	var survivors: PackedStringArray = state.unit_ids()
	survivors.sort()
	_check.call("playback: the survivors' tokens stand where the state says", (
			view.token_ids() == survivors and view.mismatches().is_empty()
	), "; ".join(view.mismatches()))
	var animated: Array[CombatFact.Kind] = [
		CombatFact.Kind.UNIT_MOVED,
		CombatFact.Kind.DAMAGE_TAKEN,
		CombatFact.Kind.DEFEATED,
		CombatFact.Kind.COMBAT_ENDED,
	]
	var missing: Array[String] = []
	for kind: CombatFact.Kind in animated:
		if played.get(kind, 0) == 0:
			missing.append(CombatFact.Kind.find_key(kind) as String)
	_check.call("playback: moves, damage, defeats and the end all played on the bus", (
			missing.is_empty()
	), "never played: %s" % [missing])
	view.free()
	run.close()


# Each token on the M1 board shows its type's two letters, no two types alike; an override in
# [member UnitToken.letter_overrides] replaces them.
func _check_token_letters(session: CombatSession, view: BattleView) -> void:
	var wrong: PackedStringArray = []
	var by_letters: Dictionary[String, String] = {}
	for unit_id: String in session.state.unit_ids():
		var token: UnitToken = view.token_of(unit_id)
		var unit_type: String = session.state.unit_type_of(unit_id)
		if token == null:
			wrong.append("%s: no token" % [unit_id])
			continue
		var shown: String = token.get_letters()
		if shown != BoardViewModel.letter_of(unit_type) or shown.length() != 2:
			wrong.append("%s (%s): %s" % [unit_id, unit_type, shown])
		if by_letters.get(shown, unit_type) != unit_type:
			wrong.append("%s and %s both show %s" % [by_letters[shown], unit_type, shown])
		by_letters[shown] = unit_type
	_check.call("board: each token shows its type's two letters, no two types alike", (
			wrong.is_empty() and by_letters.size() > 1
	), "; ".join(wrong))

	var first: String = session.state.unit_ids()[0]
	var sample: UnitToken = view.token_of(first)
	var overridden: bool = false
	if sample != null:
		sample.letter_overrides = {session.state.unit_type_of(first): "Zz"}
		sample.show_unit(BoardViewModel.unit_view(session, first))
		overridden = sample.get_letters() == "Zz"
		sample.letter_overrides = {}
		sample.show_unit(BoardViewModel.unit_view(session, first))
	_check.call("board: a token's letter override replaces its letters", overridden)


func _test_darkness_overlay(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("darkness: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)
	var overlay: DarknessOverlay = view.get_darkness()
	_check.call("darkness: a dry map draws no tile", overlay.drawn_tiles().is_empty(), (
			str(overlay.drawn_tiles())
	))

	# A fixture state over the same grid: one tile of each layer.
	var fixture: CombatState = CombatState.new(session.state.grid)
	fixture.map.darkness.layers[Vector2i(0, 0)] = WhileLayerCondition.Layer.DUSK
	fixture.map.darkness.layers[Vector2i(1, 0)] = WhileLayerCondition.Layer.GLOOM
	fixture.map.darkness.layers[Vector2i(2, 0)] = WhileLayerCondition.Layer.ABYSS
	overlay.show_layers(BoardViewModel.darkness_of(fixture))
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_check.call("darkness: each layer of a fixture state is drawn on its tile", (
			overlay.drawn_tiles() == expected
			and overlay.layer_at(Vector2i(0, 0)) == WhileLayerCondition.Layer.DUSK
			and overlay.layer_at(Vector2i(1, 0)) == WhileLayerCondition.Layer.GLOOM
			and overlay.layer_at(Vector2i(2, 0)) == WhileLayerCondition.Layer.ABYSS
			and overlay.layer_at(Vector2i(3, 0)) == WhileLayerCondition.Layer.DRY
	), str(overlay.drawn_tiles()))
	var dusk: Color = overlay.color_of(WhileLayerCondition.Layer.DUSK)
	var gloom: Color = overlay.color_of(WhileLayerCondition.Layer.GLOOM)
	var abyss: Color = overlay.color_of(WhileLayerCondition.Layer.ABYSS)
	_check.call("darkness: each layer draws at its own alpha, deeper darker", (
			is_equal_approx(dusk.a, overlay.dusk_alpha)
			and is_equal_approx(gloom.a, overlay.gloom_alpha)
			and is_equal_approx(abyss.a, overlay.abyss_alpha)
			and dusk.a < gloom.a
			and gloom.a < abyss.a
			and overlay.color_of(WhileLayerCondition.Layer.DRY).a == 0.0
	), "%s %s %s" % [dusk.a, gloom.a, abyss.a])

	# DARKNESS_ADVANCED reaches the board through playback and redraws its tile; a wave's release
	# (no tile) draws nothing.
	var deepened: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
	deepened.tile = Vector2i(4, 4)
	deepened.amount = WhileLayerCondition.Layer.GLOOM
	var released: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
	var facts: Array[CombatFact] = [released, deepened]
	session.playback.enqueue(facts)
	var has_settled: bool = settle(view)
	_check.call("darkness: DARKNESS_ADVANCED played back redraws that tile only", (
			has_settled
			and overlay.layer_at(Vector2i(4, 4)) == WhileLayerCondition.Layer.GLOOM
			and overlay.drawn_tiles().size() == 4
	), str(overlay.drawn_tiles()))
	view.free()
	run.close()


# One unit's longest walk, sent to twin boards: the one with fast-forward held settles in about a
# fast_forward_speed-th of the frames, and both end where the state says.
func _test_fast_forward(map: CombatMapDefinition) -> void:
	var case_name: String = "fast-forward: held, a walk takes a fast_forward_speed-th of the time"
	var normal: Board = _started_board(map, case_name)
	var fast: Board = _started_board(map, case_name)
	if normal == null or fast == null:
		for board: Board in [normal, fast]:
			if board != null:
				board.close()
		return
	var unit_id: String = normal.session.state.units_of(PLAYER)[0]
	var walk: Array[Vector2i] = _longest_walk(normal.session, unit_id)
	var wait: UnitTurnCommand = UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.WAIT, "", walk
	)
	var problem: String = wait.validate(normal.session)
	_submit(normal, wait)
	_submit(fast, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", walk))
	fast.view.set_fast_forward(true)
	var normal_frames: int = _frames_to_settle(normal.view)
	var fast_frames: int = _frames_to_settle(fast.view)
	var speed: float = fast.view.fast_forward_speed
	_check.call(case_name, (
			problem.is_empty()
			and walk.size() >= 3
			and normal_frames >= 4
			and fast_frames > 0
			and fast_frames < normal_frames
			and fast_frames <= ceili(float(normal_frames) / speed) + 1
	), "%d tiles: %d frames, %d held at %sx; %s" % [
		walk.size(), normal_frames, fast_frames, speed, problem,
	])
	_check.call("fast-forward: both boards end as the state says, the game speed unchanged", (
			normal.view.mismatches().is_empty()
			and fast.view.mismatches().is_empty()
			and is_equal_approx(fast.session.playback.speed, fast.view.playback_speed)
			and not fast.session.playback.is_fast_forward
	), "; ".join(normal.view.mismatches() + fast.view.mismatches()))
	fast.view.set_fast_forward(false)
	_check.call("fast-forward: released, it is off", not fast.view.is_fast_forward())
	normal.close()
	fast.close()


# The first enemy phase, skipped on one board and played out on its twin: the skip starts only
# while playback runs, everything queued has played once the screen is black, and the board
# settles as the fade clears, long before the twin.
func _test_skip(map: CombatMapDefinition) -> void:
	var skipped: Board = _started_board(map, "skip: the M1 battle begins")
	var twin: Board = _started_board(map, "skip: the twin M1 battle begins")
	if skipped == null or twin == null:
		for board: Board in [skipped, twin]:
			if board != null:
				board.close()
		return
	var idle_skip: bool = skipped.view.skip_playback()
	_submit(skipped, EndTurnCommand.new(0))
	_submit(twin, EndTurnCommand.new(0))
	var playback: FactPlayback = skipped.session.playback
	var queued: int = playback.pending()
	var started: bool = skipped.view.skip_playback()
	var again: bool = skipped.view.skip_playback()
	var watch: SkipWatch = _watch_skip(skipped)
	var twin_frames: int = _frames_to_settle(twin.view)
	var fade: SkipFade = skipped.view.get_skip_fade()
	var fade_frames: int = ceili((fade.fade_out_time + fade.fade_in_time) / FRAME)

	_check.call("skip: it starts only while playback runs, and once at a time", (
			not idle_skip and queued > 0 and started and not again
	), "idle %s, %d queued, started %s, again %s" % [idle_skip, queued, started, again])
	_check.call("skip: once the screen is black, everything queued has played", (
			watch.black_frame > 0 and watch.pending_at_black == 0
	), "black at frame %d, %d left" % [watch.black_frame, watch.pending_at_black])
	_check.call("skip: the board settles as the fade clears, long before the unskipped twin", (
			watch.settle_frame > 0
			and watch.settle_frame == watch.end_frame
			and watch.settle_frame <= fade_frames + 2
			and twin_frames > watch.settle_frame
			and fade.get_opacity() == 0.0
			and not playback.is_fast_forward
			and not playback.is_paused
	), "settled at frame %d (fades %d), twin %d" % [
		watch.settle_frame, fade_frames, twin_frames,
	])
	_check.call("skip: afterwards the board agrees with the state", (
			skipped.view.mismatches().is_empty() and twin.view.mismatches().is_empty()
	), "; ".join(skipped.view.mismatches()))
	skipped.close()
	twin.close()


# A skip with the pause hook marking every move: at black it has stopped before the first move
# still queued; when the fade clears, playback resumes and plays the rest at normal speed.
func _test_skip_stops(map: CombatMapDefinition) -> void:
	var board: Board = _started_board(map, "skip: the M1 battle begins for the pause hook")
	if board == null:
		return
	var playback: FactPlayback = board.session.playback
	var stops: Array[CombatFact] = []
	var on_paused: Callable = func(fact: CombatFact) -> void:
		stops.append(fact)
	playback.paused_before.connect(on_paused)
	playback.pause_hook = func(fact: CombatFact) -> bool:
		return fact.kind == CombatFact.Kind.UNIT_MOVED
	_submit(board, EndTurnCommand.new(0))
	var started: bool = board.view.skip_playback()
	var watch: SkipWatch = _watch_skip(board)
	playback.paused_before.disconnect(on_paused)
	_check.call("skip: a fact the pause hook marks stops it, and plays after the fade clears", (
			started
			and stops.size() == 1
			and watch.black_frame > 0
			and watch.paused_at_black
			and watch.pending_at_black > 0
			and watch.end_frame > 0
			and not watch.paused_at_end
			and watch.pending_at_end > 0
			and watch.settle_frame > watch.end_frame
			and board.view.mismatches().is_empty()
	), "%d stops; black %d (paused %s, %d left); ended %d (paused %s, %d left); settled %d" % [
		stops.size(), watch.black_frame, watch.paused_at_black, watch.pending_at_black,
		watch.end_frame, watch.paused_at_end, watch.pending_at_end, watch.settle_frame,
	])
	board.close()


# A new M1 battle drawn on a board, past its opening Start; null, with the problem reported as
# case_name, when it can't begin.
func _started_board(map: CombatMapDefinition, case_name: String) -> Board:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call(case_name, false, "begin_battle gave no battle")
		run.close()
		return null
	var board: Board = Board.new()
	board.run = run
	board.battle = battle
	board.session = battle.get_session(0)
	board.view = VIEW_SCENE.instantiate()
	_root.add_child(board.view)
	board.view.bind(board.session)
	if board.session.state.map.opening_swap_open:
		_submit(board, StartCommand.new(0))
		settle(board.view)
	return board


func _submit(board: Board, command: Command) -> void:
	board.battle.submit(command, board.session.session_id)
	board.battle.resolve_queued()


# The frames view takes to settle, stepped as the game steps it; -1 when it never does.
static func _frames_to_settle(view: BattleView) -> int:
	for frame: int in MAX_SETTLE_FRAMES:
		if view.is_settled():
			return frame
		view.advance(FRAME)
	return MAX_SETTLE_FRAMES if view.is_settled() else -1


# Steps the board until it settles, noting the frame the skip's fade turned black and the frame
# the skip ended, and what playback held at each.
func _watch_skip(board: Board) -> SkipWatch:
	var watch: SkipWatch = SkipWatch.new()
	var fade: SkipFade = board.view.get_skip_fade()
	var playback: FactPlayback = board.session.playback
	for frame: int in range(1, MAX_SETTLE_FRAMES + 1):
		board.view.advance(FRAME)
		if watch.black_frame < 0 and fade.get_opacity() >= 1.0:
			watch.black_frame = frame
			watch.pending_at_black = playback.pending()
			watch.paused_at_black = playback.is_paused
		if watch.end_frame < 0 and not board.view.is_skipping():
			watch.end_frame = frame
			watch.pending_at_end = playback.pending()
			watch.paused_at_end = playback.is_paused
		if board.view.is_settled():
			watch.settle_frame = frame
			break
	return watch


# The longest of unit_id's walks to the tiles it can reach, the first found in row-major order.
func _longest_walk(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var reach: Dictionary[Vector2i, int] = Pathing.reach(session.engine, session.state, unit_id)
	var ends: Array[Vector2i] = []
	ends.assign(reach.keys())
	ends.sort_custom(MapLayout.is_before)
	var longest: Array[Vector2i] = []
	for tile: Vector2i in ends:
		var walk: Array[Vector2i] = _walk_to(session, unit_id, tile)
		if walk.size() > longest.size():
			longest = walk
	return longest


func _new_run() -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))


# The driver (class doc), checking the board against the state each time it settles.
func _play(battle: CombatEncounter, session: CombatSession, view: BattleView) -> Played:
	var result: Played = Played.new()
	var state: CombatState = session.state
	if state.map.opening_swap_open:
		_send(battle, session, view, StartCommand.new(0), result)
	for _phase: int in MAX_PHASES:
		if session.is_finished:
			break
		for unit_id: String in state.units_of(PLAYER):
			if session.is_finished:
				break
			if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
				continue
			_send(battle, session, view, _turn_for(session, unit_id), result)
		if not session.is_finished:
			_send(battle, session, view, EndTurnCommand.new(0), result)
	return result


func _send(
		battle: CombatEncounter,
		session: CombatSession,
		view: BattleView,
		command: Command,
		result: Played
) -> void:
	battle.submit(command, session.session_id)
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		if batch.is_rejected():
			result.rejected.append("%s: %s" % [batch.label, batch.rejected_reason])
	if not settle(view):
		result.stalls.append(command.get_label())
		return
	var found: PackedStringArray = view.mismatches()
	if not found.is_empty():
		result.disagreements.append("after %s: %s" % [command.get_label(), ", ".join(found)])


# The driver's turn for unit_id (class doc).
func _turn_for(session: CombatSession, unit_id: String) -> UnitTurnCommand:
	var state: CombatState = session.state
	var reach: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var ends: Array[Vector2i] = []
	ends.assign(reach.keys())
	ends.sort_custom(MapLayout.is_before)
	var foes: PackedStringArray = state.units_of(ENEMY)
	for tile: Vector2i in ends:
		for foe: String in foes:
			var walk: Array[Vector2i] = _walk_to(session, unit_id, tile)
			var attack: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, UnitTurnCommand.Action.ATTACK, foe, walk
			)
			if attack.validate(session).is_empty():
				return attack
	var goal: Vector2i = state.tile_of(unit_id)
	var nearest: int = -1
	for tile: Vector2i in ends:
		for foe: String in foes:
			var distance: int = state.grid.distance(tile, state.tile_of(foe))
			if nearest < 0 or distance < nearest:
				nearest = distance
				goal = tile
	return UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.WAIT, "", _walk_to(session, unit_id, goal)
	)


# A cheapest walk from unit_id's tile to tile (one of its reach), stepping back from tile through
# the flood's costs; empty for its own tile or when none is found.
static func _walk_to(session: CombatSession, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = session.state
	var mover: CombatUnitState = state.unit(unit_id)
	var walk: Array[Vector2i] = []
	if tile == mover.tile:
		return walk
	var costs: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	walk.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var before: Vector2i = CombatFact.NO_TILE
		for next: Vector2i in state.grid.neighbors(at):
			if costs.has(next) and costs[next] + entry == costs[at]:
				before = next
				break
		if before == CombatFact.NO_TILE:
			walk.clear()
			return walk
		walk.push_front(before)
		at = before
	return walk


## What one driven battle left to report.
class Played:
	extends RefCounted

	## Commands the session rejected, one line each.
	var rejected: PackedStringArray = []
	## Commands after which the board never settled.
	var stalls: PackedStringArray = []
	## Each settle at which the board disagreed with the state.
	var disagreements: PackedStringArray = []


## One M1 battle and the board drawing its map.
class Board:
	extends RefCounted

	## The run the battle belongs to.
	var run: CampaignSession = null
	## The battle.
	var battle: CombatEncounter = null
	## Its one map's session.
	var session: CombatSession = null
	## The board drawing it, in the tree.
	var view: BattleView = null

	## Frees the board and closes the run.
	func close() -> void:
		view.free()
		run.close()


## When a watched skip turned black, ended and settled, and what playback held then. Frames count
## from 1; -1 for a moment that never came.
class SkipWatch:
	extends RefCounted

	## The frame the fade turned fully black.
	var black_frame: int = -1
	## Facts still queued at that frame.
	var pending_at_black: int = -1
	## Whether playback was paused at that frame.
	var paused_at_black: bool = false
	## The frame the skip ended (its fade cleared).
	var end_frame: int = -1
	## Facts still queued at that frame.
	var pending_at_end: int = -1
	## Whether playback was paused at that frame.
	var paused_at_end: bool = false
	## The frame the board settled.
	var settle_frame: int = -1
