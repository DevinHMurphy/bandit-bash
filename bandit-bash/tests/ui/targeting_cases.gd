# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     targeting_cases.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

extends RefCounted
## Targeting's cases for tests/ui/run_all.gd (combat UI plan, UI6 row; questions 21 and 23):
## [TargetList] cycling and wrapping; each action's target list (attack, staff, item on an ally,
## shove, rune) against what the validator accepts on the M1 board; keys and the mouse sending the
## same command; the target outlines; Q / E cycling the units that can act in IDLE; the purple
## support overlays; and the healers (the Hedge Healer and the Battle Medic) showing no attack
## tiles anywhere. No autoload is named or needed.
##
## The harness is [code]turn_input_cases.gd[/code]'s, with the forecast panel. The rune fixture
## gives seat 0 a Mend rune (heal 10) and a wounded unit, as [code]tests/combat/turn_cases.gd[/code]
## does (test setup only; the UI never does this).

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://scenes/ui/battle/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://scenes/ui/battle/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/battle/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://scenes/ui/battle/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/battle/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://scenes/ui/battle/forecast_panel.tscn")

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# Player phases a case may wait through to find what it needs.
const MAX_PHASES: int = 4

# HP the rune fixture takes from one player unit, so Mend and a Potion have a target.
const WOUND: int = 5

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const IDLE: BattleController.Stage = BattleController.Stage.IDLE
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const ACTION: BattleController.Stage = BattleController.Stage.ACTION
const TARGET: BattleController.Stage = BattleController.Stage.TARGET
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const STAFF: TurnInputModel.ActionKind = TurnInputModel.ActionKind.STAFF
const ITEM: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ITEM
const SHOVE: TurnInputModel.ActionKind = TurnInputModel.ActionKind.SHOVE
const RUNE: TurnInputModel.ActionKind = TurnInputModel.ActionKind.RUNE

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
		_check.call("targeting: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_list_cycling()
	_test_lists_match_validator()
	_test_keys_and_mouse()
	_test_outlines()
	_test_unit_cycling()
	_test_support_overlays()
	_test_healers()


# Next and previous target and weapon wrap; the weapon is kept across targets where it can be.
func _test_list_cycling() -> void:
	var a: TurnInputModel.TargetOption = _fake_target("a", Vector2i(0, 0), ["", "s"])
	var b: TurnInputModel.TargetOption = _fake_target("b", Vector2i(1, 0), ["", "s"])
	var c: TurnInputModel.TargetOption = _fake_target("c", Vector2i(2, 0), [""])
	var option: TurnInputModel.ActionOption = TurnInputModel.ActionOption.new(ATTACK)
	option.targets.assign([a, b, c])
	var list: TargetList = TargetList.build(option)
	var visited: PackedStringArray = []
	for _i: int in 3:
		list.next_target()
		visited.append(list.current().target_id)
	var back: PackedStringArray = []
	for _i: int in 3:
		list.previous_target()
		back.append(list.current().target_id)
	_check.call("list: next and previous target wrap", (
			visited == PackedStringArray(["b", "c", "a"])
			and back == PackedStringArray(["c", "b", "a"])
	), "next %s, previous %s" % [visited, back])

	var weapons: PackedStringArray = []
	list.next_weapon()
	weapons.append(TargetList.weapon_key(list.command()))
	list.next_weapon()
	weapons.append(TargetList.weapon_key(list.command()))
	list.previous_weapon()
	weapons.append(TargetList.weapon_key(list.command()))
	_check.call("list: next and previous weapon wrap", (
			weapons == PackedStringArray(["s", "", "s"])
	), str(weapons))

	list.next_target()
	var kept: bool = list.current() == b and list.weapon_index() == 1
	list.next_target()
	var fallback: bool = list.current() == c and list.weapon_index() == 0
	list.previous_target()
	var stays_first: bool = list.current() == b and list.weapon_index() == 0
	_check.call("list: the weapon is kept across targets, else the first", (
			kept and fallback and stays_first
	))

	var single: TargetList = TargetList.build(_single_option(c))
	_check.call("list: one target and one weapon don't cycle", (
			not single.next_target()
			and not single.previous_target()
			and not single.next_weapon()
			and single.current() == c
			and list.index_at(b.tile) == 1
			and list.index_at(Vector2i(9, 9)) == -1
			and TargetList.build(null).is_empty()
			and TargetList.build(null).command() == null
	))


# Each action's TargetList holds exactly the targets and weapons the validator accepts, on the M1
# board: attack, staff, item on an ally, shove and rune.
func _test_lists_match_validator() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	_give_mend_rune(h.session)
	# Each kind's mismatch, found on the board as it stood when the kind was first offered.
	var found: Dictionary[int, String] = {}
	for _phase: int in MAX_PHASES:
		_collect(h.session, found)
		if found.size() == 5 or h.session.is_finished:
			break
		_wait_phase(h)
	for kind: TurnInputModel.ActionKind in [ATTACK, STAFF, ITEM, SHOVE, RUNE]:
		var label: String = TurnInputModel.ACTION_LABELS[kind]
		_check.call("lists: %s's targets are exactly what the validator accepts" % [label], (
				found.has(kind) and found[kind].is_empty()
		), found.get(kind, "the M1 board never offered it"))
	h.close()


# Keys (Q / E and accept) and the mouse (hover and click) pick the same target and send the same
# command; Q / E in CONFIRM move the forecast to the next target; the cursor snaps to the current
# target; the controller's list is the action's.
func _test_keys_and_mouse() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find_with_targets(h.session, [ATTACK, SHOVE, STAFF, ITEM], 2)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty() or not _open_target(h, pick):
		_check.call("keys and mouse: an action with two targets opens", false, str(pick))
		h.close()
		return
	var c: BattleController = h.controller
	var list: TargetList = c.get_target_list()
	var option: TurnInputModel.ActionOption = pick[2]
	_check.call("keys and mouse: the controller's list is the action's, cursor on the first", (
			_listed_keys(list) == _listed_keys(TargetList.build(option))
			and c.get_cursor_tile() == list.current().tile
	))
	var chosen: int = -1
	for i: int in list.size():
		if i > 0 and _is_clear(h, list.targets()[i].tile):
			chosen = i
	if chosen < 0:
		_check.call("keys and mouse: a target off the panels for the mouse", false, "")
		h.close()
		return
	var target: TurnInputModel.TargetOption = list.targets()[chosen]
	for _i: int in chosen:
		_press(&"target_next")
	var picker: TargetPicker = h.host.top() as TargetPicker
	var focused: Control = _root.get_viewport().gui_get_focus_owner()
	_check.call("keys and mouse: E moves the current target, cursor and focused row", (
			list.current() == target
			and c.get_cursor_tile() == target.tile
			and picker != null
			and focused == picker.get_rows()[chosen]
	), "current %d of %d" % [list.current_index(), list.size()])
	_press(&"ui_accept")
	var by_keys: String = _wire(c.get_confirm_command())
	var keys_stage: BattleController.Stage = c.get_stage()
	_press(&"target_next")
	var after_next: Command = c.get_confirm_command()
	var forecast: ForecastPanel = h.host.top() as ForecastPanel
	var follows: bool = (
			forecast == null
			or (forecast.get_model() != null and forecast.get_model().command == after_next)
	)
	_press(&"target_prev")
	_check.call("keys and mouse: Q / E in the forecast move it to the next target", (
			keys_stage == CONFIRM
			and after_next == list.targets()[(chosen + 1) % list.size()].commands[0]
			and follows
			and _wire(c.get_confirm_command()) == by_keys
	), "%s then %s" % [by_keys, _wire(after_next)])
	_press(&"ui_cancel")
	_press(&"target_prev")
	var moved_away: bool = list.current() != target
	_hover(h, target.tile)
	var hovered: bool = list.current() == target
	_click(h, target.tile)
	var by_mouse: String = _wire(c.get_confirm_command())
	_check.call("keys and mouse: hovering a target makes it current; a click picks it", (
			moved_away and hovered and c.get_stage() == CONFIRM
	), "stage %d" % [c.get_stage()])
	_check.call("keys and mouse: both send the same command", (
			by_keys == by_mouse
			and by_keys != "none"
			and c.get_confirm_command().validate(h.session).is_empty()
	), "keys %s, mouse %s" % [by_keys, by_mouse])
	h.close()


# Every listed target is outlined, the current one more strongly and by its side's colour; the
# strong outline follows the current target; leaving TARGET clears the outlines.
func _test_outlines() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find_with_targets(h.session, [ATTACK, SHOVE, STAFF, ITEM], 2)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty() or not _open_target(h, pick):
		_check.call("outlines: an action with two targets opens", false, str(pick))
		h.close()
		return
	var list: TargetList = h.controller.get_target_list()
	var problems: PackedStringArray = _mark_problems(h, list)
	var current_before: Vector2i = list.current().tile
	_press(&"target_next")
	problems.append_array(_mark_problems(h, list))
	var strong_moved: bool = false
	for mark: TargetMark in h.view.get_target_marks():
		if mark.is_current:
			strong_moved = mark.tile == list.current().tile and mark.tile != current_before
	_check.call("outlines: every target outlined, the current one strongly, by side", (
			problems.is_empty()
	), "; ".join(problems))
	_check.call("outlines: the strong outline follows the current target", strong_moved)
	_press(&"ui_cancel")
	_check.call("outlines: leaving the targets clears them", (
			h.controller.get_stage() == ACTION and h.view.get_target_marks().is_empty()
	))
	h.close()


# In IDLE, E and Q visit exactly the seat's units that can act, wrapping, moving only the cursor;
# a unit that has acted is skipped; in MOVE they are inert.
func _test_unit_cycling() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var c: BattleController = h.controller
	var state: CombatState = h.session.state
	var acting: PackedStringArray = TurnInputModel.acting_units(h.session, 0)
	if acting.size() < 3:
		_check.call("units: three units can act on turn 1", false, str(acting))
		h.close()
		return
	c.move_cursor(state.tile_of(acting[0]))
	var forward: PackedStringArray = []
	for _i: int in acting.size():
		_press(&"target_next")
		forward.append(state.occupant_at(c.get_cursor_tile()))
	var backward: PackedStringArray = []
	for _i: int in acting.size():
		_press(&"target_prev")
		backward.append(state.occupant_at(c.get_cursor_tile()))
	var expected_back: PackedStringArray = []
	for i: int in acting.size():
		expected_back.append(acting[posmod(-1 - i, acting.size())])
	var expected_forward: PackedStringArray = acting.slice(1)
	expected_forward.append(acting[0])
	_check.call("units: E and Q visit exactly the units that can act, wrapping", (
			forward == expected_forward
			and backward == expected_back
			and c.get_stage() == IDLE
			and c.get_selected_unit().is_empty()
	), "E %s, Q %s, acting %s" % [forward, backward, acting])

	_send(h, UnitTurnCommand.new(0, acting[1], UnitTurnCommand.Action.WAIT))
	var left: PackedStringArray = TurnInputModel.acting_units(h.session, 0)
	var seen: Dictionary[String, bool] = {}
	for _i: int in left.size() * 2:
		_press(&"target_next")
		seen[state.occupant_at(c.get_cursor_tile())] = true
	var seen_ids: PackedStringArray = PackedStringArray(seen.keys())
	seen_ids.sort()
	var left_sorted: PackedStringArray = left.duplicate()
	left_sorted.sort()
	_check.call("units: a unit that has acted is skipped", (
			seen_ids == left_sorted and not seen.has(acting[1])
	), "seen %s, acting %s" % [seen_ids, left_sorted])

	c.confirm_tile(state.tile_of(left[0]))
	var cursor: Vector2i = c.get_cursor_tile()
	_press(&"target_next")
	_press(&"target_prev")
	_check.call("units: Q / E are inert in MOVE", (
			c.get_stage() == MOVE and c.get_cursor_tile() == cursor
			and c.get_selected_unit() == left[0]
	))
	h.close()


# The support overlays are purple and the attack ones red; on each display (the selection, an
# enemy's toggled range, the danger zone) the support tiles are never also attack tiles.
func _test_support_overlays() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var view: BattleView = h.view
	var purple: Array[TileOverlay] = [
		view.get_support_overlay(), view.get_enemy_support_overlay(),
		view.get_danger_support_overlay(),
	]
	var red: Array[TileOverlay] = [
		view.get_attack_overlay(), view.get_enemy_range_overlay(), view.get_danger_overlay(),
	]
	var colours_ok: bool = true
	for overlay: TileOverlay in purple:
		colours_ok = colours_ok and _is_purple(overlay.fill_color)
	for overlay: TileOverlay in red:
		var fill: Color = overlay.fill_color
		colours_ok = colours_ok and _is_red(fill) and not _is_purple(fill)
	_check.call("support: the support overlays are purple, the attack ones red", colours_ok)

	var problems: PackedStringArray = []
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		h.controller.confirm_tile(h.session.state.tile_of(unit_id))
		_expect_disjoint(problems, "selection of %s" % [unit_id], purple[0], red[0])
		_expect_disjoint(problems, "selection of %s, move" % [unit_id], purple[0], (
				view.get_move_overlay()
		))
		h.controller.step_back()
	for enemy_id: String in h.session.state.units_of(ENEMY):
		h.controller.confirm_tile(h.session.state.tile_of(enemy_id))
	_expect_disjoint(problems, "every enemy's range", purple[1], red[1])
	var enemy_support: int = purple[1].shown_tiles().size()
	h.controller.toggle_danger_zone()
	_expect_disjoint(problems, "the danger zone", purple[2], red[2])
	var danger_support: int = purple[2].shown_tiles().size()
	_check.call("support: support tiles are never also attack tiles", problems.is_empty(), (
			"; ".join(problems)
	))
	_check.call("support: the enemy range and the danger zone show support tiles", (
			enemy_support > 0 and danger_support > 0
	), "enemy range %d, danger zone %d" % [enemy_support, danger_support])
	h.close()


# The Hedge Healer and the Battle Medic attack nothing, so neither shows an attack tile anywhere:
# not in the medic's selection or its Staff targets, not in the healer's toggled range or the
# danger zone; their reach shows purple instead.
func _test_healers() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var session: CombatSession = h.session
	var view: BattleView = h.view
	var medic: String = _unit_of_type(session, PLAYER, "Battle Medic")
	var healer: String = _unit_of_type(session, ENEMY, "Hedge Healer")
	if medic.is_empty() or healer.is_empty():
		_check.call("healers: M1 has a Battle Medic and a Hedge Healer", false, "%s, %s" % [
			medic, healer,
		])
		h.close()
		return
	_check.call("healers: no attack ranges or tiles in the model", (
			DangerZone.attack_ranges(session.engine, medic).is_empty()
			and DangerZone.attack_ranges(session.engine, healer).is_empty()
			and TurnInputModel.attack_tiles(session, medic).is_empty()
			and TurnInputModel.enemy_range_tiles(session, healer).is_empty()
			and TurnInputModel.enemy_range_tiles(session, medic).is_empty()
			and DangerZone.tiles_for(session.engine, healer).is_empty()
	))

	h.controller.confirm_tile(session.state.tile_of(medic))
	_check.call("healers: the medic's selection shows support tiles, no attack tiles", (
			h.controller.get_stage() == MOVE
			and view.get_attack_overlay().shown_tiles().is_empty()
			and not view.get_support_overlay().shown_tiles().is_empty()
			and view.get_support_overlay().shown_tiles() == TurnInputModel.support_tiles(
					session, medic
			)
	), "%d support tiles" % [view.get_support_overlay().shown_tiles().size()])
	h.controller.step_back()

	var staff: Array = _find(session, STAFF, medic)
	var staff_ok: bool = false
	var detail: String = "the medic has no Staff target"
	if not staff.is_empty() and _open_target(h, staff):
		var tiles: Array[Vector2i] = []
		for target: TurnInputModel.TargetOption in h.controller.get_target_list().targets():
			tiles.append(target.tile)
		staff_ok = (
				view.get_attack_overlay().shown_tiles().is_empty()
				and view.get_support_overlay().shown_tiles() == tiles
		)
		detail = "%d targets" % [tiles.size()]
		while h.controller.step_back():
			pass
	_check.call("healers: the medic's Staff targets show purple, not red", staff_ok, detail)

	h.controller.confirm_tile(session.state.tile_of(healer))
	_check.call("healers: the Hedge Healer's range shows purple only", (
			h.controller.get_shown_enemies() == PackedStringArray([healer])
			and view.get_enemy_range_overlay().shown_tiles().is_empty()
			and not view.get_enemy_support_overlay().shown_tiles().is_empty()
	), "%d purple" % [view.get_enemy_support_overlay().shown_tiles().size()])
	h.controller.confirm_tile(session.state.tile_of(healer))

	h.controller.toggle_danger_zone()
	var zone: DangerZone = DangerZone.compute(session.engine)
	var others: Dictionary[Vector2i, bool] = {}
	for enemy_id: String in zone.enemy_ids:
		if enemy_id != healer:
			for tile: Vector2i in zone.tiles_of(enemy_id):
				others[tile] = true
	var shown: Array[Vector2i] = view.get_danger_overlay().shown_tiles()
	var only_others: bool = shown.size() == others.size()
	for tile: Vector2i in shown:
		only_others = only_others and others.has(tile)
	_check.call("healers: the danger zone holds no tile of the Hedge Healer's", (
			zone.tiles_of(healer).is_empty() and only_others
	), "%d shown, %d from the others" % [shown.size(), others.size()])
	h.close()


# --- Fixtures --------------------------------------------------------------------------------


func _harness() -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("targeting: the M1 battle begins", false, "begin_battle gave no battle")
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


# Seat 0 gets a Mend rune (heal 10 on the unit cast on) and one of its units loses WOUND HP.
func _give_mend_rune(session: CombatSession) -> void:
	var state: CombatState = session.state
	var rune_id: String = session.ids.next_rune_id("Mend")
	state.rune_slots[0] = PackedStringArray([rune_id])
	var amount: Constant = Constant.new()
	amount.value = 10.0
	var mend: GainResource = GainResource.new()
	mend.pool = GainResource.Pool.HP
	mend.amount = amount
	mend.target = CommandTarget.new()
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = "test_mend"
	definition.trigger = EffectTerms.Trigger.ALWAYS
	definition.operations.append(mend)
	session.engine.register(EffectInstance.new(
			session.ids.next_effect_id("Mend"), definition, EffectOwner.for_rune(rune_id, 0),
			Modifier.SourceKind.RUNE
	))
	var wounded: String = state.units_of(PLAYER)[0]
	state.set_hp(wounded, state.get_hp(wounded) - WOUND)


# For the first option of each kind any acting unit is offered, into found: why its TargetList
# isn't exactly what the validator accepts there and then, or empty when it is. An Item counts
# only with a target other than its user.
func _collect(session: CombatSession, found: Dictionary[int, String]) -> void:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				if found.has(option.kind) or not option.kind in [ATTACK, STAFF, ITEM, SHOVE, RUNE]:
					continue
				if option.kind == ITEM and not _has_other_target(option, unit_id):
					continue
				found[option.kind] = _list_mismatch(session, unit_id, path, option)


# Why option's TargetList differs from what the validator accepts for unit_id after path; empty
# when they agree and every listed command validates.
static func _list_mismatch(
		session: CombatSession,
		unit_id: String,
		path: Array[Vector2i],
		option: TurnInputModel.ActionOption
) -> String:
	var list: TargetList = TargetList.build(option)
	var listed: PackedStringArray = _listed_keys(list)
	var accepted: PackedStringArray = _accepted_keys(session, unit_id, path, option.kind)
	var rejected: PackedStringArray = []
	for target: TurnInputModel.TargetOption in list.targets():
		for command: Command in target.commands:
			var reason: String = command.validate(session)
			if not reason.is_empty():
				rejected.append(reason)
	if not listed.is_empty() and listed == accepted and rejected.is_empty():
		return ""
	return "listed %s, accepted %s, rejected %s" % [listed, accepted, rejected]


static func _has_other_target(option: TurnInputModel.ActionOption, unit_id: String) -> bool:
	for target: TurnInputModel.TargetOption in option.targets:
		if target.target_id != unit_id:
			return true
	return false


# The first [unit_id, path, option] of one of kinds with at least min_targets targets; empty when
# none.
func _find_with_targets(
		session: CombatSession, kinds: Array[TurnInputModel.ActionKind], min_targets: int
) -> Array:
	for kind: TurnInputModel.ActionKind in kinds:
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			var pick: Array = _find(session, kind, unit_id, min_targets)
			if not pick.is_empty():
				return pick
	return []


# The first [unit_id, path, option] of kind for unit_id with at least min_targets targets.
func _find(
		session: CombatSession,
		kind: TurnInputModel.ActionKind,
		unit_id: String,
		min_targets: int = 1
) -> Array:
	if not TurnInputModel.can_act(session, unit_id):
		return []
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				session, unit_id, path
		):
			if option.kind == kind and option.targets.size() >= min_targets:
				return [unit_id, path, option]
	return []


