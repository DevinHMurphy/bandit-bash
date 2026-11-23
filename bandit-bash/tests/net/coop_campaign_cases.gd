# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_campaign_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Co-op campaign runs in the harness for tests/net/run_all.gd, 2 and 4 seats, every client acting
## through its [ClientMirror]: route votes and their draw, a Treasure, a Camp, an Armory (a
## refused purchase) and a Guildhall, gifts, swaps proposed, accepted and withdrawn (a visitor's
## battle is the co-op battle cases'), an individual event, a team event (Bandit Toll's Fight to
## its battle's start, end and results), an Unknown resolved by a client, and the Key and Boss
## combats' openings. Every client's campaign hash (run, events, open proposals) equals the
## host's after every batch it applies, and every battle batch's hash as it applies. Also: the
## capture carries the events and the proposals, and one missing either is refused; the battle's
## end brings its facts to each client's victory sequence; a refused purchase settles to its
## sender alone; Leave waits for an event's seats and combat (BUG-034). Needs a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

const HOST: int = NetHarness.HOST
const HOST_SEAT: int = CampaignData.HOST_SEAT

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000301

const SAVE_NUMBER: int = 1

# Gold every seat holds, so no price refuses a purchase or a toll.
const RICH: int = 1000

# The node type of every node on floors 1 to 7, in floor order: whichever node a split vote
# draws, the run stands at that type.
const ROUTE: Array[CampaignGraph.NodeType] = [
	CampaignGraph.NodeType.TREASURE,
	CampaignGraph.NodeType.CAMP,
	CampaignGraph.NodeType.ARMORY,
	CampaignGraph.NodeType.GUILDHALL,
	CampaignGraph.NodeType.UNKNOWN,
	CampaignGraph.NodeType.UNKNOWN,
	CampaignGraph.NodeType.UNKNOWN,
]

# The events the host opens on floors 5 and 6 (data/events/), and the options every seat takes.
const OWN_EVENT: String = "dark_goblet"
const POUR_AWAY: int = 2
const TEAM_EVENT: String = "bandit_toll"
const FIGHT: int = 1

# The item each client gives away, one per gift; any item the catalog holds.
const GIFT_ITEMS: int = 2

const SOLD: String = "it is sold"
const NOT_CHOSEN: String = "seat %d hasn't chosen at the event"
const UNFOUGHT: String = "the event's surprise combat hasn't been fought"

# The run capture's keys this step adds (NetRelay's).
const EVENTS_KEY: String = "events"
const PROPOSALS_KEY: String = "swap_proposals"


func run() -> void:
	if not _has_test_user_dir():
		_skip("coop campaign: every case", "needs a test user folder (see run_all.gd's class doc)")
		return
	print("    (errors from ClientMirror and RunSaveSections below are expected)")
	for client_count: int in [1, 3]:
		_test_run(client_count)
		_test_opening(client_count, CampaignGraph.NodeType.KEY)
		_test_opening(client_count, CampaignGraph.NodeType.BOSS)
	_test_capture_parts()


# The whole route, every client acting through its mirror.
func _test_run(client_count: int) -> void:
	var tag: String = "coop campaign %d seats:" % [client_count + 1]
	var rig: Rig = _start(client_count, true)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	_start_mirrors(rig)
	_check("%s every client mirrors the host's run" % [tag], (
			_every_mirror_built(rig) and _difference(rig).is_empty()
	), _difference(rig))
	var steps: Array[Callable] = [
		_play_treasure, _play_camp, _play_swaps, _play_armory, _play_guildhall, _play_own_event,
		_play_team_event, _play_unknown,
	]
	for step: Callable in steps:
		if not step.call(rig, tag):
			break
	_check("%s every client's campaign hash matched the host's after every batch" % [tag], (
			rig.campaign_checks > 0 and rig.campaign_failures.is_empty()
	), "%d checked; %s" % [rig.campaign_checks, rig.campaign_failures])
	_check("%s every battle batch's hash matched the host's as it applied" % [tag], (
			rig.combat_checks > 0 and rig.combat_failures.is_empty()
	), "%d checked; %s" % [rig.combat_checks, rig.combat_failures])
	_stop(rig)


