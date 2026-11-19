# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     capture_screens.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

extends SceneTree
## Screenshots every screen at one window size, for checking the UI's layout by eye (UI style
## guide: base 1280×720, shown at 1920×1080 and the Steam Deck's 1280×800). Drives the real
## router through a new solo run: boot, start, save select, main menu, new run, options, lobby,
## loading, the campaign map with its heirloom bar, the battle (swap window, HUD with the unit
## panel and rune bar, the board with an elite, the heirloom bar with a count, a ready and spent
## icons, and its tooltip, action menu, forecast and a multi-hit forecast, unit detail for a
## player unit and an enemy (an elite where there is one), runes, the event log after turns played
## into the first darkness phase, the darkness's three layers side by side, every map object state
## and a lit keg, pause), the victory sequence over the board (Grade, Recap filling, a level-up,
## Recap, Rewards, the item picker, placement, the leave dialog), the sequence resumed over its
## backdrop (on Grade, then on Rewards once the pick is settled), contact sheets of every unit
## sprite and item icon, and the run's end. Each shot is [code]<out>/<size>/<nn>_<name>.png[/code].
## Each shot also lists visible text under [constant MIN_FONT_SIZE] base units and visible
## controls reaching outside the window, and the run ends with their count.[br]
## Run windowed (a headless run renders nothing), from the repo root, with a throwaway user folder
## (it starts a run in save file 1; set APPDATA on Windows):
## [code]godot --path bandit-bash --script res://tools/capture_screens.gd -- --out <dir>
## --size 1920x1080[/code]. Authoring tooling: nothing in the game loads it. Never names an
## autoload (a [code]--script[/code] run compiles before they register); it reaches them as nodes.
##
## @tutorial(UI style guide): docs/design/ui-style.md

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

# VictoryOverlay.Stage values: the script can't name the overlay, whose script names autoloads.
const STAGE_RECAP_LEVEL_UPS: int = 2
const STAGE_REWARDS: int = 4

const BOOT_SCENE: String = "res://ui/screens/boot.tscn"

## The style guide's floor for text, in base units.
const MIN_FONT_SIZE: int = 14

# Any fixed run seed, and the save file the run is written to.
const RUN_SEED: int = 0x51A7E
const SAVE_NUMBER: int = 1

# Frames left after a scene change or an action for layout, focus and tweens to settle.
const SETTLE_FRAMES: int = 20

# Real time left before a victory shot, past its 250 ms fades: frames alone can run faster than
# the fades in a windowed run.
const FADE_WAIT: float = 0.4

# Player phases the battle may wait through for a unit with an attack target.
const TURNS_FOR_ATTACK: int = 4

# Phases played for the event log's shot at most: past the M1 darkness's arrival (end of turn 4).
const LOG_PHASES: int = 6

# The contact sheets' layout, in base units: columns, art size, label width, margin, and how many
# items fit a page at 1280×720. Drawn over every screen.
const SHEET_UNIT_COLUMNS: int = 5
const SHEET_UNIT_ICON: int = 64
const SHEET_ITEM_COLUMNS: int = 6
const SHEET_ITEM_ICON: int = 32
const SHEET_ITEMS_PER_PAGE: int = 84
const SHEET_LABEL_WIDTH: int = 140
const SHEET_MARGIN: int = 12
const SHEET_LAYER: int = 100

var _out_dir: String = ""

# Darkness phases played since the event log's phases began.
var _darkness_phases: int = 0
var _size: Vector2i = Vector2i(1280, 720)
var _shot: int = 0
var _issues: int = 0


func _initialize() -> void:
	if not _read_args():
		quit(1)
		return
	_run.call_deferred()


