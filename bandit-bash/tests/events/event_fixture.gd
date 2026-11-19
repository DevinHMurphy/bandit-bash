# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_fixture.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Shared setup for the event cases: the loaded catalog plus test-only content (weapon prefixes,
## a standalone effect, a faction at the army-size ceiling), a fresh solo Mercenary run, one-
## option events built from blocks, and contexts drawing from the seat's EVENT_OUTCOME stream.
## None of the test content is real content: CT12 authors the weapon prefix list.

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const RUN_SEED: int = 0x5EA7C0DE
const MERCENARY: String = "mercenary"
const EVENT_ID: String = "test_event"
const EVENT_TITLE: String = "Test Event"

## A sword-only prefix: +2 weight, +2 damage (game-vision.md's Heavy Sword shape, with damage in
## place of MGT, which a weapon prefix can't hold yet).
const HEAVY_SWORD: String = "test_heavy_sword"
## A bow-only prefix with the same deltas, for a weapon the starting army carries.
const HEAVY_BOW: String = "test_heavy_bow"
## A prefix for Heal staves only.
const HEAL_STAFF: String = "test_heal_staff"
## A standalone effect an item can be granted ("Hit dealt: heal 2" stands in).
const TEST_EFFECT: String = "test_infusion"
## A faction whose max army size is already the ceiling.
const FULL_FACTION: String = "test_full_faction"
const PREFIX_WEIGHT: int = 2
const PREFIX_DAMAGE: int = 2

var catalog: EffectCatalog.Index = null
var map_rules: CampaignMapRules = null
var rules: CombatRewardRules = null


func _init() -> void:
	map_rules = load(RULES_PATH) as CampaignMapRules
	rules = CombatRewardRules.load_default()
	catalog = _test_catalog(EffectCatalog.index())


## Whether the catalog, map rules and reward rules all loaded.
func is_ready() -> bool:
	return catalog != null and map_rules != null and rules != null


## A new solo Mercenary run, on the map before its first node.
func session() -> CampaignSession:
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			map_rules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			catalog,
			factions,
			made.ids
	)
	made.run = start.run
	return made


## An event whose first option holds [param outcomes], [param requirements] and the curse, and
## whose second does nothing.
func event_of(
		outcomes: Array[EventOutcome],
		requirements: EventRequirements = null,
		curse_id: String = "",
		curse_tier: String = ""
) -> EventDefinition:
	var event: EventDefinition = EventDefinition.new()
	event.id = EVENT_ID
	event.title = EVENT_TITLE
	var option: EventOption = EventOption.new()
	option.title = "Take It"
	option.outcomes = outcomes
	option.requirements = requirements
	option.curse_id = curse_id
	option.curse_tier = curse_tier
	var walk_away: EventOption = EventOption.new()
	walk_away.title = "Walk Away"
	event.options = [option, walk_away]
	return event


## A context for seat 0's first option of [param event] in [param made]'s run, its stream the
## seat's EVENT_OUTCOME stream at the run's node.
func context(
		made: CampaignSession, event: EventDefinition, choice: EventChoice = null
) -> EventContext:
	var ctx: EventContext = EventContext.new()
	ctx.run = made.run
	ctx.seat = 0
	ctx.event = event
	ctx.option_index = 0
	ctx.choice = choice if choice != null else EventChoice.new()
	ctx.catalog = catalog
	ctx.ids = made.ids
	ctx.stream = stream(made)
	return ctx


## Seat 0's EVENT_OUTCOME stream at [param made]'s floor and node.
func stream(made: CampaignSession) -> RngStream:
	return made.rng.stream(RngKey.new(
			RngKey.RngPurpose.EVENT_OUTCOME, made.run.floor_number, made.run.node, 0
	))


## The seat's living unit of [param unit_type_id]; null when it has none.
func unit_of_type(seat_run: SeatRun, unit_type_id: String) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.unit_type_id == unit_type_id:
			return unit
	return null


## A new item of [param definition_id] in the seat's convoy.
func add_to_convoy(made: CampaignSession, definition_id: String) -> ItemInstance:
	var seat_run: SeatRun = made.run.seat_run(0)
	var item: ItemInstance = ItemInstance.new(made.ids.next_item_id(definition_id), definition_id)
	seat_run.items[item.instance_id] = item
	seat_run.convoy.append(item.instance_id)
	return item


## Moves [param unit] to the fallen list at 0 HP, as a battle does.
func fell(seat_run: SeatRun, unit: UnitInstance) -> void:
	seat_run.army.erase(unit)
	seat_run.fallen.append(unit)
	unit.hp = 0


## The kinds of [param facts], in order.
func kinds(facts: Array[CampaignFact]) -> Array[CampaignFact.Kind]:
	var found: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in facts:
		found.append(fact.kind)
	return found


## Whether the roster's invariant holds: a restore of its capture accepts it.
func is_whole(seat_run: SeatRun) -> bool:
	return SeatRun.new(0).restore_roster(seat_run.capture_roster()) == OK


## The first catalog item of [param kind] with [param rarity]; null when there is none.
func first_of(kind: EffectCatalog.Kind, rarity: ItemDefinition.Rarity) -> ItemDefinition:
	for definition: Resource in catalog.all_of(kind):
		var item: ItemDefinition = definition as ItemDefinition
		if item != null and item.rarity == rarity:
			return item
	return null


# The loaded catalog with the test-only content added, as a new index: the loaded one is never
# changed.
func _test_catalog(loaded: EffectCatalog.Index) -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	for id: String in loaded.ids():
		index.add(loaded.path_of(id), loaded.definition(id))
	index.add("res://tests/events/%s.tres" % [HEAVY_SWORD], _prefix(
			HEAVY_SWORD, "Heavy", [ContentIds.WEAPON_SWORD], []
	))
	index.add("res://tests/events/%s.tres" % [HEAVY_BOW], _prefix(
			HEAVY_BOW, "Heavy", [ContentIds.WEAPON_BOW], []
	))
	index.add("res://tests/events/%s.tres" % [HEAL_STAFF], _prefix(
			HEAL_STAFF, "Soothing", [ContentIds.WEAPON_STAFF], [ContentIds.STAFF_HEAL]
	))
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = TEST_EFFECT
	index.add("res://tests/events/%s.tres" % [TEST_EFFECT], effect)
	var full: FactionDefinition = loaded.faction(MERCENARY).duplicate() as FactionDefinition
	full.id = FULL_FACTION
	full.max_army_size = EventRequirements.ARMY_SIZE_CEILING
	index.add("res://tests/events/%s.tres" % [FULL_FACTION], full)
	index.finish()
	return index


func _prefix(
		id: String, label: String, weapon_types: PackedStringArray, staff_kinds: PackedStringArray
) -> WeaponPrefixDefinition:
	var prefix: WeaponPrefixDefinition = WeaponPrefixDefinition.new()
	prefix.id = id
	prefix.display_name = label
	prefix.weapon_types = weapon_types
	prefix.staff_kinds = staff_kinds
	prefix.weight_delta = PREFIX_WEIGHT
	prefix.damage_delta = PREFIX_DAMAGE
	return prefix
