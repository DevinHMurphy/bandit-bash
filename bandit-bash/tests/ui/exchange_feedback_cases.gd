# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     exchange_feedback_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## Exchange feedback's cases for the ui/display suite (combat UI plan, UI10 row; question 34): the
## forecast's flash on both units' HP bars and Stance pips, against [CombatForecast] (a single
## strike, a multi-strike exchange, a kill clipped at 0 HP, a heal), following Q / E and weapon
## cycling and cleared when the panel closes or the command is sent; the pips' outlines at 1, 3,
## overflow, Exposed and bar mode; and move then act: the walk to the picked tile at the walk
## speed (and faster held), the token shown there through TARGET and CONFIRM, the snap back on
## Cancel and after a rejection, no walk on the unit's own tile, no second walk after Confirm, and
## the board matching the session after each. No autoload is named or needed.
##
## [b]The harness[/b] is forecast_cases.gd's (turn_input_cases.gd's with the forecast panel), past
## Start. Fixtures, test setup only: a Hakkapel with Sidearm and a stowed three-strike sword (the
## multi-strike weapon), a target wounded to 1 HP (the kill), and a Battle Medic holding its
## stowed Minor Heal with the Hakkapel wounded (the heal); each also sets the token, so the board
## still matches the state.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# The bars' default flash: white at 0.8 alpha, so the white HP number reads at the peak
# (question 35 (2)).
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)

const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://scenes/ui/battle/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://scenes/ui/battle/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/battle/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://scenes/ui/battle/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/battle/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://scenes/ui/battle/forecast_panel.tscn")
const PIPS_SCENE: PackedScene = preload("res://scenes/ui/battle/stance_pips.tscn")
const HP_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/hp_bar.tscn")

# The other UI cases' seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Player phases a case may wait through to find what it needs.
const MAX_PHASES: int = 6

# The multi-strike fixture: AtkX 3, so even against Parry 1 it strikes twice a turn.
const MULTI_ID: String = "test:triple_sword"
const MULTI_ATK_X: int = 3

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const STAFF: TurnInputModel.ActionKind = TurnInputModel.ActionKind.STAFF
const WAIT: TurnInputModel.ActionKind = TurnInputModel.ActionKind.WAIT

const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const WALK: BattleController.Stage = BattleController.Stage.WALK
const ACTION: BattleController.Stage = BattleController.Stage.ACTION
const TARGET: BattleController.Stage = BattleController.Stage.TARGET
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM
const IDLE: BattleController.Stage = BattleController.Stage.IDLE

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the harness is added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("exchange: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_pip_outlines()
	_test_flash_widgets()
	_test_attack_flash()
	_test_kill_flash()
	_test_heal_flash()
	_test_walk()
	_test_walk_then_confirm()


# --- The widgets -------------------------------------------------------------------------------


# Each pip outlined, inside its own rect, at 1, 3, overflow (4 of 3) and Exposed (0 of 2); one
# outline round the bar past the tick fallback; the exports' dark default and their off values.
func _test_pip_outlines() -> void:
	var pips: StancePips = PIPS_SCENE.instantiate()
	_root.add_child(pips)
	pips.size = Vector2(44.0, 5.0)
	var problems: PackedStringArray = []
	var shapes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, 3), Vector2i(4, 3), Vector2i(0, 2)]
	for shape: Vector2i in shapes:
		pips.show_stance(shape.x, shape.y)
		var count: int = pips.pip_count()
		if pips.outline_count() != count or count == 0:
			problems.append("%s: %d outlines for %d pips" % [shape, pips.outline_count(), count])
		for i: int in count:
			if pips.segment_rect(i).size.x <= pips.outline_width * 2.0:
				problems.append("%s: pip %d too narrow for its outline" % [shape, i])
	pips.show_stance(4, 3)
	var overflow: bool = pips.pip_at(3) == StancePips.Pip.OVERFLOW
	# Shown twice: the drop from 4 lags in the change colour, the second show ends the lag.
	pips.show_stance(0, 2)
	pips.show_stance(0, 2)
	var exposed: bool = pips.is_exposed() and pips.pip_at(0) == StancePips.Pip.EXPOSED
	_check.call("pips: every pip has its own outline at 1, 3, overflow and Exposed", (
			problems.is_empty() and overflow and exposed
	), "; ".join(problems))
	pips.show_stance(8, 8)
	var bar_mode: bool = pips.is_bar_mode() and pips.outline_count() == 1
	var dark: bool = (
			pips.outline_color.get_luminance() < 0.2
			and pips.outline_color.a > 0.5
			and is_equal_approx(pips.outline_width, 1.0)
	)
	pips.outline_width = 0.0
	var off_by_width: bool = pips.outline_count() == 0
	pips.outline_width = 1.0
	pips.outline_color = Color.TRANSPARENT
	var off_by_colour: bool = pips.outline_count() == 0
	_check.call("pips: one outline round the bar in bar mode; dark by default; 0 width is off", (
			bar_mode and dark and off_by_width and off_by_colour
	), "bar %s, dark %s, width off %s, colour off %s" % [
		bar_mode, dark, off_by_width, off_by_colour,
	])
	pips.free()


