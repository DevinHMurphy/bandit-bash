# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     exchange_outcome.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name ExchangeOutcome
extends RefCounted
## What the AI knows about one candidate exchange, summed over its branches: the chance of a kill
## and of dying, expected and maximum damage, and the chance of breaking Stance.
##
## [method enumerate] runs the combat core's resolver once per branch, each in its own [Sandbox]
## with [ForcedRolls], extending the roll sequence one decision at a time (every hit or miss, crit,
## Chance and pick), so each branch ends where its exchange ended, at a defeat if there was one.
## A branch's probability is the product of its rolls' odds. Results are combined in enumeration
## order, never completion order, so the summary is the same on any thread. The rating that weighs
## these numbers belongs to the AI plan.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Probability that the defender is defeated.
var kill_probability: float = 0.0

## Probability that the attacker is defeated.
var death_probability: float = 0.0

## Expected damage the attacker deals to the defender's HP.
var expected_dealt_hp: float = 0.0

## Expected damage the attacker deals to the defender's Block.
var expected_dealt_block: float = 0.0

## Expected damage the attacker takes to its HP.
var expected_taken_hp: float = 0.0

## Expected damage the attacker takes to its Block.
var expected_taken_block: float = 0.0

## The most damage (HP and Block) the attacker deals in any branch that can happen.
var max_damage: int = 0

## Expected damage the attacker deals in the branches where it is defeated, given that it is; 0
## when it never is. The damage it gets in before it dies.
var expected_damage_before_defeat: float = 0.0

## Probability that the defender ends the exchange Exposed (Stance 0).
var stance_break_probability: float = 0.0

## Sum of every branch's probability: 1.0 when [member complete].
var total_probability: float = 0.0

## Resolver runs made, branches that can't happen included.
var branch_count: int = 0

## Whether every branch was enumerated within the budget.
var complete: bool = true

## Diagnostics the branches reported, in branch order, for the main thread to log.
var diagnostics: PackedStringArray = []


## One line for logs and comparisons: kill, death and the expected damage.
func to_text() -> String:
	var parts: PackedStringArray = [
		"kill %.6f death %.6f" % [kill_probability, death_probability],
		"dealt %.6f+%.6f" % [expected_dealt_hp, expected_dealt_block],
		"taken %.6f+%.6f" % [expected_taken_hp, expected_taken_block],
		"max %d before_defeat %.6f" % [max_damage, expected_damage_before_defeat],
		"break %.6f p %.6f n %d" % [stance_break_probability, total_probability, branch_count],
	]
	if not complete:
		parts.append("partial")
	return " ".join(parts)


## Runs [param resolve] once per branch: it receives a fresh [ForcedRolls], resolves the exchange
## in its own sandbox through those rolls, and returns the [Branch] it saw (null to skip one).
## Stops after [param max_branches] runs, marking the result incomplete.
static func enumerate(resolve: Callable, max_branches: int) -> ExchangeOutcome:
	var branches: Array[Branch] = []
	var pending: Array[PackedInt32Array] = [PackedInt32Array()]
	var runs: int = 0
	var complete_run: bool = true
	while not pending.is_empty():
		if runs >= max_branches:
			complete_run = false
			break
		var prefix: PackedInt32Array = pending.pop_back()
		var rolls: ForcedRolls = ForcedRolls.new(prefix)
		var branch: Branch = resolve.call(rolls)
		runs += 1
		var taken: PackedInt32Array = []
		for record: RollRecord in rolls.records:
			taken.append(record.outcome)
		if branch != null:
			branch.probability = rolls.probability()
			branch.outcomes = taken
			branches.append(branch)
		# Children: every other outcome of each roll past the prefix, with the rolls before it as
		# taken. Pushed in reverse so the stack explores them in roll order.
		var children: Array[PackedInt32Array] = []
		for i: int in range(prefix.size(), rolls.records.size()):
			var record: RollRecord = rolls.records[i]
			# The other outcome of a hit or percent roll is a success; each pick is 1 / count.
			for other: int in range(1, record.outcome_count()):
				if record.probability <= 0.0:
					continue
				var child: PackedInt32Array = taken.slice(0, i)
				child.append(other)
				children.append(child)
			if record.outcome_probability() <= 0.0:
				break
		for i: int in range(children.size() - 1, -1, -1):
			pending.append(children[i])
	var outcome: ExchangeOutcome = from_branches(branches)
	outcome.branch_count = runs
	outcome.complete = complete_run
	return outcome


## Sums [param branches] (each with its probability set) into one outcome.
static func from_branches(branches: Array[Branch]) -> ExchangeOutcome:
	var outcome: ExchangeOutcome = ExchangeOutcome.new()
	var dealt_when_defeated: float = 0.0
	for branch: Branch in branches:
		var p: float = branch.probability
		outcome.total_probability += p
		outcome.expected_dealt_hp += p * branch.dealt_hp
		outcome.expected_dealt_block += p * branch.dealt_block
		outcome.expected_taken_hp += p * branch.taken_hp
		outcome.expected_taken_block += p * branch.taken_block
		if branch.defender_defeated:
			outcome.kill_probability += p
		if branch.attacker_defeated:
			outcome.death_probability += p
			dealt_when_defeated += p * (branch.dealt_hp + branch.dealt_block)
		if branch.defender_exposed:
			outcome.stance_break_probability += p
		if p > 0.0:
			outcome.max_damage = maxi(outcome.max_damage, branch.dealt_hp + branch.dealt_block)
		outcome.diagnostics.append_array(branch.diagnostics)
	outcome.branch_count = branches.size()
	# ASSUMPTION: "expected damage before defeat" is the attacker's expected damage given that it is
	# defeated; the plan names the number but not its definition.
	if outcome.death_probability > 0.0:
		outcome.expected_damage_before_defeat = dealt_when_defeated / outcome.death_probability
	return outcome


## What one branch of an exchange did, as the resolver reports it.
class Branch:
	extends RefCounted

	## The branch's probability, set by [method ExchangeOutcome.enumerate].
	var probability: float = 0.0
	## The outcome of each roll, in order, set by [method ExchangeOutcome.enumerate].
	var outcomes: PackedInt32Array = []
	## Whether the attacker was defeated.
	var attacker_defeated: bool = false
	## Whether the defender was defeated.
	var defender_defeated: bool = false
	## Damage the attacker dealt to the defender's HP.
	var dealt_hp: int = 0
	## Damage the attacker dealt to the defender's Block.
	var dealt_block: int = 0
	## Damage the attacker took to its HP.
	var taken_hp: int = 0
	## Damage the attacker took to its Block.
	var taken_block: int = 0
	## Whether the defender ended the exchange Exposed.
	var defender_exposed: bool = false
	## The branch sandbox's diagnostics.
	var diagnostics: PackedStringArray = []
