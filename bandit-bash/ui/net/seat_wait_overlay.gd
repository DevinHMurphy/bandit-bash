# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     seat_wait_overlay.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SeatWaitOverlay
extends CanvasLayer
## While the run is paused, over every screen of every peer: whom it waits for and how long, one
## line per seat ("Waiting for <name> · m:ss"), or, on a client that lost the host, "Reconnecting
## to <name>". Its relay ([method follow]) decides; it shows while the relay waits for anyone.[br]
## It keeps clicks from the screen beneath; keys still reach that screen's own handlers, whose
## commands settle "paused". Its layer sits under the pause menu's, so Esc's menu opens above it.
## [b]Buttons:[/b] the host's Save & Quit (as the pause menu's: the run resumes from that save), a
## client's Leave Match, and the host's Remove for the seat that has waited longest once it has
## waited [constant NetRelay.REMOVE_WAIT] s: that seat leaves the run as removed (no archive
## record), then the directory. [b]Focus:[/b] its first button has it while shown, taking it back
## from the screen beneath but never from a higher layer; on hiding, the control focused before has
## it.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_accept"            -> Enter, Space; pad A [Cross] (press the focused button)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick   (move along the button row: Remove)
#   Mouse: clicks on the buttons; any other click stops on this layer.
# Nothing is read here; Esc reaches the pause menu above, which opens over this.
# ============================================================

const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

# Seconds in a minute, for the m:ss waited.
const _SECONDS_PER_MINUTE: int = 60

var _relay: NetRelayScript = null

# The control that had focus when the overlay showed, given it back when it hides; null for none.
var _focus_before: Control = null

# The seat Remove acts on, as the last refresh found it; NO_SEAT while it is hidden.
var _removable_seat: int = SeatDirectory.NO_SEAT

@onready var _title_label: Label = %Title
@onready var _lines_label: Label = %Lines
@onready var _status_label: Label = %Status
@onready var _leave_button: Button = %LeaveButton
@onready var _remove_button: Button = %RemoveButton


func _ready() -> void:
	visible = false
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_remove_button.pressed.connect(_on_remove_button_pressed)
	_remove_button.visible = false
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Shows what [param relay] waits for from now on, refreshed every frame.
func follow(relay: NetRelayScript) -> void:
	_relay = relay
	refresh()


## Shows the relay's waits as they are now, with Remove when a seat may be removed, or hides when
## it waits for nobody, and keeps focus on the first button while shown. [method Node._process]
## calls it each frame; tests call it to stand for one.
func refresh() -> void:
	if not is_node_ready():
		return
	var waiting: PackedInt32Array = []
	if is_instance_valid(_relay):
		waiting = _relay.waiting_seats()
	var was_visible: bool = visible
	if not was_visible and not waiting.is_empty():
		var focused: Control = _leave_button.get_viewport().gui_get_focus_owner()
		_focus_before = null if focused != null and is_ancestor_of(focused) else focused
		_status_label.text = ""
	visible = not waiting.is_empty()
	_removable_seat = _seat_to_remove(waiting) if visible else SeatDirectory.NO_SEAT
	_remove_button.visible = _removable_seat != SeatDirectory.NO_SEAT
	if not visible:
		if was_visible:
			_give_focus_back()
		return
	var is_lost: bool = _relay.is_host_lost()
	_title_label.text = "Connection lost" if is_lost else "Waiting for players"
	var lines: PackedStringArray = []
	for seat: int in waiting:
		var form: String = "Reconnecting to %s · %s" if is_lost else "Waiting for %s · %s"
		lines.append(form % [_seat_name(seat), _clock(_relay.waited(seat))])
	_lines_label.text = "\n".join(lines)
	_leave_button.text = "Save & Quit" if _is_host() else "Leave Match"
	if _remove_button.visible:
		_remove_button.text = "Remove %s" % [_seat_name(_removable_seat)]
	_keep_focus()


## The button focus starts on.
func get_default_focus() -> Control:
	return _leave_button


# Whether this machine hosts the run: it decides, and hasn't lost a host.
func _is_host() -> bool:
	return (
			is_instance_valid(_relay)
			and NetGate.is_authoritative(_relay.multiplayer)
			and not _relay.is_host_lost()
	)


# Gives the first button focus unless it is here already or on a layer above (the pause menu).
func _keep_focus() -> void:
	var focused: Control = _leave_button.get_viewport().gui_get_focus_owner()
	if focused != null and focused.is_visible_in_tree():
		if is_ancestor_of(focused) or _layer_of(focused) > layer:
			return
	_leave_button.grab_focus()


# The seat of waiting the host may remove now: the one waited for longest (the lowest on a tie),
# once that is at least NetRelay.REMOVE_WAIT; NO_SEAT off the host or before any wait has run.
func _seat_to_remove(waiting: PackedInt32Array) -> int:
	if not _is_host():
		return SeatDirectory.NO_SEAT
	var chosen: int = SeatDirectory.NO_SEAT
	var longest: float = NetRelayScript.REMOVE_WAIT
	for seat: int in waiting:
		var waited_for: float = _relay.waited(seat)
		if waited_for >= longest and (chosen == SeatDirectory.NO_SEAT or waited_for > longest):
			chosen = seat
			longest = waited_for
	return chosen


func _give_focus_back() -> void:
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null


# The name seat is shown by: its Steam name when Steam has it, else "Player 2" and on.
func _seat_name(seat: int) -> String:
	if _relay.seats != null and SteamManager.is_available:
		var steam_id: int = _relay.seats.steam_id_of_seat(seat)
		if steam_id != SeatDirectory.NO_STEAM_ID:
			var shown: String = SteamNetwork.get_member_name(steam_id)
			if not shown.is_empty():
				return shown
	return CampaignLink.seat_name(seat)


func _on_leave_button_pressed() -> void:
	if _is_host():
		var err: Error = SaveService.save_checkpoint()
		if err != OK:
			_status_label.text = "Couldn't save (%s). The game was not closed." % [
				error_string(err),
			]
			return
	SceneRouter.goto_screen(SceneRouter.Screen.MAIN_MENU)


# The run first, so a refusal leaves the seat waited for: it leaves as removed, with no archive
# record, then the directory lets it go and every peer hears it.
func _on_remove_button_pressed() -> void:
	var seat: int = _removable_seat
	if seat == SeatDirectory.NO_SEAT or not _is_host():
		return
	var name_shown: String = _seat_name(seat)
	var batch: CampaignBatch = CampaignService.forfeit_seat(seat, true)
	if batch == null or batch.is_rejected():
		var reason: String = "no run" if batch == null else batch.rejected_reason
		_status_label.text = "Couldn't remove %s (%s)." % [name_shown, reason]
		return
	if not _relay.remove_seat(seat):
		_status_label.text = "%s left the run but is still waited for." % [name_shown]
		return
	_status_label.text = ""
	refresh()


# The canvas layer node is drawn on: its nearest CanvasLayer's, else 0, the screens' own.
static func _layer_of(node: Node) -> int:
	var at: Node = node
	while at != null:
		var canvas: CanvasLayer = at as CanvasLayer
		if canvas != null:
			return canvas.layer
		at = at.get_parent()
	return 0


# seconds as m:ss, whole seconds only.
static func _clock(seconds: float) -> String:
	var whole: int = floori(seconds)
	var minutes: int = floori(seconds / float(_SECONDS_PER_MINUTE))
	return "%d:%02d" % [minutes, whole - minutes * _SECONDS_PER_MINUTE]
