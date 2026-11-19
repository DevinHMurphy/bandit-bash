# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     placement_cases.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Placement and Results cases for tests/campaign/run_all.gd: a new item's slot and the convoy's
## size (the faction's max army size); taking an offer into the convoy, a full convoy refused
## until one of its items is scrapped (gold and ITEM_SCRAPPED); equipping a usable weapon, the
## displaced item to the convoy or scrapped (ITEM_EQUIPPED both ways); a weapon the unit can't
## wield, a fallen unit, scrapping a displaced item from an empty slot, and a convoy scrap nothing
## needs, all refused and changing nothing; scrapping at pickup (gold, no GAINED); a modified
## convoy item scrapped for its own, higher value; the roster whole
## after each; the report classes read back as written, through JSON too, and bad data refused;
## the nodes the map can enter next; and the Boss's results. Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const RUN_SEED: int = 0x5EA7C0DE
const MERCENARY: String = "mercenary"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _map_rules: CampaignMapRules = null
var _rules: CombatRewardRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_map_rules = load(RULES_PATH) as CampaignMapRules
	_rules = CombatRewardRules.load_default()
	_check("placement: the catalog, map rules and reward rules load", (
			_catalog != null and _map_rules != null and _rules != null
	))
	if _catalog == null or _map_rules == null or _rules == null:
		return
	_test_slots_and_capacity()
	_test_to_convoy()
	_test_equip()
	_test_refusals()
	_test_scrap_at_pickup()
	_test_scrap_modified()
	_test_report_restore()
	_test_next_nodes_and_boss()


func _test_slots_and_capacity() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var weapon: ItemDefinition = _first_of(EffectCatalog.Kind.WEAPON)
	var equipment: ItemDefinition = _first_of(EffectCatalog.Kind.EQUIPMENT)
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	_check("placement: a weapon goes in Weapon, equipment in Equipment, a trinket in Pouch", (
			ItemPlacement.slot_for(weapon) == Loadout.Slot.WEAPON
			and ItemPlacement.slot_for(equipment) == Loadout.Slot.EQUIPMENT
			and ItemPlacement.slot_for(trinket) == Loadout.Slot.POUCH
	))
	var faction: FactionDefinition = _catalog.faction(MERCENARY)
	_check("placement: the convoy holds the faction's max army size (Mercenary 4)", (
			ItemPlacement.convoy_capacity(seat_run, _catalog) == faction.max_army_size
			and faction.max_army_size == 4
	), str(ItemPlacement.convoy_capacity(seat_run, _catalog)))
	_check("placement: scrap pays 20% of the price, rounded (a Common at its kind's price)", (
			ItemPlacement.scrap_value(trinket)
					== Prices.scrap_value(trinket.kind, trinket.rarity, 20.0)
			and ItemPlacement.scrap_value(trinket) > 0
	), str(ItemPlacement.scrap_value(trinket)))


