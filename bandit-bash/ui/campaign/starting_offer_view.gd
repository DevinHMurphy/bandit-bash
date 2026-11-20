# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_offer_view.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StartingOfferView
extends Control
## The starting heirloom offer, asked over its steps ([enum Step]): the three heirlooms
## ([HeirloomOfferCard]), then whatever the one chosen needs: a recruit ([RecruitOfferCard]), the
## unit it replaces or the unit to upgrade ([UnitChoicePanel]), or a weapon ([ItemOfferCard]) and
## where it goes ([PlacementPanel]). It builds one [StartingHeirloomCommand] by the offer's own
## rules and emits [signal command_ready]; the screen sends it, which checks it again, and shows a
## rejection here ([method show_problem]). Nothing is taken until then, so Back from any sub-choice
## returns to the three.[br]
## Each row of cards links left and right with its Back or Skip and stops at its ends. Names no
## autoload, so a suite can drive it.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input in RECRUIT, WEAPON and
#                  UNIT: Back, taken first so the pause menu doesn't open; in HEIRLOOM it is left
#                  to the pause menu; in PLACEMENT the PlacementPanel reads it)
#   "ui_left" / "ui_right" / "ui_up" / "ui_down" / "ui_accept"   (not read here: the GUI moves
#                  focus along a row or column and presses the focused card or choice, by key,
#                  d-pad, stick or A [Cross])
#   Mouse: a click on a card or choice presses it; Back steps back as ui_cancel does.
# ============================================================

## The player settled the whole choice: send [param command].
signal command_ready(command: StartingHeirloomCommand)

## The view moved to [param step]; the screen's hints follow it.
signal step_changed(step: Step)

const HEIRLOOM_CARD_SCENE: PackedScene = preload("res://ui/campaign/heirloom_offer_card.tscn")
const RECRUIT_CARD_SCENE: PackedScene = preload("res://ui/campaign/recruit_offer_card.tscn")
const ITEM_CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")

# --- Offer step (meaningful only after open()) ---------------------------------------------
# HEIRLOOM:  the three heirlooms; a refused one can't be pressed. Skip shows only when all three
#            are refused. Choosing one with nothing to ask emits command_ready at once.
# RECRUIT:   Abundance's or Mercenary Contract's recruits. Back returns to HEIRLOOM. Choosing one
#            emits for Abundance, goes to UNIT for Mercenary Contract.
# UNIT:      the unit to upgrade (Veteran Company) or the unit the recruit replaces (Mercenary
#            Contract). Back returns to RECRUIT for a replacement, else to HEIRLOOM. Choosing emits.
# WEAPON:    Ancestral Weapon's weapons. Back returns to HEIRLOOM. Choosing goes to PLACEMENT.
# PLACEMENT: where the weapon goes; the PlacementPanel's own Back from its first step returns to
#            WEAPON, and its choice emits command_ready.
# The view stays at its step after emitting, so a rejection is shown where it was made.
## Which question the view asks.
enum Step {
	## Which heirloom.
	HEIRLOOM = 0,
	## Which recruit.
	RECRUIT = 1,
	## Which unit.
	UNIT = 2,
	## Which weapon.
	WEAPON = 3,
	## Where the weapon goes.
	PLACEMENT = 4,
}

## The heading over the three heirlooms.
@export var offer_title: String = "Choose a starting heirloom"

var _step: Step = Step.HEIRLOOM
var _session: CampaignSession = null
var _seat: int = 0
var _catalog: EffectCatalog.Index = null
var _offer: StartingOffer = null
var _option: int = StartingHeirloomCommand.SKIP
var _recruit: int = StartingHeirloomCommand.NO_CHOICE
var _weapon: int = StartingHeirloomCommand.NO_CHOICE

@onready var _title_label: Label = %Title
@onready var _question_label: Label = %Question
@onready var _cards: HBoxContainer = %Cards
@onready var _back_button: Button = %BackButton
@onready var _skip_button: Button = %SkipButton
@onready var _units: UnitChoicePanel = %UnitChoicePanel
@onready var _status_label: Label = %Status
@onready var _placement: PlacementPanel = %PlacementPanel


func _ready() -> void:
	_back_button.pressed.connect(step_back)
	_skip_button.pressed.connect(_on_skip_button_pressed)
	_units.unit_chosen.connect(_on_unit_choice_panel_unit_chosen)
	_units.cancelled.connect(step_back)
	_placement.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement.cancelled.connect(_on_placement_panel_cancelled)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _offer == null:
		return
	if _step == Step.HEIRLOOM or _step == Step.PLACEMENT:
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	step_back()


