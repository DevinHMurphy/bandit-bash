# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     player_save_section.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

@abstract
class_name PlayerSaveSection
extends RefCounted
## Contract for a system that keeps data once per player in a campaign: roster, inventory,
## convoy, economy.
##
## Like [SaveSection], but every call names a seat. Register one instance with
## [code]SaveService.register_player_section()[/code]; [code]SaveService[/code] then calls it once
## per entry in [member CampaignData.players], so it works for any player count. Seats are stable
## for the life of a campaign ([member CampaignData.PlayerRun.seat]); solo is seat 0.[br]
## On the host this one instance holds every player's data, which is why the host can save them
## all. Clients never save campaign data. Data rules are the same as [SaveSection].
##
## @tutorial(Save system plan): docs/plans/2026-10-13-save-system.md


## Returns this section's key in each player's entry, e.g. [code]"inventory"[/code]. Must never
## change.
@abstract func get_key() -> String


## Returns the version of the data [method capture] produces, starting at 1. Raise it whenever
## the data's shape changes, and handle the old shape in [method migrate].
@abstract func get_version() -> int


## Returns the data of the player in [param seat] as plain JSON values.
@abstract func capture(seat: int) -> Dictionary


## Takes [param data] as the state of the player in [param seat]. [param data] is already
## migrated to [method get_version]. Returns [constant OK], or an error that stops the load.
@abstract func restore(seat: int, data: Dictionary) -> Error


## Sets the player in [param seat] to their state at the start of a run.
@abstract func reset(seat: int) -> void


## Forgets every seat; the campaign was closed or ended.
@abstract func clear() -> void


## Upgrades [param data], saved at [param from_version], to [method get_version] in place.
##
## Called only when [param from_version] is lower. The default fails loudly, so raising the
## version without writing a migration can't silently misread old saves.
## Returns [constant OK], or an error that stops the load.
func migrate(_data: Dictionary, from_version: int) -> Error:
	push_error(
			"PlayerSaveSection: '%s' has no migration from version %d to %d."
			% [get_key(), from_version, get_version()]
	)
	return ERR_UNAVAILABLE
