# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_objects.gd
# Author:
# Created:  October 29, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MapObjects
extends RefCounted
## The rules of map objects in a battle: placing, using and breaking them, powder kegs, Cutthroat
## loot, container contents, and what the darkness asks of them (map-objects.md).
##
## Objects are neutral, in [member CombatState.map]; breakables are also side-NONE units holding
## their HP, broken through [method CombatState.defeat] ([method broken]). Using one is a unit's
## action ([method use]), recording [constant CombatFact.Kind.OBJECT_USED] and one
## [constant CombatFact.Kind.OBJECT_STATE_CHANGED] per change, keyed by a [enum Change].
## [b]Powder kegs[/b] explode on any hit, splash, break, erosion or Spark (their own reactions,
## exempt from the caps): splash within 1 tile, breaking the breakables there, so kegs chain. The
## Powder Baron's are thrown mid-battle with a lit fuse ([method throw_keg], [method burn_fuses]).
## The darkness flows anew after every break and door change. Pure, static rules code.
##
## @tutorial(Map objects): docs/design/map-objects.md
## @tutorial(Combat map plan): docs/plans/2026-10-27-combat-map.md
##
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
	## A breakable next to a flooded tile gained a turn of contact with the darkness, below the
	## limit; the fact's amount is its count ([Darkness]). No target.
	CONTACTED = 7,
	## A breakable's contact reached the limit, so the darkness breaks it: amount the count, no
	## target; its [constant DESTROYED] follows.
	ERODED = 8,
	## A powder keg thrown by the unit named as the target landed on the fact's tile, lit: amount
	## its spot index ([method throw_keg]). Its unit's [constant CombatFact.Kind.UNIT_SPAWNED]
	## follows.
	LANDED = 9,
	## A thrown keg's fuse burned down at an enemy Phase End: amount the Phase Ends left; at 0 its
	## [constant DESTROYED] follows ([method burn_fuses]). No target.
	FUSE_BURNED = 10,
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

## Splash damage a powder keg deals to each unit [constant KEG_BLAST] covers (map-objects.md).
const KEG_SPLASH: int = 5

## The tiles a keg's blast covers around the keg: within 1 tile by grid distance (map-objects.md).
## A shared shape file, preloaded because the blast also runs in sandboxes off the main thread.
const KEG_BLAST: TargetShape = preload("res://data/shapes/adjacent_with_center.tres")

## The [member EffectDefinition.id] of each of a powder keg's two reactions, by trigger: "any hit"
## and "any splash". Saves name the reactions by these ([method map_definition]): never change
## them.
const KEG_EFFECT_IDS: Dictionary[EffectTerms.Trigger, String] = {
	EffectTerms.Trigger.HIT_TAKEN: "powder_keg_hit",
	EffectTerms.Trigger.DAMAGE_TAKEN: "powder_keg_splash",
}

## The first spot index of a keg thrown during the battle; each throw takes the next one. Far above
## any map's spot count, so a thrown keg's id never meets an authored object's. Saves hold these
## indexes: never change it.
const THROWN_INDEX_BASE: int = 1000

## The enemy Phase Ends a thrown keg's lit fuse burns, after the one of the phase it lands in: it
## explodes at the end of the 2nd enemy phase after it lands (enemy-roster.md, Keg Barrage). First
## pass, to tune (rebalance-and-features.md).
const FUSE_PHASES: int = 2

## Turns of darkness contact that break a thrown keg: the darkness meets its lit fuse at once
## (P05 question 46). Authored breakables keep [constant Darkness.CONTACT_LIMIT].
const LIT_CONTACT_LIMIT: int = 1

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

## The [member EffectDefinition.id] of a key's use effect: any unit opens a chest or door with it,
## and it is used up (user decision, October 29, 2026).
const KEY_EFFECT_ID: String = "key"

## The [member EffectDefinition.id] of a lockpick's use effect: only a lock picker
## ([method can_pick_locks]) opens with it, and it is kept (user decision, October 29, 2026).
const LOCKPICK_EFFECT_ID: String = "lockpick"

## The [member EffectDefinition.id] of Burglar's Roll's army effect: while it has a charge, any
## unit of its seat opens a chest or door with no item, spending the charge. Saves name the
## effect by this id: never change it.
const BURGLAR_EFFECT_ID: String = "burglar"

