# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_map_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The co-op campaign map, for tests/ui/campaign: 2- and 4-seat host runs through the real
## SaveService and CampaignService, acting for seat 0 and for seat 1 (set_local_seat), at
## 1280×720. Route votes by keys and pad: a vote on its node and in the side panel, a
## re-vote moving it, the same node sending nothing, and the last vote's draw (a teammate's and
## the seat's own) showing the drawn node with Continue while the run is already inside it. The
## swap flow: a proposal made, declined, withdrawn and accepted, shown on both seats' units until
## it ends, in the side panel and the Team panel's notes; each refusal named for the teammate,
## made by staging the run under a panel that still shows what it saw. Solo still chooses with
## ChooseNodeCommand and shows no co-op part. No press here leaves the map, so nothing changes
## scene. Writes save files, so it runs only with a test user folder; it deletes user://saves/
## before and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const MAP_SCENE: String = "res://ui/campaign/campaign_map_screen.tscn"
const VOTE_STATUS_SCENE: String = "res://ui/campaign/route_vote_status.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 3
# Made-up Steam ids, one per seat.
const STEAM_IDS: Array[int] = [0x1111, 0x2222, 0x3333, 0x4444]
const RUN_SEED: int = 0x51A7E
const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# The seat counts and local seats every case runs in.
const SEAT_COUNTS: Array[int] = [2, 4]
const LOCAL_SEATS: Array[int] = [0, 1]

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null

# Every batch the session settled since the last _batches.clear(): [seat, is_rejected, label].
var _batches: Array[Array] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")


## Runs every case. Call only with a test user folder.
func run() -> void:
	_catalog = EffectCatalog.index()
	for count: int in SEAT_COUNTS:
		for local: int in LOCAL_SEATS:
			_test_votes(count, local)
			_test_own_vote_draws(count, local)
			_test_swaps(count, local)
			_test_refusals(count, local)
	_test_continue()
	_test_refusal_text()
	_test_solo()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_votes(count: int, local: int) -> void:
	var session: CampaignSession = _start(count, local)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var tag: String = "%d seats, seat %d" % [count, local]
	var screen: Control = _add(MAP_SCENE)
	var map_view: CampaignMapView = screen.call(&"get_map_view")
	var status: RouteVoteStatus = screen.call(&"get_vote_status")
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var lines: PackedStringArray = status.get_seat_lines()
	var none_voted: bool = lines.size() == count
	for line: String in lines:
		none_voted = none_voted and line.ends_with(": hasn't voted")
	_check.call("votes (%s): the map asks for a vote, every seat yet to vote" % [tag], (
			status.visible and none_voted and hints.context == &"VOTE"
			and screen.call(&"get_info_text") == "Vote for the next node."
			and status.get_detail().begins_with("0 of %d voted." % [count])
	), "%s; %s; %s" % [screen.call(&"get_info_text"), lines, hints.context])
	var reachable: PackedInt32Array = map_view.get_reachable()
	if reachable.size() < 2:
		_check.call("votes (%s): floor 1 offers two nodes" % [tag], false, str(reachable))
		_remove(screen)
		return
	var first: int = reachable[0]
	var second: int = reachable[1]
	map_view.focus_first_reachable()
	_batches.clear()
	_press_key(KEY_ENTER)
	_check.call("votes (%s): Enter votes for the node; its badge and line show the seat" % [tag], (
			_only_batch(local, false) and run.open_route_votes() == {local: first}
			and _badge_seats(map_view, first) == PackedInt32Array([local])
			and status.get_seat_lines()[local] == "You: %s" % [_node_text(run, first)]
	), "%s; %s; %s" % [_batches, run.open_route_votes(), status.get_seat_lines()])
	_batches.clear()
	_press_key(KEY_ENTER)
	_check.call("votes (%s): pressing the node voted for sends nothing" % [tag], (
			_batches.is_empty()
	), str(_batches))
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	_press_pad(JOY_BUTTON_A)
	_check.call("votes (%s): a re-vote by pad moves the vote and its badge" % [tag], (
			_only_batch(local, false) and run.open_route_votes() == {local: second}
			and map_view.get_vote_badge(first) == null
			and _badge_seats(map_view, second) == PackedInt32Array([local])
	), "%s; %s" % [_batches, run.open_route_votes()])
	var others: PackedInt32Array = _others(run, local)
	for i: int in others.size() - 1:
		_submit(RouteVoteCommand.for_session(session, others[i], first))
	var waiting: PackedInt32Array = others.slice(0, others.size() - 1)
	var shown: PackedStringArray = status.get_seat_lines()
	var lines_match: bool = shown[others[others.size() - 1]].ends_with("hasn't voted")
	for seat: int in waiting:
		lines_match = lines_match and shown[seat] == "%s: %s" % [
			CampaignLink.seat_name(seat), _node_text(run, first),
		]
	_check.call("votes (%s): teammates' votes show on their node and by name" % [tag], (
			_badge_seats(map_view, first) == waiting and lines_match
			and status.get_detail().begins_with("%d of %d voted." % [count - 1, count])
	), "%s; %s" % [status.get_detail(), shown])
	_test_team_votes(screen, run, others)
	_batches.clear()
	_submit(RouteVoteCommand.for_session(session, others[others.size() - 1], first))
	_check_draw(screen, run, tag + ", a teammate's vote last", PackedInt32Array([first, second]))
	_remove(screen)


