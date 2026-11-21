# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_offer_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## Starting heirloom cases for tests/campaign/run_all.gd, on real runs from the real catalog: the
## pool of seven against heirlooms.md; the draw seeded, three different heirlooms each time, all
## seven reached, stored before the first save and absent without a stream; each of the seven
## taken end to end with its facts (War Chest's gold, Tactician's Manual, Family Relic's Uncommon
## heirloom, Abundance's room and recruit, Ancestral Weapon's usable Rares, Veteran Company's
## upgrade, Mercenary Contract's prefixed recruit replacing a unit, never the commander), the first
## node refused until then; a quit and Continue at the offer and inside each sub-choice (the run
## through JSON) showing the same offer and taking the same; refused options and the skip; every
## run operation and its fact; and recruit offers (level, average growths, no type twice, saved).

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const MERCENARY: String = "mercenary"

# heirlooms.md's Starting heirlooms, as data: bonus, gold, offers, positive prefix, drawn tier.
const POOL: Dictionary[String, Array] = {
	"abundance": [StartingHeirloomDefinition.Bonus.RECRUIT, 0, 2, false, ""],
	"ancestral_weapon": [StartingHeirloomDefinition.Bonus.WEAPON, 0, 3, false, ""],
	"family_relic": [StartingHeirloomDefinition.Bonus.HEIRLOOM, 0, 0, false, "uncommon"],
	"mercenary_contract": [StartingHeirloomDefinition.Bonus.REPLACE, 0, 3, true, ""],
	"tacticians_manual": [StartingHeirloomDefinition.Bonus.NONE, 0, 0, false, ""],
	"veteran_company": [StartingHeirloomDefinition.Bonus.UPGRADE, 0, 0, false, ""],
	"war_chest": [StartingHeirloomDefinition.Bonus.GOLD, 100, 0, false, ""],
}

# Seeds searched for an offer holding a given heirloom, and drawn for the pool's spread.
const SEEDS: int = 300

# A recruit's level for the average-growth case, and its type.
const RECRUIT_LEVEL: int = 3
const FIGHTER: String = "fighter"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _map_rules: CampaignMapRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_map_rules = load(RULES_PATH) as CampaignMapRules
	_check("starting: the catalog and map rules load", _catalog != null and _map_rules != null)
	if _catalog == null or _map_rules == null:
		return
	_test_pool()
	_test_draw()
	_test_war_chest_manual_and_relic()
	_test_abundance()
	_test_ancestral_weapon()
	_test_veteran_company()
	_test_mercenary_contract()
	_test_quit_and_continue()
	_test_refusals_and_skip()
	_test_operations()
	_test_recruit_offers()


func _test_pool() -> void:
	var pool: PackedStringArray = StartingOffer.pool(_catalog)
	_check("pool: the seven starting heirlooms, in id order", (
			pool == PackedStringArray(POOL.keys())
	), str(pool))
	var wrong: PackedStringArray = []
	for heirloom_id: String in POOL:
		var definition: StartingHeirloomDefinition = (
				_catalog.heirloom(heirloom_id) as StartingHeirloomDefinition
		)
		var row: Array = POOL[heirloom_id]
		if (
				definition == null or definition.tier != ContentIds.HEIRLOOM_STARTING
				or definition.bonus != row[0] or definition.gold != row[1]
				or definition.offer_count != row[2] or definition.is_prefix_positive != row[3]
				or definition.heirloom_tier != row[4]
				or (definition.bonus != StartingHeirloomDefinition.Bonus.NONE
						and not "\n".join(definition.describe()).contains(
								StartingHeirloomDefinition.RUN_START_LEAD_IN
						))
		):
			wrong.append(heirloom_id)
	_check("pool: each heirloom's bonus is heirlooms.md's, its line in its text", (
			wrong.is_empty()
	), str(wrong))
	var abundance: HeirloomDefinition = _catalog.heirloom("abundance")
	var manual: HeirloomDefinition = _catalog.heirloom("tacticians_manual")
	var ancestral: StartingHeirloomDefinition = (
			_catalog.heirloom("ancestral_weapon") as StartingHeirloomDefinition
	)
	_check("pool: Abundance and the Manual carry effects; Ancestral Weapon draws Rares", (
			abundance.effects.size() == 1 and manual.effects.size() == 1
			and ancestral.item_rarity == ItemDefinition.Rarity.RARE
	))