## The content id of the Spark rune ([RuneDefinition]): it explodes a powder keg anywhere. Rune
## slots and saves name runes by content id: never change it.
const SPARK_RUNE_ID: String = "spark"

## A chest's item rarities, in the order of [constant CHEST_RARITY_WEIGHTS] and
## [constant ItemPools.DRAWN_RARITIES].
const CHEST_RARITIES: Array[String] = ["common", "uncommon", "rare"]

## Each chest rarity's weight out of 100: Common 50, Uncommon 35, Rare 15 (game-vision.md,
## Interactables). A food shelf's ingredient and a weapon rack's weapon roll the same odds.
const CHEST_RARITY_WEIGHTS: Array[int] = [50, 35, 15]

## The item kinds a chest holds: a weapon (staves included), equipment or a trinket (game-vision.md,
## Interactables), drawn evenly over all three at the rolled rarity, as Godot_FE's chests drew.
const CHEST_KINDS: Array[EffectCatalog.Kind] = [
	EffectCatalog.Kind.WEAPON,
	EffectCatalog.Kind.EQUIPMENT,
	EffectCatalog.Kind.TRINKET,
]

## The use kinds of a house's consumable, from [constant ContentIds.CONSUMABLE_USE_KINDS]: potions
## (the Elixir included), the Key, the Lockpick and stat boosters (game-vision.md, Interactables).
const HOUSE_USE_KINDS: PackedStringArray = ["heal", "full_heal", "key", "lockpick", "stat_booster"]

## Each rarity's weight for a house's consumable, in [constant CHEST_RARITIES]' order: Common 37,
## Uncommon 8, Rare 3 (Godot_FE's house table: its Rare 2 and Mythical 1 consumables).
const HOUSE_RARITY_WEIGHTS: Array[int] = [37, 8, 3]

## The use kind of a food shelf's consumable: an ingredient (map-objects.md, Searchable).
const SHELF_USE_KINDS: PackedStringArray = ["ingredient"]

## The key of a container's drawn item or rune in its contents: its content id. Saves hold it and
## the battle-end bridge (P08) grants by it: never change it.
const CONTENTS_ID_KEY: String = "definition_id"

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
## [constant CombatHooks.Hook.OBJECT_OPERATIONS] ([method operate]) and the thrown kegs' fuses
## ([method burn_fuses]). Call once per session, after it opens and before any unit is placed, so
## no breakable's tile is taken.
static func place(session: CombatSession) -> void:
	place_objects(session.engine, session.state, session.layout, session.ids)
	session.hooks.add(CombatHooks.Hook.OBJECT_OPERATIONS, MapObjects.operate_hook)
	session.hooks.add(CombatHooks.Hook.PHASE_END_EFFECTS, MapObjects.burn_fuses)


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
## lockpick; empty for none, which opens a lock only with its army's Burglar's Roll charge); empty
## when it can. The caller checks that the unit hasn't acted.
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
			if not _may_loot(engine, state, unit_id):
				return "only player units and Cutthroats loot"
			if item_id.is_empty() and is_looter(engine, state, unit_id):
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
	return "" if _may_loot(engine, state, unit_id) else "only player units and Cutthroats loot"


## [param unit_id] uses [param object_id] as its action ([method check_use]): a key or a Burglar's
## Roll charge is spent, Object used, then the object's changes (after a door or lever, the
## darkness's new flow) and the drain. An illegal use records nothing. Returns why it was illegal;
## empty when it resolved.
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
	elif _is_lock(used) and not is_looter(engine, state, unit_id):
		# check_use passed with no item, so a charge is left.
		var ctx: EffectContext = EffectContext.new()
		ctx.command_target_id = unit_id
		engine.activate(_burglar_charge(engine, state, unit_id), ctx)
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
			Darkness.recalculate(engine, state)
		MapLayout.ObjectKind.LEVER:
			_pull(engine, state, used, unit_id)
			Darkness.recalculate(engine, state)
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
## [param by_id]); a powder keg then explodes ([method explode]); then the darkness flows through
## the new gap ([method Darkness.recalculate]).
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
	Darkness.recalculate(engine, state)


## Powder keg [param keg] explodes: [constant KEG_SPLASH] splash to every unit on the tiles
## [constant KEG_BLAST] covers around it, friend or foe, in the state's unit order, then every
## breakable there breaks, in spot order; a keg among them explodes in turn.
static func explode(engine: EffectEngine, state: CombatState, keg: MapState.ObjectState) -> void:
	var effect_id: String = _keg_effect_id(engine, keg.id)
	var breakables: Array[String] = []
	for unit_id: String in state.unit_ids():
		var tile: Vector2i = state.tile_of(unit_id)
		if tile == CombatFact.NO_TILE or not KEG_BLAST.covers(keg.tile, tile):
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


