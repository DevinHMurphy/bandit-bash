# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_bench.gd
# Author:
# Created:  November 12, 2026
# Modified: November 12, 2026
# ==============================================================================

extends SceneTree
## Campaign map benchmark: every hard rule on many seeds, and how often a route misses each soft
## target at several boost sizes, to choose [member CampaignMapRules.target_boost].
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/bench/campaign_map_bench.gd[/code]
## [br]Options after [code]--[/code]: [code]--seeds=N[/code] (default 10,000) and
## [code]--boosts=0,2,4[/code] (default [constant DEFAULT_BOOSTS]). The shipped rules run first,
## then each boost on a copy of them. A row shows, per target type, the share of routes (every
## path floor 1 to the boss) below its target and the share of maps with any such route, then the
## mean count per route of each type. Exits with code 1 if any map breaks a hard rule.

# A preloaded script used as a type (gdscript.md, Naming): the checks have no class name.
const MapChecks = preload("res://tests/campaign/map_checks.gd")

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const DEFAULT_SEEDS: int = 10000
const DEFAULT_BOOSTS: PackedInt32Array = [0, 1, 2, 3, 4, 6, 8, 12]

const TYPE_NAMES: Dictionary[int, String] = {
	CampaignGraph.NodeType.STANDARD: "Std",
	CampaignGraph.NodeType.KEY: "Key",
	CampaignGraph.NodeType.BOSS: "Boss",
	CampaignGraph.NodeType.ARMORY: "Arm",
	CampaignGraph.NodeType.GUILDHALL: "Guild",
	CampaignGraph.NodeType.UNKNOWN: "?",
	CampaignGraph.NodeType.CAMP: "Camp",
	CampaignGraph.NodeType.TREASURE: "Tres",
}


func _init() -> void:
	var seeds: int = DEFAULT_SEEDS
	var boosts: PackedInt32Array = DEFAULT_BOOSTS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = arg.trim_prefix("--seeds=").to_int()
		elif arg.begins_with("--boosts="):
			boosts = PackedInt32Array(Array(arg.trim_prefix("--boosts=").split(",")).map(
					func(text: String) -> int: return text.to_int()
			))

	var rules: CampaignMapRules = load(RULES_PATH) as CampaignMapRules
	if rules == null:
		push_error("CampaignMapBench: can't load %s" % [RULES_PATH])
		quit(1)
		return

	print("--- Campaign map bench: %d seeds per row (run seeds 1 to %d) ---" % [seeds, seeds])
	var broken: int = _row("shipped (boost %d)" % [rules.target_boost], rules, seeds)
	for boost: int in boosts:
		var copy: CampaignMapRules = rules.duplicate() as CampaignMapRules
		copy.target_boost = boost
		broken += _row("boost %d" % [boost], copy, seeds)
	print("--- %s ---" % ["every map keeps every hard rule" if broken == 0 else (
			"%d maps break a hard rule" % [broken]
	)])
	quit(1 if broken > 0 else 0)


# Generates and checks `seeds` maps under `rules`, prints one row, and returns how many broke a
# hard rule.
func _row(label: String, rules: CampaignMapRules, seeds: int) -> int:
	var targets: Array[int] = []
	for type: int in rules.path_targets:
		targets.append(type)
	targets.sort()
	var routes: int = 0
	var missed_routes: Dictionary[int, int] = {}
	var missed_maps: Dictionary[int, int] = {}
	var mean_sums: Dictionary[int, float] = {}
	var broken: int = 0
	var first_problem: String = ""
	var generate_usec: int = 0
	var started: int = Time.get_ticks_usec()

	for run_seed: int in range(1, seeds + 1):
		var stream: RngStream = RngStream.new(
				RngKey.derive_seed(run_seed, RngKey.RngPurpose.MAP_GENERATION, -1, -1, -1, -1)
		)
		var before: int = Time.get_ticks_usec()
		var graph: CampaignGraph = CampaignMapGenerator.generate(rules, stream)
		generate_usec += Time.get_ticks_usec() - before
		var problems: PackedStringArray = MapChecks.violations(graph, rules)
		if not problems.is_empty():
			broken += 1
			if first_problem.is_empty():
				first_problem = "seed %d: %s" % [run_seed, problems[0]]
			continue
		var stats: Dictionary = MapChecks.route_stats(graph, rules)
		var map_routes: int = stats[MapChecks.ROUTES]
		routes += map_routes
		var missed: Dictionary = stats[MapChecks.MISSED]
		for type: int in targets:
			var count: int = missed[type]
			missed_routes[type] = missed_routes.get(type, 0) + count
			missed_maps[type] = missed_maps.get(type, 0) + (1 if count > 0 else 0)
		var means: Dictionary = stats[MapChecks.MEANS]
		for type: int in TYPE_NAMES:
			var mean: float = means[type]
			mean_sums[type] = mean_sums.get(type, 0.0) + mean

	var total_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	var cells: PackedStringArray = []
	for type: int in targets:
		cells.append("%s %5.2f%% routes %5.1f%% maps" % [
			TYPE_NAMES[type],
			100.0 * missed_routes.get(type, 0) / maxf(routes, 1.0),
			100.0 * missed_maps.get(type, 0) / seeds,
		])
	var mix: PackedStringArray = []
	for type: int in TYPE_NAMES:
		if type != CampaignGraph.NodeType.BOSS:
			mix.append("%s %.2f" % [TYPE_NAMES[type], mean_sums.get(type, 0.0) / seeds])
	print("%-18s | misses: %s" % [label, " | ".join(cells)])
	print("%-18s | mean per route: %s" % ["", ", ".join(mix)])
	print("%-18s | %d maps break a hard rule%s; generate %.0f ms, row %.0f ms" % [
		"", broken, "" if first_problem.is_empty() else " (%s)" % [first_problem],
		generate_usec / 1000.0, total_ms,
	])
	return broken