func _test_draw() -> void:
	var first: CampaignSession = _session(7)
	var again: CampaignSession = _session(7)
	var offer: StartingOffer = StartingOffer.pending(first.run.seat_run(0))
	_check("draw: a new run stores its offer before the first save, open", (
			offer != null and not offer.is_resolved and offer.taken == StartingOffer.NOT_TAKEN
			and StartingOffer.is_open(first.run.seat_run(0))
	))
	_check("draw: the same seed draws the same offer, sub-offers and ids included", (
			JSON.stringify(first.run.seat_run(0).capture_economy())
			== JSON.stringify(again.run.seat_run(0).capture_economy())
	))
	var seen: Dictionary[String, bool] = {}
	var repeats: PackedStringArray = []
	var differs: bool = false
	var first_ids: PackedStringArray = _ids_of(offer)
	for run_seed: int in SEEDS:
		var drawn: StartingOffer = StartingOffer.pending(_session(run_seed).run.seat_run(0))
		var ids: PackedStringArray = _ids_of(drawn)
		var unique: Dictionary[String, bool] = {}
		for heirloom_id: String in ids:
			unique[heirloom_id] = true
			seen[heirloom_id] = true
		if ids.size() != StartingOffer.OFFER_SIZE or unique.size() != ids.size():
			repeats.append("%d: %s" % [run_seed, ids])
		differs = differs or ids != first_ids
	_check("draw: every offer is three different heirlooms (%d seeds)" % [SEEDS], (
			repeats.is_empty()
	), ", ".join(repeats))
	_check("draw: all seven are reached, and seeds differ", seen.size() == POOL.size() and differs)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var plain: RunStart = RunStart.build(
			_map_rules, first.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)), _catalog,
			factions, InstanceIdAllocator.new()
	)
	_check("draw: a run built without a stream has no offer", (
			not plain.run.seat_run(0).pending_offers.has(StartingOffer.OFFER_KEY)
	))


func _test_war_chest_manual_and_relic() -> void:
	var chest: CampaignSession = _session_offering("war_chest")
	var gold: int = chest.run.seat_run(0).gold
	var refused: CampaignBatch = chest.submit(ChooseNodeCommand.new(0, chest.run.next_nodes()[0]))
	var took: CampaignBatch = _take(chest, "war_chest")
	_check("war chest: the first node waits for the offer", (
			refused.is_rejected() and refused.rejected_reason.contains("starting heirloom")
	), refused.rejected_reason)
	_check("war chest: +100 gold, GAINED then GOLD_CHANGED 100", (
			not took.is_rejected()
			and _kinds(took) == [CampaignFact.Kind.GAINED, CampaignFact.Kind.GOLD_CHANGED]
			and took.facts[1].amount == 100 and took.facts[1].definition_id == "war_chest"
			and chest.run.seat_run(0).gold == gold + 100
			and chest.run.seat_run(0).heirloom_ids().has("war_chest")
	), took.rejected_reason)
	_resolved_then_map(chest, "war chest")

	var manual: CampaignSession = _session_offering("tacticians_manual")
	var taken: CampaignBatch = _take(manual, "tacticians_manual")
	_check("tactician's manual: owned, GAINED alone", (
			not taken.is_rejected() and _kinds(taken) == [CampaignFact.Kind.GAINED]
			and manual.run.seat_run(0).heirloom_ids().has("tacticians_manual")
	), taken.rejected_reason)

	var relic: CampaignSession = _session_offering("family_relic")
	var option: StartingOffer.Option = _option_of(relic, "family_relic")
	var drawn: HeirloomDefinition = _catalog.heirloom(option.drawn_heirloom_id)
	var owned_before: PackedStringArray = relic.run.seat_run(0).heirloom_ids()
	var gained: CampaignBatch = _take(relic, "family_relic")
	_check("family relic: an Uncommon heirloom not owned, gained after the relic", (
			not gained.is_rejected()
			and drawn != null and drawn.tier == ContentIds.HEIRLOOM_UNCOMMON
			and not drawn.is_coop_only and not owned_before.has(drawn.id)
			and _kinds(gained) == [CampaignFact.Kind.GAINED, CampaignFact.Kind.GAINED]
			and gained.facts[1].definition_id == drawn.id
	), "%s %s" % [option.drawn_heirloom_id, gained.rejected_reason])


