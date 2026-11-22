# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_results_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 21, 2026
# ==============================================================================

extends Control
## A combat's results when the battle is gone: a run continued at a won combat's results shows its
## [VictoryOverlay] here, over a plain [code]bg[/code] backdrop, read from the saved run. After a
## win in play the battle screen shows the same overlay over the board instead. The overlay opens
## for the local seat ([method CampaignService.local_seat]), as resumed, so it starts on Rewards
## once a reward is taken. Opened at any other stage, it sends the run on at once. Reads no input
## itself; the overlay and the pause menu do.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

@onready var _backdrop: ColorRect = %Backdrop
@onready var _overlay: VictoryOverlay = %VictoryOverlay


func _ready() -> void:
	_backdrop.color = UiTokens.color(UiTokens.BG)
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.COMBAT_RESULTS:
		RunScreen.go()
		return
	_overlay.open(CampaignService.local_seat(), true)


## The victory sequence shown.
func get_overlay() -> VictoryOverlay:
	return _overlay
