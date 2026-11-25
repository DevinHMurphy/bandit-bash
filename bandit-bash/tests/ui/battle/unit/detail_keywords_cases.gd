# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_keywords_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 25, 2026
# ==============================================================================

extends "res://tests/ui/battle/unit/unit_detail_cases.gd"
## Keyword tooltips in unit detail by keyboard and pad, for the ui/input suite (docs/design/
## keywords.md): the Drengr's detail opened with Close focused; the d-pad's down stepping focus
## through every row with text (gear first, then traits and heirlooms), each showing its own
## keywords' column and no other row any, up stepping back to Close with none and the body at its
## top; the arrow keys doing the same; up and down listed in DETAIL; the pad's A on a row closing
## the detail as Close does; stepping to another unit putting focus back on Close; mouse focus on a
## row showing none while a hover still shows its keyword; and an enemy's signature move (the Stone
## Golem's Fortify, on an AI world) carrying marked text whose words are its plain text, shown in an
## [EffectText] that is a focus stop showing its keywords. The rig and drivers are
## unit_detail_cases.gd's.

const AiWorld = preload("res://tests/enemies/ai_world.gd")

# An enemy class with a signature move, and the player placed beside it.
const SIGNED_CLASS: String = "stone_golem"
const SIGNED_TILE: Vector2i = Vector2i(3, 3)
const FOE_TILE: Vector2i = Vector2i(4, 3)

const PAD_DOWN: JoyButton = JOY_BUTTON_DPAD_DOWN
const PAD_UP: JoyButton = JOY_BUTTON_DPAD_UP
const PAD_ACCEPT: JoyButton = JOY_BUTTON_A


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("detail keywords: the M1 map definition loads", false, M1_DEFINITION)
		return
	var rig: Rig = _rig()
	if rig == null:
		return
	_test_pad_reach(rig)
	_test_keys_and_hints(rig)
	_test_accept_and_stepping(rig)
	_test_mouse_focus(rig)
	rig.close()
	_test_signature()


# The d-pad steps focus Close -> each row with text -> back to Close; each focused row shows its
# own keywords and no other row any; back at Close none shows and the body is at its top.
func _test_pad_reach(rig: Rig) -> void:
	var panel: UnitDetailPanel = _open_drengr(rig)
	if panel == null:
		return
	var rows: Array[Control] = panel.get_focus_rows()
	var effect_rows: int = panel.get_view().traits.size() + panel.get_view().heirlooms.size()
	var order_ok: bool = not rows.is_empty() and rows[0] is DetailGearRow
	var counted: int = 0
	for row: Control in rows:
		if row is DetailEffectRow:
			counted += 1
	_check.call("detail keywords: the focus rows are the gear with text, then every effect row", (
			order_ok and counted == effect_rows and effect_rows > 0
	), "%d rows, %d effect rows of %d" % [rows.size(), counted, effect_rows])
	var problems: PackedStringArray = []
	var keyworded: int = 0
	for i: int in rows.size():
		_press_pad(PAD_DOWN)
		var focused: Control = _root.get_viewport().gui_get_focus_owner()
		if focused != rows[i]:
			problems.append("down %d focused %s" % [i + 1, focused])
			continue
		var text: EffectText = _text_of(rows[i])
		if _shown_ids(text) != text.get_keyword_ids():
			problems.append("%s shows %s of %s" % [rows[i].name, _shown_ids(text), (
				text.get_keyword_ids()
			)])
		if not text.get_keyword_ids().is_empty():
			keyworded += 1
		var others: PackedStringArray = _rows_showing(rows, rows[i])
		if not others.is_empty():
			problems.append("with %s focused, %s show tooltips" % [rows[i].name, others])
	_check.call("detail keywords (pad): down focuses each row with text, showing its keywords", (
			problems.is_empty() and keyworded > 0
	), "%s; %d rows with keywords" % ["; ".join(problems), keyworded])
	for _i: int in rows.size():
		_press_pad(PAD_UP)
	var back: Control = _root.get_viewport().gui_get_focus_owner()
	_check.call("detail keywords (pad): up steps back to Close, no tooltip, the body at its top", (
			back == panel.get_close_button()
			and _rows_showing(rows, null).is_empty()
			and panel.get_scroll() == 0
	), "focus %s, showing %s, scroll %d" % [back, _rows_showing(rows, null), panel.get_scroll()])
	rig.h.controller.step_back()