func _test_abundance() -> void:
	var session: CampaignSession = _session_offering("abundance")
	var seat_run: SeatRun = session.run.seat_run(0)
	var option: StartingOffer.Option = _option_of(session, "abundance")
	_check("abundance: two recruits of different types, no prefix, level 1, a starting weapon", (
			option.recruits.size() == 2
			and option.recruits[0].unit.unit_type_id != option.recruits[1].unit.unit_type_id
			and option.recruits[0].unit.prefix_id.is_empty()
			and option.recruits[1].unit.prefix_id.is_empty()
			and option.recruits[0].unit.level == 1
			and _brings_starting_weapon(option.recruits[0])
	))
	_check("abundance: before it, the army is full at 4, the convoy holds 4", (
			RunOperations.max_army_size(seat_run, _catalog) == 4
			and ItemPlacement.convoy_capacity(seat_run, _catalog) == 4 and seat_run.army.size() == 4
	))
	var recruit_id: String = option.recruits[1].unit.instance_id
	var took: CampaignBatch = _take(session, "abundance", 1)
	_check("abundance: max army size and the convoy go to 5; the recruit joins last", (
			not took.is_rejected()
			and RunOperations.max_army_size(seat_run, _catalog) == 5
			and ItemPlacement.convoy_capacity(seat_run, _catalog) == 5
			and seat_run.army.size() == 5 and seat_run.army[4].instance_id == recruit_id
			and _is_whole(seat_run)
	), took.rejected_reason)
	_check("abundance: GAINED, ARMY_SIZE_CHANGED +1, UNIT_RECRUITED", (
			_kinds(took) == [
				CampaignFact.Kind.GAINED, CampaignFact.Kind.ARMY_SIZE_CHANGED,
				CampaignFact.Kind.UNIT_RECRUITED,
			]
			and took.facts[1].amount == 1 and took.facts[2].actor_id == recruit_id
			and took.facts[2].definition_id == "abundance" and took.facts[2].target_id.is_empty()
	), str(_kinds(took)))
	_resolved_then_map(session, "abundance")


func _test_ancestral_weapon() -> void:
	var session: CampaignSession = _session_offering("ancestral_weapon")
	var seat_run: SeatRun = session.run.seat_run(0)
	var option: StartingOffer.Option = _option_of(session, "ancestral_weapon")
	var usable: PackedStringArray = ItemPick.usable_weapon_types(seat_run, _catalog)
	var types: Dictionary[String, bool] = {}
	var wrong: PackedStringArray = []
	for weapon: ItemPick.Offer in option.weapons:
		var definition: WeaponDefinition = _catalog.weapon(weapon.definition_id)
		if (
				definition == null or definition.rarity != ItemDefinition.Rarity.RARE
				or not usable.has(definition.weapon_type)
		):
			wrong.append(weapon.definition_id)
		else:
			types[definition.weapon_type] = true
	_check("ancestral weapon: three Rare weapons the army can use, of three types", (
			option.weapons.size() == 3 and wrong.is_empty() and types.size() == 3
	), "%s; %s" % [wrong, types.keys()])
	var nowhere: StartingHeirloomCommand = _command(session.run, "ancestral_weapon", -1, 0, "")
	nowhere.placement = null
	var no_placement: CampaignBatch = session.submit(nowhere)
	_check("ancestral weapon: a weapon with nowhere to go is refused", no_placement.is_rejected())
	var weapon_id: String = option.weapons[0].instance_id
	var took: CampaignBatch = _take(
			session, "ancestral_weapon", -1, 0, "",
			ItemPlacement.new(ItemPlacement.Destination.CONVOY)
	)
	_check("ancestral weapon: taken to the convoy, GAINED for the heirloom and the weapon", (
			not took.is_rejected()
			and _kinds(took) == [CampaignFact.Kind.GAINED, CampaignFact.Kind.GAINED]
			and took.facts[1].actor_id == weapon_id
			and seat_run.convoy.has(weapon_id) and _is_whole(seat_run)
	), took.rejected_reason)

	var equipped: CampaignSession = _session_offering("ancestral_weapon")
	var holder: String = ""
	var offered: StartingOffer.Option = _option_of(equipped, "ancestral_weapon")
	var definition: WeaponDefinition = _catalog.weapon(offered.weapons[0].definition_id)
	for unit: UnitInstance in equipped.run.seat_run(0).army:
		if ItemPlacement.weapon_types_of(unit, _catalog).has(definition.weapon_type):
			holder = unit.instance_id
			break
	var old_weapon: String = equipped.run.seat_run(0).unit(holder).weapon_id
	var on_unit: CampaignBatch = _take(
			equipped, "ancestral_weapon", -1, 0, "",
			ItemPlacement.new(ItemPlacement.Destination.EQUIP, holder)
	)
	_check("ancestral weapon: equipped, its old weapon to the convoy", (
			not on_unit.is_rejected()
			and equipped.run.seat_run(0).unit(holder).weapon_id == offered.weapons[0].instance_id
			and equipped.run.seat_run(0).convoy.has(old_weapon)
			and _is_whole(equipped.run.seat_run(0))
	), on_unit.rejected_reason)


