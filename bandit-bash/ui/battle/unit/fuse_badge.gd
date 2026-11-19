# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fuse_badge.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name FuseBadge
extends Panel
## A lit powder keg's fuse on its [UnitInfo]: the enemy Phase Ends left before it explodes, the
## current phase's included ([member MapState.ObjectState.fuse]), as a number on a
## [code]danger_fill[/code] chip (rebalance-and-features.md RF-021). The number carries it, so it
## never relies on the colour.
##
## [UnitInfo] says how many ([method show_fuse]); the badge holds no rules. Its look is the
## theme's [code]FuseBadge[/code] panel and [code]FuseBadgeLabel[/code] label styles
## ([code]battle_theme.tres[/code]).
##
## @tutorial(Map objects): docs/design/map-objects.md

## The fuse shown; -1 for none, which hides the badge.
var fuse: int = -1

@onready var _count: Label = %Count


func _ready() -> void:
	show_fuse(fuse)


## Shows [param value] Phase Ends left; below 0 hides the badge (no lit fuse).
func show_fuse(value: int) -> void:
	fuse = maxi(value, -1)
	_count.text = str(maxi(fuse, 0))
	visible = fuse >= 0


## The number shown, for tests; empty while hidden.
func get_text() -> String:
	return _count.text if visible else ""
