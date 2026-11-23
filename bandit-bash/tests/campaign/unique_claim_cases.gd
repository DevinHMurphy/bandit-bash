# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unique_claim_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## A unique heirloom's first claim outside the Armory ([UniqueClaims]), on 2-seat runs from the
## real catalog with Brothers in Arms offered to both seats at a Treasure, a key combat, a starting
## offer (Family Relic) and an event: the first take wins; the teammate's offer is replaced at once
## from its own stream (golden), in the same batch (HEIRLOOM_OFFER_REPLACED); the late take is
## refused naming the claimant; a quit and Continue keeps the replacement and its stream; a mirror
## rebuilt from the saved sections applies the batch off the wire with a matching hash. Nothing
## left to draw, rolls that never offer a teammate's unique heirloom, non-unique ones and solo.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 7311

const BROTHERS: String = "brothers_in_arms"
const BROTHERS_NAME: String = "Brothers in Arms"
const FAMILY_RELIC: String = "family_relic"
const WHETSTONE: String = "grandfathers_whetstone"
const BLACK_ALTAR: String = "black_altar"
# Black Altar's Take a Token: one rare heirloom (block 0) and a major curse.
const TOKEN_OPTION: int = 1
const TOKEN_BLOCK: int = 0

# Seeds the rolls are tried on. Brothers in Arms is about 1 in 30 of the chests and 1 in 10 of
# the Uncommon picks, so a few hundred seeds offer it often when nothing excludes it.
const ROLL_SEEDS: int = 600

# The replacements RUN_SEED draws: what a change to a stream, a draw or the Uncommon pool moves.
const GOLDEN_TREASURE: String = "burglars_roll"
const GOLDEN_KEY: String = "tactical_map"
const GOLDEN_STARTING: String = "breakers_maul"
const GOLDEN_EVENT: String = "war_ledger"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _rules: CombatRewardRules = null
var _pool: EventPool = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_rules = CombatRewardRules.load_default()
	_pool = EventPool.load_default()
	var brothers: HeirloomDefinition = _catalog.heirloom(BROTHERS)
	_check("unique claims: Brothers in Arms is a unique co-op Uncommon heirloom", (
			brothers != null and brothers.has_effect_tag(EffectDefinition.Tag.UNIQUE)
			and brothers.tier == ContentIds.HEIRLOOM_UNCOMMON and brothers.is_coop_only
			and _pool.event(BLACK_ALTAR) != null
	))
	if brothers == null or _pool.event(BLACK_ALTAR) == null:
		return
	_test_treasure()
	_test_key_heirloom()
	_test_starting_offer()
	_test_event()
	_test_nothing_left()
	_test_rolls_exclude()
	_test_owned_take_refused()
	_test_unchanged()


