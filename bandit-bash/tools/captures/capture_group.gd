# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     capture_group.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## One group of shots for [code]tools/capture_screens.gd[/code], and the helpers every group
## shares: the router and services reached as nodes, waits, the throwaway run, battle access,
## and NOTE and FAIL lines. A group is a script in this folder named
## [code]<number>_<name>.gd[/code] that extends this one by path and overrides [method run]. All
## groups play one run in their numbers' order, so each starts where the one before left the game.
## Never names an autoload (a [code]--script[/code] run compiles before they register); it
## reaches them as nodes. Report lines go to stdout, which is the tool's output.

# SceneRouter.Screen values (the script can't name the autoload; see the class doc).
const SCREEN_START: int = 0
const SCREEN_LOBBY: int = 1
const SCREEN_LOADING: int = 2
const SCREEN_GAMEPLAY: int = 3
const SCREEN_RESULTS: int = 4
const SCREEN_MAIN_MENU: int = 5
const SCREEN_OPTIONS: int = 6
const SCREEN_SAVE_SELECT: int = 7
const SCREEN_NEW_RUN: int = 8
const SCREEN_MAP: int = 9
const SCREEN_COMBAT_RESULTS: int = 10

# Any fixed run seed, and the save file the throwaway run is written to.
const RUN_SEED: int = 0x51A7E
const SAVE_NUMBER: int = 1

# Frames left after a scene change or an action for layout, focus and tweens to settle.
const SETTLE_FRAMES: int = 20

# Real time left before a victory shot, past its 250 ms fades: frames alone can run faster than
# the fades in a windowed run.
const FADE_WAIT: float = 0.4

## The runner, set by [method attach] before [method run].
var tree: SceneTree = null

# The runner's capture, which numbers the shot, saves it and lists its layout issues.
var _capture_shot: Callable = Callable()


## Takes this group's shots. Returns false to end the run here; the runner still prints the
## shot and issue counts.
func run() -> bool:
	await frames(0)
	return true


## Called by the runner before [method run].
func attach(runner: SceneTree, capture_shot: Callable) -> void:
	tree = runner
	_capture_shot = capture_shot


## Saves the window as the next shot, [code]<nn>_<shot_name>.png[/code].
func capture(shot_name: String) -> void:
	await _capture_shot.call(shot_name)


## Waits [constant FADE_WAIT] seconds of real time, then captures, so a fade has ended.
func fade_capture(shot_name: String) -> void:
	await tree.create_timer(FADE_WAIT).timeout
	await capture(shot_name)


## Opens [param screen] through the router, lets it settle, and captures it.
func goto(screen: int, shot_name: String) -> void:
	node(^"SceneRouter").call(&"goto_screen", screen)
	await frames(SETTLE_FRAMES)
	await capture(shot_name)


func frames(count: int) -> void:
	for _frame: int in count:
		await tree.process_frame


## The router's current screen, a SceneRouter.Screen value.
func router_screen() -> int:
	return node(^"SceneRouter").get(&"current_screen")


func scene() -> Node:
	return tree.current_scene


## A node under the root, such as an autoload ([code]^"SaveService"[/code]).
func node(path: NodePath) -> Node:
	return tree.root.get_node(path)


## Prints a NOTE line: a shot staged in the throwaway run, or one skipped.
func note(text: String) -> void:
	print("NOTE  %s" % [text])


## Prints a FAIL line: a step that didn't reach the screen it needs.
func fail(text: String) -> void:
	print("FAIL  %s" % [text])


## Opens save file [constant SAVE_NUMBER], the throwaway run's.
func open_save() -> void:
	node(^"SaveService").call(&"open_save_file", SAVE_NUMBER)


## Starts the throwaway solo run in the open save file, seeded [constant RUN_SEED].
func start_run() -> Error:
	return node(^"SaveService").call(&"start_new_solo_run", RUN_SEED)


## Closes the save file and continues the run from it, as Save & Quit then Continue Run do.
func reopen_run() -> Error:
	var saves: Node = node(^"SaveService")
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", SAVE_NUMBER)
	return saves.call(&"continue_solo_run")


## The throwaway run's campaign session.
func campaign() -> CampaignSession:
	return node(^"CampaignService").get(&"session")


## The battle screen's view; the battle screen must be open.
func battle_view() -> BattleView:
	return scene().call(&"get_view")


## The battle screen's controller; the battle screen must be open.
func battle_controller() -> BattleController:
	return scene().call(&"get_controller")


## The first player unit on the board.
func first_player(session: CombatSession) -> String:
	return session.state.units_of(CombatFact.CombatSide.PLAYER)[0]


## Plays the view's queued animations through, up to ten seconds of them.
func settle(view: BattleView) -> void:
	for _step: int in 600:
		if view.is_settled():
			return
		view.advance(1.0 / 60.0)


## The first acting unit with an attack target from some tile it can reach, as
## [code][unit_id, path, ActionOption][/code]; empty when none has one.
func find_attack(session: CombatSession) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if not TurnInputModel.can_act(session, unit_id):
			continue
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				var is_attack: bool = option.kind == TurnInputModel.ActionKind.ATTACK
				if is_attack and not option.targets.is_empty():
					return [unit_id, path, option]
	return []