# Walks the controller from IDLE into TARGET for pick by accept and the menu's own row. Returns
# whether TARGET opened.
func _open_target(h: TurnInputCases.Harness, pick: Array) -> bool:
	var unit_id: String = pick[0]
	var path: Array[Vector2i] = []
	var walk: Array = pick[1]
	path.assign(walk)
	var option: TurnInputModel.ActionOption = pick[2]
	var end: Vector2i = h.session.state.tile_of(unit_id) if path.is_empty() else path[-1]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(end)
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		return false
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == option.kind:
			menu.get_rows()[i].pressed.emit()
			break
	return h.controller.get_stage() == TARGET and h.controller.get_target_list() != null


# Every acting unit waits where it stands, then End Turn.
func _wait_phase(h: TurnInputCases.Harness) -> void:
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	if not h.session.is_finished:
		_send(h, EndTurnCommand.new(0))


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


# Why the outlines don't show list: one mark per target on its tile, coloured by the target's
# side, exactly the current one strong and fully opaque.
func _mark_problems(h: TurnInputCases.Harness, list: TargetList) -> PackedStringArray:
	var problems: PackedStringArray = []
	var marks: Array[TargetMark] = h.view.get_target_marks()
	if marks.size() != list.size():
		problems.append("%d marks for %d targets" % [marks.size(), list.size()])
		return problems
	var targets: Array[TurnInputModel.TargetOption] = list.targets()
	var strong: int = 0
	for i: int in marks.size():
		var mark: TargetMark = marks[i]
		var side: CombatFact.CombatSide = h.session.state.side_of(targets[i].target_id)
		var colour: Color = mark.color_of(side)
		var tint: Color = mark.get_tint()
		var is_current: bool = i == list.current_index()
		if mark.tile != targets[i].tile or mark.side != side or mark.is_current != is_current:
			problems.append("mark %d is for the wrong target" % [i])
		if not Color(tint, 1.0).is_equal_approx(Color(colour, 1.0)):
			problems.append("mark %d is %s, its side's colour is %s" % [i, tint, colour])
		var style: StringName = TargetMark.CURRENT_STYLE if is_current else TargetMark.OTHER_STYLE
		if mark.get_style() != style:
			problems.append("mark %d has style %s" % [i, mark.get_style()])
		if is_current:
			strong += 1
			if not is_equal_approx(tint.a, colour.a):
				problems.append("the current mark isn't opaque")
		elif tint.a >= colour.a:
			problems.append("mark %d is as strong as the current one" % [i])
	if strong != 1:
		problems.append("%d strong marks" % [strong])
	var player_colour: Color = marks[0].color_of(PLAYER)
	var enemy_colour: Color = marks[0].color_of(ENEMY)
	if (
			not player_colour.is_equal_approx(Color.NAVY_BLUE)
			or not enemy_colour.is_equal_approx(Color.DARK_RED)
	):
		problems.append("side colours aren't Godot_FE's navy and dark red")
	return problems


