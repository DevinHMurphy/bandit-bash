# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     380_battle_pause.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The battle's pause menu, opened over the board and closed again.[br]
## Needs: the battle screen open (250_campaign_map).


func run() -> bool:
	var pause: Node = scene().get_node(^"PauseMenu")
	pause.call(&"open")
	await frames(SETTLE_FRAMES)
	await capture("battle_pause")
	pause.call(&"close")
	await frames(SETTLE_FRAMES)
	return true
