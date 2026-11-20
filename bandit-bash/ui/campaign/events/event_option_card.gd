# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_option_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventOptionCard
extends Button
## One option of the event as a pressable card: its title, what it does, the item, rune or
## heirloom it gives by name, its curse named with its tier and effect, and in a team vote its
## votes and whether this seat's vote is on it.
##
## An option that can't be chosen says why on the card ("Can't choose: ..."), and is disabled
## and out of the focus order, as [HeirloomOfferCard] treats a refused heirloom. Pressing it
## (click, or accept while focused) asks to choose or vote for it; [EventPanel] passes that on.
## It reads no input action itself.

## The card's width and least height, so three sit in a row at 1280×720 with room to spare.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(300.0, 200.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		custom_minimum_size = card_size

## Its index in the event's options, by [method show_option]; -1 before it.
var option_index: int = -1

## Why it can't be chosen, by [method show_option]. [b]Empty:[/b] it can.
var problem: String = ""


func _ready() -> void:
	custom_minimum_size = card_size


## Shows [param shown] with [param lines] under its text ([method EventScreenModel.option_lines]),
## refused for [param refusal] when that isn't empty, and [param vote_line] last when that isn't
## empty.
func show_option(
		shown: EventView.OptionView,
		lines: PackedStringArray,
		refusal: String,
		vote_line: String = ""
) -> void:
	option_index = shown.index
	problem = refusal
	var text_lines: PackedStringArray = [shown.option.title]
	if not shown.option.text.is_empty():
		text_lines.append(shown.option.text)
	text_lines.append_array(lines)
	if not vote_line.is_empty():
		text_lines.append(vote_line)
	if not refusal.is_empty():
		text_lines.append("Can't choose: %s." % [refusal])
	text = "\n".join(text_lines)
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
