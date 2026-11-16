# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roster_unit_cases.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

extends RefCounted
## The roster's unit type cases for tests/content/run_all.gd, over the real
## [code]res://data/[/code]: the eleven MVP unit types after M1 against unit-roster.md (weapons,
## movement, tags, role, starting weapon, trait, stats, Stance, growths and upgrades), the big
## upgrades through the loadout, their effect text, the Ward's shover role up front in
## auto-deployment, Skirmisher's move after combat but not after a shove, Skirmisher+'s Block on
## that move only, and each type drawn by its letters while it has no sprite. Reports each case
## through the check callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the docs and this file agree.
##
## @tutorial(Unit roster): docs/design/unit-roster.md

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const SHOVE: UnitTurnCommand.Action = UnitTurnCommand.Action.SHOVE
const MOVE: UnitTurnCommand.Action = UnitTurnCommand.Action.MOVE

## The table every unit token draws its sprite from (P07 adds the art).
const SPRITE_TABLE: String = "res://assets/sprites/units/unit_sprites.tres"

# unit-roster.md's MVP roster table, the types after M1. Columns: HP, MGT, SPD, DEF, RES, MOV, CON,
# Stance, then growths HP, MGT, SPD, DEF, RES. The Lancer's growths are Godot_FE's, kept as the
# first pass (unit-roster.md, Open questions).
const ROSTER: Dictionary[String, Array] = {
	"sellsword": [22, 5, 7, 4, 1, 5, 11, 2, 110, 42, 34, 18, 20],
	"fighter": [22, 6, 4, 3, 2, 5, 12, 3, 85, 55, 35, 32, 15],
	"lancer": [19, 3, 6, 3, 2, 5, 8, 2, 85, 42, 55, 15, 17],
	"brawler": [25, 6, 4, 1, 3, 5, 7, 2, 65, 50, 22, 22, 15],
	"thief": [14, 3, 9, 2, 1, 6, 6, 1, 65, 30, 65, 25, 20],
	"freewing": [17, 3, 7, 2, 2, 7, 5, 1, 60, 40, 48, 9, 27],
	"lance_armor": [23, 7, 2, 7, 1, 4, 14, 3, 75, 47, 15, 48, 20],
	"ward": [25, 2, 2, 7, 1, 5, 14, 3, 70, 25, 28, 45, 10],
	"mage": [16, 3, 7, 1, 3, 5, 5, 2, 55, 45, 45, 8, 30],
	"shaman": [17, 8, 3, 3, 4, 5, 12, 2, 75, 65, 22, 18, 30],
	"suncaster": [18, 1, 7, 1, 4, 5, 6, 1, 55, 37, 55, 10, 35],
}

# unit-roster.md's Upgrades table: stat gains as HP, MGT, SPD, DEF, RES, MOV. Lancer+'s Movement
# 5 -> 7 is its big change (Hakkapel's Movement), entered as a MOV gain.
const UPGRADES: Dictionary[String, Array] = {
	"sellsword": [0, 1, 0, 0, 0, 0],
	"fighter": [2, 2, 0, 0, 0, 0],
	"lancer": [0, 0, 0, 1, 0, 2],
	"brawler": [4, 1, 0, 0, 0, 0],
	"thief": [0, 0, 1, 0, 0, 0],
	"freewing": [0, 0, 2, 0, 1, 0],
	"lance_armor": [4, 0, 0, 1, 0, 0],
	"ward": [4, 0, 0, 1, 0, 0],
	"mage": [0, 1, 0, 0, 0, 0],
	"shaman": [0, 2, 1, 0, 0, 0],
	"suncaster": [0, 1, 1, 0, 1, 0],
}

# The stat value keys in ROSTER's order.
const STAT_KEYS: Array[int] = [
	CombatValue.Key.HP,
	CombatValue.Key.MGT,
	CombatValue.Key.SPD,
	CombatValue.Key.DEF,
	CombatValue.Key.RES,
	CombatValue.Key.MOVEMENT,
	CombatValue.Key.CON,
]