func _test_treasure() -> void:
	var pair: CampaignSession = _at_treasure()
	var stream: RngStream = pair.rng.stream(_reward_key(pair.run, 1))
	var golden: String = HeirloomDraw.draw(
			_copy(stream), pair.run.seat_run(1), _catalog,
			ContentIds.HEIRLOOM_UNCOMMON, true, PackedStringArray([BROTHERS])
	)
	var claim: CampaignBatch = pair.submit(TreasureCommand.new(0, true, null, BROTHERS))
	var other: TreasureChest = TreasureChest.pending(pair.run.seat_run(1))
	var replaced: CampaignFact = _replaced_fact(claim)
	_check("treasure: the first take wins; the teammate's chest is replaced from its stream", (
			not claim.is_rejected() and pair.run.seat_run(0).heirloom_ids().has(BROTHERS)
			and other != null and not other.is_resolved
			and other.heirloom_id == golden and other.heirloom_id != BROTHERS
			and other.tier == ContentIds.HEIRLOOM_UNCOMMON
			and _tier_of(other.heirloom_id) == ContentIds.HEIRLOOM_UNCOMMON
	), "%s; %s vs golden %s" % [claim.rejected_reason, other.heirloom_id, golden])
	_check("treasure: the replacement is the golden draw", (
			other.heirloom_id == GOLDEN_TREASURE
	), other.heirloom_id)
	_check("treasure: the take's batch carries the replacement after the GAINED", (
			replaced != null and replaced.seat == 1 and replaced.amount == 0
			and replaced.definition_id == other.heirloom_id
			and _index_of(claim, CampaignFact.Kind.GAINED)
			< _index_of(claim, CampaignFact.Kind.HEIRLOOM_OFFER_REPLACED)
	), str(Fixture.kinds(claim)))
	_test_mirror(pair, claim, "treasure")
	_test_continue(pair, "treasure", func(run: CampaignRunState) -> String:
		var chest: TreasureChest = TreasureChest.pending(run.seat_run(1))
		return chest.heirloom_id if chest != null else "no chest"
	)
	var late: CampaignBatch = pair.submit(TreasureCommand.new(1, true, null, BROTHERS))
	_check("treasure: the late take is refused, naming the teammate", (
			late.is_rejected()
			and late.rejected_reason == "seat 0 took %s first" % [BROTHERS_NAME]
			and CampaignLink.name_seats(late.rejected_reason)
			== "Player 1 took %s first" % [BROTHERS_NAME]
			and TreasureChest.is_open(pair.run.seat_run(1))
	), late.rejected_reason)
	var shown: String = other.heirloom_id
	var taken: CampaignBatch = pair.submit(TreasureCommand.new(1, true, null, shown))
	_check("treasure: the teammate takes the replacement it now sees", (
			not taken.is_rejected() and pair.run.seat_run(1).heirloom_ids().has(shown)
			and _replaced_fact(taken) == null
	), taken.rejected_reason)


func _test_key_heirloom() -> void:
	var pair: CampaignSession = _at_results()
	for seat: int in pair.seats:
		var offer: KeyHeirloom = KeyHeirloom.new()
		offer.heirloom_id = BROTHERS
		offer.store(pair.run.seat_run(seat))
	var stream: RngStream = pair.rng.stream(_reward_key(pair.run, 1))
	var golden: String = HeirloomDraw.draw(
			_copy(stream), pair.run.seat_run(1), _catalog,
			ContentIds.HEIRLOOM_UNCOMMON, true, PackedStringArray([BROTHERS])
	)
	var claim: CampaignBatch = pair.submit(KeyHeirloomCommand.new(0, true, BROTHERS))
	var other: KeyHeirloom = KeyHeirloom.pending(pair.run.seat_run(1))
	var replaced: CampaignFact = _replaced_fact(claim)
	_check("key heirloom: the first take wins; the teammate's offer is replaced (golden)", (
			not claim.is_rejected() and other != null and not other.is_resolved
			and other.heirloom_id == golden and other.heirloom_id == GOLDEN_KEY
			and replaced != null and replaced.seat == 1 and replaced.definition_id == golden
	), "%s; %s vs golden %s" % [claim.rejected_reason, other.heirloom_id, golden])
	_test_mirror(pair, claim, "key heirloom")
	_test_continue(pair, "key heirloom", func(run: CampaignRunState) -> String:
		var offer: KeyHeirloom = KeyHeirloom.pending(run.seat_run(1))
		return offer.heirloom_id if offer != null else "no offer"
	)
	var late: CampaignBatch = pair.submit(KeyHeirloomCommand.new(1, true, BROTHERS))
	_check("key heirloom: the late take is refused, naming the teammate", (
			late.is_rejected() and late.rejected_reason == "seat 0 took %s first" % [BROTHERS_NAME]
	), late.rejected_reason)
	var taken: CampaignBatch = pair.submit(KeyHeirloomCommand.new(1, true, other.heirloom_id))
	_check("key heirloom: the teammate takes the replacement", (
			not taken.is_rejected()
			and pair.run.seat_run(1).heirloom_ids().has(other.heirloom_id)
	), taken.rejected_reason)


