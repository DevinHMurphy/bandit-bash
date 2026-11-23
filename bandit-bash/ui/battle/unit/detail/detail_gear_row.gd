# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_gear_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name DetailGearRow
extends HBoxContainer
## One slot in the [UnitDetailPanel]'s gear: its heading (Weapon, Stowed, Equipment, Pouch), the
## item's 24-unit icon and name, and under it the weapon's profile or the item's effect text
## (ui-lift.md, Unit detail pop-up), a weapon's led by its [ProfileMark] in its unit's side's
## style (RF-039). Holds no rules: the panel formats the lines.[br]
## While it shows text it is a focus stop the panel steps keys and pads through (the mouse never
## focuses it), so key or pad focus shows its keywords beside it ([EffectText]); it draws the
## theme's focus look ([code]Button[/code]'s [code]focus[/code] style) while that focus is on it.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The name shown when the slot holds nothing.
@export var empty_text: String = "—"

@onready var _heading: Label = %Heading
@onready var _icon: RewardIcon = %Icon
@onready var _item: Label = %Item
@onready var _detail: EffectText = %Detail
@onready var _mark: ProfileMark = %ProfileMark


func _ready() -> void:
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	if has_focus(true):
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))


## Shows [param heading] with [param item_icon], [param item_name] and [param detail] under it,
## its keywords coloured ([EffectTerms] markup; plain text shows as written); an empty name shows
## [member empty_text] and no icon, a null icon the placeholder mark, and an empty detail hides
## its line and makes the row no focus stop. A weapon's [param profile] leads the detail as a
## [ProfileMark] in [param side]'s style; neither side (the default) shows no mark.
func show_gear(
		heading: String,
		item_name: String,
		detail: String,
		item_icon: Texture2D = null,
		side: CombatFact.CombatSide = CombatFact.CombatSide.NONE,
		profile: WeaponTriangle.Profile = WeaponTriangle.Profile.NONE,
) -> void:
	_heading.text = heading
	_item.text = item_name if not item_name.is_empty() else empty_text
	_icon.texture = item_icon
	_icon.visible = not item_name.is_empty()
	_detail.marked_text = detail
	_detail.visible = not detail.is_empty()
	_mark.show_mark(side, profile)
	_mark.visible = _detail.visible and _mark.is_shown()
	focus_mode = Control.FOCUS_ALL if _detail.visible else Control.FOCUS_NONE


## The profile mark, for tests; shown only on a weapon's row.
func get_profile_mark() -> ProfileMark:
	return _mark


## The icon shown, for tests; null while hidden or the placeholder.
func get_icon() -> Texture2D:
	return _icon.texture if _icon.visible else null


## The detail text, for tests of its keywords and tooltips.
func get_effect_text() -> EffectText:
	return _detail


## Its lines as shown, for tests: heading, item, detail (its words, without keyword tags).
func get_texts() -> PackedStringArray:
	return PackedStringArray([_heading.text, _item.text, _detail.get_plain_text()])