# Floor 1: a split vote, a client's re-vote, the draw; then the chest, every seat's take, a Leave.
func _play_treasure(rig: Rig, tag: String) -> bool:
	var next: PackedInt32Array = rig.session.run.next_nodes()
	var other: int = next[next.size() - 1]
	_send(rig, RouteVoteCommand.new(1, other))
	_send(rig, RouteVoteCommand.new(1, next[0]))
	var replaced: bool = rig.session.run.route_votes.get(1, CampaignGraph.NO_NODE) == next[0]
	for seat: int in rig.seats():
		if seat != 1:
			_send(rig, RouteVoteCommand.new(seat, other if seat % 2 == 0 else next[0]))
	var drawn: bool = _is_at(rig, CampaignGraph.NodeType.TREASURE)
	for index: int in rig.clients():
		var copy: CampaignRunState = rig.mirror(index).session.run
		drawn = drawn and copy.node == rig.session.run.node and _drew_node(copy)
	_check("%s a client's re-vote replaces its vote, and the draw reaches every mirror" % [tag], (
			replaced and drawn and _difference(rig).is_empty()
	), _difference(rig))
	_send(rig, OpenTreasureCommand.new(rig.last_client()))
	for seat: int in rig.seats():
		_send(rig, _first_valid(rig, [
			TreasureCommand.new(seat, true, null),
			TreasureCommand.new(seat, true, ItemPlacement.new()),
			TreasureCommand.new(seat, false, null),
		]))
	return _leave(rig, tag, "Treasure")