# The HP bar's and the pips' flash: FLASH_COLOR by default; lit at once; one pulse each
# 1 / rate s; the HP flash spans the fill between the HP and its after, both ways; cleared,
# nothing is lit.
func _test_flash_widgets() -> void:
	var bar: HpBar = HP_BAR_SCENE.instantiate()
	_root.add_child(bar)
	bar.size = Vector2(44.0, 11.0)
	bar.show_hp(10, 20)
	bar.show_preview(4)
	var lit: bool = bar.is_previewing() and is_equal_approx(bar.get_flash_level(), 1.0)
	var damage_rect: Rect2 = bar.preview_rect()
	var tween: Tween = bar.get_flash_tween()
	var half: float = 0.5 / bar.preview_flash_rate
	if tween != null:
		tween.custom_step(half)
	var dimmed: float = bar.get_flash_level()
	if tween != null:
		tween.custom_step(half)
	var relit: float = bar.get_flash_level()
	bar.show_preview(16)
	var heal_rect: Rect2 = bar.preview_rect()
	var full_end: float = bar.preview_rect().end.x
	bar.show_preview(10)
	var same_clears: bool = not bar.is_previewing()
	bar.show_preview(-5)
	var clipped: bool = (
			bar.preview_after == 0 and is_equal_approx(bar.preview_rect().position.x, 0.0)
	)
	bar.clear_preview()
	var cleared: bool = not bar.is_previewing() and bar.get_flash_level() == 0.0
	_check.call("hp bar: the flash is white, lit at once, and pulses at its rate", (
			bar.preview_flash_color == FLASH_COLOR
			and lit
			and tween != null
			and dimmed < 0.05
			and relit > 0.95
	), "lit %s, after half %f, after full %f" % [lit, dimmed, relit])
	_check.call("hp bar: it spans the fill from the HP to its after, down or up, clipped at 0", (
			damage_rect.has_area()
			and damage_rect.end.x <= bar.size.x / 2.0 + 1.0
			and damage_rect.position.x > 0.0
			and heal_rect.has_area()
			and heal_rect.position.x >= damage_rect.end.x - 1.0
			and full_end <= bar.size.x
			and same_clears
			and clipped
			and cleared
	), "damage %s, heal %s, clipped %s, cleared %s" % [damage_rect, heal_rect, clipped, cleared])
	var bar_rate: float = bar.preview_flash_rate
	bar.free()

	var pips: StancePips = PIPS_SCENE.instantiate()
	_root.add_child(pips)
	pips.size = Vector2(44.0, 5.0)
	pips.show_stance(3, 3)
	pips.show_preview(1)
	var breaking: bool = (
			pips.pip_at(0) == StancePips.Pip.FILLED
			and pips.pip_at(1) == StancePips.Pip.BREAKING
			and pips.pip_at(2) == StancePips.Pip.BREAKING
	)
	var pip_lit: bool = is_equal_approx(pips.get_preview_level(), 1.0)
	var pip_tween: Tween = pips.get_preview_tween()
	if pip_tween != null:
		pip_tween.custom_step(0.5 / pips.preview_flash_rate)
	var pip_dimmed: float = pips.get_preview_level()
	pips.clear_preview()
	_check.call("pips: the Stance a forecast breaks flashes white at the HP bar's rate", (
			breaking
			and pip_lit
			and pip_dimmed < 0.05
			and pips.preview_flash_color == FLASH_COLOR
			and is_equal_approx(pips.preview_flash_rate, bar_rate)
			and pips.get_preview_level() == 0.0
			and pips.preview_after == -1
	), "breaking %s, lit %s, dimmed %f" % [breaking, pip_lit, pip_dimmed])
	pips.free()


