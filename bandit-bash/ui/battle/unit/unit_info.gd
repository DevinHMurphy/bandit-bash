# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_info.gd
# Author:
# Created:  November 6, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitInfo
extends Control
## One unit's bars, numbers and icons on the screen-space [UnitInfoLayer]: its [HpBar] with the
## HP inside and its side's [SideShape] at the bar's end, its [StancePips], its [BlockBadge], the
## [BlockBanMark] while it can't gain Block, the range-tracked icon (combat UI plan, question
## 29 (2); UI12), a lit keg's [FuseBadge] and an elite's [EliteMark] in that same corner.
##
## Its origin is the unit's centre on screen; the layout is authored in screen pixels, around a
## tile drawn about 59 px wide (M1 at the 1280 × 720 base draws about 71). [UnitToken] gives it
## each value as the facts play and holds the values; this only draws them and holds no rules.
## [UnitInfoLayer] places it over its token whenever the camera or the token moves.[br]
## [b]The pips[/b] are a child of the HP bar, anchored along its bottom edge, so they span the
## bar's width however the bar is sized or moved; set their height in the scene.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

@onready var _hp_bar: HpBar = %HpBar
@onready var _stance_pips: StancePips = %StancePips
@onready var _block_badge: BlockBadge = %BlockBadge
@onready var _block_ban: BlockBanMark = %BlockBanMark
@onready var _range_icon: Control = %RangeTrackedIcon
@onready var _fuse_badge: FuseBadge = %FuseBadge
# A keg (the fuse's owner) is never prefixed, so the elite mark shares the fuse's corner.
@onready var _elite_mark: EliteMark = %EliteMark
@onready var _side_shape: SideShape = %SideShape


## Shows [param current] HP of [param maximum] on the bar and in its number.
func show_hp(current: int, maximum: int) -> void:
	_hp_bar.show_hp(current, maximum)


## Shows [param current] Stance of [param maximum] on the pips; returns their change tween on a
## drop, paused for the caller to step, else null ([method StancePips.show_stance]).
func show_stance(current: int, maximum: int) -> Tween:
	return _stance_pips.show_stance(current, maximum)


## Flashes the HP bar from the HP shown to [param after] HP, the open forecast's
## ([method HpBar.show_preview]).
func show_hp_preview(after: int) -> void:
	_hp_bar.show_preview(after)


## Flashes no HP.
func clear_hp_preview() -> void:
	_hp_bar.clear_preview()


## Dims and flashes the pips the open forecast would break, down to [param after] Stance.
func show_stance_preview(after: int) -> void:
	_stance_pips.show_preview(after)


## Dims and flashes no pip.
func clear_stance_preview() -> void:
	_stance_pips.clear_preview()


## Shows [param amount] Block on the badge.
func show_block(amount: int) -> void:
	_block_badge.show_block(amount)


## Shows the [BlockBanMark] while [param is_banned]: the unit can't gain Block.
func show_block_ban(is_banned: bool) -> void:
	_block_ban.show_ban(is_banned)


## Shows or hides the range-tracked icon.
func show_range_tracked(is_tracked: bool) -> void:
	_range_icon.visible = is_tracked


## Shows a lit keg's [param fuse] on the [FuseBadge]; below 0 hides it.
func show_fuse(fuse: int) -> void:
	_fuse_badge.show_fuse(fuse)


## Shows the [EliteMark] while [param is_elite]: an enemy with a prefix.
func show_elite(is_elite: bool) -> void:
	_elite_mark.show_elite(is_elite)


## Shows [param side]'s shape at the HP bar's end ([SideShape]).
func show_side(side: CombatFact.CombatSide) -> void:
	_side_shape.show_side(side)


## The fuse badge.
func get_fuse_badge() -> FuseBadge:
	return _fuse_badge


## The elite mark.
func get_elite_mark() -> EliteMark:
	return _elite_mark


## The side shape.
func get_side_shape() -> SideShape:
	return _side_shape


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


## Whether the [BlockBanMark] shows.
func is_block_ban_shown() -> bool:
	return _block_ban.is_shown()
