# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_feedback_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Combat feedback's cases for the ui/board suite (P15 UL6, ui-lift.md): each strike result's
## [StrikeFeedback] look fires on its fact and only when that fact plays, a strike holding the
## next back for its beat; the floating numbers of a multi-hit attack (one per strike), of a
## splash on two units, and of a hit that breaks Stance, stacked a row apart; skip and held
## fast-forward leaving the board as the state stands and its tokens at rest; the phase banner
## below the heirloom bar's row at any icon count and size; the elite mark and the side shape on
## the right tokens; and the event log's thrown-keg lines. Strike facts are built as
## ExchangeResolver.attack and DamagePipeline.apply record them. No autoload is named or needed.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/battle/hud/battle_hud.tscn")
const BANNER_SCENE: PackedScene = preload("res://ui/battle/hud/phase_banner.tscn")

# The other UI cases' seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# One frame at 30 fps, as BattleViewCases steps boards.
const FRAME: float = 1.0 / 30.0

# End Turns the skip and fast-forward case may send to see strikes play.
const MAX_PHASES: int = 6

# Heirloom icon counts and screen sizes (base units) the banner case lays out.
const ICON_COUNTS: Array[int] = [6, 12, 24]
const SCREEN_SIZES: Array[Vector2] = [Vector2(1280.0, 720.0), Vector2(1280.0, 800.0)]

# A strike's beat short enough for the stacking cases to show strikes' numbers side by side.
const SHORT_HOLD: float = 0.05

# A small hit, so no synthetic strike defeats an M1 unit.
const SMALL_HIT: int = 2

