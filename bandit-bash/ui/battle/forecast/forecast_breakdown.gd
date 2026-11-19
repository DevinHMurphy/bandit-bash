# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_breakdown.gd
# Author:
# Created:  November 4, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ForecastBreakdown
extends VBoxContainer
## The forecast's per-stage damage breakdown, shown on the panel's toggle: each side's first landed
## hit, then each later hit whose stages differ under a [member hit_heading_format] heading, one
## line per stage (attack, mitigation, critical, multipliers, damage), as
## [method CombatForecast.HitBreakdown.to_text] lists them ([ForecastViewModel.Breakdown]).
##
## Two labels authored in the scene, the acting unit's and the target's; a side with no landed
## hit shows [member no_hit_text].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## What a side with no landed hit shows, such as a defender that can't counter.
@export var no_hit_text: String = "no hit lands"

## The heading over a later hit's stages: [code]%d[/code] which of the side's attacks it is, from 1.
@export var hit_heading_format: String = "Hit %d"

@onready var _actor_stages: Label = %ActorStages
@onready var _target_stages: Label = %TargetStages


## Shows [param model]'s breakdowns: its actor's under the first label, its target's under the
## second.
func show_breakdowns(model: ForecastViewModel) -> void:
	# A rune's model has no unit command and no hits (the panel hides the toggle for it).
	if model.command == null:
		_actor_stages.text = ""
		_target_stages.text = ""
		return
	_actor_stages.text = _side_text(model, model.command.actor_id, model.actor_label)
	_target_stages.text = _side_text(model, model.command.get_target_id(), model.target_label)


## The two sides' text, for tests: the actor's, then the target's.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_actor_stages.text, _target_stages.text])


func _side_text(model: ForecastViewModel, unit_id: String, label: String) -> String:
	var parts: PackedStringArray = []
	for stages: ForecastViewModel.Breakdown in model.breakdowns:
		if stages.unit_id != unit_id:
			continue
		if not parts.is_empty():
			parts.append(hit_heading_format % [stages.hit_number])
		parts.append("\n".join(stages.lines))
	if parts.is_empty():
		return "%s\n%s" % [label, no_hit_text]
	return "%s\n%s" % [label, "\n".join(parts)]
