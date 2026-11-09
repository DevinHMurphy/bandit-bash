# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_text.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name BattleText
extends RefCounted
## The names the battle screen shows for ids: a unit, an item, a rune or a map object by its
## display text, never by its instance id.
##
## The name is the display text [method CombatSession.describe] puts in brackets after the id
## ([method InstanceIdAllocator.label_of], else the unit type), so a panel and a log line name a
## thing alike; ids are never taken apart (gdscript.md, Event bus and effects). An id with no
## display text falls back to [method CombatSession.describe], so it still shows something.
## Reading only.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md


## The display name of [param id] on [param session]: its label, else its unit type, else
## [method CombatSession.describe]'s text. Empty for an empty id.
static func name_of(session: CombatSession, id: String) -> String:
	if id.is_empty():
		return ""
	var label: String = session.ids.label_of(id)
	if label.is_empty():
		label = session.state.unit_type_of(id)
	return label if not label.is_empty() else session.describe(id)
