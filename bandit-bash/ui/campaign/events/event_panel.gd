# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_panel.gd
# Author:
# Created:  November 19, 2026
# Modified: November 24, 2026
# ==============================================================================

class_name EventPanel
extends Control
## The event open at the run's node, asked over its steps ([enum Step]) for one seat: the
## [EventStory], its options ([EventOptionCard]) with the team's [EventVoteStatus] and each
## teammate's part ([EventTeamStatus]), then whatever the option chosen needs (the unit, fallen
## unit or weapon, then the unit that leaves a full army, each from an [EventChooser], and where
## its items go from the [EventHandOverPanel]; where each new item goes from the
## [PlacementPanel]; a rune to discard), and last the [EventOutcomeSummary] and Leave or Fight (a
## [ReadyToggle], Ready in co-op, taken back by a problem shown), with Team in co-op
## ([member offers_team]); the [TeamReadyStatus] stays hidden. While Leave, Fight or Team holds
## key or pad focus, the summary's keywords show as a column of tooltips beside it.
##
## Each step comes from the saved [EventView] ([method refresh]); unsaved picks start over.
## Commands are built with [EventNode] and emitted ([signal command_ready]); the screen sends them
## and calls [method refresh], [method refresh_team] (a teammate's) or [method show_problem].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md
## @todo: TOD-001 - Leave's Ready and the TeamReadyStatus follow the ready gate (P18 RC4).

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input in CHOOSER, LEAVING,
#                  HAND_OVER and RUNE: Back, taken first so the pause menu doesn't open; in
#                  PLACEMENT the PlacementPanel reads it; in the other steps it is left to the
#                  pause menu)
#   "ui_left" / "ui_right" / "ui_up" / "ui_down" / "ui_accept"   (not read here: the GUI moves
#                  focus along the cards, a chooser's column or the hand-over's rows and presses
#                  the focused one, by key, d-pad, stick or A [Cross]; down from the cards or
#                  Leave reaches Team, up from Team returns)
#   Mouse: a click on a card, choice, place, Leave or Team presses it; Back steps back as
#   ui_cancel does.
# ============================================================

## The player settled a step: send [param command] ([EventChooserCommand], [EventVoteCommand]
## or [EventOptionCommand]).
signal command_ready(command: CampaignCommand)

## The panel moved to [param step]; the screen's hints follow it.
signal step_changed(step: Step)

## The player pressed Leave (or Fight, with a surprise combat pending).
signal leave_requested()

## The player pressed Team: the screen opens its [TeamPanel].
signal team_requested()

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
# LEAVING:   which living unit leaves, when the option recruits or revives into a full army
#            (unsaved). Back returns to CHOOSER, or to the cards for an option with no chooser.
# HAND_OVER: where each item of the leaving unit goes, when it holds any (unsaved); Confirm goes
#            on to the picks. Back returns to LEAVING.
# PLACEMENT: where each new item goes, in block order (the PlacementPanel). Back from its first
#            step returns to HAND_OVER or LEAVING when asked, else as from LEAVING.
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
	## Which unit leaves a full army for the one the option brings in.
	LEAVING = 8,
	## Where each item of the unit leaving goes.
	HAND_OVER = 9,
}

# Leave's co-op label while the seat isn't Ready, and Fight's: a pending fight is a Ready to fight.
# ASSUMPTION: "Ready to fight" for Fight's co-op label; no design doc words it.
const _READY_TEXT: String = "Ready"
const _READY_TO_FIGHT_TEXT: String = "Ready to fight"

# The steps that show Team, in co-op: those with no unsaved picks under way.
# ASSUMPTION: Team hides while a chooser, the leaving unit, a placement or the rune discard asks.
const _TEAM_STEPS: Array[Step] = [
	Step.CLOSED, Step.OPTIONS, Step.VOTE, Step.DRAWN, Step.OUTCOME,
]

## Whether the Team button shows, beside the cards and Leave: set by the screen in co-op before
## [method open]. [b]Off:[/b] solo, no Team button.
var offers_team: bool = false

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

# Whether the hand-over was confirmed for the leaving unit chosen; an empty one is a choice too.
var _is_handed_over: bool = false

