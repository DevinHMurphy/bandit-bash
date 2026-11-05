# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name MovePreview
extends RefCounted
## What moving a selected unit to a hovered tile would mean, before any action: the darkness damage
## it would take ending its phase there ([method Darkness.damage_at]) and the enemies' intents
## re-planned for it ([method Intents.preview]), with which enemies' intents differ from the
## current ones (combat UI plan, question 9).
##
## A preview costs about a tenth of a second in a debug build (enemies and AI plan, question 23),
## so it runs off the input path: hovering only [method Queue.request]s one, and
## [BattleController] runs at most one per frame ([method Queue.run_pending]), on the main thread,
## for the newest hover. Hovers in between are dropped. Reading only: both queries run on
## sandboxes. [MovePreviewMarks] draws it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The unit previewed.
var unit_id: String = ""

## The tile it would end its move on.
var tile: Vector2i = CombatFact.NO_TILE

## The HP it would lose to the darkness ending its phase on [member tile]; 0 on a dry tile.
var darkness_damage: int = 0

## The enemies' intents with the unit on [member tile]; null when the session keeps none (before
## turn 1's Phase Start, outside the player phase).
var intents: Intents = null

## Every enemy whose intent on [member tile] differs from the session's current one (see
## [method intent_differs]), in state order.
var changed_enemies: PackedStringArray = []

## [method CombatSession.last_seq] when it was computed: any newer fact makes it stale.
var based_on_seq: int = Command.NO_SEQ


## The preview of [param unit_id] ending its move on [param tile] on [param session] now.
static func compute(session: CombatSession, unit_id: String, tile: Vector2i) -> MovePreview:
	var found: MovePreview = MovePreview.new()
	found.unit_id = unit_id
	found.tile = tile
	found.based_on_seq = session.last_seq()
	found.darkness_damage = Darkness.damage_at(session.engine, unit_id, tile)
	found.intents = Intents.preview(session, unit_id, tile)
	var current: Intents = session.intents
	if found.intents == null or current == null:
		return found
	for enemy_id: String in session.state.units_of(CombatFact.CombatSide.ENEMY):
		if intent_differs(current.intent_of(enemy_id), found.intents.intent_of(enemy_id)):
			found.changed_enemies.append(enemy_id)
	return found


## Whether an enemy's intent [param after] the move differs from [param before] it, as the board
## marks it: one acts and the other doesn't, or its icon, target, tile or place in the order
## changed.
static func intent_differs(before: EnemyIntent, after: EnemyIntent) -> bool:
	if before == null or after == null:
		return before != after
	# ASSUMPTION: these four fields are what "changed" means; a different path to the same tile, or
	# a changed forecast against the same target, isn't marked (UI4 draws the full intent).
	return (
			before.kind != after.kind
			or before.target_id != after.target_id
			or before.tile != after.tile
			or before.order != after.order
	)


## The newest hover waiting for its preview, and the one shown: at most one preview runs per
## [method run_pending], for the newest [method request].
class Queue:
	extends RefCounted

	## Previews computed so far, for tests and benchmarks.
	var computed: int = 0

	var _unit_id: String = ""
	var _tile: Vector2i = CombatFact.NO_TILE
	var _has_pending: bool = false
	var _shown: MovePreview = null

	## Asks for the preview of [param unit_id] on [param tile], replacing any request not yet run.
	## A request for the preview already shown, on an unchanged session, is dropped when run.
	func request(unit_id: String, tile: Vector2i) -> void:
		_unit_id = unit_id
		_tile = tile
		_has_pending = true

	## Drops the request waiting and forgets the preview shown.
	func clear() -> void:
		_has_pending = false
		_shown = null

	## Whether a request is waiting.
	func has_pending() -> bool:
		return _has_pending

	## The preview last returned by [method run_pending]; null after [method clear].
	func shown() -> MovePreview:
		return _shown

	## Runs the waiting request on [param session], if any, and returns its preview; null when
	## nothing waited or it would repeat the preview shown.
	func run_pending(session: CombatSession) -> MovePreview:
		if not _has_pending:
			return null
		_has_pending = false
		if (
				_shown != null
				and _shown.unit_id == _unit_id
				and _shown.tile == _tile
				and _shown.based_on_seq == session.last_seq()
		):
			return null
		_shown = MovePreview.compute(session, _unit_id, _tile)
		computed += 1
		return _shown
