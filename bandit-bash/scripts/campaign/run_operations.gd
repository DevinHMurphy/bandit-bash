# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_operations.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name RunOperations
extends RefCounted
## The changes campaign rules make to a seat's part of a run, shared by everything that makes
## them: the starting heirloom offer, Treasure, the Camp, the Guildhall and event outcomes.
## Recruit a unit, dismiss or replace one, upgrade one, grant gold, an heirloom or an item, grow
## the army's max size, scrap a convoy item, and read the seat's campaign values outside battle:
## its max army size (the convoy's size follows), scrap rate and healing received.
##
## Each change has a [code]*_problem[/code] check, empty when it may be made, which changes
## nothing; call it first. The change itself records a [CampaignFact] for every state change, on
## the run's log. Pure and static: no nodes, no autoloads, no randomness (offers are rolled before,
## from the caller's stream).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Unit roster, Recruiting): docs/design/unit-roster.md


## [param seat_run]'s max army size: its faction's, plus [constant CampaignValue.Key.MAX_ARMY_SIZE]
## from its heirlooms and curses (Abundance, Muster Roll) and its saved value changes (the Company
## Charter), never above the rule's ceiling of 8. Read on a throwaway engine: no battle is on.[br]
## [param also_held]: heirloom ids counted as if held too, such as an offered one. [b]Units:[/b]
## units, the commander included. 0 for a faction not in [param catalog].
static func max_army_size(
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		also_held: PackedStringArray = PackedStringArray()
) -> int:
	var faction: FactionDefinition = catalog.faction(seat_run.faction_id)
	if faction == null:
		return 0
	var engine: EffectEngine = _seat_engine(seat_run, catalog, also_held)
	var subject: String = InstanceIdAllocator.seat_subject_id(seat_run.seat)
	engine.set_base(
			subject, CampaignValue.Key.MAX_ARMY_SIZE, float(faction.max_army_size),
			faction.display_name
	)
	return engine.stats(subject).get_int(CampaignValue.Key.MAX_ARMY_SIZE)


## [param seat_run]'s campaign value [param key] ([enum CampaignValue.Key]): its default base plus
## its heirlooms' and curses' modifiers and its value changes, read on a throwaway engine as
## [method max_army_size] reads, since no battle is on. Exact, unrounded.
static func campaign_value(seat_run: SeatRun, catalog: EffectCatalog.Index, key: int) -> float:
	var engine: EffectEngine = _seat_engine(seat_run, catalog, PackedStringArray())
	return engine.stats(InstanceIdAllocator.seat_subject_id(seat_run.seat)).get_value(key)


## The share of an item's value scrapping pays [param seat_run]
## ([constant CampaignValue.Key.SCRAP_PERCENT]: 20 plus Scrapper's Tongs); the default rate for
## no seat. [b]Units:[/b] percent.
static func scrap_percent(seat_run: SeatRun, catalog: EffectCatalog.Index) -> float:
	if seat_run == null or catalog == null:
		return Prices.default_scrap_percent()
	return campaign_value(seat_run, catalog, CampaignValue.Key.SCRAP_PERCENT)


## The share of a heal [param unit] of [param seat_run] receives
## ([constant CampaignValue.Key.HEALING_RECEIVED_PERCENT]): 100, changed by its own items
## (Cleansed Goblet) and its seat's heirlooms and curses (Cursed Blood). Read on a throwaway engine
## with the unit loaded and placed, as battle reads it. [b]Units:[/b] percent; never below 0.
static func healing_received_percent(
		seat_run: SeatRun, unit: UnitInstance, catalog: EffectCatalog.Index
) -> float:
	var state: CombatState = CombatState.new()
	var engine: EffectEngine = EffectEngine.new(state, ForcedRolls.new(PackedInt32Array()))
	var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			catalog, unit, seat_run.items, CombatFact.CombatSide.PLAYER, seat_run.seat, scratch
	)
	if loaded.is_loaded():
		for weapon: CombatState.WeaponStats in loaded.weapons:
			state.add_weapon(weapon)
		# A tile only so it can be placed: the throwaway state has no map.
		loaded.state.tile = Vector2i.ZERO
		state.place_unit(engine, loaded.state)
		for instance: EffectInstance in loaded.effects:
			engine.register(instance)
	for heirloom_id: String in seat_run.heirloom_ids():
		for instance: EffectInstance in Loadout.heirloom_effects(
				catalog, heirloom_id, seat_run.seat, scratch
		):
			engine.register(instance)
	var subject: String = (
			unit.instance_id if loaded.is_loaded()
			else InstanceIdAllocator.seat_subject_id(seat_run.seat)
	)
	return maxf(
			engine.stats(subject).get_value(CampaignValue.Key.HEALING_RECEIVED_PERCENT), 0.0
	)


