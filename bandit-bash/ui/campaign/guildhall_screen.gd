# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_screen.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends Control
## A Guildhall node: the shared stock ([GuildhallStockView]) under the run's header and
## [HeirloomBar], priced for the seat, with Re-roll a prefix and Leave.
##
## On entry, a stock not yet rolled is rolled and saved first ([OpenGuildhallCommand]), so a quit
## and Continue shows the same stock. A card opens the [GuildhallPanel]: a recruit's price (with a
## full army, the unit it replaces and the hand-over) or a rune's (with full slots, the rune it
## discards), sending [GuildhallPurchaseCommand]; Re-roll opens its unit list, sending
## [PrefixRerollCommand]. Leave sends [LeaveNodeCommand] at any time. Every command goes through
## [method CampaignService.submit_command], which saves; a rejection shows its reason. The run's
## facts play ([CampaignPlayback]) as each resolves. Opened at any other stage, it sends the run on.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI; the panel reads its own ui_cancel
# first):
#   "ui_left" / "ui_right" / "ui_up" / "ui_down"
#                          -> arrows; d-pad, left stick      (between the cards, Re-roll and
#                             Leave; the panel's column and a hand-over row)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (press the focused card or choice)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (the pause menu reads it; in the
#                             panel, back a step)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses
#                             it, then back; hints HEIRLOOMS meanwhile)
#   Mouse: clicks on the cards, choices, Re-roll and Leave; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context while the stock shows.
const HINT_STOCK: StringName = &"STOCK"

## The hint context while the panel asks.
const HINT_BUY: StringName = &"BUY"

var _is_leaving: bool = false
var _seat: int = 0
var _context: StringName = HINT_STOCK
var _buying: int = -1

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _stock_view: GuildhallStockView = %GuildhallStockView
@onready var _status_label: Label = %Status
@onready var _reroll_button: Button = %RerollButton
@onready var _leave_button: Button = %LeaveButton
@onready var _panel: GuildhallPanel = %GuildhallPanel
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.GUILDHALL:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = session.seats[0]
	_header.title = "Guildhall"
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_stock_view.entry_pressed.connect(_on_stock_view_entry_pressed)
	_reroll_button.pressed.connect(_on_reroll_button_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_panel.recruit_chosen.connect(_on_panel_recruit_chosen)
	_panel.rune_chosen.connect(_on_panel_rune_chosen)
	_panel.reroll_chosen.connect(_on_panel_reroll_chosen)
	_panel.cancelled.connect(_on_panel_cancelled)
	if GuildhallStock.pending(session.run) == null:
		var opened: CampaignBatch = CampaignService.submit_command(
				OpenGuildhallCommand.for_session(session)
		)
		if opened == null or opened.is_rejected():
			_status_label.text = "The Guildhall couldn't open: %s." % [
				opened.rejected_reason if opened != null else "no run in progress",
			]
	_refresh()
	_set_context(HINT_STOCK)
	CampaignPlayback.play_pending(session)
	_focus_default.call_deferred()


## The stock shown, for tests and captures.
func get_stock_view() -> GuildhallStockView:
	return _stock_view


## The purchase panel, for tests and captures.
func get_panel() -> GuildhallPanel:
	return _panel


## The Re-roll button, for tests.
func get_reroll_button() -> Button:
	return _reroll_button


## The Leave button, for tests.
func get_leave_button() -> Button:
	return _leave_button


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# Shows the run as saved: the header (its gold), the bar and the stock priced for the seat.
func _refresh() -> void:
	var run: CampaignRunState = CampaignService.session.run
	_header.show_run(run, _seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_seat)))
	_stock_view.show_stock(run, _seat, EffectCatalog.index())


# The first card that can be bought, else Leave. Deferred, so the screen may be gone.
func _focus_default() -> void:
	if not is_inside_tree() or _is_leaving:
		return
	var card: Button = _stock_view.first_enabled()
	if card != null:
		card.grab_focus()
	else:
		_leave_button.grab_focus()


func _set_context(context: StringName) -> void:
	_context = context
	_hints.context = context


