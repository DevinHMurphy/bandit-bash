# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_info_cases.gd
# Author:
# Created:  November 6, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The unit display's second round for the ui/board suite (combat UI plan, UI7F row; question
## 29): the HP number and bar after hits and heals; Stance pips equal to Stance, with the overflow
## colour above the maximum, the Exposed look at 0, a drop's lag and the tick fallback; the
## forecast dimming the pips its exchange would break; each unit's info staying on its token as the
## camera moves; and a Miss for every missed strike and a Critical for every crit, once each, in
## normal playback, held fast-forward and the faded skip; Haunted's Block ban on the token and
## the unit panel (UI12). No autoload is named or needed.
##
## [b]The battle driver[/b] is unit_display_cases.gd's: each acting unit takes a Staff, else an
## Attack on its first target, from its first move tile that offers one, else waits; then End
## Turn. The same seed and commands give the same facts on every board, whatever its playback mode.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PIPS_SCENE: PackedScene = preload("res://ui/battle/unit/stance_pips.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://ui/battle/forecast/forecast_panel.tscn")
const UNIT_PANEL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_panel.tscn")

# A fixed seed whose driven M1 battle has a missed strike, which the pop-up cases need; no case
# compares golden numbers. Retuned units can change that, so pick another seed if one goes missing.
const SEED: int = 0x0C0FFEF

# Player phases a battle may take: past what the M1 battle needs, so only a stall reaches it.
const MAX_PHASES: int = 40

# One frame at 30 fps, as BattleViewCases steps boards.
const FRAME: float = 1.0 / 30.0

# Frames stepped after a camera change: past the longest pan and shake.
const CAMERA_FRAMES: int = 30

# How far an info may sit from where the camera draws its token: rounding only.
const PLACE_TOLERANCE: float = 0.5

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const STAFF: TurnInputModel.ActionKind = TurnInputModel.ActionKind.STAFF
const MISS: DamageNumber.Style = DamageNumber.Style.MISS
const CRITICAL: DamageNumber.Style = DamageNumber.Style.CRITICAL

