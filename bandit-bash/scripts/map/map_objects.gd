# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_objects.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name MapObjects
extends RefCounted
## The rules of map objects in a battle: placing them, using them, breaking them, powder kegs
## exploding, Cutthroat loot, container contents, and what the darkness (P06) asks of them
## (map-objects.md; combat map plan, Map objects).
##
## Objects are neutral. Their state is [member CombatState.map]; breakables (debris, powder kegs)
## are also units of side [constant CombatFact.CombatSide.NONE] holding their HP, attacked through
## [ExchangeResolver] like any defender and broken through [method CombatState.defeat], which hands
## them to [method broken]. [b]Using[/b] an object is a unit's action ([method use]): a chest,
## searchable, lever or passage end from its own tile, a door or brazier from next to it. It records
## [constant CombatFact.Kind.OBJECT_USED], then one [constant CombatFact.Kind.OBJECT_STATE_CHANGED]
## per object that changed, whose [member CombatFact.key] is a [enum Change].[br]
## [b]Powder kegs[/b] explode on any hit or splash (a reaction owned by
## [constant EffectOwner.Kind.MAP_OBJECT], exempt from the reaction caps), on breaking, on the
## darkness's erosion or on Spark: splash to every unit within 1 tile through [SplashResolver], and
## every breakable within 1 tile breaks, so kegs chain with no limit.[br]
## Pure and static rules code, run unchanged in a sandbox; the caller starts the resolution step.
##
## @tutorial(Map objects): docs/design/map-objects.md
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md
##
## @todo: TOD-001 - Pick each container's item from P03's pools; contents are a category and a
## rarity until then.
## @todo: TOD-002 - Read the Cutthroat from P05's enemy data, not a unit type name.
## @todo: TOD-003 - Read which units pick locks from P03's unit data (tag or effect permission,
## escalated).
## @todo: TOD-004 - Read Spark from P03's rune catalog, not an effect definition id.
## @todo: TOD-005 - Place objects from setup step 2's draw; every candidate spot is placed now.

## What an [constant CombatFact.Kind.OBJECT_STATE_CHANGED] reports, in its
## [member CombatFact.key]. Sent over the network as an int: [b]append only[/b].
enum Change {
	## A door opened, or a chest opened and emptied.
	OPENED = 0,
	## A door closed by its lever.
	CLOSED = 1,
	## A house or shelf searched and emptied.
	SEARCHED = 2,
	## A brazier lit.
	LIT = 3,
	## A brazier doused.
	DOUSED = 4,
	## A breakable broken: off the map, its tile clear, its terrain back.
	DESTROYED = 5,
	## A reinforcement point closed for good by the unit named as the target, which earns the
	## personal-XP bonus (P08); the actor is the point ([method Reinforcements.close_points]).
	POINT_CLOSED = 6,
}

## HP, DEF and RES of each breakable (map-objects.md, from Godot_FE's entity data).
const BREAKABLE_STATS: Dictionary[MapLayout.ObjectKind, Array] = {
	MapLayout.ObjectKind.WOODEN_DEBRIS: [25, 0, 0],
	MapLayout.ObjectKind.STONE_DEBRIS: [35, 5, 5],
	MapLayout.ObjectKind.POWDER_KEG: [10, 0, 0],
}

## Every breakable's Attack Speed against an attacker's bonus turns (every Godot_FE entity
## definition: [code]attack_speed = 5[/code]).
const ATTACK_SPEED: int = 5

## Splash damage a powder keg deals to each unit within [constant KEG_RADIUS] (map-objects.md).
const KEG_SPLASH: int = 5

## A keg's blast reach, in tiles of grid distance (map-objects.md).
const KEG_RADIUS: int = 1

## The objects a unit uses standing on their tile (Godot_FE: chests, levers and searchables; a
## passage from its end).
const USED_ON_TILE: Array[MapLayout.ObjectKind] = [
	MapLayout.ObjectKind.CHEST,
	MapLayout.ObjectKind.LEVER,
	MapLayout.ObjectKind.HOUSE,
	MapLayout.ObjectKind.FOOD_SHELF,
	MapLayout.ObjectKind.BOOK_SHELF,
	MapLayout.ObjectKind.WEAPON_RACK,
	MapLayout.ObjectKind.PASSAGE,
]