# Sends command; a rejection shows on the panel while it is open, else on the status line.
func _submit(command: CampaignCommand) -> bool:
	var batch: CampaignBatch = CampaignService.submit_command(command)
	if batch == null or batch.is_rejected():
		var reason: String = batch.rejected_reason if batch != null else "no run in progress"
		if _panel.visible:
			_panel.show_problem("Can't do that: %s." % [reason])
		else:
			_status_label.text = "Can't do that: %s." % [reason]
		return false
	CampaignPlayback.play_pending(CampaignService.session)
	return true


# What the purchase just made did, for the status line, from its bought or re-rolled fact.
func _bought_note(facts: Array[CampaignFact]) -> String:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var session: CampaignSession = CampaignService.session
	for fact: CampaignFact in facts:
		match fact.kind:
			CampaignFact.Kind.UNIT_BOUGHT:
				var unit: UnitInstance = session.run.seat_run(_seat).unit(fact.actor_id)
				var title: String = (
						fact.definition_id if unit == null
						else RecruitOfferCard.title_of(unit, catalog)
				)
				return "Recruited %s for %d gold." % [title, fact.amount]
			CampaignFact.Kind.RUNE_BOUGHT:
				return "Bought %s for %d gold." % [
					GuildhallModel.rune_name(fact.definition_id, catalog), fact.amount,
				]
			CampaignFact.Kind.PREFIX_REROLLED:
				var unit: UnitInstance = session.run.seat_run(_seat).unit(fact.actor_id)
				var title: String = (
						fact.actor_id if unit == null else RecruitOfferCard.title_of(unit, catalog)
				)
				if fact.amount == 0:
					return "Re-rolled for free: now %s." % [title]
				return "Re-rolled for %d gold: now %s." % [fact.amount, title]
	return ""


# After a purchase: the panel closed, the run shown again and the note on the status line.
func _after_purchase(first: int) -> void:
	_panel.close()
	_set_context(HINT_STOCK)
	_status_label.text = _bought_note(CampaignService.session.run.fact_log.slice(first))
	_refresh()
	_focus_default()


func _on_stock_view_entry_pressed(index: int) -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	_buying = index
	_status_label.text = ""
	_panel.open_entry(session.run, _seat, index, EffectCatalog.index(), session.ids)
	_set_context(HINT_BUY)


func _on_reroll_button_pressed() -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	_buying = -1
	_status_label.text = ""
	_panel.open_reroll(session.run, _seat, EffectCatalog.index(), session.ids)
	_set_context(HINT_BUY)


func _on_panel_recruit_chosen(replaced_id: String, hand_over: Dictionary) -> void:
	var session: CampaignSession = CampaignService.session
	var first: int = session.run.fact_log.size()
	var command: GuildhallPurchaseCommand = GuildhallPurchaseCommand.new(_seat, _buying)
	command.replaced_id = replaced_id
	command.hand_over.assign(hand_over)
	if _submit(command):
		_after_purchase(first)


func _on_panel_rune_chosen(discard_slot: int) -> void:
	var session: CampaignSession = CampaignService.session
	var first: int = session.run.fact_log.size()
	var command: GuildhallPurchaseCommand = GuildhallPurchaseCommand.new(_seat, _buying)
	command.discard_slot = discard_slot
	if _submit(command):
		_after_purchase(first)


func _on_panel_reroll_chosen(unit_id: String) -> void:
	var session: CampaignSession = CampaignService.session
	var first: int = session.run.fact_log.size()
	if not _submit(PrefixRerollCommand.for_session(session, _seat, unit_id)):
		return
	_refresh()
	_panel.refresh()
	_panel.show_problem(_bought_note(session.run.fact_log.slice(first)))


func _on_panel_cancelled() -> void:
	_set_context(HINT_STOCK)
	var card: Button = _stock_view.card_for(_buying)
	if _buying < 0:
		_reroll_button.grab_focus()
	elif card != null and not card.disabled:
		card.grab_focus()
	else:
		_focus_default()


func _on_leave_button_pressed() -> void:
	if _is_leaving:
		return
	if not _submit(LeaveNodeCommand.new(_seat)):
		return
	_is_leaving = true
	RunScreen.go()


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _context
