# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     requirement_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Requirement and definition cases for tests/events/run_all.gd: each requirement passing and
## failing with its reason (gold, a unit type, the commander, an item, a fallen unit, room under
## the army-size ceiling); a unit type found past the roster's first unit (one check over the
## whole army); the first unmet requirement reported; an unmet option refused by the resolver,
## changing nothing; an event's data problems (option count, mixed picks, an individual combat,
## an unknown curse tier); and the revive shrine's eligibility. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("requirements: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_gold_and_units()
	_test_items_and_fallen()
	_test_army_room()
	_test_resolver_refuses()
	_test_definition_problems()


func _test_gold_and_units() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var needs: EventRequirements = EventRequirements.new()
	_check("requirements: none needed is met", needs.unmet_reason(seat_run, _fx.catalog).is_empty())
	needs.gold = 40
	_check("requirements: 40 gold with 100 is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	))
	needs.gold = 150
	_check("requirements: 150 gold with 100 fails, saying so", (
			needs.unmet_reason(seat_run, _fx.catalog) == "needs 150 gold"
	), needs.unmet_reason(seat_run, _fx.catalog))

	needs = EventRequirements.new()
	var last_type: String = seat_run.army[-1].unit_type_id
	needs.unit_type_id = last_type
	_check("requirements: a unit type held only by the roster's last unit is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	), last_type)
	needs.unit_type_id = _missing_unit_type(seat_run)
	var unit_type: UnitTypeDefinition = _fx.catalog.unit_type(needs.unit_type_id)
	_check("requirements: a unit type the army lacks fails, naming it", (
			needs.unmet_reason(seat_run, _fx.catalog) == "needs a %s in the army" % [
				unit_type.display_name,
			]
	), needs.unmet_reason(seat_run, _fx.catalog))

	needs = EventRequirements.new()
	needs.needs_commander = true
	_check("requirements: the commander, alive in the army, is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	))
	var commander: UnitInstance = seat_run.unit(seat_run.commander_id)
	seat_run.army.erase(commander)
	_check("requirements: without the commander in the army it fails", (
			needs.unmet_reason(seat_run, _fx.catalog) == "needs the commander"
	), needs.unmet_reason(seat_run, _fx.catalog))
	seat_run.army.push_front(commander)

	needs = EventRequirements.new()
	needs.gold = 150
	needs.needs_commander = true
	needs.needs_fallen_unit = true
	_check("requirements: the first unmet requirement is the reason", (
			needs.unmet_reason(seat_run, _fx.catalog) == "needs 150 gold"
	))


func _test_items_and_fallen() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var holder: UnitInstance = seat_run.army[-1]
	var held: ItemInstance = seat_run.items[holder.weapon_id]
	var needs: EventRequirements = EventRequirements.new()
	needs.item_id = held.definition_id
	_check("requirements: an item a living unit holds is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	), held.definition_id)
	_fx.fell(seat_run, holder)
	var item: ItemDefinition = _fx.catalog.item(held.definition_id)
	_check("requirements: an item only a fallen unit holds fails, naming it", (
			needs.unmet_reason(seat_run, _fx.catalog) == "needs a %s" % [item.display_name]
	), needs.unmet_reason(seat_run, _fx.catalog))
	_fx.add_to_convoy(made, held.definition_id)
	_check("requirements: the same item in the convoy is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	))

	var fresh: SeatRun = _fx.session().run.seat_run(0)
	needs = EventRequirements.new()
	needs.needs_fallen_unit = true
	_check("requirements: a fallen unit, with none fallen, fails", (
			needs.unmet_reason(fresh, _fx.catalog) == "needs a fallen unit"
	))
	_check("requirements: a fallen unit, with one fallen, is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	))


func _test_army_room() -> void:
	var seat_run: SeatRun = _fx.session().run.seat_run(0)
	var needs: EventRequirements = EventRequirements.new()
	needs.needs_army_room = true
	_check("requirements: max army size 4, below the ceiling of 8, is met", (
			needs.unmet_reason(seat_run, _fx.catalog).is_empty()
	))
	seat_run.faction_id = Fixture.FULL_FACTION
	_check("requirements: max army size at the ceiling fails", (
			needs.unmet_reason(seat_run, _fx.catalog).contains("largest")
	), needs.unmet_reason(seat_run, _fx.catalog))


func _test_resolver_refuses() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var needs: EventRequirements = EventRequirements.new()
	needs.gold = 150
	var gold: GoldOutcome = GoldOutcome.new()
	gold.amount = 40
	var ctx: EventContext = _fx.context(made, _fx.event_of([gold], needs))
	var log_size: int = made.run.fact_log.size()
	var result: EventResult = EventResolver.resolve(ctx)
	_check("requirements: an unmet option is refused with its reason, changing nothing", (
			result.is_rejected() and result.rejected_reason == "needs 150 gold"
			and seat_run.gold == 100 and made.run.fact_log.size() == log_size
			and EventResolver.unmet_reason(ctx) == "needs 150 gold"
	), result.rejected_reason)


func _test_definition_problems() -> void:
	var sound: EventDefinition = _fx.event_of([GoldOutcome.new()])
	_check("definition: two options, one block each, is sound", sound.problems().is_empty(), (
			str(sound.problems())
	))
	var lone: EventDefinition = _fx.event_of([])
	lone.options.resize(1)
	var crowded: EventDefinition = _fx.event_of([])
	for extra: int in 2:
		crowded.options.append(EventOption.new())
	_check("definition: one option, or four, is a problem", (
			not lone.problems().is_empty() and not crowded.problems().is_empty()
	))
	var mixed: EventDefinition = _fx.event_of([
		PrefixRerollOutcome.new(), ItemModificationOutcome.new(),
	])
	_check("definition: blocks asking for a unit and a weapon in one option are a problem", (
			mixed.problems().size() == 1
	), str(mixed.problems()))
	var fight: EventDefinition = _fx.event_of([SurpriseCombatOutcome.new()])
	_check("definition: a combat option in an individual event is a problem", (
			fight.problems().size() == 1
	))
	fight.is_team_choice = true
	_check("definition: in a team choice it is sound", fight.problems().is_empty())
	var cursed: EventDefinition = _fx.event_of([], null, "", "dire")
	_check("definition: an unknown curse tier is a problem", cursed.problems().size() == 1)

	var shrine: EventDefinition = _fx.event_of([ReviveOutcome.new()])
	shrine.eligibility = EventDefinition.Eligibility.FALLEN_UNIT
	var seat_run: SeatRun = _fx.session().run.seat_run(0)
	var no_fallen: bool = shrine.is_eligible(seat_run)
	_fx.fell(seat_run, seat_run.army[-1])
	_check("definition: the shrine is eligible only once a unit has fallen", (
			not no_fallen and shrine.is_eligible(seat_run) and sound.is_eligible(seat_run)
	))
	_check("definition: the shrine's option asks for a fallen unit", (
			shrine.options[0].chooser() == EventOutcome.Chooser.FALLEN_UNIT
	))


func _missing_unit_type(seat_run: SeatRun) -> String:
	for resource: Resource in _fx.catalog.all_of(EffectCatalog.Kind.UNIT_TYPE):
		var unit_type: UnitTypeDefinition = resource as UnitTypeDefinition
		if unit_type != null and _fx.unit_of_type(seat_run, unit_type.id) == null:
			return unit_type.id
	return ""


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
