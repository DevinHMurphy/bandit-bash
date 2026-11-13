# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 28, 2026
# Modified: November 13, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the sessions layer, a case file per topic (each one's class doc lists its
## checks): queue_cases.gd, encounter_cases.gd, bridge_cases.gd, service_cases.gd,
## run_service_cases.gd, run_battle_cases.gd, resume_cases.gd, logging_cases.gd, wire_cases.gd,
## save_cases.gd and map_save_cases.gd. Every catalog definition
## and loadout fixture is hashed before the first case and after the last; any change fails.[br]
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/sessions/run_all.gd[/code].
## Prints PASS or FAIL per case and exits with code 1 if any fails. The cases run on the first
## frame, when autoloads exist; this script compiles before they are registered, so it reaches
## them as nodes.[br]
## [b]Lifecycle cases[/b] write save files, so they run only when an [code]override.cfg[/code]
## (never committed) sets a custom user folder whose name starts [code]bandit_bash_tests[/code],
## and are skipped otherwise; [code]tools/run_tests.sh[/code] writes one, unique to each run.

# Preloaded scripts used as types (gdscript.md, Naming): the content suite's hashing, the loadout
# fixture tree the definitions hash covers, and the case scripts (no class name).
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const SessionsCaseBase = preload("res://tests/sessions/sessions_case_base.gd")
const QueueCases = preload("res://tests/sessions/queue_cases.gd")
const EncounterCases = preload("res://tests/sessions/encounter_cases.gd")
const BridgeCases = preload("res://tests/sessions/bridge_cases.gd")
const ServiceCases = preload("res://tests/sessions/service_cases.gd")
const RunServiceCases = preload("res://tests/sessions/run_service_cases.gd")
const RunBattleCases = preload("res://tests/sessions/run_battle_cases.gd")
const ResumeCases = preload("res://tests/sessions/resume_cases.gd")
const LoggingCases = preload("res://tests/sessions/logging_cases.gd")
const WireCases = preload("res://tests/sessions/wire_cases.gd")
const SaveCases = preload("res://tests/sessions/save_cases.gd")
const MapSaveCases = preload("res://tests/sessions/map_save_cases.gd")

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _has_run: bool = false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	print("--- Sessions tests. Warnings and errors from rejected commands are expected. ---")
	root.get_node(^"NetLog").set(&"min_level", SessionsCaseBase.LOG_WARN)
	# Hashed before any case loads a definition (event bus plan, question 50).
	var before: Dictionary[String, String] = CatalogCases.hash_definitions([LoadoutCases.TREE])

	_run_cases(QueueCases.new(_check, root))
	_run_cases(EncounterCases.new(_check, root))
	_run_cases(BridgeCases.new(_check, root))
	_run_cases(ServiceCases.new(_check, root))
	_run_cases(RunServiceCases.new(_check, root))
	_run_cases(RunBattleCases.new(_check, root))
	_run_cases(ResumeCases.new(_check, root))
	_run_cases(LoggingCases.new(_check, root))

	WireCases.new(_check).run()
	SaveCases.new(_check).run()
	MapSaveCases.new(_check).run()

	var changed: PackedStringArray = CatalogCases.changed_definitions(
			before, CatalogCases.hash_definitions([LoadoutCases.TREE])
	)
	_check("definitions: none changed during the run (%d hashed)" % [before.size()], (
			changed.is_empty()
	), ", ".join(changed))

	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)
	return false


# Runs a case file and adds its skips to the suite's total.
func _run_cases(cases: SessionsCaseBase) -> void:
	cases.run()
	_skips += cases.skip_count()


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