# The option whose card had focus when the cards were last rebuilt, focused again after; -1: none.
var _refocus_option: int = EventRunState.NO_OPTION

# The keyword ids of the column shown on the summary for key or pad focus; empty while none.
var _column_ids: PackedStringArray = []

@onready var _story: EventStory = %EventStory
@onready var _votes: EventVoteStatus = %EventVoteStatus
@onready var _team: EventTeamStatus = %EventTeamStatus
@onready var _ready_status: TeamReadyStatus = %TeamReadyStatus
@onready var _cards: HBoxContainer = %Cards
@onready var _chooser: EventChooser = %EventChooser
@onready var _summary: EventOutcomeSummary = %EventOutcomeSummary
@onready var _leave_button: ReadyToggle = %LeaveButton
@onready var _team_button: Button = %TeamButton
@onready var _status_label: Label = %Status
@onready var _placement: PlacementPanel = %PlacementPanel
@onready var _hand_over: EventHandOverPanel = %EventHandOverPanel


func _ready() -> void:
	_chooser.entry_chosen.connect(_on_event_chooser_entry_chosen)
	_chooser.cancelled.connect(step_back)
	_hand_over.hand_over_chosen.connect(_on_event_hand_over_panel_hand_over_chosen)
	_hand_over.cancelled.connect(step_back)
	_placement.placement_chosen.connect(_on_placement_panel_placement_chosen)
	_placement.cancelled.connect(_on_placement_panel_cancelled)
	_leave_button.pressed.connect(_on_leave_button_pressed)
	_team_button.pressed.connect(_on_team_button_pressed)
	get_viewport().gui_focus_changed.connect(_on_viewport_gui_focus_changed)
	# Focus released to nothing changes no focus owner, so the buttons report leaving too.
	_leave_button.focus_exited.connect(_refresh_keywords)
	_team_button.focus_exited.connect(_refresh_keywords)
	var lines: EffectText = _summary.get_effect_text()
	# Connected after the text's own handlers, so the column is set again after each hover change.
	lines.meta_hover_started.connect(_on_summary_meta_hover_changed)
	lines.meta_hover_ended.connect(_on_summary_meta_hover_changed)
	lines.mouse_exited.connect(_refresh_keywords)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (_chooser.visible or _hand_over.visible):
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


## Reads the saved event again after a teammate's batch: as [method refresh], except that while
## the seat is part way through its picks (a chooser, the unit that leaves and its hand-over, a
## placement, the rune discard) only the team's votes and choices update, so the picks so far stay.
func refresh_team() -> void:
	var is_picking: bool = (
			_step == Step.CHOOSER or _step == Step.LEAVING or _step == Step.HAND_OVER
			or _step == Step.PLACEMENT or _step == Step.RUNE
	)
	var fresh: EventView = EventNode.view(_session, _seat, _pool, _catalog)
	if not is_picking or not fresh.is_open() or fresh.event != _view.event:
		refresh()
		return
	_view = fresh
	_show_team_parts()


## Shows [param problem] where the choice was made, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	_leave_button.set_ready(false)
	if _step == Step.PLACEMENT:
		_placement.show_problem(problem)
		return
	_status_label.text = problem


## Goes back one step: from the chooser to the cards (closing the saved chooser); from the
## leaving unit to the chooser, or to the cards with none; from the hand-over to the leaving
## unit; from a placement or the rune discard to the hand-over or the leaving unit when asked,
## else as from the leaving unit. Does nothing on the cards or the outcome.
func step_back() -> void:
	match _step:
		Step.CHOOSER:
			if _view.event.is_team_choice:
				_show_saved_cards()
				return
			command_ready.emit(EventNode.open_chooser(
					_session, _seat, EventRunState.NO_OPTION, _pool, _catalog
			))
		Step.LEAVING:
			_back_before_leaving()
		Step.HAND_OVER:
			_show_leaving()
		Step.PLACEMENT, Step.RUNE:
			_placement.close()
			var option: EventOption = _view.event.options[_option]
			if _needs_hand_over():
				_show_hand_over()
			elif EventScreenModel.needs_leaving_unit(
					option, _session.run.seat_run(_seat), _catalog
			):
				_show_leaving()
			else:
				_back_before_leaving()


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


