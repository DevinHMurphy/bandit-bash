# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_heirloom.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name KeyHeirloom
extends RefCounted
## One seat's heirloom from a won Key combat (game-vision.md, Campaign nodes: "one random
## heirloom, rolled Common 50 / Uncommon 33 / Rare 17"), by the same draw as a Treasure chest's
## ([HeirloomDraw]).
##
## [method roll] draws from the seat's [code]REWARD[/code] stream straight after its item pick
## ([method CampaignRunState.apply_battle]); it is saved in the seat's
## [member SeatRun.pending_offers] under [constant OFFER_KEY] with the combat's report and shown
## on Results. [KeyHeirloomCommand] takes it or gives it up; the run leaves the node only once it
## is resolved. A unique heirloom a teammate takes first is replaced in it ([UniqueClaims]). Pure
## rules code.
##
## @tutorial(Heirlooms, Tiers and sources): docs/design/heirlooms.md

## The key of the offer in [member SeatRun.pending_offers].
const OFFER_KEY: String = "key_heirloom"

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_HEIRLOOM: String = "heirloom_id"
const _KEY_RESOLVED: String = "is_resolved"
const _KEY_TAKEN: String = "is_taken"

## Content id of the heirloom offered; never empty in a stored offer.
var heirloom_id: String = ""

## Whether the seat took it or gave it up.
var is_resolved: bool = false

## Whether the seat took it; false while open or after giving it up.
var is_taken: bool = false


## Writes this offer to [param seat_run]'s pending offers, replacing any there.
func store(seat_run: SeatRun) -> void:
	seat_run.pending_offers[OFFER_KEY] = capture()


## The offer as plain JSON.
func capture() -> Dictionary:
	return {_KEY_HEIRLOOM: heirloom_id, _KEY_RESOLVED: is_resolved, _KEY_TAKEN: is_taken}


## A new offer for [param seat_run] from [param stream]: a tier, then a heirloom of it
## ([HeirloomDraw]), never one of [param excluded] (a unique one a teammate owns);
## [param is_coop] admits co-op-only heirlooms. Null when no heirloom is left.
static func roll(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		is_coop: bool,
		excluded: PackedStringArray = PackedStringArray()
) -> KeyHeirloom:
	var tier: String = HeirloomDraw.roll_tier(stream)
	var drawn: String = HeirloomDraw.draw(stream, seat_run, catalog, tier, is_coop, excluded)
	if drawn.is_empty():
		return null
	var offer: KeyHeirloom = KeyHeirloom.new()
	offer.heirloom_id = drawn
	return offer


## [param seat_run]'s offer in its pending offers; null when it has none or its data is unusable
## (reported).
static func pending(seat_run: SeatRun) -> KeyHeirloom:
	if seat_run == null:
		return null
	var data: Variant = seat_run.pending_offers.get(OFFER_KEY, null)
	if data == null:
		return null
	var read: KeyHeirloom = restore(data as Dictionary) if data is Dictionary else null
	if read == null:
		push_error("KeyHeirloom: seat %d's offer is unusable - %s" % [seat_run.seat, data])
	return read


## Whether [param seat_run] has an offer it hasn't taken or given up.
static func is_open(seat_run: SeatRun) -> bool:
	var offer: KeyHeirloom = pending(seat_run)
	return offer != null and not offer.is_resolved


## The offer [param data] describes, as [method capture] wrote it; null for one without a
## heirloom or with a field of the wrong type.
static func restore(data: Dictionary) -> KeyHeirloom:
	var read_heirloom: Variant = data.get(_KEY_HEIRLOOM)
	var resolved: Variant = data.get(_KEY_RESOLVED)
	var taken: Variant = data.get(_KEY_TAKEN)
	if (
			not read_heirloom is String or (read_heirloom as String).is_empty()
			or not resolved is bool or not taken is bool
	):
		return null
	var offer: KeyHeirloom = KeyHeirloom.new()
	offer.heirloom_id = read_heirloom as String
	offer.is_resolved = resolved as bool
	offer.is_taken = taken as bool
	return offer
