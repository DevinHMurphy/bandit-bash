# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_data.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name CombatData
extends RefCounted
## The combat block: the battle in progress in one campaign slot. A stub until combat is ported.
##
## Stored as [method get_file_name] beside its campaign, and only while a battle runs.
## [code]SaveService[/code] writes it before its campaign at every battle save, both with the same
## [member checkpoint_seq], and only trusts it on load when that pairing holds (plan, "Combat crash
## protection").[br]
## Enemy units, entities and RNG state are [SaveSection]s in the [code]COMBAT[/code] block, owned
## by the systems that hold them; player units there carry their persisted uid and owning seat,
## so this block needs no players array.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md

## Which side acts. Saved at the end of a player phase, so a resumed battle starts at
## [constant ENEMY].
enum Phase {
	## Players act.
	PLAYER = 0,
	## Enemies act.
	ENEMY = 1,
}

## How a continued campaign picks up relative to its battle. Set by
## [code]SaveService.continue_solo_run()[/code].
enum ResumePoint {
	## No battle in progress; resume on the campaign.
	CAMPAIGN = 0,
	## Resume the saved battle at its saved turn and phase.
	BATTLE = 1,
	## A battle was in progress but its combat file was unusable: restart it from Begin.
	BATTLE_RETRY = 2,
}

## Current schema version of this block. Raising it needs a step in [method _migration_steps].
const SCHEMA_VERSION: int = 1

const _FILE_NAMES: Dictionary[CampaignData.Mode, String] = {
	CampaignData.Mode.SOLO: "combat_solo.json",
	CampaignData.Mode.MULTIPLAYER: "combat_multi.json",
}

# Stored as strings, not enum ints, so reordering Phase can't silently change saved files.
const _PHASE_IDS: Dictionary[Phase, String] = {
	Phase.PLAYER: "player",
	Phase.ENEMY: "enemy",
}

const _KEY_TURN: String = "turn"
const _KEY_PHASE: String = "phase"

## Turn number, starting at 1.
var turn: int = 1

## Which side acts next.
var phase: Phase = Phase.PLAYER

## Must equal its campaign's [member CampaignData.checkpoint_seq], or be exactly one ahead after a
## crash between the two writes; anything else makes the file untrustworthy.
var checkpoint_seq: int = 0

## Section key to [code]{"version": int, "data": Dictionary}[/code], as stored on disk.
## [code]SaveService[/code] moves it to and from the registered [SaveSection]s.
var sections: Dictionary = {}


## Returns this battle as a [SaveFile] envelope, ready for [method SaveFile.write].
func to_envelope() -> Dictionary:
	var core: Dictionary = {
		_KEY_TURN: turn,
		_KEY_PHASE: _PHASE_IDS[phase],
	}
	return SaveFile.make_envelope(SCHEMA_VERSION, core, sections.duplicate(true), checkpoint_seq)


## Fills this battle from [param envelope], migrating it to [constant SCHEMA_VERSION] first.
##
## Edits [param envelope] while migrating. On error the battle is left unchanged.
## Returns [constant OK]; [constant ERR_INVALID_DATA] for an unknown phase or a turn below 1; or
## the [method SaveMigrations.run] error.
func load_envelope(envelope: Dictionary) -> Error:
	var err: Error = SaveMigrations.run(envelope, SCHEMA_VERSION, _migration_steps())
	if err != OK:
		return err

	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	var phase_key: Variant = _PHASE_IDS.find_key(str(core.get(_KEY_PHASE, "")))
	var loaded_turn: int = int(core.get(_KEY_TURN, 0))
	if phase_key == null or loaded_turn < 1:
		return ERR_INVALID_DATA

	turn = loaded_turn
	phase = phase_key
	checkpoint_seq = int(envelope[SaveFile.KEY_CHECKPOINT_SEQ])
	sections = envelope[SaveFile.KEY_SECTIONS]
	return OK


## File name of the combat file for the campaign slot [param slot_mode].
static func get_file_name(slot_mode: CampaignData.Mode) -> String:
	return _FILE_NAMES[slot_mode]


# One step per schema version after 1, oldest first; see SaveMigrations.
static func _migration_steps() -> Array[Callable]:
	return []
