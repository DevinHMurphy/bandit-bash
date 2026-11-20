# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_panel.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventPanel
extends Control
## The event open at the run's node, asked over its steps ([enum Step]): the [EventStory], its
## options ([EventOptionCard]) with the team's [EventVoteStatus], then whatever the option chosen
## needs (the unit, fallen unit or weapon from an [EventChooser], where each new item goes from
## the [PlacementPanel], a rune to discard), and last the [EventOutcomeSummary] and Leave.
##
## Each step comes from the saved [EventView] ([method refresh]), so a continued run opens where
## it was saved; placements and the rune discard aren't saved and start over. Each command is
## built with [EventNode] and emitted ([signal command_ready]); the screen sends it and calls
## [method refresh], or [method show_problem] on a rejection. Names no autoload.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input in CHOOSER and RUNE:
#                  Back, taken first so the pause menu doesn't open; in PLACEMENT the
#                  PlacementPanel reads it; in the other steps it is left to the pause menu)
#   "ui_left" / "ui_right" / "ui_up" / "ui_down" / "ui_accept"   (not read here: the GUI moves
#                  focus along the cards or a chooser's column and presses the focused one, by
#                  key, d-pad, stick or A [Cross])
#   Mouse: a click on a card, choice or Leave presses it; Back steps back as ui_cancel does.
# ============================================================

## The player settled a step: send [param command] ([EventChooserCommand], [EventVoteCommand]
## or [EventOptionCommand]).
signal command_ready(command: CampaignCommand)

## The panel moved to [param step]; the screen's hints follow it.
signal step_changed(step: Step)

## The player pressed Leave (or Fight, with a surprise combat pending).
signal leave_requested()

const CARD_SCENE: PackedScene = preload("res://ui/campaign/events/event_option_card.tscn")

# --- Event step (meaningful only after open()) ---------------------------------------------
# CLOSED:    no event can be shown; the reason and Leave.
# OPTIONS:   the cards; one with a unit or weapon pick sends the chooser command (the saved view
#            then opens CHOOSER), a team choice's opens CHOOSER unsaved; else on to the picks.
# VOTE:      a team vote of more than one seat: a card votes, or changes the vote. The vote that
#            completes the set draws the option (DRAWN).
# DRAWN:     only the drawn card can be pressed: on to its picks, sent with this seat's only.
# CHOOSER:   the unit, fallen unit or weapon. Back closes the saved chooser (or returns to the
#            cards for a team choice). Choosing goes on to the picks.
# PLACEMENT: where each new item goes, in block order (the PlacementPanel). Back from its first
#            step returns to CHOOSER, or to the cards for an option with no chooser.
# RUNE:      which rune makes room, when every slot is full. Back as from PLACEMENT.
# OUTCOME:   the summary, and Leave (Fight with a combat pending), once the seat has chosen.
# The last pick sends EventOptionCommand and the step stays put until the screen refreshes, so a
# rejection shows where it was made.
## Which question the panel asks.
enum Step {
	## No event to show.
	CLOSED = 0,
	## Which option.
	OPTIONS = 1,
	## Which option to vote for.
	VOTE = 2,
	## The drawn option, to take.
	DRAWN = 3,
	## Which unit or weapon.
	CHOOSER = 4,
	## Where a new item goes.
	PLACEMENT = 5,
	## Which rune to discard.
	RUNE = 6,
	## What the option did.
	OUTCOME = 7,
}

var _step: Step = Step.CLOSED
var _session: CampaignSession = null
var _seat: int = 0
var _pool: EventPool = null
var _catalog: EffectCatalog.Index = null
var _view: EventView = EventView.new()

# The option being picked for, the picks so far, its item blocks and the next to place.
var _option: int = EventRunState.NO_OPTION
var _choice: EventChoice = EventChoice.new()
var _item_blocks: PackedInt32Array = []
var _next_block: int = 0

@onready var _story: EventStory = %EventStory
@onready var _votes: EventVoteStatus = %EventVoteStatus
@onready var _cards: HBoxContainer = %Cards
@onready var _chooser: EventChooser = %EventChooser
@onready var _summary: EventOutcomeSummary = %EventOutcomeSummary
@onready var _leave_button: Button = %LeaveButton
@onready var _status_label: Label = %Status
@onready var _placement: PlacementPanel = %PlacementPanel


func _ready() -> void:
	_chooser.entry_chosen.connect(_on_event_chooser_entry_chosen)
	_chooser.cancelled.connect(step_back)
	_placement.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement.cancelled.connect(_on_placement_panel_cancelled)
	_leave_button.pressed.connect(_on_leave_button_pressed)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (_step != Step.CHOOSER and _step != Step.RUNE):
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	step_back()