## The objects a unit uses from an orthogonally adjacent tile (Godot_FE: doors; map-objects.md:
## braziers).
const USED_FROM_NEXT_TO: Array[MapLayout.ObjectKind] = [
	MapLayout.ObjectKind.DOOR,
	MapLayout.ObjectKind.BRAZIER,
]

# TODO(TOD-002): The Cutthroat, the only enemy that loots, until P05 marks it in enemy data.
## The unit type of the Cutthroat: the only enemy that opens chests and searches, needing no key.
const CUTTHROAT_UNIT_TYPE: String = "Cutthroat"

# ASSUMPTION: a unit tag marks who picks locks, a stopgap escalated to the user and orchestrator
# (they lean toward an effect permission). TODO(TOD-003): Read it from P03's unit data.
## The unit tag that lets a unit open a chest or door with a lockpick.
const LOCKPICKER_TAG: String = "Lockpicker"

## The [member EffectDefinition.id] of a key's use effect: any unit opens a chest or door with it,
## and it is used up (user decision, October 29, 2026).
const KEY_EFFECT_ID: String = "key"

## The [member EffectDefinition.id] of a lockpick's use effect: only a lock picker
## ([constant LOCKPICKER_TAG]) opens with it, and it is kept (user decision, October 29, 2026).
const LOCKPICK_EFFECT_ID: String = "lockpick"

# TODO(TOD-004): Spark, until P03's rune catalog says which rune it is.
## The [member EffectDefinition.id] of the Spark rune's effect: it explodes a powder keg anywhere.
const SPARK_EFFECT_ID: String = "spark"

## A chest's item rarities, in the order of [constant CHEST_RARITY_WEIGHTS].
const CHEST_RARITIES: Array[String] = ["common", "uncommon", "rare"]

## Each chest rarity's weight out of 100: Common 50, Uncommon 35, Rare 15 (game-vision.md,
## Interactables).
const CHEST_RARITY_WEIGHTS: Array[int] = [50, 35, 15]

## The least gold a house holds (game-vision.md, Interactables: 15–25).
const HOUSE_GOLD_MIN: int = 15

## The most gold a house holds, inclusive.
const HOUSE_GOLD_MAX: int = 25

# ASSUMPTION: a house gives gold or a consumable at even odds; the vision gives no split.
## The chance out of 100 that a house holds gold rather than a consumable.
const HOUSE_GOLD_CHANCE: int = 50

# The keg's two reactions, "any hit" and "any splash", built once: read-only content.
static var _keg_effects: Array[EffectDefinition] = []


## Places every object of [param session]'s map on its state and registers the map's
## [constant CombatHooks.Hook.OBJECT_OPERATIONS] ([method operate]). Call once per session, after
## it opens and before any unit is placed, so no breakable's tile is taken.
static func place(session: CombatSession) -> void:
	place_objects(session.engine, session.state, session.layout, session.ids)
	session.hooks.add(CombatHooks.Hook.OBJECT_OPERATIONS, MapObjects.operate_hook)


## Places the objects of [param layout]'s object spots on [param state]: every spot's state in
## [member MapState.objects]; closed doors and breakables blocking their tiles; breakables as units
## with their stats in [param engine], kegs with their reactions. Records no fact: objects are part
## of the map. A breakable whose tile is taken is placed destroyed. [param ids] mints the keg
## reactions' instance ids and names the objects.
static func place_objects(
		engine: EffectEngine, state: CombatState, layout: MapLayout, ids: InstanceIdAllocator
) -> void:
	for marker: MapLayout.Marker in layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		var placed: MapState.ObjectState = MapState.ObjectState.new()
		placed.id = InstanceIdAllocator.object_id(marker.index)
		placed.index = marker.index
		placed.kind = marker.object_kind
		placed.tile = marker.tile
		placed.group_id = marker.group_id
		placed.pair_id = marker.pair_id
		placed.container_index = marker.container_index
		state.map.objects[placed.id] = placed
		var label: String = (MapLayout.ObjectKind.find_key(placed.kind) as String).capitalize()
		ids.set_label(placed.id, label)
		if placed.kind == MapLayout.ObjectKind.DOOR:
			state.map.set_blocking(placed.tile, MapState.Blocking.ALL)
		elif BREAKABLE_STATS.has(placed.kind):
			_place_breakable(engine, state, ids, placed, label)