# The growth stats in ROSTER's order.
const GROWTH_STATS: Array[int] = [
	CombatValue.Stat.HP,
	CombatValue.Stat.MGT,
	CombatValue.Stat.SPD,
	CombatValue.Stat.DEF,
	CombatValue.Stat.RES,
]

# Reviewed effect text, one line per effect: the trait, the "+" trait and the innate effects.
const TEXT: Dictionary[String, Array] = {
	"sellsword": ["Before Combat, while this unit has triangle Advantage: gain 3 Block"],
	"sellsword+": ["Before Combat, while this unit has triangle Advantage: gain 5 Block"],
	"fighter": ["Missed: gain +15 Hit on its next attack this combat"],
	"fighter+": ["Missed: gain +25 Hit on its next attack this combat, gain +1 Attack this combat"],
	"lancer": ["Unit Turn Start: gain Block equal to the number of adjacent allies"],
	"lancer+": ["Unit Turn Start: gain Block equal to 2 × the number of adjacent allies"],
	"brawler": ["First Hit dealt this combat: the target loses 1 extra Stance"],
	"brawler+": ["First Hit dealt this combat: the target loses 2 extra Stance"],
	"thief": ["Always: +15 Crit Chance"],
	"thief+": ["Always: +25 Crit Chance"],
	"thief innate": ["Always: can pick locks"],
	"freewing": ["After Combat: may move after acting until Phase End"],
	"freewing+": [
		"After Combat: may move after acting until Phase End",
		"Moved after acting: gain 2 Block",
	],
	"lance_armor": ["Always: +1 Parry"],
	"lance_armor+": ["Always: +1 Parry, +1 Stance Max"],
	"ward": ["Always: +1 Shove Distance"],
	"ward+": ["Always: +1 Shove Distance", "Shoved a unit: gain 2 Block"],
	"mage": ["Every 3rd Attack made this combat: +3 Attack for that attack"],
	"mage+": ["Every 3rd Attack made this combat: +5 Attack for that attack"],
	"shaman": ["While this unit's Attack Speed is higher than its opponent's: +2 Attack"],
	"shaman+": ["While this unit's Attack Speed is higher than its opponent's: +3 Attack"],
	"suncaster": ["Unit Turn End: give adjacent allies 1 Block"],
	"suncaster+": ["Unit Turn End: give adjacent allies 2 Block"],
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_test_types()
	_test_stats()
	_test_upgraded_stats()
	_test_big_upgrades()
	_test_text_snapshots()
	_test_types_load()
	_test_ward_deploys_in_front()
	_test_skirmisher()
	_test_skirmisher_plus()
	_test_sprite_fallback()


# unit-roster.md's MVP roster, Traits and Starting weapons tables.
func _test_types() -> void:
	_same("roster units: weapons, movement, tags, role, starting weapon, trait", _describe(), (
			"; ".join([
				"sellsword sword DEFAULT [] sword simple_sword Professional",
				"fighter axe DEFAULT [] axe simple_axe Momentum",
				"lancer lance DEFAULT [] lance simple_lance Phalanx",
				"brawler gauntlets DEFAULT [] fist simple_gauntlets Breaker",
				"thief dagger MOBILE [] dagger simple_dagger Opportunist",
				"freewing sword FLIER [flier, mounted] flier simple_sword Skirmisher",
				"lance_armor lance HEAVY [armored] armored simple_lance Bulwark",
				"ward lance HEAVY [] shover simple_lance Shield Bash",
				"mage anima DEFAULT [] anima simple_anima Flow",
				"shaman dark DEFAULT [] dark simple_dark Overwhelm",
				"suncaster holy DEFAULT [] holy simple_holy Radiance",
			])
	))
	var commanders: PackedStringArray = []
	for type_id: String in ROSTER:
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type == null or unit_type.is_commander:
			commanders.append(type_id)
	_ok("roster units: unit types, none a commander", commanders.is_empty(), str(commanders))


func _test_stats() -> void:
	for type_id: String in ROSTER:
		var unit: UnitInstance = UnitInstance.new("unit:1", type_id)
		var row: Array = ROSTER[type_id]
		var sheet: StatSheet = unit.stats(_catalog)
		var stats: PackedStringArray = []
		var expected: PackedStringArray = []
		for column: int in STAT_KEYS.size():
			stats.append(str(sheet.get_int(STAT_KEYS[column])))
			expected.append(str(row[column]))
		stats.append(str(sheet.get_int(CombatValue.Key.STANCE_MAX)))
		expected.append(str(row[7]))
		_same("%s: base stats and Stance (unit-roster.md)" % [type_id], "/".join(stats), (
				"/".join(expected)
		))
		var growths: PackedStringArray = []
		var expected_growths: PackedStringArray = []
		for column: int in GROWTH_STATS.size():
			growths.append(str(unit.growth(_catalog, GROWTH_STATS[column])))
			expected_growths.append(str(row[8 + column]))
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.MOV)))
		growths.append(str(unit.growth(_catalog, CombatValue.Stat.CON)))
		expected_growths.append_array(["0", "0"])
		_same("%s: growths, none for MOV and CON" % [type_id], "/".join(growths), (
				"/".join(expected_growths)
		))