## Opens on [param seat]'s part of the event open in [param session]'s run, its definition from
## [param pool] and read with [param catalog] (each null: the game's own), at the saved step.
func open(
		session: CampaignSession,
		seat: int,
		pool: EventPool = null,
		catalog: EffectCatalog.Index = null
) -> void:
	_session = session
	_seat = seat
	_pool = pool if pool != null else EventPool.load_default()
	_catalog = catalog if catalog != null else EffectCatalog.index()
	refresh()


## Reads the saved event again and shows its step: after a command resolves, or to start over.
func refresh() -> void:
	_view = EventNode.view(_session, _seat, _pool, _catalog)
	_option = EventRunState.NO_OPTION
	_choice = EventChoice.new()
	_placement.close()
	if not _view.is_open():
		_show_closed()
	elif _view.chosen != EventRunState.NO_OPTION:
		_show_outcome()
	elif _view.is_vote_needed():
		_show_cards(Step.VOTE)
	elif _view.is_team_vote:
		_show_cards(Step.DRAWN)
	elif _view.choosing != EventRunState.NO_OPTION:
		_start_picks(_view.choosing)
	else:
		_show_cards(Step.OPTIONS)


## Shows [param problem] where the choice was made, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	if _step == Step.PLACEMENT:
		_placement.show_problem(problem)
		return
	_status_label.text = problem


## Goes back one step: from the chooser to the cards (closing the saved chooser), from a
## placement or the rune discard to the chooser, or to the cards with none. Does nothing on the
## cards or the outcome.
func step_back() -> void:
	match _step:
		Step.CHOOSER:
			if _view.event.is_team_choice:
				_show_saved_cards()
				return
			command_ready.emit(EventNode.open_chooser(
					_session, _seat, EventRunState.NO_OPTION, _pool, _catalog
			))
		Step.PLACEMENT, Step.RUNE:
			_placement.close()
			if _view.event.options[_option].chooser() != EventOutcome.Chooser.NONE:
				_show_chooser()
			else:
				_show_saved_cards()


## The step shown.
func get_step() -> Step:
	return _step


## The event as last read, for the screen and tests.
func get_view() -> EventView:
	return _view


## The option cards shown, in option order; empty in the other steps. For the screen and tests.
func get_cards() -> Array[EventOptionCard]:
	var cards: Array[EventOptionCard] = []
	if not _cards.visible:
		return cards
	for child: Node in _cards.get_children():
		if child is EventOptionCard and not child.is_queued_for_deletion():
			cards.append(child as EventOptionCard)
	return cards


## The story, for tests.
func get_story() -> EventStory:
	return _story


## The vote status, for tests.
func get_vote_status() -> EventVoteStatus:
	return _votes


## The chooser, for tests.
func get_chooser() -> EventChooser:
	return _chooser


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement


## The outcome summary, for tests.
func get_summary() -> EventOutcomeSummary:
	return _summary


## The Leave (or Fight) button, for tests.
func get_leave_button() -> Button:
	return _leave_button


## The status line, for tests.
func get_status_text() -> String:
	return _status_label.text


## Focuses the first card, choice or button the step offers; returns whether one took it.
func focus_first() -> bool:
	for card: EventOptionCard in get_cards():
		if not card.disabled:
			card.grab_focus()
			return true
	if _chooser.visible:
		return _chooser.focus_first()
	if _leave_button.visible and not _leave_button.disabled:
		_leave_button.grab_focus()
		return true
	return false


func _show_closed() -> void:
	_story.show_problem(_view.problem if not _view.problem.is_empty() else "event is closed")
	_leave_button.text = "Leave"
	_leave_button.disabled = false
	_enter(Step.CLOSED)


func _show_saved_cards() -> void:
	if _view.is_vote_needed():
		_show_cards(Step.VOTE)
	elif _view.is_team_vote:
		_show_cards(Step.DRAWN)
	else:
		_show_cards(Step.OPTIONS)


func _show_cards(step: Step) -> void:
	_option = EventRunState.NO_OPTION
	_choice = EventChoice.new()
	_story.show_event(_view.event)
	_votes.show_votes(_view, _seat_count())
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var own_vote: int = _view.votes.get(_seat, EventRunState.NO_OPTION)
	for shown: EventView.OptionView in _view.options:
		var refusal: String = shown.unmet_reason
		if step == Step.DRAWN and shown.index != _view.drawn and refusal.is_empty():
			refusal = "the team drew another option"
		var vote_line: String = ""
		if _view.is_team_vote:
			vote_line = "Votes: %d%s" % [
				shown.vote_count, " (your vote)" if own_vote == shown.index else "",
			]
		var card: EventOptionCard = CARD_SCENE.instantiate()
		_cards.add_child(card)
		card.show_option(
				shown, EventScreenModel.option_lines(shown, seat_run, _catalog), refusal, vote_line
		)
		card.pressed.connect(_on_card_pressed.bind(shown.index))
	_enter(step)
	_link_cards()


