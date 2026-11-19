# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_tally_section.gd
# Author:
# Created:  November 13, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleTallySection
extends SaveSection
## The battle's XP tally in the combat block: the [code]battle_tally[/code] section, version 1,
## with its partners [member grants] ([code]battle_grants[/code], version 1) and [member stats]
## ([code]battle_stats[/code], version 1). None is per player: each holds every seat's.
##
## [code]CampaignService[/code] registers all three after the darkness section and attaches them
## to the run's [CampaignSession]. During a battle each capture reads the session's
## [member CampaignSession.tally], [member CampaignSession.battle_grants] or
## [member CampaignSession.stats]; outside one, the held data or nothing.[br]
## [b]Load order:[/b] [method restore] only checks the data and holds it. On a [code]BATTLE[/code]
## resume, after the battle is rebuilt and loaded, [method load_into] hands all three to the
## session. A combat file without a section (from before it) resumes with it empty.
## [b]Resets:[/b] Begin, battle end and [code]BATTLE_RETRY[/code] drop held data only.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# Never change them: they are how saved data finds these sections (save-system.md).
const _KEY: String = "battle_tally"
const _GRANTS_KEY: String = "battle_grants"
const _STATS_KEY: String = "battle_stats"
const _VERSION: int = 1

# GrantsSection's data keys and grant ids. Never change them: saved battles are read by these names.
const _KEY_GRANTS: String = "grants"
const _KEY_SEAT: String = "seat"
const _KEY_GRANT: String = "grant"
const _KEY_AMOUNT: String = "amount"
const _KEY_DEFINITION: String = "definition_id"
const _KEY_SOURCE: String = "source_effect_id"
const _GRANT_IDS: Dictionary[CampaignGrant.Grant, String] = {
	CampaignGrant.Grant.GOLD: "gold",
	CampaignGrant.Grant.HEIRLOOM: "heirloom",
	CampaignGrant.Grant.RECRUIT: "recruit",
	CampaignGrant.Grant.RUNE: "rune",
}

## The [code]battle_grants[/code] section: the grants the battle in progress has received
## ([member CampaignSession.battle_grants]), applied to the run when the battle ends.
var grants: GrantsSection = GrantsSection.new()

## The [code]battle_stats[/code] section: how each player unit has fought in the battle in progress
## ([member CampaignSession.stats]), for the victory recap.
var stats: StatsSection = StatsSection.new()

# The run whose battle capture() reads; null until attach() and after detach().
var _session: CampaignSession = null

# Data restore() checked, waiting for load_into(); only meaningful while _is_holding.
var _held: Dictionary = {}
var _is_holding: bool = false


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return _VERSION


## The attached run's tally during a battle; outside one, the held data, else empty.
func capture() -> Dictionary:
	if _session != null and _session.encounter != null:
		return _session.tally.capture()
	return _held.duplicate(true) if _is_holding else {}


## Checks [param data] on a scratch [BattleTally] and holds it for [method load_into]. Empty data
## (written with no battle) holds nothing. Returns [constant ERR_INVALID_DATA], holding nothing,
## for data the tally refuses.
func restore(data: Dictionary) -> Error:
	reset()
	if data.is_empty():
		return OK
	if BattleTally.new().restore(data) != OK:
		return ERR_INVALID_DATA
	_held = data.duplicate(true)
	_is_holding = true
	return OK


## Drops the held data; the attached run stays attached.
func reset() -> void:
	_held = {}
	_is_holding = false


## Reads [param session]'s battle in [method capture] from now on, and [member grants] and
## [member stats] do too. Held data stays held until [method load_into]. Returns [constant OK], or
## [constant ERR_INVALID_PARAMETER] for null.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("BattleTallySection: attach needs a session")
		return ERR_INVALID_PARAMETER
	_session = session
	grants.session = session
	stats.session = session
	return OK


## Stops reading the attached run, and [member grants] and [member stats] too: it was closed or
## replaced.
func detach() -> void:
	_session = null
	grants.session = null
	stats.session = null


## Whether it holds a saved battle's tally. False for a file from before this section.
func is_holding() -> bool:
	return _is_holding


## Hands the held tally, grants ([member grants]) and stats ([member stats]) to [param session],
## whose battle was just resumed, and drops them. Holding nothing leaves the session's empty.
## Returns [constant OK], or [constant ERR_INVALID_PARAMETER] for null.
func load_into(session: CampaignSession) -> Error:
	if session == null:
		return ERR_INVALID_PARAMETER
	if _is_holding:
		# Checked by restore(), so it can't be refused.
		session.tally.restore(_held)
	reset()
	var err: Error = grants.load_into(session)
	if err != OK:
		return err
	return stats.load_into(session)