# Each upgrade adds its stat gains and never changes growths.
func _test_upgraded_stats() -> void:
	for type_id: String in UPGRADES:
		var unit: UnitInstance = UnitInstance.new("unit:1", type_id)
		unit.is_upgraded = true
		var sheet: StatSheet = unit.stats(_catalog)
		var gains: Array = UPGRADES[type_id]
		var stats: PackedStringArray = []
		var expected: PackedStringArray = []
		for column: int in gains.size():
			stats.append(str(sheet.get_int(STAT_KEYS[column])))
			var base: int = ROSTER[type_id][column]
			var gain: int = gains[column]
			expected.append(str(base + gain))
		_same("%s+: stats with the upgrade's gains" % [type_id], "/".join(stats), (
				"/".join(expected)
		))
		var growths: PackedStringArray = []
		var expected_growths: PackedStringArray = []
		for column: int in GROWTH_STATS.size():
			growths.append(str(unit.growth(_catalog, GROWTH_STATS[column])))
			expected_growths.append(str(ROSTER[type_id][8 + column]))
		_same("%s+: growths unchanged" % [type_id], "/".join(growths), "/".join(expected_growths))


# unit-roster.md's Big change column: Sellsword+, Thief+ and Mage+ add a weapon type and Sidearm;
# Lancer+ becomes Mounted (tag and movement type). Every other upgrade is standard. Lancer+ and
# Sellsword+ also go through the loadout, which applies the change to the battle state.
func _test_big_upgrades() -> void:
	var big: PackedStringArray = []
	for type_id: String in ROSTER:
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type == null:
			big.append("%s missing" % [type_id])
			continue
		var changes: PackedStringArray = []
		for weapon_type: String in unit_type.upgrade_weapon_types:
			changes.append("+%s" % [weapon_type])
		if unit_type.grants_sidearm():
			changes.append("sidearm")
		if unit_type.upgrade_changes_movement():
			changes.append(
					CombatGrid.MovementType.find_key(unit_type.upgrade_movement_type) as String
			)
		for tag: String in unit_type.upgrade_tags:
			changes.append("[%s]" % [tag])
		if not changes.is_empty():
			big.append("%s+ %s" % [type_id, " ".join(changes)])
	_same("roster units: the big upgrades", "; ".join(big), (
			"sellsword+ +axe sidearm; lancer+ MOUNTED [mounted]; thief+ +sword sidearm; "
			+ "mage+ +dark sidearm"
	))

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var lancer: Loadout.LoadedUnit = _load("lancer", PLAYER, 0, ids, true)
	_ok("lancer+: loads Mounted, with the Mounted tag", (
			lancer.is_loaded()
			and lancer.state.movement_type == CombatGrid.MovementType.MOUNTED
			and lancer.state.tags.has(ContentIds.TAG_MOUNTED)
	), str(lancer.problems))
	var swaps: PackedStringArray = []
	for type_id: String in ["sellsword", "thief", "mage", "lancer"]:
		for is_upgraded: bool in [false, true]:
			var unit: UnitInstance = UnitInstance.new("unit:1", type_id)
			unit.is_upgraded = is_upgraded
			if unit.stats(_catalog).is_allowed(CombatValue.Permission.FREE_WEAPON_SWAP):
				swaps.append("%s%s" % [type_id, "+" if is_upgraded else ""])
	_same("sidearm: only the upgrades that add a weapon type", ", ".join(swaps), (
			"sellsword+, thief+, mage+"
	))


