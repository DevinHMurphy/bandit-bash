# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     nav_button.gd
# Author:
# Created:  October 9, 2026
# Modified: October 9, 2026
# ==============================================================================

class_name NavButton
extends Button
## Button that moves between screens through the [code]SceneRouter[/code] autoload.
##
## Lets a screen scene declare where its buttons lead without a script of its own. Replace it
## with real handlers on a screen once that screen needs more than navigation.

## What a press does.
enum Action {
	## Open [member target_screen].
	GOTO_SCREEN = 0,
	## Return to the screen shown before this one.
	GO_BACK = 1,
	## Close the game.
	QUIT = 2,
	## Open [member target_screen] on every connected peer. Host only; a client press is refused.
	## Behaves like [constant GOTO_SCREEN] when there is no lobby session.
	GOTO_SCREEN_FOR_EVERYONE = 3,
}

## What pressing this button does.
@export var action: Action = Action.GOTO_SCREEN

## Screen to open.
##
## Read only when [member action] is [constant GOTO_SCREEN] or [constant GOTO_SCREEN_FOR_EVERYONE];
## ignored for the other actions.
@export var target_screen: SceneRouter.Screen = SceneRouter.Screen.START


func _pressed() -> void:
	match action:
		Action.GOTO_SCREEN:
			SceneRouter.goto_screen(target_screen)
		Action.GO_BACK:
			SceneRouter.go_back()
		Action.QUIT:
			get_tree().quit()
		Action.GOTO_SCREEN_FOR_EVERYONE:
			SceneRouter.goto_screen_for_everyone(target_screen)