func _test_veteran_company() -> void:
	var session: CampaignSession = _session_offering("veteran_company")
	var seat_run: SeatRun = session.run.seat_run(0)
	var eligible: PackedStringArray = StartingOffer.eligible_units(session.run, 0, _catalog, false)
	_check("veteran company: every starting unit but the commander may be upgraded", (
			eligible.size() == 3 and not eligible.has(seat_run.commander_id)
	), str(eligible))
	var commander: CampaignBatch = _take(session, "veteran_company", -1, -1, seat_run.commander_id)
	var nobody: CampaignBatch = _take(session, "veteran_company")
	_check("veteran company: the commander and no unit are both refused", (
			commander.is_rejected() and commander.rejected_reason.contains("commander")
			and nobody.is_rejected()
	), commander.rejected_reason)
	var took: CampaignBatch = _take(session, "veteran_company", -1, -1, eligible[1])
	_check("veteran company: the unit is upgraded, GAINED then UNIT_UPGRADED", (
			not took.is_rejected() and seat_run.unit(eligible[1]).is_upgraded
			and _kinds(took) == [CampaignFact.Kind.GAINED, CampaignFact.Kind.UNIT_UPGRADED]
			and took.facts[1].actor_id == eligible[1]
			and took.facts[1].definition_id == "veteran_company"
	), took.rejected_reason)


func _test_mercenary_contract() -> void:
	var session: CampaignSession = _session_offering("mercenary_contract")
	var seat_run: SeatRun = session.run.seat_run(0)
	var option: StartingOffer.Option = _option_of(session, "mercenary_contract")
	var tiers: PackedStringArray = []
	for recruit: RecruitOffer in option.recruits:
		var prefix: UnitPrefixDefinition = _catalog.unit_prefix(recruit.unit.prefix_id)
		tiers.append("none" if prefix == null else str(prefix.tier))
	_check("mercenary contract: three recruits, each with a +1 or +2 prefix", (
			option.recruits.size() == 3 and not tiers.has("none") and not tiers.has("-1")
			and not tiers.has("-2") and not tiers.has("0")
	), str(tiers))
	var commander_id: String = seat_run.commander_id
	var on_commander: CampaignBatch = _take(session, "mercenary_contract", 0, -1, commander_id)
	var no_unit: CampaignBatch = _take(session, "mercenary_contract", 0)
	_check("mercenary contract: never replaces the commander, and needs a unit", (
			on_commander.is_rejected() and on_commander.rejected_reason.contains("commander")
			and no_unit.is_rejected()
			and not StartingOffer.eligible_units(session.run, 0, _catalog, true).has(commander_id)
			and seat_run.unit(commander_id) != null
	), on_commander.rejected_reason)
	var leaving: UnitInstance = seat_run.army[2]
	var leaving_items: PackedStringArray = leaving.item_ids()
	var joining: String = option.recruits[0].unit.instance_id
	var took: CampaignBatch = _take(session, "mercenary_contract", 0, -1, leaving.instance_id)
	var expected: Array[CampaignFact.Kind] = [CampaignFact.Kind.GAINED]
	for _item: String in leaving_items:
		expected.append(CampaignFact.Kind.ITEM_EQUIPPED)
	expected.append_array([CampaignFact.Kind.UNIT_DISMISSED, CampaignFact.Kind.UNIT_RECRUITED])
	var convoy_holds: bool = true
	for item_id: String in leaving_items:
		convoy_holds = convoy_holds and seat_run.convoy.has(item_id)
	_check("mercenary contract: the recruit replaces the unit, whose items go to the convoy", (
			not took.is_rejected()
			and seat_run.army.size() == 4 and seat_run.unit(leaving.instance_id) == null
			and seat_run.unit(joining) != null and seat_run.fallen.is_empty()
			and convoy_holds and not leaving_items.is_empty() and _is_whole(seat_run)
			and seat_run.unit(commander_id) != null
	), took.rejected_reason)
	_check("mercenary contract: GAINED, ITEM_EQUIPPED per item, UNIT_DISMISSED, UNIT_RECRUITED", (
			_kinds(took) == expected
			and took.facts[-2].actor_id == leaving.instance_id
			and took.facts[-2].target_id == joining
			and took.facts[-1].actor_id == joining
			and took.facts[-1].target_id == leaving.instance_id
	), str(_kinds(took)))


