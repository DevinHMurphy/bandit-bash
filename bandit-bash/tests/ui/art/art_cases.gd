# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     art_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 25, 2026
# ==============================================================================

extends RefCounted
## The board art's cases for the ui/art suite (P15 UL2): every unit type, enemy class, mini-boss,
## the boss and each breakable resolves to a sprite; every item to an icon, with names unique so
## the battle finds an item's icon by its label; every terrain to a tile of art (two listed
## placeholders keep their flat colour); every map object state to its art (the house to its
## placeholder); the intents and the Block ban to icons; a thrown keg's fuse on its token, as it
## lands and as it burns; and the victory's item pick row showing an offer's icon.
##
## [b]The battle:[/b] the Old Mill with the M1 pack, begun as the board cases begin M1
## ([method BattleViewCases.begin_m1]); a keg is thrown onto the first tile it can land on.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/art"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const SPRITE_TABLE: String = "res://assets/sprites/units/unit_sprites.tres"
const TILE_SET: String = "res://maps/greybox_tile_set.tres"
const OLD_MILL: String = "res://maps/standard/old_mill.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const MARK_SCENE: PackedScene = preload("res://ui/battle/board/map_object_mark.tscn")
const INTENT_SCENE: PackedScene = preload("res://ui/battle/intents/intent_icon.tscn")
const BAN_SCENE: PackedScene = preload("res://ui/battle/unit/block_ban_mark.tscn")
const ROW_SCENE: PackedScene = preload("res://ui/campaign/victory/reward_row.tscn")

# The terrains with no fitting Godot_FE tile, which keep their flat greybox colour (RF-008).
const PLACEHOLDER_TERRAIN: PackedStringArray = ["spiked_wall", "spilled_oil"]

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0A27

# How far the keg case looks for a tile a keg can land on.
const SEARCH_SPAN: int = 16

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where scenes are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_unit_sprites()
	_test_item_icons()
	_test_terrain_tiles()
	_test_object_art()
	_test_intent_icons()
	_test_fuse_and_battle_icons()
	_test_reward_row()


func _test_unit_sprites() -> void:
	var table: UnitSpriteTable = load(SPRITE_TABLE) as UnitSpriteTable
	if table == null:
		_check.call("sprites: the sprite table loads", false, SPRITE_TABLE)
		return
	var ids: PackedStringArray = []
	for kind: EffectCatalog.Kind in [
		EffectCatalog.Kind.UNIT_TYPE, EffectCatalog.Kind.ENEMY_CLASS,
	]:
		for resource: Resource in EffectCatalog.all_of(kind):
			ids.append(str(resource.get(&"id")))
	# A breakable's type is its kind's label, as MapObjects places it.
	for kind: MapLayout.ObjectKind in MapObjects.BREAKABLE_STATS:
		ids.append((MapLayout.ObjectKind.find_key(kind) as String).capitalize())
	var missing: PackedStringArray = []
	for id: String in ids:
		var texture: Texture2D = table.sprite_for(id)
		if texture == null or texture.get_size() != Vector2(32.0, 32.0):
			missing.append(id)
	_check.call("sprites: every unit type, enemy class, mini-boss, boss and breakable (%d)" % [
		ids.size(),
	], missing.is_empty() and ids.size() > 30, ", ".join(missing))
	var bosses: PackedStringArray = [
		"bloodhound", "brigand_captain", "hex_matron", "stone_golem", "powder_baron",
	]
	var shared: PackedStringArray = []
	for id: String in bosses:
		if not ids.has(id):
			shared.append("%s not in the catalog" % [id])
	_check.call("sprites: the four mini-bosses and the Powder Baron are enemy classes", (
			shared.is_empty()
	), ", ".join(shared))