# The Team panel's notes name each teammate's vote: voted for a node, or not yet.
func _test_team_votes(screen: Control, run: CampaignRunState, others: PackedInt32Array) -> void:
	_press_key(KEY_CTRL)
	var army: ArmyView = screen.call(&"get_army_view")
	army.get_team_button().pressed.emit()
	var panel: TeamPanel = screen.call(&"get_team_panel")
	var votes: Dictionary[int, int] = run.open_route_votes()
	var notes: PackedStringArray = []
	var notes_match: bool = panel.visible and panel.get_rows().size() == others.size()
	for row: TeammateRow in panel.get_rows():
		var note: String = row.get_note_text()
		notes.append(note)
		var expected: String = (
				"Voted for %s." % [_node_text(run, votes[row.shown_seat])]
				if votes.has(row.shown_seat) else "Hasn't voted."
		)
		notes_match = notes_match and note.contains(expected)
	_check.call("votes: the Team panel notes each teammate's vote", notes_match, str(notes))
	panel.close()
	army.close()


# The run already inside the node its votes drew: the drawn node and its votes shown, Continue
# focused, no node to choose.
func _check_draw(
		screen: Control, run: CampaignRunState, tag: String, voted: PackedInt32Array
) -> void:
	var status: RouteVoteStatus = screen.call(&"get_vote_status")
	var map_view: CampaignMapView = screen.call(&"get_map_view")
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var drawn: int = run.node
	var shown_votes: int = 0
	for node_id: int in voted:
		var badge: MapVoteBadge = map_view.get_vote_badge(node_id)
		shown_votes += 0 if badge == null else badge.get_seats().size()
	var chosen: bool = false
	for fact: CampaignFact in run.fact_log:
		chosen = chosen or (
				fact.kind == CampaignFact.Kind.NODE_CHOSEN and fact.seat == CampaignFact.NO_SEAT
				and fact.amount == drawn
		)
	_check.call("draw (%s): the run enters the drawn node; the map shows it with Continue" % [
		tag,
	], (
			not run.is_on_map() and voted.has(drawn) and chosen
			and screen.call(&"is_drawing") == true and status.is_drawing()
			and status.get_heading() == "The team drew %s" % [_node_text(run, drawn)]
			and status.get_continue_button().visible
			and status.get_continue_button().has_focus()
			and map_view.get_reachable().is_empty()
			and shown_votes == run.seats.size()
			and hints.context == &"DRAWN"
	), "%s; drawn %d; votes shown %d; %s" % [status.get_heading(), drawn, shown_votes,
		hints.context])
	_batches.clear()
	_press_key(KEY_CTRL)
	var army: ArmyView = screen.call(&"get_army_view")
	_check.call("draw (%s): the army view stays shut while the draw shows" % [tag], (
			not army.visible and _batches.is_empty()
	), "army %s" % [army.visible])