func _test_to_convoy() -> void:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	var seat_run: SeatRun = run.seat_run(0)
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	seat_run.convoy.clear()
	var pick: ItemPick = _open_pick(session, PackedStringArray([trinket.id, trinket.id]))
	var took: CampaignBatch = session.submit(ItemPickCommand.new(0, 0, ItemPlacement.new()))
	_check("placement: a take to a convoy with room adds it last, GAINED only", (
			not took.is_rejected()
			and _kinds(took) == [CampaignFact.Kind.GAINED]
			and seat_run.convoy.size() == 1
			and seat_run.convoy[0] == pick.offers[0].instance_id
			and _is_whole(seat_run)
	), took.rejected_reason)

	_fill_convoy(session, seat_run, 4)
	var full_pick: ItemPick = _open_pick(session, PackedStringArray([trinket.id]))
	var gold_before: int = seat_run.gold
	var refused: CampaignBatch = session.submit(ItemPickCommand.new(0, 0, ItemPlacement.new()))
	var snapshot: Dictionary = seat_run.capture_roster()
	_check("placement: a full convoy refuses the take, which changes nothing", (
			refused.is_rejected()
			and refused.rejected_reason.contains("full")
			and not ItemPick.pending(seat_run).is_resolved
			and seat_run.capture_roster() == snapshot
			and seat_run.gold == gold_before
	), refused.rejected_reason)
	var scrapped_id: String = seat_run.convoy[1]
	var scrapped_gold: int = ItemPlacement.scrap_value(
			_catalog.item(seat_run.items[scrapped_id].definition_id)
	)
	var made_room: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.CONVOY, "", false, scrapped_id)
	))
	_check("placement: scrapping a convoy item makes room: its gold, ITEM_SCRAPPED, then GAINED", (
			not made_room.is_rejected()
			and _kinds(made_room) == [CampaignFact.Kind.ITEM_SCRAPPED, CampaignFact.Kind.GAINED]
			and made_room.facts[0].actor_id == scrapped_id
			and made_room.facts[0].amount == scrapped_gold
			and seat_run.gold == gold_before + scrapped_gold
			and not seat_run.items.has(scrapped_id)
			and not seat_run.convoy.has(scrapped_id)
			and seat_run.convoy.size() == 4
			and seat_run.convoy[3] == full_pick.offers[0].instance_id
			and _is_whole(seat_run)
	), made_room.rejected_reason)


func _test_equip() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.convoy.clear()
	var unit: UnitInstance = null
	var weapon: WeaponDefinition = null
	for armed: UnitInstance in seat_run.army:
		weapon = _weapon_for(armed, true) if not armed.weapon_id.is_empty() else null
		if weapon != null:
			unit = armed
			break
	_check("placement: the army has an armed unit and a Common weapon it can wield", (
			unit != null and weapon != null
	))
	if unit == null or weapon == null:
		return
	var old_weapon: String = unit.weapon_id
	var pick: ItemPick = _open_pick(session, PackedStringArray([weapon.id]))
	var equipped: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit.instance_id)
	))
	var new_id: String = pick.offers[0].instance_id
	_check("placement: equipping a usable weapon sends the old one to the convoy", (
			not equipped.is_rejected()
			and _kinds(equipped) == [
				CampaignFact.Kind.GAINED,
				CampaignFact.Kind.ITEM_EQUIPPED,
				CampaignFact.Kind.ITEM_EQUIPPED,
			]
			and equipped.facts[1].actor_id == old_weapon
			and equipped.facts[1].target_id.is_empty()
			and equipped.facts[2].actor_id == new_id
			and equipped.facts[2].target_id == unit.instance_id
			and unit.weapon_id == new_id
			and seat_run.convoy == PackedStringArray([old_weapon])
			and _is_whole(seat_run)
	), equipped.rejected_reason)

	var second: ItemPick = _open_pick(session, PackedStringArray([weapon.id]))
	var gold_before: int = seat_run.gold
	var scrap_gold: int = ItemPlacement.scrap_value(weapon)
	var replaced: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit.instance_id, true)
	))
	_check("placement: equipping with the displaced item scrapped pays its gold", (
			not replaced.is_rejected()
			and _kinds(replaced) == [
				CampaignFact.Kind.GAINED,
				CampaignFact.Kind.ITEM_SCRAPPED,
				CampaignFact.Kind.ITEM_EQUIPPED,
			]
			and replaced.facts[1].actor_id == new_id
			and seat_run.gold == gold_before + scrap_gold
			and unit.weapon_id == second.offers[0].instance_id
			and not seat_run.items.has(new_id)
			and seat_run.convoy.size() == 1
			and _is_whole(seat_run)
	), replaced.rejected_reason)

	_fill_convoy(session, seat_run, 4)
	_open_pick(session, PackedStringArray([weapon.id]))
	var no_room: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit.instance_id)
	))
	var room_id: String = seat_run.convoy[0]
	var keep_and_scrap: ItemPlacement = ItemPlacement.new(
			ItemPlacement.Destination.EQUIP, unit.instance_id, false, room_id
	)
	var with_room: CampaignBatch = session.submit(ItemPickCommand.new(0, 0, keep_and_scrap))
	_check("placement: a kept displaced item needs convoy room: refused, then a scrap allows it", (
			no_room.is_rejected()
			and not with_room.is_rejected()
			and not seat_run.items.has(room_id)
			and seat_run.convoy.size() == 4
			and _is_whole(seat_run)
	), "%s / %s" % [no_room.rejected_reason, with_room.rejected_reason])