# --- The flash on the board --------------------------------------------------------------------


# An attack by a Sidearm Hakkapel: with its lance (a single strike) and, cycled, the three-strike
# sword (a multi-strike exchange), both units flash what the forecast predicts, totalled, with no
# crit and no miss; Q / E move the flash to the next target; closing the panel and sending the
# command clear it; the token stands on its picked tile through TARGET and CONFIRM.
func _test_attack_flash() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var hakkapel: String = _unit_of_type(h.session, "Hakkapel")
	if hakkapel.is_empty():
		_check.call("flash: the M1 army has a Hakkapel", false)
		h.close()
		return
	_give_multi_sidearm(h.session, hakkapel)
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find(h.session, ATTACK, hakkapel, 2)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call("flash: the Hakkapel reaches an attack with both weapons", false)
		h.close()
		return
	var steps: PackedStringArray = []
	var panel: ForecastPanel = _open_forecast(h, pick, steps)
	if panel == null:
		_check.call("flash: the forecast opens", false, "; ".join(steps))
		h.close()
		return
	var tile: Vector2i = pick[1]
	var token: UnitToken = h.view.token_of(hakkapel)
	_check.call("walk: in CONFIRM the token stands on its picked tile, the state unmoved", (
			token.position.is_equal_approx(h.view.tile_to_position(tile))
			and token.tile == h.session.state.tile_of(hakkapel)
			and h.view.mismatches().is_empty()
	), "picked %s, unit on %s; %s" % [
		tile, h.session.state.tile_of(hakkapel), "; ".join(h.view.mismatches()),
	])

	var model: ForecastViewModel = panel.get_model()
	var single: CombatForecast.ExchangeForecast = model.forecast as CombatForecast.ExchangeForecast
	var problems: PackedStringArray = _forecast_problems(model)
	problems.append_array(_board_problems(h, model))
	var strikes: int = _strikes(single, hakkapel)
	_check.call("flash: a single strike flashes both units as the forecast predicts", (
			problems.is_empty() and strikes == 1 and not model.flashes.is_empty()
	), "strikes %d; %s" % [strikes, "; ".join(problems)])

	var weapon_moved: bool = h.controller.cycle_weapon()
	var cycled: ForecastViewModel = panel.get_model()
	var multi: CombatForecast.ExchangeForecast = cycled.forecast as CombatForecast.ExchangeForecast
	problems = _forecast_problems(cycled)
	problems.append_array(_board_problems(h, cycled))
	var multi_strikes: int = _strikes(multi, hakkapel)
	var target_id: String = cycled.command.get_target_id()
	var target_flash: ForecastViewModel.Flash = cycled.flash_of(target_id)
	var sum_past_block: int = 0
	for attack: CombatForecast.AttackForecast in multi.attacks:
		if attack.defender_id == target_id:
			sum_past_block += attack.hp_damage
	_check.call("flash: weapon cycling moves it to a multi-strike exchange, totalled", (
			weapon_moved
			and problems.is_empty()
			and multi_strikes >= 2
			and target_flash != null
			and target_flash.hp_before - target_flash.hp_after == sum_past_block
	), "cycled %s, strikes %d, flash %s, HP lost %d; %s" % [
		weapon_moved, multi_strikes, _flash_text(target_flash), sum_past_block,
		"; ".join(problems),
	])

	var list: TargetList = h.controller.get_target_list()
	var old_target: String = target_id
	var moved: bool = h.controller.cycle_target(true)
	var next: ForecastViewModel = panel.get_model()
	problems = _board_problems(h, next)
	var old_token: UnitToken = h.view.token_of(old_target)
	var old_cleared: bool = (
			old_token != null
			and (next.flash_of(old_target) != null or not _is_flashing(old_token))
	)
	_check.call("flash: Q / E move it to the next target's forecast", (
			list.targets().size() < 2
			or (moved and old_cleared and problems.is_empty()
					and next.command.get_target_id() != old_target)
	), "%d targets, moved %s; %s" % [list.targets().size(), moved, "; ".join(problems)])

	h.controller.step_back()
	_check.call("flash: closing the forecast clears every flash; the token still stands there", (
			h.controller.get_stage() == TARGET
			and _flashing(h).is_empty()
			and token.position.is_equal_approx(h.view.tile_to_position(tile))
	), "stage %d, flashing %s" % [h.controller.get_stage(), _flashing(h)])

	var target_index: int = h.controller.get_target_list().current_index()
	(h.host.top() as TargetPicker).get_rows()[target_index].pressed.emit()
	var reopened: bool = h.controller.get_stage() == CONFIRM and not _flashing(h).is_empty()
	(h.host.top() as ForecastPanel).get_confirm_button().pressed.emit()
	var cleared_on_send: bool = _flashing(h).is_empty()
	BattleViewCases.settle(h.view)
	_check.call("flash: it reopens with the panel and clears when the command is sent", (
			reopened and cleared_on_send and _flashing(h).is_empty()
			and h.view.mismatches().is_empty()
	), "reopened %s, cleared %s; %s" % [
		reopened, cleared_on_send, "; ".join(h.view.mismatches()),
	])
	h.close()


