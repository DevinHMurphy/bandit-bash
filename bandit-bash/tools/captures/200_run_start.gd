# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     200_run_start.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Starts the throwaway solo run, gives it heirlooms, and shoots Loading on the way to the
## starting heirloom offer; ends the whole run if the run doesn't start.[br]
## Needs: save file [constant SAVE_NUMBER] open (100_boot_menus).


func run() -> bool:
	var err: Error = start_run()
	if err != OK:
		fail("a new solo run did not start: %s" % [error_string(err)])
		return false
	_stage_heirlooms()
	await goto(SCREEN_LOADING, "loading")
	(scene().get_node(^"%ContinueButton") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	return true


# Besides the starting heirloom it takes, this throwaway run is given heirlooms before the map for
# the battle's heirloom bar, said in a NOTE: War Ledger with its campaign count at 7, Breaker's
# Maul, Burglar's Roll, Iron Rations, and two curses, Shaken Footing and Haunted.
func _stage_heirlooms() -> void:
	var seat_run: SeatRun = campaign().run.seat_run(0)
	var ledger: SeatRun.OwnedHeirloom = seat_run.add_heirloom("war_ledger")
	ledger.counters["double_damage"] = 7
	for heirloom_id: String in [
		"breakers_maul", "burglars_roll", "iron_rations", "shaken_footing", "haunted",
	]:
		seat_run.add_heirloom(heirloom_id)
	note("besides its starting heirloom, this run is given War Ledger (7 / 10),"
			+ " Breaker's Maul, Burglar's Roll, Iron Rations, Shaken Footing and Haunted")
