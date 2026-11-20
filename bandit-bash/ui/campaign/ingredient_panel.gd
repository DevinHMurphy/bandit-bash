# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ingredient_panel.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name IngredientPanel
extends Control
## The Feast's one question, asked over the Camp screen: which ingredient to cook, from the
## convoy or a living unit's Pouch ([method Camp.ingredients]), or none. Each choice says where
## the ingredient is and what every living unit gains ([method cooked_text]); then "Cook nothing"
## and Back. One column of buttons, so a pad moves up and down within it; the dimmed backdrop takes
## every click outside the panel. It only asks: [signal ingredient_chosen] and [signal cancelled]
## go to the Camp screen, which sends the [FeastCommand].

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input while shown: Back, taken
#                  first, so the pause menu doesn't open over the panel)
#   "ui_up" / "ui_down" / "ui_accept"                     (not read here: the GUI moves focus
#                  within the column and presses the focused choice)
#   Mouse: a click on a choice presses it.
# ============================================================

## The player chose to cook the item [param item_id]; empty cooks nothing.
signal ingredient_chosen(item_id: String)

## The player pressed Back: no Feast is held.
signal cancelled()

## How dark the backdrop over the Camp is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the Camp hidden. 0.6 matches the [PlacementPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

## Each choice's least width, so an ingredient, its place and its gain fit on one line.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var choice_width: float = 520.0

@onready var _backdrop: ColorRect = %Backdrop
@onready var _question_label: Label = %Question
@onready var _choices: VBoxContainer = %Choices
@onready var _problem_label: Label = %Problem


func _ready() -> void:
	visible = false
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back_pressed()


## Opens for [param seat_run]'s ingredients ([param catalog] their content, [param ids] its
## units' names), focusing the first choice.
func open(seat_run: SeatRun, catalog: EffectCatalog.Index, ids: InstanceIdAllocator) -> void:
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_problem_label.text = ""
	_question_label.text = (
			"Every unit heals %d%% of its max HP. Cook one ingredient for the whole army?"
			% [Camp.FEAST_HEAL_PERCENT]
	)
	for item_id: String in Camp.ingredients(seat_run, catalog):
		var definition: ConsumableDefinition = (
				catalog.item(seat_run.items[item_id].definition_id) as ConsumableDefinition
		)
		var text: String = "Cook %s (%s): %s" % [
			CombatResultsModel.item_name(definition, item_id),
			_place_of(seat_run, item_id, catalog, ids),
			cooked_text(definition),
		]
		_add_choice(text, _on_choice_pressed.bind(item_id))
	_add_choice("Cook nothing", _on_choice_pressed.bind(""))
	_add_choice("Back", _on_back_pressed)
	_link_column()
	visible = true
	get_choice_buttons()[0].grab_focus()


## Hides the panel.
func close() -> void:
	visible = false


## Shows [param problem] under the choices, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	_problem_label.text = problem


## The choices shown, ingredients then "Cook nothing" and Back, for the screen and tests.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## What cooking [param definition] gives every living unit, such as
## [code]next level-up +2 HP[/code] or [code]+5 Hit now[/code].
static func cooked_text(definition: ConsumableDefinition) -> String:
	if definition == null:
		return "not in the catalog"
	var parts: PackedStringArray = []
	for stat: CombatValue.Stat in definition.cooked_gains:
		parts.append("+%d %s" % [definition.cooked_gains[stat], CombatValue.Stat.find_key(stat)])
	var lines: PackedStringArray = []
	if not parts.is_empty():
		lines.append("every unit's next level-up %s" % [", ".join(parts)])
	if definition.cooked_hit > 0:
		lines.append("+%d Hit now for every unit" % [definition.cooked_hit])
	return "; ".join(lines) if not lines.is_empty() else "no gain"


# Where item_id sits: the convoy, or the Pouch of the unit holding it.
func _place_of(
		seat_run: SeatRun, item_id: String, catalog: EffectCatalog.Index, ids: InstanceIdAllocator
) -> String:
	if seat_run.convoy.has(item_id):
		return "convoy"
	for unit: UnitInstance in seat_run.army:
		if unit.pouch_id == item_id:
			return "%s's Pouch" % [
				CombatResultsModel.unit_name(ids, seat_run, unit.instance_id, catalog),
			]
	return "?"


func _add_choice(text: String, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(choice_width, 36.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(chosen)
	_choices.add_child(button)


# The column links up and down and stops at its ends; left and right stay put.
func _link_column() -> void:
	var column: Array[Button] = get_choice_buttons()
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path


func _on_choice_pressed(item_id: String) -> void:
	ingredient_chosen.emit(item_id)


func _on_back_pressed() -> void:
	close()
	cancelled.emit()