## The [code]battle_grants[/code] section:
## [code]{"grants": [{"seat": 0, "grant": "gold", "amount": 50, "definition_id": "",
## "source_effect_id": "effect:12"}]}[/code], in the order received.
class GrantsSection:
	extends SaveSection

	## The run whose battle [method capture] reads; null when none is attached.
	var session: CampaignSession = null

	var _held: Array[CampaignSession.Grant] = []

	func get_key() -> String:
		return _GRANTS_KEY

	func get_version() -> int:
		return _VERSION

	## The attached run's battle grants during a battle; outside one, the held ones, else empty.
	func capture() -> Dictionary:
		var source: Array[CampaignSession.Grant] = _held
		if session != null and session.encounter != null:
			source = session.battle_grants
		if source.is_empty() and (session == null or session.encounter == null):
			return {}
		var entries: Array = []
		for grant: CampaignSession.Grant in source:
			entries.append({
				_KEY_SEAT: grant.seat,
				_KEY_GRANT: _GRANT_IDS[grant.grant],
				_KEY_AMOUNT: grant.amount,
				_KEY_DEFINITION: grant.definition_id,
				_KEY_SOURCE: grant.source_effect_id,
			})
		return {_KEY_GRANTS: entries}

	## Checks [param data] and holds its grants. Returns [constant ERR_INVALID_DATA], holding
	## nothing, for an entry with an unknown grant, a seat or amount that isn't a whole number, or
	## ids that aren't strings.
	func restore(data: Dictionary) -> Error:
		reset()
		if data.is_empty():
			return OK
		var entries: Variant = data.get(_KEY_GRANTS)
		if not entries is Array:
			return _refuse(data)
		var read: Array[CampaignSession.Grant] = []
		for entry: Variant in entries as Array:
			if not entry is Dictionary:
				return _refuse(data)
			var entry_data: Dictionary = entry
			var grant: CampaignSession.Grant = CampaignSession.Grant.new()
			var kind: Variant = _GRANT_IDS.find_key(entry_data.get(_KEY_GRANT))
			var seat: Variant = CampaignRunState.whole_number(entry_data.get(_KEY_SEAT))
			var amount: Variant = CampaignRunState.whole_number(entry_data.get(_KEY_AMOUNT))
			var definition: Variant = entry_data.get(_KEY_DEFINITION)
			var source: Variant = entry_data.get(_KEY_SOURCE)
			if (
					kind == null or seat == null or amount == null
					or not definition is String or not source is String
			):
				return _refuse(data)
			grant.grant = kind as CampaignGrant.Grant
			grant.seat = seat as int
			grant.amount = amount as int
			grant.definition_id = definition as String
			grant.source_effect_id = source as String
			read.append(grant)
		_held = read
		return OK

	func reset() -> void:
		_held = []

	## Hands the held grants to [param session] as its battle's and drops them.
	func load_into(target: CampaignSession) -> Error:
		if target == null:
			return ERR_INVALID_PARAMETER
		target.battle_grants = _held.duplicate()
		reset()
		return OK

	func _refuse(data: Dictionary) -> Error:
		push_error("BattleTallySection: not a battle's grants - %s" % [data])
		return ERR_INVALID_DATA


## The [code]battle_stats[/code] section, as [method BattleStats.capture] writes it.
class StatsSection:
	extends SaveSection

	## The run whose battle [method capture] reads; null when none is attached.
	var session: CampaignSession = null

	var _held: Dictionary = {}
	var _is_holding: bool = false

	func get_key() -> String:
		return _STATS_KEY

	func get_version() -> int:
		return _VERSION

	## The attached run's battle stats during a battle; outside one, the held data, else empty.
	func capture() -> Dictionary:
		if session != null and session.encounter != null:
			return session.stats.capture()
		return _held.duplicate(true) if _is_holding else {}

	## Checks [param data] on a scratch [BattleStats] and holds it. Empty data holds nothing.
	## Returns [constant ERR_INVALID_DATA], holding nothing, for data the stats refuse.
	func restore(data: Dictionary) -> Error:
		reset()
		if data.is_empty():
			return OK
		if BattleStats.new().restore(data) != OK:
			return ERR_INVALID_DATA
		_held = data.duplicate(true)
		_is_holding = true
		return OK

	func reset() -> void:
		_held = {}
		_is_holding = false

	## Hands the held stats to [param target] as its battle's and drops them; holding nothing
	## leaves its stats as they are.
	func load_into(target: CampaignSession) -> Error:
		if target == null:
			return ERR_INVALID_PARAMETER
		if _is_holding:
			# Checked by restore(), so it can't be refused.
			target.stats.restore(_held)
		reset()
		return OK