## Whether a thrown keg may land on [param tile]: on the map, standable by some movement type but
## Flier, with no unit and no object still there. A flooded tile may take one.
static func can_land(state: CombatState, tile: Vector2i) -> bool:
	if state.grid.step(tile, Vector2i.ZERO) == CombatFact.NO_TILE:
		return false
	if not state.occupant_at(tile).is_empty() or not state.map.objects_at(tile).is_empty():
		return false
	return not blocks_darkness(state, tile)


## Throws a lit powder keg onto [param tile] of [param session]'s map, for [param by_id]
## ([KegBarrage]): a keg as authored ones are, on the next spot index from
## [constant THROWN_INDEX_BASE], with a [member MapState.ObjectState.fuse] of
## [constant FUSE_PHASES] + 1. Records [constant Change.LANDED], then its unit's
## [constant CombatFact.Kind.UNIT_SPAWNED] ([method CombatSession.add_unit]), and lets the
## darkness flow anew. Its ids are derived, never minted, so a sandbox throw moves no counter.
## Returns its object id; empty, changing nothing, when [method can_land] refuses the tile.
static func throw_keg(session: CombatSession, tile: Vector2i, by_id: String) -> String:
	var state: CombatState = session.state
	var engine: EffectEngine = session.engine
	if not can_land(state, tile):
		return ""
	var index: int = THROWN_INDEX_BASE
	for object_id: String in state.map.objects:
		if state.map.objects[object_id].is_thrown:
			index += 1
	var keg: MapState.ObjectState = thrown_keg(InstanceIdAllocator.object_id(index), index, tile)
	state.map.objects[keg.id] = keg
	var landed: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, keg.id, by_id)
	landed.tile = tile
	landed.key = Change.LANDED
	landed.amount = index
	engine.record(landed)
	var label: String = (MapLayout.ObjectKind.find_key(keg.kind) as String).capitalize()
	var definitions: Array[EffectDefinition] = _keg_definitions()
	for reaction: int in definitions.size():
		# A keg's own rule, like a trait: the closest source kind there is.
		engine.register(EffectInstance.new(
				InstanceIdAllocator.object_effect_id(index, reaction),
				definitions[reaction],
				EffectOwner.for_object(keg.id),
				Modifier.SourceKind.UNIT_TRAIT,
				label
		))
	var stats: Array = BREAKABLE_STATS[keg.kind]
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = keg.id
	unit.side = CombatFact.CombatSide.NONE
	unit.seat = -1
	unit.tile = tile
	unit.unit_type = label
	unit.hp = stats[0]
	var bases: Dictionary = {
		CombatValue.Key.HP: float(stats[0] as int),
		CombatValue.Key.DEF: float(stats[1] as int),
		CombatValue.Key.RES: float(stats[2] as int),
		CombatValue.Key.SPD: float(ATTACK_SPEED),
		CombatValue.Key.STANCE_MAX: 0.0,
	}
	# Checked by can_land(), so the tile is free.
	session.add_unit(unit, bases)
	state.map.set_blocking(tile, MapState.Blocking.ALL_BUT_FLIERS)
	Darkness.recalculate(engine, state)
	return keg.id


## The state of a keg thrown onto [param tile], lit, with id [param object_id] on spot
## [param index]: what [method throw_keg] places and what a mirror makes from its
## [constant Change.LANDED].
static func thrown_keg(object_id: String, index: int, tile: Vector2i) -> MapState.ObjectState:
	var keg: MapState.ObjectState = MapState.ObjectState.new()
	keg.id = object_id
	keg.index = index
	keg.kind = MapLayout.ObjectKind.POWDER_KEG
	keg.tile = tile
	keg.is_thrown = true
	keg.fuse = FUSE_PHASES + 1
	return keg