# Each listed command as "target|weapon" (a rune's as "rune>target|"), sorted.
static func _listed_keys(list: TargetList) -> PackedStringArray:
	var keys: PackedStringArray = []
	for target: TurnInputModel.TargetOption in list.targets():
		for command: Command in target.commands:
			keys.append(_key(target.target_id, command))
	keys.sort()
	return keys


# Every command of kind for unit_id after path the validator accepts, tried on every unit on the
# map (and the user's own tile for a staff) with each weapon, as _listed_keys writes them.
static func _accepted_keys(
		session: CombatSession,
		unit_id: String,
		path: Array[Vector2i],
		kind: TurnInputModel.ActionKind
) -> PackedStringArray:
	var state: CombatState = session.state
	var unit: CombatUnitState = state.unit(unit_id)
	var found: Dictionary[String, bool] = {}
	if kind == RUNE:
		for rune_id: String in state.rune_slots.get(0, PackedStringArray()):
			for target_id: String in state.unit_ids():
				var cast: CastRuneCommand = CastRuneCommand.new(0, rune_id, target_id)
				if cast.validate(session).is_empty():
					found[_key(target_id, cast)] = true
		return _sorted_keys(found)
	var actions: Dictionary[int, UnitTurnCommand.Action] = {
		ATTACK: UnitTurnCommand.Action.ATTACK,
		STAFF: UnitTurnCommand.Action.STAFF,
		ITEM: UnitTurnCommand.Action.ITEM,
		SHOVE: UnitTurnCommand.Action.SHOVE,
	}
	var weapons: PackedStringArray = [""]
	if kind == ATTACK and not unit.stowed_weapon_id.is_empty():
		if unit.stowed_weapon_id != unit.equipped_weapon_id:
			weapons.append(unit.stowed_weapon_id)
	var targets: PackedStringArray = state.unit_ids()
	if kind == STAFF:
		targets.append("")
	for target_id: String in targets:
		if kind == SHOVE and target_id == unit_id:
			continue
		for weapon_id: String in weapons:
			var command: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, actions[kind], target_id, path
			)
			command.weapon_id = weapon_id
			if kind == ITEM:
				command.item_id = unit.pouch_item_id
			if command.validate(session).is_empty():
				found[_key(unit_id if target_id.is_empty() else target_id, command)] = true
	return _sorted_keys(found)


