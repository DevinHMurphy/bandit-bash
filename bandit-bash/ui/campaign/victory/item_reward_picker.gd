# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_reward_picker.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemRewardPicker
extends RewardPicker
## The item pick's picker: the offers and Skip ([ItemPickPanel]) in a modal, then where a taken
## item goes ([PlacementPanel]). A take with its placement goes as one [ItemPickCommand], Skip as
## another; either resolves the pick, so its row leaves the list, and its facts play
## ([CampaignPlayback]), which sound the take and the scrap (GAINED, ITEM_SCRAPPED). A rejection
## shows its reason and changes nothing. Back, or ui_cancel, closes it untouched.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, except where noted):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick   (PICK: move along the offers
#                             and Skip; the ends stop)
#   "ui_up" / "ui_down"    -> Up / Down arrows; d-pad, left stick      (PICK: between the row and
#                             Back; PLACE: the panel's column)
#   "ui_accept"            -> Enter, Space; pad A [Cross]              (press the focused choice)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]      (read in _input while shown:
#                             PICK closes the picker; PLACE: the panel reads it first and steps
#                             back; taken first, so the pause menu doesn't open over it)
#   Mouse: clicks on the same buttons; the backdrop takes clicks outside the panel.
# Hint contexts: PICK while the offers show, PLACE while the placement panel shows.
# ============================================================

## How dark the backdrop over the Rewards stage is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the stage hidden. 0.6 matches the [PlacementPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

var _reward: ItemPickReward = null
var _seat: int = 0
var _model: CombatResultsModel = null

# The offer the placement panel is placing; ItemPickCommand.SKIP while it is closed.
var _offer_index: int = ItemPickCommand.SKIP

@onready var _backdrop: ColorRect = %Backdrop
@onready var _pick_panel: ItemPickPanel = %ItemPickPanel
@onready var _status_label: Label = %Status
@onready var _back_button: Button = %BackButton
@onready var _placement_panel: PlacementPanel = %PlacementPanel


func _ready() -> void:
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_pick_panel.offer_chosen.connect(_on_pick_panel_offer_chosen)
	_pick_panel.skip_chosen.connect(_on_pick_panel_skip_chosen)
	_placement_panel.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement_panel.cancelled.connect(_on_placement_panel_cancelled)
	_back_button.pressed.connect(_on_back_button_pressed)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _placement_panel.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_button_pressed()


func open(reward: VictoryReward, seat: int) -> void:
	_reward = reward as ItemPickReward
	_seat = seat
	_offer_index = ItemPickCommand.SKIP
	_model = CombatResultsModel.build(CampaignService.session, seat)
	_status_label.text = ""
	visible = true
	if _model == null or _model.pick == null:
		_status_label.text = "This item pick couldn't be read; see the log."
		_back_button.grab_focus()
		return
	_pick_panel.show_pick(_model)
	_link_back()
	if not _pick_panel.focus_first():
		_back_button.grab_focus()
	hint_context_changed.emit()


func get_hint_context() -> StringName:
	return &"PLACE" if _placement_panel.visible else &"PICK"


## The offers and Skip, for tests.
func get_pick_panel() -> ItemPickPanel:
	return _pick_panel


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement_panel


## The Back button, for tests.
func get_back_button() -> Button:
	return _back_button


## The status line, for tests.
func get_status_text() -> String:
	return _status_label.text


# The offers row and Skip lead down to Back, and Back up to the first offer.
func _link_back() -> void:
	var row: Array[Control] = []
	for card: ItemOfferCard in _pick_panel.get_offer_cards():
		row.append(card)
	row.append(_pick_panel.get_skip_button())
	for control: Control in row:
		control.focus_neighbor_bottom = control.get_path_to(_back_button)
	var self_path: NodePath = _back_button.get_path_to(_back_button)
	_back_button.focus_neighbor_top = _back_button.get_path_to(row[0])
	_back_button.focus_neighbor_bottom = self_path
	_back_button.focus_neighbor_left = self_path
	_back_button.focus_neighbor_right = self_path


func _submit(command: CampaignCommand) -> bool:
	var batch: CampaignBatch = CampaignService.submit_command(command)
	if batch == null or batch.is_rejected():
		var reason: String = batch.rejected_reason if batch != null else "no run in progress"
		if _placement_panel.visible:
			_placement_panel.show_problem("Can't do that: %s." % [reason])
		else:
			_status_label.text = "Can't do that: %s." % [reason]
		return false
	CampaignPlayback.play_pending(CampaignService.session)
	return true


# What became of the taken item, for the overlay's status line.
func _placement_note(index: int, placement: ItemPlacement) -> String:
	var session: CampaignSession = CampaignService.session
	var seat_run: SeatRun = session.run.seat_run(_seat)
	var item: String = CombatResultsModel.item_name(
			_model.offers[index], _model.pick.offers[index].definition_id
	)
	match placement.destination:
		ItemPlacement.Destination.EQUIP:
			var unit_name: String = CombatResultsModel.unit_name(
					session.ids, seat_run, placement.unit_id, EffectCatalog.index()
			)
			return "%s equipped %s." % [unit_name, item]
		ItemPlacement.Destination.SCRAP:
			return "Scrapped %s for %d gold." % [
				item, ItemPlacement.scrap_value(_model.offers[index], seat_run),
			]
	return "%s went to the convoy." % [item]


func _close() -> void:
	_placement_panel.close()
	visible = false


func _on_pick_panel_offer_chosen(index: int) -> void:
	var session: CampaignSession = CampaignService.session
	_offer_index = index
	_placement_panel.open(
			session.run.seat_run(_seat), _model.offers[index],
			_model.pick.offers[index].definition_id, EffectCatalog.index(), session.ids
	)
	hint_context_changed.emit()


func _on_pick_panel_skip_chosen() -> void:
	if not _submit(ItemPickCommand.new(_seat, ItemPickCommand.SKIP)):
		return
	_close()
	resolved.emit("Skipped the item pick.")


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	var index: int = _offer_index
	if not _submit(ItemPickCommand.new(_seat, index, placement)):
		return
	var note: String = _placement_note(index, placement)
	_offer_index = ItemPickCommand.SKIP
	_close()
	resolved.emit(note)


func _on_placement_panel_cancelled() -> void:
	_offer_index = ItemPickCommand.SKIP
	hint_context_changed.emit()
	_pick_panel.focus_first()


func _on_back_button_pressed() -> void:
	_close()
	cancelled.emit()