## [constant CombatHooks.Hook.PHASE_END_EFFECTS]: at the enemy Phase End, each lit thrown keg on
## [param session]'s map, in spot order, burns one Phase End off its fuse
## ([constant Change.FUSE_BURNED]); one at 0 breaks and explodes, by no unit. A keg a blast broke
## earlier in the loop is skipped. Does nothing for [param side] other than the enemy's.
static func burn_fuses(session: CombatSession, side: CombatFact.CombatSide) -> void:
	if side != CombatFact.CombatSide.ENEMY:
		return
	var state: CombatState = session.state
	for keg: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.POWDER_KEG):
		if not keg.is_thrown or keg.is_destroyed or keg.fuse <= 0:
			continue
		keg.fuse -= 1
		var burned: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, keg.id)
		burned.tile = keg.tile
		burned.key = Change.FUSE_BURNED
		burned.amount = keg.fuse
		session.engine.record(burned)
		if keg.fuse == 0:
			state.defeat(session.engine, keg.id, "", _keg_effect_id(session.engine, keg.id))


## The turns of darkness contact that break breakable [param placed]: a thrown keg's
## [constant LIT_CONTACT_LIMIT], else [constant Darkness.CONTACT_LIMIT].
static func contact_limit(placed: MapState.ObjectState) -> int:
	return LIT_CONTACT_LIMIT if placed.is_thrown else Darkness.CONTACT_LIMIT


## [constant CombatHooks.Hook.OBJECT_OPERATIONS] for a session: [method operate] on its state.
static func operate_hook(session: CombatSession, source_id: String, object_id: String) -> bool:
	return operate(session.engine, session.state, source_id, object_id)


## The rune [param source_id] acting on [param object_id]: Spark ([constant SPARK_RUNE_ID], read
## from the rune catalog through [method RuneResolver.definition_of]) breaks a powder keg, which
## explodes, credited to Spark's effect. Returns whether it acted; when false, nothing changed.
static func operate(
		engine: EffectEngine, state: CombatState, source_id: String, object_id: String
) -> bool:
	var target: MapState.ObjectState = state.map.object(object_id)
	if target == null or target.is_destroyed:
		return false
	if target.kind != MapLayout.ObjectKind.POWDER_KEG:
		return false
	var rune: RuneDefinition = RuneResolver.definition_of(engine, source_id)
	if rune == null or rune.id != SPARK_RUNE_ID:
		return false
	state.defeat(engine, object_id, "", RuneResolver.effect_of(engine, source_id).instance_id)
	return true


## Setup step 7 ([constant CombatEncounter.SetupStep.CONTAINER_CONTENTS]): rolls every container
## on the map into the seat's [member MapState.contents], each from its own
## [code]MAP_LOOT[/code] stream by container index, so each seat's copy rolls its own (P13
## question 3b) and a restart from Begin rolls the same. Items come from [param catalog]
## ([method roll]); register it bound to the battle's catalog:
## [code]roll_contents.bind(catalog)[/code].
static func roll_contents(
		ctx: CombatEncounter.SetupContext, catalog: EffectCatalog.Index = null
) -> void:
	for marker: MapLayout.Marker in ctx.setup.layout.markers_of(MapLayout.MarkerKind.OBJECT_SPOT):
		if marker.container_index < 0:
			continue
		var stream: RngStream = ctx.loot_stream(marker.container_index)
		if stream == null:
			continue
		ctx.seat_setup.map.contents[marker.container_index] = roll(
				marker.object_kind, stream, catalog
		)


