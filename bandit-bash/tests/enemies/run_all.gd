# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 30, 2026
# Modified: November 4, 2026
# ==============================================================================

extends SceneTree
## Enemies suite (enemies and AI plan, P05): setup step 4 ([EnemySetup],
## [code]enemy_setup_cases.gd[/code]), the enemy AI ([code]ai_cases.gd[/code]) and its intents
## ([code]intent_cases.gd[/code]) on the loadout fixture tree's enemy classes, and a headless M1
## battle on the real catalog ([code]m1_battle_cases.gd[/code]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/enemies/run_all.gd[/code][br]
## Prints one PASS or FAIL line per check and the summary line
## [code]--- N passed, M failed ---[/code]; exits with code 1 on any failure. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## them. Each step's cases live in their own file; add a line per file here.

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const AiCases = preload("res://tests/enemies/ai_cases.gd")
const CatalogCases = preload("res://tests/content/catalog_cases.gd")
const EnemySetupCases = preload("res://tests/enemies/enemy_setup_cases.gd")
const IntentCases = preload("res://tests/enemies/intent_cases.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Enemies tests ---")
	# Hashed before the first case (event bus plan, question 50): no case may change a definition.
	var before: Dictionary[String, String] = CatalogCases.hash_definitions([LoadoutCases.TREE])
	EnemySetupCases.new(_check).run()
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	AiCases.new(_check, catalog).run()
	IntentCases.new(_check, catalog).run()
	M1BattleCases.new(_check).run()
	var changed: PackedStringArray = CatalogCases.changed_definitions(
			before, CatalogCases.hash_definitions([LoadoutCases.TREE])
	)
	_check("definitions: none changed during the run (%d hashed)" % [before.size()], (
			changed.is_empty()
	), ", ".join(changed))
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