# Every teammate votes first; the seat's own vote by pad completes the set and its answer shows
# the draw. (The map isn't clicked here: with no frame, its autowrapped side labels lay the
# screen out taller than the window, so floor 1 falls outside it; run_all's map clicks a node.)
func _test_own_vote_draws(count: int, local: int) -> void:
	var session: CampaignSession = _start(count, local)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var screen: Control = _add(MAP_SCENE)
	var map_view: CampaignMapView = screen.call(&"get_map_view")
	var reachable: PackedInt32Array = map_view.get_reachable()
	var last: int = reachable[reachable.size() - 1]
	for other: int in _others(run, local):
		_submit(RouteVoteCommand.for_session(session, other, reachable[0]))
	map_view.get_node_button(last).grab_focus()
	_batches.clear()
	_press_pad(JOY_BUTTON_A)
	_check.call("draw (%d seats, seat %d): the seat's own vote by pad casts the last vote" % [
		count, local,
	], _only_batch(local, false), str(_batches))
	_check_draw(
			screen, run, "%d seats, seat %d, own vote last" % [count, local],
			PackedInt32Array([reachable[0], last])
	)
	_remove(screen)


func _test_swaps(count: int, local: int) -> void:
	var session: CampaignSession = _start(count, local)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var partner: int = 1 - local
	var tag: String = "%d seats, seat %d" % [count, local]
	var mine: PackedStringArray = _swappable(run, local)
	var theirs: PackedStringArray = _swappable(run, partner)
	if mine.size() < 2 or theirs.size() < 2:
		_check.call("swaps (%s): each seat has two units to swap" % [tag], false, "%s %s" % [
			mine, theirs,
		])
		return
	var screen: Control = _add(MAP_SCENE)
	var panel: SwapPanel = _open_swaps(screen)
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var row: SwapRow = panel.get_row(partner)
	_check.call("swaps (%s): Army, then Swaps, opens a row per teammate" % [tag], (
			panel.visible and panel.get_rows().size() == count - 1 and row != null
			and row.get_summary() == "No swap with %s." % [CampaignLink.seat_name(partner)]
			and hints.context == SwapPanel.HINT_SWAPS
	), "%d rows; %s" % [panel.get_rows().size(), hints.context])
	if row == null:
		_remove(screen)
		return
	var picker: SwapPicker = panel.get_picker()
	row.get_propose_button().grab_focus()
	_press_key(KEY_ENTER)
	var commander: Button = _commander_button(picker, run.seat_run(local))
	_check.call("swaps (%s): Propose lists the seat's units, the commander not pressable" % [
		tag,
	], (
			picker.visible and picker.get_step() == SwapPicker.Step.OWN
			and picker.get_prompt() == "Choose your unit to send to %s's map." % [
				CampaignLink.seat_name(partner),
			]
			and commander != null and commander.disabled
			and commander.text.ends_with("(commander)")
	), "%s; %s" % [picker.get_prompt(), "none" if commander == null else commander.text])
	_press_key(KEY_ENTER)
	_batches.clear()
	_press_key(KEY_ENTER)
	var proposal: UnitSwap = UnitSwap.between(run, local, partner)
	row = panel.get_row(partner)
	var swap_status: SwapStatus = screen.call(&"get_swap_status")
	_check.call("swaps (%s): two Enters propose a unit of each; the row and side panel wait" % [
		tag,
	], (
			_only_batch(local, false) and proposal != null and proposal.seat_a == local
			and run.swap_proposals.has(proposal) and not picker.visible
			and row.get_status() == SwapText.PairStatus.PROPOSED_BY_VIEWER
			and row.get_summary().begins_with("You proposed your ")
			and swap_status.get_lines() == PackedStringArray([
				"Your swap proposal waits for %s." % [CampaignLink.seat_name(partner)],
			])
	), "%s; %s; %s" % [_batches, row.get_summary(), swap_status.get_lines()])
	if proposal == null:
		_remove(screen)
		return
	_submit(AnswerSwapCommand.new(partner, local, false, proposal.unit_a, proposal.unit_b))
	row = panel.get_row(partner)
	_check.call("swaps (%s): the teammate's decline ends it; the row offers Propose again" % [
		tag,
	], (
			row.get_status() == SwapText.PairStatus.NONE and run.swap_proposals.is_empty()
			and not swap_status.visible
	), row.get_summary())
	_click(row.get_propose_button())
	_click(picker.get_unit_buttons()[_index_of(picker, mine[0])])
	_batches.clear()
	_click(picker.get_unit_buttons()[_index_of(picker, theirs[0])])
	row = panel.get_row(partner)
	_check.call("swaps (%s): a proposal by mouse names the units clicked" % [tag], (
			_only_batch(local, false) and row.get_status() == SwapText.PairStatus.PROPOSED_BY_VIEWER
			and UnitSwap.between(run, local, partner) != null
			and UnitSwap.between(run, local, partner).unit_a == mine[0]
			and UnitSwap.between(run, local, partner).unit_b == theirs[0]
	), str(_batches))
	row.get_withdraw_button().grab_focus()
	_batches.clear()
	_press_pad(JOY_BUTTON_A)
	row = panel.get_row(partner)
	_check.call("swaps (%s): Withdraw by pad ends the seat's own proposal" % [tag], (
			_only_batch(local, false) and row.get_status() == SwapText.PairStatus.NONE
			and UnitSwap.between(run, local, partner) == null
	), str(_batches))
	_submit(ProposeSwapCommand.new(partner, theirs[0], local, mine[0]))
	row = panel.get_row(partner)
	var name: String = CampaignLink.seat_name(partner)
	var answers: Array[Button] = row.get_buttons()
	_check.call("swaps (%s): a teammate's proposal shows Accept and Decline; the map says so" % [
		tag,
	], (
			row.get_status() == SwapText.PairStatus.PROPOSED_TO_VIEWER
			and answers.size() == 2 and answers[0] == row.get_accept_button()
			and answers[1] == row.get_decline_button()
			and row.get_summary().begins_with("%s proposes their " % [name])
			and swap_status.get_lines() == PackedStringArray([
				"%s proposes a swap: open Army, then Swaps, to answer." % [name],
			])
	), "%s; %s" % [row.get_summary(), swap_status.get_lines()])
	row.get_accept_button().grab_focus()
	_press_key(KEY_RIGHT)
	_batches.clear()
	_press_key(KEY_ENTER)
	row = panel.get_row(partner)
	_check.call("swaps (%s): Right then Enter declines it" % [tag], (
			_only_batch(local, false) and row.get_status() == SwapText.PairStatus.NONE
			and _last_swap_end(run) == UnitSwap.END_DECLINED
	), "%s; %s" % [_batches, _last_swap_end(run)])
	_submit(ProposeSwapCommand.new(partner, theirs[0], local, mine[0]))
	_batches.clear()
	_click(panel.get_row(partner).get_accept_button())
	row = panel.get_row(partner)
	_check.call("swaps (%s): a click accepts it; the row shows the swap" % [tag], (
			_only_batch(local, false) and row.get_status() == SwapText.PairStatus.ACCEPTED
			and run.flow.swaps.size() == 1
			and row.get_summary().begins_with("Swapped for the next combat: your ")
			and swap_status.get_lines() == PackedStringArray([
				"Swap with %s for the next combat." % [name],
			])
	), "%s; %s" % [_batches, row.get_summary()])
	_press_key(KEY_ESCAPE)
	var army: ArmyView = screen.call(&"get_army_view")
	_check.call("swaps (%s): Esc closes the panel, back to the army view's Swaps" % [tag], (
			not panel.visible and army.visible and army.get_swaps_button().has_focus()
	), "panel %s" % [panel.visible])
	var both: String = "Next combat: %s goes to %s's map; their %s comes to yours." % [
		SwapText.unit_label(run, local, mine[0], local, _catalog), name,
		SwapText.unit_title(run, partner, theirs[0], _catalog),
	]
	_check.call("swaps (%s): the army view shows the seat's swapped unit and both units" % [tag], (
			_row_text(army, mine[0]).ends_with("\nSwap: to %s's map" % [name])
			and army.get_swap_note_text() == both
	), "%s; %s" % [_row_text(army, mine[0]), army.get_swap_note_text()])
	army.get_team_button().pressed.emit()
	var team: TeamPanel = screen.call(&"get_team_panel")
	var note: String = _team_note(team, partner)
	_check.call("swaps (%s): the Team panel notes the teammate's swap and vote" % [tag], (
			note == "Hasn't voted. Swapping their %s for %s next combat." % [
				SwapText.unit_title(run, partner, theirs[0], _catalog),
				SwapText.unit_label(run, local, mine[0], local, _catalog),
			]
	), note)
	team.close()
	army.close()
	_remove(screen)
	_service.call(&"set_local_seat", partner)
	var other_screen: Control = _add(MAP_SCENE)
	_press_key(KEY_CTRL)
	var other_army: ArmyView = other_screen.call(&"get_army_view")
	_check.call("swaps (%s): the teammate's own army shows their swapped unit too" % [tag], (
			_row_text(other_army, theirs[0]).ends_with(
				"\nSwap: to %s's map" % [CampaignLink.seat_name(local)]
			)
	), _row_text(other_army, theirs[0]))
	_remove(other_screen)
	_service.call(&"set_local_seat", local)
	screen = _add(MAP_SCENE)
	_press_key(KEY_CTRL)
	army = screen.call(&"get_army_view")
	_submit(WithdrawSwapCommand.new(partner, local))
	_check.call("swaps (%s): the swap shows until it ends; the teammate's withdraw ends it" % [
		tag,
	], (
			run.flow.swaps.is_empty() and not _row_text(army, mine[0]).contains("Swap:")
			and army.get_swap_note_text().is_empty()
			and _last_swap_end(run) == UnitSwap.END_WITHDRAWN
	), "%s; %s" % [_row_text(army, mine[0]), army.get_swap_note_text()])
	_remove(screen)