## One container's contents, plain data with a [code]"kind"[/code]: a chest's
## [code]{"kind": "item", "rarity": ...}[/code] (the rarity rolled), a house's gold
## [code]{"kind": "gold", "amount": N}[/code] or [code]"consumable"[/code], a food shelf's
## [code]"ingredient"[/code], a book shelf's [code]"rune"[/code], a rack's [code]"weapon"[/code].
## All but gold also name their item or rune under [constant CONTENTS_ID_KEY], drawn from
## [param catalog]'s pools ([ItemPools]) after the draws above, so the gold and rarity a stream
## gives never depend on the catalog. No catalog, or an empty pool, names none and draws nothing
## more. Empty for a kind that isn't a container.
static func roll(
		kind: MapLayout.ObjectKind, stream: RngStream, catalog: EffectCatalog.Index = null
) -> Dictionary:
	var contents: Dictionary = {}
	var drawn: EffectCarrierDefinition = null
	match kind:
		MapLayout.ObjectKind.CHEST:
			var rarity: int = stream.pick_weighted(PackedInt32Array(CHEST_RARITY_WEIGHTS))
			contents = {"kind": "item", "rarity": CHEST_RARITIES[rarity]}
			drawn = ItemPools.draw(stream, ItemPools.items_of(catalog, CHEST_KINDS), rarity)
		MapLayout.ObjectKind.HOUSE:
			if stream.roll_percent(HOUSE_GOLD_CHANCE):
				return {
					"kind": "gold",
					"amount": stream.randi_range(HOUSE_GOLD_MIN, HOUSE_GOLD_MAX),
				}
			contents = {"kind": "consumable"}
			drawn = _draw_item(stream, _consumables(catalog, HOUSE_USE_KINDS), HOUSE_RARITY_WEIGHTS)
		MapLayout.ObjectKind.FOOD_SHELF:
			contents = {"kind": "ingredient"}
			drawn = _draw_item(stream, _consumables(catalog, SHELF_USE_KINDS), CHEST_RARITY_WEIGHTS)
		MapLayout.ObjectKind.BOOK_SHELF:
			contents = {"kind": "rune"}
			drawn = ItemPools.draw_rune(stream, catalog)
		MapLayout.ObjectKind.WEAPON_RACK:
			contents = {"kind": "weapon"}
			var weapon_kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
			# A rack holds any weapon, staves and tomes included, as the vision words it;
			# Godot_FE's racks held neither (its tomes were on book shelves, which hold runes).
			drawn = _draw_item(
					stream, ItemPools.items_of(catalog, weapon_kinds), CHEST_RARITY_WEIGHTS
			)
		_:
			return {}
	if drawn != null:
		contents[CONTENTS_ID_KEY] = drawn.id
	return contents


## Whether [param unit_id] is an enemy that loots, opening chests with no key: its
## [constant CombatValue.Permission.CAN_LOOT], which the Cutthroat's class grants. Player units
## loot without it, but a chest still needs their key.
static func is_looter(engine: EffectEngine, state: CombatState, unit_id: String) -> bool:
	return (
			state.side_of(unit_id) == CombatFact.CombatSide.ENEMY
			and engine.stats(unit_id).is_allowed(CombatValue.Permission.CAN_LOOT)
	)


## Whether [param unit_id] may open a lock with a lockpick: its
## [constant CombatValue.Permission.CAN_PICK_LOCKS], denied unless an effect grants it (the
## Thief's innate grant).
static func can_pick_locks(engine: EffectEngine, unit_id: String) -> bool:
	return engine.stats(unit_id).is_allowed(CombatValue.Permission.CAN_PICK_LOCKS)


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


## For P06: whether [param tile] stops the darkness: off the map, a tile no movement type but
## Flier can stand on by its terrain (walls, cliffs), a closed door, or an unbroken breakable.
## Fliers don't count because they stand on walls, which block it (darkness plan question 10).
## Units never do.
static func blocks_darkness(state: CombatState, tile: Vector2i) -> bool:
	if state.map.blocking_at(tile) != MapState.Blocking.NONE:
		return true
	for movement_type: CombatGrid.MovementType in CombatGrid.MovementType.values():
		if movement_type == CombatGrid.MovementType.FLIER:
			continue
		if state.grid.can_stand(tile, movement_type):
			return false
	return true


## For P06: the darkness erodes breakable [param object_id] at its contact limit ([Darkness],
## after its [constant Change.ERODED]): it breaks, and a keg explodes. Returns false, changing
## nothing, for anything that isn't an unbroken breakable; doors never erode (the-darkness.md).
static func erode(engine: EffectEngine, state: CombatState, object_id: String) -> bool:
	var target: MapState.ObjectState = state.map.object(object_id)
	if target == null or target.is_destroyed or not BREAKABLE_STATS.has(target.kind):
		return false
	state.defeat(engine, object_id, "")
	return true


## The definition of a map object's own reaction (a powder keg's) that [param reference] names, as
## [method EffectInstance.capture] named it; null for anything else. No catalog holds these, so a
## save or snapshot restores them through this ([method CombatSession.load_snapshot]).
static func map_definition(reference: String) -> EffectDefinition:
	for definition: EffectDefinition in _keg_definitions():
		if definition.id == reference:
			return definition
	return null