func _test_refusals() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.convoy.clear()
	var unit: UnitInstance = _armed_unit(seat_run)
	var unusable: WeaponDefinition = _weapon_for(unit, false)
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	var first_offer: String = unusable.id if unusable != null else trinket.id
	_open_pick(session, PackedStringArray([first_offer, trinket.id]))
	var reasons: PackedStringArray = []
	var all_refused: bool = true
	var bad: Array[ItemPickCommand] = []
	if unusable != null:
		bad.append(ItemPickCommand.new(
				0, 0, ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit.instance_id)
		))
	var fallen: UnitInstance = seat_run.army[seat_run.army.size() - 1]
	seat_run.army.remove_at(seat_run.army.size() - 1)
	seat_run.fallen.append(fallen)
	bad.append(ItemPickCommand.new(
			0, 1, ItemPlacement.new(ItemPlacement.Destination.EQUIP, fallen.instance_id)
	))
	var empty_pouch: UnitInstance = null
	for each: UnitInstance in seat_run.army:
		if each.pouch_id.is_empty():
			empty_pouch = each
	if empty_pouch != null:
		var scrap_nothing: ItemPlacement = ItemPlacement.new(
				ItemPlacement.Destination.EQUIP, empty_pouch.instance_id, true
		)
		bad.append(ItemPickCommand.new(0, 1, scrap_nothing))
	bad.append(ItemPickCommand.new(
			0, 1, ItemPlacement.new(ItemPlacement.Destination.CONVOY, "", false, "item:none")
	))
	bad.append(ItemPickCommand.new(
			0, 1, ItemPlacement.new(ItemPlacement.Destination.SCRAP, "", true)
	))
	bad.append(ItemPickCommand.new(0, ItemPickCommand.SKIP, ItemPlacement.new()))
	var snapshot: Dictionary = seat_run.capture_roster()
	for command: ItemPickCommand in bad:
		var batch: CampaignBatch = session.submit(command)
		reasons.append(batch.rejected_reason)
		all_refused = all_refused and batch.is_rejected()
	_check("placement: an unusable weapon, a fallen unit, a scrap of nothing, a needless convoy "
			+ "scrap and a placed skip are refused, changing nothing", (
			all_refused
			and bad.size() >= 5
			and seat_run.capture_roster() == snapshot
			and not ItemPick.pending(seat_run).is_resolved
	), " / ".join(reasons))


func _test_scrap_at_pickup() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	var pick: ItemPick = _open_pick(session, PackedStringArray([trinket.id]))
	var gold_before: int = seat_run.gold
	var items_before: int = seat_run.items.size()
	var scrapped: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	))
	_check("placement: scrapping at pickup pays its gold and records ITEM_SCRAPPED alone", (
			not scrapped.is_rejected()
			and _kinds(scrapped) == [CampaignFact.Kind.ITEM_SCRAPPED]
			and scrapped.facts[0].actor_id == pick.offers[0].instance_id
			and scrapped.facts[0].definition_id == trinket.id
			and scrapped.facts[0].amount == ItemPlacement.scrap_value(trinket)
			and seat_run.gold == gold_before + ItemPlacement.scrap_value(trinket)
			and seat_run.items.size() == items_before
			and ItemPick.pending(seat_run).is_resolved
			and ItemPick.pending(seat_run).taken == 0
	), scrapped.rejected_reason)