# Each refusal, the panel still showing what it saw while the run is staged under it.
func _test_refusals(count: int, local: int) -> void:
	var session: CampaignSession = _start(count, local)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var partner: int = 1 - local
	var tag: String = "%d seats, seat %d" % [count, local]
	var mine: PackedStringArray = _swappable(run, local)
	var theirs: PackedStringArray = _swappable(run, partner)
	var screen: Control = _add(MAP_SCENE)
	var panel: SwapPanel = _open_swaps(screen)
	var picker: SwapPicker = panel.get_picker()
	var name: String = CampaignLink.seat_name(partner)
	var prefix: String = "Can't swap with %s: " % [name]
	# One swap or proposal per pair (decision 2).
	_pick_own(panel, partner, mine[0])
	var button: Button = _picker_button(picker, theirs[0])
	run.swap_proposals.append(UnitSwap.new(partner, theirs[1], local, mine[1]))
	_expect_refusal(panel, button, tag, "a pair's second proposal", (
			prefix + "%s and %s already have a swap or a proposal." % [
				CampaignLink.seat_name(local), name,
			]
	))
	run.swap_proposals.clear()
	panel.refresh()
	# A living unit of the army (decision 3).
	_pick_own(panel, partner, mine[0])
	button = _picker_button(picker, theirs[0])
	var partner_run: SeatRun = run.seat_run(partner)
	var their_unit: UnitInstance = partner_run.unit(theirs[0])
	var their_index: int = partner_run.army.find(their_unit)
	partner_run.army.erase(their_unit)
	partner_run.fallen.append(their_unit)
	_expect_refusal(panel, button, tag, "a fallen unit", (
			prefix + "%s has no living unit %s in its army." % [
				name, SwapText.unit_title(run, partner, theirs[0], _catalog),
			]
	))
	partner_run.fallen.erase(their_unit)
	partner_run.army.insert(their_index, their_unit)
	panel.refresh()
	# A unit already in an accepted swap with a third seat (P11 question 22).
	if count > 2:
		_pick_own(panel, partner, mine[0])
		button = _picker_button(picker, theirs[0])
		var third: int = _others(run, local)[1]
		run.flow.swaps.append(UnitSwap.new(local, mine[0], third, _swappable(run, third)[0]))
		_expect_refusal(panel, button, tag, "a unit in a swap", (
				prefix + "%s is already in a swap." % [
					SwapText.unit_label(run, local, mine[0], local, _catalog),
				]
		))
		run.flow.swaps.clear()
		panel.refresh()
	# A stale answer: the proposal names other units now (P11 question 95).
	_submit(ProposeSwapCommand.new(partner, theirs[0], local, mine[0]))
	UnitSwap.between(run, local, partner).unit_b = mine[1]
	_expect_refusal(panel, panel.get_row(partner).get_accept_button(), tag, "a stale answer", (
			prefix + "%s's proposal names other units now." % [name]
	))
	# An answer to a proposal no longer open (decision 7).
	run.swap_proposals.clear()
	_expect_refusal(panel, panel.get_row(partner).get_decline_button(), tag, "a gone proposal", (
			prefix + "%s has no open proposal to %s." % [name, CampaignLink.seat_name(local)]
	))
	panel.refresh()
	# A withdraw with nothing left to withdraw (decision 7).
	_submit(ProposeSwapCommand.new(local, mine[0], partner, theirs[0]))
	run.swap_proposals.clear()
	_expect_refusal(panel, panel.get_row(partner).get_withdraw_button(), tag, "a gone withdraw", (
			prefix + "%s has no swap or proposal with %s." % [CampaignLink.seat_name(local), name]
	))
	_remove(screen)


