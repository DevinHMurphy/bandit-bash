# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_screen.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

extends Control
## An Armory node: the shared stock ([StockView]) under the run's header and [HeirloomBar], priced
## for the local seat, with Leave and, in co-op, Team ([TeamPanel]). The stock and Leave scroll
## when taller than the window (cards with effect lines, at 1280×720), following focus, so the
## selected card is always in view.
##
## On entry, a stock not yet rolled is rolled and saved first ([OpenArmoryCommand]), so a quit and
## Continue shows the same stock. A card opens the [PurchasePanel]: an item's unit and deal with
## its before/after comparison, or an heirloom's price; the deal sends [ArmoryPurchaseCommand].
## Leave sends [LeaveNodeCommand] at any time, buying being optional. Every command goes through a
## [CampaignLink], which saves; a refusal shows its reason, a teammate's purchase first as "bought
## by" them. Every batch rebuilds the stock, so a card a teammate bought says so at once; once any
## seat's Leave resolves the run returns to the map. The run's facts play ([CampaignPlayback])
## after each batch, so a purchase sounds once. Opened at any other stage, it sends the run on.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI; the panels read their own
# ui_cancel first):
#   "ui_left" / "ui_right" / "ui_up" / "ui_down"
#                          -> arrows; d-pad, left stick      (between the stock's cards, Leave and
#                             Team; the panel's column; the team panel's rows)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (press the focused card or choice)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (the pause menu reads it; in the
#                             panel, back a step)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses
#                             it, then back; hints HEIRLOOMS meanwhile)
#   Mouse: clicks on the cards, choices, Leave and Team; the wheel scrolls the stock; hovering an
#   heirloom shows its tooltip.
# ============================================================

## The hint context while the stock shows.
const HINT_STOCK: StringName = &"STOCK"

## The hint context while the purchase panel asks.
const HINT_BUY: StringName = &"BUY"

var _is_leaving: bool = false
var _seat: int = 0
var _context: StringName = HINT_STOCK
var _buying: int = -1
var _link: CampaignLink = null

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _stock_view: StockView = %StockView
@onready var _status_label: Label = %Status
@onready var _leave_button: Button = %LeaveButton
@onready var _team_button: Button = %TeamButton
@onready var _purchase_panel: PurchasePanel = %PurchasePanel
@onready var _team_panel: TeamPanel = %TeamPanel
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.ARMORY:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = CampaignService.local_seat()
	_link = CampaignLink.new(session, _seat, CampaignService.submit_command)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	_header.title = "Armory"
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_stock_view.entry_pressed.connect(_on_stock_view_entry_pressed)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_team_button.visible = _link.is_coop()
	_team_button.pressed.connect(_on_team_button_pressed)
	_purchase_panel.purchase_chosen.connect(_on_purchase_panel_purchase_chosen)
	_purchase_panel.cancelled.connect(_on_purchase_panel_cancelled)
	# The host rolls the shared stock, so the roll goes out as the host's, not through the link.
	if ArmoryStock.pending(session.run) == null:
		CampaignService.submit_command(OpenArmoryCommand.for_session(session))
	_refresh()
	_set_context(HINT_STOCK)
	CampaignPlayback.play_pending(session)
	_focus_default.call_deferred()


func _exit_tree() -> void:
	if _link != null:
		_link.close()


## The stock shown, for tests and captures.
func get_stock_view() -> StockView:
	return _stock_view


## The purchase panel, for tests and captures.
func get_purchase_panel() -> PurchasePanel:
	return _purchase_panel


## The Leave button, for tests.
func get_leave_button() -> Button:
	return _leave_button


## The Team button, shown in co-op, for tests.
func get_team_button() -> Button:
	return _team_button


## The team panel, for tests and captures.
func get_team_panel() -> TeamPanel:
	return _team_panel


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# Shows the run as saved: the header (its gold), the bar and the stock priced for the seat.
func _refresh() -> void:
	var run: CampaignRunState = CampaignService.session.run
	_header.show_run(run, _seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_seat)))
	_stock_view.show_stock(run, _seat, EffectCatalog.index(), CampaignService.session.ids)


# The first card that can be bought, else Leave. Deferred, so the screen may be gone.
func _focus_default() -> void:
	if not is_inside_tree() or _is_leaving:
		return
	var card: StockCard = _stock_view.first_enabled()
	if card != null:
		card.grab_focus()
	else:
		_leave_button.grab_focus()


func _set_context(context: StringName) -> void:
	_context = context
	_hints.context = context


# What the purchase just made did, for the status line, from its ITEM_BOUGHT fact.
func _bought_note(batch_facts: Array[CampaignFact]) -> String:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for fact: CampaignFact in batch_facts:
		if fact.kind != CampaignFact.Kind.ITEM_BOUGHT:
			continue
		var heirloom: HeirloomDefinition = catalog.heirloom(fact.definition_id)
		var item: ItemDefinition = catalog.item(fact.definition_id)
		var bought_name: String = (
				heirloom.display_name if heirloom != null
				else CombatResultsModel.item_name(item, fact.definition_id)
		)
		if fact.amount < 0:
			return "Bought %s and got %d gold back." % [bought_name, -fact.amount]
		return "Bought %s for %d gold." % [bought_name, fact.amount]
	return ""


func _on_stock_view_entry_pressed(index: int) -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	_buying = index
	_status_label.text = ""
	_purchase_panel.open(session.run, _seat, index, EffectCatalog.index(), session.ids)
	_set_context(HINT_BUY)


func _on_purchase_panel_purchase_chosen(unit_id: String, is_traded_in: bool) -> void:
	var session: CampaignSession = CampaignService.session
	var command: ArmoryPurchaseCommand = ArmoryPurchaseCommand.for_session(
			session, _seat, _buying, unit_id, is_traded_in
	)
	_link.send(command, _on_purchase_resolved)


# After the seat's purchase: back to the stock, saying what it bought.
func _on_purchase_resolved(batch: CampaignBatch) -> void:
	if _is_leaving:
		return
	_purchase_panel.close()
	_set_context(HINT_STOCK)
	_status_label.text = _bought_note(batch.facts)
	_focus_default()


func _on_purchase_panel_cancelled() -> void:
	_set_context(HINT_STOCK)
	var card: StockCard = _stock_view.card_for(_buying)
	if card != null and not card.disabled:
		card.grab_focus()
	else:
		_focus_default()


func _on_leave_button_pressed() -> void:
	if _is_leaving:
		return
	_link.send(LeaveNodeCommand.new(_seat))


func _on_team_button_pressed() -> void:
	_team_panel.open(_link.session, _seat)


# Any seat's batch: one the screen follows plays its facts and, once the run left the Armory,
# moves the screen on; while the run is still here the stock shows again, a teammate's purchase
# included.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	if RunScreen.of(_link.session) != SceneRouter.Screen.ARMORY:
		if follows:
			_is_leaving = true
			RunScreen.go()
		return
	_refresh()
	_team_panel.refresh()


# A refusal says why where the player is looking; an entry a teammate bought first says who, and
# one before the stock was rolled is the roll's.
func _on_link_refused(reason: String) -> void:
	var run: CampaignRunState = _link.session.run
	if ArmoryStock.pending(run) == null:
		_status_label.text = "The Armory couldn't open: %s." % [reason]
		return
	var buyer: String = ArmoryModel.bought_by(run, _seat, _buying)
	var shown: String = "Can't do that: %s." % [reason if buyer.is_empty() else buyer]
	if _purchase_panel.visible:
		_purchase_panel.show_problem(shown)
	else:
		_status_label.text = shown


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _context