## The teammates' choices, for tests.
func get_team_status() -> EventTeamStatus:
	return _team


## The chooser, for tests.
func get_chooser() -> EventChooser:
	return _chooser


## The placement panel, for tests.
func get_placement_panel() -> PlacementPanel:
	return _placement


## The hand-over panel, for tests and captures.
func get_hand_over_panel() -> EventHandOverPanel:
	return _hand_over


## The outcome summary, for tests.
func get_summary() -> EventOutcomeSummary:
	return _summary


## The Leave (or Fight) button, a [ReadyToggle], for the screen and tests.
func get_leave_button() -> Button:
	return _leave_button


## Who the team waits for, hidden until the ready gate feeds it; for tests and captures.
func get_ready_status() -> TeamReadyStatus:
	return _ready_status


## The Team button, shown in co-op, for the screen and tests.
func get_team_button() -> Button:
	return _team_button


## The status line, for tests.
func get_status_text() -> String:
	return _status_label.text


## Focuses the first card, choice or button the step offers (Team last); returns whether one took
## it. Out of the tree, as when the screen changed in the frame a step showed, none does.
func focus_first() -> bool:
	if not is_inside_tree():
		return false
	for card: EventOptionCard in get_cards():
		if not card.disabled:
			card.grab_focus()
			return true
	if _chooser.visible:
		return _chooser.focus_first()
	if _hand_over.visible:
		return _hand_over.focus_first()
	for button: Button in [_leave_button, _team_button]:
		if button.visible and not button.disabled:
			button.grab_focus()
			return true
	return false


func _show_closed() -> void:
	_story.show_problem(_view.problem if not _view.problem.is_empty() else "event is closed")
	_leave_button.solo_text = "Leave"
	_leave_button.ready_text = _READY_TEXT
	_set_enabled(_leave_button, true)
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
	_show_team_parts()
	_refocus_option = EventRunState.NO_OPTION
	for child: Node in _cards.get_children():
		var card: EventOptionCard = child as EventOptionCard
		if card != null and card.has_focus():
			_refocus_option = card.option_index
		_cards.remove_child(child)
		child.queue_free()
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var own_vote: int = _view.votes.get(_seat, EventRunState.NO_OPTION)
	for shown: EventView.OptionView in _view.options:
		var refusal: String = shown.unmet_reason
		if step == Step.DRAWN and shown.index != _view.drawn and refusal.is_empty():
			refusal = "the team drew another option"
		if _is_coop():
			refusal = CampaignLink.name_seats(refusal)
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
	_is_handed_over = false
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
	_show_team_parts()
	_enter(Step.CHOOSER)
	_chooser.show_entries(
			EventScreenModel.chooser_question(option.chooser(), option.title),
			EventScreenModel.chooser_entries(
					_session.run, _seat, _view.event, _option, _catalog
			)
	)


# Asks which living unit leaves the full army for the one the option brings in, with no picks
# after it made yet.
func _show_leaving() -> void:
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var title: String = _view.event.options[_option].title
	_choice.replaced_id = ""
	_clear_picks_after_leaving()
	_story.show_event(_view.event)
	_show_team_parts()
	_enter(Step.LEAVING)
	_chooser.show_entries(
			EventScreenModel.leaving_question(title, seat_run, _catalog),
			EventScreenModel.leaving_entries(_session.run, _seat, _catalog)
	)


# Asks where each item of the leaving unit goes, opening with every one to the convoy, with no
# picks after it made yet.
func _show_hand_over() -> void:
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var option: EventOption = _view.event.options[_option]
	_clear_picks_after_leaving()
	_story.show_event(_view.event)
	_show_team_parts()
	_enter(Step.HAND_OVER)
	_hand_over.show_hand_over(
			seat_run,
			EventOutcome.living_unit(seat_run, _choice.replaced_id),
			EventScreenModel.joining(
					_session.run, _seat, _view.event, _option, _choice, _catalog
			),
			EventScreenModel.is_revive(option),
			_catalog
	)


