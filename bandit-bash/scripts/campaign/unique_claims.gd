# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unique_claims.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name UniqueClaims
extends RefCounted
## A unique heirloom's first claim outside the Armory (game-vision.md, Co-op ownership): the first
## take wins, and every teammate's open offer of it is replaced at once by another heirloom of the
## same tier, from the stream that offer came from.
##
## [method offers_to_replace] finds, for each [constant CampaignFact.Kind.GAINED] of a unique
## heirloom in a batch ([method ArmoryStock.unique_owner], the one test of "unique and owned"),
## every other seat's open offer of it: a chest, a key combat's heirloom, Family Relic's draw, an
## open event's pick. [method replace] draws each from its stream ([method stream_key]) and saves
## it where the offer is: [constant CampaignFact.Kind.HEIRLOOM_OFFER_REPLACED]. [CampaignSession]
## runs both after every resolved command; the Armory restocks its own slot. Pure and static.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## Where an open offer is saved.
enum Source {
	## The seat's [TreasureChest].
	TREASURE,
	## The seat's [KeyHeirloom].
	KEY_HEIRLOOM,
	## An option of the seat's [StartingOffer]: Family Relic's drawn heirloom.
	STARTING_OFFER,
	## A tier heirloom pick of the open event's [EventRolls], for a seat that hasn't chosen.
	EVENT,
}