func _read_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		if args[i] == "--out":
			_out_dir = args[i + 1]
		elif args[i] == "--size":
			var parts: PackedStringArray = args[i + 1].split("x")
			if parts.size() == 2:
				_size = Vector2i(parts[0].to_int(), parts[1].to_int())
	if _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		push_error("CaptureScreens: run windowed with -- --out <dir> [--size WxH]")
		return false
	_out_dir = _out_dir.path_join("%dx%d" % [_size.x, _size.y])
	return DirAccess.make_dir_recursive_absolute(_out_dir) == OK


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = _size
	root.position = Vector2i.ZERO
	await _frames(SETTLE_FRAMES)
	if root.size != _size:
		print("NOTE  the window is %s, not %s (screen %s)" % [
			root.size, _size, DisplayServer.screen_get_size(),
		])
	change_scene_to_file(BOOT_SCENE)
	await process_frame
	await _capture("boot")
	await _frames(SETTLE_FRAMES)
	await _capture("start")
	await _goto(SCREEN_SAVE_SELECT, "save_select")
	_node(^"SaveService").call(&"open_save_file", SAVE_NUMBER)
	await _goto(SCREEN_MAIN_MENU, "main_menu")
	await _goto(SCREEN_NEW_RUN, "new_run")
	await _goto(SCREEN_OPTIONS, "options")
	await _goto(SCREEN_LOBBY, "lobby")
	var err: Error = _node(^"SaveService").call(&"start_new_solo_run", RUN_SEED)
	if err != OK:
		print("FAIL  a new solo run did not start: %s" % [error_string(err)])
		_end()
		return
	_stage_heirlooms()
	await _goto(SCREEN_LOADING, "loading")
	(current_scene.get_node(^"%ContinueButton") as Button).pressed.emit()
	await _frames(SETTLE_FRAMES)
	if not await _campaign_map():
		_end()
		return
	await _battle()
	await _results()
	await _contact_sheets()
	await _goto(SCREEN_RESULTS, "run_end")
	_end()


# Captures the map, then enters its first reachable combat node. Returns whether the battle opened.
func _campaign_map() -> bool:
	await _capture("campaign_map")
	var view: CampaignMapView = current_scene.call(&"get_map_view")
	for node_id: int in view.get_reachable():
		var button: MapNodeButton = view.get_node_button(node_id)
		if button.node_type == CampaignGraph.NodeType.STANDARD:
			button.pressed.emit()
			await _frames(SETTLE_FRAMES)
			return _router_screen() == SCREEN_GAMEPLAY
	print("FAIL  no reachable Standard combat node on the map")
	return false


func _battle() -> void:
	var view: BattleView = current_scene.call(&"get_view")
	var controller: BattleController = current_scene.call(&"get_controller")
	_settle(view)
	await _frames(SETTLE_FRAMES)
	await _capture("battle_swap_window")
	controller.request_start()
	_settle(view)
	await _frames(SETTLE_FRAMES)
	var session: CombatSession = view.get_session()
	var first: String = session.state.units_of(CombatFact.CombatSide.PLAYER)[0]
	controller.move_cursor(session.state.tile_of(first))
	await _frames(SETTLE_FRAMES)
	await _capture("battle_hud")
	await _elite_board(view, session)
	_heirloom_states(session)
	await _frames(SETTLE_FRAMES)
	await _capture("battle_heirloom_bar")
	if controller.request_heirloom_bar():
		await _frames(SETTLE_FRAMES)
		await _capture("battle_heirloom_tooltip")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	if controller.request_unit_detail(first):
		await _frames(SETTLE_FRAMES)
		await _capture("battle_unit_detail")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	if controller.request_unit_detail(_elite_or_first_enemy(session)):
		await _frames(SETTLE_FRAMES)
		await _capture("battle_unit_detail_enemy")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	if controller.request_runes():
		await _frames(SETTLE_FRAMES)
		await _capture("battle_runes")
		controller.step_back()
		await _frames(SETTLE_FRAMES)
	await _attack(view, controller, session)
	await _play_for_log(view, session)
	await _capture("battle_event_log")
	await _darkness_layers(view, session)
	await _object_states(view, session)
	var pause: Node = current_scene.get_node(^"PauseMenu")
	pause.call(&"open")
	await _frames(SETTLE_FRAMES)
	await _capture("battle_pause")
	pause.call(&"close")
	await _frames(SETTLE_FRAMES)
	current_scene.set(&"end_banner_time", 0.0)
	# One unit a point short of a level, so the recap shows a level-up card.
	var campaign: CampaignSession = _node(^"CampaignService").get(&"session")
	var leveler: UnitInstance = campaign.run.seat_run(0).army[0]
	leveler.xp = CombatRewardRules.load_default().xp_per_level - 1
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	session.engine.record(ended)
	_settle(view)
	view.settled.emit()
	await _frames(SETTLE_FRAMES)


