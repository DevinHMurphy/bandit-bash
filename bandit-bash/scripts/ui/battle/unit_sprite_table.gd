# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_sprite_table.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name UnitSpriteTable
extends Resource
## The sprite each unit type and enemy class is drawn with on the battle board (combat UI plan,
## question 22), kept in one editable table: [code]assets/sprites/units/unit_sprites.tres[/code].
##
## Keys are content ids, a [UnitTypeDefinition]'s or an [EnemyClassDefinition]'s [code]id[/code],
## as [method CombatState.unit_type_of] gives them. A type with no entry, or a null one, is drawn
## with its letters ([UnitToken]). Presentation only: rules never read it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The sprite of each unit type or enemy class id: one 32 × 32 image, drawn whole.[br]
## [b]Empty:[/b] every unit shows its letters.
@export var sprites: Dictionary[String, Texture2D] = {}


## The sprite for [param unit_type]; null when the table has none.
func sprite_for(unit_type: String) -> Texture2D:
	var texture: Texture2D = sprites.get(unit_type, null)
	return texture
