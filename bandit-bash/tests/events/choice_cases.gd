# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     choice_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Choosing in an open event, through the commands EventNode builds: an event opens only in an
## Unknown node; the chooser stage opens, closes and is refused for an option with nothing to
## pick; a fallen unit can't be chosen, except by the shrine; an option resolves once, after its
## EVENT_CHOSEN, with its item placed and its drawn curse given; a team choice applies to every
## seat and needs every seat to meet it; the view greys options with their reasons; and a surprise
## combat begins through the battle bridge on the Standard pool, then returns to the map.
## Touches no save files.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const NO_OPTION: int = EventRunState.NO_OPTION
const DRINK: int = 0
const ICE: int = 1
const WALK_AWAY: int = 2
const PRAYER: int = 0
const PAY: int = 0
const FIGHT: int = 1
const INTIMIDATE: int = 2
const POOR_GOLD: int = 10

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("choice: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_open_rules()
	_test_chooser()
	_test_choose_unit()
	_test_shrine()
	_test_item_and_curse()
	_test_team_choice()
	_test_surprise_combat()


func _test_open_rules() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.goblet()])
	made.run.graph.set_node_type(made.run.node, CampaignGraph.NodeType.STANDARD)
	var standard: CampaignBatch = _fx.open(made, events)
	_check("choice: no event opens outside an Unknown node", (
			standard.is_rejected() and standard.rejected_reason.contains("Unknown")
	), standard.rejected_reason)
	made.run.graph.set_node_type(made.run.node, CampaignGraph.NodeType.UNKNOWN)
	var closed: EventView = EventNode.view(made, 0, events, _fx.catalog)
	var none: CampaignBatch = _fx.choose(made, events, 0, WALK_AWAY)
	_check("choice: before an event opens there is nothing to show or choose", (
			not closed.is_open() and none.is_rejected()
			and none.rejected_reason.contains("no event is open")
	), none.rejected_reason)
	var opened: CampaignBatch = _fx.open(made, events)
	var view: EventView = EventNode.view(made, 0, events, _fx.catalog)
	_check("choice: an opened event shows its options, the tier curse named", (
			not opened.is_rejected() and view.is_open() and view.options.size() == 3
			and _fx.curses_of(Fixture.MINOR).has(view.options[ICE].curse_id)
			and not view.options[ICE].rolls.pick(0).is_empty()
			and view.choosing == NO_OPTION and view.chosen == NO_OPTION
	), opened.rejected_reason)
	var other: EventPool = _fx.pool([_fx.toll()])
	var missing: CampaignBatch = _fx.choose(made, other, 0, WALK_AWAY)
	_check("choice: an open event the pool lacks can't be chosen", (
			missing.is_rejected() and missing.rejected_reason.contains("isn't in the pool")
			and EventNode.view(made, 0, other, _fx.catalog).problem.contains(Fixture.GOBLET)
	), missing.rejected_reason)


func _test_chooser() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.goblet()])
	_fx.open(made, events)
	var nothing: CampaignBatch = _fx.chooser(made, events, 0, WALK_AWAY)
	_check("chooser: an option with nothing to pick opens no chooser", (
			nothing.is_rejected() and nothing.rejected_reason.contains("nothing to choose")
	), nothing.rejected_reason)
	var no_close: CampaignBatch = _fx.chooser(made, events, 0, NO_OPTION)
	_check("chooser: closing with none open is refused", no_close.is_rejected())
	var opened: CampaignBatch = _fx.chooser(made, events, 0, DRINK)
	_check("chooser: opening one records EVENT_CHOOSING with the option", (
			not opened.is_rejected() and made.run.events.seat_event(0).choosing == DRINK
			and opened.facts.size() == 1
			and opened.facts[0].kind == CampaignFact.Kind.EVENT_CHOOSING
			and opened.facts[0].amount == DRINK
			and opened.facts[0].definition_id == Fixture.GOBLET
	), opened.rejected_reason)
	var shut: CampaignBatch = _fx.chooser(made, events, 0, NO_OPTION)
	_check("chooser: closing it goes back to the options", (
			not shut.is_rejected() and made.run.events.seat_event(0).choosing == NO_OPTION
			and shut.facts[0].amount == NO_OPTION
	), shut.rejected_reason)
	var team: CampaignSession = _fx.unknown_session()
	var toll: EventPool = _fx.pool([_fx.toll()])
	_fx.open(team, toll)
	var staged: CampaignBatch = _fx.chooser(team, toll, 0, PAY)
	_check("chooser: a team choice has no chooser stage", (
			staged.is_rejected() and staged.rejected_reason.contains("team choice")
	), staged.rejected_reason)