# The arrow keys step the same rows; DETAIL lists up and down while the detail has focus rows.
func _test_keys_and_hints(rig: Rig) -> void:
	var panel: UnitDetailPanel = _open_drengr(rig)
	if panel == null:
		return
	var rows: Array[Control] = panel.get_focus_rows()
	var live: Array[StringName] = rig.h.controller.get_live_actions()
	_press_key(KEY_DOWN)
	var first: Control = _root.get_viewport().gui_get_focus_owner()
	var shown: PackedStringArray = _shown_ids(_text_of(rows[0])) if not rows.is_empty() else []
	_press_key(KEY_UP)
	var back: Control = _root.get_viewport().gui_get_focus_owner()
	_check.call("detail keywords (keys): Down focuses the first row with its keywords, Up Close", (
			not rows.is_empty()
			and first == rows[0]
			and shown == _text_of(rows[0]).get_keyword_ids()
			and back == panel.get_close_button()
	), "first %s showing %s, back %s" % [first, shown, back])
	_check.call("detail keywords (hints): DETAIL lists up and down with focus rows to step", (
			live.has(&"ui_up") and live.has(&"ui_down")
	), str(live))
	rig.h.controller.step_back()


# E on a focused row shows the next unit with focus back on Close and no row's tooltips left; A on
# a focused row closes the detail, IDLE as it was before it opened, as Close does.
func _test_accept_and_stepping(rig: Rig) -> void:
	var drengr: String = _unit_of_type(rig.h.session, "drengr")
	rig.h.controller.move_cursor(rig.h.session.state.tile_of(drengr))
	var before: String = _state_line(rig)
	var panel: UnitDetailPanel = _open_drengr(rig)
	if panel == null:
		return
	_press_pad(PAD_DOWN)
	_press_pad(PAD_DOWN)
	var stepped_rows: Array[Control] = panel.get_focus_rows()
	_press_key(KEY_E)
	var stepped: UnitDetailPanel = rig.h.controller.get_detail_panel()
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	var leftover: PackedStringArray = _rows_showing(stepped_rows, null)
	_check.call("detail keywords: stepping to another unit puts focus back on Close", (
			stepped != null
			and focus == stepped.get_close_button()
			and leftover.is_empty()
	), "focus %s, showing %s" % [focus, leftover])
	_press_pad(PAD_DOWN)
	var on_row: bool = stepped != null and stepped.get_focus_rows().has(
			_root.get_viewport().gui_get_focus_owner()
	)
	_press_pad(PAD_ACCEPT)
	var after: String = _state_line(rig)
	_check.call("detail keywords (pad): A on a focused row closes the detail, as Close does", (
			on_row and rig.h.controller.get_stage() == IDLE and after == before
	), "on a row %s; before %s, after %s" % [on_row, before, after])


# Mouse focus (hidden) on a row shows none; hovering its keyword still shows that one.
func _test_mouse_focus(rig: Rig) -> void:
	var panel: UnitDetailPanel = _open_drengr(rig)
	if panel == null:
		return
	var row: Control = _first_keyworded(panel.get_focus_rows())
	if row == null:
		_check.call("detail keywords (mouse): a row with keywords", false, "none")
		rig.h.controller.step_back()
		return
	var text: EffectText = _text_of(row)
	row.grab_focus(true)
	var on_focus: PackedStringArray = _shown_ids(text)
	var id: String = text.get_keyword_ids()[0]
	text.meta_hover_started.emit(id)
	var on_hover: PackedStringArray = _shown_ids(text)
	text.meta_hover_ended.emit(id)
	_check.call("detail keywords (mouse): mouse focus shows none; a hover shows its own", (
			on_focus.is_empty() and on_hover == PackedStringArray([id])
	), "on focus %s, on hover %s" % [on_focus, on_hover])
	panel.get_close_button().grab_focus()
	rig.h.controller.step_back()