## How a driven battle's board plays its facts.
enum Mode {
	NORMAL = 0,
	FAST_FORWARD = 1,
	SKIP = 2,
}

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
		_check.call("unit info: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_hp_number()
	_test_pips()
	_test_tick_fallback()
	_test_forecast_dims()
	_test_follows_camera()
	_test_popups_synthetic()
	_test_popups_by_mode()
	_test_block_ban()


# Haunted on seat 0 (UI12): after each of two enemy phases, the units whose tokens show the Block
# ban are exactly those the session denies CAN_GAIN_BLOCK, one at a time (the last ban expired at
# the enemy phase's end, as its facts played), and the unit panel names it for that unit only.
func _test_block_ban() -> void:
	var h: TurnInputCases.Harness = _harness("block ban: the M1 battle begins")
	if h == null:
		return
	for instance: EffectInstance in Loadout.heirloom_effects(_catalog, "haunted", 0, h.session.ids):
		h.session.engine.register(instance)
	var panel: UnitPanel = UNIT_PANEL_SCENE.instantiate()
	h.hud.add_child(panel)
	var rounds: PackedStringArray = []
	var problems: PackedStringArray = []
	for round_index: int in 2:
		_wait_phase(h)
		if h.session.is_finished:
			break
		var banned: PackedStringArray = []
		for unit_id: String in h.session.state.units_of(PLAYER):
			var denied: bool = not h.session.stats(unit_id).is_allowed(
					CombatValue.Permission.CAN_GAIN_BLOCK
			)
			var token: UnitToken = h.view.token_of(unit_id)
			if token.is_block_banned != denied or token.info.is_block_ban_shown() != denied:
				problems.append("round %d %s: denied %s, token %s, mark %s" % [
					round_index, unit_id, denied, token.is_block_banned,
					token.info.is_block_ban_shown(),
				])
			panel.show_unit(HudViewModel.unit_view(h.session, unit_id))
			if panel.get_texts()[3].ends_with(panel.block_ban_text) != denied:
				problems.append("round %d %s: panel '%s'" % [
					round_index, unit_id, panel.get_texts()[3],
				])
			if denied:
				banned.append(unit_id)
		if banned.size() != 1:
			problems.append("round %d: %d units banned" % [round_index, banned.size()])
		rounds.append(" ".join(banned))
	_check.call("block ban: the token's mark and the panel follow the session's ban", (
			problems.is_empty() and rounds.size() == 2
	), "; ".join(problems) + " (banned: %s)" % [" | ".join(rounds)])
	panel.free()
	h.close()


# Every unit's HP bar and number match the session at the start ("HP/max", the bar's default);
# a hit and a heal played to one token move both by their amounts.
func _test_hp_number() -> void:
	var board: BattleViewCases.Board = _board("hp: the M1 battle begins")
	if board == null:
		return
	var state: CombatState = board.session.state
	var wrong: PackedStringArray = []
	for unit_id: String in state.unit_ids():
		var token: UnitToken = board.view.token_of(unit_id)
		var bar: HpBar = token.info.get_hp_bar()
		var hp: int = state.get_hp(unit_id)
		var expected: String = "%d/%d" % [hp, token.max_hp]
		if bar.get_text() != expected or roundi(bar.value) != hp:
			wrong.append("%s: %s (%d), has %d" % [unit_id, bar.get_text(), roundi(bar.value), hp])
	_check.call("hp: every unit's bar and number show its HP", wrong.is_empty(), "; ".join(wrong))

	var unit_id: String = state.units_of(PLAYER)[0]
	var token: UnitToken = board.view.token_of(unit_id)
	var bar: HpBar = token.info.get_hp_bar()
	var hp_before: int = token.hp
	var hit: CombatFact = _fact(CombatFact.Kind.DAMAGE_TAKEN, unit_id, 5)
	hit.hp_amount = 5
	_play(board, [hit])
	var after_hit: String = bar.get_text()
	var healed: CombatFact = _fact(CombatFact.Kind.HEALED, unit_id, 3)
	healed.hp_amount = 3
	_play(board, [healed])
	_check.call("hp: a hit and a heal move the bar and the number inside it", (
			after_hit == "%d/%d" % [hp_before - 5, token.max_hp]
			and bar.get_text() == "%d/%d" % [hp_before - 2, token.max_hp]
			and roundi(bar.value) == hp_before - 2
			and roundi(bar.max_value) == token.max_hp
	), "%d, hit %s, healed %s" % [hp_before, after_hit, bar.get_text()])
	board.close()


# Pips equal Stance; Triage above the maximum shows the overflow colour; a drop lags in the change
# colour, then a Stance of 0 shows the Exposed look; a refresh fills them again.
func _test_pips() -> void:
	var board: BattleViewCases.Board = _board("pips: the M1 battle begins")
	if board == null:
		return
	var state: CombatState = board.session.state
	var wrong: PackedStringArray = []
	for unit_id: String in state.unit_ids():
		var pips: StancePips = board.view.token_of(unit_id).info.get_stance_pips()
		var stance: int = state.unit(unit_id).stance
		if pips.stance != stance or _count(pips, StancePips.Pip.FILLED) != stance:
			wrong.append("%s: %d filled of %d, has %d" % [
				unit_id, _count(pips, StancePips.Pip.FILLED), pips.pip_count(), stance,
			])
	_check.call("pips: every unit shows one filled pip per point of Stance", (
			wrong.is_empty()
	), "; ".join(wrong))
	var unaligned: PackedStringArray = []
	for unit_id: String in state.unit_ids():
		var info: UnitInfo = board.view.token_of(unit_id).info
		var bar: Rect2 = info.get_hp_bar().get_global_rect()
		var pips_rect: Rect2 = info.get_stance_pips().get_global_rect()
		if (
				not is_equal_approx(pips_rect.position.x, bar.position.x)
				or not is_equal_approx(pips_rect.size.x, bar.size.x)
		):
			unaligned.append("%s: pips %s, bar %s" % [unit_id, pips_rect, bar])
	_check.call("pips: every unit's pips span its HP bar's width", (
			unaligned.is_empty()
	), "; ".join(unaligned))

	var unit_id: String = state.units_of(PLAYER)[0]
	var token: UnitToken = board.view.token_of(unit_id)
	var pips: StancePips = token.info.get_stance_pips()
	var top: int = token.stance_max
	_play(board, [_fact(CombatFact.Kind.STANCE_CHANGED, unit_id, 1)])
	var raised: Array[StancePips.Pip] = _pips_of(pips)
	var overflow_ok: bool = (
			pips.pip_count() == top + 1
			and pips.pip_at(top) == StancePips.Pip.OVERFLOW
			and _count(pips, StancePips.Pip.FILLED) == top
			and pips.color_of(StancePips.Pip.OVERFLOW) != pips.color_of(StancePips.Pip.FILLED)
	)
	_check.call("pips: Stance above the maximum shows in the overflow colour", (
			top > 0 and overflow_ok
	), "max %d: %s" % [top, raised])

	_play(board, [_fact(CombatFact.Kind.STANCE_CHANGED, unit_id, -(top + 1))])
	var lagging: Array[StancePips.Pip] = _pips_of(pips)
	var lag_ok: bool = _count(pips, StancePips.Pip.LOST) == top and pips.is_exposed()
	_step(board.view, ceili(pips.lag_time / FRAME) + 2)
	var exposed: Array[StancePips.Pip] = _pips_of(pips)
	_check.call("pips: a drop lags in the change colour, then 0 shows the Exposed look", (
			lag_ok
			and _count(pips, StancePips.Pip.EXPOSED) == top
			and pips.color_of(StancePips.Pip.EXPOSED) != pips.color_of(StancePips.Pip.EMPTY)
			and token.get_stance_bar() == Vector2i(0, top)
	), "lagging %s, then %s" % [lagging, exposed])

	_play(board, [_fact(CombatFact.Kind.BLOCK_STANCE_REFRESHED, unit_id, 0)])
	_check.call("pips: a refresh fills them to the maximum again", (
			_count(pips, StancePips.Pip.FILLED) == top and not pips.is_exposed()
	), str(_pips_of(pips)))
	board.close()


# Up to tick_fallback_count (6) points draw as segments; past it, one bar with a tick between
# points, overflow included.
func _test_tick_fallback() -> void:
	var pips: StancePips = PIPS_SCENE.instantiate()
	_root.add_child(pips)
	var default_count: int = pips.tick_fallback_count
	pips.show_stance(6, 6)
	var at_six: bool = not pips.is_bar_mode() and pips.tick_count() == 0
	pips.show_stance(7, 6)
	var over: bool = (
			pips.is_bar_mode()
			and pips.tick_count() == 6
			and pips.pip_at(6) == StancePips.Pip.OVERFLOW
	)
	pips.show_stance(3, 8)
	var long_bar: bool = pips.is_bar_mode() and pips.tick_count() == 7
	pips.tick_fallback_count = 10
	var raised: bool = not pips.is_bar_mode()
	_check.call("pips: past the export count (default 6) they fall back to a bar with ticks", (
			default_count == 6 and at_six and over and long_bar and raised
	), "six %s, seven %s, eight %s, raised %s" % [at_six, over, long_bar, raised])

	# From 1 to 9 points, as segments and as a bar, the first starts at the left edge and the last
	# ends at the right, at two widths.
	pips.tick_fallback_count = 6
	var gaps: PackedStringArray = []
	for width: float in [44.0, 71.0]:
		pips.size = Vector2(width, 5.0)
		for points: int in range(1, 10):
			pips.show_stance(points, points)
			var first: Rect2 = pips.segment_rect(0)
			var last: Rect2 = pips.segment_rect(points - 1)
			if not is_zero_approx(first.position.x) or not is_equal_approx(last.end.x, width):
				gaps.append("%d at %d px: %s to %s" % [points, width, first.position.x, last.end.x])
	_check.call("pips: the segments stretch to span the whole width, however many", (
			gaps.is_empty()
	), "; ".join(gaps))
	pips.free()


# An attack whose forecast breaks Stance, opened to CONFIRM by input: the pips from each unit's
# Stance after up to its Stance before are dimmed, the rest not; leaving CONFIRM clears them.
func _test_forecast_dims() -> void:
	var h: TurnInputCases.Harness = _harness("forecast: the M1 battle begins")
	if h == null:
		return
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find_breaking_attack(h.session)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty() or not _open_confirm(h, pick):
		_check.call("forecast: an attack that breaks Stance opens its forecast", false, str(pick))
		h.close()
		return
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	var forecast: CombatForecast.Forecast = panel.get_model().forecast
	var wrong: PackedStringArray = []
	var dimmed_units: int = 0
	for unit_id: String in h.view.token_ids():
		var pips: StancePips = h.view.token_of(unit_id).info.get_stance_pips()
		var outcome: CombatForecast.UnitOutcome = _outcome_of(forecast, unit_id)
		var breaks: bool = outcome != null and outcome.stance_after < outcome.stance_before
		for i: int in pips.pip_count():
			var should_dim: bool = (
					breaks and i >= outcome.stance_after and i < outcome.stance_before
			)
			if (pips.pip_at(i) == StancePips.Pip.BREAKING) != should_dim:
				wrong.append("%s pip %d" % [unit_id, i])
		if breaks:
			dimmed_units += 1
	_check.call("forecast: it dims exactly the pips the exchange would break", (
			dimmed_units > 0 and wrong.is_empty()
	), "%d units dimmed; wrong %s" % [dimmed_units, wrong])
	_press(&"ui_cancel")
	var left: int = 0
	for unit_id: String in h.view.token_ids():
		left += _count(h.view.token_of(unit_id).info.get_stance_pips(), StancePips.Pip.BREAKING)
	_check.call("forecast: leaving CONFIRM clears the dimming", (
			h.controller.get_stage() != BattleController.Stage.CONFIRM and left == 0
	), "%d still dimmed" % [left])
	h.close()


# Each info sits where the camera draws its token, as the engine's own canvas transform says, after
# a zoom onto a quarter of the map, a pan across it, a shake and a unit's walk.
func _test_follows_camera() -> void:
	var board: BattleViewCases.Board = _board("camera: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var rig: CameraRig = view.get_camera_rig()
	var problems: PackedStringArray = _placement_problems(view, "framed")
	var whole: Rect2 = view.map_rect()
	var quarter: Rect2 = Rect2(whole.position, whole.size * 0.5)
	rig.frame(quarter)
	# Zoomed onto a quarter, pans may still reach the whole map.
	rig.map_rect = whole
	_step(view, 1)
	problems.append_array(_placement_problems(view, "zoomed"))
	var focus_before: Vector2 = rig.get_focus()
	view.focus_tile(view.tile_at(whole.end - Vector2.ONE))
	_step(view, CAMERA_FRAMES)
	var panned: bool = not rig.get_focus().is_equal_approx(focus_before)
	problems.append_array(_placement_problems(view, "panned"))
	view.crit_shake_strength = 6.0
	var unit_id: String = board.session.state.units_of(PLAYER)[0]
	_play(board, [_fact(CombatFact.Kind.CRIT_TAKEN, unit_id, 0)])
	view.advance(FRAME)
	problems.append_array(_placement_problems(view, "shaking"))
	_step(view, CAMERA_FRAMES)
	problems.append_array(_placement_problems(view, "shaken"))
	var mover: String = TurnInputModel.acting_units(board.session, 0)[0]
	var tiles: Array[Vector2i] = TurnInputModel.move_tiles(board.session, mover)
	var walk: Array[Vector2i] = TurnInputModel.path_to(board.session, mover, tiles[-1])
	board.battle.submit(
			UnitTurnCommand.new(0, mover, UnitTurnCommand.Action.WAIT, "", walk),
			board.session.session_id
	)
	board.battle.resolve_queued()
	view.advance(FRAME * 3.0)
	problems.append_array(_placement_problems(view, "walking"))
	BattleViewCases.settle(view)
	problems.append_array(_placement_problems(view, "walked"))
	_check.call("camera: every info stays on its unit through a zoom, a pan, a shake and a walk", (
			panned and walk.size() > 1 and problems.is_empty()
	), "panned %s; %s" % [panned, "; ".join(problems.slice(0, 4))])
	_check.call("camera: the infos are drawn at scale 1.0 while both clamps are 1.0", (
			is_equal_approx(view.get_info_layer().info_scale(), 1.0)
			and view.get_info_layer().info_of(unit_id).scale.is_equal_approx(Vector2.ONE)
	))
	board.close()


# A Miss rises over the unit that dodged; a Critical with the crit's damage replaces the strike's
# number, flashes the struck unit and holds playback even when fully countered.
func _test_popups_synthetic() -> void:
	var board: BattleViewCases.Board = _board("pop-ups: the M1 battle begins")
	if board == null:
		return
	var shown: Array[Array] = []
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		shown.append([unit_id, style])
	board.view.number_shown.connect(on_shown)
	var attacker: String = board.session.state.units_of(PLAYER)[0]
	var defender: String = board.session.state.units_of(ENEMY)[0]
	var missed: CombatFact = CombatFact.new(CombatFact.Kind.MISSED, attacker, defender)
	var dodged: CombatFact = CombatFact.new(CombatFact.Kind.DODGED, defender, attacker)
	_play(board, [missed, dodged])
	var miss_ok: bool = (
			str(shown) == str([[defender, MISS]]) and _last_number(board.view).get_text() == "Miss"
	)
	shown.clear()

	var crit: CombatFact = CombatFact.new(CombatFact.Kind.CRIT_TAKEN, defender, attacker)
	crit.amount = 7
	var hit: CombatFact = _fact(CombatFact.Kind.DAMAGE_TAKEN, defender, 7)
	hit.hp_amount = 7
	board.session.playback.enqueue([
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, attacker, defender),
		CombatFact.new(CombatFact.Kind.CRIT_DEALT, attacker, defender), crit, hit,
	])
	board.view.advance(0.0)
	var token: UnitToken = board.view.token_of(defender)
	var flashing: bool = token.flash_amount > 0.0
	var number: DamageNumber = _last_number(board.view)
	BattleViewCases.settle(board.view)
	var crit_ok: bool = (
			str(shown) == str([[defender, CRITICAL]])
			and number.get_text() == "Critical 7"
			and number.style == CRITICAL
			and flashing
	)
	shown.clear()
	var countered: CombatFact = CombatFact.new(CombatFact.Kind.CRIT_TAKEN, defender, attacker)
	board.session.playback.enqueue([countered])
	board.view.advance(0.0)
	var held: bool = not board.view.is_settled()
	BattleViewCases.settle(board.view)
	board.view.number_shown.disconnect(on_shown)
	_check.call("pop-ups: a Miss rises over the unit that dodged, once per strike", miss_ok)
	_check.call("pop-ups: a Critical shows its damage once, with no second number, and flashes", (
			crit_ok
	), "flashing %s" % [flashing])
	_check.call("pop-ups: a fully countered Critical still shows and holds playback", (
			held and str(shown) == str([[defender, CRITICAL]])
	), str(shown))
	board.close()


# The same driven M1 battle on three boards, played normally, with fast-forward held and with every
# command's playback skipped: each board shows one Miss per Missed fact and one Critical per Crit
# taken, on the right units in order. The driven battle has misses but, like every seed tried
# (Stance refreshes each phase, so few units are Exposed when hit), no crit; so each mode also
# plays a crit strike's facts as ExchangeResolver.attack records them, with a miss beside it.
func _test_popups_by_mode() -> void:
	var expected: Array[Array] = []
	for mode: Mode in [Mode.NORMAL, Mode.FAST_FORWARD, Mode.SKIP]:
		var mode_name: String = Mode.find_key(mode) as String
		var result: Dictionary[String, Array] = _drive_battle(mode, "pop-ups (%s)" % [mode_name])
		if result.is_empty():
			return
		var facts: Array = result["facts"]
		var shown: Array = result["shown"]
		var misses: int = 0
		for entry: Array in facts:
			if entry[1] == MISS:
				misses += 1
		if mode == Mode.NORMAL:
			expected.assign(facts)
		var same_facts: bool = str(facts) == str(expected)
		var case_name: String = "pop-ups (%s): the driven battle shows one Miss per missed strike"
		_check.call(case_name % [mode_name], (
				str(shown) == str(facts) and same_facts and misses > 0
		), "%d shown for %d facts (%d misses); same facts as normal %s" % [
			shown.size(), facts.size(), misses, same_facts,
		])
		_test_strike_in_mode(mode, mode_name)


# A missed strike and a crit strike, each fact as ExchangeResolver.attack records it, played in
# mode: one Miss over the dodger, one Critical with the damage over the struck unit, no plain
# number for the crit's damage.
func _test_strike_in_mode(mode: Mode, mode_name: String) -> void:
	var board: BattleViewCases.Board = _board("strikes (%s): the M1 battle begins" % [mode_name])
	if board == null:
		return
	var shown: Array[Array] = []
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		shown.append([unit_id, style])
	board.view.number_shown.connect(on_shown)
	var a: String = board.session.state.units_of(PLAYER)[0]
	var d: String = board.session.state.units_of(ENEMY)[0]
	var crit_taken: CombatFact = CombatFact.new(CombatFact.Kind.CRIT_TAKEN, d, a)
	crit_taken.amount = 6
	var damage: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, d, a)
	damage.amount = 6
	damage.hp_amount = 6
	var facts: Array[CombatFact] = [
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, a, d),
		CombatFact.new(CombatFact.Kind.MISSED, a, d),
		CombatFact.new(CombatFact.Kind.DODGED, d, a),
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, a, d),
		CombatFact.new(CombatFact.Kind.HIT_DEALT, a, d),
		CombatFact.new(CombatFact.Kind.HIT_TAKEN, d, a),
		CombatFact.new(CombatFact.Kind.CRIT_DEALT, a, d),
		crit_taken,
		CombatFact.new(CombatFact.Kind.DAMAGE_DEALT, a, d),
		damage,
	]
	board.session.playback.enqueue(facts)
	board.view.set_fast_forward(mode == Mode.FAST_FORWARD)
	var skipped: bool = mode == Mode.SKIP and board.view.skip_playback()
	BattleViewCases.settle(board.view)
	board.view.number_shown.disconnect(on_shown)
	_check.call("strikes (%s): one Miss and one Critical, no second number" % [mode_name], (
			str(shown) == str([[d, MISS], [d, CRITICAL]]) and (skipped or mode != Mode.SKIP)
	), "%s; skipped %s" % [shown, skipped])
	board.close()