# A quit at the offer, or inside any sub-choice (which saves nothing), Continues on the saved run:
# the same offer, the same sub-offers, and taking it there gives what it gives unbroken.
func _test_quit_and_continue() -> void:
	var failures: PackedStringArray = []
	for heirloom_id: String in POOL:
		var session: CampaignSession = _session_offering(heirloom_id)
		var before: String = JSON.stringify(
				StartingOffer.pending(session.run.seat_run(0)).capture()
		)
		var reloaded: CampaignRunState = _through_json(session.run)
		var after: StartingOffer = null if reloaded == null else StartingOffer.pending(
				reloaded.seat_run(0)
		)
		if after == null or _as_saved(JSON.stringify(after.capture())) != _as_saved(before):
			failures.append("%s: offer" % [heirloom_id])
			continue
		var straight: CampaignBatch = _take(session, heirloom_id, 0, 0, _choice_unit(session.run))
		session.run = reloaded
		var resumed: CampaignBatch = _take(session, heirloom_id, 0, 0, _choice_unit(reloaded))
		if straight.is_rejected() != resumed.is_rejected() or _kinds(straight) != _kinds(resumed):
			failures.append("%s: %s / %s" % [
				heirloom_id, straight.rejected_reason, resumed.rejected_reason,
			])
			continue
		var done: CampaignRunState = _through_json(reloaded)
		var twice: CampaignBatch = done.resolve(_command(done, heirloom_id, 0, 0, ""))
		if not StartingOffer.pending(done.seat_run(0)).is_resolved or not twice.is_rejected():
			failures.append("%s: taken once" % [heirloom_id])
	_check("quit and Continue: at the offer and in each sub-choice, the same offer and take", (
			failures.is_empty()
	), ", ".join(failures))


func _test_refusals_and_skip() -> void:
	var session: CampaignSession = _session(11)
	var skip: CampaignBatch = session.submit(StartingHeirloomCommand.new(0))
	_check("refusals: no skip while an heirloom can be taken", (
			skip.is_rejected() and skip.rejected_reason.contains("can still be taken")
	), skip.rejected_reason)
	var seat_run: SeatRun = session.run.seat_run(0)
	var offer: StartingOffer = StartingOffer.new()
	for heirloom_id: String in ["veteran_company", "mercenary_contract", "ancestral_weapon"]:
		offer.options.append(StartingOffer.Option.new(heirloom_id))
	offer.store(seat_run)
	var commander: UnitInstance = seat_run.unit(seat_run.commander_id)
	for unit: UnitInstance in seat_run.army.duplicate():
		if unit != commander:
			seat_run.army.erase(unit)
			seat_run.fallen.append(unit)
	var reasons: PackedStringArray = []
	for option: StartingOffer.Option in offer.options:
		reasons.append(StartingOffer.option_problem(session.run, 0, option, _catalog))
	_check("refusals: each says why (no unit to upgrade, none to replace, no weapon)", (
			reasons[0].contains("upgraded") and reasons[1].contains("recruit")
			and reasons[2].contains("Rare")
	), str(reasons))
	var taken: CampaignBatch = session.submit(_command(session.run, "veteran_company", -1, -1, ""))
	var skipped: CampaignBatch = session.submit(StartingHeirloomCommand.new(0))
	_check("refusals: a refused heirloom can't be taken; with all three refused, the skip", (
			taken.is_rejected() and not skipped.is_rejected() and skipped.facts.is_empty()
			and StartingOffer.pending(seat_run).is_resolved
			and StartingOffer.pending(seat_run).taken == StartingOffer.NOT_TAKEN
	), "%s / %s" % [taken.rejected_reason, skipped.rejected_reason])

	var crowded: CampaignSession = _session_offering("abundance")
	var crowded_run: SeatRun = crowded.run.seat_run(0)
	var extra: RecruitOffer = RecruitOffer.make(_catalog, FIGHTER, "", 1, crowded.ids)
	crowded_run.army.append(extra.unit)
	crowded_run.items.merge(extra.items)
	var no_room: String = StartingOffer.option_problem(
			crowded.run, 0, _option_of(crowded, "abundance"), _catalog
	)
	_check("refusals: Abundance with no room, even with its own +1", (
			no_room.contains("no room")
	), no_room)


