# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     treasure_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Treasure and the Key combat's heirloom for tests/campaign/run_all.gd, on real runs from the
## real catalog: the vision's chest odds over many seeds (sizes 50 / 33 / 17, gold half the time at
## 20-60, a Large chest's Legendary 10% of the time, never the Ring of Favor, never an owned,
## cursed or off-pool heirloom); the empty-tier fallback; the chests rolled once on entry, per seat
## and seeded; taking (gold at once, the heirloom, the Legendary placed) and giving up; Leave
## refused until every chest is settled; a quit and Continue at the chest; the Key combat's
## heirloom rolled after its pick, its odds, taken, given up, saved and blocking Leave.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 4242

# Chests rolled for the odds, and how far a share may stray from the rule's.
# Units: chests; percentage points.
const ODDS_ROLLS: int = 6000
const ODDS_TOLERANCE: float = 2.5
# A Large chest's Legendary share strays more: about a sixth of the rolls are Large.
const LEGENDARY_TOLERANCE: float = 3.0

const RING_OF_FAVOR: String = "ring_of_favor"
const M1_ID: String = "m1_greybox"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _rules: CombatRewardRules = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_rules = CombatRewardRules.load_default()
	_check("treasure: the catalog and reward rules load", _catalog != null and _rules != null)
	if _catalog == null or _rules == null:
		return
	_test_odds()
	_test_fallback()
	_test_open()
	_test_take_and_give_up()
	_test_legendary_placed()
	_test_leave_and_resume()
	_test_key_heirloom()
	_test_key_heirloom_odds()


func _test_odds() -> void:
	var seat_run: SeatRun = Fixture.session(RUN_SEED).run.seat_run(0)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var sizes: Dictionary[String, int] = {}
	var with_gold: int = 0
	var gold_low: int = TreasureChest.GOLD_MAX
	var gold_high: int = TreasureChest.GOLD_MIN
	var large: int = 0
	var legendary: int = 0
	var wrong: PackedStringArray = []
	var allowed: PackedStringArray = HeirloomDraw.candidates(
			seat_run, _catalog, HeirloomDraw.TIERS, false
	)
	for roll_seed: int in ODDS_ROLLS:
		var chest: TreasureChest = TreasureChest.roll(
				RngStream.new(roll_seed), seat_run, _catalog, ids, false
		)
		sizes[chest.tier] = sizes.get(chest.tier, 0) + 1
		if chest.gold > 0:
			with_gold += 1
			gold_low = mini(gold_low, chest.gold)
			gold_high = maxi(gold_high, chest.gold)
			if chest.gold < TreasureChest.GOLD_MIN or chest.gold > TreasureChest.GOLD_MAX:
				wrong.append("gold %d" % [chest.gold])
		if chest.tier == ContentIds.HEIRLOOM_RARE:
			large += 1
		if chest.item != null:
			legendary += 1
			var item: ItemDefinition = _catalog.item(chest.item.definition_id)
			if chest.tier != ContentIds.HEIRLOOM_RARE or item == null:
				wrong.append("item in a %s chest" % [chest.tier])
			elif item.rarity != ItemDefinition.Rarity.LEGENDARY or item.id == RING_OF_FAVOR:
				wrong.append("item %s" % [item.id])
			if not chest.heirloom_id.is_empty():
				wrong.append("an item and an heirloom")
			continue
		var heirloom: HeirloomDefinition = _catalog.heirloom(chest.heirloom_id)
		if heirloom == null or not allowed.has(chest.heirloom_id) or heirloom.tier != chest.tier:
			wrong.append("heirloom %s in a %s chest" % [chest.heirloom_id, chest.tier])
	var shares: PackedStringArray = []
	var is_close: bool = true
	for index: int in HeirloomDraw.TIERS.size():
		var tier: String = HeirloomDraw.TIERS[index]
		var share: float = 100.0 * sizes.get(tier, 0) / ODDS_ROLLS
		shares.append("%s %.1f" % [tier, share])
		is_close = is_close and absf(share - HeirloomDraw.TIER_WEIGHTS[index]) <= ODDS_TOLERANCE
	_check("odds: chest sizes over %d seeds are Small 50 / Medium 33 / Large 17" % [ODDS_ROLLS], (
			is_close
	), ", ".join(shares))
	var gold_share: float = 100.0 * with_gold / ODDS_ROLLS
	_check("odds: half the chests add gold, from 20 to 60, both ends reached", (
			absf(gold_share - TreasureChest.GOLD_CHANCE) <= ODDS_TOLERANCE
			and gold_low == TreasureChest.GOLD_MIN
			and gold_high == TreasureChest.GOLD_MAX
	), "%.1f%%, %d to %d" % [gold_share, gold_low, gold_high])
	var legendary_share: float = 100.0 * legendary / maxi(large, 1)
	_check("odds: a Large chest holds a Legendary instead of its heirloom 10% of the time", (
			absf(legendary_share - TreasureChest.LEGENDARY_CHANCE) <= LEGENDARY_TOLERANCE
			and legendary > 0
	), "%d of %d Large (%.1f%%)" % [legendary, large, legendary_share])
	_check("odds: every chest holds its size's heirloom, never owned or off the pool, or an item", (
			wrong.is_empty()
	), ", ".join(wrong.slice(0, 5)))
	var legendaries: PackedStringArray = []
	for item: ItemDefinition in TreasureChest.usable_legendaries(seat_run, _catalog):
		legendaries.append(item.id)
	_check("odds: the Legendary pool is usable by the army and leaves out the Ring of Favor", (
			not legendaries.is_empty() and not legendaries.has(RING_OF_FAVOR)
	), ", ".join(legendaries))


