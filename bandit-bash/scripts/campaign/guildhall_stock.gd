# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_stock.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name GuildhallStock
extends RefCounted
## One Guildhall visit's stock, shared by every seat (game-vision.md, Campaign nodes and Co-op
## ownership), and each seat's prefix re-rolls this visit. Each entry sells once, to the first
## confirmed purchase ([Guildhall]).
##
## [method roll] draws it all from the node's shared [code]SHOP_STOCK[/code] stream, in order: per
## recruit a unit type not yet offered (evenly, [method RecruitOffer.pool]) and its prefix at the
## recruit odds ([method UnitPrefixDefinition.roll]), then per rune one not yet stocked, evenly. A
## recruit is kept at level 1; [method Guildhall.recruit_for] levels it for the seat that views or
## buys it. Ids are minted at the roll. Saved in [member RunFlow.shop_stock] under
## [constant OFFER_KEY] when the Guildhall opens ([OpenGuildhallCommand]), cleared on leaving.
## Pure rules code.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The key of the stock in [member RunFlow.shop_stock].
const OFFER_KEY: String = "guildhall"

## An entry's category: a recruit.
const CATEGORY_RECRUIT: String = "recruit"
## An entry's category: a rune.
const CATEGORY_RUNE: String = "rune"

## Recruits offered per visit in solo (game-vision.md, Guildhall). [b]Units:[/b] recruits.
const RECRUITS: int = 3

## Runes offered per visit in solo (game-vision.md, Guildhall). [b]Units:[/b] runes.
const RUNES: int = 2

## Entries each seat past the first adds to the recruits and to the runes (game-vision.md, Co-op
## ownership). [b]Units:[/b] entries.
const EXTRA_PER_SEAT: int = 1

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_ENTRIES: String = "entries"
const _KEY_CATEGORY: String = "category"
const _KEY_RECRUIT: String = "recruit"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_INSTANCE: String = "instance_id"
const _KEY_BUYER: String = "buyer"
const _KEY_REROLLS: String = "rerolls"
const _KEY_FREE: String = "free"
const _KEY_PAID: String = "paid"

## Everything stocked: the recruits, then the runes.
var entries: Array[Entry] = []

## Each seat's prefix re-rolls this visit, by seat; a seat with none has no entry.
var rerolls: Dictionary[int, Rerolls] = {}


## Writes this stock to [param run]'s shared shop stock, replacing any there.
func store(run: CampaignRunState) -> void:
	run.flow.shop_stock[OFFER_KEY] = capture()


## The indexes in [member entries] of [param category]'s entries, in order.
func indexes_of(category: String) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for index: int in entries.size():
		if entries[index].category == category:
			found.append(index)
	return found


## Seat [param seat]'s re-rolls this visit; a fresh, unsaved count of none when it has made none.
func rerolls_of(seat: int) -> Rerolls:
	return rerolls.get(seat, Rerolls.new())


## The stock as plain JSON.
func capture() -> Dictionary:
	var written: Array = []
	for entry: Entry in entries:
		var entry_data: Dictionary = {
			_KEY_CATEGORY: entry.category,
			_KEY_BUYER: entry.buyer,
		}
		if entry.is_recruit():
			entry_data[_KEY_RECRUIT] = entry.recruit.capture()
		else:
			entry_data[_KEY_DEFINITION] = entry.definition_id
			entry_data[_KEY_INSTANCE] = entry.instance_id
		written.append(entry_data)
	var counts: Dictionary = {}
	var seats: Array[int] = []
	seats.assign(rerolls.keys())
	seats.sort()
	for seat: int in seats:
		counts[str(seat)] = {_KEY_FREE: rerolls[seat].free, _KEY_PAID: rerolls[seat].paid}
	return {_KEY_ENTRIES: written, _KEY_REROLLS: counts}