func _test_operations() -> void:
	var session: CampaignSession = _session(5, false)
	var run: CampaignRunState = session.run
	var seat_run: SeatRun = run.seat_run(0)
	var recruit: RecruitOffer = RecruitOffer.make(_catalog, FIGHTER, "", 1, session.ids)
	_check("operations: a full army refuses a recruit", (
			RunOperations.recruit_problem(run, 0, recruit, _catalog).contains("full")
	))
	var first: int = run.fact_log.size()
	RunOperations.grant_heirloom(run, 0, "muster_roll", _catalog)
	_check("operations: Muster Roll is GAINED then ARMY_SIZE_CHANGED +1; army and convoy 5", (
			_kinds_from(run, first) == [
				CampaignFact.Kind.GAINED, CampaignFact.Kind.ARMY_SIZE_CHANGED,
			]
			and run.fact_log[-1].amount == 1
			and RunOperations.max_army_size(seat_run, _catalog) == 5
			and ItemPlacement.convoy_capacity(seat_run, _catalog) == 5
	))
	first = run.fact_log.size()
	RunOperations.recruit(run, 0, recruit, "test")
	_check("operations: recruit adds the unit and its weapon, UNIT_RECRUITED", (
			_kinds_from(run, first) == [CampaignFact.Kind.UNIT_RECRUITED]
			and seat_run.army[-1] == recruit.unit and _is_whole(seat_run)
	))
	var fighter: UnitInstance = recruit.unit
	fighter.hp = 10
	first = run.fact_log.size()
	RunOperations.upgrade(run, 0, fighter.instance_id, _catalog, "test")
	_check("operations: upgrading a hurt Fighter raises its HP by Fighter+'s 2", (
			fighter.is_upgraded and fighter.hp == 12
			and _kinds_from(run, first) == [
				CampaignFact.Kind.UNIT_UPGRADED, CampaignFact.Kind.HP_CHANGED,
			]
			and run.fact_log[-1].amount == 2
			and RunOperations.upgrade_problem(run, 0, fighter.instance_id, _catalog).contains(
					"already"
			)
			and not RunOperations.upgrade_problem(
					run, 0, seat_run.commander_id, _catalog
			).is_empty()
	), str(fighter.hp))
	first = run.fact_log.size()
	RunOperations.upgrade(run, 0, seat_run.army[1].instance_id, _catalog, "test")
	_check("operations: a unit at full HP stays full, UNIT_UPGRADED alone", (
			seat_run.army[1].hp == UnitInstance.FULL_HP
			and _kinds_from(run, first) == [CampaignFact.Kind.UNIT_UPGRADED]
	))
	var leaving: UnitInstance = seat_run.army[2]
	var carried: PackedStringArray = leaving.item_ids()
	for index: int in RunOperations.max_army_size(seat_run, _catalog) - carried.size() + 1:
		seat_run.convoy.append("item:filler%d" % [index])
	var crowded: String = RunOperations.dismiss_problem(run, 0, leaving.instance_id, _catalog)
	seat_run.convoy.clear()
	first = run.fact_log.size()
	RunOperations.dismiss(run, 0, leaving.instance_id, "test")
	_check("operations: dismiss needs convoy room, then moves the items and the unit out", (
			crowded.contains("convoy")
			and RunOperations.dismiss_problem(
					run, 0, seat_run.commander_id, _catalog
			).contains("commander")
			and _kinds_from(run, first).size() == carried.size() + 1
			and run.fact_log[-1].kind == CampaignFact.Kind.UNIT_DISMISSED
			and run.fact_log[first].kind == CampaignFact.Kind.ITEM_EQUIPPED
			and run.fact_log[first].target_id.is_empty()
			and seat_run.unit(leaving.instance_id) == null and seat_run.convoy == carried
			and _is_whole(seat_run)
	), crowded)
	var gold: int = seat_run.gold
	first = run.fact_log.size()
	RunOperations.grant_gold(run, 0, 50, "test")
	RunOperations.grant_gold(run, 0, -10000, "test")
	RunOperations.grant_gold(run, 0, -5, "test")
	_check("operations: gold changes by what it can, never below 0; nothing when nothing moves", (
			_kinds_from(run, first) == [
				CampaignFact.Kind.GOLD_CHANGED, CampaignFact.Kind.GOLD_CHANGED,
			]
			and run.fact_log[first].amount == 50 and run.fact_log[first + 1].amount == -(gold + 50)
			and seat_run.gold == 0
	))
	var trinket_kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.TRINKET]
	var trinket: ItemDefinition = ItemPools.items_of(_catalog, trinket_kinds)[0]
	var item: ItemInstance = ItemInstance.new(session.ids.next_item_id(), trinket.id)
	var to_convoy: ItemPlacement = ItemPlacement.new()
	first = run.fact_log.size()
	var problem: String = RunOperations.item_problem(run, 0, trinket, to_convoy, _catalog)
	RunOperations.grant_item(run, 0, item, to_convoy, _catalog)
	_check("operations: an item placed by its placement, GAINED", (
			problem.is_empty() and _kinds_from(run, first) == [CampaignFact.Kind.GAINED]
			and seat_run.convoy.has(item.instance_id)
	), problem)
	for _copy: int in 6:
		seat_run.add_heirloom("muster_roll")
	_check("operations: max army size never passes 8", (
			RunOperations.max_army_size(seat_run, _catalog) == 8
	), str(RunOperations.max_army_size(seat_run, _catalog)))