## Why [param unit_id] can't use [param object_id] now, with Pouch item [param item_id] (a key or
## lockpick; empty for none); empty when it can. The caller checks that the unit hasn't acted.
static func check_use(
		engine: EffectEngine,
		state: CombatState,
		unit_id: String,
		object_id: String,
		item_id: String = ""
) -> String:
	if not state.has_unit(unit_id) or state.side_of(unit_id) == CombatFact.CombatSide.NONE:
		return "not a unit on the map"
	var used: MapState.ObjectState = state.map.object(object_id)
	if used == null or used.is_destroyed:
		return "no such object on the map"
	if BREAKABLE_STATS.has(used.kind):
		return "a breakable is attacked, not used"
	var distance: int = state.grid.distance(state.tile_of(unit_id), used.tile)
	if USED_ON_TILE.has(used.kind) and distance != 0:
		return "not standing on it"
	if USED_FROM_NEXT_TO.has(used.kind) and distance != 1:
		return "not next to it"
	var takes_item: bool = (
			used.kind == MapLayout.ObjectKind.CHEST or used.kind == MapLayout.ObjectKind.DOOR
	)
	if not item_id.is_empty() and not takes_item:
		return "it takes no item"
	match used.kind:
		MapLayout.ObjectKind.CHEST:
			if used.is_used:
				return "already opened"
			if not _may_loot(state, unit_id):
				return "only player units and Cutthroats loot"
			if item_id.is_empty() and is_cutthroat(state, unit_id):
				return ""
			return _unlock_reason(engine, state, unit_id, item_id)
		MapLayout.ObjectKind.DOOR:
			if used.is_open:
				return "already open"
			return _unlock_reason(engine, state, unit_id, item_id)
		MapLayout.ObjectKind.LEVER:
			return "it pulls nothing" if used.group_id < 0 else ""
		MapLayout.ObjectKind.PASSAGE:
			var other: MapState.ObjectState = other_end(state, used)
			if other == null:
				return "it leads nowhere"
			if not state.occupant_at(other.tile).is_empty():
				return "the other end is taken"
			if not state.can_stand(other.tile, state.unit(unit_id).movement_type):
				return "it can't stand at the other end"
			return ""
		MapLayout.ObjectKind.BRAZIER:
			return ""
	if used.is_used:
		return "already searched"
	return "" if _may_loot(state, unit_id) else "only player units and Cutthroats loot"


## [param unit_id] uses [param object_id] as its action ([method check_use]): a key is spent,
## Object used, then the object's changes and the drain. An illegal use records nothing. Returns
## why it was illegal; empty when it resolved.
static func use(
		engine: EffectEngine,
		state: CombatState,
		unit_id: String,
		object_id: String,
		item_id: String = ""
) -> String:
	var reason: String = check_use(engine, state, unit_id, object_id, item_id)
	if not reason.is_empty():
		return reason
	var user: CombatUnitState = state.unit(unit_id)
	user.has_acted = true
	var used: MapState.ObjectState = state.map.object(object_id)
	if not item_id.is_empty():
		_spend_key(engine, state, unit_id, item_id)
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_USED, unit_id, object_id)
	fact.tile = used.tile
	fact.item_id = item_id
	engine.record(fact)
	match used.kind:
		MapLayout.ObjectKind.CHEST:
			loot(state, unit_id, used)
			_changed(engine, used, Change.OPENED, unit_id)
		MapLayout.ObjectKind.DOOR:
			for door: MapState.ObjectState in door_tiles(state, used):
				_set_door(engine, state, door, true, unit_id)
		MapLayout.ObjectKind.LEVER:
			_pull(engine, state, used, unit_id)
		MapLayout.ObjectKind.PASSAGE:
			var other: MapState.ObjectState = other_end(state, used)
			state.move_unit(unit_id, other.tile)
			var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, unit_id)
			moved.tile = other.tile
			engine.record(moved)
		MapLayout.ObjectKind.BRAZIER:
			used.is_lit = not used.is_lit
			_changed(engine, used, Change.LIT if used.is_lit else Change.DOUSED, unit_id)
		_:
			loot(state, unit_id, used)
			_changed(engine, used, Change.SEARCHED, unit_id)
	engine.drain()
	return ""