# A target wounded to 1 HP: the forecast kills it, its HP flash runs to 0 though the hit's damage
# past Block is more (overkill clipped), its Stance flash is what its strikes broke, and the
# attacker's bars flash the counter line's loss.
func _test_kill_flash() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find(h.session, ATTACK)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call("kill flash: an attack is found", false)
		h.close()
		return
	var target_id: String = (pick[3] as TurnInputModel.TargetOption).target_id
	_wound(h, target_id, 1)
	var steps: PackedStringArray = []
	var panel: ForecastPanel = _open_forecast(h, pick, steps)
	if panel == null:
		_check.call("kill flash: the forecast opens", false, "; ".join(steps))
		h.close()
		return
	var model: ForecastViewModel = panel.get_model()
	var found: CombatForecast.ExchangeForecast = model.forecast as CombatForecast.ExchangeForecast
	var flash: ForecastViewModel.Flash = model.flash_of(target_id)
	var past_block: int = 0
	for attack: CombatForecast.AttackForecast in found.attacks:
		if attack.defender_id == target_id:
			past_block += attack.damage - attack.block_damage
	var bar: HpBar = h.view.token_of(target_id).info.get_hp_bar()
	var problems: PackedStringArray = _forecast_problems(model)
	problems.append_array(_board_problems(h, model))
	_check.call("kill flash: the target's HP flashes down to 0, overkill clipped", (
			found.defender.outcome.is_defeated
			and flash != null
			and flash.hp_before == 1
			and flash.hp_after == 0
			and past_block > 1
			and bar.preview_after == 0
			and is_equal_approx(bar.preview_rect().position.x, 0.0)
			and problems.is_empty()
	), "defeated %s, past Block %d, bar after %d; %s" % [
		found.defender.outcome.is_defeated, past_block, bar.preview_after, "; ".join(problems),
	])
	var actor: String = model.command.actor_id
	var actor_flash: ForecastViewModel.Flash = model.flash_of(actor)
	var counters: bool = model.counter != null
	_check.call("kill flash: the attacker's bars flash the counter line, as its note reads", (
			not counters
			or (
					actor_flash != null
					and actor_flash.hp_after == model.counter.attacker.outcome.hp_after
			)
	), "counter %s, attacker flash %s" % [
		counters, "-" if actor_flash == null else str(actor_flash.hp_after),
	])
	h.close()


