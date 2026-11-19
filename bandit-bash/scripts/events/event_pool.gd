# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_pool.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventPool
extends RefCounted
## The events an Unknown node can draw from, sorted by id, and the lookup that turns a saved
## event id back into its [EventDefinition].
##
## [method load_default] reads every event under [constant PATH] once, on the main thread, and
## keeps it; tests build their own pool from definitions. Rules code is handed a pool and never
## loads one. An event with data problems ([method EventDefinition.problems]), or an id already
## in the pool, is left out and reported in [member problems].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The folder holding the game's events, one [EventDefinition] per file.
const PATH: String = "res://data/events/"

static var _loaded: EventPool = null

## The pool's events, sorted by id. Read-only.
var events: Array[EventDefinition] = []

## What was left out and why, one line each. Empty when every event was sound.
var problems: PackedStringArray = []

var _by_id: Dictionary[String, EventDefinition] = {}


func _init(definitions: Array[EventDefinition] = []) -> void:
	for definition: EventDefinition in definitions:
		_add(definition)
	events.sort_custom(func(a: EventDefinition, b: EventDefinition) -> bool: return a.id < b.id)


## The event [param id]; null when the pool has none.
func event(id: String) -> EventDefinition:
	return _by_id.get(id, null)


## The game's pool from [constant PATH], loaded on the first call and kept; an empty pool when the
## folder is missing or empty. Problems are reported once, when it loads.
static func load_default() -> EventPool:
	if _loaded != null:
		return _loaded
	var definitions: Array[EventDefinition] = []
	var unread: PackedStringArray = []
	if DirAccess.dir_exists_absolute(PATH):
		var entries: PackedStringArray = ResourceLoader.list_directory(PATH)
		entries.sort()
		for entry: String in entries:
			if entry.ends_with("/"):
				continue
			var definition: EventDefinition = ResourceLoader.load(PATH + entry) as EventDefinition
			if definition == null:
				unread.append("%s%s isn't an event" % [PATH, entry])
				continue
			definitions.append(definition)
	_loaded = EventPool.new(definitions)
	_loaded.problems.append_array(unread)
	for problem: String in _loaded.problems:
		push_error("EventPool: %s" % [problem])
	return _loaded


func _add(definition: EventDefinition) -> void:
	if definition == null:
		problems.append("an event is missing")
		return
	var found: PackedStringArray = definition.problems()
	if not found.is_empty():
		problems.append("; ".join(found))
		return
	if _by_id.has(definition.id):
		problems.append("%s repeats an event id" % [definition.id])
		return
	_by_id[definition.id] = definition
	events.append(definition)