# Pressing button sends a command the run refuses; the panel shows expected.
func _expect_refusal(
		panel: SwapPanel, button: Button, tag: String, what: String, expected: String
) -> void:
	_batches.clear()
	if button == null or not button.is_visible_in_tree():
		_check.call("refusals (%s): %s's button shows" % [tag, what], false, "")
		return
	button.grab_focus()
	_press_key(KEY_ENTER)
	_check.call("refusals (%s): %s is refused, naming the teammate" % [tag, what], (
			_only_batch(_local(), true)
			and panel.get_status_text() == expected
	), "%s; %s" % [_batches, panel.get_status_text()])


# Propose for partner, then own_unit: the picker waits on the teammate's unit.
func _pick_own(panel: SwapPanel, partner: int, own_unit: String) -> void:
	panel.get_row(partner).get_propose_button().pressed.emit()
	var button: Button = _picker_button(panel.get_picker(), own_unit)
	if button != null:
		button.pressed.emit()


# The draw's Continue reports once a node is drawn, by Enter.
func _test_continue() -> void:
	var session: CampaignSession = _start(2, 0)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var status: RouteVoteStatus = (load(VOTE_STATUS_SCENE) as PackedScene).instantiate()
	_root.add_child(status)
	var reports: Array[int] = []
	status.continued.connect(func() -> void: reports.append(1))
	status.show_vote(run, 0)
	var hidden_while_open: bool = not status.get_continue_button().visible
	status.show_draw(run, 0, run.next_nodes()[0])
	status.get_continue_button().grab_focus()
	_press_key(KEY_ENTER)
	_check.call("draw: Continue shows only once a node is drawn, and Enter reports it", (
			hidden_while_open and reports.size() == 1
	), "%d reports" % [reports.size()])
	_root.remove_child(status)
	status.free()