# --- Fixtures --------------------------------------------------------------------------------


# Drives the M1 battle to its end with the board in mode; returns "facts" (each Missed fact's
# target and each Crit taken's actor, with the pop-up style due, in order), "shown" (each Miss or
# Critical pop-up's unit and style); empty when it can't begin.
func _drive_battle(mode: Mode, case_name: String) -> Dictionary[String, Array]:
	var result: Dictionary[String, Array] = {}
	var board: BattleViewCases.Board = _board(case_name + ": the M1 battle begins")
	if board == null:
		return result
	var facts: Array[Array] = []
	var shown: Array[Array] = []
	var on_fact: Callable = func(fact: CombatFact) -> void:
		if fact.kind == CombatFact.Kind.MISSED:
			facts.append([fact.target_id, MISS])
		elif fact.kind == CombatFact.Kind.CRIT_TAKEN:
			facts.append([fact.actor_id, CRITICAL])
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		if style == MISS or style == CRITICAL:
			shown.append([unit_id, style])
	board.session.bus.fact_played.connect(on_fact)
	board.view.number_shown.connect(on_shown)
	board.view.set_fast_forward(mode == Mode.FAST_FORWARD)
	var disagreements: PackedStringArray = []
	for _phase: int in MAX_PHASES:
		if board.session.is_finished:
			break
		for unit_id: String in board.session.state.units_of(PLAYER):
			if board.session.is_finished:
				break
			if TurnInputModel.can_act(board.session, unit_id):
				_drive(board, _driver_command(board.session, unit_id), mode, disagreements)
		if not board.session.is_finished:
			_drive(board, EndTurnCommand.new(0), mode, disagreements)
	board.session.bus.fact_played.disconnect(on_fact)
	board.view.number_shown.disconnect(on_shown)
	_check.call(case_name + ": the battle ends and the board agrees with the state throughout", (
			board.session.is_finished and disagreements.is_empty()
	), "; ".join(disagreements.slice(0, 3)))
	board.close()
	result["facts"] = facts
	result["shown"] = shown
	return result


