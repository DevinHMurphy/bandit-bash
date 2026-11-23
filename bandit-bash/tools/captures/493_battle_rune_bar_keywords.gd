# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     493_battle_rune_bar_keywords.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The HUD rune bar's keyword text and the unit detail rows' focus inset, on a battle of its own:
## the bar with runes held, the first focused by the pad's open_runes, its marked text under the
## slots and its keyword column beside the bar; then the first player unit's detail with the
## d-pad on its first row with keywords, its contents inset inside the focus outline. A seeded solo
## session stands in for the throwaway run in CampaignService, as 489's co-op one does: its seat
## is given [constant RUNES] and its first Standard combat begun on the session itself, which
## saves nothing. The run's own session then comes back and the group ends on the map, as it
## found it, so 500 starts where 492 left it.[br]
## Needs: the map, as the co-op battle screen shots leave it (492_coop_battle_screen).

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# The runes the seat holds: the catalog's with keywords of more than one colour group.
const RUNES: PackedStringArray = ["mend", "aegis", "clarity"]

# The most d-pad presses a step through the detail takes before it gives up.
const MAX_STEPS: int = 16


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the rune bar shots need the map (screen %d)" % [router_screen()])
		return true
	var solo: CampaignSession = campaign()
	var staged: CampaignSession = _new_solo()
	if staged == null or not _enter_standard(staged.run):
		fail("the staged solo run couldn't reach a Standard combat")
		return true
	var request: CampaignSession.BattleRequest = staged.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null or staged.begin_battle(request) == null:
		fail("the staged solo battle couldn't begin")
		staged.close()
		return true
	node(^"CampaignService").set(&"session", staged)
	note("rune bar shots: a solo run seeded %X holding %s, its battle begun unsaved" % [
		RUN_SEED, ", ".join(RUNES),
	])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_GAMEPLAY)
	await frames(SETTLE_FRAMES)
	var view: BattleView = battle_view()
	var controller: BattleController = battle_controller()
	controller.request_start()
	settle(view)
	await frames(SETTLE_FRAMES)
	await _rune_bar(controller)
	await _detail_row(controller, view.get_session())
	node(^"CampaignService").set(&"session", solo)
	staged.close()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The pad's open_runes focuses the bar's first rune: its line and keyword column show.
func _rune_bar(controller: BattleController) -> void:
	_press_pad(JOY_BUTTON_RIGHT_STICK)
	await frames(SETTLE_FRAMES)
	var bar: RuneBar = controller.rune_bar
	if controller.get_stage() != BattleController.Stage.RUNE_SLOTS or bar == null:
		fail("open_runes didn't focus the rune bar (stage %d)" % [controller.get_stage()])
		return
	if bar.get_effect_text().get_shown_tooltips().is_empty():
		fail("the focused rune shows no keyword column")
	await capture("battle_rune_bar_keywords")
	controller.step_back()
	await frames(SETTLE_FRAMES)


# The first player unit's detail, the d-pad on its first row with keywords.
func _detail_row(controller: BattleController, session: CombatSession) -> void:
	if not controller.request_unit_detail(first_player(session)):
		fail("the player unit's detail didn't open")
		return
	await frames(SETTLE_FRAMES)
	var panel: UnitDetailPanel = controller.get_detail_panel()
	var target: Control = null
	for row: Control in panel.get_focus_rows():
		if _has_keywords(row):
			target = row
			break
	if target == null or not _step_to(target):
		fail("no row with text took the d-pad's focus")
	await frames(SETTLE_FRAMES)
	await capture("battle_detail_focus_inset")
	controller.step_back()
	await frames(SETTLE_FRAMES)


# A new solo run on RUN_SEED, as CampaignService builds one, with no starting offer left open and
# RUNES in its seat's first slots.
func _new_solo() -> CampaignSession:
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: FACTION}
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids,
			made.starting_offer_streams()
	)
	if start.run == null:
		return null
	made.run = start.run
	var seat: SeatRun = made.run.seat_run(0)
	seat.pending_offers.erase(StartingOffer.OFFER_KEY)
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for i: int in mini(RUNES.size(), seat.rune_slots.size()):
		var label: String = catalog.rune(RUNES[i]).display_name
		seat.rune_slots[i] = SeatRun.RuneSlot.new(made.ids.next_rune_id(label), RUNES[i])
	return made


# Puts run inside the first Standard combat reached from floor 1, breadth first, as choosing each
# node on the way would. False when the map has none.
func _enter_standard(run: CampaignRunState) -> bool:
	var routes: Array[PackedInt32Array] = []
	for start: int in run.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run.graph.type_of(last) == CampaignGraph.NodeType.STANDARD:
			run.visited = route
			run.floor_number = route.size()
			run.node = last
			run.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	return false


# Presses the d-pad down from the panel's first focus until target holds focus. Returns whether it
# got there.
func _step_to(target: Control) -> bool:
	for _step: int in MAX_STEPS:
		if tree.root.gui_get_focus_owner() == target:
			return true
		_press_pad(JOY_BUTTON_DPAD_DOWN)
	return tree.root.gui_get_focus_owner() == target


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = is_down
		tree.root.push_input(event, true)


# Whether row holds effect text with a keyword.
static func _has_keywords(row: Control) -> bool:
	for node: Node in row.find_children("*", "RichTextLabel", true, false):
		var text: EffectText = node as EffectText
		if text != null and not text.get_keyword_ids().is_empty():
			return true
	return false
