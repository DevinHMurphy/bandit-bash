# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_heirloom_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StartingHeirloomCommand
extends CampaignCommand
## The seat takes one heirloom of its [StartingOffer] with its sub-choice, all at once, or skips
## an offer whose every option is refused ([constant SKIP]).
##
## Valid once, while the seat's offer is open and the run is on the map. The option must not be
## refused ([method StartingOffer.option_problem]) and its sub-choice must fit its bonus: a
## recruit ([member recruit]) for Abundance, a recruit and the unit it replaces
## ([member unit_id]) for Mercenary Contract, a weapon ([member weapon]) and its
## [member placement] for Ancestral Weapon, the unit to upgrade for Veteran Company, nothing for
## the rest. Resolving gains the heirloom first ([method RunOperations.grant_heirloom]), so
## Abundance's room exists before its recruit joins, then applies the bonus through
## [RunOperations], each recording its facts.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## [member option] for skipping an offer whose every option is refused.
const SKIP: int = -1

## [member recruit] and [member weapon] when the bonus offers none.
const NO_CHOICE: int = -1

## The option taken, its index in [member StartingOffer.options]; [constant SKIP] to take none.
var option: int = SKIP

## The recruit taken, its index in [member StartingOffer.Option.recruits]; [constant NO_CHOICE]
## unless the bonus recruits.
var recruit: int = NO_CHOICE

## The weapon taken, its index in [member StartingOffer.Option.weapons]; [constant NO_CHOICE]
## unless the bonus offers weapons.
var weapon: int = NO_CHOICE

## The living unit upgraded, or replaced by the recruit. [b]Empty:[/b] the bonus names none.
var unit_id: String = ""

## Where the weapon taken goes. Must be null unless the bonus offers weapons.
var placement: ItemPlacement = null

## The content the offer and the seat come from. [b]Null:[/b] the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, option_index: int = SKIP) -> void:
	seat = sender
	option = option_index


func get_label() -> String:
	if option == SKIP:
		return "skip starting heirloom"
	var parts: PackedStringArray = ["take starting heirloom %d" % [option]]
	if recruit != NO_CHOICE:
		parts.append("recruit %d" % [recruit])
	if weapon != NO_CHOICE:
		parts.append("weapon %d (%s)" % [weapon, _placement_text()])
	if not unit_id.is_empty():
		parts.append("unit %s" % [unit_id])
	return ", ".join(parts)


func validate(run: CampaignRunState) -> String:
	if not run.is_on_map():
		return "the run isn't on the map"
	var seat_run: SeatRun = run.seat_run(seat)
	var offer: StartingOffer = StartingOffer.pending(seat_run)
	if offer == null:
		return "seat %d has no starting heirloom offer" % [seat]
	if offer.is_resolved:
		return "seat %d already took its starting heirloom" % [seat]
	var contents: EffectCatalog.Index = _contents()
	if option == SKIP:
		return _skip_problem(run, offer, contents)
	if option < 0 or option >= offer.options.size():
		return "the offer has no option %d" % [option]
	var offered: StartingOffer.Option = offer.options[option]
	var problem: String = StartingOffer.option_problem(run, seat, offered, contents)
	if not problem.is_empty():
		return problem
	return _choice_problem(run, offered, StartingOffer.definition_of(offered, contents), contents)


