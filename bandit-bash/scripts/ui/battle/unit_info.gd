# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_info.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

class_name UnitInfo
extends Control
## One unit's bars, numbers and icons on the screen-space [UnitInfoLayer]: its [HpBar] with the
## HP inside, its [StancePips], its [BlockBadge] and the range-tracked icon (combat UI plan,
## question 29 (2)).
##
## Its origin is the unit's centre on screen; the layout is authored in screen pixels, around a
## tile drawn about 59 px wide (M1 framed in the default 1152 × 648 window). [UnitToken] gives it
## each value as the facts play and holds the values; this only draws them and holds no rules.
## [UnitInfoLayer] places it over its token whenever the camera or the token moves.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

@onready var _hp_bar: HpBar = %HpBar
@onready var _stance_pips: StancePips = %StancePips
@onready var _block_badge: BlockBadge = %BlockBadge
@onready var _range_icon: Control = %RangeTrackedIcon


## Shows [param current] HP of [param maximum] on the bar and in its number.
func show_hp(current: int, maximum: int) -> void:
	_hp_bar.show_hp(current, maximum)


## Shows [param current] Stance of [param maximum] on the pips; returns their change tween on a
## drop, paused for the caller to step, else null ([method StancePips.show_stance]).
func show_stance(current: int, maximum: int) -> Tween:
	return _stance_pips.show_stance(current, maximum)


## Dims the pips the open forecast would break, down to [param after] Stance.
func show_stance_preview(after: int) -> void:
	_stance_pips.show_preview(after)


## Dims no pip.
func clear_stance_preview() -> void:
	_stance_pips.clear_preview()


## Shows [param amount] Block on the badge.
func show_block(amount: int) -> void:
	_block_badge.show_block(amount)


## Shows or hides the range-tracked icon.
func show_range_tracked(is_tracked: bool) -> void:
	_range_icon.visible = is_tracked


## The HP bar.
func get_hp_bar() -> HpBar:
	return _hp_bar


## The Stance pips.
func get_stance_pips() -> StancePips:
	return _stance_pips


## The Block badge.
func get_block_badge() -> BlockBadge:
	return _block_badge


## Whether the range-tracked icon shows.
func is_range_icon_shown() -> bool:
	return _range_icon.visible