# The Battle Medic holding its Minor Heal, the Hakkapel wounded: the heal's target flashes from its
# HP up to its HP after, white as damage is, and the medic flashes nothing.
func _test_heal_flash() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var medic: String = _unit_of_type(h.session, "Battle Medic")
	var hakkapel: String = _unit_of_type(h.session, "Hakkapel")
	if medic.is_empty() or hakkapel.is_empty() or not _hold_stowed(h.session, medic):
		_check.call("heal flash: a Battle Medic with a stowed Minor Heal", false, medic)
		h.close()
		return
	var hp: int = h.session.state.get_hp(hakkapel)
	_wound(h, hakkapel, maxi(hp - 8, 1))
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find(h.session, STAFF, medic, 1, hakkapel)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call("heal flash: the medic can heal the Hakkapel", false)
		h.close()
		return
	var steps: PackedStringArray = []
	var panel: ForecastPanel = _open_forecast(h, pick, steps)
	if panel == null:
		_check.call("heal flash: the forecast opens", false, "; ".join(steps))
		h.close()
		return
	var model: ForecastViewModel = panel.get_model()
	var found: CombatForecast.StaffForecast = model.forecast as CombatForecast.StaffForecast
	var flash: ForecastViewModel.Flash = model.flash_of(hakkapel)
	var restored: int = 0
	for recipient: CombatForecast.Recipient in found.recipients:
		if recipient.unit_id == hakkapel:
			restored = recipient.restored
	var bar: HpBar = h.view.token_of(hakkapel).info.get_hp_bar()
	var rect: Rect2 = bar.preview_rect()
	var problems: PackedStringArray = _board_problems(h, model)
	_check.call("heal flash: the target flashes up by what it restores, white; the medic not", (
			found.kind == CombatState.WeaponStats.Staff.HEAL
			and flash != null
			and restored > 0
			and flash.hp_after == flash.hp_before + restored
			and bar.preview_after == flash.hp_after
			and rect.has_area()
			and bar.preview_flash_color == FLASH_COLOR
			and model.flash_of(medic) == null
			and not _is_flashing(h.view.token_of(medic))
			and problems.is_empty()
	), "restored %d, flash %s, bar after %d; %s" % [
		restored, _flash_text(flash), bar.preview_after, "; ".join(problems),
	])
	h.close()


# --- Move then act -----------------------------------------------------------------------------


# The walk to a far tile: WALK, the token on its way while its tile stays the unit's, arriving in
# the path's length over the walk speed and the menu opening, the session untouched; faster held;
# Cancel from the menu snapping it back at once; no walk on its own tile; a rejection snapping it
# back. The board matches the session after each.
func _test_walk() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var c: BattleController = h.controller
	var state: CombatState = h.session.state
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	var origin: Vector2i = state.tile_of(unit_id)
	var far: Vector2i = _far_tile(h.session, unit_id)
	var path: Array[Vector2i] = TurnInputModel.path_to(h.session, unit_id, far)
	var seconds: float = 0.0
	for i: int in range(1, path.size()):
		seconds += (
				h.view.tile_to_position(path[i - 1]).distance_to(h.view.tile_to_position(path[i]))
				/ h.view.move_speed
		)
	var token: UnitToken = h.view.token_of(unit_id)
	var hash_before: int = h.session.state_hash()
	var batches: int = h.batches.size()

	c.confirm_tile(origin)
	c.confirm_tile(far)
	var walking: bool = c.get_stage() == WALK and h.view.get_staged_unit() == unit_id
	h.view.advance(BattleViewCases.FRAME)
	var on_its_way: bool = (
			not token.position.is_equal_approx(h.view.tile_to_position(origin))
			and not token.position.is_equal_approx(h.view.tile_to_position(far))
			and token.tile == origin
			and h.view.mismatches().is_empty()
	)
	var frames: int = 1 + _frames_to_arrive(h)
	var expected_frames: int = ceili(seconds / BattleViewCases.FRAME)
	_check.call("walk: accept on a far tile walks the token there at the walk speed", (
			path.size() > 2
			and walking
			and on_its_way
			and absi(frames - expected_frames) <= 1
	), "path %d tiles, walking %s, on its way %s, %d frames for %d" % [
		path.size(), walking, on_its_way, frames, expected_frames,
	])
	_check.call("walk: on arrival the menu opens, the token there, the session untouched", (
			c.get_stage() == ACTION
			and h.host.top() is ActionMenu
			and token.position.is_equal_approx(h.view.tile_to_position(far))
			and token.tile == origin
			and state.tile_of(unit_id) == origin
			and h.session.state_hash() == hash_before
			and h.batches.size() == batches
			and h.view.mismatches().is_empty()
	), "stage %d; %s" % [c.get_stage(), "; ".join(h.view.mismatches())])

	_press(&"ui_cancel")
	_check.call("walk: Cancel from the menu snaps it back at once, to MOVE", (
			c.get_stage() == MOVE
			and h.host.depth() == 0
			and h.view.get_staged_unit().is_empty()
			and token.position.is_equal_approx(h.view.tile_to_position(origin))
			and h.view.get_info_layer().info_of(unit_id).position.is_equal_approx(
					h.view.get_info_layer().screen_point_of(unit_id)
			)
			and h.view.mismatches().is_empty()
	), "stage %d; %s" % [c.get_stage(), "; ".join(h.view.mismatches())])

	h.view.set_fast_forward(true)
	c.confirm_tile(far)
	var fast_frames: int = _frames_to_arrive(h)
	h.view.set_fast_forward(false)
	var fast_seconds: float = seconds / h.view.fast_forward_speed
	_check.call("walk: held fast-forward walks it fast_forward_speed times faster", (
			c.get_stage() == ACTION
			and fast_frames <= ceili(fast_seconds / BattleViewCases.FRAME) + 1
			and fast_frames < frames
	), "%d frames held, %d not" % [fast_frames, frames])
	_press(&"ui_cancel")

	c.confirm_tile(origin)
	_check.call("walk: accept on its own tile opens the menu with no walk", (
			c.get_stage() == ACTION
			and h.view.get_staged_unit().is_empty()
			and not h.view.is_staged_walking()
			and token.position.is_equal_approx(h.view.tile_to_position(origin))
	), "stage %d" % [c.get_stage()])
	_press(&"ui_cancel")

	c.confirm_tile(far)
	BattleViewCases.arrive(h.view)
	# The menu is now stale: the same unit waits behind its back, so its Wait is rejected.
	_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	_press_menu_row(h, WAIT)
	BattleViewCases.settle(h.view)
	var rejected: bool = h.last_batch() != null and h.last_batch().is_rejected()
	_check.call("walk: a rejected command snaps the token back to its tile", (
			rejected
			and c.get_stage() == IDLE
			and h.view.get_staged_unit().is_empty()
			and token.position.is_equal_approx(h.view.tile_to_position(state.tile_of(unit_id)))
			and h.view.mismatches().is_empty()
	), "rejected %s, stage %d; %s" % [rejected, c.get_stage(), "; ".join(h.view.mismatches())])
	h.close()