func resolve(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var offer: StartingOffer = StartingOffer.pending(seat_run)
	offer.is_resolved = true
	offer.taken = StartingOffer.NOT_TAKEN if option == SKIP else option
	offer.store(seat_run)
	if option == SKIP:
		# A skip records no fact: nothing is gained.
		return
	var contents: EffectCatalog.Index = _contents()
	var offered: StartingOffer.Option = offer.options[option]
	var definition: StartingHeirloomDefinition = StartingOffer.definition_of(offered, contents)
	var source: String = offered.heirloom_id
	RunOperations.grant_heirloom(run, seat, source, contents)
	match definition.bonus:
		StartingHeirloomDefinition.Bonus.GOLD:
			RunOperations.grant_gold(run, seat, definition.gold, source)
		StartingHeirloomDefinition.Bonus.HEIRLOOM:
			RunOperations.grant_heirloom(run, seat, offered.drawn_heirloom_id, contents)
		StartingHeirloomDefinition.Bonus.RECRUIT:
			RunOperations.recruit(run, seat, offered.recruits[recruit], source)
		StartingHeirloomDefinition.Bonus.REPLACE:
			RunOperations.replace(run, seat, unit_id, offered.recruits[recruit], source)
		StartingHeirloomDefinition.Bonus.UPGRADE:
			RunOperations.upgrade(run, seat, unit_id, contents, source)
		StartingHeirloomDefinition.Bonus.WEAPON:
			var taken: ItemPick.Offer = offered.weapons[weapon]
			RunOperations.grant_item(
					run, seat, ItemInstance.new(taken.instance_id, taken.definition_id), placement,
					contents
			)


# Why this command's sub-choice doesn't fit offered's bonus; empty when it does.
func _choice_problem(
		run: CampaignRunState,
		offered: StartingOffer.Option,
		definition: StartingHeirloomDefinition,
		contents: EffectCatalog.Index
) -> String:
	var wants_recruit: bool = (
			definition.bonus == StartingHeirloomDefinition.Bonus.RECRUIT
			or definition.bonus == StartingHeirloomDefinition.Bonus.REPLACE
	)
	var wants_weapon: bool = definition.bonus == StartingHeirloomDefinition.Bonus.WEAPON
	var wants_unit: bool = (
			definition.bonus == StartingHeirloomDefinition.Bonus.REPLACE
			or definition.bonus == StartingHeirloomDefinition.Bonus.UPGRADE
	)
	if not wants_recruit and recruit != NO_CHOICE:
		return "%s offers no recruit" % [definition.display_name]
	if not wants_weapon and (weapon != NO_CHOICE or placement != null):
		return "%s offers no weapon" % [definition.display_name]
	if not wants_unit and not unit_id.is_empty():
		return "%s names no unit" % [definition.display_name]
	if wants_recruit and (recruit < 0 or recruit >= offered.recruits.size()):
		return "choose one of the %d recruits" % [offered.recruits.size()]
	if wants_weapon and (weapon < 0 or weapon >= offered.weapons.size()):
		return "choose one of the %d weapons" % [offered.weapons.size()]
	if wants_unit and unit_id.is_empty():
		return "choose a unit"
	match definition.bonus:
		StartingHeirloomDefinition.Bonus.RECRUIT:
			return RunOperations.recruit_problem(
					run, seat, offered.recruits[recruit], contents,
					PackedStringArray([offered.heirloom_id])
			)
		StartingHeirloomDefinition.Bonus.REPLACE:
			return RunOperations.replace_problem(
					run, seat, unit_id, offered.recruits[recruit], contents
			)
		StartingHeirloomDefinition.Bonus.UPGRADE:
			return RunOperations.upgrade_problem(run, seat, unit_id, contents)
		StartingHeirloomDefinition.Bonus.WEAPON:
			var taken: ItemPick.Offer = offered.weapons[weapon]
			if run.seat_run(seat).items.has(taken.instance_id):
				return "the seat already holds %s" % [taken.instance_id]
			return RunOperations.item_problem(
					run, seat, contents.item(taken.definition_id), placement, contents
			)
	return ""


# A skip needs every option refused, so a takeable heirloom is never thrown away.
func _skip_problem(
		run: CampaignRunState, offer: StartingOffer, contents: EffectCatalog.Index
) -> String:
	if recruit != NO_CHOICE or weapon != NO_CHOICE or placement != null or not unit_id.is_empty():
		return "a skip chooses nothing"
	for offered: StartingOffer.Option in offer.options:
		if StartingOffer.option_problem(run, seat, offered, contents).is_empty():
			return "%s can still be taken, so the offer can't be skipped" % [offered.heirloom_id]
	return ""


func _placement_text() -> String:
	return "nowhere" if placement == null else placement.describe()


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
