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
## For the draw: three test-only events built in code (a goblet with a chooser and a tier curse,
## a shrine needing a fallen unit, a team-choice toll with a surprise combat), runs standing in an
## Unknown node, and the commands EventNode builds (team votes included), submitted to the
## session; and a quit and Continue through the campaign block's sections and JSON. None of the
## test content is real content: CT12 authors the weapon prefix list, EV4 the 13 events.

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

## The test events' ids. The goblet: 0 "Drink Deep" (a chosen unit +2 MGT), 1 "Break the Ice"
## (a random rare weapon and a minor curse), 2 "Walk Away". The shrine (a fallen unit in every
## army): 0 "Offer a Prayer" (revive), 1 "Claim the Relic" (a rare heirloom). The toll (a team
## choice): 0 "Pay" (-30 gold, needs 30), 1 "Fight" (a surprise combat), 2 "Intimidate" (+40 gold
## and a minor curse).
const GOBLET: String = "test_goblet"
const SHRINE: String = "test_shrine"
const TOLL: String = "test_toll"
const MGT_GAIN: int = 2
const TOLL_GOLD: int = 30
const LOOT_GOLD: int = 40
const MINOR: String = "minor"
const RARE: String = "rare"
const START_GOLD: int = 100

var catalog: EffectCatalog.Index = null
var map_rules: CampaignMapRules = null
var rules: CombatRewardRules = null
## The last [method resume]'s error: [constant OK] when it loaded.
var resume_error: Error = OK


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


## The goblet (see [constant GOBLET]).
func goblet() -> EventDefinition:
	var drink: StatOutcome = StatOutcome.new()
	drink.target = EventOutcome.Target.CHOSEN
	drink.stat = CombatValue.Stat.MGT
	drink.amount = MGT_GAIN
	var weapon: ItemGrantOutcome = ItemGrantOutcome.new()
	weapon.random = ItemGrantOutcome.RandomItem.RARE_WEAPON
	return _event(GOBLET, false, EventDefinition.Eligibility.ALWAYS, [
		_option("Drink Deep", [drink]),
		_option("Break the Ice", [weapon], null, MINOR),
		_option("Walk Away", []),
	])


## The shrine (see [constant GOBLET]).
func shrine() -> EventDefinition:
	var needs: EventRequirements = EventRequirements.new()
	needs.needs_fallen_unit = true
	var relic: HeirloomOutcome = HeirloomOutcome.new()
	relic.tier = RARE
	return _event(SHRINE, false, EventDefinition.Eligibility.FALLEN_UNIT, [
		_option("Offer a Prayer", [ReviveOutcome.new()], needs),
		_option("Claim the Relic", [relic]),
	])


## The toll (see [constant GOBLET]).
func toll() -> EventDefinition:
	var pay: GoldOutcome = GoldOutcome.new()
	pay.amount = -TOLL_GOLD
	var needs: EventRequirements = EventRequirements.new()
	needs.gold = TOLL_GOLD
	var loot: GoldOutcome = GoldOutcome.new()
	loot.amount = LOOT_GOLD
	return _event(TOLL, true, EventDefinition.Eligibility.ALWAYS, [
		_option("Pay", [pay], needs),
		_option("Fight", [SurpriseCombatOutcome.new()]),
		_option("Intimidate", [loot], null, MINOR),
	])


## A pool of [param events]; the three test events when empty.
func pool(events: Array[EventDefinition] = []) -> EventPool:
	if events.is_empty():
		return EventPool.new([goblet(), shrine(), toll()])
	return EventPool.new(events)


## A new Mercenary run of [param seat_count] seats, inside a floor-1 node made an Unknown one.
func unknown_session(seat_count: int = 1) -> CampaignSession:
	var seat_numbers: PackedInt32Array = []
	var factions: Dictionary[int, String] = {}
	for seat: int in seat_count:
		seat_numbers.append(seat)
		factions[seat] = MERCENARY
	var mode: CampaignData.Mode = (
			CampaignData.Mode.SOLO if seat_count == 1 else CampaignData.Mode.MULTIPLAYER
	)
	var made: CampaignSession = CampaignSession.new(mode, RUN_SEED, seat_numbers)
	var start: RunStart = RunStart.build(
			map_rules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			catalog,
			factions,
			made.ids
	)
	made.run = start.run
	var first: int = made.run.graph.nodes_on_floor(1)[0]
	made.run.graph.set_node_type(first, CampaignGraph.NodeType.UNKNOWN)
	made.submit(ChooseNodeCommand.new(0, first))
	return made


## Leaves the run's node and enters its first child, made an Unknown node.
func next_unknown(made: CampaignSession) -> void:
	made.submit(LeaveNodeCommand.new(0))
	var child: int = made.run.graph.children_of(made.run.node)[0]
	made.run.graph.set_node_type(child, CampaignGraph.NodeType.UNKNOWN)
	made.submit(ChooseNodeCommand.new(0, child))


