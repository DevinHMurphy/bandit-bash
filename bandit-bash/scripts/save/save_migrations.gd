# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_migrations.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name SaveMigrations
extends RefCounted
## Upgrades a save envelope from the schema version it was written with to the current one.
##
## Each data class (profile, settings, campaign, combat) owns its current schema version and its
## list of steps, next to the fields they change. This class only runs them, so the rules are
## enforced in one place: one step per version, run in order, and a file newer than the build is
## refused rather than guessed at.[br]
## A step is a [Callable] that takes the envelope [Dictionary], edits it in place and returns an
## [enum Error]. [code]steps[0][/code] upgrades version 1 to 2, [code]steps[1][/code] 2 to 3,
## and so on.
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md


## Runs the steps that take [param envelope] from its schema version to [param current_version].
##
## Edits [param envelope] in place and sets its [constant SaveFile.KEY_SCHEMA_VERSION]. On any
## error the envelope may be partly migrated; the caller must discard it, not save it.
## [param steps]: exactly [code]current_version - 1[/code] steps, oldest first.
## Returns [constant OK]; [constant ERR_BUG] when the step list doesn't match the version;
## [constant ERR_INVALID_DATA] for a version below 1; [constant ERR_FILE_UNRECOGNIZED] for a
## version newer than [param current_version]; or the first error a step returns.
static func run(envelope: Dictionary, current_version: int, steps: Array[Callable]) -> Error:
	if current_version < 1 or steps.size() != current_version - 1:
		push_error(
				"SaveMigrations: schema version %d needs %d steps, got %d."
				% [current_version, current_version - 1, steps.size()]
		)
		return ERR_BUG

	var file_version: int = int(envelope.get(SaveFile.KEY_SCHEMA_VERSION, 0))
	if file_version < 1:
		push_error("SaveMigrations: invalid schema version %d." % [file_version])
		return ERR_INVALID_DATA
	if file_version > current_version:
		push_error(
				"SaveMigrations: schema version %d is newer than this build's %d."
				% [file_version, current_version]
		)
		return ERR_FILE_UNRECOGNIZED

	for step_index: int in range(file_version - 1, current_version - 1):
		var step_err: Error = steps[step_index].call(envelope)
		if step_err != OK:
			push_error(
					"SaveMigrations: step %d -> %d failed - %s"
					% [step_index + 1, step_index + 2, error_string(step_err)]
			)
			return step_err
		envelope[SaveFile.KEY_SCHEMA_VERSION] = step_index + 2

	return OK