# Generated text is canonical (content catalog plan, Approach); these are its reviewed snapshots.
func _test_text_snapshots() -> void:
	for key: String in TEXT:
		var type_id: String = key.trim_suffix("+").trim_suffix(" innate")
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type == null:
			_ok("text %s: in the catalog" % [key], false)
			continue
		var effects: Array[EffectDefinition] = unit_type.effects
		if key.ends_with("+"):
			effects = unit_type.upgraded_effects
		elif key.ends_with(" innate"):
			effects = unit_type.innate_effects
		var texts: PackedStringArray = []
		for effect: EffectDefinition in effects:
			texts.append(effect.describe())
		var expected: PackedStringArray = PackedStringArray(TEXT[key])
		_same("text %s" % [key], " | ".join(texts), " | ".join(expected))
	var innate: PackedStringArray = []
	for type_id: String in ROSTER:
		if not _catalog.unit_type(type_id).innate_effects.is_empty():
			innate.append(type_id)
	_same("roster units: only the Thief has innate effects", ", ".join(innate), "thief")


# Every type through the loadout with its starting weapon: no problems, and its weapon record.
func _test_types_load() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var problems: PackedStringArray = []
	var weapons: PackedStringArray = []
	for type_id: String in ROSTER:
		var loaded: Loadout.LoadedUnit = _load(type_id, PLAYER, 0, ids, false)
		problems.append_array(loaded.problems)
		if not loaded.is_loaded():
			problems.append("%s didn't load" % [type_id])
			continue
		var labels: PackedStringArray = []
		for weapon: CombatState.WeaponStats in loaded.weapons:
			labels.append(weapon.label)
		weapons.append("%s: %s" % [type_id, ", ".join(labels)])
	_ok("roster units: every type loads without problems", problems.is_empty(), str(problems))
	_same("roster units: each unit's weapon records", "; ".join(weapons), "; ".join([
		"sellsword: Simple Sword", "fighter: Simple Axe", "lancer: Simple Lance",
		"brawler: Simple Gauntlets", "thief: Simple Dagger", "freewing: Simple Sword",
		"lance_armor: Simple Lance", "ward: Simple Lance", "mage: Fire", "shaman: Shade",
		"suncaster: Smite",
	]))


# The Ward's role comes from its data into battle, and auto-deployment reads it as front. The Ward
# is Heavy too, which alone also makes it front, so the role itself is checked as well.
func _test_ward_deploys_in_front() -> void:
	var session: CombatSession = _battle(_plain(3, 1))
	var ward: String = _place(session, "ward", PLAYER, 0, Vector2i(0, 0))
	var sellsword: String = _place(session, "sellsword", PLAYER, 0, Vector2i(1, 0))
	if ward.is_empty() or sellsword.is_empty():
		return
	var unit: CombatUnitState = session.state.unit(ward)
	_ok("ward: the shover role, from its data", unit.role == ContentIds.ROLE_SHOVER, unit.role)
	_same("ward: auto-deployment puts it in front, a Sellsword among the strikers", "%s, %s" % [
		AutoDeploy.Role.find_key(AutoDeploy.role_of(session.state, unit)),
		AutoDeploy.Role.find_key(AutoDeploy.role_of(session.state, session.state.unit(sellsword))),
	], "FRONT, STRIKER")