# Runs gain no heirloom yet (RN6), so this throwaway run is given some before the map, said in a
# NOTE: War Ledger with its campaign count at 7, Breaker's Maul, Burglar's Roll, Iron Rations, and
# two curses, Shaken Footing and Haunted.
func _stage_heirlooms() -> void:
	var campaign: CampaignSession = _node(^"CampaignService").get(&"session")
	var seat_run: SeatRun = campaign.run.seat_run(0)
	var ledger: SeatRun.OwnedHeirloom = seat_run.add_heirloom("war_ledger")
	ledger.counters["double_damage"] = 7
	for heirloom_id: String in [
		"breakers_maul", "burglars_roll", "iron_rations", "shaken_footing", "haunted",
	]:
		seat_run.add_heirloom(heirloom_id)
	print("NOTE  runs gain no heirlooms yet (RN6): this run is given War Ledger (7 / 10),"
			+ " Breaker's Maul, Burglar's Roll, Iron Rations, Shaken Footing and Haunted")


# The heirloom bar's shot in the states it shows: War Ledger mid-count (7, copied in), Breaker's
# Maul ready (4 of 5, set here), Burglar's Roll's use spent (here), and the first-only Iron
# Rations and Shaken Footing spent by the battle's first Phase Start.
func _heirloom_states(session: CombatSession) -> void:
	var hud: BattleHud = current_scene.call(&"get_hud")
	for icon: HeirloomIcon in hud.get_heirloom_bar().get_icons():
		var view: HeirloomViewModel = icon.get_view()
		if view.heirloom_id == "breakers_maul":
			session.engine.get_instance(view.counter_instance_id).set_counter(
					EffectTerms.Lane.COMBAT, 4
			)
		elif view.heirloom_id == "burglars_roll":
			session.engine.get_instance(view.instance_ids[0]).spend_charge()
	hud.refresh()
	print("NOTE  heirloom bar shot: Breaker's Maul set to 4 / 5 (ready), Burglar's Roll's use spent")


# Walks a unit to an enemy in reach and opens Attack, capturing the action menu and the forecast;
# waits whole phases out while no unit has a target, up to TURNS_FOR_ATTACK.
func _attack(view: BattleView, controller: BattleController, session: CombatSession) -> void:
	for _turn: int in TURNS_FOR_ATTACK:
		var pick: Array = _find_attack(session)
		if not pick.is_empty():
			var unit_id: String = pick[0]
			var walk: Array = pick[1]
			var path: Array[Vector2i] = []
			path.assign(walk)
			var end: Vector2i = session.state.tile_of(unit_id) if path.is_empty() else path[-1]
			controller.confirm_tile(session.state.tile_of(unit_id))
			controller.confirm_tile(end)
			for _step: int in 600:
				if not view.is_staged_walking():
					break
				view.advance(1.0 / 60.0)
			_settle(view)
			await _frames(SETTLE_FRAMES)
			await _capture("battle_action_menu")
			var host: PanelHost = current_scene.get_node(^"%PanelHost")
			var menu: ActionMenu = host.top() as ActionMenu
			if menu != null:
				var options: Array[TurnInputModel.ActionOption] = menu.get_options()
				for i: int in options.size():
					if options[i].kind == TurnInputModel.ActionKind.ATTACK:
						menu.get_rows()[i].pressed.emit()
						break
				await _frames(SETTLE_FRAMES)
				await _capture("battle_target")
				var option: TurnInputModel.ActionOption = pick[2]
				controller.confirm_tile(option.targets[0].tile)
				await _frames(SETTLE_FRAMES)
				await _capture("battle_forecast")
				await _multi_hit_forecast(controller, session, unit_id, option.targets[0].tile)
			while controller.step_back():
				await process_frame
			_settle(view)
			return
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
			session.resolve_next()
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		_settle(view)
		await _frames(SETTLE_FRAMES)
	print("NOTE  no unit had an attack target within %d turns: no forecast shot" % [
		TURNS_FOR_ATTACK,
	])