## Moves [param container]'s contents to whoever takes them: a player unit's seat in
## [member MapState.found], a Cutthroat's [member MapState.carried]. The container is used either
## way; one with no contents rolled gives nothing.
static func loot(state: CombatState, unit_id: String, container: MapState.ObjectState) -> void:
	container.is_used = true
	if not state.map.contents.has(container.container_index):
		return
	var taken: Variant = state.map.contents[container.container_index]
	if state.side_of(unit_id) == CombatFact.CombatSide.PLAYER:
		_add_found(state, state.seat_of(unit_id), [taken])
		return
	if not state.map.carried.has(unit_id):
		state.map.carried[unit_id] = []
	state.map.carried[unit_id].append(taken)


## When [param unit_id] is defeated by [param by_id]: the loot it carried goes to the seat of
## [param by_id] if that is a player unit, and is lost otherwise (the darkness, a keg, an enemy).
## [method CombatState.defeat] calls it. Records nothing: the defeat says who took it.
static func drop_carried(state: CombatState, unit_id: String, by_id: String) -> void:
	if not state.map.carried.has(unit_id):
		return
	var dropped: Array = state.map.carried[unit_id]
	state.map.carried.erase(unit_id)
	# ASSUMPTION: loot dropped with no player unit to take it is lost (plan question 8 names only
	# "the seat whose unit defeats it").
	if state.side_of(by_id) == CombatFact.CombatSide.PLAYER:
		_add_found(state, state.seat_of(by_id), dropped)


## A breakable [param object_id] was just taken off the map by [method CombatState.defeat]:
## it is destroyed, its tile clear and its terrain back, Object state changed (destroyed, by
## [param by_id]); a powder keg then explodes ([method explode]).
static func broken(
		engine: EffectEngine,
		state: CombatState,
		object_id: String,
		by_id: String,
		source_effect_id: String = ""
) -> void:
	var gone: MapState.ObjectState = state.map.object(object_id)
	if gone == null or gone.is_destroyed:
		return
	gone.is_destroyed = true
	state.map.set_blocking(gone.tile, MapState.Blocking.NONE)
	_changed(engine, gone, Change.DESTROYED, by_id, source_effect_id)
	if gone.kind == MapLayout.ObjectKind.POWDER_KEG:
		explode(engine, state, gone)


## Powder keg [param keg] explodes: [constant KEG_SPLASH] splash to every unit within
## [constant KEG_RADIUS] tiles, friend or foe, in the state's unit order, then every breakable
## within that reach breaks, in spot order; a keg among them explodes in turn.
static func explode(engine: EffectEngine, state: CombatState, keg: MapState.ObjectState) -> void:
	var effect_id: String = _keg_effect_id(engine, keg.id)
	var breakables: Array[String] = []
	for unit_id: String in state.unit_ids():
		if state.grid.distance(keg.tile, state.tile_of(unit_id)) > KEG_RADIUS:
			continue
		if state.side_of(unit_id) == CombatFact.CombatSide.NONE:
			breakables.append(unit_id)
		else:
			engine.deal_splash(keg.id, unit_id, KEG_SPLASH, effect_id)
	breakables.sort_custom(func(a: String, b: String) -> bool:
		return state.map.object(a).index < state.map.object(b).index
	)
	for object_id: String in breakables:
		state.defeat(engine, object_id, keg.id, effect_id)


## Breaks powder keg [param object_id] from a hit or splash it took: the keg's own reaction
## ([KegExplosion]) calls it. [param by_id]: the unit or object that hit it. Nothing happens once
## it is gone.
static func detonate(
		engine: EffectEngine, state: CombatState, object_id: String, by_id: String
) -> void:
	var keg: MapState.ObjectState = state.map.object(object_id)
	if keg == null or keg.is_destroyed or keg.kind != MapLayout.ObjectKind.POWDER_KEG:
		return
	state.defeat(engine, object_id, by_id, _keg_effect_id(engine, object_id))


## [constant CombatHooks.Hook.OBJECT_OPERATIONS] for a session: [method operate] on its state.
static func operate_hook(session: CombatSession, source_id: String, object_id: String) -> bool:
	return operate(session.engine, session.state, source_id, object_id)