func _drive(
		board: BattleViewCases.Board,
		command: Command,
		mode: Mode,
		disagreements: PackedStringArray
) -> void:
	board.battle.submit(command, board.session.session_id)
	board.battle.resolve_queued()
	if mode == Mode.SKIP:
		board.view.skip_playback()
	if not BattleViewCases.settle(board.view):
		disagreements.append("%s never settled" % [command.get_label()])
		return
	var found: PackedStringArray = board.view.mismatches()
	if not found.is_empty():
		disagreements.append("after %s: %s" % [command.get_label(), ", ".join(found)])


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


# The first [unit_id, path, option, target index] of an Attack whose forecast leaves a unit with
# less Stance than it has; empty when no acting unit has one.
func _find_breaking_attack(session: CombatSession) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				if option.kind != ATTACK:
					continue
				for i: int in option.targets.size():
					var command: UnitTurnCommand = option.targets[i].command as UnitTurnCommand
					var model: ForecastViewModel = ForecastViewModel.build(session, command, 0, 1)
					if model.forecast != null and _breaks_stance(model.forecast):
						return [unit_id, path, option, i]
	return []


static func _breaks_stance(forecast: CombatForecast.Forecast) -> bool:
	for outcome: CombatForecast.UnitOutcome in forecast.units:
		if outcome.stance_after < outcome.stance_before:
			return true
	return false