# Reasons that the panel never sends, through the same wording.
func _test_refusal_text() -> void:
	var session: CampaignSession = _start(2, 0)
	if session == null:
		return
	var run: CampaignRunState = session.run
	var mine: String = _swappable(run, 0)[0]
	var commander: String = SwapText.refusal(
			"a commander stays on its own map", run, 0, 1, _catalog
	)
	var in_swap: String = SwapText.refusal("%s is already in a swap" % [mine], run, 0, 1, _catalog)
	_check.call("refusals: a commander's and a swapped unit's reasons name the teammate", (
			commander == "Can't swap with Player 2: a commander stays on its own map."
			and in_swap == "Can't swap with Player 2: your %s is already in a swap." % [
				SwapText.unit_title(run, 0, mine, _catalog),
			]
	), "%s | %s" % [commander, in_swap])


func _test_solo() -> void:
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	if err != OK or session == null:
		_check.call("solo: a run starts", false, error_string(err))
		return
	session.run.seat_run(CampaignData.HOST_SEAT).pending_offers.erase(StartingOffer.OFFER_KEY)
	session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	var screen: Control = _add(MAP_SCENE)
	var map_view: CampaignMapView = screen.call(&"get_map_view")
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var reachable: PackedInt32Array = map_view.get_reachable()
	var has_badge: bool = false
	for node_id: int in reachable:
		has_badge = has_badge or map_view.get_vote_badge(node_id) != null
	_check.call("solo: the map shows no vote, swap or badge, and asks to choose", (
			not (screen.call(&"get_vote_status") as Control).visible
			and not (screen.call(&"get_swap_status") as Control).visible
			and not has_badge and hints.context == &"MAP"
			and screen.call(&"get_info_text") == "Choose the next node."
	), "%s; %s" % [screen.call(&"get_info_text"), hints.context])
	_press_key(KEY_CTRL)
	var army: ArmyView = screen.call(&"get_army_view")
	_check.call("solo: the army view offers neither Team nor Swaps", (
			army.visible and not army.get_team_button().visible
			and not army.get_swaps_button().visible
	), "")
	army.close()
	# Inside a node, so the choice is refused and the screen stays: the command it sent shows.
	session.run.flow.stage = RunFlow.Stage.NODE
	map_view.focus_first_reachable()
	_batches.clear()
	_press_key(KEY_ENTER)
	session.run.flow.stage = RunFlow.Stage.MAP
	_check.call("solo: Enter still sends ChooseNodeCommand", (
			_batches.size() == 1 and _batches[0][2] == "choose node %d" % [reachable[0]]
			and str(screen.call(&"get_status_text")).begins_with("Can't go there: ")
	), "%s; %s" % [_batches, screen.call(&"get_status_text")])
	_remove(screen)


