# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_bar_keywords_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/ui/battle/input/rune_cases.gd"
## Keyword text in the HUD rune bar, for the ui/input suite (docs/design/keywords.md): the pointed
## rune's line is an [EffectText], "Name: " and the rune's marked text, its words the plain line
## the bar always showed, its keywords drawn in their colours. Focused by keys and by a pad, a
## rune's circle shows one column of its keyword tooltips beside the bar, moving with focus;
## Discard and a refused rune's reason show as plain words, Discard with no column; a hovered
## keyword adds none. The mouse pointing at a circle shows the column too, and leaving hides it.
## On a co-op teammate's map an empty slot says "Your runes act on your own map only." with no
## column. The harness and drivers are rune_cases.gd's.


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("rune bar keywords: the M1 map definition loads", false, M1_DEFINITION)
		return
	for device: Device in [Device.KEYS, Device.PAD]:
		_test_focus_column(device)
	_test_mouse_column()
	_test_own_map_only()


# open_runes by device focuses the first rune: its marked line, coloured keywords and column beside
# the bar; down to Discard shows its plain line and no column, up brings the column back; across
# to Spark its line keeps its keywords and adds why it can't be cast; a hover adds no column.
func _test_focus_column(device: Device) -> void:
	var tag: String = "rune bar keywords (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var bar: RuneBar = h.controller.rune_bar
	var text: EffectText = bar.get_effect_text()
	_press(device, &"open_runes")
	var rune: TurnInputModel.HeldRune = _focused(bar)
	if rune == null:
		_check.call("%s: open_runes focuses a rune" % [tag], false, str(h.controller.get_stage()))
		h.close()
		return
	var ids: PackedStringArray = text.get_keyword_ids()
	var problems: PackedStringArray = _line_problems(bar, rune)
	if ids.is_empty() or _shown_ids(text) != ids:
		problems.append("column %s of %s" % [_shown_ids(text), ids])
	if not _is_beside(text, bar):
		problems.append("column %s not beside the bar %s" % [
			text.get_tooltip_column().get_global_rect(), bar.get_global_rect(),
		])
	_check.call("%s: the focused rune's marked line, keyword colours and column" % [tag], (
			problems.is_empty()
	), "; ".join(problems))

	_press(device, &"ui_down")
	var discard_line: String = bar.get_text()
	var discard_marked: String = text.marked_text
	var discard_column: PackedStringArray = _shown_ids(text)
	_press(device, &"ui_up")
	var back: PackedStringArray = _shown_ids(text)
	_check.call("%s: Discard's line is plain with no column; up brings the column back" % [tag], (
			discard_line == bar.discard_text_format % [rune.label]
			and discard_marked == discard_line
			and discard_column.is_empty()
			and back == ids
	), "discard '%s' (marked '%s'), its column %s; back %s of %s" % [
		discard_line, discard_marked, discard_column, back, ids,
	])

	var hovered: PackedStringArray = []
	if not ids.is_empty():
		text.meta_hover_started.emit(ids[0])
		hovered = _shown_ids(text)
		text.meta_hover_ended.emit(ids[0])
	_check.call("%s: a hovered keyword adds no column" % [tag], (
			hovered == ids and _shown_ids(text) == ids
	), "hovered %s of %s" % [hovered, ids])

	var spark_id: String = _rune_id_of(h.session, "spark")
	for _i: int in bar.get_runes().size():
		if bar.get_focused_rune() == spark_id:
			break
		_press(device, &"ui_right")
	var spark: TurnInputModel.HeldRune = _focused(bar)
	var spark_problems: PackedStringArray = []
	if spark == null or spark.rune_id != spark_id:
		spark_problems.append("Spark not focused")
	else:
		spark_problems = _line_problems(bar, spark)
		if not bar.get_text().ends_with("(%s)" % [TurnInputModel.NO_TARGET_REASON]):
			spark_problems.append("line '%s' gives no reason" % [bar.get_text()])
	_check.call("%s: a refused rune keeps its keywords and adds why, plainly" % [tag], (
			spark_problems.is_empty()
	), "; ".join(spark_problems))
	h.close()


# The mouse pointing at a rune's circle (no focus: the bar isn't navigable) shows its line and
# column; pointing at its Discard shows no column; leaving hides the line and the column.
func _test_mouse_column() -> void:
	var tag: String = "rune bar keywords (mouse)"
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var bar: RuneBar = h.controller.rune_bar
	var text: EffectText = bar.get_effect_text()
	var slot: RuneSlotButton = bar.get_slots()[0]
	var rune: TurnInputModel.HeldRune = bar.get_runes()[0]
	slot.get_slot_button().mouse_entered.emit()
	var problems: PackedStringArray = _line_problems(bar, rune)
	var ids: PackedStringArray = text.get_keyword_ids()
	if ids.is_empty() or _shown_ids(text) != ids or not _is_beside(text, bar):
		problems.append("column %s of %s" % [_shown_ids(text), ids])
	_check.call("%s: pointing at a rune shows its marked line and its column" % [tag], (
			problems.is_empty() and not bar.is_navigable()
	), "; ".join(problems))
	slot.get_slot_button().mouse_exited.emit()
	slot.get_discard_button().mouse_entered.emit()
	var on_discard: PackedStringArray = _shown_ids(text)
	slot.get_discard_button().mouse_exited.emit()
	_check.call("%s: Discard shows no column; leaving hides the line and the column" % [tag], (
			on_discard.is_empty()
			and bar.get_text().is_empty()
			and _shown_ids(text).is_empty()
	), "on discard %s; after '%s', %s" % [on_discard, bar.get_text(), _shown_ids(text)])
	h.close()