static func _outcome_of(
		forecast: CombatForecast.Forecast, unit_id: String
) -> CombatForecast.UnitOutcome:
	for outcome: CombatForecast.UnitOutcome in forecast.units:
		if outcome.unit_id == unit_id:
			return outcome
	return null


# Walks the controller from IDLE into CONFIRM for pick by accept, the menu's row and the target
# keys. Returns whether CONFIRM opened on a forecast panel.
func _open_confirm(h: TurnInputCases.Harness, pick: Array) -> bool:
	var unit_id: String = pick[0]
	var path: Array[Vector2i] = []
	var walk: Array = pick[1]
	path.assign(walk)
	var option: TurnInputModel.ActionOption = pick[2]
	var index: int = pick[3]
	var end: Vector2i = h.session.state.tile_of(unit_id) if path.is_empty() else path[-1]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(end)
	BattleViewCases.arrive(h.view)
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		return false
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == option.kind:
			menu.get_rows()[i].pressed.emit()
			break
	var list: TargetList = h.controller.get_target_list()
	if list == null:
		return false
	var wanted: String = option.targets[index].target_id
	for _i: int in list.size():
		if list.current().target_id == wanted:
			break
		_press(&"target_next")
	_press(&"ui_accept")
	return (
			h.controller.get_stage() == BattleController.Stage.CONFIRM
			and h.host.top() is ForecastPanel
	)