# Whole phases, each unit attacking where it can while more than one enemy stands (so the battle
# goes on) and waiting elsewhere, until a darkness phase has played or LOG_PHASES pass: the event
# log then holds lines of every group.
func _play_for_log(view: BattleView, session: CombatSession) -> void:
	_darkness_phases = 0
	view.darkness_phase_started.connect(_on_view_darkness_phase_started)
	for _phase: int in LOG_PHASES:
		if session.is_finished or _darkness_phases > 0:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			var command: Command = UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)
			var pick: Array = _find_attack(session)
			var enemies: int = session.state.units_of(CombatFact.CombatSide.ENEMY).size()
			if not pick.is_empty() and pick[0] == unit_id and enemies > 1:
				var option: TurnInputModel.ActionOption = pick[2]
				command = option.targets[0].command
			session.submit(command)
			session.resolve_next()
			_settle(view)
			if session.is_finished:
				break
		if not session.is_finished:
			session.submit(EndTurnCommand.new(0))
			session.resolve_next()
		_settle(view)
		await _frames(SETTLE_FRAMES)
	view.darkness_phase_started.disconnect(_on_view_darkness_phase_started)


func _on_view_darkness_phase_started(_turn: int) -> void:
	_darkness_phases += 1


# The forecast open in CONFIRM, shot again as a multi-hit attack: as it is when it already lists
# its hits, else with the attacker's weapon at AtkX 2 in this throwaway run (said in a NOTE), the
# forecast reopened on the same target.
func _multi_hit_forecast(
		controller: BattleController, session: CombatSession, unit_id: String, tile: Vector2i
) -> void:
	var host: PanelHost = current_scene.get_node(^"%PanelHost")
	var panel: ForecastPanel = host.top() as ForecastPanel
	if panel == null:
		return
	if panel.get_model().row(ForecastViewModel.HITS_LABEL) == null:
		var held: CombatState.WeaponStats = session.state.equipped_weapon(unit_id)
		if held == null:
			return
		print("NOTE  multi-hit forecast: %s's weapon set to AtkX 2 for the shot" % [unit_id])
		held.atk_x = 2
		session.state.load_bases(session.engine, unit_id)
		controller.step_back()
		await _frames(SETTLE_FRAMES)
		controller.confirm_tile(tile)
		await _frames(SETTLE_FRAMES)
	await _capture("battle_forecast_multi_hit")


# The board with its darkness drawn in three bands, Dusk, Gloom and Abyss, from the map's left
# edge, for judging each layer's opacity by eye; the board's own darkness is drawn again after.
# Drawing only: the session's darkness is untouched.
func _darkness_layers(view: BattleView, session: CombatSession) -> void:
	var overlay: DarknessOverlay = view.get_darkness()
	var kept: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in overlay.drawn_tiles():
		kept[tile] = overlay.layer_at(tile)
	var rect: Rect2i = session.layout.get_rect()
	var band: int = maxi(floori(rect.size.x / 4.0), 1)
	var bands: Dictionary[Vector2i, int] = {}
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, mini(rect.position.x + band * 3, rect.end.x)):
			var across: int = floori(float(x - rect.position.x) / band)
			var layer: int = WhileLayerCondition.Layer.DUSK + across
			bands[Vector2i(x, y)] = mini(layer, WhileLayerCondition.Layer.ABYSS)
	overlay.show_layers(bands)
	await _frames(SETTLE_FRAMES)
	await _capture("battle_darkness_layers")
	overlay.show_layers(kept)


