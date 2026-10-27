# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_select_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: October 27, 2026
# ==============================================================================

extends Control
## Save Select: the player chooses a save file before reaching the Main Menu.
##
## Entered from Start on every launch; there is no way to the Main Menu without choosing a file.
## Entering this screen closes any open save file.[br]
## One card per save file is built in code from [code]SaveService.SAVE_FILE_COUNT[/code], so the
## count lives in one place. Choosing an empty card creates that save file. Delete always asks for
## confirmation. Focus starts on the last selected file.

# Save number waiting on the delete confirmation dialog.
var _pending_delete: int = 0
# Open/New button per save number, for initial focus.
var _open_buttons: Dictionary[int, Button] = {}

@onready var _status_label: Label = %Status
@onready var _cards: VBoxContainer = %Cards
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog


func _ready() -> void:
	_delete_dialog.confirmed.connect(_on_delete_dialog_confirmed)
	SaveService.close_save_file()
	_rebuild_cards()
	_focus_card(SaveService.get_last_selected())


func _rebuild_cards() -> void:
	for child: Node in _cards.get_children():
		child.queue_free()
	_open_buttons.clear()

	var notices: PackedStringArray = []
	for save_number: int in range(1, SaveService.SAVE_FILE_COUNT + 1):
		var summary: SaveFileSummary = SaveService.get_summary(save_number)
		_cards.add_child(_build_card(summary))
		if summary.was_recovered:
			notices.append("Save %d was restored from its backup copy." % [save_number])
	_status_label.text = "\n".join(notices)


func _build_card(summary: SaveFileSummary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var column: VBoxContainer = VBoxContainer.new()
	card.add_child(column)

	var title: Label = Label.new()
	title.text = "Save %d" % [summary.save_number]
	column.add_child(title)

	var detail: Label = Label.new()
	detail.text = _describe(summary)
	column.add_child(detail)

	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)

	var open_button: Button = Button.new()
	var is_empty: bool = summary.state == SaveFileSummary.State.EMPTY
	open_button.text = "New" if is_empty else "Open"
	open_button.disabled = not (is_empty or summary.state == SaveFileSummary.State.READY)
	open_button.pressed.connect(_on_open_button_pressed.bind(summary.save_number))
	buttons.add_child(open_button)
	_open_buttons[summary.save_number] = open_button

	var delete_button: Button = Button.new()
	delete_button.text = "Delete"
	delete_button.visible = not is_empty
	delete_button.pressed.connect(_on_delete_button_pressed.bind(summary.save_number))
	buttons.add_child(delete_button)

	return card


func _describe(summary: SaveFileSummary) -> String:
	match summary.state:
		SaveFileSummary.State.READY:
			var player_name: String = summary.player_name
			if player_name.is_empty():
				player_name = "Unknown player"
			var played: String = _format_play_time(summary.play_time_seconds)
			return "%s  ·  %s played\n%s\n%s" % [
				player_name, played, _describe_solo(summary), _describe_multi(summary)
			]
		SaveFileSummary.State.UNREADABLE:
			return "Can't be read. Delete it to reuse this slot."
		SaveFileSummary.State.TOO_NEW:
			return "Made by a newer version of the game."
	return "Empty"


func _describe_solo(summary: SaveFileSummary) -> String:
	match summary.solo_state:
		SaveFileSummary.State.READY:
			return "Solo run: floor %d, last played %s" % [
				summary.solo_floors_climbed, _format_local_time(summary.solo_last_opened)
			]
		SaveFileSummary.State.UNREADABLE:
			return "Solo run can't be read."
		SaveFileSummary.State.TOO_NEW:
			return "Solo run made by a newer version of the game."
	return "No solo run"


func _describe_multi(summary: SaveFileSummary) -> String:
	match summary.multi_state:
		SaveFileSummary.State.READY:
			return "Hosted campaign: %d players, last played %s" % [
				summary.multi_player_count, _format_local_time(summary.multi_last_opened)
			]
		SaveFileSummary.State.UNREADABLE:
			return "Hosted campaign can't be read."
		SaveFileSummary.State.TOO_NEW:
			return "Hosted campaign made by a newer version of the game."
	return "No hosted campaign"


# Saved times are UTC; shown in the player's time zone.
func _format_local_time(unix_seconds: int) -> String:
	var bias_minutes: int = Time.get_time_zone_from_system().get("bias", 0) as int
	return Time.get_datetime_string_from_unix_time(unix_seconds + bias_minutes * 60, true)


# Whole hours and minutes; leftover seconds are dropped on purpose.
func _format_play_time(seconds: int) -> String:
	# Truncation is the point (above). On each statement: 4.7 ignores it on the func for the body.
	@warning_ignore("integer_division")
	var minutes: int = seconds / 60
	@warning_ignore("integer_division")
	return "%dh %02dm" % [minutes / 60, minutes % 60]


# Focuses the given save's button, or the first enabled one when it has none or is disabled.
func _focus_card(save_number: int) -> void:
	var target: Button = _open_buttons.get(save_number)
	if target == null or target.disabled:
		target = null
		for candidate: Button in _open_buttons.values():
			if not candidate.disabled:
				target = candidate
				break
	if target != null:
		target.grab_focus.call_deferred()


func _on_open_button_pressed(save_number: int) -> void:
	var err: Error = SaveService.open_save_file(save_number)
	if err != OK:
		_status_label.text = "Couldn't open save %d (%s)." % [save_number, error_string(err)]
		return
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


func _on_delete_button_pressed(save_number: int) -> void:
	_pending_delete = save_number
	_delete_dialog.dialog_text = "Delete save %d? This can't be undone." % [save_number]
	_delete_dialog.popup_centered()


func _on_delete_dialog_confirmed() -> void:
	var save_number: int = _pending_delete
	var err: Error = SaveService.delete_save_file(save_number)
	_rebuild_cards()
	if err != OK:
		_status_label.text = "Couldn't delete save %d (%s)." % [save_number, error_string(err)]
	_focus_card(save_number)