func _test_starting_offer() -> void:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	for seat: int in pair.seats:
		_family_relic(BROTHERS).store(pair.run.seat_run(seat))
	var stream: RngStream = pair.rng.stream(_starting_key(1))
	var golden: String = StartingOffer.draw_heirloom(
			_copy(stream), pair.run.seat_run(1), _catalog,
			ContentIds.HEIRLOOM_UNCOMMON, true, PackedStringArray([BROTHERS])
	)
	var claim: CampaignBatch = pair.submit(StartingHeirloomCommand.new(0, 0))
	var other: StartingOffer = StartingOffer.pending(pair.run.seat_run(1))
	var drawn: String = other.options[0].drawn_heirloom_id if other != null else ""
	_check("starting offer: Family Relic's claim replaces the teammate's draw (golden)", (
			not claim.is_rejected() and pair.run.seat_run(0).heirloom_ids().has(BROTHERS)
			and not other.is_resolved and drawn == golden and drawn == GOLDEN_STARTING
			and _replaced_fact(claim) != null and _replaced_fact(claim).seat == 1
	), "%s; %s vs golden %s" % [claim.rejected_reason, drawn, golden])
	_test_mirror(pair, claim, "starting offer")
	_test_continue(pair, "starting offer", func(run: CampaignRunState) -> String:
		var offer: StartingOffer = StartingOffer.pending(run.seat_run(1))
		return offer.options[0].drawn_heirloom_id if offer != null else "no offer"
	)
	var taken: CampaignBatch = pair.submit(StartingHeirloomCommand.new(1, 0))
	_check("starting offer: the teammate's hidden draw gives the replacement", (
			not taken.is_rejected() and pair.run.seat_run(1).heirloom_ids().has(drawn)
			and not pair.run.seat_run(1).heirloom_ids().has(BROTHERS)
	), taken.rejected_reason)


func _test_event() -> void:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, CampaignGraph.NodeType.UNKNOWN)
	var event: EventDefinition = _pool.event(BLACK_ALTAR)
	var rolls: Dictionary[int, Array] = {}
	for seat: int in pair.seats:
		var rolled: Array[EventRolls] = EventDraw.roll_seat(
				event, pair.run, seat, RngStream.new(RUN_SEED + seat), _catalog, _rules
		)
		rolled[TOKEN_OPTION].picks[TOKEN_BLOCK] = BROTHERS
		rolls[seat] = rolled
	pair.run.events.open(BLACK_ALTAR, pair.run.floor_number, pair.run.node, pair.seats, rolls)
	var stream: RngStream = pair.rng.stream(RngKey.new(
			RngKey.RngPurpose.EVENT_OUTCOME, pair.run.floor_number, pair.run.node, 1
	))
	var found: PackedStringArray = EventDraw.heirloom_candidates(
			ContentIds.HEIRLOOM_UNCOMMON, pair.run.seat_run(1), PackedStringArray(),
			true, _catalog, PackedStringArray([BROTHERS])
	)
	var golden: String = found[_copy(stream).pick_index(found.size())]
	var claim: CampaignBatch = pair.submit(EventNode.choose(pair, 0, TOKEN_OPTION))
	var pick: String = pair.run.events.seat_event(1).rolls_of(TOKEN_OPTION).pick(TOKEN_BLOCK)
	_check("event: the first choice wins; the teammate's pick is replaced (golden)", (
			not claim.is_rejected() and pair.run.seat_run(0).heirloom_ids().has(BROTHERS)
			and pick == golden and pick == GOLDEN_EVENT
			and _replaced_fact(claim) != null and _replaced_fact(claim).seat == 1
	), "%s; %s vs golden %s" % [claim.rejected_reason, pick, golden])
	_test_mirror(pair, claim, "event")
	var taken: CampaignBatch = pair.submit(EventNode.choose(pair, 1, TOKEN_OPTION))
	_check("event: the teammate's choice gives the replacement", (
			not taken.is_rejected() and pair.run.seat_run(1).heirloom_ids().has(pick)
			and not pair.run.seat_run(1).heirloom_ids().has(BROTHERS)
	), taken.rejected_reason)