# The board's units with an elite among the enemies: the first prefixed enemy, else the first enemy
# given a prefix in this throwaway run (said in a NOTE), outlined by the LeaderMark a Defeat the
# Leader map's elite wears (drawing only, cleared by the next settle).
func _elite_board(view: BattleView, session: CombatSession) -> void:
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	if enemies.is_empty():
		return
	var elite_id: String = ""
	for enemy_id: String in enemies:
		if not session.state.unit(enemy_id).prefix_id.is_empty():
			elite_id = enemy_id
			break
	if elite_id.is_empty():
		elite_id = enemies[0]
		var prefixes: Array[Resource] = EffectCatalog.all_of(EffectCatalog.Kind.UNIT_PREFIX)
		if not prefixes.is_empty():
			session.state.unit(elite_id).prefix_id = str(prefixes[0].get(&"id"))
		print("NOTE  elite board shot: %s given a prefix for the shot" % [elite_id])
	var objective: HudViewModel.ObjectiveView = HudViewModel.ObjectiveView.new()
	objective.marked_left_ids = PackedStringArray([elite_id])
	view.show_objective(objective)
	print("NOTE  elite board shot: %s outlined as a leader; the board has no elite mark" % [
		elite_id,
	])
	await _frames(SETTLE_FRAMES)
	await _capture("battle_board_elite")
	view.show_objective(null)


# Every map object state's mark side by side on the board, from the map's top-left tile, and a lit
# keg thrown onto the first free tile: staged in this throwaway run (said in a NOTE), the marks
# removed after the shot. The keg stays in the run.
func _object_states(view: BattleView, session: CombatSession) -> void:
	var mark_scene: PackedScene = load("res://ui/battle/board/map_object_mark.tscn")
	var rect: Rect2i = session.layout.get_rect()
	var staged: Array[Node] = []
	var index: int = 0
	for state: Array in _staged_object_views():
		var tile: Vector2i = rect.position + Vector2i(
				index % rect.size.x, floori(float(index) / rect.size.x)
		)
		var mark: MapObjectMark = mark_scene.instantiate()
		view.add_child(mark)
		var shown: BoardViewModel.ObjectView = state[1]
		mark.show_object(shown, view.tile_to_position(tile))
		staged.append(mark)
		index += 1
	var thrower: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	var keg_tile: String = "none"
	var recorded: int = session.engine.fact_log.size()
	if not thrower.is_empty():
		for y: int in range(rect.end.y - 1, rect.position.y - 1, -1):
			for x: int in range(rect.position.x, rect.end.x):
				var tile: Vector2i = Vector2i(x, y)
				if keg_tile == "none" and MapObjects.can_land(session.state, tile):
					if not MapObjects.throw_keg(session, tile, thrower[0]).is_empty():
						keg_tile = str(tile)
	# The throw's facts play as a session's do, so the keg's token spawns on the board.
	var thrown: Array[CombatFact] = []
	thrown.assign(session.engine.fact_log.slice(recorded))
	session.playback.enqueue(thrown)
	print("NOTE  object states shot: %d marks staged from the top-left tile (%s), a lit keg"
			% [index, ", ".join(_staged_names())] + " thrown at %s" % [keg_tile])
	_settle(view)
	await _frames(SETTLE_FRAMES)
	await _capture("battle_object_states")
	for mark: Node in staged:
		mark.queue_free()
	await _frames(1)


