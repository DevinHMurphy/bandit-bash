# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_hooks.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name CombatHooks
extends RefCounted
## The named points in the turn loop where other plans plug in their rules: one registry per
## map, held by its [CombatSession] as [member CombatSession.hooks].
##
## [PhaseRunner] calls each [enum Hook] at its fixed place in the loop, and the registrations of
## one hook in the order they were made, so the order is the session's registration order. Every
## registration is a pure rules function on the session (gdscript.md, Event bus and effects): it
## never awaits, and it records any change as a fact through [member CombatSession.engine]. Each
## hook's doc gives its call signature.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## Where a registration runs. Not saved or sent: registrations are made again whenever a session
## opens.
enum Hook {
	## At the player Phase Start, before the Block and Stance refresh: units sent from another map
	## arrive ([method CombatEncounter.deliver_arrivals]). [code]func(session) -> void[/code].
	ARRIVALS = 0,
	## During Phase Start terrain healing, for each unit on a healing tile: false stops its heal
	## (P06: flooded tiles). Every registration must allow it.
	## [code]func(session, unit_id: String) -> bool[/code].
	TERRAIN_HEALING_ALLOWED = 1,
	## At each side's Phase End, after Unit Turn End and the drain (P06: darkness damage).
	## [code]func(session, side: CombatFact.CombatSide) -> void[/code].
	PHASE_END_EFFECTS = 2,
	## The enemy side's turns, asked one command at a time, each after the one before resolved:
	## the first registration with a command gives it; null from all of them ends the side's turns
	## (P05: the AI). With none registered, every enemy Waits.
	## [code]func(session) -> Command[/code].
	ENEMY_COMMANDS = 3,
	## After the enemy Phase End, each registration its own step (P06's darkness step, then P04's
	## reinforcement arrival). [code]func(session) -> void[/code].
	AFTER_ENEMY_PHASE = 4,
	## After every player Phase Start (P05: the new intents). [code]func(session) -> void[/code].
	INTENTS = 5,
	## After every resolution step: each command, each enemy turn and each phase boundary (P04:
	## the objective checks, which end the combat). [code]func(session) -> void[/code].
	AFTER_STEP = 6,
	## When a rune or effect acts on a map object (P04 MP6: Spark detonates a powder keg).
	## [code]func(session, source_id: String, object_id: String) -> bool[/code].
	OBJECT_OPERATIONS = 7,
}

var _registered: Dictionary[int, Array] = {}


## Registers [param run] for [param hook], after every registration already made for it. See
## [enum Hook] for the signature each hook calls it with.
func add(hook: Hook, run: Callable) -> void:
	if not _registered.has(hook):
		var runs: Array[Callable] = []
		_registered[hook] = runs
	_registered[hook].append(run)


## The registrations of [param hook], in the order they were made.
func get_registered(hook: Hook) -> Array[Callable]:
	var runs: Array[Callable] = []
	if _registered.has(hook):
		runs.assign(_registered[hook])
	return runs


## Whether anything is registered for [param hook].
func has_registered(hook: Hook) -> bool:
	return _registered.has(hook) and not _registered[hook].is_empty()