func _test_item_icons() -> void:
	var missing: PackedStringArray = []
	var names: Dictionary[String, String] = {}
	var repeated: PackedStringArray = []
	var count: int = 0
	for kind: EffectCatalog.Kind in [
		EffectCatalog.Kind.WEAPON, EffectCatalog.Kind.EQUIPMENT, EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]:
		for resource: Resource in EffectCatalog.all_of(kind):
			var item: ItemDefinition = resource as ItemDefinition
			if item == null:
				continue
			count += 1
			if item.icon == null:
				missing.append(item.id)
			if names.has(item.display_name):
				repeated.append("%s and %s" % [names[item.display_name], item.id])
			names[item.display_name] = item.id
	_check.call("items: every item has an icon (%d)" % [count], (
			missing.is_empty() and count > 100
	), ", ".join(missing))
	_check.call("items: display names are unique, so a label finds one icon", (
			repeated.is_empty()
	), ", ".join(repeated))


func _test_terrain_tiles() -> void:
	var tile_set: TileSet = load(TILE_SET) as TileSet
	var source: TileSetAtlasSource = null
	if tile_set != null:
		source = tile_set.get_source(tile_set.get_source_id(0)) as TileSetAtlasSource
	if source == null or source.texture == null or source.texture is GradientTexture2D:
		_check.call("terrain: the tile set draws an art atlas", false, TILE_SET)
		return
	var atlas: Image = source.texture.get_image()
	var cells: Dictionary[String, Vector2i] = {}
	for i: int in source.get_tiles_count():
		var coords: Vector2i = source.get_tile_id(i)
		var terrain: Variant = source.get_tile_data(coords, 0).get_custom_data(
				MapLoader.TERRAIN_DATA
		)
		if terrain is String and not (terrain as String).is_empty():
			cells[terrain as String] = coords
	var wrong: PackedStringArray = []
	var seen: Dictionary[PackedByteArray, String] = {}
	var count: int = 0
	for resource: Resource in EffectCatalog.all_of(EffectCatalog.Kind.TERRAIN):
		var id: String = str(resource.get(&"id"))
		count += 1
		if not cells.has(id):
			wrong.append("%s has no tile" % [id])
			continue
		var cell: Image = atlas.get_region(Rect2i(cells[id] * 32, Vector2i(32, 32)))
		var pixels: PackedByteArray = cell.get_data()
		if seen.has(pixels):
			wrong.append("%s looks like %s" % [id, seen[pixels]])
		seen[pixels] = id
		# Some Godot_FE tiles are flat too (plain, ocean), so only the placeholders are checked.
		if PLACEHOLDER_TERRAIN.has(id) and not _is_flat(cell):
			wrong.append("%s should be the flat placeholder" % [id])
	_check.call("terrain: every terrain has its own tile; the placeholders flat (%d)" % [count], (
			wrong.is_empty() and count > 20
	), ", ".join(wrong))


func _test_object_art() -> void:
	var mark: MapObjectMark = MARK_SCENE.instantiate()
	_root.add_child(mark)
	var wrong: PackedStringArray = []
	var seen: Dictionary[Texture2D, String] = {}
	for state: Array in _object_states():
		var view: BoardViewModel.ObjectView = state[1]
		mark.show_object(view, Vector2.ZERO)
		var art: Texture2D = mark.get_art()
		var expects_art: bool = state[2]
		if (art != null) != expects_art:
			wrong.append("%s: art %s" % [state[0], art])
		elif art == null and mark.get_glyph_text().is_empty():
			wrong.append("%s: no placeholder glyph" % [state[0]])
		var tint: Color = mark.spent_modulate if view.is_spent() else Color.WHITE
		if not mark.modulate.is_equal_approx(tint):
			wrong.append("%s: tint %s" % [state[0], mark.modulate])
		if art != null and state[3]:
			if seen.has(art):
				wrong.append("%s shares its art with %s" % [state[0], seen[art]])
			seen[art] = state[0]
	mark.free()
	_check.call("objects: every state has its art, the house its placeholder", wrong.is_empty(), (
			"; ".join(wrong)
	))


