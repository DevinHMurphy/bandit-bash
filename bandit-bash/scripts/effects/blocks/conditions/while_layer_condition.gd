# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_layer_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhileLayerCondition
extends EffectCondition
## Passes while this unit stands on a darkness layer: "while on Gloom or deeper", "while on Abyss".
##
## Layers follow the-darkness.md: each wave that enters a tile deepens it one layer.
##
## @tutorial(The darkness): docs/design/the-darkness.md

## A tile's darkness layer, by waves that have entered it. Saved as an int: [b]append only[/b].
enum Layer {
	## No darkness.
	DRY = 0,
	## One wave.
	DUSK = 1,
	## Two waves.
	GLOOM = 2,
	## Three or more waves.
	ABYSS = 3,
}

## The layer this unit's tile must be on.
@export var layer: Layer = Layer.DUSK

## Whether deeper layers pass too. [b]Off:[/b] only [member layer] itself.
@export var or_deeper: bool = false


func describe() -> String:
	var layer_name: String = String(Layer.find_key(layer)).capitalize()
	return "while on %s%s" % [layer_name, " or deeper" if or_deeper else ""]
