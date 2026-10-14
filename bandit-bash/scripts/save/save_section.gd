# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_section.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

@abstract
class_name SaveSection
extends RefCounted
## Contract for a system that keeps its own data in a save file, once per file.
##
## A system extends this, implements the abstract methods, and registers one instance with
## [code]SaveService.register_section()[/code] before a save file opens; an autoload's
## [code]_ready()[/code] is early enough. From then on [code]SaveService[/code] calls
## [method restore] when the file loads, [method capture] when it saves, and [method reset] for a
## new run or a closed file. The system never touches disk.[br]
## Data must be plain JSON values: no Objects or Resources, and ints above 2^53 (Steam ids) as
## strings, since JSON returns every number as a float. Data that exists once per player uses
## [PlayerSaveSection] instead.
##
## @tutorial(Save system design): docs/design/save-system.md

## Which save file block a section lives in.
enum Block {
	## [code]profile.json[/code]: progress across runs (unlocks, statistics). Reset on close.
	PROFILE = 0,
	## A campaign file: the run in progress. Reset for a new run and on close.
	CAMPAIGN = 1,
	## A combat file: the battle in progress. Reset when a battle begins or ends.
	COMBAT = 2,
}


## Returns this section's key in the file, e.g. [code]"unlocks"[/code]. Must never change: it is
## how saved data finds its owner.
@abstract func get_key() -> String


## Returns the version of the data [method capture] produces, starting at 1. Raise it whenever
## the data's shape changes, and handle the old shape in [method migrate].
@abstract func get_version() -> int


## Returns this section's current data as plain JSON values.
@abstract func capture() -> Dictionary


## Takes [param data] as this section's state. [param data] is already migrated to
## [method get_version]. Returns [constant OK], or an error that stops the file from loading.
@abstract func restore(data: Dictionary) -> Error


## Returns this section to its state for a new run or new save file.
@abstract func reset() -> void


## Upgrades [param data], saved at [param from_version], to [method get_version] in place.
##
## Called only when [param from_version] is lower. The default fails loudly, so raising the
## version without writing a migration can't silently misread old saves.
## Returns [constant OK], or an error that stops the file from loading.
func migrate(_data: Dictionary, from_version: int) -> Error:
	push_error(
			"SaveSection: '%s' has no migration from version %d to %d."
			% [get_key(), from_version, get_version()]
	)
	return ERR_UNAVAILABLE