func _test_choose_unit() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.goblet()])
	var seat_run: SeatRun = made.run.seat_run(0)
	var fallen: UnitInstance = _fx.soldier(seat_run)
	_fx.fell(seat_run, fallen)
	var living: UnitInstance = _fx.soldier(seat_run)
	_fx.open(made, events)
	_fx.chooser(made, events, 0, DRINK)
	var dead: CampaignBatch = _fx.choose(
			made, events, 0, DRINK, EventChoice.new(fallen.instance_id)
	)
	_check("choose: a fallen unit can't be chosen", (
			dead.is_rejected() and dead.rejected_reason.contains("living unit")
			and made.run.events.seat_event(0).choosing == DRINK
	), dead.rejected_reason)
	var mgt_before: int = living.stats(_fx.catalog).get_int(CombatValue.Key.MGT)
	var chosen: CampaignBatch = _fx.choose(
			made, events, 0, DRINK, EventChoice.new(living.instance_id)
	)
	var part: EventRunState.SeatEvent = made.run.events.seat_event(0)
	_check("choose: the chosen living unit takes the option; EVENT_CHOSEN comes first", (
			not chosen.is_rejected()
			and living.stats(_fx.catalog).get_int(CombatValue.Key.MGT) == mgt_before + 2
			and chosen.facts.size() > 1
			and chosen.facts[0].kind == CampaignFact.Kind.EVENT_CHOSEN
			and chosen.facts[0].amount == DRINK and chosen.facts[0].seat == 0
			and part.chosen == DRINK and part.choosing == NO_OPTION
			and made.run.events.is_finished()
	), chosen.rejected_reason)
	var twice: CampaignBatch = _fx.choose(made, events, 0, WALK_AWAY)
	_check("choose: a seat chooses once", (
			twice.is_rejected() and twice.rejected_reason.contains("already chose")
	), twice.rejected_reason)


func _test_shrine() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.shrine()])
	var seat_run: SeatRun = made.run.seat_run(0)
	var fallen: UnitInstance = _fx.soldier(seat_run)
	_fx.fell(seat_run, fallen)
	_fx.open(made, events)
	var staged: CampaignBatch = _fx.chooser(made, events, 0, PRAYER)
	var prayed: CampaignBatch = _fx.choose(
			made, events, 0, PRAYER, EventChoice.new(fallen.instance_id)
	)
	_check("shrine: the prayer's chooser takes a fallen unit, which returns", (
			not staged.is_rejected() and not prayed.is_rejected()
			and seat_run.army.has(fallen) and not seat_run.fallen.has(fallen)
			and _fx.kinds(prayed.facts).has(CampaignFact.Kind.UNIT_REVIVED)
	), "%s / %s" % [staged.rejected_reason, prayed.rejected_reason])


func _test_item_and_curse() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.goblet()])
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.open(made, events)
	var rolls: EventRolls = made.run.events.seat_event(0).rolls_of(ICE)
	var convoy_before: int = seat_run.convoy.size()
	var taken: CampaignBatch = _fx.choose(made, events, 0, ICE)
	var new_id: String = "" if seat_run.convoy.is_empty() else seat_run.convoy[-1]
	_check("choose: the rolled weapon goes to the convoy, the named curse with it", (
			not taken.is_rejected()
			and seat_run.convoy.size() == convoy_before + 1
			and seat_run.items[new_id].definition_id == rolls.pick(0)
			and seat_run.heirloom_ids().has(rolls.curse_id)
			and _fx.is_whole(seat_run)
	), taken.rejected_reason)