# After attacking a Hound, the Freewing may still move with its movement left, once; after shoving
# it (Exposed, so it can be shoved), it may not, because Skirmisher fires After Combat and a shove
# is no combat.
func _test_skirmisher() -> void:
	var fought: CombatSession = _battle(_plain(4, 3))
	var freewing: String = _place(fought, "freewing", PLAYER, 0, Vector2i(0, 0))
	var hound: String = _place(fought, "hound", ENEMY, -1, Vector2i(1, 0))
	if freewing.is_empty() or hound.is_empty():
		return
	fought.open_battle()
	fought.submit(UnitTurnCommand.new(0, freewing, ATTACK, hound))
	var attack: CombatSession.FactBatch = fought.resolve_next()
	_ok("skirmisher: a move is pending after combat", (
			not attack.is_rejected() and fought.state.unit(freewing).is_second_move_pending
	), attack.rejected_reason)
	var away: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	fought.submit(UnitTurnCommand.new(0, freewing, MOVE, "", away))
	var moved: CombatSession.FactBatch = fought.resolve_next()
	_ok("skirmisher: it moves away, and the move is spent", (
			not moved.is_rejected()
			and fought.state.tile_of(freewing) == Vector2i(0, 2)
			and not fought.state.unit(freewing).is_second_move_pending
	), moved.rejected_reason)

	var shoved: CombatSession = _battle(_plain(4, 3))
	var shover: String = _place(shoved, "freewing", PLAYER, 0, Vector2i(0, 0))
	var pushed: String = _place(shoved, "hound", ENEMY, -1, Vector2i(1, 0))
	if shover.is_empty() or pushed.is_empty():
		return
	shoved.open_battle()
	shoved.state.set_stance(pushed, 0)
	shoved.submit(UnitTurnCommand.new(0, shover, SHOVE, pushed))
	var shove: CombatSession.FactBatch = shoved.resolve_next()
	_ok("skirmisher: no move after a shove", (
			not shove.is_rejected()
			and shoved.state.tile_of(pushed) == Vector2i(2, 0)
			and not shoved.state.unit(shover).is_second_move_pending
	), shove.rejected_reason)


# A Freewing walks up to a Hound and attacks, then moves on; only that move after acting is
# flagged a second move, and only the Freewing+ gains 2 Block from it, none from the first walk.
func _test_skirmisher_plus() -> void:
	var results: PackedStringArray = []
	for is_upgraded: bool in [false, true]:
		var session: CombatSession = _battle(_plain(4, 3))
		var freewing: String = _place(session, "freewing", PLAYER, 0, Vector2i(0, 0), is_upgraded)
		var hound: String = _place(session, "hound", ENEMY, -1, Vector2i(2, 0))
		if freewing.is_empty() or hound.is_empty():
			return
		session.open_battle()
		var walk_up: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
		session.submit(UnitTurnCommand.new(0, freewing, ATTACK, hound, walk_up))
		var attack: CombatSession.FactBatch = session.resolve_next()
		var after_attack: int = session.state.get_block(freewing)
		var away: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)]
		session.submit(UnitTurnCommand.new(0, freewing, MOVE, "", away))
		var moved: CombatSession.FactBatch = session.resolve_next()
		if attack.is_rejected() or moved.is_rejected():
			_ok("skirmisher+: both commands resolve", false, "%s %s" % [
				attack.rejected_reason, moved.rejected_reason,
			])
			return
		var flags: PackedStringArray = []
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind == CombatFact.Kind.UNIT_MOVED and fact.actor_id == freewing:
				var is_second: bool = (fact.flags & CombatFact.Flag.SECOND_MOVE) != 0
				flags.append("second" if is_second else "first")
		results.append("%s: %s, Block %d then %d" % [
			"freewing+" if is_upgraded else "freewing",
			" ".join(flags),
			after_attack,
			session.state.get_block(freewing),
		])
	_same("skirmisher+: the move after acting, flagged, and its Block", " | ".join(results), (
			"freewing: first second, Block 0 then 0 | freewing+: first second, Block 0 then 2"
	))


