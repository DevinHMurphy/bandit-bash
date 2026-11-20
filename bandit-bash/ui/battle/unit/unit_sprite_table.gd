# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_sprite_table.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
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
## @tutorial(Art sources): docs/design/art-sources.md

# The table's picks where Godot_FE had no exact match (ui-lift.md decision 10; art-sources.md lists
# every file's source):
# ASSUMPTION: cutthroat - bladehand (paired knives, as its dagger); corsair rejected (sword-armed).
# ASSUMPTION: hexer - sea_witch; bone_mancer rejected (reads like the player Shaman).
# hound - the user's hound.png (32rogues' wolf), the user's pick.
# ASSUMPTION: raider - axe_cavalier (mounted, as the class); marauder rejected (on foot).
# ASSUMPTION: shieldbearer - Bulwark (tower shield); sword_armor went to the Iron Wall.
# ASSUMPTION: warcaller - banner_bearer; sanctioner rejected.
# bloodhound - the user's own blood_hound.png, the user's pick.
# ASSUMPTION: brigand_captain - Destroyer; a tinted vandal and tier4/captain rejected.
# ASSUMPTION: hex_matron - tier1/herbalist (crooked staff, earthy greens), apart from the pale,
# purple Shaman and the Hexer; bone_mancer, dark_imp, bishop, Cleric and goblin_caster rejected.
# ASSUMPTION: iron_wall - sword_armor; a tinted Bulwark rejected.
# ASSUMPTION: powder_baron - gunner (a firearm, for the powder); a tinted vandal rejected.
# ASSUMPTION: powder kegs - the dungeon tile sheet's barrel; Godot_FE has no keg.
# NOTE: breakables key by their display label ("Powder Keg"), which MapObjects sets as their type.
## The sprite of each unit type or enemy class id, or breakable label: one 32 × 32 image, drawn
## whole.[br]
## [b]Empty:[/b] every unit shows its letters.
@export var sprites: Dictionary[String, Texture2D] = {}


## The sprite for [param unit_type]; null when the table has none.
func sprite_for(unit_type: String) -> Texture2D:
	var texture: Texture2D = sprites.get(unit_type, null)
	return texture