## Opens on seat [param seat]'s offer in [param session]'s run, read with [param catalog] (null:
## the loaded one), at the three heirlooms. Shows nothing for a seat with no offer.
func open(session: CampaignSession, seat: int, catalog: EffectCatalog.Index = null) -> void:
	_session = session
	_seat = seat
	_catalog = catalog if catalog != null else EffectCatalog.index()
	var seat_run: SeatRun = null if session.run == null else session.run.seat_run(seat)
	_offer = StartingOffer.pending(seat_run)
	_show_heirlooms()


## Shows [param problem] where the choice was made, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	if _step == Step.PLACEMENT:
		_placement.show_problem(problem)
		return
	_status_label.text = problem


## Goes back one step: to the three heirlooms from a recruit, a weapon or an upgrade's unit, to
## the recruits from a replacement's unit. Does nothing at the three or while placing.
func step_back() -> void:
	match _step:
		Step.RECRUIT, Step.WEAPON:
			_show_heirlooms()
		Step.UNIT:
			if _bonus() == StartingHeirloomDefinition.Bonus.REPLACE:
				_show_recruits()
			else:
				_show_heirlooms()


## The step shown.
func get_step() -> Step:
	return _step


## The cards shown in a row (heirlooms, recruits or weapons), in offer order; empty in the other
## steps. For the screen and tests.
func get_cards() -> Array[Button]:
	var cards: Array[Button] = []
	if not _cards.visible:
		return cards
	for child: Node in _cards.get_children():
		if child is Button and not child.is_queued_for_deletion():
			cards.append(child as Button)
	return cards


## The Back button, for tests.
func get_back_button() -> Button:
	return _back_button


## The Skip button, for tests.
func get_skip_button() -> Button:
	return _skip_button


## The unit choice, for tests.
func get_unit_panel() -> UnitChoicePanel:
	return _units


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement


## The status line, for tests.
func get_status_text() -> String:
	return _status_label.text


## Focuses the first card or choice the step offers; returns whether one took it.
func focus_first() -> bool:
	for card: Button in get_cards():
		if not card.disabled:
			card.grab_focus()
			return true
	if _units.visible:
		for button: Button in _units.get_choice_buttons():
			if not button.disabled:
				button.grab_focus()
				return true
	return false


func _show_heirlooms() -> void:
	_option = StartingHeirloomCommand.SKIP
	_recruit = StartingHeirloomCommand.NO_CHOICE
	_weapon = StartingHeirloomCommand.NO_CHOICE
	_title_label.text = offer_title
	_question_label.text = "Pick 1 of 3. Each is offered only now."
	_clear_cards()
	var every_refused: bool = true
	var options: Array[StartingOffer.Option] = [] if _offer == null else _offer.options
	for index: int in options.size():
		var option: StartingOffer.Option = options[index]
		var problem: String = StartingOffer.option_problem(_session.run, _seat, option, _catalog)
		every_refused = every_refused and not problem.is_empty()
		var card: HeirloomOfferCard = HEIRLOOM_CARD_SCENE.instantiate()
		_cards.add_child(card)
		card.show_heirloom(
				StartingOffer.definition_of(option, _catalog), option.heirloom_id, problem
		)
		card.pressed.connect(_on_heirloom_card_pressed.bind(index))
	_skip_button.visible = every_refused and not options.is_empty()
	_enter(Step.HEIRLOOM, false)


func _show_recruits() -> void:
	_recruit = StartingHeirloomCommand.NO_CHOICE
	var option: StartingOffer.Option = _offer.options[_option]
	_title_label.text = _heirloom_name()
	_question_label.text = (
			"Choose the recruit, then the unit it replaces." if _bonus() == (
					StartingHeirloomDefinition.Bonus.REPLACE
			)
			else "Choose the recruit who joins the army."
	)
	_clear_cards()
	for index: int in option.recruits.size():
		var card: RecruitOfferCard = RECRUIT_CARD_SCENE.instantiate()
		_cards.add_child(card)
		card.show_recruit(option.recruits[index], _catalog)
		card.pressed.connect(_on_recruit_card_pressed.bind(index))
	_enter(Step.RECRUIT, true)


func _show_weapons() -> void:
	_weapon = StartingHeirloomCommand.NO_CHOICE
	var option: StartingOffer.Option = _offer.options[_option]
	_title_label.text = _heirloom_name()
	_question_label.text = "Choose the weapon, then where it goes."
	_clear_cards()
	for index: int in option.weapons.size():
		var weapon: ItemPick.Offer = option.weapons[index]
		var card: ItemOfferCard = ITEM_CARD_SCENE.instantiate()
		_cards.add_child(card)
		card.show_item(_catalog.item(weapon.definition_id), weapon.definition_id)
		card.pressed.connect(_on_weapon_card_pressed.bind(index))
	_enter(Step.WEAPON, true)