## A rune or effect [param source_id] acting on [param object_id]: Spark explodes a powder keg.
## Returns whether it acted; when false, nothing changed.
static func operate(
		engine: EffectEngine, state: CombatState, source_id: String, object_id: String
) -> bool:
	var target: MapState.ObjectState = state.map.object(object_id)
	if target == null or target.is_destroyed:
		return false
	if target.kind != MapLayout.ObjectKind.POWDER_KEG:
		return false
	var spark: EffectInstance = _rune_effect(engine, source_id)
	if spark == null or spark.definition.id != SPARK_EFFECT_ID:
		return false
	state.defeat(engine, object_id, "", spark.instance_id)
	return true


## Setup step 7 ([constant CombatEncounter.SetupStep.CONTAINER_CONTENTS]): rolls every container
## on the map into the seat's [member MapState.contents], each from its own
## [code]MAP_LOOT[/code] stream by container index, so each seat's copy rolls its own (P13
## question 3b) and a restart from Begin rolls the same.
static func roll_contents(ctx: CombatEncounter.SetupContext) -> void:
	for marker: MapLayout.Marker in ctx.setup.layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if marker.container_index < 0:
			continue
		var stream: RngStream = ctx.loot_stream(marker.container_index)
		if stream == null:
			continue
		ctx.seat_setup.map.contents[marker.container_index] = roll(marker.object_kind, stream)


## One container's contents, plain data with a [code]"kind"[/code]: a chest's
## [code]{"kind": "item", "rarity": ...}[/code], a house's gold [code]{"kind": "gold",
## "amount": N}[/code] or [code]{"kind": "consumable"}[/code], a shelf's ingredient or rune, a
## rack's weapon. Empty for a kind that isn't a container.
static func roll(kind: MapLayout.ObjectKind, stream: RngStream) -> Dictionary:
	# TODO(TOD-001): Pick the item itself from P03's pools; these are its category and rarity.
	match kind:
		MapLayout.ObjectKind.CHEST:
			var rarity: int = stream.pick_weighted(PackedInt32Array(CHEST_RARITY_WEIGHTS))
			return {"kind": "item", "rarity": CHEST_RARITIES[rarity]}
		MapLayout.ObjectKind.HOUSE:
			if stream.roll_percent(HOUSE_GOLD_CHANCE):
				return {
					"kind": "gold",
					"amount": stream.randi_range(HOUSE_GOLD_MIN, HOUSE_GOLD_MAX),
				}
			return {"kind": "consumable"}
		MapLayout.ObjectKind.FOOD_SHELF:
			return {"kind": "ingredient"}
		MapLayout.ObjectKind.BOOK_SHELF:
			return {"kind": "rune"}
		MapLayout.ObjectKind.WEAPON_RACK:
			return {"kind": "weapon"}
	return {}


## Whether [param unit_id] is a Cutthroat, the enemy that loots without a key.
static func is_cutthroat(state: CombatState, unit_id: String) -> bool:
	return (
			state.side_of(unit_id) == CombatFact.CombatSide.ENEMY
			and state.unit_type_of(unit_id) == CUTTHROAT_UNIT_TYPE
	)


## Whether [param unit_id] may open a lock with a lockpick ([constant LOCKPICKER_TAG]).
static func can_pick_locks(state: CombatState, unit_id: String) -> bool:
	return state.tags_of(unit_id).has(LOCKPICKER_TAG)


## Every tile of the door [param door] belongs to: the 4-connected door tiles with its lever group,
## in spot order. Several tiles are one door that opens together; doors in no group join the same
## way.
static func door_tiles(
		state: CombatState, door: MapState.ObjectState
) -> Array[MapState.ObjectState]:
	var by_tile: Dictionary[Vector2i, MapState.ObjectState] = {}
	for other: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.DOOR):
		if other.group_id == door.group_id:
			by_tile[other.tile] = other
	var reached: Dictionary[Vector2i, bool] = {door.tile: true}
	var frontier: Array[Vector2i] = [door.tile]
	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_back()
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var next: Vector2i = tile + direction
			if by_tile.has(next) and not reached.has(next):
				reached[next] = true
				frontier.append(next)
	var tiles: Array[MapState.ObjectState] = []
	for other: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.DOOR):
		if other.group_id == door.group_id and reached.has(other.tile):
			tiles.append(other)
	return tiles