# Each object state staged for the shot: [name, view].
func _staged_object_views() -> Array[Array]:
	var kinds: Array[MapLayout.ObjectKind] = [
		MapLayout.ObjectKind.CHEST, MapLayout.ObjectKind.LEVER, MapLayout.ObjectKind.HOUSE,
		MapLayout.ObjectKind.FOOD_SHELF, MapLayout.ObjectKind.BOOK_SHELF,
		MapLayout.ObjectKind.WEAPON_RACK, MapLayout.ObjectKind.PASSAGE,
	]
	var states: Array[Array] = []
	for kind: MapLayout.ObjectKind in kinds:
		var name: String = (MapLayout.ObjectKind.find_key(kind) as String).to_lower()
		states.append([name, _object_view(kind, false, false, false, -1)])
		if kind != MapLayout.ObjectKind.LEVER and kind != MapLayout.ObjectKind.PASSAGE:
			states.append([name + " used", _object_view(kind, false, true, false, -1)])
	var door: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
	var brazier: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER
	states.append(["key door", _object_view(door, false, false, false, -1)])
	states.append(["key door open", _object_view(door, true, false, false, -1)])
	states.append(["lever door", _object_view(door, false, false, false, 0)])
	states.append(["lever door open", _object_view(door, true, false, false, 0)])
	states.append(["brazier lit", _object_view(brazier, false, false, true, -1)])
	states.append(["brazier out", _object_view(brazier, false, false, false, -1)])
	return states


func _staged_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for state: Array in _staged_object_views():
		names.append(state[0] as String)
	return names


func _object_view(
		kind: MapLayout.ObjectKind, is_open: bool, is_used: bool, is_lit: bool, group_id: int
) -> BoardViewModel.ObjectView:
	var shown: BoardViewModel.ObjectView = BoardViewModel.ObjectView.new()
	shown.id = "object:staged"
	shown.kind = kind
	shown.is_open = is_open
	shown.is_used = is_used
	shown.is_lit = is_lit
	shown.group_id = group_id
	return shown


# Contact sheets for reviewing the art picks: every sprite in the unit sprite table at twice its
# size with its key, then every item's icon with its name, a page at a time, over the screen.
func _contact_sheets() -> void:
	var table: UnitSpriteTable = load("res://assets/sprites/units/unit_sprites.tres")
	var units: Array[Array] = []
	var keys: Array[String] = []
	keys.assign(table.sprites.keys())
	keys.sort()
	for key: String in keys:
		units.append([key, table.sprites[key]])
	await _sheet("sheet_unit_sprites", units, SHEET_UNIT_COLUMNS, SHEET_UNIT_ICON)
	var items: Array[Array] = []
	for kind: EffectCatalog.Kind in [
		EffectCatalog.Kind.WEAPON, EffectCatalog.Kind.EQUIPMENT, EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]:
		for resource: Resource in EffectCatalog.all_of(kind):
			var item: ItemDefinition = resource as ItemDefinition
			if item != null:
				items.append([item.display_name, item.icon])
	var page: int = 0
	while page * SHEET_ITEMS_PER_PAGE < items.size():
		var start: int = page * SHEET_ITEMS_PER_PAGE
		var shown: Array[Array] = []
		shown.assign(items.slice(start, start + SHEET_ITEMS_PER_PAGE))
		await _sheet(
				"sheet_item_icons_%d" % [page + 1], shown, SHEET_ITEM_COLUMNS, SHEET_ITEM_ICON
		)
		page += 1


# One contact sheet of entries ([label, texture]) in a grid over the screen, captured and removed.
func _sheet(shot_name: String, entries: Array[Array], columns: int, icon_size: int) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = SHEET_LAYER
	var backdrop: Panel = Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	layer.add_child(grid)
	grid.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, SHEET_MARGIN
	)
	for entry: Array in entries:
		var cell: HBoxContainer = HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var art: TextureRect = TextureRect.new()
		art.texture = entry[1]
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.custom_minimum_size = Vector2(icon_size, icon_size)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(art)
		var label: Label = Label.new()
		label.text = entry[0]
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(SHEET_LABEL_WIDTH, 0.0)
		cell.add_child(label)
		grid.add_child(cell)
	root.add_child(layer)
	await _frames(SETTLE_FRAMES)
	await _capture(shot_name)
	layer.queue_free()
	await _frames(1)