func _show_units() -> void:
	var is_replacing: bool = _bonus() == StartingHeirloomDefinition.Bonus.REPLACE
	_title_label.text = _heirloom_name()
	_question_label.text = ""
	_clear_cards()
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var eligible: PackedStringArray = StartingOffer.eligible_units(
			_session.run, _seat, _catalog, is_replacing
	)
	_enter(Step.UNIT, false)
	if is_replacing:
		var joining: String = RecruitOfferCard.title_of(
				_offer.options[_option].recruits[_recruit].unit, _catalog
		)
		_units.show_units(
				"Which unit does %s replace? Its items go to the convoy." % [joining], seat_run,
				_catalog, eligible, "Replace", "can't leave"
		)
	else:
		_units.show_units(
				"Which unit is upgraded?", seat_run, _catalog, eligible, "Upgrade",
				"can't be upgraded"
		)


# Shows step: the card row with Back when has_back (else Skip only as _show_heirlooms set it), or
# the unit column; links the row and focuses its first card.
func _enter(step: Step, has_back: bool) -> void:
	_step = step
	_status_label.text = ""
	var is_row: bool = step != Step.UNIT and step != Step.PLACEMENT
	_cards.visible = is_row
	_back_button.visible = is_row and has_back
	if step != Step.HEIRLOOM:
		_skip_button.visible = false
	_units.visible = step == Step.UNIT
	if is_row:
		_link_row()
		focus_first.call_deferred()
	step_changed.emit(step)


# The enabled cards then Back or Skip as one row: left and right step along it and stop at its
# ends; up and down stay put.
func _link_row() -> void:
	var row: Array[Control] = []
	for card: Button in get_cards():
		if not card.disabled:
			row.append(card)
	for button: Button in [_back_button, _skip_button]:
		if button.visible:
			row.append(button)
	for i: int in row.size():
		var control: Control = row[i]
		var self_path: NodePath = control.get_path_to(control)
		control.focus_neighbor_left = control.get_path_to(row[maxi(i - 1, 0)])
		control.focus_neighbor_right = control.get_path_to(row[mini(i + 1, row.size() - 1)])
		control.focus_neighbor_top = self_path
		control.focus_neighbor_bottom = self_path
		control.focus_previous = control.focus_neighbor_left
		control.focus_next = control.focus_neighbor_right


func _clear_cards() -> void:
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()


func _bonus() -> StartingHeirloomDefinition.Bonus:
	var definition: StartingHeirloomDefinition = (
			null if _option == StartingHeirloomCommand.SKIP
			else StartingOffer.definition_of(_offer.options[_option], _catalog)
	)
	return StartingHeirloomDefinition.Bonus.NONE if definition == null else definition.bonus


func _heirloom_name() -> String:
	var option: StartingOffer.Option = _offer.options[_option]
	var definition: StartingHeirloomDefinition = StartingOffer.definition_of(option, _catalog)
	return option.heirloom_id if definition == null else definition.display_name


# The command for what is chosen so far, with unit_id (empty: none) and placement (null: none).
func _emit(unit_id: String = "", placement: ItemPlacement = null) -> void:
	var command: StartingHeirloomCommand = StartingHeirloomCommand.new(_seat, _option)
	command.recruit = _recruit
	command.weapon = _weapon
	command.unit_id = unit_id
	command.placement = placement
	command.catalog = _catalog
	command_ready.emit(command)


func _on_heirloom_card_pressed(index: int) -> void:
	_option = index
	match _bonus():
		StartingHeirloomDefinition.Bonus.RECRUIT, StartingHeirloomDefinition.Bonus.REPLACE:
			_show_recruits()
		StartingHeirloomDefinition.Bonus.WEAPON:
			_show_weapons()
		StartingHeirloomDefinition.Bonus.UPGRADE:
			_show_units()
		_:
			_emit()


func _on_recruit_card_pressed(index: int) -> void:
	_recruit = index
	if _bonus() == StartingHeirloomDefinition.Bonus.REPLACE:
		_show_units()
		return
	_emit()


func _on_weapon_card_pressed(index: int) -> void:
	_weapon = index
	var weapon: ItemPick.Offer = _offer.options[_option].weapons[index]
	_enter(Step.PLACEMENT, false)
	_placement.open(
			_session.run.seat_run(_seat), _catalog.item(weapon.definition_id),
			weapon.definition_id, _catalog, _session.ids
	)


func _on_unit_choice_panel_unit_chosen(unit_id: String) -> void:
	_emit(unit_id)


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	_emit("", placement)


func _on_placement_panel_cancelled() -> void:
	_placement.close()
	_show_weapons()


func _on_skip_button_pressed() -> void:
	_option = StartingHeirloomCommand.SKIP
	_emit()