func _test_intent_icons() -> void:
	var icon: IntentIcon = INTENT_SCENE.instantiate()
	_root.add_child(icon)
	var wrong: PackedStringArray = []
	var seen: Dictionary[Texture2D, int] = {}
	for kind: EnemyIntent.Kind in [
		EnemyIntent.Kind.ATTACK, EnemyIntent.Kind.HEAL, EnemyIntent.Kind.GUARD,
		EnemyIntent.Kind.ADVANCE, EnemyIntent.Kind.USE_OBJECT, EnemyIntent.Kind.SIGNATURE,
	]:
		var entry: IntentViewModel.Entry = IntentViewModel.Entry.new()
		entry.enemy_id = "enemy:art"
		entry.kind = kind
		icon.show_entry(entry, Vector2.ZERO, false)
		var art: Texture2D = icon.get_art()
		if art == null or seen.has(art):
			wrong.append("%s: %s" % [EnemyIntent.Kind.find_key(kind), art])
		else:
			seen[art] = kind
	icon.free()
	var ban: BlockBanMark = BAN_SCENE.instantiate()
	_root.add_child(ban)
	ban.show_ban(true)
	if ban.get_shield() == null or ban.text.is_empty():
		wrong.append("block ban: shield %s, glyph \"%s\"" % [ban.get_shield(), ban.text])
	ban.free()
	_check.call("intents: each kind has its own icon; the Block ban a slashed shield", (
			wrong.is_empty()
	), "; ".join(wrong))


func _test_fuse_and_battle_icons() -> void:
	var map: CombatMapDefinition = load(OLD_MILL) as CombatMapDefinition
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = null
	if map != null:
		battle = BattleViewCases.begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("fuse: the Old Mill battle begins", false, OLD_MILL)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var thrower: String = state.units_of(CombatFact.CombatSide.ENEMY)[0]
	var keg_id: String = ""
	for y: int in SEARCH_SPAN:
		for x: int in SEARCH_SPAN:
			if keg_id.is_empty() and MapObjects.can_land(state, Vector2i(x, y)):
				keg_id = MapObjects.throw_keg(session, Vector2i(x, y), thrower)
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)
	var keg: UnitToken = null if keg_id.is_empty() else view.token_of(keg_id)
	var landed: String = _fuse_text(keg)
	var burned: CombatFact = CombatFact.new(CombatFact.Kind.OBJECT_STATE_CHANGED, keg_id)
	burned.key = MapObjects.Change.FUSE_BURNED
	burned.amount = MapObjects.FUSE_PHASES
	session.bus.play(burned)
	var after: String = _fuse_text(keg)
	var player: String = state.units_of(CombatFact.CombatSide.PLAYER)[0]
	var plain: String = _fuse_text(view.token_of(player))
	_check.call("fuse: a thrown keg shows its fuse as it lands and as it burns", (
			landed == str(MapObjects.FUSE_PHASES + 1)
			and after == str(MapObjects.FUSE_PHASES)
			and plain.is_empty()
	), "landed \"%s\", burned \"%s\", a unit \"%s\"" % [landed, after, plain])

	var weapon: CombatState.WeaponStats = state.equipped_weapon(player)
	var detail: UnitDetailViewModel = UnitDetailViewModel.build(session, player)
	var expected: Texture2D = _icon_named(BattleText.name_of(session, weapon.id))
	_check.call("battle icons: a unit's weapon finds its item's icon by its label", (
			expected != null
			and BattleText.item_icon(session, weapon.id) == expected
			and detail != null
			and detail.weapon != null
			and detail.weapon.icon == expected
	), BattleText.name_of(session, weapon.id))
	view.free()
	run.close()


