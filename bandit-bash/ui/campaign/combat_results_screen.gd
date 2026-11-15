# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_results_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

extends Control
## Results after a won combat, all at once (game-vision.md, Units: Experience): grades and gold,
## the item pick, each unit's XP and the Standout, and every level-up with its gains, read from
## the run as saved ([CombatResultsModel]), so a quit and Continue shows the same.
##
## An offer opens the [PlacementPanel]; the take and its placement go as one [ItemPickCommand],
## Skip as another, each through [method CampaignService.submit_command], which saves. Continue
## opens once the pick is resolved and sends [LeaveNodeCommand] back to the map; after the Boss it
## reads End run and ends the run as won ([method CampaignService.end_won_run]), then the run's
## end. A rejection shows its reason and changes nothing. Opened at any other stage, it sends the
## run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, except where noted):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick   (PICK: move along the
#                             offers and Skip; the ends stop)
#   "ui_up" / "ui_down"    -> Up / Down arrows; d-pad, left stick      (PLACE: move within the
#                             panel's column; PICK and DONE: deliberately inert, focus stays)
#   "ui_accept"            -> Enter, Space; pad A [Cross]              (press the focused offer,
#                             Skip, choice or Continue)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]      (PLACE: the panel reads it
#                             first and steps back one step; otherwise the pause menu opens)
#   Mouse: clicks on the same buttons; the panel's backdrop takes clicks outside it.
# Hint contexts: PICK while the pick is open, PLACE while the panel is shown, DONE once Continue
# is open, BOSS for the Boss's End run.
# ============================================================

var _seat: int = 0
var _model: CombatResultsModel = null
var _is_leaving: bool = false

# The offer the placement panel is placing; ItemPickCommand.SKIP while it is closed.
var _offer_index: int = ItemPickCommand.SKIP

@onready var _header: RunHeader = %RunHeader
@onready var _grades: GradesPanel = %GradesPanel
@onready var _level_ups: LevelUpPanel = %LevelUpPanel
@onready var _pick_panel: ItemPickPanel = %ItemPickPanel
@onready var _xp_panel: XpPanel = %XpPanel
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _placement_panel: PlacementPanel = %PlacementPanel
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.COMBAT_RESULTS:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = session.seats[0]
	_pick_panel.offer_chosen.connect(_on_pick_panel_offer_chosen)
	_pick_panel.skip_chosen.connect(_on_pick_panel_skip_chosen)
	_placement_panel.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement_panel.cancelled.connect(_on_placement_panel_cancelled)
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_refresh()
	_focus_default.call_deferred()


## The model shown, for tests.
func get_model() -> CombatResultsModel:
	return _model


## The item pick's panel, for tests.
func get_pick_panel() -> ItemPickPanel:
	return _pick_panel


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement_panel


## The Continue (or End run) button, for tests.
func get_continue_button() -> Button:
	return _continue_button


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# Reads the run again and shows it; note replaces the pick's outcome line when not empty.
func _refresh(note: String = "") -> void:
	var session: CampaignSession = CampaignService.session
	_model = CombatResultsModel.build(session, _seat)
	_header.show_run(session.run, _seat)
	if _model == null:
		_status_label.text = "This combat's report couldn't be read; see the log."
		_continue_button.disabled = true
		return
	_header.title = "Boss defeated" if _model.is_boss else "Victory"
	_grades.show_grades(_model.grades)
	_level_ups.show_level_ups(_model)
	_xp_panel.show_xp(_model)
	_pick_panel.show_pick(_model, note)
	var can_go: bool = _model.can_continue()
	_continue_button.text = "End run" if _model.is_boss else "Continue"
	_continue_button.disabled = not can_go
	_continue_button.focus_mode = Control.FOCUS_ALL if can_go else Control.FOCUS_NONE
	var self_path: NodePath = _continue_button.get_path_to(_continue_button)
	for side: StringName in [
		&"focus_neighbor_left", &"focus_neighbor_right",
		&"focus_neighbor_top", &"focus_neighbor_bottom",
	]:
		_continue_button.set(side, self_path)
	_update_hints()


func _update_hints() -> void:
	if _placement_panel.visible:
		_hints.context = &"PLACE"
	elif _model != null and not _model.can_continue():
		_hints.context = &"PICK"
	elif _model != null and _model.is_boss:
		_hints.context = &"BOSS"
	else:
		_hints.context = &"DONE"


# Focus where the player acts next: the first offer while the pick is open, else Continue.
func _focus_default() -> void:
	if _placement_panel.visible:
		return
	if not _pick_panel.focus_first() and not _continue_button.disabled:
		_continue_button.grab_focus()


func _submit(command: CampaignCommand) -> bool:
	var batch: CampaignBatch = CampaignService.submit_command(command)
	if batch == null or batch.is_rejected():
		var reason: String = batch.rejected_reason if batch != null else "no run in progress"
		if _placement_panel.visible:
			_placement_panel.show_problem("Can't do that: %s." % [reason])
		else:
			_status_label.text = "Can't do that: %s." % [reason]
		return false
	_status_label.text = ""
	return true


# What became of the taken item, for the pick's outcome line.
func _placement_note(index: int, placement: ItemPlacement) -> String:
	var seat_run: SeatRun = CampaignService.session.run.seat_run(_seat)
	var item: String = CombatResultsModel.item_name(
			_model.offers[index], _model.pick.offers[index].definition_id
	)
	match placement.destination:
		ItemPlacement.Destination.EQUIP:
			var unit_name: String = CombatResultsModel.unit_name(
					CampaignService.session.ids, seat_run, placement.unit_id, EffectCatalog.index()
			)
			return "%s equipped %s." % [unit_name, item]
		ItemPlacement.Destination.SCRAP:
			return "Scrapped %s for %d gold." % [
				item, ItemPlacement.scrap_value(_model.offers[index]),
			]
	return "%s went to the convoy." % [item]


func _on_pick_panel_offer_chosen(index: int) -> void:
	var session: CampaignSession = CampaignService.session
	_offer_index = index
	_placement_panel.open(
			session.run.seat_run(_seat), _model.offers[index],
			_model.pick.offers[index].definition_id, EffectCatalog.index(), session.ids
	)
	_update_hints()


func _on_pick_panel_skip_chosen() -> void:
	if _submit(ItemPickCommand.new(_seat, ItemPickCommand.SKIP)):
		_refresh()
		_focus_default()


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	var index: int = _offer_index
	if not _submit(ItemPickCommand.new(_seat, index, placement)):
		return
	var note: String = _placement_note(index, placement)
	_offer_index = ItemPickCommand.SKIP
	_placement_panel.close()
	_refresh(note)
	_focus_default()


func _on_placement_panel_cancelled() -> void:
	_offer_index = ItemPickCommand.SKIP
	_update_hints()
	_pick_panel.focus_first()


func _on_continue_button_pressed() -> void:
	if _is_leaving or _model == null or not _model.can_continue():
		return
	if _model.is_boss:
		var err: Error = CampaignService.end_won_run()
		if CampaignService.session != null:
			_status_label.text = "Couldn't end the run (%s)." % [error_string(err)]
			return
		_is_leaving = true
		SceneRouter.goto_screen(SceneRouter.Screen.RESULTS)
		return
	if not _submit(LeaveNodeCommand.new(_seat)):
		return
	_is_leaving = true
	RunScreen.go()