func _test_recruit_offers() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var leveled: RecruitOffer = RecruitOffer.make(_catalog, FIGHTER, "", RECRUIT_LEVEL, ids)
	var sheet: StatSheet = leveled.unit.stats(_catalog)
	var bare: StatSheet = RecruitOffer.make(_catalog, FIGHTER, "", 1, ids).unit.stats(_catalog)
	# Fighter growths HP 85, MGT 55, SPD 35, DEF 32, RES 15: two levels give +1 HP and +1 MGT.
	_check("recruits: a level-3 Fighter gains its average growths, as enemies do", (
			leveled.unit.level == RECRUIT_LEVEL
			and sheet.get_int(CombatValue.Key.HP) == bare.get_int(CombatValue.Key.HP) + 1
			and sheet.get_int(CombatValue.Key.MGT) == bare.get_int(CombatValue.Key.MGT) + 1
			and sheet.get_int(CombatValue.Key.SPD) == bare.get_int(CombatValue.Key.SPD)
	))
	var session: CampaignSession = _session(3, false)
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.army[1].level = 4
	seat_run.army[2].level = 3
	_check("recruits: they join at the army's average level, rounded down", (
			RecruitOffer.level_for(seat_run) == 2
	), str(RecruitOffer.level_for(seat_run)))
	var pool: PackedStringArray = RecruitOffer.pool(_catalog)
	var every: Array[RecruitOffer] = RecruitOffer.roll(
			RngStream.new(99), _catalog, pool.size() + 2, false, 1, ids
	)
	var types: Dictionary[String, bool] = {}
	for offered: RecruitOffer in every:
		types[offered.unit.unit_type_id] = true
	_check("recruits: one offer never repeats a type, and stops when the pool runs out", (
			pool.size() == 14 and every.size() == pool.size() and types.size() == pool.size()
	), "%d of %d" % [every.size(), pool.size()])
	var data: Variant = JSON.parse_string(JSON.stringify(leveled.capture()))
	var restored: RecruitOffer = (
			RecruitOffer.restore(data as Dictionary) if data is Dictionary else null
	)
	_check("recruits: an offer reads back through JSON, gear and level deltas included", (
			restored != null
			and _as_saved(JSON.stringify(restored.capture()))
					== _as_saved(JSON.stringify(leveled.capture()))
			and RecruitOffer.restore({"unit": leveled.unit.capture(), "items": {}}) == null
	))


# --- Helpers -----------------------------------------------------------------------------------


# A new solo run on run_seed, with its starting offer when with_offer.
func _session(run_seed: int, with_offer: bool = true) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
	)
	var streams: Dictionary[int, RngStream] = {}
	if with_offer:
		streams = session.starting_offer_streams()
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			_map_rules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog,
			factions,
			session.ids,
			streams
	)
	session.run = start.run
	return session


# The first seed's new run whose offer holds heirloom_id.
func _session_offering(heirloom_id: String) -> CampaignSession:
	for run_seed: int in SEEDS:
		var session: CampaignSession = _session(run_seed)
		if _ids_of(StartingOffer.pending(session.run.seat_run(0))).has(heirloom_id):
			return session
	_check("%s: some seed offers it" % [heirloom_id], false)
	return _session(0)


func _option_of(session: CampaignSession, heirloom_id: String) -> StartingOffer.Option:
	var offer: StartingOffer = StartingOffer.pending(session.run.seat_run(0))
	return offer.options[_ids_of(offer).find(heirloom_id)]


# Takes heirloom_id with the sub-choice given.
func _take(
		session: CampaignSession,
		heirloom_id: String,
		recruit: int = -1,
		weapon: int = -1,
		unit_id: String = "",
		placement: ItemPlacement = null
) -> CampaignBatch:
	return session.submit(_command(session.run, heirloom_id, recruit, weapon, unit_id, placement))


