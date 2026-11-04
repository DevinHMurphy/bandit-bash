# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_panel.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattlePanel
extends PanelContainer
## A panel [PanelHost] stacks: the action menu, the target picker, the confirm dialog.
##
## A panel draws the payload it is opened with ([method open_with]) and reports what the player
## did through its signals; it never reaches for the controller or the session (Godot_FE
## [code]12_ui_architecture.md[/code], FR-UI-2 and its PanelHost recipe). Stepping back is the
## host's: the controller calls [method PanelHost.back] on cancel, so a panel needs no back
## handling of its own. Each panel scene's script extends this one.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The player chose [param result]: what it is depends on the panel (an action, a target, a yes).
signal confirmed(result: Variant)

## The player pressed the panel's own Back.
signal cancelled()

## The player moved onto [param result] without choosing it yet, such as a focused target.
signal highlighted(result: Variant)


## Draws [param payload]. Called once, after the panel is in the tree. Each panel says what its
## payload is.
func open_with(_payload: Variant) -> void:
	pass


## Gives keyboard focus to the panel's first choice. Called whenever the panel becomes the top of
## the stack.
func focus_first() -> void:
	pass


## Links [param rows], a column of choices in the tree, so up and down move between neighbours and
## stop at the ends, never leaving the column for another widget. Set explicitly, so it works
## before the column's first layout pass.
static func chain_focus(rows: Array[Button]) -> void:
	for i: int in rows.size():
		var row: Button = rows[i]
		var above: Button = rows[maxi(i - 1, 0)]
		var below: Button = rows[mini(i + 1, rows.size() - 1)]
		row.focus_neighbor_top = row.get_path_to(above)
		row.focus_neighbor_bottom = row.get_path_to(below)
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)
		row.focus_previous = row.focus_neighbor_top
		row.focus_next = row.focus_neighbor_bottom