## Why [param joining] can't join seat [param seat]'s army now: no seat, an unusable recruit, an
## id the seat already holds, or a full army ([method max_army_size], as if it held
## [param also_held] too). Empty when it can.
static func recruit_problem(
		run: CampaignRunState,
		seat: int,
		joining: RecruitOffer,
		catalog: EffectCatalog.Index,
		also_held: PackedStringArray = PackedStringArray()
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var problem: String = _join_problem(seat_run, seat, joining)
	if not problem.is_empty():
		return problem
	var limit: int = max_army_size(seat_run, catalog, also_held)
	if seat_run.army.size() >= limit:
		return "the army is full (%d of %d)" % [seat_run.army.size(), limit]
	return ""


## Adds [param joining] to the end of seat [param seat]'s army with its items, once
## [method recruit_problem] passed: [constant CampaignFact.Kind.UNIT_RECRUITED] by
## [param source_id], naming [param replaced_id] when it takes a dismissed unit's place.
static func recruit(
		run: CampaignRunState,
		seat: int,
		joining: RecruitOffer,
		source_id: String,
		replaced_id: String = ""
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	seat_run.army.append(joining.unit)
	for item_id: String in joining.items:
		seat_run.items[item_id] = joining.items[item_id]
	var joined: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.UNIT_RECRUITED, seat, joining.unit.instance_id
	)
	joined.target_id = replaced_id
	joined.definition_id = source_id
	run.record(joined)


## Why seat [param seat]'s unit [param unit_id] can't leave the army for good now: it isn't a
## living unit there, it is the commander, or the convoy can't take its items. Empty when it can.
static func dismiss_problem(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	var unit: UnitInstance = _living(seat_run, unit_id)
	if unit == null:
		return "seat %d has no living unit %s" % [seat, unit_id]
	if unit_id == seat_run.commander_id:
		return "the commander never leaves the army"
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, catalog)
	var carried: int = unit.item_ids().size()
	if seat_run.convoy.size() + carried > capacity:
		return "the convoy can't take its %d items (%d of %d)" % [
			carried, seat_run.convoy.size(), capacity,
		]
	return ""


## Takes seat [param seat]'s unit [param unit_id] out of the army for good, once
## [method dismiss_problem] passed: each of its items to the convoy, Weapon, Equipment then
## Pouch ([constant CampaignFact.Kind.ITEM_EQUIPPED] each, no unit), then
## [constant CampaignFact.Kind.UNIT_DISMISSED] by [param source_id], naming [param replaced_by].
static func dismiss(
		run: CampaignRunState, seat: int, unit_id: String, source_id: String,
		replaced_by: String = ""
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var unit: UnitInstance = _living(seat_run, unit_id)
	for item_id: String in unit.item_ids():
		var item: ItemInstance = seat_run.items[item_id]
		_clear_slot(unit, item_id)
		seat_run.convoy.append(item_id)
		var moved: CampaignFact = CampaignFact.new(CampaignFact.Kind.ITEM_EQUIPPED, seat, item_id)
		moved.definition_id = item.definition_id
		run.record(moved)
	seat_run.army.erase(unit)
	var left: CampaignFact = CampaignFact.new(CampaignFact.Kind.UNIT_DISMISSED, seat, unit_id)
	left.target_id = replaced_by
	left.definition_id = source_id
	run.record(left)


## Why [param joining] can't take the place of seat [param seat]'s unit [param unit_id] now: the
## unit can't leave ([method dismiss_problem]) or the recruit can't join. The army may be full.
## Empty when it can.
static func replace_problem(
		run: CampaignRunState,
		seat: int,
		unit_id: String,
		joining: RecruitOffer,
		catalog: EffectCatalog.Index
) -> String:
	var problem: String = dismiss_problem(run, seat, unit_id, catalog)
	if not problem.is_empty():
		return problem
	return _join_problem(run.seat_run(seat), seat, joining)


## Recruiting past the max (game-vision.md, Army), once [method replace_problem] passed: seat
## [param seat]'s unit [param unit_id] is dismissed ([method dismiss]), its items to the convoy,
## and [param joining] joins in its place ([method recruit]), both by [param source_id].
static func replace(
		run: CampaignRunState, seat: int, unit_id: String, joining: RecruitOffer, source_id: String
) -> void:
	dismiss(run, seat, unit_id, source_id, joining.unit.instance_id)
	recruit(run, seat, joining, source_id, unit_id)


## Why seat [param seat]'s unit [param unit_id] can't be upgraded now: it isn't a living unit
## there, it is a commander (never upgraded), or it is upgraded already. Empty when it can.
static func upgrade_problem(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	var unit: UnitInstance = _living(seat_run, unit_id)
	if unit == null:
		return "seat %d has no living unit %s" % [seat, unit_id]
	var unit_type: UnitTypeDefinition = unit.definition(catalog)
	if unit_type == null:
		return "%s's unit type isn't in the catalog" % [unit_id]
	if unit_type.is_commander:
		return "a commander is never upgraded"
	if unit.is_upgraded:
		return "it is upgraded already"
	return ""


## Upgrades seat [param seat]'s unit [param unit_id] ("Archer+"), once [method upgrade_problem]
## passed: [constant CampaignFact.Kind.UNIT_UPGRADED] by [param source_id]. A max-HP gain raises
## a hurt unit's current HP by as much, as a level-up's does
## ([constant CampaignFact.Kind.HP_CHANGED]); a unit at full stays full.
static func upgrade(
		run: CampaignRunState,
		seat: int,
		unit_id: String,
		catalog: EffectCatalog.Index,
		source_id: String
) -> void:
	var unit: UnitInstance = _living(run.seat_run(seat), unit_id)
	var old_max: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	unit.is_upgraded = true
	var upgraded: CampaignFact = CampaignFact.new(CampaignFact.Kind.UNIT_UPGRADED, seat, unit_id)
	upgraded.definition_id = source_id
	run.record(upgraded)
	var gain: int = unit.stats(catalog).get_int(CombatValue.Key.HP) - old_max
	if unit.hp == UnitInstance.FULL_HP or gain <= 0:
		return
	unit.hp += gain
	var healed: CampaignFact = CampaignFact.new(CampaignFact.Kind.HP_CHANGED, seat, unit_id)
	healed.amount = gain
	healed.definition_id = source_id
	run.record(healed)


## Adds [param amount] gold to seat [param seat] (negative pays it), never below 0:
## [constant CampaignFact.Kind.GOLD_CHANGED] by the change made, by [param source_id]; nothing
## when nothing changes.
static func grant_gold(run: CampaignRunState, seat: int, amount: int, source_id: String) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var before: int = seat_run.gold
	seat_run.gold = maxi(before + amount, 0)
	if seat_run.gold == before:
		return
	var changed: CampaignFact = CampaignFact.new(CampaignFact.Kind.GOLD_CHANGED, seat)
	changed.amount = seat_run.gold - before
	changed.definition_id = source_id
	run.record(changed)


## Why seat [param seat] can't gain the heirloom or curse [param heirloom_id] now: no seat, or
## not in [param catalog]. Empty when it can; a copy already owned is a second copy.
static func heirloom_problem(
		run: CampaignRunState, seat: int, heirloom_id: String, catalog: EffectCatalog.Index
) -> String:
	if run.seat_run(seat) == null:
		return "seat %d isn't in the run" % [seat]
	if catalog.heirloom(heirloom_id) == null:
		return "heirloom \"%s\" isn't in the catalog" % [heirloom_id]
	return ""


## Adds a copy of the heirloom or curse [param heirloom_id] to seat [param seat], once
## [method heirloom_problem] passed: [constant CampaignFact.Kind.GAINED], then
## [constant CampaignFact.Kind.ARMY_SIZE_CHANGED] when it moved [method max_army_size].
static func grant_heirloom(
		run: CampaignRunState, seat: int, heirloom_id: String, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var size_before: int = max_army_size(seat_run, catalog)
	seat_run.add_heirloom(heirloom_id)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, seat)
	gained.definition_id = heirloom_id
	run.record(gained)
	var size_change: int = max_army_size(seat_run, catalog) - size_before
	if size_change == 0:
		return
	var resized: CampaignFact = CampaignFact.new(CampaignFact.Kind.ARMY_SIZE_CHANGED, seat)
	resized.amount = size_change
	resized.definition_id = heirloom_id
	run.record(resized)


## Why seat [param seat]'s max army size can't grow by [param amount] now: no seat, an amount
## below 1, or its max army size at the ceiling of 8 already. Empty when it can, even when only
## part of [param amount] fits.
static func army_size_problem(
		run: CampaignRunState, seat: int, amount: int, catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if amount < 1:
		return "max army size can't grow by %d" % [amount]
	var ceiling: int = _army_size_ceiling()
	# ASSUMPTION: at the ceiling the growth is refused (the option applies all or nothing), and
	# below it only the part that fits is added.
	if max_army_size(seat_run, catalog) >= ceiling:
		return "the army is already at its largest (%d)" % [ceiling]
	return ""


## Grows seat [param seat]'s max army size by [param amount], once [method army_size_problem]
## passed, never past the ceiling of 8: a saved value change ([member SeatRun.value_changes]) of
## what fits, sourced to [param source_id] and named [param label], and
## [constant CampaignFact.Kind.ARMY_SIZE_CHANGED] by that much. The convoy grows with it.
static func grow_army(
		run: CampaignRunState,
		seat: int,
		amount: int,
		catalog: EffectCatalog.Index,
		source_id: String,
		label: String
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var grown: int = mini(amount, _army_size_ceiling() - max_army_size(seat_run, catalog))
	seat_run.add_value_change(CampaignValue.Key.MAX_ARMY_SIZE, float(grown), source_id, label)
	var resized: CampaignFact = CampaignFact.new(CampaignFact.Kind.ARMY_SIZE_CHANGED, seat)
	resized.amount = grown
	resized.definition_id = source_id
	run.record(resized)


## Why the new item of [param definition] can't go to seat [param seat] by [param placement]
## now ([method ItemPlacement.validate]). Empty when it can.
static func item_problem(
		run: CampaignRunState,
		seat: int,
		definition: ItemDefinition,
		placement: ItemPlacement,
		catalog: EffectCatalog.Index
) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if placement == null:
		return "the item has nowhere to go"
	return placement.validate(seat_run, definition, catalog)


## Gives seat [param seat] the new [param item], placed by [param placement], once
## [method item_problem] passed; the placement records its facts ([method ItemPlacement.apply]).
static func grant_item(
		run: CampaignRunState,
		seat: int,
		item: ItemInstance,
		placement: ItemPlacement,
		catalog: EffectCatalog.Index
) -> void:
	placement.apply(run, seat, item, catalog)


## Why seat [param seat] can't scrap its item [param item_id] now: no seat, or the item isn't in
## its convoy (army management scraps convoy items; items.md, Scrapping). Empty when it can.
static func scrap_problem(run: CampaignRunState, seat: int, item_id: String) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if not seat_run.convoy.has(item_id):
		return "the convoy holds no %s" % [item_id]
	return ""


## Scraps seat [param seat]'s convoy item [param item_id], once [method scrap_problem] passed:
## it leaves the roster and pays [method ItemPlacement.held_scrap_value] at the seat's rate
## ([constant CampaignFact.Kind.ITEM_SCRAPPED]).
static func scrap(
		run: CampaignRunState, seat: int, item_id: String, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var item: ItemInstance = seat_run.items[item_id]
	seat_run.convoy.remove_at(seat_run.convoy.find(item_id))
	seat_run.items.erase(item_id)
	ItemPlacement.pay_scrap(run, seat, item, catalog)


# A throwaway engine holding seat_run's heirloom and curse effects (and also_held's) with fresh
# lanes, and its value changes on the seat, for a campaign value read outside battle.
static func _seat_engine(
		seat_run: SeatRun, catalog: EffectCatalog.Index, also_held: PackedStringArray
) -> EffectEngine:
	var engine: EffectEngine = EffectEngine.new(
			CombatState.new(), ForcedRolls.new(PackedInt32Array())
	)
	# NOTE: a fresh allocator, so the scratch effects' ids are minted outside the run's.
	var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
	for heirloom_id: String in seat_run.heirloom_ids() + also_held:
		for instance: EffectInstance in Loadout.heirloom_effects(
				catalog, heirloom_id, seat_run.seat, scratch
		):
			engine.register(instance)
	var subject: String = InstanceIdAllocator.seat_subject_id(seat_run.seat)
	for change: SeatRun.ValueChange in seat_run.value_changes:
		# NOTE: sourced as an heirloom, the seat-level carrier kind; only overrides read it.
		engine.add_delta(subject, Modifier.new(
				change.key, Modifier.Mode.ADD, change.amount, Modifier.SourceKind.HEIRLOOM,
				change.source_id, change.label
		))
	return engine


# The most units an army may ever hold: the rule's bound on MAX_ARMY_SIZE (game-vision.md, Army).
static func _army_size_ceiling() -> int:
	return roundi(CampaignValue.RULE_MAX[CampaignValue.Key.MAX_ARMY_SIZE])


# Why joining can't be added to seat_run (seat): no seat, no unit, or an id it already holds.
static func _join_problem(seat_run: SeatRun, seat: int, joining: RecruitOffer) -> String:
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if joining == null or joining.unit == null:
		return "there is no unit to recruit"
	if seat_run.unit(joining.unit.instance_id) != null:
		return "the seat already has a unit %s" % [joining.unit.instance_id]
	for item_id: String in joining.items:
		if seat_run.items.has(item_id):
			return "the seat already holds %s" % [item_id]
	return ""


# Empties whichever of unit's slots holds item_id.
static func _clear_slot(unit: UnitInstance, item_id: String) -> void:
	for slot: Loadout.Slot in [Loadout.Slot.WEAPON, Loadout.Slot.EQUIPMENT, Loadout.Slot.POUCH]:
		if ItemPlacement.item_in(unit, slot) == item_id:
			ItemPlacement.put_item(unit, slot, "")


static func _living(seat_run: SeatRun, unit_id: String) -> UnitInstance:
	if seat_run == null:
		return null
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == unit_id:
			return unit
	return null