# A new host run of count seats in a fresh save file, acting for local, every starting offer
# put aside. Null, reported, when it doesn't start.
func _start(count: int, local: int) -> CampaignSession:
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var ids: PackedInt64Array = []
	for i: int in count:
		ids.append(STEAM_IDS[i])
	var err: Error = _saves.call(&"start_new_multiplayer_run", ids)
	var session: CampaignSession = _session()
	if err != OK or session == null or session.seats.size() != count:
		_check.call("co-op: a %d-seat host run starts" % [count], false, error_string(err))
		return null
	if not _service.call(&"set_local_seat", local):
		_check.call("co-op: the local seat is set to %d" % [local], false, "")
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	return session


# Opens screen's army view by Ctrl, then its Swaps by click: the swap panel.
func _open_swaps(screen: Control) -> SwapPanel:
	_press_key(KEY_CTRL)
	var army: ArmyView = screen.call(&"get_army_view")
	_click(army.get_swaps_button())
	return screen.call(&"get_swap_panel") as SwapPanel


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# The seat the screens act for now.
func _local() -> int:
	var seat: int = _service.call(&"local_seat")
	return seat


# Sends command as a teammate would, outside any screen.
func _submit(command: CampaignCommand) -> void:
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	if batch == null or batch.is_rejected():
		_check.call("co-op: %s resolves" % [command.get_label()], false, (
				batch.rejected_reason if batch != null else "no batch"
		))


