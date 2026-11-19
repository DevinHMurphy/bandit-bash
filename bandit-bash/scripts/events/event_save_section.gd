# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_save_section.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventSaveSection
extends SaveSection
## The run's events ([EventRunState]): block [code]CAMPAIGN[/code], key [code]events[/code],
## version [constant VERSION], shared by every seat (each seat's part is inside it).
## [code]CampaignService[/code] registers it after the run sections.[br]
## [b]Load order:[/b] it restores before the run's session exists, so it only checks its data
## and holds it; [method attach] puts it into the session's run once the run is built, and the
## section reads that run's [member CampaignRunState.events] from then on, the copy a battle's
## end swaps in included. [code]{}[/code] is a run with no events yet.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The section's data version.
const VERSION: int = 1

# The section key. Never change it: it is how saved data finds its owner (save-system.md).
const _KEY: String = "events"

var _session: CampaignSession = null
var _held: Dictionary = {}


func get_key() -> String:
	return _KEY


func get_version() -> int:
	return VERSION


## The attached session's run's events, else the held data; [code]{}[/code] with neither.
func capture() -> Dictionary:
	if _session != null:
		return {} if _session.run == null else _session.run.events.capture()
	return _held.duplicate(true)


## Checks [param data] and holds it, letting go of any attached session.
## [constant ERR_INVALID_DATA] for data [method EventRunState.restore] refuses.
func restore(data: Dictionary) -> Error:
	_session = null
	if data.is_empty():
		_held = {}
		return OK
	var parsed: EventRunState = EventRunState.new()
	if parsed.restore(data) != OK:
		return ERR_INVALID_DATA
	_held = parsed.capture()
	return OK


func reset() -> void:
	_held = {}
	_session = null


## Puts the held data into [param session]'s run and reads that session from then on. Returns
## [constant OK]; [constant ERR_INVALID_PARAMETER] for null; or [constant ERR_UNCONFIGURED],
## keeping the data held and unattached, when the session has no run (its run couldn't load).
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("EventSaveSection: attach needs a session")
		return ERR_INVALID_PARAMETER
	if session.run == null:
		return ERR_UNCONFIGURED
	if not _held.is_empty():
		# restore() checked the data, so this can't fail.
		session.run.events.restore(_held)
	_held = {}
	_session = session
	return OK


## Stops reading the attached session: the run it belongs to was closed or replaced.
func detach() -> void:
	_session = null