func _test_fallback() -> void:
	var seat_run: SeatRun = Fixture.session(RUN_SEED).run.seat_run(0)
	for heirloom_id: String in HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_RARE]), false
	):
		seat_run.add_heirloom(heirloom_id)
	var drawn: String = HeirloomDraw.draw(
			RngStream.new(1), seat_run, _catalog, ContentIds.HEIRLOOM_RARE, false
	)
	var drawn_heirloom: HeirloomDefinition = _catalog.heirloom(drawn)
	var drawn_tier: String = drawn_heirloom.tier if drawn_heirloom != null else ""
	_check("fallback: a tier with nothing left draws from the whole main pool", (
			not drawn.is_empty()
			and drawn_tier != ContentIds.HEIRLOOM_RARE
			and HeirloomDraw.TIERS.has(drawn_tier)
			and not seat_run.heirloom_ids().has(drawn)
	), "%s (%s)" % [drawn, drawn_tier])
	for heirloom_id: String in HeirloomDraw.candidates(
			seat_run, _catalog, HeirloomDraw.TIERS, true
	):
		seat_run.add_heirloom(heirloom_id)
	var none_left: String = HeirloomDraw.draw(
			RngStream.new(1), seat_run, _catalog, ContentIds.HEIRLOOM_COMMON, true
	)
	_check("fallback: with every heirloom owned, nothing is drawn", none_left.is_empty(), none_left)
	var coop_only: PackedStringArray = []
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		var heirloom: HeirloomDefinition = resource as HeirloomDefinition
		if heirloom != null and heirloom.is_coop_only:
			coop_only.append(heirloom.id)
	var fresh: SeatRun = Fixture.session(RUN_SEED).run.seat_run(0)
	var tiers: PackedStringArray = HeirloomDraw.TIERS
	var solo: PackedStringArray = HeirloomDraw.candidates(fresh, _catalog, tiers, false)
	var coop: PackedStringArray = HeirloomDraw.candidates(fresh, _catalog, tiers, true)
	var leaked: bool = false
	for heirloom_id: String in coop_only:
		leaked = leaked or solo.has(heirloom_id)
	_check("pool: co-op-only heirlooms are drawn only in co-op; no starting, Shop or curse", (
			not leaked
			and coop.size() == solo.size() + _main_pool_count(coop_only)
			and not _has_off_pool(coop)
	), "%d solo, %d co-op, co-op only %s" % [solo.size(), coop.size(), coop_only])


func _test_open() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var outside: CampaignBatch = session.submit(OpenTreasureCommand.for_session(session, _catalog))
	_check("open: refused outside a Treasure node, changing nothing", (
			outside.is_rejected()
			and not session.run.seat_run(0).pending_offers.has(TreasureChest.OFFER_KEY)
	), outside.rejected_reason)
	_check("open: the map has a Treasure route", Fixture.enter(session.run, _treasure()))
	var opened: CampaignBatch = session.submit(OpenTreasureCommand.for_session(session, _catalog))
	var chest: TreasureChest = TreasureChest.pending(session.run.seat_run(0))
	_check("open: the chest is rolled and saved before it shows, recording no fact", (
			not opened.is_rejected() and opened.facts.is_empty() and chest != null
			and not chest.is_resolved
	), opened.rejected_reason)
	var again: CampaignBatch = session.submit(OpenTreasureCommand.for_session(session, _catalog))
	_check("open: a second open is refused, so a chest never rolls twice", again.is_rejected())
	var twin: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(twin.run, _treasure())
	twin.submit(OpenTreasureCommand.for_session(twin, _catalog))
	_check("open: the same seed rolls the same chest", (
			JSON.stringify(TreasureChest.pending(twin.run.seat_run(0)).capture())
			== JSON.stringify(chest.capture())
	))
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, _treasure())
	var both: CampaignBatch = pair.submit(OpenTreasureCommand.for_session(pair, _catalog))
	var first: TreasureChest = TreasureChest.pending(pair.run.seat_run(0))
	var second: TreasureChest = TreasureChest.pending(pair.run.seat_run(1))
	_check("open (co-op): every seat gets its own chest from its own stream", (
			not both.is_rejected() and first != null and second != null
	), both.rejected_reason)


