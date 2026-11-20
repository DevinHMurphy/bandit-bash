# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_screen_model.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name EventScreenModel
extends RefCounted
## The words and choices the event screen shows, read from an [EventView] and the run: each
## option's rolled parts and named curse, the steps a chosen option asks for (a pick, the unit
## that leaves a full army, item placements, a rune to discard), every chooser's entries with why
## each is greyed out, and the outcome summary.
##
## Static and read-only: it reads only what it is handed and changes nothing. The summary is
## built from saved state alone (the option, its rolls and the team's votes), so the one shown
## after a quit and Continue is the one shown before it. Never instantiated.
##
## @tutorial(Events): docs/design/events.md

## A modified item's name (items.md, Modified items).
const INFUSED_FORMAT: String = "Infused %s"


## The lines [param shown] adds under its text on its card ([param is_done] false) or in the
## summary once taken (true): each block's rolled or named item, rune and heirloom by name, then
## its curse with its tier and effect. [param seat_run] tells a rune gained with every slot full.
static func option_lines(
		shown: EventView.OptionView,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		is_done: bool = false
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var verb: String = "Gained" if is_done else "Gain"
	for index: int in shown.option.outcomes.size():
		var outcome: EventOutcome = shown.option.outcomes[index]
		if outcome is ItemGrantOutcome:
			var item_id: String = granted_item(shown.option, index, shown.rolls)
			var item: ItemDefinition = catalog.item(item_id)
			lines.append("%s %s (%s)" % [
				verb, CombatResultsModel.item_name(item, item_id),
				CombatResultsModel.item_details(item).get_slice("\n", 0),
			])
		elif outcome is RuneOutcome:
			var rune_id: String = _granted_rune(outcome as RuneOutcome, index, shown.rolls)
			var rune_name: String = _carrier_name(catalog.rune(rune_id), rune_id)
			lines.append("%s the rune %s" % [verb, rune_name])
			if not is_done and seat_run != null and not has_free_rune_slot(seat_run):
				lines.append("Every rune slot is full: you discard one for it.")
		elif outcome is HeirloomOutcome:
			var heirloom_id: String = _granted_heirloom(
					outcome as HeirloomOutcome, index, shown.rolls
			)
			lines.append("%s the heirloom %s" % [
				verb, _described(catalog.heirloom(heirloom_id), heirloom_id),
			])
	if not shown.curse_id.is_empty():
		lines.append(curse_line(shown.curse_id, catalog, is_done))
	return lines


## The curse [param curse_id] as an option names it before it is chosen ([param is_done] false)
## or once taken: [code]Curse: Haunted (Minor curse). Phase Start: ...[/code].
static func curse_line(
		curse_id: String, catalog: EffectCatalog.Index, is_done: bool = false
) -> String:
	var curse: CurseDefinition = catalog.curse(curse_id)
	var tier: String = "" if curse == null or curse.tier.is_empty() else curse.tier.capitalize()
	var effect: String = "" if curse == null else " ".join(curse.describe())
	var line: String = "%s: %s (%s curse). %s" % [
		"Cursed" if is_done else "Curse", _carrier_name(curse, curse_id), tier, effect,
	]
	return line.strip_edges()


## The content id of the item the block at [param index] of [param option] gives: its named
## item, or the one [param rolls] drew. Empty for a block that gives no item.
static func granted_item(option: EventOption, index: int, rolls: EventRolls) -> String:
	var grant: ItemGrantOutcome = option.outcomes[index] as ItemGrantOutcome
	if grant == null:
		return ""
	return grant.item_id if grant.random == ItemGrantOutcome.RandomItem.NONE else rolls.pick(index)


## The indices of [param option]'s item-granting blocks, in order: each asks where its item goes.
static func item_blocks(option: EventOption) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for index: int in option.outcomes.size():
		if option.outcomes[index] is ItemGrantOutcome:
			found.append(index)
	return found


## Whether choosing [param option] asks [param seat_run] which rune to discard: it gives a rune
## and every slot is full.
static func needs_rune_discard(option: EventOption, seat_run: SeatRun) -> bool:
	if has_free_rune_slot(seat_run):
		return false
	for outcome: EventOutcome in option.outcomes:
		if outcome is RuneOutcome:
			return true
	return false


## Whether [param seat_run] has an empty rune slot.
static func has_free_rune_slot(seat_run: SeatRun) -> bool:
	for slot: SeatRun.RuneSlot in seat_run.rune_slots:
		if slot.is_empty():
			return true
	return false


## The question a chooser of [param kind] asks for the option [param option_title].
static func chooser_question(kind: EventOutcome.Chooser, option_title: String) -> String:
	match kind:
		EventOutcome.Chooser.UNIT:
			return "%s: which unit?" % [option_title]
		EventOutcome.Chooser.WEAPON:
			return "%s: which weapon?" % [option_title]
		EventOutcome.Chooser.FALLEN_UNIT:
			return "%s: which fallen unit returns?" % [option_title]
	return option_title


## The entries the chooser of option [param option_index] of [param event] lists for
## [param seat] of [param run], each greyed out with its own block's reason: the living units,
## the fallen ones, or the weapons on living units then in the convoy. A full army greys no fallen
## unit: [method leaving_entries] asks which unit makes room next. Empty for no chooser.
static func chooser_entries(
		run: CampaignRunState,
		seat: int,
		event: EventDefinition,
		option_index: int,
		catalog: EffectCatalog.Index
) -> Array[Entry]:
	var entries: Array[Entry] = []
	var seat_run: SeatRun = run.seat_run(seat)
	var option: EventOption = event.options[option_index]
	match option.chooser():
		EventOutcome.Chooser.UNIT, EventOutcome.Chooser.FALLEN_UNIT:
			var is_fallen: bool = option.chooser() == EventOutcome.Chooser.FALLEN_UNIT
			var units: Array[UnitInstance] = seat_run.fallen if is_fallen else seat_run.army
			for unit: UnitInstance in units:
				var choice: EventChoice = EventChoice.new(unit.instance_id)
				var shown: String = unit_text(unit, catalog, is_fallen)
				var reason: String = _pick_reason(run, seat, event, option_index, catalog, choice)
				entries.append(Entry.new(unit.instance_id, shown, reason.replace(
						unit.instance_id, title_of(unit, catalog)
				)))
		EventOutcome.Chooser.WEAPON:
			for item_id: String in _weapon_ids(seat_run, catalog):
				var item: ItemInstance = seat_run.items[item_id]
				var choice: EventChoice = EventChoice.new("", item_id)
				var item_name: String = held_item_name(item, catalog)
				var reason: String = _pick_reason(run, seat, event, option_index, catalog, choice)
				entries.append(Entry.new(
						item_id, "%s, %s" % [item_name, _holder_text(seat_run, item_id, catalog)],
						reason.replace(item_id, item_name)
				))
	return entries


## Whether choosing [param option] asks [param seat_run] which unit leaves the army: a block
## brings a unit in (a recruit, a revived unit) and the army is full
## ([method RunOperations.max_army_size], read with [param catalog]).
static func needs_leaving_unit(
		option: EventOption, seat_run: SeatRun, catalog: EffectCatalog.Index
) -> bool:
	if seat_run.army.size() < RunOperations.max_army_size(seat_run, catalog):
		return false
	for outcome: EventOutcome in option.outcomes:
		if outcome is RecruitOutcome or outcome is ReviveOutcome:
			return true
	return false


## The question the leaving step asks for the option [param option_title], with
## [param seat_run]'s army size: the leaving unit's items go to the convoy
## ([method RunOperations.dismiss]).
static func leaving_question(
		option_title: String, seat_run: SeatRun, catalog: EffectCatalog.Index
) -> String:
	return "%s: the army is full (%d of %d). Which unit leaves? Its items go to the convoy." % [
		option_title, seat_run.army.size(), RunOperations.max_army_size(seat_run, catalog),
	]


## The living units of [param seat] of [param run] that the leaving step lists, in roster order,
## each with its level and HP ([method leaving_text]); one that can't leave (the commander, one
## whose items the convoy can't take) is greyed out with [method RunOperations.dismiss_problem].
static func leaving_entries(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index
) -> Array[Entry]:
	var entries: Array[Entry] = []
	var seat_run: SeatRun = run.seat_run(seat)
	for unit: UnitInstance in seat_run.army:
		var reason: String = RunOperations.dismiss_problem(run, seat, unit.instance_id, catalog)
		entries.append(Entry.new(unit.instance_id, leaving_text(unit, catalog), reason.replace(
				unit.instance_id, title_of(unit, catalog)
		)))
	return entries


## [param unit] as the leaving step lists it: [code]Steady (+1) Archer, level 3, HP 14 / 18[/code].
static func leaving_text(unit: UnitInstance, catalog: EffectCatalog.Index) -> String:
	var unit_max: int = EventOutcome.max_hp(unit, catalog)
	return "%s, level %d, HP %d / %d" % [
		title_of(unit, catalog), unit.level, EventOutcome.current_hp(unit, unit_max), unit_max,
	]


## [param seat_run]'s rune slots as a chooser lists them to discard one, by slot index.
static func rune_entries(seat_run: SeatRun, catalog: EffectCatalog.Index) -> Array[Entry]:
	var entries: Array[Entry] = []
	for index: int in seat_run.rune_slots.size():
		var slot: SeatRun.RuneSlot = seat_run.rune_slots[index]
		var rune_name: String = _carrier_name(catalog.rune(slot.definition_id), slot.definition_id)
		entries.append(Entry.new(str(index), "Discard %s" % [rune_name], ""))
	return entries


## The summary of [param view]'s chosen option for its seat: its text, what it gave by name (its
## curse with tier and effect), the team's draw, and a surprise combat. Empty with none chosen.
static func summary_lines(
		view: EventView, seat_run: SeatRun, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var lines: PackedStringArray = []
	if not view.is_open() or view.chosen == EventRunState.NO_OPTION:
		return lines
	var shown: EventView.OptionView = view.options[view.chosen]
	if not shown.option.text.is_empty():
		lines.append(shown.option.text)
	lines.append_array(option_lines(shown, seat_run, catalog, true))
	if view.is_team_vote:
		lines.append("The team drew it with %d of %d votes." % [
			shown.vote_count, view.votes.size(),
		])
	if view.is_combat_pending:
		lines.append("A surprise combat begins: a Standard combat, with its full rewards.")
	elif not view.is_finished:
		lines.append("Waiting for the rest of the team to choose.")
	return lines


## [param item]'s name as the screen shows it: "Infused <name>" once modified (items.md).
static func held_item_name(item: ItemInstance, catalog: EffectCatalog.Index) -> String:
	var shown_name: String = CombatResultsModel.item_name(
			catalog.item(item.definition_id), item.instance_id
	)
	return INFUSED_FORMAT % [shown_name] if item.is_modified() else shown_name


## [param unit]'s name as a chooser lists it, with its HP: [code]Steady (+1) Archer, HP 14 / 18
## [/code]; a fallen one ([param is_fallen]) shows its max HP alone.
static func unit_text(
		unit: UnitInstance, catalog: EffectCatalog.Index, is_fallen: bool = false
) -> String:
	var unit_max: int = EventOutcome.max_hp(unit, catalog)
	if is_fallen:
		return "%s, fallen (max HP %d)" % [title_of(unit, catalog), unit_max]
	return "%s, HP %d / %d" % [
		title_of(unit, catalog), EventOutcome.current_hp(unit, unit_max), unit_max,
	]


## [param unit]'s name: its prefix, type and upgrade ([method RecruitOfferCard.title_of]).
static func title_of(unit: UnitInstance, catalog: EffectCatalog.Index) -> String:
	return RecruitOfferCard.title_of(unit, catalog)


# Why choice can't be picked for the option: the first refusal among the option's blocks that ask
# for a pick, nothing else. A full army isn't one (the revive validates its join last): the
# leaving step names the unit that makes room. Changes nothing. The stream is never drawn from
# (validation draws nothing); the prefix re-roll only checks that one is there.
static func _pick_reason(
		run: CampaignRunState,
		seat: int,
		event: EventDefinition,
		option_index: int,
		catalog: EffectCatalog.Index,
		choice: EventChoice
) -> String:
	var ctx: EventContext = EventContext.of(
			run, seat, event, option_index, catalog, null, RngStream.new(0), choice
	)
	var full_army: String = EventOutcome.join_problem(ctx)
	var option: EventOption = event.options[option_index]
	for index: int in option.outcomes.size():
		var outcome: EventOutcome = option.outcomes[index]
		if outcome != null and outcome.chooser() != EventOutcome.Chooser.NONE:
			var problem: String = outcome.validate(ctx, index)
			if not problem.is_empty() and problem != full_army:
				return problem
	return ""


# Ids of seat_run's weapons and staves: on living units in roster order, then in the convoy.
static func _weapon_ids(seat_run: SeatRun, catalog: EffectCatalog.Index) -> PackedStringArray:
	var held: PackedStringArray = []
	for unit: UnitInstance in seat_run.army:
		held.append_array(unit.item_ids())
	held.append_array(seat_run.convoy)
	var found: PackedStringArray = []
	for item_id: String in held:
		var item: ItemInstance = seat_run.items.get(item_id, null)
		if item != null and catalog.item(item.definition_id) is WeaponDefinition:
			found.append(item_id)
	return found


# Where item_id is: on which living unit, or in the convoy.
static func _holder_text(
		seat_run: SeatRun, item_id: String, catalog: EffectCatalog.Index
) -> String:
	for unit: UnitInstance in seat_run.army:
		if unit.item_ids().has(item_id):
			return "on %s" % [title_of(unit, catalog)]
	return "in the convoy"


static func _granted_rune(rune: RuneOutcome, index: int, rolls: EventRolls) -> String:
	return rolls.pick(index) if rune.is_random else rune.rune_id


static func _granted_heirloom(heirloom: HeirloomOutcome, index: int, rolls: EventRolls) -> String:
	return rolls.pick(index) if heirloom.is_tier_draw() else heirloom.heirloom_id


# A carrier's name, then its effects' text: "Gilded Purse: +10% gold from combats".
static func _described(carrier: EffectCarrierDefinition, fallback: String) -> String:
	var carrier_name: String = _carrier_name(carrier, fallback)
	if carrier == null or carrier.describe().is_empty():
		return carrier_name
	return "%s: %s" % [carrier_name, " ".join(carrier.describe())]


static func _carrier_name(carrier: EffectCarrierDefinition, fallback: String) -> String:
	if carrier == null or carrier.display_name.is_empty():
		return fallback
	return carrier.display_name


## One thing a chooser lists: a unit, a weapon or a rune slot.
class Entry:
	extends RefCounted

	## What choosing it names: a unit's or item's instance id, or a rune slot's index.
	var id: String = ""
	## Its line on the chooser.
	var text: String = ""
	## Why it can't be chosen; empty when it can.
	var reason: String = ""

	func _init(entry_id: String = "", entry_text: String = "", refusal: String = "") -> void:
		id = entry_id
		text = entry_text
		reason = refusal

	## Whether it can be chosen.
	func is_available() -> bool:
		return reason.is_empty()
