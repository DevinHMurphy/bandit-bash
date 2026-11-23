# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_battle.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name CoopBattle
extends HintSource
## The battle screen's co-op parts, for one seat ([BattleScreen] binds it in a battle of more than
## one map): the [CoopBar], the [MapsPanel] that views any map, the [SendPanel], the frozen map's
## [FrozenBanner] and the [WaitingBanner]. It sends the seat's [SendUnitsCommand]s and
## [CallForAidCommand]s, never other commands, and asks the screen to view a map
## ([signal view_requested]); turn input on that map is [BattleController]'s, held off while a panel
## here takes the keys ([method BattleController.set_held]). The send panel opens by itself once the
## seat's own map is won and its end banner has shown ([member send_offer_delay]) whenever it can
## send, and again when a map freezes. [signal run_lost] fires once the run can't be saved. It reads
## the encounter each frame, so it works the same on a host and on a client's mirror. In co-op it is
## the hint bar's source, passing the controller's contexts through.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

# ============================================================
# INPUT MAP SETUP (named actions in project.godot; ui_* are Godot's built-in actions):
#   "cycle_weapon"  -> C; X [Square]   (read in _unhandled_input while bound, no panel here is
#                                        open and BattleController.can_open_maps() allows it: its
#                                        SWAP, SWAP_PICKED, IDLE, MOVE and INACTIVE, or nothing
#                                        bound once the viewed map has ended: opens the maps
#                                        panel. Deliberate reuse by stage, as the controller does
#                                        nothing with it there; its forecast use is untouched)
#   ui_up / ui_down / ui_left / ui_right / ui_accept / ui_cancel   (in the panels, through the
#                                        GUI and their own _input: see MapsPanel and SendPanel)
#   Mouse: the CoopBar's Maps and call for aid; the panels' rows and buttons.
# ASSUMPTION: no pad button is free, so cycle_weapon is reused (P11 question 130); no basis in
# Godot_FE, which had no co-op battle screen.
# Hint contexts: MAPS, SEND, SEND_CONFIRM while a panel is open; otherwise the controller's
# context with cycle_weapon added where it opens the panel; WAITING once nothing is bound.
# ============================================================

## The seat asked to view the map [param session_id].
signal view_requested(session_id: int)

## The run was found lost ([method CombatEncounter.is_run_lost]): sent once per bind.
signal run_lost()