# The enemy whose name isn't its class's alone (a prefixed elite), else the first enemy.
func _elite_or_first_enemy(session: CombatSession) -> String:
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	for enemy_id: String in enemies:
		var type_id: String = session.state.unit_type_of(enemy_id)
		if BattleText.name_of(session, enemy_id) != BattleText.type_name(type_id):
			return enemy_id
	return enemies[0] if not enemies.is_empty() else ""


func _find_attack(session: CombatSession) -> Array:
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


# The victory sequence over the board, stage by stage, the item picker, placement and the leave
# dialog; then the sequence resumed over its backdrop, on Grade, and once the pick is skipped, on
# Rewards; then Leave.
func _results() -> void:
	var overlay: Node = _victory_overlay()
	if _router_screen() != SCREEN_GAMEPLAY or overlay == null:
		print("FAIL  the won battle showed no victory sequence (screen %d)" % [_router_screen()])
		return
	await _frames(SETTLE_FRAMES)
	await _fade_capture("victory_grade")
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	await _frames(SETTLE_FRAMES)
	await _fade_capture("victory_recap_filling")
	overlay.call(&"skip")
	await _frames(SETTLE_FRAMES)
	if (overlay.call(&"get_stage") as int) == STAGE_RECAP_LEVEL_UPS:
		await _fade_capture("victory_level_up")
	while (overlay.call(&"get_stage") as int) == STAGE_RECAP_LEVEL_UPS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await process_frame
	await _frames(SETTLE_FRAMES)
	await _fade_capture("victory_recap")
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	await _frames(SETTLE_FRAMES)
	await _fade_capture("victory_rewards")
	var rows: Array[RewardRow] = _reward_rows(overlay)
	if not rows.is_empty():
		rows[0].pressed.emit()
		await _frames(SETTLE_FRAMES)
		await _fade_capture("victory_item_picker")
		var picker: Control = overlay.call(&"get_picker") as Control
		var cards: Array[ItemOfferCard] = _pick_panel(picker).get_offer_cards()
		if not cards.is_empty():
			cards[0].pressed.emit()
			await _frames(SETTLE_FRAMES)
			await _fade_capture("victory_placement")
			(picker.call(&"get_placement_panel") as PlacementPanel).step_back()
			await _frames(SETTLE_FRAMES)
		(picker.call(&"get_back_button") as Button).pressed.emit()
		await _frames(SETTLE_FRAMES)
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await _frames(SETTLE_FRAMES)
		await _fade_capture("victory_leave_confirm")
		(overlay.call(&"get_confirm_dialog") as LeaveConfirmDialog).get_stay_button().pressed.emit()
		await _frames(SETTLE_FRAMES)
	await _resume_results("victory_resumed_grade")
	overlay = _victory_overlay()
	if overlay == null:
		return
	var open_rows: Array[RewardRow] = _reward_rows(overlay)
	(overlay.call(&"get_primary_button") as Button).pressed.emit()
	overlay.call(&"skip")
	while (overlay.call(&"get_stage") as int) < STAGE_REWARDS:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await process_frame
	open_rows = _reward_rows(overlay)
	if not open_rows.is_empty():
		open_rows[0].pressed.emit()
		await _frames(SETTLE_FRAMES)
		var resumed_picker: Control = overlay.call(&"get_picker") as Control
		_pick_panel(resumed_picker).get_skip_button().pressed.emit()
		await _frames(SETTLE_FRAMES)
	await _resume_results("victory_resumed_rewards")
	overlay = _victory_overlay()
	if overlay != null:
		(overlay.call(&"get_primary_button") as Button).pressed.emit()
		await _frames(SETTLE_FRAMES)