# Walk, then Wait: the command's playback starts where the token stands and never walks it again
# (it holds its tile's centre every frame, and settles with no walk's wait); then the board
# matches the session, the unit on its new tile.
func _test_walk_then_confirm() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var state: CombatState = h.session.state
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	var origin: Vector2i = state.tile_of(unit_id)
	var far: Vector2i = _far_tile(h.session, unit_id)
	var token: UnitToken = h.view.token_of(unit_id)
	h.controller.confirm_tile(origin)
	h.controller.confirm_tile(far)
	var walk_frames: int = _frames_to_arrive(h)
	_press_menu_row(h, WAIT)
	var at: Vector2 = h.view.tile_to_position(far)
	var drift: float = token.position.distance_to(at)
	var frames: int = 0
	while not h.view.is_settled() and frames < BattleViewCases.MAX_SETTLE_FRAMES:
		h.view.advance(BattleViewCases.FRAME)
		drift = maxf(drift, token.position.distance_to(at))
		frames += 1
	var sent: CombatSession.FactBatch = h.last_batch()
	_check.call("walk: Confirm plays from where the token stands, with no second walk", (
			sent != null
			and not sent.is_rejected()
			and is_zero_approx(drift)
			and frames < walk_frames
	), "drift %f px, playback %d frames, walk %d" % [drift, frames, walk_frames])
	_check.call("walk: after it the board matches the session, the unit on its new tile", (
			state.tile_of(unit_id) == far
			and token.tile == far
			and h.view.get_staged_unit().is_empty()
			and h.view.mismatches().is_empty()
	), "%s at %s; %s" % [unit_id, state.tile_of(unit_id), "; ".join(h.view.mismatches())])
	h.close()


# --- Checks ------------------------------------------------------------------------------------