# Begins the picks for option index: its chooser first, if it has one.
func _start_picks(index: int) -> void:
	_option = index
	_choice = EventChoice.new()
	_item_blocks = EventScreenModel.item_blocks(_view.event.options[index])
	_next_block = 0
	if _view.event.options[index].chooser() != EventOutcome.Chooser.NONE:
		_show_chooser()
		return
	_next_pick()


func _show_chooser() -> void:
	var option: EventOption = _view.event.options[_option]
	_choice = EventChoice.new()
	_next_block = 0
	_story.show_event(_view.event)
	_votes.show_votes(_view, _seat_count())
	_enter(Step.CHOOSER)
	_chooser.show_entries(
			EventScreenModel.chooser_question(option.chooser(), option.title),
			EventScreenModel.chooser_entries(
					_session.run, _seat, _view.event, _option, _catalog
			)
	)


# The next pick the option needs (a placement per new item, then a rune to discard), or the
# command once nothing more is needed.
func _next_pick() -> void:
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var option: EventOption = _view.event.options[_option]
	if _next_block < _item_blocks.size():
		var block: int = _item_blocks[_next_block]
		var item_id: String = EventScreenModel.granted_item(
				option, block, _view.options[_option].rolls
		)
		_enter(Step.PLACEMENT)
		_placement.open(seat_run, _catalog.item(item_id), item_id, _catalog, _session.ids)
		return
	if (
			EventScreenModel.needs_rune_discard(option, seat_run)
			and _choice.rune_discard_slot == EventChoice.NO_SLOT
	):
		_placement.close()
		_enter(Step.RUNE)
		_chooser.show_entries(
				"Every rune slot is full. Which rune is discarded for the new one?",
				EventScreenModel.rune_entries(seat_run, _catalog)
		)
		return
	command_ready.emit(EventNode.choose(
			_session, _seat, _option, _choice, _pool, _catalog
	))


func _show_outcome() -> void:
	var shown: EventView.OptionView = _view.options[_view.chosen]
	_story.show_event(_view.event)
	_votes.show_votes(_view, _seat_count())
	_summary.show_outcome(shown.option.title, EventScreenModel.summary_lines(
			_view, _session.run.seat_run(_seat), _catalog
	))
	_leave_button.text = "Fight" if _view.is_combat_pending else "Leave"
	_leave_button.disabled = not _view.is_finished
	_enter(Step.OUTCOME)


# Shows the parts step uses, clears the status line and focuses the step's first control.
func _enter(step: Step) -> void:
	_step = step
	_status_label.text = ""
	var is_cards: bool = step == Step.OPTIONS or step == Step.VOTE or step == Step.DRAWN
	_cards.visible = is_cards
	_chooser.visible = step == Step.CHOOSER or step == Step.RUNE
	_summary.visible = step == Step.OUTCOME
	_leave_button.visible = step == Step.OUTCOME or step == Step.CLOSED
	if step == Step.CLOSED:
		_votes.visible = false
	if step != Step.PLACEMENT:
		focus_first.call_deferred()
	step_changed.emit(step)


# The enabled cards as one row: left and right step along it and stop at its ends; up and down
# stay put.
func _link_cards() -> void:
	var row: Array[Control] = []
	for card: EventOptionCard in get_cards():
		if not card.disabled:
			row.append(card)
	for i: int in row.size():
		var control: Control = row[i]
		var self_path: NodePath = control.get_path_to(control)
		control.focus_neighbor_left = control.get_path_to(row[maxi(i - 1, 0)])
		control.focus_neighbor_right = control.get_path_to(row[mini(i + 1, row.size() - 1)])
		control.focus_neighbor_top = self_path
		control.focus_neighbor_bottom = self_path
		control.focus_previous = control.focus_neighbor_left
		control.focus_next = control.focus_neighbor_right


func _seat_count() -> int:
	return _session.run.events.seats.size()


func _on_card_pressed(index: int) -> void:
	match _step:
		Step.VOTE:
			command_ready.emit(EventNode.vote(_session, _seat, index, _pool, _catalog))
		Step.OPTIONS, Step.DRAWN:
			var option: EventOption = _view.event.options[index]
			var has_chooser: bool = option.chooser() != EventOutcome.Chooser.NONE
			if has_chooser and not _view.event.is_team_choice:
				command_ready.emit(EventNode.open_chooser(
						_session, _seat, index, _pool, _catalog
				))
				return
			_start_picks(index)


func _on_event_chooser_entry_chosen(entry_id: String) -> void:
	if _step == Step.RUNE:
		_choice.rune_discard_slot = entry_id.to_int()
		_next_pick()
		return
	match _view.event.options[_option].chooser():
		EventOutcome.Chooser.WEAPON:
			_choice.weapon_id = entry_id
		_:
			_choice.unit_id = entry_id
	_next_pick()


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	_choice.placements[_item_blocks[_next_block]] = placement
	_next_block += 1
	_next_pick()


func _on_placement_panel_cancelled() -> void:
	step_back()


func _on_leave_button_pressed() -> void:
	leave_requested.emit()
