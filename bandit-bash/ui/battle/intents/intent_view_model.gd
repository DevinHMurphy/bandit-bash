# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_view_model.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name IntentViewModel
extends RefCounted
## What the intent display draws for one [Intents]: each acting enemy's icon, target rule and line,
## in the order the enemy phase is expected to play (combat UI plan, question 10;
## game-vision.md, Enemy intentions).
##
## Plain data built from the session's board, so tests read it without rendering. For a move
## preview ([method Intents.preview]) the moved player unit stands on
## [member Intents.moved_to], so a line at it points at the hovered tile, not where its token is.
## [IntentDisplay] draws it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Whether these are a move preview's re-planned intents, not the session's current ones.
var is_preview: bool = false

## Every enemy that would act, in [member EnemyIntent.order].
var entries: Array[Entry] = []


## The entry of [param enemy_id]; null for an enemy that doesn't act.
func entry_of(enemy_id: String) -> Entry:
	for entry: Entry in entries:
		if entry.enemy_id == enemy_id:
			return entry
	return null


## The entries that draw a line (a target other than the enemy itself), in order.
func lines() -> Array[Entry]:
	var found: Array[Entry] = []
	for entry: Entry in entries:
		if entry.has_line():
			found.append(entry)
	return found


## The model of [param intents] on [param session]'s board. [param is_previewed]: they are a move
## preview's. [param changed]: the enemies whose intent differs from the current one
## ([member MovePreview.changed_enemies]); empty for the current intents.
static func build(
		session: CombatSession,
		intents: Intents,
		is_previewed: bool,
		changed: PackedStringArray = PackedStringArray()
) -> IntentViewModel:
	var model: IntentViewModel = IntentViewModel.new()
	model.is_preview = is_previewed
	if intents == null:
		return model
	var state: CombatState = session.state
	for intent: EnemyIntent in intents.enemies:
		if not state.has_unit(intent.unit_id):
			continue
		var entry: Entry = Entry.new()
		entry.enemy_id = intent.unit_id
		entry.kind = intent.kind
		entry.order = intent.order
		entry.rule_text = intent.target_rule_text
		entry.enemy_tile = state.tile_of(intent.unit_id)
		entry.target_id = intent.target_id
		entry.is_changed = changed.has(intent.unit_id)
		if intent.target_id == intents.moved_unit_id and not intents.moved_unit_id.is_empty():
			entry.target_tile = intents.moved_to
		elif state.has_unit(intent.target_id):
			entry.target_tile = state.tile_of(intent.target_id)
		model.entries.append(entry)
	return model


## One enemy's intent as the board draws it.
class Entry:
	extends RefCounted

	## The enemy.
	var enemy_id: String = ""
	## Its icon.
	var kind: EnemyIntent.Kind = EnemyIntent.Kind.GUARD
	## Its place in the expected phase, from 0; the line shows it from 1.
	var order: int = 0
	## Its target rule as the player reads it; empty for an enemy with no class.
	var rule_text: String = ""
	## The tile it stands on now.
	var enemy_tile: Vector2i = CombatFact.NO_TILE
	## The unit it attacks, heals or advances on; empty for a guard.
	var target_id: String = ""
	## Where that unit stands on the board read; [constant CombatFact.NO_TILE] for none.
	var target_tile: Vector2i = CombatFact.NO_TILE
	## In a preview, whether this intent differs from the current one.
	var is_changed: bool = false

	## Whether it draws a line: it has a target on the board other than itself.
	func has_line() -> bool:
		return target_tile != CombatFact.NO_TILE and target_tile != enemy_tile