## The unique heirlooms seats other than [param seat] own, sorted: what no offer to
## [param seat] may hold. Empty in solo.
static func owned_by_teammates(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var found: PackedStringArray = []
	for other: int in run.seat_numbers():
		if other == seat:
			continue
		for heirloom_id: String in run.seat_run(other).heirloom_ids():
			if found.has(heirloom_id):
				continue
			if ArmoryStock.unique_owner(run, catalog, heirloom_id) != CampaignFact.NO_SEAT:
				found.append(heirloom_id)
	found.sort()
	return found


## Why seat [param seat] can't take the offered [param heirloom_id] (empty: the offer holds none),
## whose take expects [param expected_id] (empty: no check): the offer no longer holds the expected
## one ("seat N took X first" when a teammate claimed it), or it is unique and a teammate owns it.
## Empty when neither.
static func take_problem(
		run: CampaignRunState,
		seat: int,
		heirloom_id: String,
		expected_id: String,
		catalog: EffectCatalog.Index
) -> String:
	if not expected_id.is_empty() and expected_id != heirloom_id:
		var claimant: int = ArmoryStock.unique_owner(run, catalog, expected_id)
		if claimant != CampaignFact.NO_SEAT and claimant != seat:
			return "seat %d took %s first" % [claimant, _name_of(catalog, expected_id)]
		return "the offer no longer holds %s" % [_name_of(catalog, expected_id)]
	if heirloom_id.is_empty():
		return ""
	var owner: int = ArmoryStock.unique_owner(run, catalog, heirloom_id)
	if owner != CampaignFact.NO_SEAT and owner != seat:
		return "it is unique, and seat %d owns it" % [owner]
	return ""


## Every open offer to replace after [param facts]: for each GAINED of a unique heirloom, every
## other seat's open offer of it, in fact, seat, then source order (an event's options and blocks
## ascending). Empty in solo. Changes nothing.
static func offers_to_replace(
		run: CampaignRunState, facts: Array[CampaignFact], catalog: EffectCatalog.Index
) -> Array[Offer]:
	var found: Array[Offer] = []
	if run.seat_numbers().size() < 2:
		return found
	for fact: CampaignFact in facts:
		if fact.kind != CampaignFact.Kind.GAINED or fact.definition_id.is_empty():
			continue
		if ArmoryStock.unique_owner(run, catalog, fact.definition_id) == CampaignFact.NO_SEAT:
			continue
		for seat: int in run.seat_numbers():
			# ASSUMPTION: the claimant's own other open offers of it stay, as a second copy is
			# allowed (game-vision.md: copies stack); only teammates' are replaced.
			if seat != fact.seat:
				_add_open_offers(run, seat, fact.definition_id, fact.seat, found)
	return found


## The key of the stream [param offer] was rolled from, at [param run]'s node: the seat's
## [code]REWARD[/code] stream for a chest or a key heirloom, its run-level
## [code]STARTING_OFFER[/code] stream, or its [code]EVENT_OUTCOME[/code] stream for an event.
static func stream_key(run: CampaignRunState, offer: Offer) -> RngKey:
	match offer.source:
		Source.STARTING_OFFER:
			return RngKey.new(RngKey.RngPurpose.STARTING_OFFER, -1, -1, offer.seat)
		Source.EVENT:
			return RngKey.new(
					RngKey.RngPurpose.EVENT_OUTCOME, run.floor_number, run.node, offer.seat
			)
	return RngKey.new(RngKey.RngPurpose.REWARD, run.floor_number, run.node, offer.seat)


## Replaces [param offer] with another heirloom drawn from [param stream] by the offer's own roll
## rule, none owned by a teammate: a chest's tier or a key heirloom's, then the whole main pool
## ([method HeirloomDraw.draw]); Family Relic's or the event pick's tier only. With nothing left,
## a chest holds no heirloom, the starting or event option is refused, and a key heirloom is given
## up. Saved in the offer; records HEIRLOOM_OFFER_REPLACED. Nothing when the offer has gone.
static func replace(
		run: CampaignRunState, offer: Offer, stream: RngStream, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(offer.seat)
	var heirloom: HeirloomDefinition = catalog.heirloom(offer.heirloom_id)
	if seat_run == null or heirloom == null or stream == null:
		return
	var is_coop: bool = run.seat_numbers().size() > 1
	var excluded: PackedStringArray = owned_by_teammates(run, offer.seat, catalog)
	var drawn: String = ""
	match offer.source:
		Source.TREASURE:
			var chest: TreasureChest = TreasureChest.pending(seat_run)
			if chest == null:
				return
			drawn = HeirloomDraw.draw(stream, seat_run, catalog, chest.tier, is_coop, excluded)
			chest.heirloom_id = drawn
			chest.store(seat_run)
		Source.KEY_HEIRLOOM:
			var key: KeyHeirloom = KeyHeirloom.pending(seat_run)
			if key == null:
				return
			drawn = HeirloomDraw.draw(stream, seat_run, catalog, heirloom.tier, is_coop, excluded)
			if drawn.is_empty():
				# A stored offer always names its heirloom, so the claimed one stays, given up.
				key.is_resolved = true
				key.is_taken = false
			else:
				key.heirloom_id = drawn
			key.store(seat_run)
		Source.STARTING_OFFER:
			var start: StartingOffer = StartingOffer.pending(seat_run)
			if start == null or offer.option >= start.options.size():
				return
			var option: StartingOffer.Option = start.options[offer.option]
			var definition: StartingHeirloomDefinition = StartingOffer.definition_of(
					option, catalog
			)
			if definition == null:
				return
			drawn = StartingOffer.draw_heirloom(
					stream, seat_run, catalog, definition.heirloom_tier, is_coop, excluded
			)
			option.drawn_heirloom_id = drawn
			start.store(seat_run)
		Source.EVENT:
			var part: EventRunState.SeatEvent = run.events.seat_event(offer.seat)
			if part == null or offer.option >= part.rolls.size():
				return
			var rolls: EventRolls = part.rolls[offer.option]
			drawn = _event_pick(
					stream, rolls, offer, seat_run, heirloom.tier, is_coop, excluded, catalog
			)
			rolls.picks[offer.block] = drawn
	var replaced: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.HEIRLOOM_OFFER_REPLACED, offer.seat
	)
	replaced.definition_id = drawn
	replaced.amount = offer.claimant
	run.record(replaced)


# Appends to found each open offer of heirloom_id to seat, claimed by claimant.
static func _add_open_offers(
		run: CampaignRunState,
		seat: int,
		heirloom_id: String,
		claimant: int,
		found: Array[Offer]
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	var chest: TreasureChest = TreasureChest.pending(seat_run)
	if chest != null and not chest.is_resolved and chest.heirloom_id == heirloom_id:
		_add(found, Offer.new(seat, Source.TREASURE, heirloom_id, claimant))
	var key: KeyHeirloom = KeyHeirloom.pending(seat_run)
	if key != null and not key.is_resolved and key.heirloom_id == heirloom_id:
		_add(found, Offer.new(seat, Source.KEY_HEIRLOOM, heirloom_id, claimant))
	var start: StartingOffer = StartingOffer.pending(seat_run)
	if start != null and not start.is_resolved:
		for index: int in start.options.size():
			if start.options[index].drawn_heirloom_id == heirloom_id:
				_add(found, Offer.new(seat, Source.STARTING_OFFER, heirloom_id, claimant, index))
	var part: EventRunState.SeatEvent = run.events.seat_event(seat)
	if (
			part == null or part.chosen != EventRunState.NO_OPTION
			or not run.events.is_open_at(run.floor_number, run.node)
	):
		return
	for option: int in part.rolls.size():
		var picks: Dictionary[int, String] = part.rolls[option].picks
		var blocks: Array[int] = []
		blocks.assign(picks.keys())
		blocks.sort()
		for block: int in blocks:
			if picks[block] == heirloom_id:
				_add(found, Offer.new(
						seat, Source.EVENT, heirloom_id, claimant, option, block
				))


# Appends offer unless found already holds the same one (one heirloom gained twice in a batch).
static func _add(found: Array[Offer], offer: Offer) -> void:
	for each: Offer in found:
		if each.is_same_offer(offer):
			return
	found.append(offer)


# The event pick's replacement: one of tier the seat may be given, none of the option's other
# picks, as EventDraw draws them (one candidate draws nothing); empty for none.
static func _event_pick(
		stream: RngStream,
		rolls: EventRolls,
		offer: Offer,
		seat_run: SeatRun,
		tier: String,
		is_coop: bool,
		excluded: PackedStringArray,
		catalog: EffectCatalog.Index
) -> String:
	var others: PackedStringArray = []
	for block: int in rolls.picks:
		if block != offer.block and not rolls.picks[block].is_empty():
			others.append(rolls.picks[block])
	var found: PackedStringArray = EventDraw.heirloom_candidates(
			tier, seat_run, others, is_coop, catalog, excluded
	)
	if found.is_empty():
		return ""
	return found[0 if found.size() == 1 else stream.pick_index(found.size())]


static func _name_of(catalog: EffectCatalog.Index, heirloom_id: String) -> String:
	var heirloom: HeirloomDefinition = catalog.heirloom(heirloom_id)
	return heirloom.display_name if heirloom != null else heirloom_id


## One open offer of a claimed unique heirloom to a seat.
class Offer:
	extends RefCounted

	## [member option] and [member block] when the source has none.
	const NONE: int = -1

	## The seat the offer is to.
	var seat: int = CampaignFact.NO_SEAT
	## Where the offer is saved.
	var source: UniqueClaims.Source = UniqueClaims.Source.TREASURE
	## Content id of the unique heirloom it holds, which [member claimant] gained.
	var heirloom_id: String = ""
	## The seat that took the heirloom first.
	var claimant: int = CampaignFact.NO_SEAT
	## The starting offer's option, or the event's option index; [constant NONE] otherwise.
	var option: int = NONE
	## The event option's block index; [constant NONE] otherwise.
	var block: int = NONE

	func _init(
			offer_seat: int = CampaignFact.NO_SEAT,
			offer_source: UniqueClaims.Source = UniqueClaims.Source.TREASURE,
			offered_id: String = "",
			claimed_by: int = CampaignFact.NO_SEAT,
			option_index: int = NONE,
			block_index: int = NONE
	) -> void:
		seat = offer_seat
		source = offer_source
		heirloom_id = offered_id
		claimant = claimed_by
		option = option_index
		block = block_index

	## Whether [param other] is the same offer: seat, source, option and block.
	func is_same_offer(other: Offer) -> bool:
		return (
				other.seat == seat and other.source == source and other.option == option
				and other.block == block
		)
