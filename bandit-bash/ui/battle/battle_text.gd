# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_text.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleText
extends RefCounted
## The names the battle screen shows for ids: a unit, an item, a rune or a map object by its
## display text, never by its instance id or a content id.
##
## The name is the display text [method CombatSession.describe] puts in brackets after the id
## ([method InstanceIdAllocator.label_of]), else the unit type's display name from the content
## catalog ([method type_name]), so a panel and a log line name a thing alike; ids are never taken
## apart (gdscript.md, Event bus and effects). An id with neither falls back to
## [method CombatSession.describe], so it still shows something. Reading only.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md


## The display name of [param id] on [param session]: its label, else its unit type's name, else
## [method CombatSession.describe]'s text. Empty for an empty id.
static func name_of(session: CombatSession, id: String) -> String:
	if id.is_empty():
		return ""
	var label: String = session.ids.label_of(id)
	if label.is_empty():
		label = type_name(session.state.unit_type_of(id))
	return label if not label.is_empty() else session.describe(id)


## The display name of the unit type or enemy class [param type_id] ("Battle Medic"), from the
## content catalog; the id capitalised only for one the catalog lacks. Empty for an empty id.
static func type_name(type_id: String) -> String:
	if type_id.is_empty():
		return ""
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var enemy: EnemyClassDefinition = catalog.enemy_class(type_id)
	if enemy != null and not enemy.display_name.is_empty():
		return enemy.display_name
	var unit_type: UnitTypeDefinition = catalog.unit_type(type_id)
	if unit_type != null and not unit_type.display_name.is_empty():
		return unit_type.display_name
	return type_id.capitalize()