func _test_take_and_give_up() -> void:
	var session: CampaignSession = _at_open_treasure()
	var seat_run: SeatRun = session.run.seat_run(0)
	var chest: TreasureChest = _staged_chest(seat_run, 35, _first_common(seat_run))
	var gold_before: int = seat_run.gold
	var taken: CampaignBatch = session.submit(TreasureCommand.new(0))
	_check("take: the gold at once, then the heirloom, as GOLD_CHANGED and GAINED", (
			not taken.is_rejected()
			and Fixture.kinds(taken) == [CampaignFact.Kind.GOLD_CHANGED, CampaignFact.Kind.GAINED]
			and seat_run.gold == gold_before + 35
			and taken.facts[0].definition_id == TreasureCommand.SOURCE_ID
			and seat_run.heirloom_ids().has(chest.heirloom_id)
			and seat_run.convoy.is_empty()
			and TreasureChest.pending(seat_run).is_taken
	), "%s %s" % [taken.rejected_reason, Fixture.kinds(taken)])
	_check("take: the chest can't be taken twice", (
			session.submit(TreasureCommand.new(0)).is_rejected()
	))
	var later: CampaignSession = _at_open_treasure()
	var later_run: SeatRun = later.run.seat_run(0)
	_staged_chest(later_run, 0, _first_common(later_run))
	var heirlooms_before: int = later_run.heirloom_ids().size()
	var placed: CampaignBatch = later.submit(
			TreasureCommand.new(0, true, ItemPlacement.new(ItemPlacement.Destination.CONVOY))
	)
	var given: CampaignBatch = later.submit(TreasureCommand.new(0, false))
	_check("give up: a placement for a chest with no item is refused; giving up records nothing", (
			placed.is_rejected()
			and not given.is_rejected() and given.facts.is_empty()
			and later_run.heirloom_ids().size() == heirlooms_before
			and TreasureChest.pending(later_run).is_resolved
			and not TreasureChest.pending(later_run).is_taken
	), "%s / %s" % [placed.rejected_reason, given.rejected_reason])


func _test_legendary_placed() -> void:
	var session: CampaignSession = _at_open_treasure()
	var seat_run: SeatRun = session.run.seat_run(0)
	var legendaries: Array[ItemDefinition] = TreasureChest.usable_legendaries(seat_run, _catalog)
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(legendaries[0].id, session.ids.next_item_id("legendary"))
	chest.store(seat_run)
	var unplaced: CampaignBatch = session.submit(TreasureCommand.new(0))
	var placed: CampaignBatch = session.submit(
			TreasureCommand.new(0, true, ItemPlacement.new(ItemPlacement.Destination.CONVOY))
	)
	_check("legendary: needs a placement, then joins the convoy (GAINED), no heirloom", (
			unplaced.is_rejected()
			and not placed.is_rejected()
			and Fixture.kinds(placed) == [CampaignFact.Kind.GAINED]
			and seat_run.convoy.has(chest.item.instance_id)
			and Fixture.is_whole(seat_run)
	), "%s / %s" % [unplaced.rejected_reason, placed.rejected_reason])