# The Stone Golem's Fortify: marked text whose words are its plain text, in the enemy section's
# EffectText, which is a focus stop showing its keywords on key focus and none on mouse focus.
func _test_signature() -> void:
	var world: AiWorld = AiWorld.new(_catalog, _plain_rows(8, 8))
	world.add_enemy("e1", SIGNED_CLASS, SIGNED_TILE)
	world.add_player("p1", FOE_TILE)
	world.session.open_battle()
	var view: UnitDetailViewModel = UnitDetailViewModel.build(world.session, "e1")
	var marked: String = "" if view == null else view.signature_marked_text
	_check.call("detail keywords (signature): its text marked, its words the plain text", (
			view != null
			and marked.contains(EffectTerms.KEYWORD_OPEN)
			and EffectTerms.plain_text(marked) == view.signature_text
			and not view.signature_text.is_empty()
	), "'%s' / '%s'" % [marked, "" if view == null else view.signature_text])
	if view == null:
		return
	var layer: CanvasLayer = CanvasLayer.new()
	_root.add_child(layer)
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	layer.add_child(panel)
	panel.show_detail(view)
	var section: DetailEnemySection = panel.get_enemy_section()
	var text: EffectText = section.get_signature_text()
	var lines: PackedStringArray = section.get_texts()
	_check.call("detail keywords (signature): an EffectText shows it; get_texts plain", (
			text.marked_text == marked
			and text.get_plain_text() == view.signature_text
			and lines[3] == view.signature_text
	), "'%s'; lines %s" % [text.marked_text, lines])
	var is_stop: bool = panel.get_focus_rows().has(section)
	section.grab_focus()
	var on_key: PackedStringArray = _shown_ids(text)
	section.release_focus()
	section.grab_focus(true)
	var on_mouse: PackedStringArray = _shown_ids(text)
	section.release_focus()
	_check.call("detail keywords (signature): a focus stop; keys show its keywords, mouse none", (
			is_stop
			and on_key == text.get_keyword_ids()
			and not on_key.is_empty()
			and on_mouse.is_empty()
	), "stop %s, key %s of %s, mouse %s" % [is_stop, on_key, text.get_keyword_ids(), on_mouse])
	# Freed now: the cases after it run in this frame, and its dim would take their clicks.
	_root.remove_child(layer)
	layer.free()


# Opens the Drengr's detail from IDLE with Close focused; null, with a failed check, when it can't.
func _open_drengr(rig: Rig) -> UnitDetailPanel:
	var drengr: String = _unit_of_type(rig.h.session, "drengr")
	rig.h.controller.move_cursor(rig.h.session.state.tile_of(drengr))
	rig.h.controller.request_unit_detail()
	var problem: String = _open_problem(rig, drengr)
	if not problem.is_empty():
		_check.call("detail keywords: the Drengr's detail opens on Close", false, problem)
		return null
	return rig.h.controller.get_detail_panel()


# The names of rows (but skip) whose text shows any tooltip.
func _rows_showing(rows: Array[Control], skip: Control) -> PackedStringArray:
	var showing: PackedStringArray = []
	for row: Control in rows:
		var text: EffectText = _text_of(row)
		if row != skip and text != null and not text.get_shown_tooltips().is_empty():
			showing.append(row.name)
	return showing


func _first_keyworded(rows: Array[Control]) -> Control:
	for row: Control in rows:
		var text: EffectText = _text_of(row)
		if text != null and not text.get_keyword_ids().is_empty():
			return row
	return null


# The EffectText a focus row holds.
static func _text_of(row: Control) -> EffectText:
	if row is DetailGearRow:
		return (row as DetailGearRow).get_effect_text()
	if row is DetailEffectRow:
		return (row as DetailEffectRow).get_effect_text()
	if row is DetailEnemySection:
		return (row as DetailEnemySection).get_signature_text()
	return null


static func _shown_ids(text: EffectText) -> PackedStringArray:
	var ids: PackedStringArray = []
	if text == null:
		return ids
	for tooltip: KeywordTooltip in text.get_shown_tooltips():
		ids.append(tooltip.keyword_id)
	return ids


# width × height plain tiles, for the AI world (mini_boss_cases.gd's form).
static func _plain_rows(width: int, height: int) -> Array[String]:
	var row: PackedStringArray = []
	for _x: int in width:
		row.append("plain")
	var rows: Array[String] = []
	for _y: int in height:
		rows.append(" ".join(row))
	return rows