# The command taking heirloom_id from run's offer, its sub-choice trimmed to what its bonus asks.
func _command(
		run: CampaignRunState,
		heirloom_id: String,
		recruit: int,
		weapon: int,
		unit_id: String,
		placement: ItemPlacement = null
) -> StartingHeirloomCommand:
	var offer: StartingOffer = StartingOffer.pending(run.seat_run(0))
	var command: StartingHeirloomCommand = StartingHeirloomCommand.new(
			0, _ids_of(offer).find(heirloom_id)
	)
	var bonus: StartingHeirloomDefinition.Bonus = (
			_catalog.heirloom(heirloom_id) as StartingHeirloomDefinition
	).bonus
	var wants_recruit: bool = (
			bonus == StartingHeirloomDefinition.Bonus.RECRUIT
			or bonus == StartingHeirloomDefinition.Bonus.REPLACE
	)
	var wants_unit: bool = (
			bonus == StartingHeirloomDefinition.Bonus.REPLACE
			or bonus == StartingHeirloomDefinition.Bonus.UPGRADE
	)
	var wants_weapon: bool = bonus == StartingHeirloomDefinition.Bonus.WEAPON
	command.recruit = recruit if wants_recruit else StartingHeirloomCommand.NO_CHOICE
	command.unit_id = unit_id if wants_unit else ""
	command.weapon = weapon if wants_weapon else StartingHeirloomCommand.NO_CHOICE
	if wants_weapon:
		command.placement = (
				placement if placement != null
				else ItemPlacement.new(ItemPlacement.Destination.CONVOY)
		)
	command.catalog = _catalog
	return command


# The third unit of run's army, which every unit sub-choice may name in a new run.
func _choice_unit(run: CampaignRunState) -> String:
	return run.seat_run(0).army[2].instance_id


func _resolved_then_map(session: CampaignSession, what: String) -> void:
	var chosen: CampaignBatch = session.submit(
			ChooseNodeCommand.new(0, session.run.next_nodes()[0])
	)
	_check("%s: the offer is resolved and the first node can be chosen" % [what], (
			not StartingOffer.is_open(session.run.seat_run(0)) and not chosen.is_rejected()
	), chosen.rejected_reason)


# run as a quit and Continue gives it back: every section through JSON.
func _through_json(run: CampaignRunState) -> CampaignRunState:
	var copied: CampaignRunState = CampaignRunState.new()
	if (
			copied.restore_map(_json(run.capture_map())) != OK
			or copied.restore_flow(_json(run.flow.capture())) != OK
	):
		return null
	for seat: int in run.seat_numbers():
		var source: SeatRun = run.seat_run(seat)
		var seat_run: SeatRun = SeatRun.new(seat)
		if (
				seat_run.restore_roster(_json(source.capture_roster())) != OK
				or seat_run.restore_heirlooms(_json(source.capture_heirlooms())) != OK
				or seat_run.restore_runes(_json(source.capture_runes())) != OK
				or seat_run.restore_economy(_json(source.capture_economy())) != OK
		):
			return null
		copied.seats[seat] = seat_run
	return copied


func _json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed if parsed is Dictionary else {}


# text as JSON gives it back, so whole numbers and whole floats read alike.
func _as_saved(text: String) -> String:
	return JSON.stringify(JSON.parse_string(text))


func _ids_of(offer: StartingOffer) -> PackedStringArray:
	var ids: PackedStringArray = []
	if offer == null:
		return ids
	for option: StartingOffer.Option in offer.options:
		ids.append(option.heirloom_id)
	return ids


func _brings_starting_weapon(recruit: RecruitOffer) -> bool:
	var unit_type: UnitTypeDefinition = recruit.unit.definition(_catalog)
	var weapon: ItemInstance = recruit.items.get(recruit.unit.weapon_id, null)
	return (
			weapon != null and weapon.definition_id == unit_type.starting_weapon_id
			and recruit.items.size() == 1
	)


func _kinds(batch: CampaignBatch) -> Array[CampaignFact.Kind]:
	var kinds: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in batch.facts:
		kinds.append(fact.kind)
	return kinds


func _kinds_from(run: CampaignRunState, first: int) -> Array[CampaignFact.Kind]:
	var kinds: Array[CampaignFact.Kind] = []
	for fact: CampaignFact in run.fact_log.slice(first):
		kinds.append(fact.kind)
	return kinds


# Whether the roster's invariant holds: a restore of its capture accepts it.
func _is_whole(seat_run: SeatRun) -> bool:
	return SeatRun.new(0).restore_roster(seat_run.capture_roster()) == OK


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