func _test_leave_and_resume() -> void:
	var session: CampaignSession = _at_open_treasure()
	var chest: TreasureChest = TreasureChest.pending(session.run.seat_run(0))
	var early: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("leave: refused while the chest is open", early.is_rejected(), early.rejected_reason)
	var resumed: CampaignRunState = Fixture.through_json(session.run)
	var resumed_chest: TreasureChest = (
			TreasureChest.pending(resumed.seat_run(0)) if resumed != null else null
	)
	_check("resume: a quit and Continue at the chest shows the same chest, still open", (
			resumed_chest != null
			and JSON.stringify(resumed_chest.capture()) == JSON.stringify(chest.capture())
			and not resumed_chest.is_resolved
	))
	session.run = resumed
	var reopened: CampaignBatch = session.submit(OpenTreasureCommand.for_session(session, _catalog))
	var took: CampaignBatch = session.submit(_take_command(session.run.seat_run(0)))
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("resume: never rolled again; taken after it, then Leave clears the chest", (
			reopened.is_rejected()
			and not took.is_rejected()
			and not left.is_rejected()
			and session.run.is_on_map()
			and not session.run.seat_run(0).pending_offers.has(TreasureChest.OFFER_KEY)
	), "%s / %s" % [took.rejected_reason, left.rejected_reason])
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, _treasure())
	pair.submit(OpenTreasureCommand.for_session(pair, _catalog))
	pair.submit(_take_command(pair.run.seat_run(0), 0))
	var waiting: CampaignBatch = pair.submit(LeaveNodeCommand.new(0))
	pair.submit(TreasureCommand.new(1, false))
	var done: CampaignBatch = pair.submit(LeaveNodeCommand.new(0))
	_check("leave (co-op): waits for every seat's chest", (
			waiting.is_rejected() and not done.is_rejected()
	), "%s / %s" % [waiting.rejected_reason, done.rejected_reason])


func _test_key_heirloom() -> void:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	var run: CampaignRunState = session.run
	_check("key: the map has a Key route", Fixture.enter(run, CampaignGraph.NodeType.KEY))
	var result: CampaignSession.BattleResult = _won_result(
			run, CombatMapDefinition.CombatType.KEY
	)
	var won: CampaignRunState = run.apply_battle(
			result, session.ids, session.reward_rolls(result), _rules, _catalog
	)
	var offer: KeyHeirloom = KeyHeirloom.pending(won.seat_run(0)) if won != null else null
	_check("key: a won Key combat offers one heirloom, saved with its report, not owned", (
			offer != null
			and not offer.is_resolved
			and won.seat_run(0).pending_offers.has(CampaignRunState.COMBAT_REPORT_KEY)
			and not won.seat_run(0).heirloom_ids().has(offer.heirloom_id)
			and HeirloomDraw.TIERS.has(_catalog.heirloom(offer.heirloom_id).tier)
	))
	if offer == null:
		return
	session.run = won
	var pick: ItemPick = ItemPick.pending(won.seat_run(0))
	if pick != null and not pick.is_resolved:
		session.submit(ItemPickCommand.new(0, ItemPickCommand.SKIP))
	var early: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	var resumed: CampaignRunState = Fixture.through_json(won)
	_check("key: Leave waits for it; a quit and Continue keeps the same open offer", (
			early.is_rejected()
			and resumed != null
			and KeyHeirloom.pending(resumed.seat_run(0)).heirloom_id == offer.heirloom_id
			and KeyHeirloom.is_open(resumed.seat_run(0))
	), early.rejected_reason)
	var taken: CampaignBatch = session.submit(KeyHeirloomCommand.new(0))
	var twice: CampaignBatch = session.submit(KeyHeirloomCommand.new(0))
	var left: CampaignBatch = session.submit(LeaveNodeCommand.new(0))
	_check("key: taken (GAINED) once; then Leave clears it", (
			not taken.is_rejected()
			and Fixture.kinds(taken) == [CampaignFact.Kind.GAINED]
			and won.seat_run(0).heirloom_ids().has(offer.heirloom_id)
			and twice.is_rejected()
			and not left.is_rejected()
			and not won.seat_run(0).pending_offers.has(KeyHeirloom.OFFER_KEY)
	), "%s / %s" % [taken.rejected_reason, left.rejected_reason])
	var skipping: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(skipping.run, CampaignGraph.NodeType.KEY)
	var again: CampaignSession.BattleResult = _won_result(
			skipping.run, CombatMapDefinition.CombatType.KEY
	)
	skipping.run = skipping.run.apply_battle(
			again, skipping.ids, skipping.reward_rolls(again), _rules, _catalog
	)
	var owned_before: int = skipping.run.seat_run(0).heirloom_ids().size()
	var given: CampaignBatch = skipping.submit(KeyHeirloomCommand.new(0, false))
	_check("key: giving it up records nothing and grants nothing", (
			not given.is_rejected() and given.facts.is_empty()
			and skipping.run.seat_run(0).heirloom_ids().size() == owned_before
			and not KeyHeirloom.is_open(skipping.run.seat_run(0))
	), given.rejected_reason)
	var standard: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(standard.run, CampaignGraph.NodeType.STANDARD)
	var plain: CampaignSession.BattleResult = _won_result(
			standard.run, CombatMapDefinition.CombatType.STANDARD
	)
	var after: CampaignRunState = standard.run.apply_battle(
			plain, standard.ids, standard.reward_rolls(plain), _rules, _catalog
	)
	_check("key: a Standard combat offers no heirloom", (
			after != null and KeyHeirloom.pending(after.seat_run(0)) == null
	))