# Every acting unit waits where it stands, then End Turn.
func _wait_phase(h: TurnInputCases.Harness) -> void:
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		var wait: UnitTurnCommand = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)
		h.battle.submit(wait, h.session.session_id)
		h.battle.resolve_queued()
		BattleViewCases.settle(h.view)
	if not h.session.is_finished:
		h.battle.submit(EndTurnCommand.new(0), h.session.session_id)
		h.battle.resolve_queued()
		BattleViewCases.settle(h.view)


# Each info not where its layer puts it or not where the engine's canvas transform draws its
# token, labelled with when. A camera moved by a tween reaches the viewport only in the frame's
# process, which these cases don't run, so the camera applies its scroll first.
func _placement_problems(view: BattleView, when: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var layer: UnitInfoLayer = view.get_info_layer()
	var camera: Camera2D = view.get_camera_rig().get_node(^"%Camera")
	camera.force_update_scroll()
	var to_screen: Transform2D = view.get_camera_rig().board_to_screen()
	for unit_id: String in view.token_ids():
		var token: UnitToken = view.token_of(unit_id)
		var info: UnitInfo = layer.info_of(unit_id)
		if info == null or info != token.info:
			problems.append("%s %s: no info" % [when, unit_id])
			continue
		var drawn: Vector2 = to_screen * token.global_position + layer.unit_offset
		var engine: Vector2 = token.get_global_transform_with_canvas().origin + layer.unit_offset
		if (
				info.position.distance_to(drawn) > PLACE_TOLERANCE
				or info.position.distance_to(engine) > PLACE_TOLERANCE
		):
			problems.append("%s %s: at %s, drawn %s, engine %s" % [
				when, unit_id, info.position, drawn, engine,
			])
	return problems


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


# The M1 battle with turn input, past Start, as unit_display_cases.gd builds it.
func _harness(case_name: String) -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call(case_name, false, "begin_battle gave no battle")
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


# Plays facts through the board's playback, as a resolved batch would, and settles it.
func _play(board: BattleViewCases.Board, facts: Array[CombatFact]) -> void:
	board.session.playback.enqueue(facts)
	BattleViewCases.settle(board.view)


# Steps the board frames times, settled or not, so cosmetic tweens (pans, lags, shakes) run on.
static func _step(view: BattleView, frames: int) -> void:
	for _i: int in frames:
		view.advance(FRAME)


static func _fact(kind: CombatFact.Kind, actor_id: String, amount: int) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor_id)
	fact.amount = amount
	return fact


static func _count(pips: StancePips, pip: StancePips.Pip) -> int:
	var found: int = 0
	for i: int in pips.pip_count():
		if pips.pip_at(i) == pip:
			found += 1
	return found


static func _pips_of(pips: StancePips) -> Array[StancePips.Pip]:
	var drawn: Array[StancePips.Pip] = []
	for i: int in pips.pip_count():
		drawn.append(pips.pip_at(i))
	return drawn


# The pop-up added last to the unit info layer, Block numbers aside; null with none.
static func _last_number(view: BattleView) -> DamageNumber:
	var popups: Array[Node2D] = view.get_info_layer().get_popups()
	for i: int in range(popups.size() - 1, -1, -1):
		var number: DamageNumber = popups[i] as DamageNumber
		if number != null and number.style != DamageNumber.Style.BLOCK:
			return number
	return null


func _press(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)
