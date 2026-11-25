# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     335_battle_detail_keywords.gd
# Author:
# Created:  November 22, 2026
# Modified: November 25, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Keyword tooltips in the battle by pad ([EffectText]): the first player unit's detail with the
## d-pad on its first row with keywords, that row's column beside it; an enemy's signature move in
## its detail, the d-pad on it (an enemy whose class has one, else the first enemy's detail with
## the Stone Golem's Fortify staged into its view, said in a NOTE); and the rune menu the action
## menu's Rune opens, a row focused by the d-pad, its column beside it (with no rune to cast, a
## menu of the catalog's runes opened in the panel column, said in a NOTE). Nothing in the battle
## is changed, so it ends idle in the player phase as it began.[br]
## Needs: the battle started (300_battle_start); runs after 330_battle_details.

const RUNE_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/rune_menu.tscn")

# The enemy class whose signature move is staged when no enemy on the board has one.
const STAGED_CLASS: String = "stone_golem"

# The runes a staged menu lists: the catalog's with keywords of more than one colour group.
const STAGED_RUNES: PackedStringArray = ["mend", "aegis", "clarity"]

# The most d-pad presses a step through a panel takes before it gives up.
const MAX_STEPS: int = 16


func run() -> bool:
	var controller: BattleController = battle_controller()
	var session: CombatSession = battle_view().get_session()
	await _player_detail(controller, session)
	await _signature_detail(controller, session)
	await _rune_menu(controller, session)
	return true


# The first player unit's detail, the d-pad on its first row with keywords.
func _player_detail(controller: BattleController, session: CombatSession) -> void:
	if not controller.request_unit_detail(first_player(session)):
		fail("the player unit's detail didn't open")
		return
	await frames(SETTLE_FRAMES)
	var panel: UnitDetailPanel = controller.get_detail_panel()
	var target: Control = null
	for row: Control in panel.get_focus_rows():
		if _keywords_of(row) > 0:
			target = row
			break
	if target == null or not _step_to(target):
		fail("no row with keywords took the d-pad's focus")
	await frames(SETTLE_FRAMES)
	await capture("battle_detail_pad_row")
	controller.step_back()
	await frames(SETTLE_FRAMES)


# An enemy's signature move in its detail, the d-pad on it.
func _signature_detail(controller: BattleController, session: CombatSession) -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	if enemies.is_empty():
		fail("no enemy on the board for the signature shot")
		return
	var signed: String = ""
	for enemy_id: String in enemies:
		var enemy_class: EnemyClassDefinition = catalog.enemy_class(
				session.state.unit_type_of(enemy_id)
		)
		if enemy_class != null and enemy_class.signature_move != null:
			signed = enemy_id
			break
	var shown: String = signed if not signed.is_empty() else enemies[0]
	if not controller.request_unit_detail(shown):
		fail("the enemy's detail didn't open")
		return
	var panel: UnitDetailPanel = controller.get_detail_panel()
	if signed.is_empty():
		var staged: EnemyClassDefinition = catalog.enemy_class(STAGED_CLASS)
		var view: UnitDetailViewModel = UnitDetailViewModel.build(session, shown)
		view.signature_name = staged.signature_name
		view.signature_text = staged.signature_move.describe()
		view.signature_marked_text = staged.signature_move.describe_marked()
		panel.show_detail(view)
		note("no enemy on the board has a signature move: %s's Fortify staged into %s's view" % [
			STAGED_CLASS, BattleText.name_of(session, shown),
		])
	await frames(SETTLE_FRAMES)
	if not _step_to(panel.get_enemy_section()):
		fail("the signature move didn't take the d-pad's focus")
	await frames(SETTLE_FRAMES)
	await capture("battle_detail_signature")
	controller.step_back()
	await frames(SETTLE_FRAMES)


# The action menu's Rune on the first acting unit, a row focused by the d-pad; staged on a layer
# of its own when that unit has no rune to cast.
func _rune_menu(controller: BattleController, session: CombatSession) -> void:
	var caster: String = ""
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if not TurnInputModel.runes_for_unit(session, 0, unit_id).is_empty():
			caster = unit_id
			break
	if caster.is_empty():
		await _staged_rune_menu()
		return
	var tile: Vector2i = session.state.tile_of(caster)
	controller.move_cursor(tile)
	controller.confirm_tile(tile)
	controller.confirm_tile(tile)
	await frames(SETTLE_FRAMES)
	var actions: ActionMenu = controller.panel_host.top() as ActionMenu
	if actions == null:
		fail("the action menu didn't open on %s" % [caster])
		_back_to_idle(controller)
		return
	var options: Array[TurnInputModel.ActionOption] = actions.get_options()
	for i: int in options.size():
		if options[i].kind == TurnInputModel.ActionKind.RUNE:
			actions.get_rows()[i].pressed.emit()
			break
	await frames(SETTLE_FRAMES)
	var menu: RuneMenu = controller.panel_host.top() as RuneMenu
	if menu == null:
		fail("the rune menu didn't open")
	else:
		_press_pad(JOY_BUTTON_DPAD_DOWN)
		_press_pad(JOY_BUTTON_DPAD_UP)
		await frames(SETTLE_FRAMES)
		await capture("battle_rune_menu_keywords")
	_back_to_idle(controller)
	await frames(SETTLE_FRAMES)


# A rune menu of STAGED_RUNES in the panel column, where the controller opens one, its first row
# focused as the host focuses it.
func _staged_rune_menu() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var options: Array[TurnInputModel.RuneOption] = []
	for rune_id: String in STAGED_RUNES:
		var definition: RuneDefinition = catalog.rune(rune_id)
		if definition == null:
			continue
		var option: TurnInputModel.RuneOption = TurnInputModel.RuneOption.new()
		option.rune_id = rune_id
		option.label = definition.display_name
		option.text = " ".join(definition.describe())
		option.marked_text = " ".join(definition.describe_marked())
		options.append(option)
	var host: PanelHost = battle_controller().panel_host
	var menu: RuneMenu = host.open(RUNE_MENU_SCENE, options) as RuneMenu
	if menu == null:
		fail("the staged rune menu didn't open")
		return
	note("no acting unit has a rune to cast: the rune menu staged in the panel column with %s" % [
		", ".join(STAGED_RUNES),
	])
	await frames(SETTLE_FRAMES)
	await capture("battle_rune_menu_keywords")
	host.back()
	await frames(SETTLE_FRAMES)


# Presses the d-pad down from the panel's first focus until target holds focus. Returns whether it
# got there.
func _step_to(target: Control) -> bool:
	for _step: int in MAX_STEPS:
		if tree.root.gui_get_focus_owner() == target:
			return true
		_press_pad(JOY_BUTTON_DPAD_DOWN)
	return tree.root.gui_get_focus_owner() == target


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = is_down
		tree.root.push_input(event, true)


# Steps back until the controller is idle again, at most a few stages.
func _back_to_idle(controller: BattleController) -> void:
	for _step: int in 4:
		if controller.get_stage() == BattleController.Stage.IDLE:
			return
		controller.step_back()


static func _keywords_of(row: Control) -> int:
	var count: int = 0
	for node: Node in row.find_children("*", "RichTextLabel", true, false):
		var text: EffectText = node as EffectText
		if text != null:
			count += text.get_keyword_ids().size()
	return count