static func _key(target_id: String, command: Command) -> String:
	var cast: CastRuneCommand = command as CastRuneCommand
	if cast != null:
		return "%s>%s|" % [cast.rune_id, target_id]
	return "%s|%s" % [target_id, TargetList.weapon_key(command)]


static func _sorted_keys(found: Dictionary[String, bool]) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray(found.keys())
	keys.sort()
	return keys


static func _fake_target(
		target_id: String, tile: Vector2i, weapons: Array[String]
) -> TurnInputModel.TargetOption:
	var option: TurnInputModel.TargetOption = TurnInputModel.TargetOption.new()
	option.target_id = target_id
	option.tile = tile
	for weapon_id: String in weapons:
		var command: UnitTurnCommand = UnitTurnCommand.new(
				0, "unit:fake", UnitTurnCommand.Action.ATTACK, target_id
		)
		command.weapon_id = weapon_id
		option.commands.append(command)
	option.command = option.commands[0]
	return option


static func _single_option(target: TurnInputModel.TargetOption) -> TurnInputModel.ActionOption:
	var option: TurnInputModel.ActionOption = TurnInputModel.ActionOption.new(ATTACK)
	option.targets.append(target)
	return option


static func _unit_of_type(
		session: CombatSession, side: CombatFact.CombatSide, label: String
) -> String:
	for unit_id: String in session.state.units_of(side):
		if session.describe(unit_id).contains("(%s)" % [label]):
			return unit_id
	return ""


