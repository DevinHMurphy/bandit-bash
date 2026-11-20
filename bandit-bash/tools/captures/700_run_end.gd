# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     700_run_end.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The run's end screen.[br]
## Needs: the run ended as lost (500_campaign_after_battle), so it shows a lost run and its seed.


func run() -> bool:
	await goto(SCREEN_RESULTS, "run_end")
	return true