## A new stock for [param run]'s seats from [param stream] (see the class doc), ids minted from
## [param ids]. Recruits: [constant RECRUITS], plus every seat's
## [constant CampaignValue.Key.GUILDHALL_RECRUITS] (Guild Charter), plus [constant EXTRA_PER_SEAT]
## per extra seat; runes: [constant RUNES] plus the same per extra seat. Fewer when a pool runs out.
static func roll(
		stream: RngStream,
		run: CampaignRunState,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> GuildhallStock:
	var stock: GuildhallStock = GuildhallStock.new()
	var extra: int = maxi(run.seat_numbers().size() - 1, 0) * EXTRA_PER_SEAT
	var types: PackedStringArray = RecruitOffer.pool(catalog)
	for _recruit: int in RECRUITS + extra_recruits(run, catalog) + extra:
		if types.is_empty():
			break
		var type_id: String = types[stream.pick_index(types.size())]
		types.remove_at(types.find(type_id))
		var prefix_id: String = UnitPrefixDefinition.roll(stream, catalog)
		var made: RecruitOffer = RecruitOffer.make(catalog, type_id, prefix_id, 1, ids)
		if made != null:
			var entry: Entry = Entry.new(CATEGORY_RECRUIT)
			entry.recruit = made
			entry.definition_id = type_id
			entry.instance_id = made.unit.instance_id
			stock.entries.append(entry)
	var stocked: PackedStringArray = []
	for _rune: int in RUNES + extra:
		var rune_id: String = _draw_rune(stream, catalog, stocked)
		if rune_id.is_empty():
			break
		stocked.append(rune_id)
		var entry: Entry = Entry.new(CATEGORY_RUNE)
		entry.definition_id = rune_id
		entry.instance_id = ids.next_rune_id(catalog.rune(rune_id).display_name)
		stock.entries.append(entry)
	return stock


## The extra recruits every seat's [constant CampaignValue.Key.GUILDHALL_RECRUITS] adds (Guild
## Charter), each seat's rounded and never below 0. [b]Units:[/b] recruits.
static func extra_recruits(run: CampaignRunState, catalog: EffectCatalog.Index) -> int:
	var count: int = 0
	for seat: int in run.seat_numbers():
		var value: float = RunOperations.campaign_value(
				run.seat_run(seat), catalog, CampaignValue.Key.GUILDHALL_RECRUITS
		)
		count += maxi(roundi(value), 0)
	return count


## [param run]'s stock waiting in its shared shop stock; null when none is rolled, or its data is
## unusable (reported).
static func pending(run: CampaignRunState) -> GuildhallStock:
	if run == null:
		return null
	var data: Variant = run.flow.shop_stock.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: GuildhallStock = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("GuildhallStock: the Guildhall's stock is unusable - %s" % [data])
	return read


## The stock [param data] describes, as [method capture] wrote it, numbers as whole floats too;
## null for an unknown category, a recruit [method RecruitOffer.restore] refuses, a rune without
## its ids, a buyer below [constant Entry.NOT_SOLD] or a re-roll count below 0.
static func restore(data: Dictionary) -> GuildhallStock:
	var written: Variant = data.get(_KEY_ENTRIES)
	var counts: Variant = data.get(_KEY_REROLLS, {})
	if not written is Array or not counts is Dictionary:
		return null
	var stock: GuildhallStock = GuildhallStock.new()
	for value: Variant in written as Array:
		var entry: Entry = Entry.restore(value as Dictionary) if value is Dictionary else null
		if entry == null:
			return null
		stock.entries.append(entry)
	for key: Variant in counts as Dictionary:
		var count_data: Variant = (counts as Dictionary)[key]
		if not str(key).is_valid_int() or not count_data is Dictionary:
			return null
		var free: Variant = CampaignRunState.whole_number((count_data as Dictionary).get(_KEY_FREE))
		var paid: Variant = CampaignRunState.whole_number((count_data as Dictionary).get(_KEY_PAID))
		if free == null or paid == null or (free as int) < 0 or (paid as int) < 0:
			return null
		var made: Rerolls = Rerolls.new()
		made.free = free as int
		made.paid = paid as int
		stock.rerolls[str(key).to_int()] = made
	return stock


# One rune id from stream, evenly among the runes not in stocked (id order); every rune once all
# are stocked; empty, drawing nothing, when the catalog has none.
static func _draw_rune(
		stream: RngStream, catalog: EffectCatalog.Index, stocked: PackedStringArray
) -> String:
	var all_ids: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.RUNE):
		var rune: RuneDefinition = resource as RuneDefinition
		if rune != null:
			all_ids.append(rune.id)
	all_ids.sort()
	var left: PackedStringArray = []
	for rune_id: String in all_ids:
		if not stocked.has(rune_id):
			left.append(rune_id)
	if left.is_empty():
		left = all_ids
	if left.is_empty():
		return ""
	return left[stream.pick_index(left.size())]


