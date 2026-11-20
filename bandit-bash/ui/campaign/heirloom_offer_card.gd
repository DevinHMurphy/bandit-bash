# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_offer_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name HeirloomOfferCard
extends Button
## One starting heirloom on offer: a pressable card with its icon, name and every line of its
## text, its run-start bonus included ([method StartingHeirloomDefinition.describe]).
##
## A refused heirloom ([method StartingOffer.option_problem]) says why on the card, and is
## disabled and out of the focus order, as [PlacementPanel] treats a choice it can't take.
## Pressing it (click, or accept while focused) asks to take it; [StartingOfferView] passes that
## on. It reads no input action itself.

## The card's width and least height, so three sit in a row at 1280×720 with room to spare.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(300.0, 200.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		custom_minimum_size = card_size

## The heirloom's name, by [method show_heirloom]; empty before it.
var heirloom_name: String = ""

## Why it can't be taken, by [method show_heirloom]. [b]Empty:[/b] it can.
var problem: String = ""


func _ready() -> void:
	custom_minimum_size = card_size


## Shows the heirloom [param definition] (content id [param heirloom_id], its name when the
## catalog lacks it), refused for [param refusal] when that isn't empty.
func show_heirloom(
		definition: StartingHeirloomDefinition, heirloom_id: String, refusal: String
) -> void:
	heirloom_name = heirloom_id if definition == null else definition.display_name
	problem = refusal
	var lines: PackedStringArray = [heirloom_name]
	if definition != null:
		lines.append_array(definition.describe())
	if not refusal.is_empty():
		lines.append("Can't take it: %s." % [refusal])
	text = "\n".join(lines)
	icon = null if definition == null else definition.icon
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
