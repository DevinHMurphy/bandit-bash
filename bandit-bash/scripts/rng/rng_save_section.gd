# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_save_section.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name RngSaveSection
extends SaveSection
## One of a run's two [code]rng[/code] save sections: the live streams of the campaign block or
## of the combat block.
##
## [code]CampaignService[/code] registers one per block and hands each the run's
## [CampaignSession] with [method attach]. Both save under the key [code]"rng"[/code] at version
## 1 as [code]{save key: state}[/code], every state a hex string, since states pass 2^53.
## [method RngStreams.capture_campaign] and [method RngStreams.capture_combat] decide which
## purposes each block holds. A [SaveSection], not a [PlayerSaveSection]: every seat's streams live
## in the one registry on the host.[br]
## [b]Load order:[/b] [code]SaveService[/code] restores sections while a file loads, before the
## run's session exists. So [method restore] only checks the data, all or nothing, and holds it;
## [method attach] applies it to the new session's registry before any stream is handed out.
## [method capture] reads the attached session, else returns the held data.[br]
## [b]Resets:[/b] a campaign reset (new run, run dropped) also lets go of the session, which
## belongs to the run before. A combat reset (Begin, battle end, [code]BATTLE_RETRY[/code]) only
## drops held data: at Begin the battle's sessions already hold their streams, and a retry
## re-derives them from their keys.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

# Never change it: it is how saved data finds this section (save-system.md).
const _KEY: String = "rng"
const _VERSION: int = 1

var _is_combat: bool = false

# The run whose registry capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for attach(); only meaningful while _is_holding, since an empty
# section is data too.
var _held: Dictionary[String, String] = {}
var _is_holding: bool = false


## [param block]: [constant SaveSection.Block.CAMPAIGN] or [constant SaveSection.Block.COMBAT].
func _init(block: SaveSection.Block) -> void:
	if block == SaveSection.Block.PROFILE:
		push_error("RngSaveSection: streams belong to a run, not the profile")
	_is_combat = block == SaveSection.Block.COMBAT


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


## The attached session's streams of this block; with no session, the held data, or nothing.
func capture() -> Dictionary:
	if _session != null:
		return _capture_from(_session.rng)
	return _held.duplicate()


## Checks every entry of [param data] on a scratch registry and holds the data for
## [method attach]; no live registry is touched. Lets go of any attached session, whose streams
## the data now replaces. Returns [constant ERR_INVALID_DATA], changing nothing, if any entry is
## malformed or belongs to another block.
func restore(data: Dictionary) -> Error:
	# The seed doesn't matter: only the restored states are read back.
	var scratch: RngStreams = RngStreams.new(0)
	if not _restore_into(scratch, data):
		push_error("RngSaveSection: the %s streams can't be restored" % [_block_name()])
		return ERR_INVALID_DATA
	_held = _capture_from(scratch)
	_is_holding = true
	_session = null
	return OK


## Drops the held data. A campaign reset also lets go of the session (see the class doc).
func reset() -> void:
	_held = {}
	_is_holding = false
	if not _is_combat:
		_session = null


## Applies the held data to [param session]'s registry, then reads that session in
## [method capture]. Call it on a session just built, before any stream is handed out: a restore
## replaces stream objects, so a holder of the old ones would draw from a stream nothing saves.
## Returns [constant OK]; [constant ERR_INVALID_PARAMETER] for null; or
## [constant ERR_ALREADY_IN_USE], changing nothing, when data is held and [param session] has a
## battle on.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("RngSaveSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	if _is_holding:
		if session.encounter != null:
			push_error(
					"RngSaveSection: can't restore %s streams into a battle in progress"
					% [_block_name()]
			)
			return ERR_ALREADY_IN_USE
		# restore() checked the data, so this can't fail.
		_restore_into(session.rng, _held)
	_held = {}
	_is_holding = false
	_session = session
	return OK


## Stops reading the attached session: the run it belongs to was closed or replaced.
func detach() -> void:
	_session = null


func _capture_from(registry: RngStreams) -> Dictionary[String, String]:
	return registry.capture_combat() if _is_combat else registry.capture_campaign()


func _restore_into(registry: RngStreams, data: Dictionary) -> bool:
	return registry.restore_combat(data) if _is_combat else registry.restore_campaign(data)


func _block_name() -> String:
	return "combat" if _is_combat else "campaign"