func _test_team_choice() -> void:
	var team: CampaignSession = _fx.unknown_session(2)
	var events: EventPool = _fx.pool([_fx.toll()])
	_fx.open(team, events)
	var poor: SeatRun = team.run.seat_run(1)
	poor.gold = POOR_GOLD
	var view: EventView = EventNode.view(team, 0, events, _fx.catalog)
	_check("team: an option a teammate can't meet is greyed out, naming the seat", (
			view.options[PAY].unmet_reason.begins_with("seat 1")
			and view.options[INTIMIDATE].is_available()
	), view.options[PAY].unmet_reason)
	var paid: CampaignBatch = _fx.choose(team, events, 0, PAY)
	_check("team: it can't be chosen, and nothing changes", (
			paid.is_rejected() and paid.rejected_reason.begins_with("seat 1")
			and team.run.seat_run(0).gold == Fixture.START_GOLD
			and team.run.events.seat_event(0).chosen == NO_OPTION
	), paid.rejected_reason)
	var looted: CampaignBatch = _fx.choose(team, events, 0, INTIMIDATE)
	var every: bool = not looted.is_rejected() and team.run.events.is_finished()
	for seat: int in [0, 1]:
		var seat_run: SeatRun = team.run.seat_run(seat)
		var curse: String = team.run.events.seat_event(seat).rolls_of(INTIMIDATE).curse_id
		every = every and seat_run.heirloom_ids().has(curse)
	_check("team: one choice applies to every seat, each with its own curse", (
			every
			and team.run.seat_run(0).gold == Fixture.START_GOLD + Fixture.LOOT_GOLD
			and poor.gold == POOR_GOLD + Fixture.LOOT_GOLD
			and _chosen_seats(looted) == [0, 1]
	), looted.rejected_reason)


func _test_surprise_combat() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool([_fx.toll()])
	var pools: CombatMapPools = CombatMapPools.load_default()
	_fx.open(made, events)
	var run: CampaignRunState = made.run
	var fight: CampaignBatch = _fx.choose(made, events, 0, FIGHT)
	_check("combat: choosing the fight marks a surprise combat pending", (
			not fight.is_rejected() and run.events.is_combat_pending
			and EventNode.view(made, 0, events, _fx.catalog).is_combat_pending
	), fight.rejected_reason)
	var request: CampaignSession.BattleRequest = run.battle_request(pools, _fx.catalog)
	var standard: CombatMapPool = pools.pool_for(
			CampaignGraph.NodeType.STANDARD, run.floor_number
	)
	var battle: CombatEncounter = null if request == null else made.begin_battle(request)
	_check("combat: it begins through the bridge on a Standard map of the node's floor", (
			request != null and battle != null
			and standard.map_ids().has(battle.setup.map.id)
			and request.floor_number == run.floor_number and request.node == run.node
	))
	if battle == null:
		made.close()
		return
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	battle.get_session(0).engine.record(ended)
	var result: CampaignSession.BattleResult = made.collect_battle()
	var next: CampaignRunState = run.apply_battle(
			result, made.ids, made.reward_rolls(result), _fx.rules, _fx.catalog
	)
	made.end_battle()
	made.run = next
	_check("combat: a win pays a Standard combat's rewards and keeps the event", (
			next != null and next.flow.stage == RunFlow.Stage.RESULTS
			and ItemPick.pending(next.seat_run(0)) != null
			and next.events.event_id == Fixture.TOLL
			and next.seat_run(0).gold > Fixture.START_GOLD
	))
	if next == null:
		made.close()
		return
	made.submit(ItemPickCommand.new(0, ItemPickCommand.SKIP))
	var left: CampaignBatch = made.submit(LeaveNodeCommand.new(0))
	_check("combat: after its results the run returns to the map", (
			not left.is_rejected() and next.is_on_map()
	), left.rejected_reason)
	made.close()


# The seats of the batch's EVENT_CHOSEN facts, in order.
func _chosen_seats(batch: CampaignBatch) -> Array[int]:
	var found: Array[int] = []
	for fact: CampaignFact in batch.facts:
		if fact.kind == CampaignFact.Kind.EVENT_CHOSEN:
			found.append(fact.seat)
	return found


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