func _test_scrap_modified() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	seat_run.convoy.clear()
	_fill_convoy(session, seat_run, 4)
	var modified_id: String = seat_run.convoy[0]
	var modified: ItemInstance = seat_run.items[modified_id]
	modified.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.HIT, 10.0, "placement_event", "Event"
	))
	var held_gold: int = ItemPlacement.held_scrap_value(modified, _catalog)
	_open_pick(session, PackedStringArray([trinket.id]))
	var gold_before: int = seat_run.gold
	var made_room: CampaignBatch = session.submit(ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.CONVOY, "", false, modified_id)
	))
	_check("placement: a modified convoy item scraps for its own value, more than a fresh one", (
			not made_room.is_rejected()
			and held_gold > ItemPlacement.scrap_value(trinket)
			and held_gold == Prices.item_scrap_value(modified, _catalog, 20.0)
			and made_room.facts[0].kind == CampaignFact.Kind.ITEM_SCRAPPED
			and made_room.facts[0].amount == held_gold
			and seat_run.gold == gold_before + held_gold
			and _is_whole(seat_run)
	), "%s: %d gold" % [made_room.rejected_reason, held_gold])


func _test_report_restore() -> void:
	var grades: CombatGrades = CombatGrades.new()
	grades.is_under_par = true
	grades.base_gold = 40
	grades.bonus_per_grade = 10
	grades.extra_gold = 5
	grades.gold = 55
	var award: XpAward = XpAward.new()
	award.unit_id = "unit:3"
	award.shared = 40
	award.personal = 12
	award.is_standout = true
	award.standout = _rules.standout_xp
	award.percent = 110
	award.total = 63
	var reached: LevelUp = LevelUp.new()
	reached.unit_id = "unit:3"
	reached.level = 2
	reached.gains = {CombatValue.Stat.HP: 1, CombatValue.Stat.MGT: 2}
	var data: Dictionary = {
		"grades": grades.capture(),
		"xp": [award.capture()],
		"level_ups": [reached.capture()],
	}
	var through_json: Variant = JSON.parse_string(JSON.stringify(data))
	var seat_run: SeatRun = SeatRun.new(0)
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = through_json
	var report: CampaignRunState.CombatReport = CampaignRunState.read_combat_report(
			seat_run, _rules
	)
	_check("report: grades, XP and level-ups read back as written, through JSON", (
			report != null
			and report.grades.capture() == grades.capture()
			and report.xp.size() == 1
			and report.xp[0].capture() == award.capture()
			and report.xp[0].standout == _rules.standout_xp
			and report.standout() == report.xp[0]
			and report.level_ups.size() == 1
			and report.level_ups[0].level == 2
			and report.level_ups[0].gains == reached.gains
	))
	print("    (errors about an unusable combat report follow)")
	var broken: Array[Dictionary] = [
		{"grades": {}, "xp": [], "level_ups": []},
		{"grades": grades.capture(), "xp": [{"unit_id": ""}], "level_ups": []},
		{"grades": grades.capture(), "xp": [], "level_ups": [{"unit_id": "u", "level": 0}]},
		{"grades": grades.capture(), "xp": [], "level_ups": [
			{"unit_id": "u", "level": 2, "gains": {"99": 1}},
		]},
	]
	var refused: int = 0
	for entry: Dictionary in broken:
		seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = entry
		if CampaignRunState.read_combat_report(seat_run, _rules) == null:
			refused += 1
	seat_run.pending_offers.erase(CampaignRunState.COMBAT_REPORT_KEY)
	_check("report: a missing part, an empty unit, level 0 or an unknown stat is refused; none "
			+ "reads as null", (
			refused == broken.size()
			and CampaignRunState.read_combat_report(seat_run, _rules) == null
	), "%d of %d refused" % [refused, broken.size()])