# Every main-pool heirloom but Brothers in Arms held by seat 1, so no replacement is left.
func _test_nothing_left() -> void:
	var pair: CampaignSession = _at_treasure()
	_exhaust(pair.run.seat_run(1), HeirloomDraw.TIERS)
	var claim: CampaignBatch = pair.submit(TreasureCommand.new(0, true, null, BROTHERS))
	var chest: TreasureChest = TreasureChest.pending(pair.run.seat_run(1))
	var late: CampaignBatch = pair.submit(TreasureCommand.new(1, true, null, BROTHERS))
	_check("nothing left (treasure): the chest keeps its size and gold, no heirloom", (
			not claim.is_rejected() and chest.heirloom_id.is_empty() and not chest.is_resolved
			and chest.tier == ContentIds.HEIRLOOM_UNCOMMON
			and _replaced_fact(claim) != null and _replaced_fact(claim).definition_id.is_empty()
			and late.rejected_reason == "seat 0 took %s first" % [BROTHERS_NAME]
	), "%s / %s" % [chest.heirloom_id, late.rejected_reason])
	var gold_before: int = pair.run.seat_run(1).gold
	var gold_only: CampaignBatch = pair.submit(TreasureCommand.new(1, true))
	_check("nothing left (treasure): the chest still gives its gold", (
			not gold_only.is_rejected()
			and pair.run.seat_run(1).gold == gold_before + chest.gold
	), gold_only.rejected_reason)

	var key_pair: CampaignSession = _at_results()
	_exhaust(key_pair.run.seat_run(1), HeirloomDraw.TIERS)
	for seat: int in key_pair.seats:
		var offer: KeyHeirloom = KeyHeirloom.new()
		offer.heirloom_id = BROTHERS
		offer.store(key_pair.run.seat_run(seat))
	var key_claim: CampaignBatch = key_pair.submit(KeyHeirloomCommand.new(0, true, BROTHERS))
	var given_up: KeyHeirloom = KeyHeirloom.pending(key_pair.run.seat_run(1))
	var key_late: CampaignBatch = key_pair.submit(KeyHeirloomCommand.new(1, true, BROTHERS))
	# The given-up offer still names the claimed heirloom, so the late take reads as a take of a
	# unique heirloom the teammate owns.
	_check("nothing left (key heirloom): the offer is given up; a late take names the teammate", (
			given_up.is_resolved and not given_up.is_taken
			and _replaced_fact(key_claim) != null
			and _replaced_fact(key_claim).definition_id.is_empty()
			and key_late.rejected_reason == "it is unique, and seat 0 owns it"
	), key_late.rejected_reason)

	var start_pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	_exhaust(start_pair.run.seat_run(1), PackedStringArray([ContentIds.HEIRLOOM_UNCOMMON]))
	for seat: int in start_pair.seats:
		_family_relic(BROTHERS).store(start_pair.run.seat_run(seat))
	start_pair.submit(StartingHeirloomCommand.new(0, 0))
	var refused: StartingOffer = StartingOffer.pending(start_pair.run.seat_run(1))
	var problem: String = StartingOffer.option_problem(
			start_pair.run, 1, refused.options[0], _catalog
	)
	_check("nothing left (Family Relic): no other tier; the option is refused as rolled empty", (
			refused.options[0].drawn_heirloom_id.is_empty()
			and problem == "no Uncommon heirloom is left to draw"
	), problem)