# Floor 2: every seat's Camp choice and a client's gift to the host seat, then a Leave.
func _play_camp(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _is_at(rig, CampaignGraph.NodeType.CAMP):
		_check("%s the team reaches the Camp" % [tag], false)
		return false
	_send(rig, FeastCommand.new(1))
	for seat: int in rig.seats():
		if seat != 1:
			var trains: Array[CampaignCommand] = []
			for unit: UnitInstance in rig.session.run.seat_run(seat).army:
				trains.append(TrainCommand.new(seat, unit.instance_id))
			_send(rig, _first_valid(rig, trains))
	var gift: String = rig.gifts[0]
	_send(rig, GiftItemCommand.new(1, gift, HOST_SEAT))
	_check("%s a client's gift at the Camp reaches the host seat's convoy on every mirror" % [
		tag,
	], (
			rig.session.run.seat_run(HOST_SEAT).convoy.has(gift)
			and not rig.session.run.seat_run(1).convoy.has(gift)
			and _difference(rig).is_empty()
	), _difference(rig))
	return _leave(rig, tag, "Camp")


# On the map: clients propose, answer and withdraw swaps; every mirror holds the open proposals.
func _play_swaps(rig: Rig, tag: String) -> bool:
	var run: CampaignRunState = rig.session.run
	if rig.clients().size() == 1:
		_send(rig, ProposeSwapCommand.new(1, _soldier(rig, 1), HOST_SEAT, _soldier(rig, HOST_SEAT)))
		var held: bool = _proposals_mirrored(rig, 1)
		_send(rig, WithdrawSwapCommand.new(1, HOST_SEAT))
		_check("%s a client's proposal reaches every mirror, and its withdraw ends it" % [tag], (
				held and _proposals_mirrored(rig, 0) and run.flow.swaps.is_empty()
				and _difference(rig).is_empty()
		), _difference(rig))
		return true
	_send(rig, ProposeSwapCommand.new(1, _soldier(rig, 1), 2, _soldier(rig, 2)))
	_send(rig, ProposeSwapCommand.new(3, _soldier(rig, 3), HOST_SEAT, _soldier(rig, HOST_SEAT)))
	var both: bool = _proposals_mirrored(rig, 2)
	_send(rig, AnswerSwapCommand.new(2, 1, true, _soldier(rig, 1), _soldier(rig, 2)))
	_send(rig, WithdrawSwapCommand.new(3, HOST_SEAT))
	var accepted: bool = run.flow.swaps.size() == 1 and _difference(rig).is_empty()
	_check("%s clients' proposals reach every mirror; one is accepted, one withdrawn" % [tag], (
			both and accepted and _proposals_mirrored(rig, 0) and run.flow.swaps.size() == 1
			and _difference(rig).is_empty()
	), _difference(rig))
	return true


# Floor 3: the host seat buys first; a client's purchase of the same entry is refused to it alone;
# that client buys another; a gift; a Leave.
func _play_armory(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _is_at(rig, CampaignGraph.NodeType.ARMORY):
		_check("%s the team reaches the Armory" % [tag], false)
		return false
	_send(rig, OpenArmoryCommand.new(1))
	var entry: int = _shared_entry(rig)
	if entry < 0:
		_check("%s the Armory stocks an entry both seats can buy" % [tag], false)
		return false
	var attempt: ArmoryPurchaseCommand = _purchase(rig, 1, entry)
	_send(rig, _purchase(rig, HOST_SEAT, entry))
	var host_link: CampaignLink = CampaignLink.new(
			rig.session, HOST_SEAT, CampaignService.submit_command
	)
	var host_refusals: PackedStringArray = []
	host_link.refused.connect(func(reason: String) -> void: host_refusals.append(reason))
	rig.clear()
	var token: int = rig.mirror(1).submit_campaign(attempt)
	rig.harness.step_until_idle()
	var others_quiet: bool = host_refusals.is_empty()
	for index: int in rig.clients():
		if index != 1:
			var heard: Record = rig.record(index)
			others_quiet = (
					others_quiet and heard.settles.is_empty() and heard.batches.is_empty()
					and heard.rejections.is_empty()
			)
	var own: Record = rig.record(1)
	_check("%s a refused purchase settles to its sender alone, with its reason" % [tag], (
			own.settles == [[token, SOLD]]
			and own.rejections == [[1, SOLD]]
			and own.batches.size() == 1
			and others_quiet
			and _difference(rig).is_empty()
	), "%s; %s; %s" % [own.describe(), host_refusals, _difference(rig)])
	host_link.close()
	var buys: Array[CampaignCommand] = []
	for other: int in ArmoryStock.pending(rig.session.run).entries.size():
		buys.append(_purchase(rig, 1, other))
	_send(rig, _first_valid(rig, buys))
	var gift: String = rig.gifts[1]
	var receiver: int = rig.last_client() if rig.clients().size() > 1 else HOST_SEAT
	_send(rig, GiftItemCommand.new(1, gift, receiver))
	_check("%s a client's purchase and gift at the Armory reach every mirror" % [tag], (
			rig.session.run.seat_run(receiver).convoy.has(gift) and _difference(rig).is_empty()
	), _difference(rig))
	return _leave(rig, tag, "Armory")


# Floor 4: a client opens the Guildhall and buys from it, then leaves.
func _play_guildhall(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _is_at(rig, CampaignGraph.NodeType.GUILDHALL):
		_check("%s the team reaches the Guildhall" % [tag], false)
		return false
	_send(rig, OpenGuildhallCommand.new(rig.last_client()))
	var buys: Array[CampaignCommand] = []
	var stock: GuildhallStock = GuildhallStock.pending(rig.session.run)
	for entry: int in (0 if stock == null else stock.entries.size()):
		buys.append(GuildhallPurchaseCommand.new(1, entry))
	var bought: int = rig.session.run.fact_log.size()
	_send(rig, _first_valid(rig, buys))
	_check("%s a client's Guildhall purchase resolves and reaches every mirror" % [tag], (
			rig.session.run.fact_log.size() > bought and _difference(rig).is_empty()
	), _difference(rig))
	return _leave(rig, tag, "Guildhall")


# Floor 5: the host opens an individual event; each client reads it from its mirror and chooses;
# a client's early Leave is refused to it alone; once every seat chose, a client leaves.
func _play_own_event(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _open_event(rig, OWN_EVENT):
		_check("%s the host opens %s" % [tag, OWN_EVENT], false)
		return false
	var readable: bool = true
	for index: int in rig.clients():
		readable = readable and EventNode.view(rig.mirror(index).session, index).is_open()
	_check("%s every client's mirror holds the open event for its screens" % [tag], (
			readable and _difference(rig).is_empty()
	), _difference(rig))
	if not _pour_away(rig, tag, 1):
		return false
	rig.clear()
	var token: int = rig.mirror(1).submit_campaign(LeaveNodeCommand.new(1))
	rig.harness.step_until_idle()
	var reason: String = NOT_CHOSEN % [HOST_SEAT]
	_check("%s BUG-034: a client's Leave before every seat chose is refused to it alone" % [tag], (
			rig.record(1).settles == [[token, reason]]
			and not rig.session.run.is_on_map()
			and _is_quiet_but(rig, 1)
	), rig.record(1).describe())
	for seat: int in rig.seats():
		if seat != 1 and not _pour_away(rig, tag, seat):
			return false
	return _leave(rig, tag, "the individual event")


# Floor 6: the host opens Bandit Toll; every seat votes Fight and applies it; Leave waits for the
# combat; the battle opens on every mirror, plays, ends with its facts on every client, and the
# results leave.
func _play_team_event(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _open_event(rig, TEAM_EVENT):
		_check("%s the host opens %s" % [tag, TEAM_EVENT], false)
		return false
	for seat: int in rig.seats():
		_send(rig, EventVoteCommand.new(seat, FIGHT))
	var drawn: bool = rig.session.run.events.drawn_option() == FIGHT
	for seat: int in rig.seats():
		_send(rig, _event_choice(rig, seat, FIGHT))
	var events: EventRunState = rig.session.run.events
	_check("%s every seat's vote and own apply of Fight reach every mirror" % [tag], (
			drawn and events.is_finished()
			and events.is_combat_pending_at(rig.session.run.floor_number, rig.session.run.node)
			and _difference(rig).is_empty()
	), _difference(rig))
	rig.clear()
	var token: int = rig.mirror(1).submit_campaign(LeaveNodeCommand.new(1))
	rig.harness.step_until_idle()
	_check("%s BUG-034: a client's Leave before the surprise combat is refused" % [tag], (
			rig.record(1).settles == [[token, UNFOUGHT]] and not rig.session.run.is_on_map()
	), rig.record(1).describe())
	if not _fight(rig, tag):
		return false
	for seat: int in rig.seats():
		_send(rig, ItemPickCommand.new(seat, ItemPickCommand.SKIP))
	return _leave(rig, tag, "the surprise combat's results")


# The surprise combat: begun on the host, pushed, each seat's Start, every map won, the end.
func _fight(rig: Rig, tag: String) -> bool:
	var session: CampaignSession = rig.session
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	_near_level_up(session)
	var begun: Error = FAILED if request == null else CampaignService.begin_battle(request)
	rig.harness.step_until_idle()
	_push(rig)
	var battle: CombatEncounter = session.encounter
	var built: bool = begun == OK and battle != null
	for index: int in rig.clients():
		built = built and rig.mirror(index).session.encounter != null
	_check("%s the surprise combat's battle opens on every mirror" % [tag], (
			built and _difference(rig).is_empty()
	), _difference(rig))
	if not built:
		return false
	_check("%s every seat's Start on the surprise combat settles; mirrors follow" % [tag], (
			_start_every_map(rig, battle) and _difference(rig).is_empty()
	), _difference(rig))
	var battle_from: int = session.run.fact_log.size()
	for map: CombatSession in battle.get_sessions():
		_win(map)
	rig.harness.step_until_idle()
	var result: CampaignSession.BattleResult = CampaignService.end_battle()
	rig.harness.step_until_idle()
	_check("%s the battle's end closes every mirror's battle at the results" % [tag], (
			result != null and session.run.flow.stage == RunFlow.Stage.RESULTS
			and _difference(rig).is_empty()
	), _difference(rig))
	_check("%s the battle's end brings its facts to every client's victory sequence" % [tag], (
			_ended_facts_mirrored(rig, battle_from)
	), _facts_text(session.run.fact_log.slice(battle_from)))
	return result != null


# Floor 7: a client resolves the Unknown node, and opens its event when it became one.
func _play_unknown(rig: Rig, tag: String) -> bool:
	_vote_every_seat(rig)
	if not _is_at(rig, CampaignGraph.NodeType.UNKNOWN):
		_check("%s the team reaches the Unknown node" % [tag], false)
		return false
	_send(rig, ResolveUnknownCommand.new(1))
	var resolved: bool = not rig.session.run.flow.unknown.is_empty()
	if UnknownResolution.needs_event(rig.session.run):
		_send(rig, OpenEventCommand.new(1))
		resolved = rig.session.run.events.is_open_at(
				rig.session.run.floor_number, rig.session.run.node
		)
	_check("%s a client resolves the Unknown node (%s) on every mirror" % [
		tag, rig.session.run.flow.unknown,
	], resolved and _difference(rig).is_empty(), _difference(rig))
	return true


# A Key or Boss combat's opening: the battle is pushed to every mirror and every seat starts.
func _test_opening(client_count: int, type: CampaignGraph.NodeType) -> void:
	var tag: String = "coop campaign %d seats, %s opening:" % [
		client_count + 1, CampaignGraph.NodeType.find_key(type),
	]
	var rig: Rig = _start(client_count, false)
	if rig == null or not Fixture.enter(rig.session.run, type):
		_check("%s the run stands in the combat" % [tag], false)
		if rig != null:
			_stop(rig)
		return
	_start_mirrors(rig)
	var request: CampaignSession.BattleRequest = rig.session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	var begun: Error = FAILED if request == null else CampaignService.begin_battle(request)
	rig.harness.step_until_idle()
	_push(rig)
	var battle: CombatEncounter = rig.session.encounter
	var built: bool = begun == OK and battle != null
	for index: int in rig.clients():
		built = built and rig.mirror(index).session.encounter != null
	_check("%s the battle opens on every mirror" % [tag], (
			built and _difference(rig).is_empty()
	), _difference(rig))
	if built:
		_check("%s every seat's Start settles and every mirror follows" % [tag], (
				_start_every_map(rig, battle) and _difference(rig).is_empty()
				and rig.combat_failures.is_empty()
		), "%s; %s" % [_difference(rig), rig.combat_failures])
	_stop(rig)


# The capture's new parts, and a mirror's refusal of a capture missing either.
func _test_capture_parts() -> void:
	var rig: Rig = _start(1, true)
	if rig == null:
		_check("coop campaign capture: the rig starts", false)
		return
	_start_mirrors(rig)
	var client: NetRelayScript = rig.relay(1)
	var heard: Array[Dictionary] = []
	var on_heard: Callable = func(_facts: Array, run: Dictionary) -> void: heard.append(run)
	client.campaign_batch_received.connect(on_heard)
	_send(rig, ProposeSwapCommand.new(HOST_SEAT, _soldier(rig, HOST_SEAT), 1, _soldier(rig, 1)))
	client.campaign_batch_received.disconnect(on_heard)
	var host_proposals: Array = []
	for proposal: UnitSwap in rig.session.run.swap_proposals:
		host_proposals.append(proposal.capture())
	var captured: Dictionary = {} if heard.is_empty() else heard[0]
	# Typed, since a comparison of a Dictionary's Variant values is a Variant.
	var has_events: bool = captured.get(EVENTS_KEY, null) == rig.session.run.events.capture()
	var has_proposals: bool = captured.get(PROPOSALS_KEY, null) == host_proposals
	_check("coop campaign capture: it carries the events section and the open proposals", (
			heard.size() == 1 and host_proposals.size() == 1 and has_events and has_proposals
			and _proposals_mirrored(rig, 1)
	), str(captured.keys()))
	var mirror: ClientMirror = rig.mirror(1)
	var before: String = rig.text_of(mirror.session)
	var refused: bool = true
	for key: String in [EVENTS_KEY, PROPOSALS_KEY]:
		var lacking: Dictionary = captured.duplicate(true)
		lacking.erase(key)
		(lacking.get(PROPOSALS_KEY, []) as Array).clear()
		client.campaign_batch_received.emit([], lacking)
		refused = refused and mirror.is_syncing() and rig.text_of(mirror.session) == before
		rig.harness.step_until_idle()
	_check("coop campaign capture: a capture missing either is refused, and a resync repairs it", (
			refused and not mirror.is_syncing() and _difference(rig).is_empty()
	), _difference(rig))
	var parts: Dictionary = NetContract.format_parts()
	var version: int = parts.get("EventSaveSection.version", 0)
	_check("coop campaign capture: the fingerprint covers the events section's version", (
			version == EventSaveSection.VERSION
	))
	_stop(rig)


# A multiplayer run of client_count + 1 seats through SaveService, no starting offers, every seat
# rich, floors 1 to 7 made ROUTE's types (when shaped), GIFT_ITEMS items in seat 1's convoy, and a
# harness with a relay and a mirror, not yet started, per client. Null when any of it fails.
func _start(client_count: int, shaped: bool) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = []
	for seat: int in client_count + 1:
		steam_ids.append(FIRST_STEAM_ID + seat)
	var started: Error = SaveService.start_new_multiplayer_run(steam_ids)
	var session: CampaignSession = CampaignService.session
	if started != OK or session == null or session.run == null:
		SaveService.close_save_file()
		return null
	var rig: Rig = Rig.new()
	rig.session = session
	for seat: int in session.run.seat_numbers():
		var seat_run: SeatRun = session.run.seat_run(seat)
		seat_run.pending_offers.erase(StartingOffer.OFFER_KEY)
		seat_run.gold = RICH
	if shaped:
		_shape_route(session.run)
		var giver: SeatRun = session.run.seat_run(1)
		var kind: String = (giver.items.values()[0] as ItemInstance).definition_id
		for _gift: int in GIFT_ITEMS:
			rig.gifts.append(Fixture.add_to_convoy(giver, kind, session.ids))
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		_end_run()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for seat: int in client_count + 1:
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
		rig.records.append(Record.new())
		rig.mirrors.append(null)
	session.campaign_batch_resolved.connect(rig.on_host_batch)
	for index: int in rig.clients():
		rig.add_mirror(index)
	return rig


# Every node of floors 1 to ROUTE.size() made its floor's type.
func _shape_route(run: CampaignRunState) -> void:
	for index: int in ROUTE.size():
		for node: int in run.graph.nodes_on_floor(index + 1):
			run.graph.set_node_type(node, ROUTE[index])


func _start_mirrors(rig: Rig) -> void:
	for index: int in rig.clients():
		rig.mirror(index).start()
	rig.harness.step_until_idle()


func _stop(rig: Rig) -> void:
	if rig.session.campaign_batch_resolved.is_connected(rig.on_host_batch):
		rig.session.campaign_batch_resolved.disconnect(rig.on_host_batch)
	for mirror: ClientMirror in rig.mirrors:
		if mirror != null:
			mirror.close()
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


# Sends command as its seat does: the host seat's filled by HostFill and resolved on the host, as
# its own screen's would be; a client's through its mirror. Then lets the network settle.
func _send(rig: Rig, command: CampaignCommand) -> void:
	if command == null:
		push_error("coop campaign cases: no command to send")
		return
	if command.seat == HOST_SEAT:
		CampaignService.submit_command(HostFill.complete(command, rig.session))
	else:
		rig.mirror(command.seat).submit_campaign(command)
	rig.harness.step_until_idle()


# The first of candidates the host would resolve now, once filled; null when none would.
func _first_valid(rig: Rig, candidates: Array[CampaignCommand]) -> CampaignCommand:
	for candidate: CampaignCommand in candidates:
		var filled: CampaignCommand = HostFill.complete(candidate, rig.session)
		if filled != null and filled.validate(rig.session.run).is_empty():
			return candidate
	return null


# Every seat votes for the next floor's first node; the last vote draws it.
func _vote_every_seat(rig: Rig) -> void:
	var node: int = rig.session.run.next_nodes()[0]
	for seat: int in rig.seats():
		_send(rig, RouteVoteCommand.new(seat, node))


# The host opens event_id, alone in its pool, with its own command at the Unknown node.
func _open_event(rig: Rig, event_id: String) -> bool:
	if not _is_at(rig, CampaignGraph.NodeType.UNKNOWN):
		return false
	var only: EventPool = EventPool.new([EventPool.load_default().event(event_id)])
	CampaignService.submit_command(EventNode.open(rig.session, only))
	rig.harness.step_until_idle()
	return rig.session.run.events.event_id == event_id and _difference(rig).is_empty()


# Seat's choice of option: with no picks, its new item to the convoy, or, when the convoy is full
# (gifts and loot can fill the host seat's on some seeds), its new item scrapped.
func _event_choice(rig: Rig, seat: int, option: int) -> CampaignCommand:
	var to_convoy: EventChoice = EventChoice.new()
	to_convoy.placements[0] = ItemPlacement.new()
	var scrapped: EventChoice = EventChoice.new()
	scrapped.placements[0] = ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	return _first_valid(rig, [
		EventOptionCommand.new(seat, option, null),
		EventOptionCommand.new(seat, option, to_convoy),
		EventOptionCommand.new(seat, option, scrapped),
	])


# Seat pours the goblet away; false, failing a check with the host's reason, when no choice of it
# would resolve.
func _pour_away(rig: Rig, tag: String, seat: int) -> bool:
	var choice: CampaignCommand = _event_choice(rig, seat, POUR_AWAY)
	if choice != null:
		_send(rig, choice)
		return true
	var plain: CampaignCommand = HostFill.complete(
			EventOptionCommand.new(seat, POUR_AWAY, null), rig.session
	)
	_check("%s seat %d has a choice at %s the host would take" % [tag, seat, OWN_EVENT], false, (
			"no fill" if plain == null else plain.validate(rig.session.run)
	))
	return false


# The last client sends Leave, which resolves and brings every mirror back to the map.
func _leave(rig: Rig, tag: String, place: String) -> bool:
	rig.clear()
	var leaver: int = rig.last_client()
	var token: int = rig.mirror(leaver).submit_campaign(LeaveNodeCommand.new(leaver))
	rig.harness.step_until_idle()
	var left: bool = rig.session.run.is_on_map() and rig.record(leaver).settles == [[token, ""]]
	_check("%s a client leaves %s on every mirror" % [tag, place], (
			left and _difference(rig).is_empty()
	), "%s; %s" % [rig.record(leaver).describe(), _difference(rig)])
	return left


# Seat's purchase of entry: an heirloom on no unit, an item on the first unit that can take it.
func _purchase(rig: Rig, seat: int, entry: int) -> ArmoryPurchaseCommand:
	var candidates: Array[CampaignCommand] = [ArmoryPurchaseCommand.new(seat, entry, "", false)]
	for unit: UnitInstance in rig.session.run.seat_run(seat).army:
		candidates.append(ArmoryPurchaseCommand.new(seat, entry, unit.instance_id, false))
	var found: CampaignCommand = _first_valid(rig, candidates)
	return found as ArmoryPurchaseCommand if found != null else candidates[0]


# An Armory entry both the host seat and seat 1 can buy now; -1 for none.
func _shared_entry(rig: Rig) -> int:
	var stock: ArmoryStock = ArmoryStock.pending(rig.session.run)
	for entry: int in (0 if stock == null else stock.entries.size()):
		var host_buy: ArmoryPurchaseCommand = _purchase(rig, HOST_SEAT, entry)
		var first: CampaignCommand = HostFill.complete(host_buy, rig.session)
		var second: CampaignCommand = HostFill.complete(_purchase(rig, 1, entry), rig.session)
		if (
				first.validate(rig.session.run).is_empty()
				and second.validate(rig.session.run).is_empty()
		):
			return entry
	return -1


# Every seat's Start on its own map; whether each client's settled with no refusal.
func _start_every_map(rig: Rig, battle: CombatEncounter) -> bool:
	rig.clear()
	CampaignService.submit_combat(
			StartCommand.new(HOST_SEAT), battle.session_of_seat(HOST_SEAT).session_id
	)
	var tokens: Dictionary[int, int] = {}
	for index: int in rig.clients():
		tokens[index] = rig.mirror(index).submit_combat(
				StartCommand.new(index), battle.session_of_seat(index).session_id
		)
	rig.harness.step_until_idle()
	var settled: bool = true
	for index: int in rig.clients():
		settled = settled and rig.record(index).settles == [[tokens[index], ""]]
	return settled


# Every army unit one XP short of a level, so the battle's shared XP levels it up.
func _near_level_up(session: CampaignSession) -> void:
	var per_level: int = CombatRewardRules.load_default().xp_per_level
	for seat: int in session.run.seat_numbers():
		for unit: UnitInstance in session.run.seat_run(seat).army:
			unit.xp = per_level - 1


# Whether every client's mirror holds what the host's run recorded from from on, by seq, kind,
# seat and actor, with each seat's COMBAT_ENDED and a level-up its victory sequence finds next.
func _ended_facts_mirrored(rig: Rig, from: int) -> bool:
	var ended: Array[CampaignFact] = rig.session.run.fact_log.slice(from)
	var host_kinds: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in ended:
		host_kinds.append(fact.kind)
	if not host_kinds.has(CampaignFact.Kind.COMBAT_ENDED):
		return false
	if not host_kinds.has(CampaignFact.Kind.LEVELED_UP):
		return false
	var wanted: String = _facts_text(ended)
	for index: int in rig.clients():
		var copy: CampaignSession = rig.mirror(index).session
		var tail: Array[CampaignFact] = []
		for fact: CampaignFact in copy.run.fact_log:
			if fact.seq > from:
				tail.append(fact)
		var level_up: CampaignFact = CampaignPlayback.next_pending(
				copy, CampaignFact.Kind.LEVELED_UP, index
		)
		if _facts_text(tail) != wanted or level_up == null or level_up.seat != index:
			return false
	return true


func _facts_text(facts: Array[CampaignFact]) -> String:
	var lines: PackedStringArray = []
	for fact: CampaignFact in facts:
		lines.append("%d:%s:%d:%s" % [
			fact.seq, CampaignFact.Kind.find_key(fact.kind), fact.seat, fact.actor_id,
		])
	return ", ".join(lines)


# The host relay's frame after a battle opened: its snapshot goes out.
func _push(rig: Rig) -> void:
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()


# Ends map as won outside any command, sent as its own batch.
func _win(map: CombatSession) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	map.engine.record(ended)
	map.flush("test win")


# The last unit of seat's army: never its commander.
func _soldier(rig: Rig, seat: int) -> String:
	var army: Array[UnitInstance] = rig.session.run.seat_run(seat).army
	return army[army.size() - 1].instance_id


func _is_at(rig: Rig, type: CampaignGraph.NodeType) -> bool:
	var run: CampaignRunState = rig.session.run
	return run.flow.stage == RunFlow.Stage.NODE and run.graph.type_of(run.node) == type


# Whether run's last route draw reached it: its log's last NODE_CHOSEN is for no seat.
func _drew_node(run: CampaignRunState) -> bool:
	for index: int in range(run.fact_log.size() - 1, -1, -1):
		var fact: CampaignFact = run.fact_log[index]
		if fact.kind == CampaignFact.Kind.NODE_CHOSEN:
			return fact.seat == CampaignFact.NO_SEAT and fact.amount == run.node
	return false


# Whether every client holds count open proposals, equal to the host's in order.
func _proposals_mirrored(rig: Rig, count: int) -> bool:
	var host: Array[UnitSwap] = rig.session.run.swap_proposals
	if host.size() != count:
		return false
	for index: int in rig.clients():
		var copy: Array[UnitSwap] = rig.mirror(index).session.run.swap_proposals
		if copy.size() != count:
			return false
		for at: int in count:
			if copy[at].capture() != host[at].capture():
				return false
	return true


# Whether no client but index heard a settle, a batch or a rejection since the last clear.
func _is_quiet_but(rig: Rig, index: int) -> bool:
	for other: int in rig.clients():
		var heard: Record = rig.record(other)
		if other != index and not (
				heard.settles.is_empty() and heard.batches.is_empty()
				and heard.rejections.is_empty()
		):
			return false
	return true


func _every_mirror_built(rig: Rig) -> bool:
	for index: int in rig.clients():
		var mirror: ClientMirror = rig.mirror(index)
		if mirror.session == null or not mirror.session.is_mirror or mirror.local_seat() != index:
			return false
	return true


# The first way a client's mirror differs from the host: its campaign text, its battle, a map or
# the encounter; empty when every mirror is equal.
func _difference(rig: Rig) -> String:
	var host: CampaignSession = rig.session
	for index: int in rig.clients():
		var copy: CampaignSession = rig.mirror(index).session
		if copy == null or copy.run == null:
			return "client %d has no run" % [index]
		if rig.text_of(copy) != rig.text_of(host):
			return "client %d's run differs" % [index]
		if (copy.encounter == null) != (host.encounter == null):
			return "client %d's battle is %s" % [
				index, "missing" if copy.encounter == null else "extra",
			]
		if host.encounter == null:
			continue
		if copy.encounter.state_hash() != host.encounter.state_hash():
			return "client %d's encounter differs" % [index]
		for map: CombatSession in host.encounter.get_sessions():
			if copy.encounter.get_session(map.session_id).state_hash() != map.state_hash():
				return "client %d's map %d differs" % [index, map.session_id]
	return ""


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# One case's peers and what they heard: the host's session, the harness, each branch's relay,
# mirror and record, the items seat 1 gives away, and the hash checks.
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var records: Array[Record] = []
	var gifts: PackedStringArray = []
	# The host's campaign hash after each batch, by the batch's arrival.
	var host_hashes: Dictionary[int, int] = {}
	var campaign_checks: int = 0
	var campaign_failures: PackedStringArray = []
	var combat_checks: int = 0
	var combat_failures: PackedStringArray = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	func record(index: int) -> Record:
		return records[index]

	# The client branches, which are also their seats.
	func clients() -> PackedInt32Array:
		var found: PackedInt32Array = []
		for index: int in range(1, harness.size()):
			found.append(index)
		return found

	func last_client() -> int:
		return harness.size() - 1

	func seats() -> PackedInt32Array:
		return session.run.seat_numbers()

	func clear() -> void:
		for each: Record in records:
			each.clear()

	# What a campaign hash covers: the run's sections, its events and its open proposals.
	func text_of(of: CampaignSession) -> String:
		var proposals: Array = []
		for proposal: UnitSwap in of.run.swap_proposals:
			proposals.append(proposal.capture())
		return JSON.stringify([RunStateCases.run_text(of.run), of.run.events.capture(), proposals])

	func on_host_batch(batch: CampaignBatch) -> void:
		host_hashes[batch.arrival] = text_of(session).hash()

	# A mirror for client branch index, not started; its record and the hash checks hear the
	# relay and the mirror's session after the mirror does.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		var made: ClientMirror = ClientMirror.new(client, session.rng.run_seed)
		mirrors[index] = made
		var heard: Record = records[index]
		client.command_settled.connect(heard.on_settled)
		client.combat_batch_received.connect(_check_map.bind(index))
		client.encounter_batch_received.connect(_check_encounter.bind(index))
		made.session_built.connect(_on_mirror_built.bind(index))

	func _on_mirror_built(built: CampaignSession, index: int) -> void:
		var heard: Record = records[index]
		built.campaign_batch_resolved.connect(heard.on_batch)
		built.campaign_batch_resolved.connect(_check_campaign.bind(index))
		built.command_rejected.connect(heard.on_rejected)

	func _check_campaign(batch: CampaignBatch, index: int) -> void:
		if not host_hashes.has(batch.arrival):
			campaign_failures.append("client %d heard #%d, unknown" % [index, batch.arrival])
			return
		campaign_checks += 1
		if text_of(mirror(index).session).hash() != host_hashes[batch.arrival]:
			campaign_failures.append("client %d #%d %s" % [index, batch.arrival, batch.label])

	func _check_map(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		combat_checks += 1
		if map.state_hash() != batch.state_hash:
			combat_failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])

	func _check_encounter(wire: Array, index: int) -> void:
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = _battle_of(index)
		if batch == null or battle == null or batch.state_hash == CombatSession.NO_HASH:
			return
		combat_checks += 1
		if battle.state_hash() != batch.state_hash:
			combat_failures.append("client %d encounter #%d" % [index, batch.last_seq()])

	func _battle_of(index: int) -> CombatEncounter:
		var copy: CampaignSession = mirror(index).session
		return null if copy == null else copy.encounter


# What one client heard since the last clear: its settles, its mirror's announced batches (arrival
# and rejection) and the rejections its mirror announced for it.
class Record:
	extends RefCounted

	var settles: Array = []
	var batches: Array = []
	var rejections: Array = []

	func clear() -> void:
		settles.clear()
		batches.clear()
		rejections.clear()

	func describe() -> String:
		return "settles %s, batches %s, rejections %s" % [settles, batches, rejections]

	func on_settled(token: int, reason: String) -> void:
		settles.append([token, reason])

	func on_batch(batch: CampaignBatch) -> void:
		batches.append([batch.arrival, batch.rejected_reason])

	func on_rejected(seat: int, _arrival: int, reason: String) -> void:
		rejections.append([seat, reason])
