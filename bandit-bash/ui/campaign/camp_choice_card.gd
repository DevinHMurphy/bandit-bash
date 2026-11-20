# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camp_choice_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name CampChoiceCard
extends Button
## One of a Camp's two choices, Feast or Train: a pressable card with its name and what it does.
##
## A choice the seat can't make ([method Camp.train_option_problem], or a choice made already)
## says why on the card and is disabled and out of the focus order, as [PlacementPanel] treats a
## choice it can't take. Pressing it (click, or accept while focused) asks for it; the Camp screen
## passes that on. It reads no input action itself.

## The card's width and least height, so the two sit in a row at 1280×720 with room to spare.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(300.0, 150.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		custom_minimum_size = card_size

## The choice's name, by [method show_choice]; empty before it.
var choice_name: String = ""

## Why it can't be chosen, by [method show_choice]. [b]Empty:[/b] it can.
var problem: String = ""


func _ready() -> void:
	custom_minimum_size = card_size


## Shows the choice [param title] with its [param lines], refused for [param refusal] when that
## isn't empty.
func show_choice(title: String, lines: PackedStringArray, refusal: String) -> void:
	choice_name = title
	problem = refusal
	var shown: PackedStringArray = [title]
	shown.append_array(lines)
	if not refusal.is_empty():
		shown.append("Can't choose it: %s." % [refusal])
	text = "\n".join(shown)
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
