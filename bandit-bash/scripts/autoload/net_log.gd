# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_log.gd
# Author:
# Created:  October 9, 2026
# Modified: October 9, 2026
# ==============================================================================

extends Node
## Leveled, categorized, peer-tagged logging for networking code.
##
## Registered as autoload [code]NetLog[/code], before [code]SteamManager[/code]. Every line carries
## this machine's peer id, because "which machine printed this" is the question most multiplayer
## bugs turn on; logs pasted from two instances still read clearly.[br]
## [b]Hot paths:[/b] gate on [method would_log] before building a formatted message, since the
## [code]%[/code] format runs before the call whether or not anything prints.[br]
## Pair with [code]file_logging/enable_file_logging[/code] in project.godot so each run lands in
## [code]user://logs/godot.log[/code] on both machines.

## Severity, most to least severe. A line prints when its level is at or above [member min_level].
enum Level {
	ERROR = 0,
	WARN = 1,
	INFO = 2,
	DEBUG = 3,
}

## Subsystem a line belongs to. The enum key, capitalized, is the tag printed in the line.
enum Category {
	## Steam init and API availability.
	STEAM = 0,
	## Lobby create, join, leave and the peer bridge.
	LOBBY = 1,
	## Screen transitions.
	SCENE = 2,
}

## Least severe level that still prints.
##
## [b]INFO:[/b] shows every connect and state change without per-frame chatter.
## [b]DEBUG:[/b] use while chasing a desync.
var min_level: Level = Level.INFO

## Categories that print. Empty prints every category.
var enabled_categories: Array[Category] = []


func error(category: Category, message: String) -> void:
	_log(Level.ERROR, category, message)


func warn(category: Category, message: String) -> void:
	_log(Level.WARN, category, message)


func info(category: Category, message: String) -> void:
	_log(Level.INFO, category, message)


## Per-frame traffic such as RPC sends and transform broadcasts. Off by default.
func debug(category: Category, message: String) -> void:
	_log(Level.DEBUG, category, message)


## Whether a line at [param level] and [param category] would print.
##
## Check this before formatting a message in any per-frame or per-entity path.
func would_log(level: Level, category: Category) -> bool:
	if level > min_level:
		return false
	return enabled_categories.is_empty() or enabled_categories.has(category)


func _log(level: Level, category: Category, message: String) -> void:
	if not would_log(level, category):
		return

	# get_unique_id() returns 1 with no peer attached, the same value as solo play.
	var line: String = "[%s][%s][peer %d] %s" % [
		Level.find_key(level),
		String(Category.find_key(category)).capitalize(),
		multiplayer.get_unique_id(),
		message,
	]
	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			# This is the project's logging facility, so it is the one place that prints.
			print(line)