# Forgets the hand-over, placements and rune discard, so the steps after the leaving unit ask
# afresh.
func _clear_picks_after_leaving() -> void:
	_choice.hand_over.clear()
	_is_handed_over = false
	_choice.placements.clear()
	_choice.rune_discard_slot = EventChoice.NO_SLOT
	_next_block = 0


# Whether the option asks where the leaving unit's items go: a unit leaves, holding any.
func _needs_hand_over() -> bool:
	var leaving: UnitInstance = EventOutcome.living_unit(
			_session.run.seat_run(_seat), _choice.replaced_id
	)
	return leaving != null and not leaving.item_ids().is_empty()


# Back from the leaving unit, or from a later pick when it wasn't asked: to the chooser, or to
# the cards for an option with none.
func _back_before_leaving() -> void:
	if _view.event.options[_option].chooser() != EventOutcome.Chooser.NONE:
		_show_chooser()
	else:
		_show_saved_cards()


# The next pick the option needs (the unit that leaves a full army and where its items go, a
# placement per new item, then a rune to discard), or the command once nothing more is needed.
func _next_pick() -> void:
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var option: EventOption = _view.event.options[_option]
	if (
			_choice.replaced_id.is_empty()
			and EventScreenModel.needs_leaving_unit(option, seat_run, _catalog)
	):
		_show_leaving()
		return
	if not _is_handed_over and _needs_hand_over():
		_show_hand_over()
		return
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
	_show_team_parts()
	_summary.show_outcome(shown.option.title, EventScreenModel.summary_lines(
			_view, _session.run.seat_run(_seat), _catalog
	))
	_leave_button.solo_text = "Fight" if _view.is_combat_pending else "Leave"
	_leave_button.ready_text = _READY_TO_FIGHT_TEXT if _view.is_combat_pending else _READY_TEXT
	_set_enabled(_leave_button, _view.is_finished)
	_enter(Step.OUTCOME)
	# New lines hide the column; focus kept on Leave or Team across a batch brings it back.
	_refresh_keywords()


# Shows the parts step uses, clears the status line and focuses the step's first control a frame
# later (_focus_step).
func _enter(step: Step) -> void:
	_step = step
	_status_label.text = ""
	var is_cards: bool = step == Step.OPTIONS or step == Step.VOTE or step == Step.DRAWN
	_cards.visible = is_cards
	_chooser.visible = step == Step.CHOOSER or step == Step.LEAVING or step == Step.RUNE
	_hand_over.visible = step == Step.HAND_OVER
	_summary.visible = step == Step.OUTCOME
	if step != Step.OUTCOME:
		_refresh_keywords()
	_leave_button.visible = step == Step.OUTCOME or step == Step.CLOSED
	# TODO(TOD-001): the ready gate drives Leave's Ready and the status (P18 RC4).
	_leave_button.is_coop = offers_team
	_team_button.visible = offers_team and _TEAM_STEPS.has(step)
	if step == Step.CLOSED:
		_votes.visible = false
		_team.visible = false
	_link_team()
	if step != Step.PLACEMENT:
		_focus_step.call_deferred()
	step_changed.emit(step)


# The step's focus, deferred from _enter: the card of the option focused before the cards were
# rebuilt, else the step's first control. Does nothing once the panel has left the tree (the
# screen changed in the frame the step showed), or while a shown control keeps focus (Leave or
# Team across a teammate's batch, the team panel, the heirloom bar), so a batch never takes it.
func _focus_step() -> void:
	if not is_inside_tree():
		return
	var owner_now: Control = get_viewport().gui_get_focus_owner()
	var refocus: int = _refocus_option
	_refocus_option = EventRunState.NO_OPTION
	if owner_now != null and owner_now.is_visible_in_tree():
		var held: BaseButton = owner_now as BaseButton
		if held == null or not held.disabled:
			return
	for card: EventOptionCard in get_cards():
		if card.option_index == refocus and not card.disabled:
			card.grab_focus()
			return
	focus_first()