# Q88: no roll offers seat 1 a unique heirloom seat 0 owns; without the owner it does.
func _test_rolls_exclude() -> void:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, CampaignGraph.NodeType.TREASURE)
	var uncommon: EventDefinition = _uncommon_event()
	var seat_run: SeatRun = pair.run.seat_run(1)
	var excluded: PackedStringArray = UniqueClaims.owned_by_teammates(pair.run, 1, _catalog)
	var free_chests: int = _brothers_in_chests(pair)
	var free_picks: int = _brothers_in_picks(pair, uncommon)
	pair.run.seat_run(0).add_heirloom(BROTHERS)
	var owned: PackedStringArray = UniqueClaims.owned_by_teammates(pair.run, 1, _catalog)
	var owned_chests: int = _brothers_in_chests(pair)
	var owned_picks: int = _brothers_in_picks(pair, uncommon)
	var free_keys: int = 0
	var owned_keys: int = 0
	for roll_seed: int in ROLL_SEEDS:
		free_keys += _has(KeyHeirloom.roll(RngStream.new(roll_seed), seat_run, _catalog, true))
		owned_keys += _has(KeyHeirloom.roll(
				RngStream.new(roll_seed), seat_run, _catalog, true, owned
		))
	_check("rolls: a teammate's unique heirloom is excluded from chests, key offers, events", (
			excluded.is_empty() and owned == PackedStringArray([BROTHERS])
			and free_chests > 0 and owned_chests == 0
			and free_keys > 0 and owned_keys == 0
			and free_picks > 0 and owned_picks == 0
	), "chests %d/%d, keys %d/%d, picks %d/%d" % [
		free_chests, owned_chests, free_keys, owned_keys, free_picks, owned_picks,
	])
	var relic_found: bool = false
	for roll_seed: int in ROLL_SEEDS:
		if StartingOffer.draw_heirloom(
				RngStream.new(roll_seed), seat_run, _catalog, ContentIds.HEIRLOOM_UNCOMMON, true,
				PackedStringArray([BROTHERS])
		) == BROTHERS:
			relic_found = true
	_check("rolls: Family Relic's draw never gives an excluded heirloom", not relic_found)


# A stale or staged offer of a unique heirloom a teammate owns: the take is refused by owner.
func _test_owned_take_refused() -> void:
	var pair: CampaignSession = _at_treasure()
	pair.run.seat_run(0).add_heirloom(BROTHERS)
	var chest_take: CampaignBatch = pair.submit(TreasureCommand.new(1, true))
	var start_pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	start_pair.run.seat_run(0).add_heirloom(BROTHERS)
	var offer: StartingOffer = _family_relic(BROTHERS)
	var problem: String = StartingOffer.option_problem(
			start_pair.run, 1, offer.options[0], _catalog
	)
	var owner_says: String = StartingOffer.option_problem(
			start_pair.run, 0, offer.options[0], _catalog
	)
	_check("owned: a unique heirloom a teammate owns can't be taken, in their words", (
			chest_take.rejected_reason == "it is unique, and seat 0 owns it"
			and problem == "it is unique, and seat 0 owns it" and owner_says.is_empty()
	), "%s / %s" % [chest_take.rejected_reason, problem])


func _test_unchanged() -> void:
	var pair: CampaignSession = _at_treasure(WHETSTONE, ContentIds.HEIRLOOM_COMMON)
	var claim: CampaignBatch = pair.submit(TreasureCommand.new(0, true, null, WHETSTONE))
	var other: TreasureChest = TreasureChest.pending(pair.run.seat_run(1))
	var second: CampaignBatch = pair.submit(TreasureCommand.new(1, true, null, WHETSTONE))
	_check("non-unique: both seats take the same heirloom; nothing is replaced", (
			not claim.is_rejected() and _replaced_fact(claim) == null
			and other.heirloom_id == WHETSTONE and not second.is_rejected()
			and pair.run.seat_run(1).heirloom_ids().has(WHETSTONE)
	), "%s / %s" % [claim.rejected_reason, second.rejected_reason])
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	Fixture.enter(solo.run, CampaignGraph.NodeType.TREASURE)
	solo.submit(OpenTreasureCommand.for_session(solo))
	var chest: TreasureChest = TreasureChest.pending(solo.run.seat_run(0))
	chest.heirloom_id = BROTHERS
	chest.item = null
	chest.store(solo.run.seat_run(0))
	var taken: CampaignBatch = solo.submit(TreasureCommand.new(0, true))
	_check("solo: a unique heirloom is taken as any other; no replacement, no exclusions", (
			not taken.is_rejected() and _replaced_fact(taken) == null
			and UniqueClaims.owned_by_teammates(solo.run, 0, _catalog).is_empty()
			and UniqueClaims.offers_to_replace(solo.run, taken.facts, _catalog).is_empty()
	), taken.rejected_reason)
	var wire: TreasureCommand = CampaignCommand.from_wire(
			_through_json_array(TreasureCommand.new(1, true, null, BROTHERS).to_wire())
	) as TreasureCommand
	var key_wire: KeyHeirloomCommand = CampaignCommand.from_wire(
			_through_json_array(KeyHeirloomCommand.new(1, true, BROTHERS).to_wire())
	) as KeyHeirloomCommand
	_check("wire: the expected heirloom travels with both takes", (
			wire != null and wire.expected_heirloom_id == BROTHERS
			and key_wire != null and key_wire.expected_heirloom_id == BROTHERS
	))