# A command as text, to compare two by value.
static func _wire(command: Command) -> String:
	var turn: UnitTurnCommand = command as UnitTurnCommand
	if turn != null:
		return "%s %s %s '%s' '%s' %s" % [
			turn.actor_id, turn.action, turn.target_id, turn.weapon_id, turn.item_id, turn.path,
		]
	var cast: CastRuneCommand = command as CastRuneCommand
	if cast != null:
		return "rune %s on %s" % [cast.rune_id, cast.target_id]
	return "none"


static func _is_purple(colour: Color) -> bool:
	return colour.b > colour.g + 0.3 and colour.r > colour.g + 0.3 and colour.b > colour.r


static func _is_red(colour: Color) -> bool:
	return colour.r > colour.g + 0.3 and colour.r > colour.b + 0.3


static func _expect_disjoint(
		problems: PackedStringArray, label: String, one: TileOverlay, other: TileOverlay
) -> void:
	var tiles: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in other.shown_tiles():
		tiles[tile] = true
	for tile: Vector2i in one.shown_tiles():
		if tiles.has(tile):
			problems.append("%s: %s is both" % [label, tile])
			return


# --- Input -----------------------------------------------------------------------------------


func _press(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


# Where tile's centre is on screen, with the camera's scroll applied as a frame would.
func _screen_point(h: TurnInputCases.Harness, tile: Vector2i) -> Vector2:
	var camera: Camera2D = _root.get_viewport().get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	return h.view.get_global_transform_with_canvas() * h.view.tile_to_position(tile)


# Whether a click at tile's centre reaches the board: on screen, and no visible widget covers it.
func _is_clear(h: TurnInputCases.Harness, tile: Vector2i) -> bool:
	var point: Vector2 = _screen_point(h, tile)
	if not _root.get_viewport().get_visible_rect().has_point(point):
		return false
	var covers: Array[Control] = [h.bar, h.swap, h.message]
	if h.host.top() != null:
		covers.append(h.host.top())
	for widget: Control in covers:
		if widget.is_visible_in_tree() and widget.get_global_rect().has_point(point):
			return false
	return true


func _hover(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _screen_point(h, tile)
	motion.global_position = motion.position
	_root.get_viewport().push_input(motion, true)


func _click(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	var point: Vector2 = _screen_point(h, tile)
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		_root.get_viewport().push_input(click, true)