# Why the model's flashes aren't the forecast's outcomes: each changed unit's HP and Stance after,
# the actor's from the counter line when there is one; every hit landed and none crit.
static func _forecast_problems(model: ForecastViewModel) -> PackedStringArray:
	var problems: PackedStringArray = []
	var found: CombatForecast.Forecast = model.forecast
	for outcome: CombatForecast.UnitOutcome in found.units:
		var shown: CombatForecast.UnitOutcome = outcome
		if model.counter != null and outcome.unit_id == found.actor_id:
			shown = model.counter.attacker.outcome
		var flash: ForecastViewModel.Flash = model.flash_of(outcome.unit_id)
		var changes: bool = (
				shown.hp_after != shown.hp_before or shown.stance_after < shown.stance_before
		)
		if changes != (flash != null):
			problems.append("%s: changes %s, flash %s" % [outcome.unit_id, changes, flash != null])
			continue
		if flash == null:
			continue
		if flash.hp_after != maxi(shown.hp_after, 0) or flash.stance_after != shown.stance_after:
			problems.append("%s: flash %d HP %d Stance, forecast %d, %d" % [
				outcome.unit_id, flash.hp_after, flash.stance_after, shown.hp_after,
				shown.stance_after,
			])
	var exchange: CombatForecast.ExchangeForecast = found as CombatForecast.ExchangeForecast
	if exchange != null:
		for attack: CombatForecast.AttackForecast in exchange.attacks:
			if not attack.is_hit or attack.is_crit:
				problems.append("attack %d: hit %s, crit %s" % [
					attack.index, attack.is_hit, attack.is_crit,
				])
	return problems


# Why the board's bars don't flash the model's flashes: each token's HP bar and pips previewing
# exactly its flash's after (or nothing), lit, white.
static func _board_problems(
		h: TurnInputCases.Harness, model: ForecastViewModel
) -> PackedStringArray:
	var problems: PackedStringArray = []
	for unit_id: String in h.view.token_ids():
		var info: UnitInfo = h.view.token_of(unit_id).info
		var flash: ForecastViewModel.Flash = model.flash_of(unit_id)
		var hp_expected: int = flash.hp_after if flash != null and flash.changes_hp() else -1
		var stance_expected: int = (
				flash.stance_after if flash != null and flash.breaks_stance() else -1
		)
		var bar: HpBar = info.get_hp_bar()
		var pips: StancePips = info.get_stance_pips()
		if bar.preview_after != hp_expected or pips.preview_after != stance_expected:
			problems.append("%s: bar %d (expected %d), pips %d (expected %d)" % [
				unit_id, bar.preview_after, hp_expected, pips.preview_after, stance_expected,
			])
		if hp_expected >= 0 and not is_equal_approx(bar.get_flash_level(), 1.0):
			problems.append("%s: HP flash not lit" % [unit_id])
	return problems


# The ids of every token whose HP bar or pips flash.
static func _flashing(h: TurnInputCases.Harness) -> PackedStringArray:
	var found: PackedStringArray = []
	for unit_id: String in h.view.token_ids():
		if _is_flashing(h.view.token_of(unit_id)):
			found.append(unit_id)
	return found


static func _is_flashing(token: UnitToken) -> bool:
	return (
			token.info.get_hp_bar().is_previewing()
			or token.info.get_stance_pips().preview_after >= 0
	)


# A flash as "HP before → after", or "-" for none.
static func _flash_text(flash: ForecastViewModel.Flash) -> String:
	if flash == null:
		return "-"
	return "%d → %d" % [flash.hp_before, flash.hp_after]


# unit_id's strikes in exchange: its attacks made.
static func _strikes(exchange: CombatForecast.ExchangeForecast, unit_id: String) -> int:
	var count: int = 0
	for attack: CombatForecast.AttackForecast in exchange.attacks:
		if attack.attacker_id == unit_id:
			count += 1
	return count


# --- Fixtures ----------------------------------------------------------------------------------


# forecast_cases.gd's harness, past Start.
func _harness() -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("exchange: the M1 battle begins", false, "begin_battle gave no battle")
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


# Frames the staged walk takes from now to arrive, stepping the board.
func _frames_to_arrive(h: TurnInputCases.Harness) -> int:
	var frames: int = 0
	while h.view.is_staged_walking() and frames < BattleViewCases.MAX_SETTLE_FRAMES:
		h.view.advance(BattleViewCases.FRAME)
		frames += 1
	return frames


# unit_id's move tile farthest from it by walk length; its own tile when it can't move.
static func _far_tile(session: CombatSession, unit_id: String) -> Vector2i:
	var best: Vector2i = session.state.tile_of(unit_id)
	var longest: int = 0
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var length: int = TurnInputModel.path_to(session, unit_id, tile).size()
		if length > longest:
			longest = length
			best = tile
	return best