# ASSUMPTION: no campaign mirror or campaign hash exists before P10 NT5, so the mirror is a run
# rebuilt from the host's saved sections, and the hash is of every section's capture; the batch
# applies to it as presentation does, off the wire through JSON.
func _test_mirror(host: CampaignSession, batch: CampaignBatch, label: String) -> void:
	var mirror: CampaignRunState = _restored(host.run)
	var wired: CampaignBatch = CampaignBatch.from_wire(_through_json_array(batch.to_wire()))
	var same_facts: bool = wired != null and wired.facts.size() == batch.facts.size()
	if same_facts:
		for index: int in batch.facts.size():
			var sent: Array = batch.facts[index].to_wire()
			same_facts = same_facts and wired.facts[index].to_wire() == sent
	var replaced: CampaignFact = _replaced_fact(wired) if wired != null else null
	var case_name: String = (
			"%s: a mirror from the saved sections matches the host; the batch's wire form keeps"
			+ " the replacement"
	)
	_check(case_name % [label], (
			mirror != null and _run_hash(mirror) == _run_hash(host.run)
			and same_facts and replaced != null
	), "%s" % [Fixture.kinds(wired) if wired != null else "no batch"])


# A quit and Continue: the restored run shows the teammate's replaced offer, and its stream
# continues where the host's does.
func _test_continue(host: CampaignSession, label: String, offered: Callable) -> void:
	var restored: CampaignRunState = _restored(host.run)
	var streams: RngStreams = RngStreams.new(RUN_SEED)
	var is_read: bool = streams.restore_campaign(Fixture.json(host.rng.capture_campaign()))
	var same_streams: bool = is_read and streams.capture_campaign() == host.rng.capture_campaign()
	var shown: String = offered.call(host.run)
	var continued: String = offered.call(restored) if restored != null else "not restored"
	_check("%s: a quit and Continue keeps the replacement and its stream's place" % [label], (
			restored != null and continued == shown and same_streams
	), "%s vs %s" % [continued, shown])


func _at_treasure(
		heirloom_id: String = BROTHERS, tier: String = ContentIds.HEIRLOOM_UNCOMMON
) -> CampaignSession:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, CampaignGraph.NodeType.TREASURE)
	pair.submit(OpenTreasureCommand.for_session(pair))
	for seat: int in pair.seats:
		var chest: TreasureChest = TreasureChest.pending(pair.run.seat_run(seat))
		chest.tier = tier
		chest.item = null
		chest.heirloom_id = heirloom_id
		chest.store(pair.run.seat_run(seat))
	return pair


func _at_results() -> CampaignSession:
	var pair: CampaignSession = Fixture.session(RUN_SEED, 2)
	Fixture.enter(pair.run, CampaignGraph.NodeType.KEY)
	pair.run.flow.stage = RunFlow.Stage.RESULTS
	return pair


func _family_relic(drawn: String) -> StartingOffer:
	var offer: StartingOffer = StartingOffer.new()
	var option: StartingOffer.Option = StartingOffer.Option.new(FAMILY_RELIC)
	option.drawn_heirloom_id = drawn
	offer.options.append(option)
	return offer


# An event of one option whose one block draws an Uncommon heirloom: no shipped event does.
func _uncommon_event() -> EventDefinition:
	var block: HeirloomOutcome = HeirloomOutcome.new()
	block.tier = ContentIds.HEIRLOOM_UNCOMMON
	var option: EventOption = EventOption.new()
	option.outcomes.append(block)
	var event: EventDefinition = EventDefinition.new()
	event.id = "unique_claim_test"
	event.options.append(option)
	return event


