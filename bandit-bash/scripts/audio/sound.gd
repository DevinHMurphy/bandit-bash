# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sound.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name Sound
extends RefCounted
## Plays a cue through the [code]AudioService[/code] autoload from presentation code that must not
## name the autoload: scripts a test suite compiles before autoloads exist ([BattleController],
## the victory sequence). Finds the service at run time and does nothing without one.[br]
## [b]Presentation only:[/b] rules code never calls it (gdscript.md, Event bus and effects).
## Static; never instantiated.
##
## @tutorial(Audio scope): docs/design/audio.md

## The autoload's node path under the root.
const SERVICE_PATH: NodePath = ^"/root/AudioService"


## Plays cue [param cue_id]; nothing when the service isn't running.
static func play(cue_id: StringName) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var service: Node = tree.root.get_node_or_null(SERVICE_PATH)
	if service != null:
		service.call(&"play_cue", cue_id)