# No type here has a sprite yet (P07), so its token draws its fallback letters.
func _test_sprite_fallback() -> void:
	var table: UnitSpriteTable = load(SPRITE_TABLE) as UnitSpriteTable
	if table == null:
		_ok("sprites: the sprite table loads", false)
		return
	var drawn: PackedStringArray = []
	for type_id: String in ROSTER:
		if table.sprite_for(type_id) != null:
			drawn.append("%s sprite" % [type_id])
		elif BoardViewModel.letter_of(type_id).length() != 2:
			drawn.append("%s \"%s\"" % [type_id, BoardViewModel.letter_of(type_id)])
	_ok("sprites: no type has one yet, so each draws two letters", drawn.is_empty(), str(drawn))


func _battle(grid: MapGrid) -> CombatSession:
	return CombatSession.new(
			0, PackedInt32Array([0]), grid, ForecastRolls.new(), InstanceIdAllocator.new()
	)


# Loads a new unit of type_id at level 1 with its starting weapon, upgraded when is_upgraded.
func _load(
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		ids: InstanceIdAllocator,
		is_upgraded: bool
) -> Loadout.LoadedUnit:
	var unit_id: String = (
			ids.next_enemy_id(type_id) if side == ENEMY else ids.next_unit_id(type_id)
	)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	unit.is_upgraded = is_upgraded
	var items: Dictionary[String, ItemInstance] = {}
	var definition: UnitTypeDefinition = unit.definition(_catalog)
	if definition != null and not definition.starting_weapon_id.is_empty():
		var weapon: ItemInstance = ItemInstance.new(
				ids.next_item_id(definition.starting_weapon_id), definition.starting_weapon_id
		)
		items[weapon.instance_id] = weapon
		unit.weapon_id = weapon.instance_id
	return Loadout.load_unit(_catalog, unit, items, side, seat, ids)


# Loads and places a unit of type_id on tile, upgraded when is_upgraded; its id, or empty when it
# didn't load cleanly or wasn't placed.
func _place(
		session: CombatSession,
		type_id: String,
		side: CombatFact.CombatSide,
		seat: int,
		tile: Vector2i,
		is_upgraded: bool = false
) -> String:
	var loaded: Loadout.LoadedUnit = _load(type_id, side, seat, session.ids, is_upgraded)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		_ok("%s: loads for the battle" % [type_id], false, str(loaded.problems))
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = tile
	return loaded.state.id if session.add_unit(loaded.state, loaded.bases) else ""


func _plain(width: int, height: int) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "roster_units"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for y: int in height:
		for x: int in width:
			layout.set_terrain(Vector2i(x, y), plain)
	return MapGrid.new(layout)


func _describe() -> String:
	var parts: PackedStringArray = []
	for type_id: String in ROSTER:
		var unit_type: UnitTypeDefinition = _catalog.unit_type(type_id)
		if unit_type == null:
			parts.append("%s missing" % [type_id])
			continue
		parts.append("%s %s %s [%s] %s %s %s" % [
			type_id,
			"/".join(unit_type.weapon_types),
			CombatGrid.MovementType.find_key(unit_type.movement_type),
			", ".join(unit_type.tags),
			unit_type.role,
			unit_type.starting_weapon_id,
			unit_type.trait_name,
		])
	return "; ".join(parts)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