## The other end of passage [param passage]: the other passage with its pair id; null when it has
## none, or more than one.
static func other_end(state: CombatState, passage: MapState.ObjectState) -> MapState.ObjectState:
	if passage.pair_id < 0:
		return null
	var found_end: MapState.ObjectState = null
	for other: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.PASSAGE):
		if other == passage or other.pair_id != passage.pair_id or other.is_destroyed:
			continue
		if found_end != null:
			return null
		found_end = other
	return found_end


## For P06: whether the darkness may flood [param tile]. See [method blocks_darkness].
static func is_floodable(state: CombatState, tile: Vector2i) -> bool:
	return not blocks_darkness(state, tile)


# ASSUMPTION: "a tile at least one movement type can stand on" (the-darkness.md) means a ground
# movement type, since fliers stand on walls and walls block the darkness.
## For P06: whether [param tile] stops the darkness: off the map, a tile no ground unit can stand
## on by its terrain (walls, cliffs), a closed door, or an unbroken breakable. Units never do.
static func blocks_darkness(state: CombatState, tile: Vector2i) -> bool:
	if state.map.blocking_at(tile) != MapState.Blocking.NONE:
		return true
	for movement_type: CombatGrid.MovementType in CombatGrid.MovementType.values():
		if movement_type == CombatGrid.MovementType.FLIER:
			continue
		if state.grid.can_stand(tile, movement_type):
			return false
	return true


## For P06: the darkness erodes breakable [param object_id] at its contact limit: it breaks, and a
## keg explodes. Returns false, changing nothing, for anything that isn't an unbroken breakable;
## doors never erode (the-darkness.md).
static func erode(engine: EffectEngine, state: CombatState, object_id: String) -> bool:
	var target: MapState.ObjectState = state.map.object(object_id)
	if target == null or target.is_destroyed or not BREAKABLE_STATS.has(target.kind):
		return false
	state.defeat(engine, object_id, "")
	return true


## For P06: whether brazier [param object_id] is lit.
static func is_lit(state: CombatState, object_id: String) -> bool:
	var brazier: MapState.ObjectState = state.map.object(object_id)
	return brazier != null and brazier.kind == MapLayout.ObjectKind.BRAZIER and brazier.is_lit


static func _place_breakable(
		engine: EffectEngine,
		state: CombatState,
		ids: InstanceIdAllocator,
		placed: MapState.ObjectState,
		label: String
) -> void:
	var stats: Array = BREAKABLE_STATS[placed.kind]
	var hp: int = stats[0]
	engine.set_base(placed.id, CombatValue.Key.HP, float(hp), label)
	engine.set_base(placed.id, CombatValue.Key.DEF, float(stats[1] as int), label)
	engine.set_base(placed.id, CombatValue.Key.RES, float(stats[2] as int), label)
	engine.set_base(placed.id, CombatValue.Key.SPD, float(ATTACK_SPEED), label)
	engine.set_base(placed.id, CombatValue.Key.STANCE_MAX, 0.0, label)
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = placed.id
	unit.side = CombatFact.CombatSide.NONE
	unit.seat = -1
	unit.tile = placed.tile
	unit.unit_type = label
	unit.hp = hp
	if not state.place_unit(engine, unit):
		placed.is_destroyed = true
		return
	state.map.set_blocking(placed.tile, MapState.Blocking.ALL_BUT_FLIERS)
	if placed.kind != MapLayout.ObjectKind.POWDER_KEG:
		return
	for definition: EffectDefinition in _keg_definitions():
		# A keg's own rule, like a trait: the closest source kind there is.
		engine.register(EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_object(placed.id),
				Modifier.SourceKind.UNIT_TRAIT,
				label
		))


# Why the unit can't open a lock with item_id; empty when it can.
static func _unlock_reason(
		engine: EffectEngine, state: CombatState, unit_id: String, item_id: String
) -> String:
	if item_id.is_empty():
		return "needs a key or a lockpick"
	if state.unit(unit_id).pouch_item_id != item_id:
		return "not in its Pouch"
	match _opener_id(engine, item_id):
		KEY_EFFECT_ID:
			var effects: Array[EffectInstance] = ItemUseResolver.use_effects(engine, item_id)
			return "" if ItemUseResolver.has_uses(effects) else "no uses left"
		LOCKPICK_EFFECT_ID:
			return "" if can_pick_locks(state, unit_id) else "can't pick locks"
	return "not a key or a lockpick"


