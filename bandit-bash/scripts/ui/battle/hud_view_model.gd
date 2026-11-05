# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hud_view_model.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name HudViewModel
extends RefCounted
## What the battle HUD shows, as plain data read from a [CombatSession]: a tile's terrain and what
## stands on it, a unit's panel, the turn against par, the darkness's counter and the objective
## (combat UI plan, question 11: Godot_FE FR-UI-3 minus XP).
##
## Each builder reads state and [method CombatSession.stats] only, never changes either, and holds
## no rule of its own: the numbers are the session's, the names [method BattleText.name_of]'s. The
## widgets ([TileInfo], [UnitPanel], [TurnCounter], [DarknessCounter], [ObjectivePanel]) format
## them; tests check the views without rendering.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The base stats a unit panel lists, in order: each its short name and [enum CombatValue.Key].
const STAT_ROWS: Array[Array] = [
	["MGT", CombatValue.Key.MGT],
	["SPD", CombatValue.Key.SPD],
	["DEF", CombatValue.Key.DEF],
	["RES", CombatValue.Key.RES],
	["CON", CombatValue.Key.CON],
	["MOV", CombatValue.Key.MOVEMENT],
]

## Each objective's text, by [enum CombatMapDefinition.Objective]; [code]%d[/code] is
## [member CombatMapDefinition.survive_turns] (game-vision.md, Combat maps: Objectives).
const OBJECTIVE_TEXT: Dictionary[CombatMapDefinition.Objective, String] = {
	CombatMapDefinition.Objective.ROUT: "Rout: defeat every enemy",
	CombatMapDefinition.Objective.DEFEAT_LEADER: "Defeat the leader",
	CombatMapDefinition.Objective.DEFEAT_BOSS: "Defeat the boss",
	CombatMapDefinition.Objective.SEIZE: "Seize the marked tile",
	CombatMapDefinition.Objective.SURVIVE: "Survive %d turns",
	CombatMapDefinition.Objective.DEFEND: "Defend the marked tile for %d turns",
}

# Terrain display names by terrain id, read once from res://data/terrain/: content is read-only.
static var _terrain_names: Dictionary[String, String] = {}


## [param tile]'s view on [param session]: its terrain and bonuses, its occupant and the map
## objects on it. Off the map, [member TileView.is_on_map] is false and the rest is empty.
static func tile_view(session: CombatSession, tile: Vector2i) -> TileView:
	var view: TileView = TileView.new()
	view.tile = tile
	var terrain: MapLayout.Terrain = session.layout.terrain_at(tile)
	if terrain == null:
		return view
	view.is_on_map = true
	view.terrain_name = terrain_name(terrain.id)
	view.avoid = terrain.bonus.avoid
	view.defense = terrain.bonus.defense
	view.resistance = terrain.bonus.resistance
	view.occupant_id = session.state.occupant_at(tile)
	view.occupant_name = BattleText.name_of(session, view.occupant_id)
	view.occupant_side = session.state.side_of(view.occupant_id)
	for placed: MapState.ObjectState in session.state.map.objects_at(tile):
		# A standing breakable is the occupant already; a broken one is off the map.
		if placed.is_destroyed or placed.id == view.occupant_id:
			continue
		view.object_names.append(BattleText.name_of(session, placed.id))
	return view


## [param unit_id]'s panel on [param session]; null when it isn't on the map.
static func unit_view(session: CombatSession, unit_id: String) -> UnitView:
	var state: CombatState = session.state
	if unit_id.is_empty() or not state.has_unit(unit_id):
		return null
	var unit: CombatUnitState = state.unit(unit_id)
	var sheet: StatSheet = session.stats(unit_id)
	var view: UnitView = UnitView.new()
	view.unit_id = unit_id
	view.name = BattleText.name_of(session, unit_id)
	view.side = unit.side
	view.hp = unit.hp
	view.max_hp = sheet.get_int(CombatValue.Key.HP)
	view.block = unit.block
	view.stance = unit.stance
	view.stance_max = sheet.get_int(CombatValue.Key.STANCE_MAX)
	for row: Array in STAT_ROWS:
		view.stat_names.append(row[0] as String)
		view.stat_values.append(sheet.get_int(row[1] as int))
	view.has_acted = unit.has_acted and not unit.is_second_move_pending
	var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
	if held != null:
		view.weapon_name = BattleText.name_of(session, held.id)
		view.is_staff = held.is_staff()
		view.weapon_damage = held.damage
		view.weapon_hit = sheet.get_int(CombatValue.Key.HIT)
		view.range_min = sheet.get_int(CombatValue.Key.RANGE_MIN)
		view.range_max = sheet.get_int(CombatValue.Key.RANGE_MAX)
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		view.stowed_name = BattleText.name_of(session, unit.stowed_weapon_id)
	view.pouch_name = BattleText.name_of(session, unit.pouch_item_id)
	return view