## One stocked recruit or rune.
class Entry:
	extends RefCounted

	## [member buyer] while nobody has bought it.
	const NOT_SOLD: int = -1

	## [constant GuildhallStock.CATEGORY_RECRUIT] or [constant GuildhallStock.CATEGORY_RUNE].
	var category: String = ""
	## A recruit's unit type id, or a rune's [RuneDefinition] id.
	var definition_id: String = ""
	## The id minted at the roll: the recruit's unit, or the rune's.
	var instance_id: String = ""
	## A recruit at level 1 with its prefix and starting weapon; null for a rune.
	var recruit: RecruitOffer = null
	## The seat that bought it; [constant NOT_SOLD] while it is for sale.
	var buyer: int = NOT_SOLD

	func _init(entry_category: String = "") -> void:
		category = entry_category

	## Whether it is a recruit.
	func is_recruit() -> bool:
		return category == GuildhallStock.CATEGORY_RECRUIT

	## Whether a seat bought it.
	func is_sold() -> bool:
		return buyer != NOT_SOLD

	## The entry [param data] describes, as [method GuildhallStock.capture] wrote it; null when
	## anything is missing or unusable.
	static func restore(data: Dictionary) -> Entry:
		var read_category: Variant = data.get(_KEY_CATEGORY)
		var read_buyer: Variant = CampaignRunState.whole_number(data.get(_KEY_BUYER))
		if read_buyer == null or (read_buyer as int) < NOT_SOLD:
			return null
		var entry: Entry = null
		if read_category == GuildhallStock.CATEGORY_RECRUIT:
			var recruit_data: Variant = data.get(_KEY_RECRUIT)
			var made: RecruitOffer = (
					RecruitOffer.restore(recruit_data as Dictionary) if recruit_data is Dictionary
					else null
			)
			if made == null:
				return null
			entry = Entry.new(GuildhallStock.CATEGORY_RECRUIT)
			entry.recruit = made
			entry.definition_id = made.unit.unit_type_id
			entry.instance_id = made.unit.instance_id
		elif read_category == GuildhallStock.CATEGORY_RUNE:
			var rune_id: Variant = data.get(_KEY_DEFINITION)
			var instance: Variant = data.get(_KEY_INSTANCE)
			if (
					not rune_id is String or (rune_id as String).is_empty()
					or not instance is String or (instance as String).is_empty()
			):
				return null
			entry = Entry.new(GuildhallStock.CATEGORY_RUNE)
			entry.definition_id = rune_id as String
			entry.instance_id = instance as String
		else:
			return null
		entry.buyer = read_buyer as int
		return entry


## One seat's prefix re-rolls at this visit.
class Rerolls:
	extends RefCounted

	## Free re-rolls used ([constant CampaignValue.Key.FREE_REROLLS]). [b]Units:[/b] re-rolls.
	var free: int = 0
	## Paid re-rolls made; each raises the next one's price. [b]Units:[/b] re-rolls.
	var paid: int = 0
