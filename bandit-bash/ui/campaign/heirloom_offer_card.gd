# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_offer_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name HeirloomOfferCard
extends Button
## One heirloom on offer: a pressable card with its icon, name and every line of its text
## ([method HeirloomDefinition.describe_marked]; a starting heirloom's run-start bonus included),
## keywords coloured and explained by an [EffectText].
##
## A refused heirloom ([method StartingOffer.option_problem]) says why on the card, its lines
## muted, and is disabled and out of the focus order, as [PlacementPanel] treats a choice it
## can't take. Pressing it (click, or accept while focused) asks to take it; the view holding it
## ([StartingOfferView], [KeyHeirloomPicker]) passes that on, and [ChestView] shows it
## unpressable. It reads no input action itself.

# The look of a refused heirloom's lines, in place of each one's own: muted labels, and muted
# effect text with its keywords still coloured.
const _REFUSED_STYLE: StringName = &"MutedLabel"
const _REFUSED_TEXT_STYLE: StringName = &"EffectTextMuted"

## The card's width and least height, so three sit in a row at 1280×720 with room to spare.
## Taller content makes it taller.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(300.0, 200.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		fit_content()

## The heirloom's name, by [method show_heirloom]; empty before it.
var heirloom_name: String = ""

## Why it can't be taken, by [method show_heirloom]. [b]Empty:[/b] it can.
var problem: String = ""

# Each line's look as the scene sets it, put back when an heirloom can be taken again.
var _styles: Dictionary[Control, StringName] = {}

@onready var _content: MarginContainer = %Content
@onready var _heirloom_icon: TextureRect = %HeirloomIcon
@onready var _name_label: Label = %HeirloomName
@onready var _effects_text: EffectText = %Effects
@onready var _problem_label: Label = %Problem


func _ready() -> void:
	for line: Control in _lines():
		_styles[line] = line.theme_type_variation
	_content.minimum_size_changed.connect(fit_content)
	fit_content()


## Shows the heirloom [param definition] (content id [param heirloom_id], its name when the
## catalog lacks it), refused for [param refusal] when that isn't empty.
func show_heirloom(
		definition: HeirloomDefinition, heirloom_id: String, refusal: String
) -> void:
	heirloom_name = heirloom_id if definition == null else definition.display_name
	problem = refusal
	if not is_node_ready():
		push_error("HeirloomOfferCard: show_heirloom before the card is in the tree - %s" % [
			heirloom_id,
		])
		return
	_name_label.text = heirloom_name
	var lines: PackedStringArray = (
			PackedStringArray() if definition == null else definition.describe_marked()
	)
	_effects_text.marked_text = "\n".join(lines)
	_effects_text.visible = not lines.is_empty()
	_problem_label.text = "Can't take it: %s." % [refusal]
	_problem_label.visible = not refusal.is_empty()
	_heirloom_icon.texture = null if definition == null else definition.icon
	_heirloom_icon.visible = _heirloom_icon.texture != null
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	for line: Control in _lines():
		var refused: StringName = _REFUSED_TEXT_STYLE if line is EffectText else _REFUSED_STYLE
		line.theme_type_variation = refused if disabled else _styles[line]


## The card's words as shown, one line each: the name, each effect line (its words, without
## keyword tags) and why it can't be taken.
func get_card_text() -> String:
	var lines: PackedStringArray = [_name_label.text]
	if _effects_text.visible:
		lines.append(_effects_text.get_plain_text())
	if _problem_label.visible:
		lines.append(_problem_label.text)
	return "\n".join(lines)


## The icon shown; null for an heirloom with none.
func get_heirloom_icon() -> Texture2D:
	return _heirloom_icon.texture


## Sizes the card to its content now: [member card_size]'s width, and its height or the content's,
## whichever is taller. The button doesn't lay its content out itself, so a change to the content's
## least size calls this a frame later; a layout read in the same frame (as tests do) calls it.
func fit_content() -> void:
	custom_minimum_size = Vector2(
			card_size.x, maxf(card_size.y, _content.get_combined_minimum_size().y)
	)


func _lines() -> Array[Control]:
	return [_name_label, _effects_text, _problem_label]
