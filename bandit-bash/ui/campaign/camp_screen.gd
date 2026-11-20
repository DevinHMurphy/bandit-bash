# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camp_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Control
## A Camp: choose one of Feast or Train ([CampChoiceCard]s), re-gear freely alongside
## ([ArmyView] in its re-gear mode), then Leave, under the run's header and [HeirloomBar].
##
## Feast asks which ingredient to cook, or none ([IngredientPanel]), then sends [FeastCommand];
## Train asks which unit ([UnitChoicePanel]) and sends [TrainCommand]. A choice that can't be made
## says why on its card; once one is made both cards say so, and Leave ([LeaveNodeCommand]) opens
## up. Every command goes through [method CampaignService.submit_command], which saves, so a quit
## and Continue returns here with the choice as made; a rejection shows its reason and changes
## nothing. The run's facts play ([CampaignPlayback]) as each resolves. Opened at any other stage,
## it sends the run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI; the panels read their own
# ui_cancel first):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (between the cards; the buttons)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (cards to buttons; a panel's column;
#                             the army view's rows)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (press the focused card or button)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (the pause menu reads it; read
#                             here in _input while the unit choice shows: Back; the ingredient
#                             panel and army view read their own)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses
#                             it, then back; hints HEIRLOOMS meanwhile)
#   Mouse: clicks on the cards, buttons and choices; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context while the choices show.
const HINT_CHOOSE: StringName = &"CHOOSE"

## The hint context while a panel asks (an ingredient, a unit).
const HINT_ASK: StringName = &"ASK"

## The hint context while the army view shows.
const HINT_ARMY: StringName = &"ARMY"

## The name each choice is shown by.
const CHOICE_NAMES: Dictionary[Camp.Choice, String] = {
	Camp.Choice.FEAST: "Feast",
	Camp.Choice.TRAIN: "Train",
}

