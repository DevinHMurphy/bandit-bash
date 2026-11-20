# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     treasure_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

extends Control
## A Treasure node: the seat's chest ([ChestView]) under the run's header and [HeirloomBar], with
## Open and Leave.
##
## On entry, a chest not yet rolled is rolled and saved first ([OpenTreasureCommand]), so a quit
## and Continue shows the same chest. Open takes it whole ([TreasureCommand]); a Legendary item
## asks where it goes in the [PlacementPanel] first. Leave with the chest unopened asks first
## ([LeaveConfirmDialog]) and gives it up, then [LeaveNodeCommand] returns to the map. Every
## command goes through [method CampaignService.submit_command], which saves; a rejection shows
## its reason and changes nothing. The run's facts play ([CampaignPlayback]) as each resolves.
## Opened at any other stage, it sends the run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI; the panel and dialog read their
# own ui_cancel first):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (between Open and Leave; the
#                             dialog's Stay and Leave)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (the placement panel's column)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (press the focused button)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (the pause menu reads it; in the
#                             placement panel, back a step; in the dialog, Stay)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses
#                             it, then back; hints HEIRLOOMS meanwhile)
#   Mouse: clicks on the buttons and choices; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context while the chest shows.
const HINT_CHEST: StringName = &"CHEST"

## The hint context while the placement panel asks where the Legendary item goes.
const HINT_PLACE: StringName = &"PLACE"

## The hint context while the leave dialog asks.
const HINT_CONFIRM: StringName = &"CONFIRM"

var _is_leaving: bool = false
var _seat: int = 0
var _context: StringName = HINT_CHEST

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _chest_view: ChestView = %ChestView
@onready var _status_label: Label = %Status
@onready var _open_button: Button = %OpenButton
@onready var _leave_button: Button = %LeaveButton
@onready var _placement_panel: PlacementPanel = %PlacementPanel
@onready var _confirm: LeaveConfirmDialog = %LeaveConfirmDialog
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.TREASURE:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = session.seats[0]
	_header.title = "Treasure"
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_open_button.pressed.connect(_on_open_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_placement_panel.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement_panel.cancelled.connect(_on_placement_panel_cancelled)
	_confirm.confirmed.connect(_on_confirm_confirmed)
	_confirm.cancelled.connect(_on_confirm_cancelled)
	_link_buttons()
	if TreasureChest.pending(session.run.seat_run(_seat)) == null:
		var opened: CampaignBatch = CampaignService.submit_command(
				OpenTreasureCommand.for_session(session)
		)
		if opened == null or opened.is_rejected():
			_status_label.text = "The chest couldn't be opened: %s." % [
				opened.rejected_reason if opened != null else "no run in progress",
			]
	_refresh()
	_set_context(HINT_CHEST)
	CampaignPlayback.play_pending(session)
	_focus_default.call_deferred()


## The chest shown, for tests and captures.
func get_chest_view() -> ChestView:
	return _chest_view


## The Open button, for tests.
func get_open_button() -> Button:
	return _open_button


## The Leave button, for tests.
func get_leave_button() -> Button:
	return _leave_button


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement_panel


## The leave dialog, for tests.
func get_confirm_dialog() -> LeaveConfirmDialog:
	return _confirm


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


func _chest() -> TreasureChest:
	return TreasureChest.pending(CampaignService.session.run.seat_run(_seat))


# Shows the run as saved: the header, the bar and the chest; Open while it is open, Leave styled
# as the way on once it is settled.
func _refresh() -> void:
	var run: CampaignRunState = CampaignService.session.run
	_header.show_run(run, _seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_seat)))
	var chest: TreasureChest = _chest()
	_chest_view.show_chest(
			chest, EffectCatalog.index(), run.seat_run(_seat), CampaignService.session.ids
	)
	var is_open: bool = chest != null and not chest.is_resolved
	_open_button.visible = is_open
	_open_button.text = "Open the chest"
	_leave_button.text = "Leave" if is_open else "Continue"
	_leave_button.theme_type_variation = &"" if is_open else &"PrimaryButton"
	_link_buttons()


# Open and Leave as one row: left and right between them, the ends stop, up and down stay put.
func _link_buttons() -> void:
	var row: Array[Button] = []
	for button: Button in [_open_button, _leave_button]:
		if button.visible:
			row.append(button)
	for i: int in row.size():
		var button: Button = row[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_left = button.get_path_to(row[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(row[mini(i + 1, row.size() - 1)])
		button.focus_neighbor_top = self_path
		button.focus_neighbor_bottom = self_path


# Open while the chest is open, else Leave. Deferred from _ready, so the screen may be gone.
func _focus_default() -> void:
	if not is_inside_tree() or _is_leaving:
		return
	(_open_button if _open_button.visible else _leave_button).grab_focus()


func _set_context(context: StringName) -> void:
	_context = context
	_hints.context = context


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


func _take(placement: ItemPlacement) -> void:
	var chest: TreasureChest = _chest()
	if not _submit(TreasureCommand.new(_seat, true, placement)):
		return
	_placement_panel.close()
	_set_context(HINT_CHEST)
	_status_label.text = _taken_note(chest)
	_refresh()
	_leave_button.grab_focus()


# What taking chest gave, for the status line.
func _taken_note(chest: TreasureChest) -> String:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var parts: PackedStringArray = []
	if chest.gold > 0:
		parts.append("%d gold" % [chest.gold])
	if not chest.heirloom_id.is_empty():
		var heirloom: HeirloomDefinition = catalog.heirloom(chest.heirloom_id)
		parts.append(heirloom.display_name if heirloom != null else chest.heirloom_id)
	if chest.item != null:
		parts.append(CombatResultsModel.item_name(
				catalog.item(chest.item.definition_id), chest.item.definition_id
		))
	return "The chest was empty." if parts.is_empty() else "Took %s." % [", ".join(parts)]


func _leave() -> void:
	if not _submit(LeaveNodeCommand.new(_seat)):
		return
	_is_leaving = true
	RunScreen.go()


func _on_open_button_pressed() -> void:
	if _is_leaving:
		return
	var chest: TreasureChest = _chest()
	if chest == null or chest.is_resolved:
		return
	if chest.item == null:
		_take(null)
		return
	var session: CampaignSession = CampaignService.session
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	_placement_panel.open(
			session.run.seat_run(_seat), catalog.item(chest.item.definition_id),
			chest.item.definition_id, catalog, session.ids
	)
	_set_context(HINT_PLACE)


func _on_leave_button_pressed() -> void:
	if _is_leaving:
		return
	var chest: TreasureChest = _chest()
	if chest != null and not chest.is_resolved:
		_confirm.open(PackedStringArray(["the %s chest" % [chest.size_name().to_lower()]]))
		_set_context(HINT_CONFIRM)
		return
	_leave()


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	_take(placement)


func _on_placement_panel_cancelled() -> void:
	_set_context(HINT_CHEST)
	_open_button.grab_focus()


func _on_confirm_confirmed() -> void:
	_confirm.visible = false
	_set_context(HINT_CHEST)
	if _submit(TreasureCommand.new(_seat, false)):
		_leave()


func _on_confirm_cancelled() -> void:
	_confirm.visible = false
	_set_context(HINT_CHEST)
	_leave_button.grab_focus()


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _context