func _test_reward_row() -> void:
	var offer: ItemDefinition = _catalog.item("iron_shield")
	var model: CombatResultsModel = CombatResultsModel.new()
	model.pick = ItemPick.new()
	model.pick.slot = ItemPick.Slot.EQUIPMENT
	model.pick.offers.append(ItemPick.Offer.new("iron_shield", "item:art"))
	model.offers.append(offer)
	var rewards: Array[VictoryReward] = VictoryRewards.build(model)
	var row: RewardRow = ROW_SCENE.instantiate()
	_root.add_child(row)
	var shown: Texture2D = null
	if not rewards.is_empty():
		row.show_reward(rewards[0])
		var icon: RewardIcon = row.get_node(^"%Icon") as RewardIcon
		shown = null if icon == null else icon.texture
	row.free()
	_check.call("rewards: the item pick row shows its offer's icon", (
			offer != null and offer.icon != null and shown == offer.icon
	), "%s" % [shown])


# The fuse a token's badge shows; empty when hidden or there is no token.
func _fuse_text(token: UnitToken) -> String:
	if token == null or not is_instance_valid(token.info):
		return ""
	return token.info.get_fuse_badge().get_text()


func _icon_named(display_name: String) -> Texture2D:
	for kind: EffectCatalog.Kind in [EffectCatalog.Kind.WEAPON]:
		for resource: Resource in EffectCatalog.all_of(kind):
			var item: ItemDefinition = resource as ItemDefinition
			if item != null and item.display_name == display_name:
				return item.icon
	return null


# Each object state a mark draws: [name, view, whether it has art, whether its art is its own].
func _object_states() -> Array[Array]:
	var states: Array[Array] = []
	var kinds: Array[MapLayout.ObjectKind] = [
		MapLayout.ObjectKind.CHEST, MapLayout.ObjectKind.LEVER, MapLayout.ObjectKind.HOUSE,
		MapLayout.ObjectKind.FOOD_SHELF, MapLayout.ObjectKind.BOOK_SHELF,
		MapLayout.ObjectKind.WEAPON_RACK, MapLayout.ObjectKind.PASSAGE,
	]
	for kind: MapLayout.ObjectKind in kinds:
		var name: String = (MapLayout.ObjectKind.find_key(kind) as String).to_lower()
		var has_art: bool = kind != MapLayout.ObjectKind.HOUSE
		var used_own: bool = kind in [
			MapLayout.ObjectKind.FOOD_SHELF, MapLayout.ObjectKind.BOOK_SHELF,
			MapLayout.ObjectKind.WEAPON_RACK,
		]
		states.append([name, _view(kind, false, false, false, -1), has_art, true])
		states.append([name + " used", _view(kind, false, true, false, -1), has_art, used_own])
	states.append(["key door closed", _view(MapLayout.ObjectKind.DOOR, false, false, false, -1),
			true, true])
	states.append(["key door open", _view(MapLayout.ObjectKind.DOOR, true, false, false, -1),
			true, false])
	states.append(["lever door closed", _view(MapLayout.ObjectKind.DOOR, false, false, false, 0),
			true, true])
	states.append(["lever door open", _view(MapLayout.ObjectKind.DOOR, true, false, false, 0),
			true, false])
	states.append(["brazier lit", _view(MapLayout.ObjectKind.BRAZIER, false, false, true, -1),
			true, true])
	states.append(["brazier out", _view(MapLayout.ObjectKind.BRAZIER, false, false, false, -1),
			true, true])
	return states


func _view(
		kind: MapLayout.ObjectKind, is_open: bool, is_used: bool, is_lit: bool, group_id: int
) -> BoardViewModel.ObjectView:
	var view: BoardViewModel.ObjectView = BoardViewModel.ObjectView.new()
	view.id = "object:art"
	view.kind = kind
	view.is_open = is_open
	view.is_used = is_used
	view.is_lit = is_lit
	view.group_id = group_id
	return view


static func _is_flat(cell: Image) -> bool:
	var first: Color = cell.get_pixel(0, 0)
	for y: int in cell.get_height():
		for x: int in cell.get_width():
			if not cell.get_pixel(x, y).is_equal_approx(first):
				return false
	return true