var _is_leaving: bool = false
var _seat: int = 0
var _context: StringName = HINT_CHOOSE

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _feast_card: CampChoiceCard = %FeastCard
@onready var _train_card: CampChoiceCard = %TrainCard
@onready var _status_label: Label = %Status
@onready var _army_button: Button = %ArmyButton
@onready var _leave_button: Button = %LeaveButton
@onready var _ingredients: IngredientPanel = %IngredientPanel
@onready var _train_overlay: Control = %TrainOverlay
@onready var _train_backdrop: ColorRect = %TrainBackdrop
@onready var _unit_choice: UnitChoicePanel = %UnitChoicePanel
@onready var _army_view: ArmyView = %ArmyView
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.CAMP:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = session.seats[0]
	_header.title = "Camp"
	_train_overlay.visible = false
	_train_backdrop.color = UiTokens.with_alpha(UiTokens.BG, _ingredients.backdrop_alpha)
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_feast_card.pressed.connect(_on_feast_card_pressed)
	_train_card.pressed.connect(_on_train_card_pressed)
	_army_button.pressed.connect(_on_army_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_ingredients.ingredient_chosen.connect(_on_ingredients_ingredient_chosen)
	_ingredients.cancelled.connect(_on_panel_cancelled)
	_unit_choice.unit_chosen.connect(_on_unit_choice_unit_chosen)
	_unit_choice.cancelled.connect(_on_panel_cancelled)
	_army_view.command_ready.connect(_on_army_view_command_ready)
	_army_view.closed.connect(_on_army_view_closed)
	_refresh()
	_set_context(HINT_CHOOSE)
	CampaignPlayback.play_pending(session)
	_focus_default.call_deferred()


func _input(event: InputEvent) -> void:
	if not _train_overlay.visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_panel_cancelled()


## The Feast card, for tests and captures.
func get_feast_card() -> CampChoiceCard:
	return _feast_card


## The Train card, for tests.
func get_train_card() -> CampChoiceCard:
	return _train_card


## The re-gear button, for tests.
func get_army_button() -> Button:
	return _army_button


## The Leave button, for tests.
func get_leave_button() -> Button:
	return _leave_button


## The ingredient panel, for tests.
func get_ingredient_panel() -> IngredientPanel:
	return _ingredients


## The unit choice for Train, for tests; shown while its overlay is.
func get_unit_choice() -> UnitChoicePanel:
	return _unit_choice


## Whether Train's unit choice shows, for tests.
func is_unit_choice_shown() -> bool:
	return _train_overlay.visible


## The army view, for tests and captures.
func get_army_view() -> ArmyView:
	return _army_view


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# Shows the run as saved: the header, the bar, the two cards and whether Leave can go.
func _refresh() -> void:
	var session: CampaignSession = CampaignService.session
	var run: CampaignRunState = session.run
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var seat_run: SeatRun = run.seat_run(_seat)
	_header.show_run(run, _seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(seat_run))
	var chosen: Camp.Choice = Camp.choice_of(seat_run)
	var made: String = (
			"" if chosen == Camp.Choice.NONE
			else "you chose %s at this Camp" % [CHOICE_NAMES[chosen]]
	)
	_feast_card.show_choice("Feast", PackedStringArray([
		"Every unit heals %d%% of its max HP." % [Camp.FEAST_HEAL_PERCENT],
		"Cook one ingredient for the army's next level-up (%d on hand)." % [
			Camp.ingredients(seat_run, catalog).size(),
		],
	]), made)
	var train_refusal: String = made
	if train_refusal.is_empty():
		train_refusal = Camp.train_option_problem(run, _seat, catalog)
	_train_card.show_choice("Train", PackedStringArray([
		"Upgrade one unit: its \"+\" trait and stat gains.",
		"The commander is never upgraded.",
	]), train_refusal)
	var can_leave: bool = chosen != Camp.Choice.NONE
	_leave_button.disabled = not can_leave
	_leave_button.focus_mode = Control.FOCUS_ALL if can_leave else Control.FOCUS_NONE
	_leave_button.text = "Leave" if can_leave else "Leave (choose Feast or Train first)"


# The first card that can be chosen, else Leave. Deferred from _ready, so the screen may be gone.
func _focus_default() -> void:
	if not is_inside_tree() or _is_leaving:
		return
	for control: Button in [_feast_card, _train_card, _leave_button, _army_button]:
		if not control.disabled:
			control.grab_focus()
			return


func _set_context(context: StringName) -> void:
	_context = context
	_hints.context = context


# Sends command; on a rejection says why where the player is looking and returns false.
func _submit(command: CampaignCommand) -> bool:
	var batch: CampaignBatch = CampaignService.submit_command(command)
	if batch == null or batch.is_rejected():
		var reason: String = "Can't do that: %s." % [
			batch.rejected_reason if batch != null else "no run in progress"
		]
		if _ingredients.visible:
			_ingredients.show_problem(reason)
		elif _army_view.visible:
			_army_view.show_problem(reason)
		else:
			_status_label.text = reason
		return false
	CampaignPlayback.play_pending(CampaignService.session)
	return true


# Back to the cards after a panel, focusing Leave once the choice is made.
func _back_to_choices() -> void:
	_ingredients.close()
	_train_overlay.visible = false
	_set_context(HINT_CHOOSE)
	_refresh()
	_focus_default()


func _on_feast_card_pressed() -> void:
	var session: CampaignSession = CampaignService.session
	_ingredients.open(session.run.seat_run(_seat), EffectCatalog.index(), session.ids)
	_set_context(HINT_ASK)


func _on_train_card_pressed() -> void:
	var run: CampaignRunState = CampaignService.session.run
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	_train_overlay.visible = true
	_unit_choice.show_units(
			"Upgrade which unit?", run.seat_run(_seat), catalog,
			Camp.trainable_units(run, _seat, catalog), "Upgrade", "can't be upgraded"
	)
	_set_context(HINT_ASK)


func _on_army_button_pressed() -> void:
	_army_view.open(CampaignService.session, _seat, ArmyView.Mode.REGEAR)
	_set_context(HINT_ARMY)


func _on_leave_button_pressed() -> void:
	if _is_leaving:
		return
	if not _submit(LeaveNodeCommand.new(_seat)):
		return
	_is_leaving = true
	RunScreen.go()


func _on_ingredients_ingredient_chosen(item_id: String) -> void:
	if not _submit(FeastCommand.new(_seat, item_id)):
		return
	_status_label.text = (
			"The army feasted." if item_id.is_empty()
			else "The army feasted; the cooked gain lands on each unit's next level-up."
	)
	_back_to_choices()


func _on_unit_choice_unit_chosen(unit_id: String) -> void:
	if not _submit(TrainCommand.new(_seat, unit_id)):
		return
	var session: CampaignSession = CampaignService.session
	_status_label.text = "%s trained." % [CombatResultsModel.unit_name(
			session.ids, session.run.seat_run(_seat), unit_id, EffectCatalog.index()
	)]
	_back_to_choices()


func _on_panel_cancelled() -> void:
	_back_to_choices()


func _on_army_view_command_ready(command: CampaignCommand) -> void:
	if not _submit(command):
		return
	_header.show_run(CampaignService.session.run, _seat)
	_army_view.refresh()


func _on_army_view_closed() -> void:
	_set_context(HINT_CHOOSE)
	_refresh()
	_army_button.grab_focus()


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _context