# The key or lockpick effect id of item_id's use effects; empty for neither.
static func _opener_id(engine: EffectEngine, item_id: String) -> String:
	for instance: EffectInstance in ItemUseResolver.use_effects(engine, item_id):
		if instance.definition.id == KEY_EFFECT_ID or instance.definition.id == LOCKPICK_EFFECT_ID:
			return instance.definition.id
	return ""


# A key spends a use and leaves the Pouch once it has none; a lockpick is kept.
static func _spend_key(
		engine: EffectEngine, state: CombatState, unit_id: String, item_id: String
) -> void:
	if _opener_id(engine, item_id) != KEY_EFFECT_ID:
		return
	var effects: Array[EffectInstance] = ItemUseResolver.use_effects(engine, item_id)
	ItemUseResolver.spend(engine, effects, unit_id)
	if not ItemUseResolver.has_uses(effects):
		state.unit(unit_id).pouch_item_id = ""
		state.load_bases(engine, unit_id)


# Player units loot; of the enemies, only Cutthroats do (map-objects.md, Enemy AI).
static func _may_loot(state: CombatState, unit_id: String) -> bool:
	return state.side_of(unit_id) == CombatFact.CombatSide.PLAYER or is_cutthroat(state, unit_id)


static func _add_found(state: CombatState, seat: int, loot_found: Array) -> void:
	if not state.map.found.has(seat):
		state.map.found[seat] = []
	state.map.found[seat].append_array(loot_found)


# ASSUMPTION: a pull opens the whole group unless every door is already open, then closes it; a
# door with a unit or object in it stays open (map-objects.md says only "toggles").
static func _pull(
		engine: EffectEngine, state: CombatState, lever: MapState.ObjectState, unit_id: String
) -> void:
	var doors: Array[MapState.ObjectState] = []
	var is_all_open: bool = true
	for door: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.DOOR):
		if door.group_id == lever.group_id:
			doors.append(door)
			is_all_open = is_all_open and door.is_open
	for door: MapState.ObjectState in doors:
		if is_all_open and not state.occupant_at(door.tile).is_empty():
			continue
		_set_door(engine, state, door, not is_all_open, unit_id)


static func _set_door(
		engine: EffectEngine,
		state: CombatState,
		door: MapState.ObjectState,
		is_open: bool,
		by_id: String
) -> void:
	if door.is_open == is_open:
		return
	door.is_open = is_open
	state.map.set_blocking(
			door.tile, MapState.Blocking.NONE if is_open else MapState.Blocking.ALL
	)
	_changed(engine, door, Change.OPENED if is_open else Change.CLOSED, by_id)


static func _changed(
		engine: EffectEngine,
		changed: MapState.ObjectState,
		change: Change,
		by_id: String,
		source_effect_id: String = ""
) -> void:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, changed.id, by_id)
	fact.tile = changed.tile
	fact.key = change
	fact.source_effect_id = source_effect_id
	engine.record(fact)


# The keg's first registered reaction, named as the source of its blast; empty when it has none.
static func _keg_effect_id(engine: EffectEngine, keg_id: String) -> String:
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.MAP_OBJECT and instance.owner.owner_id == keg_id:
			return instance.instance_id
	return ""


static func _rune_effect(engine: EffectEngine, rune_id: String) -> EffectInstance:
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.RUNE and instance.owner.owner_id == rune_id:
			return instance
	return null


# "Any hit" and "any splash": one reaction each, both breaking the keg ([KegExplosion]).
static func _keg_definitions() -> Array[EffectDefinition]:
	if not _keg_effects.is_empty():
		return _keg_effects
	for trigger: EffectDefinition.Trigger in [
		EffectDefinition.Trigger.HIT_TAKEN,
		EffectDefinition.Trigger.DAMAGE_TAKEN,
	]:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = "powder_keg"
		definition.trigger = trigger
		definition.scope = EffectDefinition.Scope.THIS_UNIT
		var blast: KegExplosion = KegExplosion.new()
		blast.text = "explode"
		definition.operations = [blast]
		_keg_effects.append(definition)
	return _keg_effects