## Opens an event from [param events] at the run's node, as the Unknown node does.
func open(made: CampaignSession, events: EventPool) -> CampaignBatch:
	return made.submit(EventNode.open(made, events, catalog, rules))


## Seat [param seat] opens option [param option]'s chooser (or closes it with -1).
func chooser(made: CampaignSession, events: EventPool, seat: int, option: int) -> CampaignBatch:
	return made.submit(EventNode.open_chooser(made, seat, option, events, catalog))


## Seat [param seat] chooses option [param option] with [param choice].
func choose(
		made: CampaignSession,
		events: EventPool,
		seat: int,
		option: int,
		choice: EventChoice = null
) -> CampaignBatch:
	return made.submit(EventNode.choose(made, seat, option, choice, events, catalog))


## Seat [param seat] votes for option [param option] of the open team choice.
func vote(made: CampaignSession, events: EventPool, seat: int, option: int) -> CampaignBatch:
	return made.submit(EventNode.vote(made, seat, option, events, catalog))


## [param made]'s campaign block saved through every campaign section a resume needs, through
## JSON, then loaded into a new session the way CampaignService builds one: rng, instance_ids,
## the run, then the events. Null when any step fails; [member resume_error] says which error.
func resume(made: CampaignSession) -> CampaignSession:
	var saving: Sections = Sections.new()
	saving.attach(made)
	var players: Array[CampaignData.PlayerRun] = _players(made.seats)
	var block: Dictionary = saving.registry.capture(SaveSection.Block.CAMPAIGN, {})
	saving.registry.capture_players(players)
	var player_data: Array = []
	for player: CampaignData.PlayerRun in players:
		player_data.append(player.to_dict())
	var parsed: Variant = JSON.parse_string(JSON.stringify(
			{"sections": block, "players": player_data}
	))
	var saved: Dictionary = parsed as Dictionary if parsed is Dictionary else {}

	var loading: Sections = Sections.new()
	var read_players: Array[CampaignData.PlayerRun] = []
	for entry: Variant in saved.get("players", []) as Array:
		read_players.append(CampaignData.PlayerRun.from_dict(entry as Dictionary))
	var sections: Dictionary = saved.get("sections", {}) as Dictionary
	resume_error = loading.registry.restore(SaveSection.Block.CAMPAIGN, sections)
	if resume_error == OK:
		resume_error = loading.registry.restore_players(read_players)
	var resumed: CampaignSession = CampaignSession.new(made.mode, RUN_SEED, made.seats)
	if resume_error == OK:
		resume_error = loading.attach(resumed)
	return resumed if resume_error == OK else null


## The seat's living unit that isn't the commander, first in roster order.
func soldier(seat_run: SeatRun) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit
	return null


## The sorted ids of every curse of [param tier] in the catalog.
func curses_of(tier: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.CURSE):
		var curse: CurseDefinition = definition as CurseDefinition
		if curse != null and curse.tier == tier:
			found.append(curse.id)
	found.sort()
	return found


func _event(
		id: String,
		is_team: bool,
		eligibility: EventDefinition.Eligibility,
		options: Array[EventOption]
) -> EventDefinition:
	var event: EventDefinition = EventDefinition.new()
	event.id = id
	event.title = id
	event.is_team_choice = is_team
	event.eligibility = eligibility
	event.options = options
	return event


func _option(
		title: String,
		outcomes: Array[EventOutcome],
		requirements: EventRequirements = null,
		curse_tier: String = ""
) -> EventOption:
	var option: EventOption = EventOption.new()
	option.title = title
	option.outcomes = outcomes
	option.requirements = requirements
	option.curse_tier = curse_tier
	return option


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


func _players(seats: PackedInt32Array) -> Array[CampaignData.PlayerRun]:
	var players: Array[CampaignData.PlayerRun] = []
	for seat: int in seats:
		var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
		player.seat = seat
		players.append(player)
	return players


# The campaign block's sections a continued run needs, registered as CampaignService registers
# them, and attached to a session in its order.
class Sections:
	extends RefCounted

	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var rng: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
	var ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.CAMPAIGN)
	var run: RunSaveSections = RunSaveSections.new()
	var events: EventSaveSection = EventSaveSection.new()

	func _init() -> void:
		registry.register(SaveSection.Block.CAMPAIGN, rng)
		registry.register(SaveSection.Block.CAMPAIGN, ids)
		registry.register(SaveSection.Block.CAMPAIGN, run.map)
		registry.register(SaveSection.Block.CAMPAIGN, run.flow)
		for section: RunSaveSections.SeatSection in run.seat_sections:
			registry.register_player(section)
		registry.register(SaveSection.Block.CAMPAIGN, events)

	## Attaches every section to session; the first error, else OK. A session that already has its
	## run (one being saved) keeps it.
	func attach(session: CampaignSession) -> Error:
		var err: Error = rng.attach(session)
		if err == OK:
			err = ids.attach(session)
		if err == OK:
			var run_err: Error = run.attach(session)
			err = OK if run_err == ERR_DOES_NOT_EXIST and session.run != null else run_err
		if err == OK:
			err = events.attach(session)
		return err
