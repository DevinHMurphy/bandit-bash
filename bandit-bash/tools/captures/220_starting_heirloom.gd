# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     220_starting_heirloom.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The starting heirloom offer and the first sub-choice it offers (Back from it), then the first
## heirloom that asks nothing more taken, else the first that can be, pressing each sub-choice's
## focused choice until the map opens. Ends the whole run if the map doesn't open.[br]
## Needs: Loading continued into the new run (200_run_start).

# Sub-choice screens pressed through at most after taking the heirloom.
const MAX_CHOICE_PRESSES: int = 8


func run() -> bool:
	if router_screen() != SCREEN_STARTING_HEIRLOOM:
		fail("the new run opened screen %d, not the starting heirloom offer" % [router_screen()])
		return false
	await capture("starting_heirloom")
	var view: StartingOfferView = scene().call(&"get_view")
	var picks: Vector2i = _pick_cards(view)
	var simple: int = picks.x
	var asking: int = picks.y
	if asking >= 0:
		view.get_cards()[asking].pressed.emit()
		await frames(SETTLE_FRAMES)
		await capture("starting_choice")
		view.step_back()
		await frames(SETTLE_FRAMES)
	else:
		note("this seed's offer asks no sub-choice, so starting_choice isn't shot")
	var taken: int = simple if simple >= 0 else asking
	if taken < 0:
		fail("no starting heirloom can be taken")
		return false
	view.get_cards()[taken].pressed.emit()
	for _press: int in MAX_CHOICE_PRESSES:
		await frames(SETTLE_FRAMES)
		if router_screen() != SCREEN_STARTING_HEIRLOOM:
			break
		var focused: Button = tree.root.gui_get_focus_owner() as Button
		if focused != null:
			focused.pressed.emit()
	return router_screen() == SCREEN_MAP


# The first enabled card that asks nothing more (x) and the first that asks a sub-choice (y), each
# -1 when there is none. Gold and an extra heirloom ask nothing.
func _pick_cards(view: StartingOfferView) -> Vector2i:
	var offer: StartingOffer = StartingOffer.pending(campaign().run.seat_run(0))
	var cards: Array[Button] = view.get_cards()
	var simple: int = -1
	var asking: int = -1
	for index: int in cards.size():
		var bonus: StartingHeirloomDefinition.Bonus = StartingOffer.definition_of(
				offer.options[index], EffectCatalog.index()
		).bonus
		var asks: bool = (
				bonus != StartingHeirloomDefinition.Bonus.NONE
				and bonus != StartingHeirloomDefinition.Bonus.GOLD
				and bonus != StartingHeirloomDefinition.Bonus.HEIRLOOM
		)
		if cards[index].disabled:
			continue
		if asks and asking < 0:
			asking = index
		elif not asks and simple < 0:
			simple = index
	return Vector2i(simple, asking)