# The first [unit_id, tile, option, target] of kind TurnInputModel offers, for only_unit and on
# only_target when set, whose target has at least min_weapons commands; empty when none.
static func _find(
		session: CombatSession,
		kind: TurnInputModel.ActionKind,
		only_unit: String = "",
		min_weapons: int = 1,
		only_target: String = ""
) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if not only_unit.is_empty() and unit_id != only_unit:
			continue
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				if option.kind != kind:
					continue
				for target: TurnInputModel.TargetOption in option.targets:
					if not only_target.is_empty() and target.target_id != only_target:
						continue
					if target.commands.size() >= min_weapons:
						return [unit_id, tile, option, target]
	return []


# forecast_cases.gd's walk from IDLE to CONFIRM for pick, with the walk to its tile arriving; the
# forecast panel on top, or null with the problem in steps.
func _open_forecast(
		h: TurnInputCases.Harness, pick: Array, steps: PackedStringArray
) -> ForecastPanel:
	var unit_id: String = pick[0]
	var tile: Vector2i = pick[1]
	var option: TurnInputModel.ActionOption = pick[2]
	var target: TurnInputModel.TargetOption = pick[3]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(tile)
	BattleViewCases.arrive(h.view)
	if not _press_menu_row(h, option.kind):
		steps.append("no %s in the menu for %s at %s" % [option.label, unit_id, tile])
		return null
	var picker: TargetPicker = h.host.top() as TargetPicker
	if picker == null:
		steps.append("no target picker for %s" % [option.label])
		return null
	var targets: Array[TurnInputModel.TargetOption] = picker.get_options()
	for i: int in targets.size():
		if targets[i].target_id == target.target_id:
			picker.get_rows()[i].pressed.emit()
			break
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if panel == null or h.controller.get_stage() != CONFIRM:
		steps.append("no forecast panel for %s on %s" % [option.label, target.target_id])
		return null
	return panel


# Presses the open action menu's row for kind; whether it had one.
func _press_menu_row(h: TurnInputCases.Harness, kind: TurnInputModel.ActionKind) -> bool:
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		return false
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == kind:
			menu.get_rows()[i].pressed.emit()
			return true
	return false


# Sidearm (free swaps) and a stowed three-strike sword for unit_id, as forecast_cases.gd's Sidearm
# fixture with MULTI_ATK_X (test setup only).
func _give_multi_sidearm(session: CombatSession, unit_id: String) -> void:
	var sword: CombatState.WeaponStats = CombatState.WeaponStats.new()
	sword.id = MULTI_ID
	sword.label = "Triple Sword"
	sword.weapon_type = "sword"
	sword.damage = 5
	sword.atk_x = MULTI_ATK_X
	sword.profile = WeaponTriangle.Profile.NIMBLE
	sword.range_min = 1
	sword.range_max = 1
	sword.hit = 80
	sword.crit_x = 3.0
	sword.weight = 8
	session.state.add_weapon(sword)
	session.state.unit(unit_id).stowed_weapon_id = MULTI_ID
	session.state.load_bases(session.engine, unit_id)
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = "test_sidearm"
	definition.operations.append(grant)
	var state: CombatState = session.state
	var owner: EffectOwner = EffectOwner.for_unit(
			unit_id, state.seat_of(unit_id), state.side_of(unit_id)
	)
	session.engine.register(EffectInstance.new(
			"test:sidearm", definition, owner, Modifier.SourceKind.UNIT_TRAIT, "test:sidearm"
	))


# unit_id holds its stowed weapon and stows the one it held (test setup only); whether it had one.
static func _hold_stowed(session: CombatSession, unit_id: String) -> bool:
	var unit: CombatUnitState = session.state.unit(unit_id)
	if unit == null or unit.stowed_weapon_id.is_empty():
		return false
	var held: String = unit.equipped_weapon_id
	unit.equipped_weapon_id = unit.stowed_weapon_id
	unit.stowed_weapon_id = held
	session.state.load_bases(session.engine, unit_id)
	return true


# Sets unit_id's HP to hp on the state and its token (test setup only), so the board still matches.
static func _wound(h: TurnInputCases.Harness, unit_id: String, hp: int) -> void:
	h.session.state.unit(unit_id).hp = hp
	var token: UnitToken = h.view.token_of(unit_id)
	token.show_hp(hp, token.max_hp)


static func _unit_of_type(session: CombatSession, label: String) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if session.describe(unit_id).contains("(%s)" % [label]):
			return unit_id
	return ""


func _wait_phase(h: TurnInputCases.Harness) -> void:
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	if not h.session.is_finished:
		_send(h, EndTurnCommand.new(0))


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


func _press(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)
