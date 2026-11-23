# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_option_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventOptionCard
extends Button
## One option of the event as a pressable card: its title, what it does, the item, rune or
## heirloom it gives by name, its curse named with its tier and effect, and in a team vote its
## votes and whether this seat's vote is on it. The gains and curse are marked text in an
## [EffectText]: keywords coloured and explained on hover, and all of them while the card holds
## key or pad focus.
##
## An option that can't be chosen says why on the card ("Can't choose: ..."), its lines muted, and
## is disabled and out of the focus order, as [HeirloomOfferCard] treats a refused heirloom.
## Pressing it (click, or accept while focused) asks to choose or vote for it; [EventPanel] passes
## that on. It reads no input action itself.

# The look of a refused option's lines, in place of each one's own: muted labels, and muted
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

## Its index in the event's options, by [method show_option]; -1 before it.
var option_index: int = -1

## Why it can't be chosen, by [method show_option]. [b]Empty:[/b] it can.
var problem: String = ""

# Each line's look as the scene sets it, put back when an option can be chosen again.
var _styles: Dictionary[Control, StringName] = {}

@onready var _content: MarginContainer = %Content
@onready var _title_label: Label = %Title
@onready var _text_label: Label = %OptionText
@onready var _effects_text: EffectText = %Effects
@onready var _votes_label: Label = %Votes
@onready var _problem_label: Label = %Problem


func _ready() -> void:
	for line: Control in _lines():
		_styles[line] = line.theme_type_variation
	_content.minimum_size_changed.connect(fit_content)
	fit_content()


## Shows [param shown] with [param lines] under its text, keywords marked
## ([method EventScreenModel.option_lines]), refused for [param refusal] when that isn't empty,
## and [param vote_line] after them when that isn't empty. Call once the card is in the tree.
func show_option(
		shown: EventView.OptionView,
		lines: PackedStringArray,
		refusal: String,
		vote_line: String = ""
) -> void:
	option_index = shown.index
	problem = refusal
	if not is_node_ready():
		push_error("EventOptionCard: show_option before the card is in the tree - %s" % [
			shown.option.title,
		])
		return
	_title_label.text = shown.option.title
	_text_label.text = shown.option.text
	_text_label.visible = not shown.option.text.is_empty()
	_effects_text.marked_text = "\n".join(lines)
	_effects_text.visible = not lines.is_empty()
	_votes_label.text = vote_line
	_votes_label.visible = not vote_line.is_empty()
	_problem_label.text = "Can't choose: %s." % [refusal]
	_problem_label.visible = not refusal.is_empty()
	disabled = not refusal.is_empty()
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	for line: Control in _lines():
		var refused: StringName = _REFUSED_TEXT_STYLE if line is EffectText else _REFUSED_STYLE
		line.theme_type_variation = refused if disabled else _styles[line]


## The card's words as shown, one line each: the title, the option's text, each gain and curse
## (their words, without keyword tags), the votes and why it can't be chosen.
func get_card_text() -> String:
	var lines: PackedStringArray = [_title_label.text]
	if _text_label.visible:
		lines.append(_text_label.text)
	if _effects_text.visible:
		lines.append(_effects_text.get_plain_text())
	for label: Label in [_votes_label, _problem_label]:
		if label.visible:
			lines.append(label.text)
	return "\n".join(lines)


## The gains and curse as shown, keywords and all, for tests.
func get_effect_text() -> EffectText:
	return _effects_text


## Sizes the card to its content now: [member card_size]'s width, and its height or the content's,
## whichever is taller. The button doesn't lay its content out itself, so a change to the content's
## least size calls this a frame later; a layout read in the same frame (as tests do) calls it.
func fit_content() -> void:
	custom_minimum_size = Vector2(
			card_size.x, maxf(card_size.y, _content.get_combined_minimum_size().y)
	)


func _lines() -> Array[Control]:
	return [_title_label, _text_label, _effects_text, _votes_label, _problem_label]