## The actions live in each of this node's own hint contexts, in the hint bar's order.
const LIVE_ACTIONS: Dictionary[StringName, Array] = {
	&"MAPS": [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"],
	&"SEND": [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"],
	&"SEND_CONFIRM": [&"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"],
	&"WAITING": [&"cycle_weapon", &"ui_cancel", &"toggle_save_debug"],
}

## The controller's hint contexts in which cycle_weapon opens the maps panel.
const MAPS_CONTEXTS: Array[StringName] = [&"SWAP", &"SWAP_PICKED", &"IDLE", &"MOVE", &"INACTIVE"]

## The turn input whose stage the panels respect, held off while a panel is open.[br]
## [b]Unset:[/b] [method bind] reports an error and nothing shows.
@export var controller: BattleController = null

## The hint bar, which reads this node in co-op and gives the [CoopBar] room
## ([member hint_bar_right_margin]); given back as it was on [method unbind].[br]
## [b]Unset:[/b] the hints stay the controller's, and the panels show none.
@export var hint_bar: ControlHintBar = null

## Where a refused send or call for aid shows its reason.[br]
## [b]Unset:[/b] the send panel shows a send's refusal; a call's is only logged by the session.
@export var message: BattleMessage = null

## How long after the seat's own map ends the send panel may open by itself, so the end banner
## shows first; [BattleScreen] sets it to its [member BattleScreen.end_banner_time].[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it may open as soon as the map ends.
@export_range(0.0, 10.0, 0.1) var send_offer_delay: float = 2.0

## The hint bar's right margin in co-op, so its line ends left of the [CoopBar].[br]
## [b]Units:[/b] base units from the right edge.
@export_range(0.0, 2000.0, 1.0) var hint_bar_right_margin: float = 636.0

var _encounter: CombatEncounter = null
var _seat: int = -1
var _viewed_id: int = -1
# Whether the seat's own map has ended and send_offer_delay has passed since.
var _is_offer_ready: bool = false
var _is_offer_timing: bool = false
# The offer state the seat closed the send panel in; it opens by itself again only once it changes.
var _dismissed_offer: String = ""
var _is_run_lost: bool = false
# The map a send or call was submitted on and not yet settled (-1: none), and whether it is a send.
var _pending_map: int = -1
var _is_pending_send: bool = false
# The hint bar's source and margin before bind(), given back by unbind().
var _kept_source: HintSource = null
var _kept_margin: float = 0.0
var _has_kept_hints: bool = false
# What the panels last drew from: refreshed only when it changes.
var _drawn: String = ""

@onready var _bar: CoopBar = %CoopBar
@onready var _banners: Control = %Banners
@onready var _frozen: FrozenBanner = %FrozenBanner
@onready var _waiting: WaitingBanner = %WaitingBanner
@onready var _maps_panel: MapsPanel = %MapsPanel
@onready var _send_panel: SendPanel = %SendPanel


func _ready() -> void:
	_show_parts(false)
	_bar.maps_pressed.connect(_on_coop_bar_maps_pressed)
	_bar.aid_requested.connect(_on_aid_requested)
	_maps_panel.view_requested.connect(_on_maps_panel_view_requested)
	_maps_panel.aid_requested.connect(_on_aid_requested)
	_maps_panel.send_requested.connect(_on_maps_panel_send_requested)
	_maps_panel.closed.connect(_on_panel_closed)
	_send_panel.send_confirmed.connect(_on_send_panel_send_confirmed)
	_send_panel.closed.connect(_on_send_panel_closed)


func _exit_tree() -> void:
	unbind()


func _unhandled_input(event: InputEvent) -> void:
	if _encounter == null or not event.is_action_pressed(&"cycle_weapon"):
		return
	if open_maps():
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _encounter != null:
		refresh()


## Shows the co-op parts for [param seat] of [param encounter], its map [param viewed_id] viewed.
## Does nothing in a battle of one map. Binding again replaces it.
func bind(encounter: CombatEncounter, seat: int, viewed_id: int) -> void:
	unbind()
	if encounter == null or encounter.seats.size() <= 1:
		return
	if controller == null:
		push_error("CoopBattle: the controller must be set")
		return
	_encounter = encounter
	_seat = seat
	_viewed_id = viewed_id
	_is_offer_ready = false
	_is_offer_timing = false
	_dismissed_offer = ""
	_is_run_lost = false
	_pending_map = -1
	_drawn = ""
	for map: CombatSession in encounter.get_sessions():
		map.command_rejected.connect(_on_session_command_rejected.bind(map.session_id))
	var service: Node = _campaign_service()
	if service != null:
		service.connect(&"combat_settled", _on_campaign_service_combat_settled)
	controller.live_actions_changed.connect(_on_controller_live_actions_changed)
	if hint_bar != null:
		_kept_source = hint_bar.controller
		_kept_margin = hint_bar.right_margin
		_has_kept_hints = true
		hint_bar.controller = self
		hint_bar.right_margin = hint_bar_right_margin
	_show_parts(true)
	refresh()


## Hides every part and gives the hint bar back. Does nothing when nothing is bound.
func unbind() -> void:
	if _encounter == null:
		return
	close_panels()
	for map: CombatSession in _encounter.get_sessions():
		for connection: Dictionary in map.command_rejected.get_connections():
			var callable: Callable = connection[&"callable"]
			if callable.get_object() == self:
				map.command_rejected.disconnect(callable)
	var service: Node = _campaign_service()
	if service != null and service.is_connected(
			&"combat_settled", _on_campaign_service_combat_settled
	):
		service.disconnect(&"combat_settled", _on_campaign_service_combat_settled)
	if is_instance_valid(controller) and controller.live_actions_changed.is_connected(
			_on_controller_live_actions_changed
	):
		controller.live_actions_changed.disconnect(_on_controller_live_actions_changed)
	if _has_kept_hints and is_instance_valid(hint_bar):
		hint_bar.controller = _kept_source
		hint_bar.right_margin = _kept_margin
	_has_kept_hints = false
	_kept_source = null
	_encounter = null
	_seat = -1
	_viewed_id = -1
	_show_parts(false)


## Whether a co-op battle is bound.
func is_bound() -> bool:
	return _encounter != null


## The screen now views the map [param session_id].
func show_viewed(session_id: int) -> void:
	_viewed_id = session_id
	_drawn = ""
	if _encounter != null:
		refresh()


## The map viewed; -1 while unbound.
func get_viewed() -> int:
	return _viewed_id


## Opens the maps panel, holding turn input off, where [method BattleController.can_open_maps]
## allows. Returns whether it opened.
func open_maps() -> bool:
	if _encounter == null or _is_run_lost or is_panel_open():
		return false
	if not controller.can_open_maps():
		return false
	controller.set_held(true)
	_drawn = ""
	_draw_maps_panel()
	live_actions_changed.emit()
	return true


## Opens the send panel, holding turn input off, while the seat may send
## ([method CoopViewModel.can_send]); from the maps panel too. Returns whether it opened.
func open_send() -> bool:
	if _encounter == null or _is_run_lost or not CoopViewModel.can_send(_encounter, _seat):
		return false
	if _send_panel.visible:
		return true
	if not _maps_panel.visible and not controller.can_open_maps():
		return false
	_maps_panel.close()
	controller.set_held(true)
	_send_panel.open(_encounter, _seat)
	live_actions_changed.emit()
	return true


## Closes any panel here and gives turn input back.
func close_panels() -> void:
	var was_open: bool = is_panel_open()
	_maps_panel.close()
	_send_panel.close()
	if is_instance_valid(controller):
		controller.set_held(false)
	if was_open:
		live_actions_changed.emit()


## Whether the maps panel or the send panel is open.
func is_panel_open() -> bool:
	return _maps_panel.visible or _send_panel.visible


## Raises ([param is_raised] true) or lowers the seat's call for aid on its own map. Returns
## whether the command was sent.
func request_aid(is_raised: bool) -> bool:
	var own: CombatSession = null if _encounter == null else _encounter.session_of_seat(_seat)
	if own == null or own.is_finished or _pending_map >= 0:
		return false
	_submit(CallForAidCommand.new(_seat, is_raised), own.session_id, false)
	return true


## Sends [param unit_ids] from the won map [param source_id] to [param target_id] (none and
## [constant SendUnitsCommand.NO_TARGET]: Send none), as the send panel confirms. Returns whether
## the command was sent.
func send(unit_ids: PackedStringArray, source_id: int, target_id: int) -> bool:
	if _encounter == null or source_id < 0 or _pending_map >= 0:
		return false
	_submit(SendUnitsCommand.new(_seat, unit_ids, target_id), source_id, true)
	return true


## Whether the run was found lost and its banner shows.
func is_run_lost_shown() -> bool:
	return _is_run_lost


## The maps panel, for tests.
func get_maps_panel() -> MapsPanel:
	return _maps_panel


## The send panel, for tests.
func get_send_panel() -> SendPanel:
	return _send_panel


## The strip, for tests.
func get_bar() -> CoopBar:
	return _bar


## The frozen map's banner, for tests.
func get_frozen_banner() -> FrozenBanner:
	return _frozen


## The waiting banner, for tests.
func get_waiting_banner() -> WaitingBanner:
	return _waiting


func get_hint_context() -> StringName:
	if _encounter == null:
		return &""
	if _send_panel.visible:
		return &"SEND_CONFIRM" if _send_panel.is_confirming() else &"SEND"
	if _maps_panel.visible:
		return &"MAPS"
	var context: StringName = controller.get_hint_context()
	if not context.is_empty() or _is_run_lost or _encounter.is_finished():
		return context
	return &"WAITING"


func get_live_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	var context: StringName = get_hint_context()
	if LIVE_ACTIONS.has(context):
		for action: StringName in LIVE_ACTIONS[context]:
			if action != &"toggle_save_debug" or OS.is_debug_build():
				actions.append(action)
		return actions
	actions = controller.get_live_actions()
	if context in MAPS_CONTEXTS and controller.can_open_maps():
		# Before the pause menu's Esc, which every one of these rows ends with.
		var at: int = actions.find(&"ui_cancel")
		actions.insert(at if at >= 0 else actions.size(), &"cycle_weapon")
	return actions


## Reads the encounter: the run's loss, the strip, the banners, an open panel and the send offer;
## all but the loss check redraw only when the battle or the view moved. Each frame calls it;
## tests call it to stand for a frame.
func refresh() -> void:
	if _encounter == null:
		return
	if not _is_run_lost and _encounter.is_run_lost():
		_is_run_lost = true
		close_panels()
		_drawn = ""
		run_lost.emit()
	var own: CombatSession = _encounter.session_of_seat(_seat)
	if own != null and _viewed_id != own.session_id and _encounter.is_map_forfeited(_viewed_id):
		# A forfeited map leaves every view: back to the seat's own. A forfeit records no fact.
		view_requested.emit(own.session_id)
		return
	var drawn: String = _state_key()
	if drawn == _drawn:
		return
	_drawn = drawn
	_start_offer_timer(own)
	var viewed: CombatSession = _encounter.get_session(_viewed_id)
	var is_teammate_calling: bool = false
	for shown: CoopViewModel.MapStatus in CoopViewModel.maps(_encounter, _seat):
		is_teammate_calling = is_teammate_calling or (
				not shown.is_own and shown.is_aid_called and not shown.is_finished
		)
	# ASSUMPTION: the strip's short names ("Yours", "Player 2"); no design doc words them.
	var whose: String = "Yours"
	if viewed != null and not viewed.seats.has(_seat) and not viewed.seats.is_empty():
		whose = CampaignLink.seat_name(CoopViewModel.owner_of(viewed))
	var is_own_open: bool = own != null and not own.is_finished and not _is_run_lost
	var is_aid_raised: bool = own != null and _encounter.is_aid_called(own.session_id)
	var is_aid_waiting: bool = _pending_map >= 0 and not _is_pending_send
	_bar.show_bar(whose, is_teammate_calling, is_aid_raised, is_own_open, is_aid_waiting)
	# Once the run is lost nothing here can be opened, so the strip goes.
	_bar.visible = not _is_run_lost
	_draw_banners(own, viewed)
	if _maps_panel.visible:
		_draw_maps_panel()
	if _send_panel.visible:
		if CoopViewModel.can_send(_encounter, _seat) or _pending_map >= 0:
			_send_panel.refresh()
		else:
			close_panels()
	_offer_send()


# What the parts draw from: every map's last seq, the encounter's facts and forfeits, the view,
# the pending command and the offer.
func _state_key() -> String:
	var parts: PackedStringArray = [
		str(_encounter.fact_log.size()), str(_viewed_id), str(_pending_map), str(_is_offer_ready),
		str(_is_run_lost), str(_encounter.forfeited_seats()),
	]
	for map: CombatSession in _encounter.get_sessions():
		parts.append(str(map.last_seq()))
	return ",".join(parts)


func _draw_banners(own: CombatSession, viewed: CombatSession) -> void:
	var is_frozen: bool = viewed != null and _encounter.is_frozen(viewed.session_id)
	_frozen.visible = is_frozen and not _is_run_lost
	if _frozen.visible:
		_frozen.show_map(CoopViewModel.map_title(viewed, _seat), viewed.seats.has(_seat))
	if _is_run_lost:
		_waiting.show_run_lost()
	elif own != null and own.is_finished and not _encounter.is_finished():
		_waiting.show_waiting(CoopViewModel.maps_left(_encounter))
	else:
		_waiting.visible = false


func _draw_maps_panel() -> void:
	var own: CombatSession = _encounter.session_of_seat(_seat)
	_maps_panel.show_maps(
			CoopViewModel.maps(_encounter, _seat),
			_viewed_id,
			own != null and _encounter.is_aid_called(own.session_id),
			own != null and not own.is_finished,
			_pending_map >= 0 and not _is_pending_send,
			CoopViewModel.can_send(_encounter, _seat)
	)


# Once the seat's own map has ended, offer_ready waits send_offer_delay, so the banner shows first.
func _start_offer_timer(own: CombatSession) -> void:
	if _is_offer_ready or _is_offer_timing or own == null or not own.is_finished:
		return
	if send_offer_delay <= 0.0 or not is_inside_tree():
		_is_offer_ready = true
		return
	_is_offer_timing = true
	var wait: SceneTreeTimer = get_tree().create_timer(send_offer_delay, false)
	wait.timeout.connect(_on_offer_timer_timeout.bind(_encounter))


# Opens the send panel by itself when the seat may send, its own map's banner has shown, the
# offer differs from the one it closed, and no unit's action is under way.
func _offer_send() -> void:
	if not _is_offer_ready or _is_run_lost or is_panel_open() or _pending_map >= 0:
		return
	if not CoopViewModel.can_send(_encounter, _seat) or _offer_key() == _dismissed_offer:
		return
	var stage: BattleController.Stage = controller.get_stage()
	if stage == BattleController.Stage.MOVE or stage == BattleController.Stage.SWAP_PICKED:
		return
	open_send()


# What the offer stands on: whether the seat has sent, and which maps are frozen.
func _offer_key() -> String:
	var frozen: PackedStringArray = []
	for map: CombatSession in _encounter.get_sessions():
		if _encounter.is_frozen(map.session_id):
			frozen.append(str(map.session_id))
	return "%s|%s" % [_encounter.has_sent(_seat), ",".join(frozen)]


# Submits command on the map session_id: through CampaignService.submit_combat() when the battle
# is the run's (host and client), else straight on the encounter (a test's). A host's settles at
# once; a client's when the host's answer arrives (combat_settled).
func _submit(command: Command, session_id: int, is_send: bool) -> void:
	_pending_map = session_id
	_is_pending_send = is_send
	_drawn = ""
	var service: Node = _campaign_service()
	var run: CampaignSession = null
	if service != null:
		run = service.get(&"session") as CampaignSession
	var is_mirror: bool = false
	if run == null or run.encounter != _encounter:
		_encounter.submit(command, session_id)
		_encounter.resolve_queued()
	else:
		is_mirror = run.is_mirror
		service.call(&"submit_combat", command, session_id)
	if not is_mirror and _pending_map == session_id:
		_settle(session_id, "")


# The command on session_id settled: refused with reason, else done.
func _settle(session_id: int, reason: String) -> void:
	if session_id != _pending_map:
		return
	var was_send: bool = _is_pending_send
	_pending_map = -1
	_drawn = ""
	if not reason.is_empty():
		if was_send and _send_panel.visible:
			_send_panel.show_refusal(reason)
		elif message != null:
			message.show_message("Can't do that: %s" % [CampaignLink.name_seats(reason)])
	elif was_send:
		close_panels()
		_dismissed_offer = _offer_key()
	if _encounter != null:
		refresh()


# The CampaignService autoload, reached as a node, as BattleController does: this script compiles
# in --script runs before autoload names exist. Null outside the tree.
func _campaign_service() -> Node:
	return get_node_or_null(^"/root/CampaignService") if is_inside_tree() else null


func _show_parts(is_shown: bool) -> void:
	_bar.visible = is_shown
	_banners.visible = is_shown
	if not is_shown:
		_frozen.visible = false
		_waiting.visible = false
		_maps_panel.close()
		_send_panel.close()


func _on_offer_timer_timeout(encounter: CombatEncounter) -> void:
	if encounter != _encounter:
		return
	_is_offer_timing = false
	_is_offer_ready = true


func _on_coop_bar_maps_pressed() -> void:
	if _maps_panel.visible:
		close_panels()
	else:
		open_maps()


func _on_aid_requested(is_raised: bool) -> void:
	request_aid(is_raised)


func _on_maps_panel_view_requested(session_id: int) -> void:
	close_panels()
	if session_id != _viewed_id:
		view_requested.emit(session_id)


func _on_maps_panel_send_requested() -> void:
	open_send()


func _on_panel_closed() -> void:
	close_panels()


func _on_send_panel_closed() -> void:
	if _encounter != null:
		_dismissed_offer = _offer_key()
	close_panels()


func _on_send_panel_send_confirmed(
		unit_ids: PackedStringArray, source_id: int, target_id: int
) -> void:
	send(unit_ids, source_id, target_id)


func _on_session_command_rejected(
		seat: int, _arrival: int, reason: String, session_id: int
) -> void:
	if seat == _seat:
		_settle(session_id, reason)


func _on_campaign_service_combat_settled(session_id: int, reason: String) -> void:
	_settle(session_id, reason)


func _on_controller_live_actions_changed() -> void:
	live_actions_changed.emit()