# Seat 0 viewing seat 1's map in a co-op battle: the bar is refused because runes act on their own
# map only, and an empty slot pointed at says so, with no keyword and no column.
func _test_own_map_only() -> void:
	var tag: String = "rune bar keywords (co-op)"
	var h: TurnInputCases.Harness = _coop_harness()
	if h == null:
		return
	var bar: RuneBar = h.controller.rune_bar
	var text: EffectText = bar.get_effect_text()
	var slot: RuneSlotButton = bar.get_slots()[0]
	slot.get_slot_button().mouse_entered.emit()
	_check.call("%s: on a teammate's map an empty slot says runes act on their own map" % [tag], (
			h.controller.rune_bar_reason() == BattleController.RUNES_OWN_MAP
			and bar.get_text() == BattleController.RUNES_OWN_MAP
			and text.marked_text == BattleController.RUNES_OWN_MAP
			and text.get_keyword_ids().is_empty()
			and _shown_ids(text).is_empty()
	), "reason '%s', line '%s', column %s" % [
		h.controller.rune_bar_reason(), bar.get_text(), _shown_ids(text),
	])
	slot.get_slot_button().mouse_exited.emit()
	h.close()


# What is wrong with bar's line for rune: its EffectText's marked text, its plain words, and each
# keyword drawn in its group's colour.
func _line_problems(bar: RuneBar, rune: TurnInputModel.HeldRune) -> PackedStringArray:
	var problems: PackedStringArray = []
	var text: EffectText = bar.get_effect_text()
	var prefix: String = "%s: %s" % [rune.label, rune.marked_text]
	if not text.marked_text.begins_with(prefix):
		problems.append("%s marked '%s'" % [rune.label, text.marked_text])
	if not bar.get_text().begins_with("%s: %s" % [rune.label, rune.text]):
		problems.append("%s plain '%s'" % [rune.label, bar.get_text()])
	var glossary: KeywordGlossary = KeywordGlossary.shared()
	for id: String in text.get_keyword_ids():
		var entry: KeywordEntry = glossary.entry(id)
		var colour: Color = text.get_theme_color(KeywordEntry.colour_item(entry.colour_group))
		var span: String = "[url=%s][color=#%s]" % [id, colour.to_html(false)]
		if not text.text.contains(span):
			problems.append("%s not in its colour" % [id])
	return problems


# The rune whose circle has focus; null for none or its Discard.
func _focused(bar: RuneBar) -> TurnInputModel.HeldRune:
	for i: int in bar.get_runes().size():
		if bar.get_slots()[i].get_slot_button().has_focus():
			return bar.get_runes()[i]
	return null


# A co-op battle on the M1 map, each seat with the mercenary army and no swap window, seat 0's
# controller and rune bar bound to seat 1's map, where seat 0 has no units.
func _coop_harness() -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.MULTIPLAYER, SEED, PackedInt32Array([0, 1]))
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BattleViewCases.FLOOR
	request.node = BattleViewCases.NODE
	request.pool = [_map]
	request.catalog = BattleViewCases.PackCatalog.with_only(_catalog, "m1_pack")
	for seat: int in [0, 1]:
		var mercenary: StartingArmy = StartingArmy.build(_catalog, "mercenary", h.run.ids)
		var army: CampaignSession.Army = CampaignSession.Army.new()
		army.unit_instances = mercenary.units
		army.item_instances = mercenary.items
		request.armies[seat] = army
		request.opening_swap[seat] = false
	h.battle = h.run.begin_battle(request)
	if h.battle == null:
		_check.call("rune bar keywords: the co-op M1 battle begins", false)
		h.run.close()
		return null
	h.session = h.battle.session_of_seat(1)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	var rune_bar: RuneBar = RUNE_BAR_SCENE.instantiate()
	for widget: Control in [h.bar, rune_bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	h.controller.rune_bar = rune_bar
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	BattleViewCases.settle(h.view)
	return h


static func _shown_ids(text: EffectText) -> PackedStringArray:
	var ids: PackedStringArray = []
	for tooltip: KeywordTooltip in text.get_shown_tooltips():
		ids.append(tooltip.keyword_id)
	return ids


# Whether text's tooltip column sits wholly left or right of bar.
static func _is_beside(text: EffectText, bar: RuneBar) -> bool:
	var column: Rect2 = text.get_tooltip_column().get_global_rect()
	var box: Rect2 = bar.get_global_rect()
	return column.position.x >= box.end.x - 0.5 or column.end.x <= box.position.x + 0.5
