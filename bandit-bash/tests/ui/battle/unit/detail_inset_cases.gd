# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_inset_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/ui/battle/unit/detail_keywords_cases.gd"
## The unit detail rows' focus inset, for the ui/input suite (ui-style.md, the 4-unit row gap):
## in the Drengr's detail, each focus row the d-pad steps onto (gear with text, traits and
## heirlooms) holds key focus with its contents [constant INSET] units inside its edge, where the
## focus outline draws, on every side, so the outline never touches the name's first letter; the
## enemy section, shown for an enemy, the same. The rig and drivers are unit_detail_cases.gd's and
## detail_keywords_cases.gd's.

# The style guide's gap between rows, which the rows' focus_inset defaults to.
const INSET: float = 4.0

# How far a laid-out edge may sit from where it should, in base units.
const TOLERANCE: float = 0.5


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("detail inset: the M1 map definition loads", false, M1_DEFINITION)
		return
	var rig: Rig = _rig()
	if rig == null:
		return
	_test_focus_rows(rig)
	_test_enemy_inset(rig)
	rig.close()


# Down steps onto each focus row in turn: each holds key focus, its contents inset on every side.
func _test_focus_rows(rig: Rig) -> void:
	var panel: UnitDetailPanel = _open_drengr(rig)
	if panel == null:
		return
	var rows: Array[Control] = panel.get_focus_rows()
	var problems: PackedStringArray = []
	var has_gear: bool = false
	var has_effect: bool = false
	for i: int in rows.size():
		_press_pad(PAD_DOWN)
		_lay_out(panel)
		var row: Control = rows[i]
		has_gear = has_gear or row is DetailGearRow
		has_effect = has_effect or row is DetailEffectRow
		if not row.has_focus(true):
			problems.append("%s has no key focus" % [row.name])
		var problem: String = _inset_problem(row)
		if not problem.is_empty():
			problems.append(problem)
	_check.call("detail inset: each focused row's contents sit 4 units inside its outline", (
			problems.is_empty() and has_gear and has_effect
	), "%s; gear %s, effect %s" % ["; ".join(problems), has_gear, has_effect])
	rig.h.controller.step_back()


# An enemy's detail: its section's contents sit 4 units inside its edge.
func _test_enemy_inset(rig: Rig) -> void:
	var session: CombatSession = rig.h.session
	var enemy: String = session.state.units_of(ENEMY)[0]
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	rig.h.hud.add_child(panel)
	panel.open_with(UnitDetailViewModel.build(session, enemy))
	_lay_out(panel)
	var section: DetailEnemySection = panel.get_enemy_section()
	var problem: String = _inset_problem(section)
	_check.call("detail inset: the enemy section's contents sit 4 units inside its edge", (
			section.visible and problem.is_empty()
	), "shown %s; %s" % [section.visible, problem])
	panel.free()


# Why row's contents don't sit INSET inside its edge on every side; empty when they do. The
# contents are the one child of its Inset margin, and the first text in them starts that far in.
func _inset_problem(row: Control) -> String:
	var inset: MarginContainer = row.get_node_or_null(^"Inset") as MarginContainer
	if inset == null or inset.get_child_count() != 1:
		return "%s has no Inset holding its contents" % [row.name]
	var box: Rect2 = row.get_global_rect()
	var content: Rect2 = (inset.get_child(0) as Control).get_global_rect()
	var gaps: Array[float] = [
		content.position.x - box.position.x,
		content.position.y - box.position.y,
		box.end.x - content.end.x,
		box.end.y - content.end.y,
	]
	for gap: float in gaps:
		if absf(gap - INSET) > TOLERANCE:
			return "%s's contents sit %s inside its edge" % [row.name, gaps]
	var first: Control = _first_text(inset)
	if first == null or first.get_global_rect().position.x - box.position.x < INSET - TOLERANCE:
		return "%s's first text starts at %s, the row at %s" % [
			row.name, first.get_global_rect().position if first != null else Vector2.ZERO,
			box.position,
		]
	return ""


# Sorts every container in node twice, as a frame's deferred sorts would.
static func _lay_out(node: Node) -> void:
	for _pass: int in 2:
		for container: Node in node.find_children("*", "Container", true, false):
			container.notification(Container.NOTIFICATION_SORT_CHILDREN)


# The first visible Label or RichTextLabel under node, in tree order; null for none.
static func _first_text(node: Node) -> Control:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		if control is Label or control is RichTextLabel:
			return control
		var found: Control = _first_text(control)
		if found != null:
			return found
	return null