# How many of ROLL_SEEDS chest rolls by OpenTreasureCommand give seat 1 Brothers in Arms.
func _brothers_in_chests(pair: CampaignSession) -> int:
	var command: OpenTreasureCommand = OpenTreasureCommand.for_session(pair)
	var count: int = 0
	for roll_seed: int in ROLL_SEEDS:
		for seat: int in pair.seats:
			pair.run.seat_run(seat).pending_offers.erase(TreasureChest.OFFER_KEY)
			command.streams[seat] = RngStream.new(roll_seed * 2 + seat)
		command.resolve(pair.run)
		var chest: TreasureChest = TreasureChest.pending(pair.run.seat_run(1))
		count += 1 if chest.heirloom_id == BROTHERS else 0
	for seat: int in pair.seats:
		pair.run.seat_run(seat).pending_offers.erase(TreasureChest.OFFER_KEY)
	return count


# How many of ROLL_SEEDS rolls of event give seat 1 Brothers in Arms in its one pick.
func _brothers_in_picks(pair: CampaignSession, event: EventDefinition) -> int:
	var count: int = 0
	for roll_seed: int in ROLL_SEEDS:
		var rolled: Array[EventRolls] = EventDraw.roll_seat(
				event, pair.run, 1, RngStream.new(roll_seed), _catalog, _rules
		)
		count += 1 if rolled[0].pick(0) == BROTHERS else 0
	return count


# Gives seat_run every heirloom of tiers it may be offered in co-op, but Brothers in Arms.
func _exhaust(seat_run: SeatRun, tiers: PackedStringArray) -> void:
	for heirloom_id: String in HeirloomDraw.candidates(seat_run, _catalog, tiers, true):
		if heirloom_id != BROTHERS:
			seat_run.add_heirloom(heirloom_id)


func _restored(run: CampaignRunState) -> CampaignRunState:
	var restored: CampaignRunState = Fixture.through_json(run)
	if restored == null:
		return null
	if restored.events.restore(Fixture.json(run.events.capture())) != OK:
		return null
	return restored


# Every saved section of run as the save file holds it (through JSON, so the free-form pending
# offers' whole numbers read alike on both sides), hashed with sorted keys.
func _run_hash(run: CampaignRunState) -> int:
	var parts: Dictionary = {
		"map": run.capture_map(),
		"flow": run.flow.capture(),
		"events": run.events.capture(),
	}
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		parts["seat %d" % [seat]] = [
			seat_run.capture_roster(), seat_run.capture_heirlooms(), seat_run.capture_runes(),
			seat_run.capture_economy(),
		]
	return hash(JSON.stringify(Fixture.json(parts), "", true))


func _replaced_fact(batch: CampaignBatch) -> CampaignFact:
	for fact: CampaignFact in batch.facts:
		if fact.kind == CampaignFact.Kind.HEIRLOOM_OFFER_REPLACED:
			return fact
	return null


func _index_of(batch: CampaignBatch, kind: CampaignFact.Kind) -> int:
	for index: int in batch.facts.size():
		if batch.facts[index].kind == kind:
			return index
	return -1


func _tier_of(heirloom_id: String) -> String:
	var heirloom: HeirloomDefinition = _catalog.heirloom(heirloom_id)
	return heirloom.tier if heirloom != null else ""


func _has(offer: KeyHeirloom) -> int:
	return 1 if offer != null and offer.heirloom_id == BROTHERS else 0


func _reward_key(run: CampaignRunState, seat: int) -> RngKey:
	return RngKey.new(RngKey.RngPurpose.REWARD, run.floor_number, run.node, seat)


func _starting_key(seat: int) -> RngKey:
	return RngKey.new(RngKey.RngPurpose.STARTING_OFFER, -1, -1, seat)


func _copy(stream: RngStream) -> RngStream:
	var copy: RngStream = RngStream.new(0)
	copy.restore(stream.capture())
	return copy


func _through_json_array(data: Array) -> Array:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed if parsed is Array else []


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
