# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     panel_host.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name PanelHost
extends Control
## The battle screen's one panel stack: opening pushes a [BattlePanel], [method back] pops exactly
## one, [method flush] clears them all, and only the top panel takes input (Godot_FE
## [code]12_ui_architecture.md[/code], FR-UI-2 and its PanelHost recipe).
##
## Panels below the top are hidden and disabled, so neither the mouse nor focus reaches them; the
## one uncovered by [method back] shows again with focus on its first choice. Panels go in the
## [code]%Slot[/code] node, inside the [code]%Scroll[/code] area whose place on screen is set in
## the scene: the right-hand column between the HUD's top strip and the turn bar, beside the map
## area ([BattleHud]). A panel taller than the area (the forecast with its breakdown open) scrolls,
## following focus, instead of growing over the turn bar. The host and the area let the mouse
## through, so clicks off a panel reach the board.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

var _stack: Array[BattlePanel] = []

@onready var _slot: Control = %Slot
@onready var _scroll: ScrollContainer = %Scroll


## Opens an instance of [param scene] (a [BattlePanel] scene) on top with [param payload], and
## returns it; null, opening nothing, when [param scene] is unset or isn't a panel.
func open(scene: PackedScene, payload: Variant) -> BattlePanel:
	if scene == null:
		push_error("PanelHost: no panel scene given")
		return null
	var panel: BattlePanel = scene.instantiate() as BattlePanel
	if panel == null:
		push_error("PanelHost: %s is not a BattlePanel scene" % [scene.resource_path])
		return null
	_slot.add_child(panel)
	_stack.append(panel)
	panel.open_with(payload)
	_show_top()
	return panel


## Closes the top panel and shows the one under it. Returns false, doing nothing, when the stack
## is empty.
func back() -> bool:
	if _stack.is_empty():
		return false
	var closing: BattlePanel = _stack.pop_back()
	_free(closing)
	_show_top()
	return true


## Closes every panel.
func flush() -> void:
	while not _stack.is_empty():
		var closing: BattlePanel = _stack.pop_back()
		_free(closing)


## The panel taking input; null when none is open.
func top() -> BattlePanel:
	return null if _stack.is_empty() else _stack[_stack.size() - 1]


## How many panels are open.
func depth() -> int:
	return _stack.size()


## The area panels show in, on screen; a panel's part outside it is clipped and scrolls into view.
func get_area_rect() -> Rect2:
	return _scroll.get_global_rect()


func _show_top() -> void:
	var last: int = _stack.size() - 1
	for i: int in _stack.size():
		var panel: BattlePanel = _stack[i]
		var is_top: bool = i == last
		panel.visible = is_top
		panel.process_mode = Node.PROCESS_MODE_INHERIT if is_top else Node.PROCESS_MODE_DISABLED
	if last >= 0:
		_stack[last].focus_first()


func _free(panel: BattlePanel) -> void:
	if not is_instance_valid(panel):
		return
	_slot.remove_child(panel)
	panel.queue_free()