func _test_key_heirloom_odds() -> void:
	var seat_run: SeatRun = Fixture.session(RUN_SEED).run.seat_run(0)
	var tiers: Dictionary[String, int] = {}
	for roll_seed: int in ODDS_ROLLS:
		var offer: KeyHeirloom = KeyHeirloom.roll(
				RngStream.new(roll_seed), seat_run, _catalog, false
		)
		var tier: String = "none"
		if offer != null:
			tier = _catalog.heirloom(offer.heirloom_id).tier
		tiers[tier] = tiers.get(tier, 0) + 1
	var shares: PackedStringArray = []
	var is_close: bool = true
	for index: int in HeirloomDraw.TIERS.size():
		var tier: String = HeirloomDraw.TIERS[index]
		var share: float = 100.0 * tiers.get(tier, 0) / ODDS_ROLLS
		shares.append("%s %.1f" % [tier, share])
		is_close = is_close and absf(share - HeirloomDraw.TIER_WEIGHTS[index]) <= ODDS_TOLERANCE
	_check("key odds: over %d seeds the heirloom is Common 50 / Uncommon 33 / Rare 17" % [
		ODDS_ROLLS,
	], is_close, ", ".join(shares))


# A run inside a Treasure node with its chest rolled.
func _at_open_treasure() -> CampaignSession:
	var session: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(session.run, _treasure())
	session.submit(OpenTreasureCommand.for_session(session, _catalog))
	return session


# Replaces seat_run's chest with an open Small one holding gold and heirloom_id.
func _staged_chest(seat_run: SeatRun, gold: int, heirloom_id: String) -> TreasureChest:
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_COMMON
	chest.gold = gold
	chest.heirloom_id = heirloom_id
	chest.store(seat_run)
	return chest


# The command that takes seat_run's chest, a Legendary to the convoy.
func _take_command(seat_run: SeatRun, seat: int = 0) -> TreasureCommand:
	var chest: TreasureChest = TreasureChest.pending(seat_run)
	var placement: ItemPlacement = (
			ItemPlacement.new(ItemPlacement.Destination.CONVOY) if chest.item != null else null
	)
	return TreasureCommand.new(seat, true, placement)


func _first_common(seat_run: SeatRun) -> String:
	return HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_COMMON]), false
	)[0]


func _main_pool_count(heirloom_ids: PackedStringArray) -> int:
	var count: int = 0
	for heirloom_id: String in heirloom_ids:
		if HeirloomDraw.TIERS.has(_catalog.heirloom(heirloom_id).tier):
			count += 1
	return count


func _has_off_pool(heirloom_ids: PackedStringArray) -> bool:
	for heirloom_id: String in heirloom_ids:
		var heirloom: HeirloomDefinition = _catalog.heirloom(heirloom_id)
		if heirloom is CurseDefinition or not HeirloomDraw.TIERS.has(heirloom.tier):
			return true
	return false


func _treasure() -> CampaignGraph.NodeType:
	return CampaignGraph.NodeType.TREASURE


# A won result for run's node: every army unit standing at full HP, the seat's map won on turn 1.
func _won_result(
		run: CampaignRunState, combat_type: CombatMapDefinition.CombatType
) -> CampaignSession.BattleResult:
	var result: CampaignSession.BattleResult = CampaignSession.BattleResult.new()
	result.floor_number = run.floor_number
	result.node = run.node
	result.map_id = M1_ID
	result.pool_ids = PackedStringArray([M1_ID])
	result.is_finished = true
	result.is_won = true
	for unit: UnitInstance in run.seat_run(0).army:
		var unit_outcome: CampaignSession.UnitOutcome = CampaignSession.UnitOutcome.new()
		unit_outcome.seat = 0
		unit_outcome.hp = UnitInstance.FULL_HP
		result.units[unit.instance_id] = unit_outcome
	var outcome: CampaignSession.SeatOutcome = CampaignSession.SeatOutcome.new()
	outcome.seat = 0
	outcome.is_won = true
	outcome.combat_type = combat_type
	outcome.grade_bonus_percent = 25
	outcome.shared_xp_percent = 100
	outcome.turn = 1
	result.seats[0] = outcome
	return result


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
