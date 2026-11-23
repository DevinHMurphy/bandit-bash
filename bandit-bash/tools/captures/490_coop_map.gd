# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     490_coop_map.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The co-op campaign map for the host's seat, in a 2-seat and a 4-seat run: the route vote open,
## teammates' votes, the host's vote and re-vote; the army view's Swaps, the swap panel with no
## swap, each picker step, a proposal made, one made to the host, an accepted swap, a refusal
## naming the teammate; the army view and Team panel showing the swap, the side panel's status;
## then the last vote's draw with Continue.[br]
## A seeded session per seat count stands in for the solo run in CampaignService, as 485's does;
## every vote and swap is staged on it directly, which saves nothing, and only refused presses go
## through the service. The solo session then comes back and the group ends on its map, as it
## found it.[br]
## Needs: the map, as the co-op screens leave it (485_coop_screens; 489_coop_battle, between
## them, leaves it as it found it).

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# The seat counts shot.
const SEAT_COUNTS: Array[int] = [2, 4]

var _coop: CampaignSession = null


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op map shots need the map (screen %d)" % [router_screen()])
		return true
	var solo: CampaignSession = campaign()
	for count: int in SEAT_COUNTS:
		_coop = _new_coop(count)
		if _coop == null:
			fail("the %d-seat run couldn't be built" % [count])
			continue
		node(^"CampaignService").set(&"session", _coop)
		note("co-op map shots: a %d-seat run seeded %X stands in for the solo run, for the host" % [
			count, RUN_SEED,
		])
		await _shoot(count)
		_coop.close()
	node(^"CampaignService").set(&"session", solo)
	node(^"CampaignService").call(&"set_local_seat", CampaignData.HOST_SEAT)
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# Every vote and swap state for count seats, the draw last.
func _shoot(count: int) -> void:
	var prefix: String = "coop%d_" % [count]
	var nodes: PackedInt32Array = _coop.run.next_nodes()
	if nodes.size() < 2:
		fail("the %d-seat map's floor 1 has one node" % [count])
		return
	await goto(SCREEN_MAP, prefix + "vote_open")
	# Every teammate but the last votes; in 2 seats that is none, and the teammate's vote draws.
	if count > 2:
		for seat: int in range(1, count - 1):
			_vote(seat, nodes[seat % 2])
		await frames(SETTLE_FRAMES)
		await capture(prefix + "vote_teammates")
	_vote(CampaignData.HOST_SEAT, nodes[0])
	await frames(SETTLE_FRAMES)
	await capture(prefix + "vote_own")
	_vote(CampaignData.HOST_SEAT, nodes[1])
	await frames(SETTLE_FRAMES)
	await capture(prefix + "vote_moved")
	await _swaps(prefix, count)
	_vote(count - 1, nodes[0])
	await frames(SETTLE_FRAMES)
	if scene().call(&"is_drawing") != true:
		fail("the last vote didn't show the draw")
	await capture(prefix + "draw")


# The swap panel's states, then the swap on the army view, the Team panel and the side panel.
func _swaps(prefix: String, count: int) -> void:
	var host: int = CampaignData.HOST_SEAT
	var mine: PackedStringArray = _swappable(host)
	var partner_units: PackedStringArray = _swappable(1)
	if mine.size() < 2 or partner_units.is_empty():
		fail("the host or its teammate has too few units to swap")
		return
	(scene().call(&"get_army_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "army_swaps")
	var army: ArmyView = scene().call(&"get_army_view")
	army.get_swaps_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "swaps_none")
	var panel: SwapPanel = scene().call(&"get_swap_panel")
	panel.get_row(1).get_propose_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "swap_pick_own")
	var picker: SwapPicker = panel.get_picker()
	_first_enabled(picker).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "swap_pick_theirs")
	picker.back()
	picker.back()
	_coop.submit(ProposeSwapCommand.new(host, mine[0], 1, partner_units[0]))
	if count > 2:
		_coop.submit(ProposeSwapCommand.new(2, _swappable(2)[0], host, mine[1]))
	await frames(SETTLE_FRAMES)
	await capture(prefix + "swap_proposed")
	if count == 2:
		_coop.submit(WithdrawSwapCommand.new(host, 1))
		_coop.submit(ProposeSwapCommand.new(1, partner_units[0], host, mine[0]))
		await frames(SETTLE_FRAMES)
		await capture(prefix + "swap_to_you")
		_coop.submit(AnswerSwapCommand.new(host, 1, true, partner_units[0], mine[0]))
	else:
		_coop.submit(AnswerSwapCommand.new(1, host, true, mine[0], partner_units[0]))
	await frames(SETTLE_FRAMES)
	await capture(prefix + "swap_accepted")
	await _refusal(prefix, panel, count)
	panel.close()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "army_swapped")
	army.get_team_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "team_notes")
	(scene().call(&"get_team_panel") as TeamPanel).close()
	army.close()
	await frames(SETTLE_FRAMES)
	await capture(prefix + "map_status")


# A refusal shown with the teammate named: in 4 seats a stale answer to seat 2's proposal, in 2
# a withdraw of a swap the run no longer holds; the run is put back after.
func _refusal(prefix: String, panel: SwapPanel, count: int) -> void:
	var run: CampaignRunState = _coop.run
	if count > 2:
		var proposal: UnitSwap = UnitSwap.between(run, CampaignData.HOST_SEAT, 2)
		var seen: String = proposal.unit_b
		proposal.unit_b = proposal.unit_a
		panel.get_row(2).get_accept_button().pressed.emit()
		proposal.unit_b = seen
	else:
		var held: Array[UnitSwap] = run.flow.swaps.duplicate()
		run.flow.swaps.clear()
		panel.get_row(1).get_withdraw_button().pressed.emit()
		run.flow.swaps = held
	await frames(SETTLE_FRAMES)
	if panel.get_status_text().is_empty():
		fail("the staged refusal showed no reason")
	await capture(prefix + "swap_refused")


# Stages seat's vote for node_id on the session, as its own command would resolve.
func _vote(seat: int, node_id: int) -> void:
	_coop.submit(RouteVoteCommand.for_session(_coop, seat, node_id))


# Seat's units a swap may name, in army order.
func _swappable(seat: int) -> PackedStringArray:
	var found: PackedStringArray = []
	for unit: UnitInstance in _coop.run.seat_run(seat).army:
		if UnitSwap.unit_problem(_coop.run, seat, unit.instance_id).is_empty():
			found.append(unit.instance_id)
	return found


func _first_enabled(picker: SwapPicker) -> Button:
	for button: Button in picker.get_unit_buttons():
		if not button.disabled:
			return button
	return picker.get_back_button()


# A new run of count seats on RUN_SEED, as CampaignService builds one, every starting offer put
# aside so the map opens.
func _new_coop(count: int) -> CampaignSession:
	var seats: PackedInt32Array = []
	var factions: Dictionary[int, String] = {}
	for seat: int in count:
		seats.append(seat)
		factions[seat] = FACTION
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, seats
	)
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids,
			made.starting_offer_streams()
	)
	if start.run == null:
		return null
	made.run = start.run
	for seat: int in seats:
		made.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return made