# Closes the save file and continues the run from it through Loading, as Save & Quit then
# Continue Run do, and captures the sequence the Results screen reopens.
func _resume_results(shot_name: String) -> void:
	var saves: Node = _node(^"SaveService")
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"continue_solo_run")
	if err != OK:
		print("FAIL  the run did not continue: %s" % [error_string(err)])
		return
	await _goto(SCREEN_LOADING, "loading_resumed")
	(current_scene.get_node(^"%ContinueButton") as Button).pressed.emit()
	await _frames(SETTLE_FRAMES)
	if _router_screen() != SCREEN_COMBAT_RESULTS:
		print("FAIL  the continued run did not reopen Results (screen %d)" % [_router_screen()])
		return
	await _fade_capture(shot_name)


func _reward_rows(overlay: Node) -> Array[RewardRow]:
	var stage: VictoryRewardsStage = overlay.call(&"get_rewards_stage")
	return stage.get_rows()


func _pick_panel(picker: Control) -> ItemPickPanel:
	var panel: ItemPickPanel = picker.call(&"get_pick_panel")
	return panel


# The victory sequence shown: the Results screen's, or the battle screen's over its board.
func _victory_overlay() -> Node:
	if current_scene == null:
		return null
	if current_scene.has_method(&"get_overlay"):
		return current_scene.call(&"get_overlay") as Node
	for child: Node in current_scene.get_children():
		if child.has_method(&"get_rewards_stage"):
			return child
	return null


func _goto(screen: int, shot_name: String) -> void:
	_node(^"SceneRouter").call(&"goto_screen", screen)
	await _frames(SETTLE_FRAMES)
	await _capture(shot_name)


# Saves the window as the next shot and lists its text and clipping issues.
func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path: String = _out_dir.path_join("%02d_%s.png" % [_shot, shot_name])
	var image: Image = root.get_texture().get_image()
	var err: Error = image.save_png(path)
	print("SHOT  %s%s" % [path, "" if err == OK else " (%s)" % [error_string(err)]])
	for issue: String in _issues_in(root):
		_issues += 1
		print("  ISSUE  %s: %s" % [shot_name, issue])


# Visible text under the floor, and visible controls reaching outside the window.
func _issues_in(top: Node) -> PackedStringArray:
	var found: PackedStringArray = []
	var bounds: Rect2 = root.get_visible_rect().grow(0.5)
	for node: Node in top.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree():
			continue
		var size: int = _font_size_of(control)
		if size > 0 and size < MIN_FONT_SIZE and _has_text(control):
			found.append("%s text at %d" % [control.get_path(), size])
		# A scroll container's content may run past it; the container itself is checked.
		if _is_scrolled(control):
			continue
		# On screen, through any camera or canvas layer above it.
		var to_screen: Transform2D = control.get_global_transform_with_canvas()
		var rect: Rect2 = to_screen * Rect2(Vector2.ZERO, control.size)
		if rect.has_area() and not bounds.encloses(rect):
			found.append("%s outside the window %s" % [control.get_path(), rect])
	return found


func _font_size_of(control: Control) -> int:
	if control is RichTextLabel:
		return control.get_theme_font_size(&"normal_font_size")
	if control is Label or control is Button or control is LineEdit:
		return control.get_theme_font_size(&"font_size")
	return 0


func _has_text(control: Control) -> bool:
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).get_parsed_text().is_empty()
	if control is Button:
		return not (control as Button).text.is_empty()
	return true


func _is_scrolled(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _settle(view: BattleView) -> void:
	for _step: int in 600:
		if view.is_settled():
			return
		view.advance(1.0 / 60.0)


func _frames(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _router_screen() -> int:
	return _node(^"SceneRouter").get(&"current_screen")


func _node(path: NodePath) -> Node:
	return root.get_node(path)


func _end() -> void:
	print("--- %d shots, %d issues ---" % [_shot, _issues])
	quit(0)


# Waits FADE_WAIT seconds of real time, then captures, so a victory stage's fade has ended.
func _fade_capture(shot_name: String) -> void:
	await create_timer(FADE_WAIT).timeout
	await _capture(shot_name)