func _test_next_nodes_and_boss() -> void:
	var session: CampaignSession = _session()
	var run: CampaignRunState = session.run
	var first: PackedInt32Array = run.next_nodes()
	var floor_one: PackedInt32Array = run.graph.nodes_on_floor(1)
	floor_one.sort()
	session.submit(ChooseNodeCommand.new(0, first[0]))
	var inside: PackedInt32Array = run.next_nodes()
	session.submit(LeaveNodeCommand.new(0))
	var children: PackedInt32Array = run.graph.children_of(run.node).duplicate()
	children.sort()
	var accepted: bool = true
	for node_id: int in run.next_nodes():
		accepted = accepted and ChooseNodeCommand.new(0, node_id).validate(run).is_empty()
	_check("map: next nodes are floor 1 at the start, none inside a node, then the children", (
			first == floor_one
			and inside.is_empty()
			and run.next_nodes() == children
			and accepted
	), "%s / %s / %s" % [first, inside, run.next_nodes()])
	run.flow.stage = RunFlow.Stage.RESULTS
	var at_standard: bool = run.is_boss_beaten()
	var boss: int = run.graph.nodes_on_floor(run.graph.get_floor_count())[0]
	run.node = boss
	var at_boss: bool = run.is_boss_beaten()
	run.flow.stage = RunFlow.Stage.NODE
	_check("map: only a Boss node's results count as the Boss beaten", (
			not at_standard
			and at_boss
			and run.graph.type_of(boss) == CampaignGraph.NodeType.BOSS
			and not run.is_boss_beaten()
	))


# A new Mercenary run for seat 0, built as a new run is.
func _session() -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			_map_rules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog,
			factions,
			session.ids
	)
	session.run = start.run
	return session


# Puts the run at a combat's results with an open pick offering definition_ids, entering a node
# first when on the map, and returns the pick.
func _open_pick(session: CampaignSession, definition_ids: PackedStringArray) -> ItemPick:
	var run: CampaignRunState = session.run
	if run.is_on_map():
		session.submit(ChooseNodeCommand.new(0, run.next_nodes()[0]))
	var pick: ItemPick = ItemPick.new()
	pick.slot = ItemPick.Slot.POUCH
	for definition_id: String in definition_ids:
		var definition: ItemDefinition = _catalog.item(definition_id)
		pick.offers.append(ItemPick.Offer.new(
				definition_id, session.ids.next_item_id(definition.display_name)
		))
	pick.store(run.seat_run(0))
	run.flow.stage = RunFlow.Stage.RESULTS
	return pick


# Tops the seat's convoy up to count items, each a new trinket instance.
func _fill_convoy(session: CampaignSession, seat_run: SeatRun, count: int) -> void:
	var trinket: ItemDefinition = _first_of(EffectCatalog.Kind.TRINKET)
	while seat_run.convoy.size() < count:
		var item_id: String = session.ids.next_item_id(trinket.display_name)
		seat_run.items[item_id] = ItemInstance.new(item_id, trinket.id)
		seat_run.convoy.append(item_id)


# The first living unit holding a weapon.
func _armed_unit(seat_run: SeatRun) -> UnitInstance:
	for unit: UnitInstance in seat_run.army:
		var types: PackedStringArray = ItemPlacement.weapon_types_of(unit, _catalog)
		if not unit.weapon_id.is_empty() and not types.is_empty():
			return unit
	return null


# A Common weapon unit can wield (usable true) or can't (false); null when the catalog has none.
func _weapon_for(unit: UnitInstance, usable: bool) -> WeaponDefinition:
	if unit == null:
		return null
	var types: PackedStringArray = ItemPlacement.weapon_types_of(unit, _catalog)
	for definition: Resource in _catalog.all_of(EffectCatalog.Kind.WEAPON):
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if weapon == null or weapon.rarity != ItemDefinition.Rarity.COMMON:
			continue
		if types.has(weapon.weapon_type) == usable:
			return weapon
	return null


# The first Common item of kind, else the first of any rarity.
func _first_of(kind: EffectCatalog.Kind) -> ItemDefinition:
	var found: ItemDefinition = null
	for definition: Resource in _catalog.all_of(kind):
		var item: ItemDefinition = definition as ItemDefinition
		if item == null:
			continue
		if item.rarity == ItemDefinition.Rarity.COMMON:
			return item
		if found == null:
			found = item
	return found


func _kinds(batch: CampaignBatch) -> Array[CampaignFact.Kind]:
	var kinds: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in batch.facts:
		kinds.append(fact.kind)
	return kinds


# Whether the roster's invariant holds: a restore of its capture accepts it.
func _is_whole(seat_run: SeatRun) -> bool:
	return SeatRun.new(0).restore_roster(seat_run.capture_roster()) == OK


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
