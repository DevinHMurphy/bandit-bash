# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_heirloom_picker.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name KeyHeirloomPicker
extends RewardPicker
## A Key combat's heirloom in a modal: the heirloom as an [HeirloomOfferCard], which takes it when
## pressed ([KeyHeirloomCommand], through a [CampaignLink]), and Back. Once the take resolves the
## offer is settled, so its row leaves the list, and its facts play ([CampaignPlayback]), sounding
## the gain. A refusal shows its reason and changes nothing. Back, or ui_cancel, closes it
## untouched; the overlay's Leave gives the heirloom up.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, except where noted):
#   "ui_up" / "ui_down" -> Up / Down arrows; d-pad, left stick  (between the card and Back)
#   "ui_accept"         -> Enter, Space; pad A [Cross]           (press the focused choice)
#   "ui_cancel"         -> Esc; pad B [Circle], Menu [Options]   (read in _input while shown:
#                          closes the picker, taken first, so the pause menu doesn't open over it)
#   Mouse: clicks on the card or Back; the backdrop takes clicks outside the panel.
# Hint context: PICK.
# ============================================================

## How dark the backdrop over the Rewards stage is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the stage hidden. 0.6 matches the [PlacementPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

var _seat: int = 0
var _link: CampaignLink = null
# The heirloom the card shows, which the take names, so a teammate's first claim of a unique one
# refuses it by name instead of taking the replacement unseen. Empty: none shown.
var _shown_heirloom_id: String = ""

@onready var _backdrop: ColorRect = %Backdrop
@onready var _card: HeirloomOfferCard = %HeirloomCard
@onready var _status_label: Label = %Status
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_card.pressed.connect(_on_card_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	_card.focus_neighbor_bottom = _card.get_path_to(_back_button)
	_back_button.focus_neighbor_top = _back_button.get_path_to(_card)
	for control: Control in [_card, _back_button]:
		var self_path: NodePath = control.get_path_to(control)
		control.focus_neighbor_left = self_path
		control.focus_neighbor_right = self_path
	_card.focus_neighbor_top = _card.get_path_to(_card)
	_back_button.focus_neighbor_bottom = _back_button.get_path_to(_back_button)


func _exit_tree() -> void:
	if _link != null:
		_link.close()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_button_pressed()


func open(_reward: VictoryReward, seat: int) -> void:
	_seat = seat
	if _link != null:
		_link.close()
	_link = CampaignLink.new(CampaignService.session, seat, CampaignService.submit_command)
	_link.refused.connect(_on_link_refused)
	_status_label.text = ""
	_shown_heirloom_id = ""
	visible = true
	var model: CombatResultsModel = CombatResultsModel.build(CampaignService.session, seat)
	if model == null or model.key_heirloom == null:
		_status_label.text = "This heirloom couldn't be read; see the log."
		_card.visible = false
		_back_button.grab_focus()
		return
	_card.visible = true
	_shown_heirloom_id = model.key_heirloom.heirloom_id
	_card.show_heirloom(model.key_heirloom_definition, _shown_heirloom_id, "")
	_card.grab_focus()
	hint_context_changed.emit()


## The heirloom's card, for tests.
func get_card() -> HeirloomOfferCard:
	return _card


## The Back button, for tests.
func get_back_button() -> Button:
	return _back_button


## The status line, for tests.
func get_status_text() -> String:
	return _status_label.text


func _on_card_pressed() -> void:
	_link.send(KeyHeirloomCommand.new(_seat, true, _shown_heirloom_id), _on_take_resolved)


func _on_take_resolved(_batch: CampaignBatch) -> void:
	CampaignPlayback.play_pending(CampaignService.session)
	visible = false
	resolved.emit("Took %s." % [_card.heirloom_name])


func _on_link_refused(reason: String) -> void:
	if visible:
		_status_label.text = "Can't take it: %s." % [reason]


func _on_back_button_pressed() -> void:
	visible = false
	cancelled.emit()