# Every seat of run but local, ascending.
func _others(run: CampaignRunState, local: int) -> PackedInt32Array:
	var others: PackedInt32Array = []
	for seat: int in run.seat_numbers():
		if seat != local:
			others.append(seat)
	return others


# Seat's living units a swap may name, in army order.
func _swappable(run: CampaignRunState, seat: int) -> PackedStringArray:
	var found: PackedStringArray = []
	for unit: UnitInstance in run.seat_run(seat).army:
		if UnitSwap.unit_problem(run, seat, unit.instance_id).is_empty():
			found.append(unit.instance_id)
	return found


func _badge_seats(map_view: CampaignMapView, node_id: int) -> PackedInt32Array:
	var badge: MapVoteBadge = map_view.get_vote_badge(node_id)
	return PackedInt32Array() if badge == null else badge.get_seats()


func _node_text(run: CampaignRunState, node_id: int) -> String:
	return RouteVoteStatus.node_text(run.graph, node_id)


# The picker's button for unit_id, by its place in the listed seat's army; null when not listed.
func _picker_button(picker: SwapPicker, unit_id: String) -> Button:
	var index: int = _index_of(picker, unit_id)
	var buttons: Array[Button] = picker.get_unit_buttons()
	return buttons[index] if index >= 0 and index < buttons.size() else null


# unit_id's place in the army the picker lists now; -1 when neither seat holds it.
func _index_of(picker: SwapPicker, unit_id: String) -> int:
	var run: CampaignRunState = _session().run
	var seat: int = (
			_local() if picker.get_step() == SwapPicker.Step.OWN
			else picker.get_partner()
	)
	var army: Array[UnitInstance] = run.seat_run(seat).army
	for i: int in army.size():
		if army[i].instance_id == unit_id:
			return i
	return -1


func _commander_button(picker: SwapPicker, seat_run: SeatRun) -> Button:
	for i: int in seat_run.army.size():
		if seat_run.army[i].instance_id == seat_run.commander_id:
			return picker.get_unit_buttons()[i]
	return null


func _row_text(army: ArmyView, unit_id: String) -> String:
	for row: UnitGearRow in army.get_rows():
		if row.unit_id == unit_id:
			return row.get_name_text()
	return ""


func _team_note(panel: TeamPanel, seat: int) -> String:
	for row: TeammateRow in panel.get_rows():
		if row.shown_seat == seat:
			return row.get_note_text()
	return ""


# The reason of run's last SWAP_ENDED; empty with none.
func _last_swap_end(run: CampaignRunState) -> String:
	for i: int in range(run.fact_log.size() - 1, -1, -1):
		if run.fact_log[i].kind == CampaignFact.Kind.SWAP_ENDED:
			return run.fact_log[i].definition_id
	return ""


# Whether exactly one batch settled since the last clear, of seat, rejected or not.
func _only_batch(seat: int, is_rejected: bool) -> bool:
	return _batches.size() == 1 and _batches[0][0] == seat and _batches[0][1] == is_rejected


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	_batches.append([batch.seat, batch.is_rejected(), batch.label])


# scene instanced into the root at SCREEN_SIZE, anchored top-left, laid out.
func _add(path: String) -> Control:
	var scene: PackedScene = load(path)
	var screen: Control = scene.instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	_lay_out(screen)
	return screen


func _remove(screen: Control) -> void:
	_root.remove_child(screen)
	screen.free()


# Sorts the screen's containers twice, parents first, as a frame's deferred sort would.
func _lay_out(screen: Control) -> void:
	for _pass: int in 2:
		for node: Node in screen.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# A left click at the middle of control, its screen laid out first.
func _click(control: Control) -> void:
	var top: Control = control
	while top.get_parent_control() != null:
		top = top.get_parent_control()
	_lay_out(top)
	var point: Vector2 = control.get_global_rect().get_center()
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		_root.push_input(click, true)


func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = is_down
		_root.push_input(event, true)


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		_root.push_input(event, true)
