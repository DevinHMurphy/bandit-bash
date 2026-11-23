# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_keywords_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tests/ui/battle/input/rune_cases.gd"
## Keyword text in the battle's rune menu, for the ui/input suite (docs/design/keywords.md): every
## rune's [member TurnInputModel.RuneOption.marked_text] and
## [member TurnInputModel.HeldRune.marked_text] the catalog's marked text, its words the plain
## text; the menu, opened by the pad, showing the focused rune's marked text in an [EffectText]
## (its get_text() the plain words) with its keywords as one column beside the menu while a row
## holds pad focus, following the d-pad from row to row; a hovered keyword adding none; focus
## leaving the menu hiding it; mouse focus on a row showing none, a hover then showing its own.
## The harness and drivers are rune_cases.gd's.


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("rune keywords: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_marked_text()
	_test_menu_column()


# Each rune's marked text is the catalog's describe_marked(), its words describe()'s, on the
# options the menu lists and on the runes the bar holds.
func _test_marked_text() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var problems: PackedStringArray = []
	var tagged: int = 0
	for option: TurnInputModel.RuneOption in TurnInputModel.rune_options(h.session, 0):
		var definition: RuneDefinition = _catalog.rune(_definition_id(h.session, option))
		var marked: String = " ".join(definition.describe_marked())
		if option.marked_text != marked or EffectTerms.plain_text(marked) != option.text:
			problems.append("%s option: '%s'" % [option.label, option.marked_text])
		if marked.contains(EffectTerms.KEYWORD_OPEN):
			tagged += 1
	for held: TurnInputModel.HeldRune in TurnInputModel.held_runes(h.session, 0):
		var definition: RuneDefinition = _catalog.rune(held.definition_id)
		var marked: String = " ".join(definition.describe_marked())
		if held.marked_text != marked or EffectTerms.plain_text(marked) != held.text:
			problems.append("%s held: '%s'" % [held.label, held.marked_text])
	_check.call("rune keywords: each rune's marked text is the catalog's, its words the plain", (
			problems.is_empty() and tagged > 0
	), "%s; %d tagged" % ["; ".join(problems), tagged])
	h.close()


# The pad opens the menu on its first row: the column shows that rune's keywords beside the menu;
# the d-pad moves it with focus; a hover adds none; focus leaving hides it; mouse focus shows none.
func _test_menu_column() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	if not _open_rune_menu(h, Device.PAD, _caster(h)):
		_check.call("rune keywords: the pad opens the rune menu", false, (
				str(h.controller.get_stage())
		))
		h.close()
		return
	var menu: RuneMenu = h.host.top() as RuneMenu
	var text: EffectText = menu.get_effect_text()
	var options: Array[TurnInputModel.RuneOption] = menu.get_options()
	var rows: Array[Button] = menu.get_rows()
	var problems: PackedStringArray = []
	for i: int in rows.size():
		if i > 0:
			_press(Device.PAD, &"ui_down")
		if not rows[i].has_focus():
			problems.append("row %d not focused" % [i])
			continue
		if text.marked_text != options[i].marked_text or menu.get_text() != options[i].text:
			problems.append("%s shows '%s'" % [options[i].label, text.marked_text])
		if _shown_ids(text) != text.get_keyword_ids():
			problems.append("%s's column %s of %s" % [
				options[i].label, _shown_ids(text), text.get_keyword_ids(),
			])
	_check.call("rune keywords (pad): each focused rune's marked text and its keyword column", (
			problems.is_empty() and rows.size() > 1
	), "; ".join(problems))

	# Back on the first row (Mend, with keywords; Recall, last, has none).
	for _i: int in rows.size() - 1:
		_press(Device.PAD, &"ui_up")
	var column: Rect2 = text.get_tooltip_column().get_global_rect()
	var box: Rect2 = menu.get_global_rect()
	var is_beside: bool = (
			column.position.x >= box.end.x - 0.5 or column.end.x <= box.position.x + 0.5
	)
	var ids: PackedStringArray = text.get_keyword_ids()
	var hovered: PackedStringArray = []
	if not ids.is_empty():
		text.meta_hover_started.emit(ids[0])
		hovered = _shown_ids(text)
		text.meta_hover_ended.emit(ids[0])
	_check.call("rune keywords (pad): the column sits beside the menu; a hover adds none", (
			not ids.is_empty() and is_beside and hovered == ids and _shown_ids(text) == ids
	), "column %s, menu %s; hovered %s of %s" % [column, box, hovered, ids])

	var outside: Button = Button.new()
	_root.add_child(outside)
	outside.grab_focus()
	var after_leaving: PackedStringArray = _shown_ids(text)
	rows[0].grab_focus(true)
	var on_mouse: PackedStringArray = _shown_ids(text)
	var first: PackedStringArray = text.get_keyword_ids()
	var on_hover: PackedStringArray = []
	if not first.is_empty():
		text.meta_hover_started.emit(first[0])
		on_hover = _shown_ids(text)
		text.meta_hover_ended.emit(first[0])
	_check.call("rune keywords: focus leaving hides it; mouse focus shows none, a hover its own", (
			after_leaving.is_empty()
			and on_mouse.is_empty()
			and not first.is_empty()
			and on_hover == PackedStringArray([first[0]])
	), "after leaving %s, mouse %s, hover %s" % [after_leaving, on_mouse, on_hover])
	outside.get_parent().remove_child(outside)
	outside.free()
	h.close()


static func _shown_ids(text: EffectText) -> PackedStringArray:
	var ids: PackedStringArray = []
	for tooltip: KeywordTooltip in text.get_shown_tooltips():
		ids.append(tooltip.keyword_id)
	return ids
