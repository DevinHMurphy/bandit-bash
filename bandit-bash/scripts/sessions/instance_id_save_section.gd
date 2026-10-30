# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     instance_id_save_section.gd
# Author:
# Created:  October 29, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name InstanceIdSaveSection
extends SaveSection
## One of a run's two [code]instance_ids[/code] save sections: the [InstanceIdAllocator]'s counter
## and labels, in the campaign block or in the combat block.
##
## [code]CampaignService[/code] registers one per block and hands each the run's
## [CampaignSession] with [method attach]. Both save under [code]"instance_ids"[/code] at version 1
## as [code]{"next": N, "labels": {id: text}}[/code] ([method InstanceIdAllocator.capture]); the
## labels keep [method CampaignSession.describe] readable after a resume. The campaign block holds
## the counter as Begin captured it (campaign writes keep Begin's sections through a battle); the
## combat block holds it at each combat checkpoint, so a resumed enemy phase mints the ids the
## first run minted, and a battle restarted from Begin mints from Begin's value (event bus plan,
## Definitions and instances).[br]
## [b]Load order:[/b] [code]SaveService[/code] restores sections while a file loads, before the
## run's session exists. So [method restore] only checks the data and holds it; [method attach]
## applies it to the new session's allocator. Attach the campaign section first: the combat one,
## when it holds data, carries the later counter.[br]
## [b]Resets:[/b] a campaign reset (new run, run dropped) also lets go of the session; a combat
## reset (Begin, battle end, [code]BATTLE_RETRY[/code]) only drops held data.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

# Never change it: it is how saved data finds this section (save-system.md).
const _KEY: String = "instance_ids"
const _VERSION: int = 1

var _is_combat: bool = false

# The run whose allocator capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for attach(); only meaningful while _is_holding.
var _held: Dictionary = {}
var _is_holding: bool = false


## [param block]: [constant SaveSection.Block.CAMPAIGN] or [constant SaveSection.Block.COMBAT].
func _init(block: SaveSection.Block) -> void:
	if block == SaveSection.Block.PROFILE:
		push_error("InstanceIdSaveSection: instance ids belong to a run, not the profile")
	_is_combat = block == SaveSection.Block.COMBAT


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


## The attached session's allocator; with no session, the held data, else a fresh allocator's
## (a new run writes its first save before its session exists).
func capture() -> Dictionary:
	if _session != null:
		return _session.ids.capture()
	if _is_holding:
		return _held.duplicate(true)
	return InstanceIdAllocator.new().capture()


## Checks [param data] on a scratch allocator and holds it for [method attach]; no live allocator
## is touched. Lets go of any attached session, whose ids the data now replaces. Returns
## [constant ERR_INVALID_DATA], changing nothing, when the data is malformed.
func restore(data: Dictionary) -> Error:
	var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
	if scratch.restore(data) != OK:
		push_error("InstanceIdSaveSection: the %s instance ids can't be restored" % [_block_name()])
		return ERR_INVALID_DATA
	_held = scratch.capture()
	_is_holding = true
	_session = null
	return OK


## Drops the held data. A campaign reset also lets go of the session (see the class doc).
func reset() -> void:
	_held = {}
	_is_holding = false
	if not _is_combat:
		_session = null


## Applies the held data to [param session]'s allocator, then reads that session in
## [method capture]. Call it on a session just built, before it mints an id. Returns
## [constant OK]; [constant ERR_INVALID_PARAMETER] for null; or [constant ERR_ALREADY_IN_USE],
## changing nothing, when data is held and [param session] has a battle on.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("InstanceIdSaveSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	if _is_holding:
		if session.encounter != null:
			push_error(
					"InstanceIdSaveSection: can't restore %s instance ids into a battle in progress"
					% [_block_name()]
			)
			return ERR_ALREADY_IN_USE
		# restore() checked the data, so this can't fail.
		session.ids.restore(_held)
	_held = {}
	_is_holding = false
	_session = session
	return OK


## Stops reading the attached session: the run it belongs to was closed or replaced.
func detach() -> void:
	_session = null


func _block_name() -> String:
	return "combat" if _is_combat else "campaign"