# The enabled cards as one row: left and right step along it and stop at its ends; up stays put,
# down goes to Team when it shows.
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
		control.focus_neighbor_bottom = (
				control.get_path_to(_team_button) if _team_button.visible else self_path
		)
		control.focus_previous = control.focus_neighbor_left
		control.focus_next = control.focus_neighbor_right


# Team under the step's controls: up from it to the first enabled card, else an enabled Leave,
# else it stays; down from Leave to it. Left, right and down from Team stay put.
func _link_team() -> void:
	if not _team_button.visible:
		_leave_button.focus_neighbor_bottom = NodePath()
		return
	var above: Control = _team_button
	for card: EventOptionCard in get_cards():
		if not card.disabled:
			above = card
			break
	if above == _team_button and _leave_button.visible and not _leave_button.disabled:
		above = _leave_button
	var self_path: NodePath = _team_button.get_path_to(_team_button)
	_team_button.focus_neighbor_top = _team_button.get_path_to(above)
	_team_button.focus_neighbor_bottom = self_path
	_team_button.focus_neighbor_left = self_path
	_team_button.focus_neighbor_right = self_path
	_leave_button.focus_neighbor_bottom = _leave_button.get_path_to(_team_button)


# Shows the team's vote and each teammate's part as the view stands.
func _show_team_parts() -> void:
	_votes.show_votes(_view, _seat_count())
	_team.show_team(_view)


# Enables or disables button, taking it out of the focus order while disabled.
func _set_enabled(button: Button, is_enabled: bool) -> void:
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE


func _seat_count() -> int:
	return _session.run.events.seats.size()


# Shows the summary's keywords as a column beside it while Leave, Fight or Team holds key or pad
# focus on the outcome, and hides it once none does; meanwhile a hovered keyword, already in the
# column, shows no tooltip of its own. Rebuilds only when the column changed, or a hover or new
# lines replaced it.
func _refresh_keywords() -> void:
	var lines: EffectText = _summary.get_effect_text()
	if not _has_outcome_key_focus():
		# Only the column is the panel's to hide: a hovered keyword keeps its tooltip.
		if not _column_ids.is_empty():
			_column_ids = PackedStringArray()
			lines.hide_tooltips()
		return
	var ids: PackedStringArray = lines.get_keyword_ids()
	if ids == _column_ids and lines.get_shown_tooltips().size() == ids.size():
		return
	_column_ids = ids
	lines.show_tooltips(ids)


# Whether Leave (or Fight) or Team holds focus a key or pad gave on the shown outcome, not a
# click's hidden focus.
func _has_outcome_key_focus() -> bool:
	if _step != Step.OUTCOME or not _summary.is_visible_in_tree():
		return false
	var focused: Control = get_viewport().gui_get_focus_owner()
	return (
			(focused == _leave_button or focused == _team_button)
			and focused.is_visible_in_tree() and focused.has_focus(true)
	)


func _is_coop() -> bool:
	return _session != null and _session.seats.size() > 1


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
	if _step == Step.LEAVING:
		_choice.replaced_id = entry_id
		_next_pick()
		return
	match _view.event.options[_option].chooser():
		EventOutcome.Chooser.WEAPON:
			_choice.weapon_id = entry_id
		_:
			_choice.unit_id = entry_id
	_next_pick()


func _on_event_hand_over_panel_hand_over_chosen(hand_over: Dictionary) -> void:
	_choice.hand_over.clear()
	for item_id: Variant in hand_over:
		_choice.hand_over[item_id as String] = hand_over[item_id] as int
	_is_handed_over = true
	_next_pick()


func _on_placement_panel_placement_chosen(placement: ItemPlacement) -> void:
	_choice.placements[_item_blocks[_next_block]] = placement
	_next_block += 1
	_next_pick()


func _on_placement_panel_cancelled() -> void:
	step_back()


# A press that took Ready back asks nothing.
func _on_leave_button_pressed() -> void:
	if _leave_button.is_taking_back():
		return
	leave_requested.emit()


func _on_team_button_pressed() -> void:
	team_requested.emit()


func _on_viewport_gui_focus_changed(_control: Control) -> void:
	_refresh_keywords()


func _on_summary_meta_hover_changed(_meta: Variant) -> void:
	_refresh_keywords()
