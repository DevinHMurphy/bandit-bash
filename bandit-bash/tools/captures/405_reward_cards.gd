# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     405_reward_cards.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The item offer cards with their effect text and who can use them, on the three screens that
## show them: a won combat's weapon pick (a weapon the army wields, one it can't, another), the
## first card focused and listing its wielders, then the mouse over a unit icon; a pouch pick (the
## longest Pouch items' text, so the row's heights show); a Treasure chest's Legendary weapon; and
## the starting offer's Ancestral Weapon step. Each is staged on the run (the screens route by the
## run's stage), then left; the run's route is put back as 400_victory left it, on the map.[br]
## Needs: the map reached by the victory's Leave (400_victory). Runs after it, before 450.

const Fixture = preload("res://tests/campaign/node_fixture.gd")

# SceneRouter.Screen's Treasure (the script can't name the autoload; see the base).
const SCREEN_TREASURE: int = 14

# VictoryOverlay.Stage's Rewards: the script can't name the overlay, whose script names autoloads.
const STAGE_REWARDS: int = 4

const ANCESTRAL_WEAPON: String = "ancestral_weapon"

# Offers per pick and weapons in the Ancestral Weapon offer, as the real ones hold.
const OFFERS: int = 3


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the reward card shots need the map (screen %d)" % [router_screen()])
		return true
	var run_state: CampaignRunState = campaign().run
	var visited: PackedInt32Array = run_state.visited.duplicate()
	var floor_number: int = run_state.floor_number
	var at_node: int = run_state.node
	await _pick(ItemPick.Slot.WEAPON, "reward_cards_weapon")
	await _pick(ItemPick.Slot.POUCH, "reward_cards_pouch")
	await _treasure()
	await _starting_offer()
	run_state.visited = visited
	run_state.floor_number = floor_number
	run_state.node = at_node
	run_state.flow.stage = RunFlow.Stage.MAP
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# A won Standard combat's Results staged at Rewards with a pick of slot's offers, its picker
# opened and shot as shot_name (a weapon pick's icon hovered too); then the pick skipped and left.
func _pick(slot: ItemPick.Slot, shot_name: String) -> void:
	var run_state: CampaignRunState = campaign().run
	if not Fixture.enter(run_state, CampaignGraph.NodeType.STANDARD):
		note("the map has no Standard node, so %s isn't shot" % [shot_name])
		return
	var seat_run: SeatRun = run_state.seat_run(0)
	var items: Array[ItemDefinition] = (
			_weapon_offers(seat_run) if slot == ItemPick.Slot.WEAPON else _pouch_offers()
	)
	if items.size() < OFFERS:
		note("the catalog has too few offers, so %s isn't shot" % [shot_name])
		return
	run_state.flow.stage = RunFlow.Stage.RESULTS
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": CombatGrades.new().capture(), "xp": [], "level_ups": [],
	}
	var pick: ItemPick = ItemPick.new()
	pick.slot = slot
	for item: ItemDefinition in items:
		pick.offers.append(ItemPick.Offer.new(
				item.id, campaign().ids.next_item_id(item.display_name)
		))
	pick.store(seat_run)
	note("%s: a won Standard combat's Results staged with this pick" % [shot_name])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_COMBAT_RESULTS)
	await frames(SETTLE_FRAMES)
	var overlay: Node = _victory_overlay()
	if overlay == null:
		fail("the staged Results showed no victory sequence")
		return
	overlay.call(&"skip")
	while (overlay.call(&"get_stage") as int) < STAGE_REWARDS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await tree.process_frame
	await frames(SETTLE_FRAMES)
	var stage: VictoryRewardsStage = overlay.call(&"get_rewards_stage")
	var rows: Array[RewardRow] = stage.get_rows()
	if rows.is_empty():
		fail("the staged Results listed no item pick")
		return
	rows[0].pressed.emit()
	await frames(SETTLE_FRAMES)
	await fade_capture(shot_name)
	var picker: Control = overlay.call(&"get_picker") as Control
	var panel: ItemPickPanel = picker.call(&"get_pick_panel")
	if slot == ItemPick.Slot.WEAPON:
		await _hover_icon(panel, shot_name + "_hover")
	panel.get_skip_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	await frames(SETTLE_FRAMES)


# The mouse over the first unit icon of the first card that has one, shot as shot_name.
func _hover_icon(panel: ItemPickPanel, shot_name: String) -> void:
	for card: ItemOfferCard in panel.get_offer_cards():
		var icons: Array[ItemUserIcon] = card.get_usable_by().get_icons()
		if icons.is_empty():
			continue
		var point: Vector2 = icons[0].get_global_rect().get_center()
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		tree.root.push_input(motion)
		await frames(SETTLE_FRAMES)
		await capture(shot_name)
		return
	note("no card has a unit icon, so %s isn't shot" % [shot_name])


