# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_enemy_section.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name DetailEnemySection
extends VBoxContainer
## An enemy's part of the [UnitDetailPanel]: its intent and target rule as the intents show them,
## and its signature move with its effect text, keywords marked ([EffectText]), and counter, read
## as an effect card reads one ("War Horn 1/3") (ui-lift.md, Unit detail pop-up). Hidden for a
## player unit. Holds no rules.[br]
## While it shows the move's text it is a focus stop the panel steps keys and pads through (the
## mouse never focuses it), so key or pad focus shows the move's keywords beside it; it draws the
## theme's focus look ([code]Button[/code]'s [code]focus[/code] style) on its edge while that focus
## is on it, its contents [member focus_inset] inside.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The intent line: [code]%s[/code] the intent, such as "Attack Archer".
@export var intent_format: String = "Intent: %s"

## The intent line while the enemy has no intent (it doesn't act, or the intents are hidden).
@export var no_intent_text: String = "Intent: —"

## The target rule line: [code]%s[/code] the rule as its intent states it.
@export var rule_format: String = "Target rule: %s"

## The signature line: [code]%s[/code] the move's name.
@export var signature_format: String = "Signature move: %s"

## Added to the signature line for a move on a counter: [code]%d[/code] the count, then the
## period, as an effect card shows a counter.
@export var counter_format: String = " %d/%d"

## Added to the signature line while the intents show the move firing at the next enemy Phase
## Start. [b]Empty:[/b] nothing is added.
@export var next_text: String = " · fires next enemy phase"

## How far the section's contents sit inside its edge, where the focus outline draws, on every
## side, so the outline never touches the text; the style guide's row gap.[br]
## [b]Units:[/b] base units. [b]0.0:[/b] the contents reach the edge, under the outline.
@export_range(0.0, 16.0, 1.0) var focus_inset: float = 4.0

@onready var _inset: MarginContainer = %Inset
@onready var _intent: Label = %Intent
@onready var _rule: Label = %Rule
@onready var _signature: Label = %Signature
@onready var _signature_text: EffectText = %SignatureText


func _ready() -> void:
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		_inset.add_theme_constant_override(side, roundi(focus_inset))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	if has_focus(true):
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))


## Draws [param view]'s enemy lines; hides for a player unit or null. A focus stop only while it
## shows the signature move's text.
func show_enemy(view: UnitDetailViewModel) -> void:
	visible = view != null and view.side == CombatFact.CombatSide.ENEMY
	if not visible:
		focus_mode = Control.FOCUS_NONE
		return
	_intent.text = intent_format % [view.intent_text] if not view.intent_text.is_empty() else (
			no_intent_text
	)
	_rule.text = rule_format % [view.target_rule_text]
	_rule.visible = not view.target_rule_text.is_empty()
	var has_signature: bool = not view.signature_name.is_empty()
	_signature.visible = has_signature
	_signature_text.marked_text = view.signature_marked_text if has_signature else ""
	_signature_text.visible = has_signature and not view.signature_marked_text.is_empty()
	focus_mode = Control.FOCUS_ALL if _signature_text.visible else Control.FOCUS_NONE
	if not has_signature:
		return
	var line: String = signature_format % [view.signature_name]
	if view.signature_period > 0:
		line += counter_format % [view.signature_count, view.signature_period]
	if view.is_signature_next:
		line += next_text
	_signature.text = line


## The signature move's text, for tests of its keywords and tooltips.
func get_signature_text() -> EffectText:
	return _signature_text


## Its lines as shown, for tests: intent, rule, signature, the signature's text (its words,
## without keyword tags; a hidden one as empty).
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for label: Label in [_intent, _rule, _signature]:
		texts.append(label.text if label.visible else "")
	texts.append(_signature_text.get_plain_text() if _signature_text.visible else "")
	return texts