## Whether [param item_id] is a key with no use left, so it leaves its holder's Pouch: what using
## a chest or door with it does on the host, and what a mirror follows
## ([method CombatState.follow]). False for a lockpick and anything else.
static func is_key_spent(engine: EffectEngine, item_id: String) -> bool:
	if _opener_id(engine, item_id) != KEY_EFFECT_ID:
		return false
	return not ItemUseResolver.has_uses(ItemUseResolver.use_effects(engine, item_id))


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
		if _burglar_charge(engine, state, unit_id) != null:
			return ""
		return "needs a key or a lockpick"
	if state.unit(unit_id).pouch_item_id != item_id:
		return "not in its Pouch"
	match _opener_id(engine, item_id):
		KEY_EFFECT_ID:
			var effects: Array[EffectInstance] = ItemUseResolver.use_effects(engine, item_id)
			return "" if ItemUseResolver.has_uses(effects) else "no uses left"
		LOCKPICK_EFFECT_ID:
			return "" if can_pick_locks(engine, unit_id) else "can't pick locks"
	return "not a key or a lockpick"


# The first Burglar's Roll effect of unit_id's army with a charge left, in instance order; null
# when none. Enemies have no army, so they never have one.
static func _burglar_charge(
		engine: EffectEngine, state: CombatState, unit_id: String
) -> EffectInstance:
	var seat: int = state.seat_of(unit_id)
	if seat < 0:
		return null
	for instance: EffectInstance in engine.get_instances():
		if (
				instance.owner.kind == EffectOwner.Kind.ARMY
				and instance.owner.seat == seat
				and instance.definition.id == BURGLAR_EFFECT_ID
				and instance.has_charge()
		):
			return instance
	return null


# Whether the object is a lock: a chest or a door.
static func _is_lock(used: MapState.ObjectState) -> bool:
	return used.kind == MapLayout.ObjectKind.CHEST or used.kind == MapLayout.ObjectKind.DOOR


# The key or lockpick effect id of item_id's use effects; empty for neither.
static func _opener_id(engine: EffectEngine, item_id: String) -> String:
	for instance: EffectInstance in ItemUseResolver.use_effects(engine, item_id):
		if instance.definition.id == KEY_EFFECT_ID or instance.definition.id == LOCKPICK_EFFECT_ID:
			return instance.definition.id
	return ""


# A key spends a use and leaves the Pouch once it has none ([method is_key_spent]); a lockpick is
# kept.
static func _spend_key(
		engine: EffectEngine, state: CombatState, unit_id: String, item_id: String
) -> void:
	if _opener_id(engine, item_id) != KEY_EFFECT_ID:
		return
	var effects: Array[EffectInstance] = ItemUseResolver.use_effects(engine, item_id)
	ItemUseResolver.spend(engine, effects, unit_id)
	if is_key_spent(engine, item_id):
		state.unit(unit_id).pouch_item_id = ""
		state.load_bases(engine, unit_id)


# Player units loot; of the enemies, only looters (Cutthroats) do (map-objects.md, Enemy AI).
static func _may_loot(engine: EffectEngine, state: CombatState, unit_id: String) -> bool:
	return (
			state.side_of(unit_id) == CombatFact.CombatSide.PLAYER
			or is_looter(engine, state, unit_id)
	)


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


# The catalog's consumables of the given use kinds; empty with no catalog.
static func _consumables(
		catalog: EffectCatalog.Index, use_kinds: PackedStringArray
) -> Array[ItemDefinition]:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.CONSUMABLE]
	return ItemPools.with_use_kinds(ItemPools.items_of(catalog, kinds), use_kinds)


# A rarity by the weights, then an item of it from candidates; null, drawing nothing, when there
# are no candidates.
static func _draw_item(
		stream: RngStream, candidates: Array[ItemDefinition], weights: Array[int]
) -> ItemDefinition:
	if candidates.is_empty():
		return null
	var rarity: int = stream.pick_weighted(PackedInt32Array(weights))
	return ItemPools.draw(stream, candidates, maxi(rarity, 0))


# "Any hit" and "any splash": one reaction each, both breaking the keg ([KegExplosion]). Each has
# its own id, since a save names a definition by its id (map_definition()).
static func _keg_definitions() -> Array[EffectDefinition]:
	if not _keg_effects.is_empty():
		return _keg_effects
	for trigger: EffectTerms.Trigger in KEG_EFFECT_IDS:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = KEG_EFFECT_IDS[trigger]
		definition.trigger = trigger
		definition.scope = EffectTerms.Scope.THIS_UNIT
		var blast: KegExplosion = KegExplosion.new()
		blast.text = "explode"
		definition.operations = [blast]
		_keg_effects.append(definition)
	return _keg_effects