## The turn against the map's par on [param session].
static func turn_view(session: CombatSession) -> TurnView:
	var view: TurnView = TurnView.new()
	view.turn = session.state.turn
	view.par = session.setup.map.turn_par if session.setup != null else 0
	return view


## The darkness's counter on [param session]: the turns until it arrives, then until the next
## wave, from [method Darkness.source_counters] (every source counts alike, so the first is
## shown).
static func darkness_view(session: CombatSession) -> DarknessView:
	var view: DarknessView = DarknessView.new()
	var counters: PackedInt32Array = Darkness.source_counters(session.state)
	if counters.is_empty():
		return view
	view.is_coming = true
	view.turns = counters[0]
	view.has_arrived = session.state.map.has_darkness_arrived
	return view


## The objective's text on [param session] ([constant OBJECTIVE_TEXT]); empty with no map.
static func objective_text(session: CombatSession) -> String:
	if session.setup == null or session.setup.map == null:
		return ""
	var definition: CombatMapDefinition = session.setup.map
	var text: String = OBJECTIVE_TEXT.get(definition.objective, "")
	return text % [definition.survive_turns] if text.contains("%d") else text


## The display name of terrain [param terrain_id] ([member TerrainDefinition.display_name]); the id
## made readable when its definition has none.
static func terrain_name(terrain_id: String) -> String:
	if _terrain_names.has(terrain_id):
		return _terrain_names[terrain_id]
	var shown: String = terrain_id.capitalize()
	var definition: TerrainDefinition = MapLoader.load_terrain(terrain_id)
	if definition != null and not definition.display_name.is_empty():
		shown = definition.display_name
	_terrain_names[terrain_id] = shown
	return shown


## One tile's terrain and what stands on it.
class TileView:
	extends RefCounted

	## The tile.
	var tile: Vector2i = CombatFact.NO_TILE
	## Whether it is on the map; everything below is empty when it isn't.
	var is_on_map: bool = false
	## Its terrain's name, such as "Forest".
	var terrain_name: String = ""
	## Avoid a defender gets here. [b]Units:[/b] Hit percent.
	var avoid: int = 0
	## DEF a unit gets here.
	var defense: int = 0
	## RES a unit gets here.
	var resistance: int = 0
	## The unit (or standing breakable) on it; empty for none.
	var occupant_id: String = ""
	## Its name; empty for none.
	var occupant_name: String = ""
	## Its side; [constant CombatFact.CombatSide.NONE] for none or a breakable.
	var occupant_side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	## The names of the map objects on it besides the occupant, in spot order.
	var object_names: PackedStringArray = []


## One unit's panel.
class UnitView:
	extends RefCounted

	## Its instance id.
	var unit_id: String = ""
	## Its name ([method BattleText.name_of]).
	var name: String = ""
	## Its side.
	var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	## HP now.
	var hp: int = 0
	## Maximum HP ([method CombatSession.stats]).
	var max_hp: int = 0
	## Block now.
	var block: int = 0
	## Stance now.
	var stance: int = 0
	## Stance after a refresh ([constant CombatValue.Key.STANCE_MAX]).
	var stance_max: int = 0
	## The base stats' short names, in [constant HudViewModel.STAT_ROWS] order.
	var stat_names: PackedStringArray = []
	## The base stats' values, in the same order ([method CombatSession.stats]).
	var stat_values: PackedInt32Array = []
	## Whether it has taken its turn's action, with no second move left.
	var has_acted: bool = false
	## The Weapon slot's name; empty when it holds nothing.
	var weapon_name: String = ""
	## Whether that is a staff, which never counters.
	var is_staff: bool = false
	## The weapon's damage, before Might.
	var weapon_damage: int = 0
	## Hit before the defender's avoid ([constant CombatValue.Key.HIT]).
	var weapon_hit: int = 0
	## Its shortest range, in tiles, effects included.
	var range_min: int = 0
	## Its longest range, in tiles, effects included.
	var range_max: int = 0
	## The stowed weapon's name; empty for none.
	var stowed_name: String = ""
	## The Pouch item's name; empty for none.
	var pouch_name: String = ""


## The turn against par.
class TurnView:
	extends RefCounted

	## The turn: 0 before turn 1's Phase Start (the opening swap window).
	var turn: int = 0
	## The map's par; 0 when it has none set.
	var par: int = 0

	## Whether the turn is past par, which colours the counter. Never with no par set.
	func is_past_par() -> bool:
		return par > 0 and turn > par


## The darkness's counter.
class DarknessView:
	extends RefCounted

	## Whether the darkness comes to this map at all.
	var is_coming: bool = false
	## Whether it has arrived.
	var has_arrived: bool = false
	## Turns until it arrives, or after arrival until the next wave, this turn included: 1 means
	## at the end of this turn.
	var turns: int = 0