# A Treasure node with a Rare chest holding a Legendary weapon the army wields, shot; then Leave,
# answered by giving the chest up.
func _treasure() -> void:
	var run_state: CampaignRunState = campaign().run
	if not Fixture.enter(run_state, CampaignGraph.NodeType.TREASURE):
		note("the map has no Treasure node, so reward_cards_treasure isn't shot")
		return
	var seat_run: SeatRun = run_state.seat_run(0)
	var legendary: ItemDefinition = null
	for item: ItemDefinition in TreasureChest.usable_legendaries(seat_run, EffectCatalog.index()):
		if item is WeaponDefinition:
			legendary = item
			break
	if legendary == null:
		note("no Legendary weapon fits the army, so reward_cards_treasure isn't shot")
		return
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(
			legendary.id, campaign().ids.next_item_id(legendary.display_name)
	)
	chest.store(seat_run)
	note("reward_cards_treasure: a Rare chest staged with %s" % [legendary.display_name])
	await goto(SCREEN_TREASURE, "reward_cards_treasure")
	(scene().call(&"get_leave_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	(scene().call(&"get_confirm_dialog") as LeaveConfirmDialog).confirmed.emit()
	await frames(SETTLE_FRAMES)


# The starting offer staged with Ancestral Weapon alone, its weapons drawn from what the army
# wields, opened at the weapon step and shot; then the offer dropped unanswered.
func _starting_offer() -> void:
	var run_state: CampaignRunState = campaign().run
	var seat_run: SeatRun = run_state.seat_run(0)
	var weapons: Array[ItemDefinition] = _weapon_offers(seat_run)
	if weapons.size() < OFFERS:
		note("too few weapons, so reward_cards_starting_offer isn't shot")
		return
	run_state.flow.stage = RunFlow.Stage.MAP
	var offer: StartingOffer = StartingOffer.new()
	var option: StartingOffer.Option = StartingOffer.Option.new(ANCESTRAL_WEAPON)
	for weapon: ItemDefinition in weapons:
		option.weapons.append(ItemPick.Offer.new(
				weapon.id, campaign().ids.next_item_id(weapon.display_name)
		))
	offer.options.append(option)
	offer.store(seat_run)
	note("reward_cards_starting_offer: an offer of Ancestral Weapon alone staged on the map")
	node(^"SceneRouter").call(&"goto_screen", SCREEN_STARTING_HEIRLOOM)
	await frames(SETTLE_FRAMES)
	if router_screen() != SCREEN_STARTING_HEIRLOOM:
		fail("the staged offer didn't open the starting heirloom screen")
	else:
		var view: StartingOfferView = scene().call(&"get_view")
		view.get_cards()[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		await capture("reward_cards_starting_offer")
	seat_run.pending_offers.erase(StartingOffer.OFFER_KEY)


# Weapon offers: one the army wields, one it can't (when the catalog has one), then more it
# wields, OFFERS in all and of different types where it can.
func _weapon_offers(seat_run: SeatRun) -> Array[ItemDefinition]:
	var wielded: Array[ItemDefinition] = []
	var unwielded: Array[ItemDefinition] = []
	var types: Dictionary[String, bool] = {}
	for item: ItemDefinition in ItemPick.items_for(ItemPick.Slot.WEAPON, EffectCatalog.index()):
		var weapon: WeaponDefinition = item as WeaponDefinition
		if weapon == null or types.has(weapon.weapon_type):
			continue
		types[weapon.weapon_type] = true
		if ItemUsableBy.wielders(weapon, seat_run, EffectCatalog.index()).is_empty():
			unwielded.append(weapon)
		else:
			wielded.append(weapon)
	var offers: Array[ItemDefinition] = []
	offers.append_array(wielded.slice(0, 1))
	offers.append_array(unwielded.slice(0, 1))
	offers.append_array(wielded.slice(1, OFFERS - offers.size() + 1))
	return offers.slice(0, OFFERS)


# The Pouch items with the longest effect text, longest first.
func _pouch_offers() -> Array[ItemDefinition]:
	var items: Array[ItemDefinition] = ItemPick.items_for(
			ItemPick.Slot.POUCH, EffectCatalog.index()
	)
	items.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		return "\n".join(a.describe()).length() > "\n".join(b.describe()).length()
	)
	return items.slice(0, OFFERS)


# The victory sequence shown: the Results screen's.
func _victory_overlay() -> Node:
	if scene() == null or not scene().has_method(&"get_overlay"):
		return null
	return scene().call(&"get_overlay") as Node