# Any prefix id: the elite case marks an enemy by its prefix alone.
const PREFIX_ID: String = "test:prefix"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

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
		_check.call("feedback: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_kinds()
	_test_only_when_played()
	_test_beat_ends_with_batch()
	_test_multi_hit()
	_test_splash()
	_test_stance_break_stack()
	_test_skip_and_fast_forward()
	_test_banner_place()
	_test_elite_and_sides()
	_test_keg_lines()


# Each result's facts, played alone: exactly its kinds fire, on the struck unit (the dodger for a
# miss), and a crit or Block taking a hit whole plays no plain hit's look.
func _test_kinds() -> void:
	var board: BattleViewCases.Board = _board("kinds: the M1 battle begins")
	if board == null:
		return
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	var block_hit: CombatFact = _damage(d, a, SMALL_HIT, 0, SMALL_HIT)
	var cases: Array[Array] = [
		["hit", _strike(a, d, SMALL_HIT, false), [StrikeFeedback.Kind.HIT]],
		["miss", _miss(a, d), [StrikeFeedback.Kind.MISS]],
		["crit", _strike(a, d, SMALL_HIT, true), [StrikeFeedback.Kind.CRIT]],
		["no damage", [_fact(CombatFact.Kind.HIT_TAKEN, d, a, 0)], [StrikeFeedback.Kind.NO_DAMAGE]],
		["Block absorbed", [_fact(CombatFact.Kind.HIT_TAKEN, d, a, SMALL_HIT), block_hit], [
			StrikeFeedback.Kind.BLOCK_ABSORBED,
		]],
		["Stance lost", [_fact(CombatFact.Kind.STANCE_CHANGED, d, a, -1)], [
			StrikeFeedback.Kind.STANCE_LOST,
		]],
		["Stance broken", [_fact(CombatFact.Kind.EXPOSED, d, a)], [
			StrikeFeedback.Kind.STANCE_BROKEN,
		]],
		["splash", [_splash(d, a, SMALL_HIT)], [StrikeFeedback.Kind.SPLASH]],
	]
	var fired: Array[Array] = []
	var on_played: Callable = func(unit_id: String, kind: StrikeFeedback.Kind) -> void:
		fired.append([unit_id, kind])
	board.view.feedback_played.connect(on_played)
	for case: Array in cases:
		fired.clear()
		var given: Array = case[1]
		var kinds: Array = case[2]
		var facts: Array[CombatFact] = []
		facts.assign(given)
		board.session.playback.enqueue(facts)
		var before: int = fired.size()
		BattleViewCases.settle(board.view)
		var expected: Array[Array] = []
		for kind: StrikeFeedback.Kind in kinds:
			expected.append([d, kind])
		_check.call("kinds: %s fires its look on its fact, and nothing else" % [case[0]], (
				before == 0 and str(fired) == str(expected)
		), "%s, expected %s (%d before playing)" % [fired, expected, before])
	board.view.feedback_played.disconnect(on_played)
	board.close()


# A miss, then a hit, then the exchange's end: the hit's look waits out the miss's beat
# (miss_hold), and the hit's beat (strike_hold) then holds the end back. A fact's wait delays only
# the fact after it, so the end stands for whatever follows a strike.
func _test_only_when_played() -> void:
	var board: BattleViewCases.Board = _board("only when played: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	var fired: Array[int] = []
	var on_played: Callable = func(_unit_id: String, kind: StrikeFeedback.Kind) -> void:
		fired.append(kind)
	view.feedback_played.connect(on_played)
	var facts: Array[CombatFact] = _miss(a, d)
	facts.append_array(_strike(a, d, SMALL_HIT, false))
	# DamagePipeline.apply's Stance loss on a unit left standing, and its Exposed at 0.
	facts.append(_fact(CombatFact.Kind.STANCE_CHANGED, d, a, -1))
	if view.token_of(d).stance == 1:
		facts.append(_fact(CombatFact.Kind.EXPOSED, d, a))
	facts.append(_fact(CombatFact.Kind.AFTER_COMBAT, a, d))
	board.session.playback.enqueue(facts)
	view.advance(0.0)
	var at_start: Array[int] = fired.duplicate()
	var miss_frames: int = ceili(view.miss_hold / FRAME) - 2
	for _frame: int in miss_frames:
		view.advance(FRAME)
	var in_miss_beat: Array[int] = fired.duplicate()
	for _frame: int in 4:
		view.advance(FRAME)
	var after_miss: Array[int] = fired.duplicate()
	var held: bool = board.session.playback.pending() == 1
	BattleViewCases.settle(view)
	view.feedback_played.disconnect(on_played)
	var miss_then_hit: Array[int] = [StrikeFeedback.Kind.MISS, StrikeFeedback.Kind.HIT]
	_check.call("only when played: the hit's look waits out the miss's beat, then plays", (
			at_start == [StrikeFeedback.Kind.MISS] and in_miss_beat == [StrikeFeedback.Kind.MISS]
			and after_miss.slice(0, 2) == miss_then_hit and held
	), "start %s, in the beat %s, after %s, held %s" % [at_start, in_miss_beat, after_miss, held])
	_check.call("only when played: the beats are Godot_FE's, 1.0 s a hit and 0.75 s a miss", (
			is_equal_approx(view.strike_hold, 1.0) and is_equal_approx(view.miss_hold, 0.75)
	), "strike %.2f, miss %.2f" % [view.strike_hold, view.miss_hold])
	board.close()


# A batch ending on a strike (its beat waiting for a Stance fact that never comes) leaves nothing
# waiting: the next batch's strike plays as soon as it is queued, not a beat after its first fact.
func _test_beat_ends_with_batch() -> void:
	var board: BattleViewCases.Board = _board("beat at a batch's end: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	board.session.playback.enqueue(_strike(a, d, SMALL_HIT, false))
	BattleViewCases.settle(view)
	var fired: Array[int] = []
	var on_played: Callable = func(_unit_id: String, kind: StrikeFeedback.Kind) -> void:
		fired.append(kind)
	view.feedback_played.connect(on_played)
	board.session.playback.enqueue(_strike(a, d, SMALL_HIT, false))
	view.advance(0.0)
	view.feedback_played.disconnect(on_played)
	BattleViewCases.settle(view)
	_check.call("beat at a batch's end: the next batch's strike plays at once", (
			fired == [StrikeFeedback.Kind.HIT]
	), str(fired))
	board.close()


# An AtkX 3 attack's three strikes: three damage numbers on the target, one per strike, each
# shown as its strike plays; with a short beat they stand on three rows at once.
func _test_multi_hit() -> void:
	var board: BattleViewCases.Board = _board("multi-hit: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	_clear_popups(view)
	view.strike_hold = SHORT_HOLD
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	var shown: Array[Array] = []
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		shown.append([unit_id, style])
	view.number_shown.connect(on_shown)
	var facts: Array[CombatFact] = []
	for _strike_index: int in 3:
		facts.append_array(_strike(a, d, 1, false))
	board.session.playback.enqueue(facts)
	BattleViewCases.settle(view)
	view.number_shown.disconnect(on_shown)
	var damage: Array[Array] = []
	for _strike_index: int in 3:
		damage.append([d, DamageNumber.Style.DAMAGE])
	var rows: PackedStringArray = _stack_problems(view, d, 3)
	_check.call("multi-hit: each strike of an AtkX 3 attack shows its own number", (
			str(shown) == str(damage)
	), str(shown))
	_check.call("multi-hit: the three numbers stand a row apart, none on another", (
			rows.is_empty()
	), "; ".join(rows))
	board.close()


# One splash on two units (no roll, no Hit taken), one into Block: each shows its number, the
# Block one its Block number beside it, each plays the splash look, and Block absorbing too.
func _test_splash() -> void:
	var board: BattleViewCases.Board = _board("splash: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var a: String = board.session.state.units_of(PLAYER)[0]
	var enemies: PackedStringArray = board.session.state.units_of(ENEMY)
	if enemies.size() < 2:
		_check.call("splash: the M1 battle has two enemies", false, str(enemies))
		board.close()
		return
	var shown: Array[Array] = []
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		shown.append([unit_id, style])
	var fired: Array[Array] = []
	var on_played: Callable = func(unit_id: String, kind: StrikeFeedback.Kind) -> void:
		fired.append([unit_id, kind])
	view.number_shown.connect(on_shown)
	view.feedback_played.connect(on_played)
	var into_block: CombatFact = _splash(enemies[1], a, SMALL_HIT)
	into_block.hp_amount = 1
	into_block.block_amount = SMALL_HIT - 1
	board.session.playback.enqueue([_splash(enemies[0], a, SMALL_HIT), into_block])
	BattleViewCases.settle(view)
	view.number_shown.disconnect(on_shown)
	view.feedback_played.disconnect(on_played)
	var expected_shown: Array[Array] = [
		[enemies[0], DamageNumber.Style.DAMAGE],
		[enemies[1], DamageNumber.Style.DAMAGE],
		[enemies[1], DamageNumber.Style.BLOCK],
	]
	var expected_fired: Array[Array] = [
		[enemies[0], StrikeFeedback.Kind.SPLASH],
		[enemies[1], StrikeFeedback.Kind.SPLASH],
		[enemies[1], StrikeFeedback.Kind.BLOCK_ABSORBED],
	]
	_check.call("splash: each unit it reaches shows its number, Block's beside its own", (
			str(shown) == str(expected_shown)
	), str(shown))
	_check.call("splash: each plays the splash look, and Block absorbing where it took some", (
			str(fired) == str(expected_fired)
	), str(fired))
	board.close()


# A hit that takes the last of a unit's Stance: its damage, "Stance −1" and "Exposed" show at
# once a row apart, and the strike's beat holds the exchange's end after the Exposed, not the
# words before it, for strike_hold.
func _test_stance_break_stack() -> void:
	var board: BattleViewCases.Board = _board("Stance break: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	_clear_popups(view)
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	var token: UnitToken = view.token_of(d)
	var to_zero: int = -token.stance
	var facts: Array[CombatFact] = _strike(a, d, SMALL_HIT, false)
	facts.append(_fact(CombatFact.Kind.STANCE_CHANGED, d, a, to_zero))
	facts.append(_fact(CombatFact.Kind.EXPOSED, d, a))
	facts.append(_fact(CombatFact.Kind.AFTER_COMBAT, a, d))
	var shown: Array[int] = []
	var on_shown: Callable = func(_unit_id: String, style: DamageNumber.Style) -> void:
		shown.append(style)
	view.number_shown.connect(on_shown)
	board.session.playback.enqueue(facts)
	view.advance(0.0)
	var words_first: Array[int] = shown.duplicate()
	var rows: PackedStringArray = _stack_problems(view, d, 3)
	for _frame: int in ceili(view.strike_hold / FRAME) - 2:
		view.advance(FRAME)
	var held: bool = board.session.playback.pending() == 1
	BattleViewCases.settle(view)
	view.number_shown.disconnect(on_shown)
	var expected: Array[int] = [
		DamageNumber.Style.DAMAGE, DamageNumber.Style.STANCE, DamageNumber.Style.EXPOSED,
	]
	_check.call("Stance break: damage, Stance and Exposed show together, the beat after them", (
			words_first == expected and held and to_zero < 0
	), "%s at once, held after the last %s (Stance change %d)" % [words_first, held, to_zero])
	_check.call("Stance break: the three pop-ups stand a row apart", rows.is_empty(), (
			"; ".join(rows)
	))
	board.close()


# Twin boards from one seed, sent the same End Turns until strikes have played: a skipped board
# and a fast-forward board each settle agreeing with the state, the skipped one with every token
# at rest (no pop, no flash) and no pop-up left, and fast-forward in fewer frames than normal.
func _test_skip_and_fast_forward() -> void:
	var normal: BattleViewCases.Board = _board("skip and fast-forward: the M1 battle begins")
	var skipped: BattleViewCases.Board = _board("skip and fast-forward: a twin begins")
	var fast: BattleViewCases.Board = _board("skip and fast-forward: a third twin begins")
	if normal == null or skipped == null or fast == null:
		for board: BattleViewCases.Board in [normal, skipped, fast]:
			if board != null:
				board.close()
		return
	var strikes: Array[int] = [0]
	var on_played: Callable = func(_unit_id: String, _kind: StrikeFeedback.Kind) -> void:
		strikes[0] += 1
	normal.view.feedback_played.connect(on_played)
	var problems: PackedStringArray = []
	var frames: Array[int] = [0, 0]
	var did_skip: bool = false
	for _phase: int in MAX_PHASES:
		if normal.session.is_finished or strikes[0] > 0:
			break
		for board: BattleViewCases.Board in [normal, skipped, fast]:
			board.battle.submit(EndTurnCommand.new(0), board.session.session_id)
			board.battle.resolve_queued()
		frames[0] += _settle_counting(normal.view)
		did_skip = skipped.view.skip_playback() or did_skip
		BattleViewCases.settle(skipped.view)
		problems.append_array(_at_rest_problems(skipped.view))
		fast.view.set_fast_forward(true)
		frames[1] += _settle_counting(fast.view)
		fast.view.set_fast_forward(false)
		for board: BattleViewCases.Board in [normal, skipped, fast]:
			for line: String in board.view.mismatches():
				problems.append(line)
	normal.view.feedback_played.disconnect(on_played)
	_check.call("skip and fast-forward: strikes played, and each board agrees with the state", (
			strikes[0] > 0 and did_skip and problems.is_empty()
	), "%d results; %s" % [strikes[0], "; ".join(problems.slice(0, 4))])
	_check.call("skip and fast-forward: held fast-forward settles in fewer frames", (
			frames[1] > 0 and frames[1] < frames[0]
	), "normal %d frames, fast-forward %d" % [frames[0], frames[1]])
	for board: BattleViewCases.Board in [normal, skipped, fast]:
		board.close()


# The HUD at each size with 6, 12 and 24 heirlooms: the phase banner (each phase's and the end's)
# sits wholly below the bar's row, so however long the bar grows the two never meet; its fades
# are ui-style.md's 250 ms around a 1.5 s hold, and follow the board's pace.
func _test_banner_place() -> void:
	var problems: PackedStringArray = []
	for screen: Vector2 in SCREEN_SIZES:
		for count: int in ICON_COUNTS:
			var frame: Control = Control.new()
			frame.size = screen
			_root.add_child(frame)
			var hud: BattleHud = HUD_SCENE.instantiate()
			frame.add_child(hud)
			var bar: HeirloomBar = hud.get_heirloom_bar()
			bar.show_views(_heirloom_views(count))
			var banner: PhaseBanner = hud.get_phase_banner()
			for shown: int in 4:
				match shown:
					0:
						banner.show_phase(PLAYER, 3)
					1:
						banner.show_phase(ENEMY, 3)
					2:
						banner.show_darkness()
					3:
						banner.show_result(true)
				var bar_rect: Rect2 = Rect2(
						bar.get_global_position(), bar.get_combined_minimum_size()
				)
				var banner_rect: Rect2 = Rect2(
						banner.get_global_position(),
						banner.size.max(banner.get_combined_minimum_size())
				)
				var is_clear: bool = (
						bar_rect.size.x >= count * 8.0
						and banner_rect.position.y >= bar_rect.end.y
						and not banner_rect.intersects(bar_rect)
				)
				if not is_clear:
					problems.append("%s, %d icons, banner %d: bar %s, banner %s" % [
						screen, count, shown, bar_rect, banner_rect,
					])
			frame.free()
	_check.call("banner: below the heirloom bar's row at 6, 12 and 24 icons, every banner", (
			problems.is_empty()
	), "; ".join(problems.slice(0, 3)))
	var probe: PhaseBanner = BANNER_SCENE.instantiate()
	var timing: bool = (
			is_equal_approx(probe.fade_in_time, 0.25) and is_equal_approx(probe.hold_time, 1.5)
			and is_equal_approx(probe.fade_out_time, 0.25)
			and is_equal_approx(probe.phase_time(), 2.0)
	)
	probe.free()
	_check.call("banner: 0.25 s in, 1.5 s held, 0.25 s out: Godot_FE's 2.0 s", timing)


# An enemy given a prefix before the board is built: its token is marked elite and shows the
# mark; no other token does. Player tokens draw a circle, enemies a diamond, others nothing.
func _test_elite_and_sides() -> void:
	var board: BattleViewCases.Board = _board("elite and sides: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var state: CombatState = board.session.state
	var elite: String = state.units_of(ENEMY)[0]
	state.unit(elite).prefix_id = PREFIX_ID
	view.bind(board.session)
	var wrong_elites: PackedStringArray = []
	var wrong_shapes: PackedStringArray = []
	var players: int = 0
	var enemies: int = 0
	for unit_id: String in view.token_ids():
		var token: UnitToken = view.token_of(unit_id)
		var mark: EliteMark = token.info.get_elite_mark()
		var shape: SideShape.Shape = token.info.get_side_shape().shape
		var is_elite: bool = unit_id == elite
		if token.is_elite != is_elite or mark.is_shown() != is_elite:
			wrong_elites.append("%s elite %s, mark %s" % [
				unit_id, token.is_elite, mark.is_shown(),
			])
		var side: CombatFact.CombatSide = state.side_of(unit_id)
		if shape != SideShape.shape_of(side):
			wrong_shapes.append("%s (side %d) draws shape %d" % [unit_id, side, shape])
		players += 1 if side == PLAYER and shape == SideShape.Shape.CIRCLE else 0
		enemies += 1 if side == ENEMY and shape == SideShape.Shape.DIAMOND else 0
	_check.call("elite and sides: only the prefixed enemy is marked elite", (
			view.token_of(elite).is_elite and wrong_elites.is_empty()
	), "; ".join(wrong_elites))
	_check.call("elite and sides: circles on player tokens, diamonds on enemies", (
			wrong_shapes.is_empty() and players > 0 and enemies > 0
	), "%d circles, %d diamonds; %s" % [players, enemies, "; ".join(wrong_shapes)])
	board.close()


# A thrown keg's landing, by its thrower and by no one, and its fuse burning down: each its own
# line, never the generic "changes".
func _test_keg_lines() -> void:
	var board: BattleViewCases.Board = _board("keg lines: the M1 battle begins")
	if board == null:
		return
	var session: CombatSession = board.session
	var thrower: String = session.state.units_of(ENEMY)[0]
	var keg: String = "test:keg"
	var tile: Vector2i = Vector2i(0, 7)
	var writer: EventLogWriter = EventLogWriter.new(session)
	var keg_name: String = BattleText.name_of(session, keg)
	var by_name: String = BattleText.name_of(session, thrower)
	var landed: CombatFact = _object_fact(keg, thrower, MapObjects.Change.LANDED, tile, 0)
	var dropped: CombatFact = _object_fact(keg, "", MapObjects.Change.LANDED, tile, 0)
	var burned: CombatFact = _object_fact(keg, "", MapObjects.Change.FUSE_BURNED, tile, 1)
	var texts: PackedStringArray = []
	for fact: CombatFact in [landed, dropped, burned]:
		for entry: EventLogWriter.Entry in writer.write(fact):
			texts.append(entry.text())
	var expected: PackedStringArray = [
		"%s throws %s: it lands at (0, 7), lit" % [by_name, keg_name],
		"%s lands at (0, 7), lit" % [keg_name],
		"%s's fuse burns down (1 left)" % [keg_name],
	]
	_check.call("keg lines: a thrown keg lands, lit, and its fuse burns down, by name", (
			texts == expected
	), "%s, expected %s" % [texts, expected])
	board.close()


# --- Fixtures --------------------------------------------------------------------------------


# The M1 battle on a board in the tree, past Start; null, with the problem reported, when it
# can't begin.
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


# Each live pop-up on unit_id should stand on its own row, rows popup_row_height apart on screen,
# none reaching past the screen's top (popup_reach);
# returns what's wrong, empty when expected pop-ups do.
func _stack_problems(view: BattleView, unit_id: String, expected: int) -> PackedStringArray:
	var layer: UnitInfoLayer = view.get_info_layer()
	var problems: PackedStringArray = []
	var ys: Array[float] = []
	var rows: Array[int] = []
	var point: Vector2 = view.token_of(unit_id).global_position
	for popup: Node2D in layer.get_popups():
		var number: DamageNumber = popup as DamageNumber
		if number == null or number.style == DamageNumber.Style.BLOCK:
			continue
		ys.append(popup.position.y)
		rows.append(layer.popup_row_of(popup))
	if ys.size() != expected:
		problems.append("%d pop-ups live over %s, expected %d" % [ys.size(), point, expected])
		return problems
	var gap: float = layer.popup_row_height * layer.info_scale()
	var reach: float = layer.popup_reach * layer.info_scale()
	for y: float in ys:
		if y - reach < -0.5:
			problems.append("a pop-up at y %.1f reaches past the screen's top" % [y])
	for i: int in ys.size():
		for j: int in range(i + 1, ys.size()):
			if rows[i] == rows[j] or absf(ys[i] - ys[j]) < gap - 0.5:
				problems.append("rows %d and %d at y %.1f and %.1f" % [
					rows[i], rows[j], ys[i], ys[j],
				])
	return problems


# Steps view a frame at a time until no pop-up is left on its info layer, such as the Drengr's
# Vanguard Block from the opening Phase Start, which the stacking cases would count with their own.
static func _clear_popups(view: BattleView) -> void:
	var layer: UnitInfoLayer = view.get_info_layer()
	for _frame: int in BattleViewCases.MAX_SETTLE_FRAMES:
		if layer.get_popups().is_empty():
			return
		view.advance(FRAME)


# Settles view a frame at a time; returns the frames it took.
static func _settle_counting(view: BattleView) -> int:
	var frames: int = 0
	while not view.is_settled() and frames < BattleViewCases.MAX_SETTLE_FRAMES:
		view.advance(FRAME)
		frames += 1
	return frames


# Every token at rest and no pop-up left, as a skip leaves the board.
static func _at_rest_problems(view: BattleView) -> PackedStringArray:
	var problems: PackedStringArray = []
	for unit_id: String in view.token_ids():
		var token: UnitToken = view.token_of(unit_id)
		if not token.scale.is_equal_approx(Vector2.ONE) or token.flash_amount > 0.0:
			problems.append("%s scale %s, flash %.2f" % [unit_id, token.scale, token.flash_amount])
	var left: int = view.get_info_layer().get_popups().size()
	if left > 0:
		problems.append("%d pop-ups left after the skip" % [left])
	return problems


# count heirloom copies with names only, as the bar draws a view with no icon (its generic mark).
static func _heirloom_views(count: int) -> Array[HeirloomViewModel]:
	var views: Array[HeirloomViewModel] = []
	for index: int in count:
		var view: HeirloomViewModel = HeirloomViewModel.new()
		view.heirloom_id = "test:heirloom_%d" % [index]
		view.display_name = "Heirloom %d" % [index]
		view.tier = "common"
		views.append(view)
	return views


static func _fact(
		kind: CombatFact.Kind, actor: String, target: String = "", amount: int = 0,
) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor, target)
	fact.amount = amount
	return fact


# A strike's facts as ExchangeResolver.attack and DamagePipeline.apply record them, all to HP.
static func _strike(a: String, d: String, damage: int, is_crit: bool) -> Array[CombatFact]:
	var facts: Array[CombatFact] = [
		_fact(CombatFact.Kind.ATTACK_MADE, a, d),
		_fact(CombatFact.Kind.HIT_DEALT, a, d, damage),
		_fact(CombatFact.Kind.HIT_TAKEN, d, a, damage),
	]
	if is_crit:
		facts.append(_fact(CombatFact.Kind.CRIT_DEALT, a, d, damage))
		facts.append(_fact(CombatFact.Kind.CRIT_TAKEN, d, a, damage))
	facts.append(_fact(CombatFact.Kind.DAMAGE_DEALT, a, d, damage))
	facts.append(_damage(d, a, damage, damage, 0))
	return facts


static func _miss(a: String, d: String) -> Array[CombatFact]:
	var facts: Array[CombatFact] = [
		_fact(CombatFact.Kind.ATTACK_MADE, a, d),
		_fact(CombatFact.Kind.MISSED, a, d),
		_fact(CombatFact.Kind.DODGED, d, a),
	]
	return facts


static func _damage(d: String, a: String, amount: int, to_hp: int, absorbed: int) -> CombatFact:
	var fact: CombatFact = _fact(CombatFact.Kind.DAMAGE_TAKEN, d, a, amount)
	fact.hp_amount = to_hp
	fact.block_amount = absorbed
	fact.source = CombatFact.Source.ATTACK
	return fact


# Splash as SplashResolver records it: a Damage taken with no Hit taken before it.
static func _splash(d: String, source: String, amount: int) -> CombatFact:
	var fact: CombatFact = _damage(d, source, amount, amount, 0)
	fact.source = CombatFact.Source.SPLASH
	return fact


static func _object_fact(
		object_id: String, by: String, change: MapObjects.Change, tile: Vector2i, amount: int,
) -> CombatFact:
	var fact: CombatFact = _fact(CombatFact.Kind.OBJECT_STATE_CHANGED, object_id, by, amount)
	fact.key = change
	fact.tile = tile
	return fact
