# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_file_summary.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name SaveFileSummary
extends RefCounted
## What Save Select shows for one save file, read without opening it.
##
## Built by [code]SaveService.get_summary()[/code]. Covers the profile and both campaign slots;
## the multiplayer slot only ever holds a campaign this save file hosts.

## Whether and how the save file can be opened.
enum State {
	## No profile on disk. Opening creates the save file.
	EMPTY = 0,
	## Readable. [member player_name] and [member play_time_seconds] are filled.
	READY = 1,
	## Files exist but none is readable. It can only be deleted.
	UNREADABLE = 2,
	## Written by a newer game version. This build can't open it.
	TOO_NEW = 3,
}

## Which save file this is, 1 to [code]SaveService.SAVE_FILE_COUNT[/code].
var save_number: int = 0

## Whether and how the save file can be opened.
var state: State = State.EMPTY

## True when reading it fell back to a [code].tmp[/code] or [code].bak[/code] copy. The repair
## already happened, so this is true only on the read that did it.
var was_recovered: bool = false

## Cached Steam persona name. Empty unless [member state] is [constant READY].
var player_name: String = ""

## Total play time.[br]
## [b]Units:[/b] seconds. 0 unless [member state] is [constant READY].
var play_time_seconds: int = 0

## The solo campaign slot, using the same states: [constant EMPTY] means no run in progress.
## Only read when [member state] is [constant READY].
var solo_state: State = State.EMPTY

## Floors climbed in the solo run. 0 unless [member solo_state] is [constant READY].
var solo_floors_climbed: int = 0

## When the solo run was last saved.[br]
## [b]Units:[/b] Unix seconds, UTC. 0 unless [member solo_state] is [constant READY].
var solo_last_opened: int = 0

## The multiplayer campaign slot, using the same states: [constant EMPTY] means no campaign.
## Only read when [member state] is [constant READY].
var multi_state: State = State.EMPTY

## Seats in the hosted campaign. 0 unless [member multi_state] is [constant READY].
var multi_player_count: int = 0

## When the hosted campaign was last saved.[br]
## [b]Units:[/b] Unix seconds, UTC. 0 unless [member multi_state] is [constant READY].
var multi_last_opened: int = 0
