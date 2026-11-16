# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pool_cases.gd
# Author:
# Created:  November 15, 2026
# Modified: November 15, 2026
# ==============================================================================

extends RefCounted
## The unit prefix and item pool cases for tests/content/run_all.gd: the twelve prefixes against
## unit-roster.md (each field, each tier's budget, the prefix rules), the tier odds, seeded rolls
## and re-rolls; the pools by kind and rarity (never a Basic, Legendary or Unique item, the
## fallbacks, seeded draws); and container contents drawn from the real catalog (each kind's pool,
## the house's odds, the gold and rarity unchanged by the catalog). Reports each case through the
## check callable it is given.
##
## The expected values are transcribed from the design docs, never read from the data, so a
## changed .tres fails here until the docs and this file agree. The goldens pin today's catalog:
## adding an item or prefix of a pool's kind changes them, and they are then re-recorded.
##
## @tutorial(Unit roster, Prefixes): docs/design/unit-roster.md

const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE
const BASIC: ItemDefinition.Rarity = ItemDefinition.Rarity.BASIC
const LEGENDARY: ItemDefinition.Rarity = ItemDefinition.Rarity.LEGENDARY
const UNIQUE: ItemDefinition.Rarity = ItemDefinition.Rarity.UNIQUE

const CHEST: MapLayout.ObjectKind = MapLayout.ObjectKind.CHEST
const HOUSE: MapLayout.ObjectKind = MapLayout.ObjectKind.HOUSE
const FOOD_SHELF: MapLayout.ObjectKind = MapLayout.ObjectKind.FOOD_SHELF
const BOOK_SHELF: MapLayout.ObjectKind = MapLayout.ObjectKind.BOOK_SHELF
const WEAPON_RACK: MapLayout.ObjectKind = MapLayout.ObjectKind.WEAPON_RACK

# unit-roster.md's prefix list. Columns: tier, stats HP, MGT, SPD, DEF, RES, then Hit, then growths
# HP, MGT, SPD, DEF, RES.
const PREFIXES: Dictionary[String, Array] = {
	"heroic": [2, 2, 2, 2, 0, 0, 0, 10, 15, 10, 0, 0],
	"stalwart": [2, 0, 0, 0, 3, 2, 0, 0, 0, 0, 20, 15],
	"mighty": [1, 0, 3, 0, 0, 0, 0, 0, 25, 0, 0, 0],
	"swift": [1, 0, 0, 3, 0, 0, 0, 0, 0, 25, 0, 0],
	"sturdy": [1, 4, 0, 0, 1, 0, 0, 15, 0, 0, 10, 0],
	"warded": [1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 25],
	"keen": [1, 0, 0, 1, 0, 0, 20, 0, 10, 15, 0, 0],
	"reckless": [1, 0, 4, 0, -1, 0, 0, 0, 30, 0, -5, 0],
	"hasty": [1, -2, 0, 4, 0, 0, 0, -5, 0, 30, 0, 0],
	"frail": [-1, -4, 0, 0, 0, 0, 0, -10, 0, 0, 0, 0],
	"sluggish": [-1, 0, 0, -2, 0, 0, 0, 0, 0, -10, 0, 0],
	"feeble": [-2, 0, -2, -2, 0, 0, 0, 0, -15, -10, 0, 0],
}

# unit-roster.md's Budget by tier: stat points, growth points.
const BUDGETS: Dictionary[int, Array] = {
	2: [5, 35],
	1: [3, 25],
	-1: [-2, -10],
	-2: [-4, -25],
}

# The stats in PREFIXES' column order.
const STATS: Array[CombatValue.Stat] = [
	CombatValue.Stat.HP,
	CombatValue.Stat.MGT,
	CombatValue.Stat.SPD,
	CombatValue.Stat.DEF,
	CombatValue.Stat.RES,
]

# Draws for the statistical cases, and how far a share may stray from its chance.
const DRAWS: int = 20000
const TOLERANCE: float = 0.012

# Golden draws on today's catalog (see the class doc). The first twelve rolls of stream 7; the
# first eight re-rolls of a Keen unit on stream 11; one chest, house, food shelf and rack each on
# streams 1 to 3; the sha256 of 200 pool draws.
const GOLDEN_ROLLS: String = (
		"none,none,keen,keen,none,hasty,none,reckless,mighty,sluggish,keen,heroic"
)
const GOLDEN_REROLLS: String = "none,feeble,heroic,reckless,none,none,frail,swift"
const GOLDEN_CONTENTS: String = (
		"wyvern_pike,large_potion,brutvine_heartroot,twin_fang,boar_spear,lockpick,"
		+ "sanctuary_shell,sabre,minor_heal,21,runewart,javelin"
)
const GOLDEN_DRAWS_SHA: String = "c5bde528a2963bd283e5faedbdd7b33e736353267617c30689c7ebb5e3371e58"

var _report: Callable
var _catalog: EffectCatalog.Index = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_check("pools: the catalog loads", _catalog != null)
	if _catalog == null:
		return
	_test_prefix_table()
	_test_prefix_budgets()
	_test_prefix_rules()
	_test_tier_odds()
	_test_roll_shares()
	_test_roll_seeded()
	_test_rerolls()
	_test_roll_edges()
	_test_never_unsellable()
	_test_draw_fallbacks()
	_test_draw_seeded()
	_test_rune_draw()
	_test_contents_pools()
	_test_house_odds()
	_test_contents_keep_their_draws()
	_test_contents_seeded()


func _test_prefix_table() -> void:
	var all: Array[Resource] = _catalog.all_of(EffectCatalog.Kind.UNIT_PREFIX)
	_check(
			"prefixes: twelve in data/prefixes/units/",
			all.size() == PREFIXES.size(),
			str(all.size())
	)
	for id: String in PREFIXES:
		var row: Array = PREFIXES[id]
		var prefix: UnitPrefixDefinition = _catalog.unit_prefix(id)
		if prefix == null:
			_check("prefix %s: is in the catalog" % [id], false)
			continue
		var stats: Dictionary[CombatValue.Stat, int] = {}
		var growths: Dictionary[CombatValue.Stat, int] = {}
		for index: int in STATS.size():
			if row[1 + index] != 0:
				stats[STATS[index]] = row[1 + index]
			if row[7 + index] != 0:
				growths[STATS[index]] = row[7 + index]
		var tier: int = row[0]
		var hit: int = row[6]
		_check("prefix %s: tier, stats, Hit and growths as unit-roster.md lists" % [id], (
				prefix.tier == tier
				and prefix.stat_deltas == stats
				and prefix.growth_deltas == growths
				and prefix.hit_delta == hit
				and prefix.display_name == id.capitalize()
				and prefix.effects.is_empty()
		), "%d %s %s %d" % [
			prefix.tier, prefix.stat_deltas, prefix.growth_deltas, prefix.hit_delta,
		])


# 2 HP and 10 Hit count as 1 stat point each; growth points are the growths' sum.
func _test_prefix_budgets() -> void:
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.UNIT_PREFIX):
		var prefix: UnitPrefixDefinition = resource as UnitPrefixDefinition
		var points: float = float(prefix.hit_delta) / 10.0
		for stat: CombatValue.Stat in prefix.stat_deltas:
			var delta: int = prefix.stat_deltas[stat]
			points += float(delta) / 2.0 if stat == CombatValue.Stat.HP else float(delta)
		var growth: int = 0
		for stat: CombatValue.Stat in prefix.growth_deltas:
			growth += prefix.growth_deltas[stat]
		var budget: Array = BUDGETS.get(prefix.tier, [0, 0])
		var stat_budget: int = budget[0]
		var growth_budget: int = budget[1]
		_check("prefix %s: spends its tier's budget" % [prefix.id], (
				BUDGETS.has(prefix.tier)
				and is_equal_approx(points, float(stat_budget))
				and growth == growth_budget
		), "tier %d: %.1f / %d" % [prefix.tier, points, growth])


func _test_prefix_rules() -> void:
	var counts: Dictionary[int, int] = {}
	var broken: PackedStringArray = []
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.UNIT_PREFIX):
		var prefix: UnitPrefixDefinition = resource as UnitPrefixDefinition
		counts[prefix.tier] = counts.get(prefix.tier, 0) + 1
		for deltas: Dictionary in [prefix.stat_deltas, prefix.growth_deltas]:
			if deltas.has(CombatValue.Stat.MOV) or deltas.has(CombatValue.Stat.CON):
				broken.append("%s touches MOV or CON" % [prefix.id])
		for stat: CombatValue.Stat in prefix.stat_deltas:
			if absi(prefix.stat_deltas[stat]) > 5:
				broken.append("%s moves a stat more than 5" % [prefix.id])
		var hp: int = prefix.stat_deltas.get(CombatValue.Stat.HP, 0)
		if hp % 2 != 0:
			broken.append("%s has an odd HP change" % [prefix.id])
	_check("prefixes: never MOV or CON, no stat past 5, HP in whole points", (
			broken.is_empty()
	), ", ".join(broken))
	var expected: Dictionary[int, int] = {2: 2, 1: 7, -1: 2, -2: 1}
	_check("prefixes: two at +2, seven at +1, two at -1, one at -2, none at 0", (
			counts == expected
	), str(counts))


func _test_tier_odds() -> void:
	var total: int = 0
	var positive: int = 0
	var negative: int = 0
	for index: int in UnitPrefixDefinition.TIERS.size():
		var weight: int = UnitPrefixDefinition.TIER_WEIGHTS[index]
		var tier: int = UnitPrefixDefinition.TIERS[index]
		total += weight
		positive += weight if tier > 0 else 0
		negative += weight if tier < 0 else 0
	var odds: Dictionary[int, int] = {}
	for index: int in UnitPrefixDefinition.TIERS.size():
		odds[UnitPrefixDefinition.TIERS[index]] = UnitPrefixDefinition.TIER_WEIGHTS[index]
	var expected: Dictionary[int, int] = {0: 30, 2: 10, 1: 35, -1: 18, -2: 7}
	_check("odds: none 30, +2 10, +1 35, -1 18, -2 7, out of 100", (
			total == 100 and odds == expected
	), str(odds))
	_check("odds: 45% positive against 25% negative", positive == 45 and negative == 25)


func _test_roll_shares() -> void:
	var by_tier: Dictionary[int, int] = {}
	var by_id: Dictionary[String, int] = {}
	var stream: RngStream = RngStream.new(3)
	for draw: int in DRAWS:
		var id: String = UnitPrefixDefinition.roll(stream, _catalog)
		var tier: int = 0 if id.is_empty() else _catalog.unit_prefix(id).tier
		by_tier[tier] = by_tier.get(tier, 0) + 1
		by_id[id] = by_id.get(id, 0) + 1
	for index: int in UnitPrefixDefinition.TIERS.size():
		var tier: int = UnitPrefixDefinition.TIERS[index]
		var chance: int = UnitPrefixDefinition.TIER_WEIGHTS[index]
		_check("roll: tier %+d comes up %d%% of the time" % [tier, chance], (
				_near((by_tier.get(tier, 0) as int), DRAWS, float(chance))
		), str(by_tier))
	var plus_one: Array[UnitPrefixDefinition] = UnitPrefixDefinition.of_tier(_catalog, 1)
	var even: bool = plus_one.size() == 7
	for prefix: UnitPrefixDefinition in plus_one:
		even = even and _near((by_id.get(prefix.id, 0) as int), DRAWS, 35.0 / 7.0)
	_check("roll: within a tier every prefix has equal odds", even, str(by_id))


func _test_roll_seeded() -> void:
	var texts: PackedStringArray = []
	for attempt: int in 2:
		var stream: RngStream = RngStream.new(7)
		var ids: PackedStringArray = []
		for draw: int in 12:
			ids.append(_shown(UnitPrefixDefinition.roll(stream, _catalog)))
		texts.append(",".join(ids))
	_check("roll: the same seed rolls the same prefixes", texts[0] == texts[1])
	_check("roll: stream 7's first twelve rolls are pinned", texts[0] == GOLDEN_ROLLS, texts[0])
	var stream: RngStream = RngStream.new(11)
	var rerolls: PackedStringArray = []
	for draw: int in 8:
		rerolls.append(_shown(UnitPrefixDefinition.reroll(stream, _catalog, "keen")))
	_check("reroll: stream 11's first eight Keen re-rolls are pinned", (
			",".join(rerolls) == GOLDEN_REROLLS
	), ",".join(rerolls))


func _test_rerolls() -> void:
	var currents: PackedStringArray = PREFIXES.keys()
	currents.append(UnitPrefixDefinition.NO_PREFIX)
	var stream: RngStream = RngStream.new(17)
	for current: String in currents:
		var is_different: bool = true
		var reached: Dictionary[String, bool] = {}
		for draw: int in 400:
			var id: String = UnitPrefixDefinition.reroll(stream, _catalog, current)
			is_different = is_different and id != current
			reached[id] = true
		_check("reroll: from %s never lands on it again" % [_shown(current)], (
				is_different and reached.size() == PREFIXES.size()
		), str(reached.keys()))
	var feeble: Dictionary[int, int] = {}
	for draw: int in DRAWS:
		var id: String = UnitPrefixDefinition.reroll(stream, _catalog, "feeble")
		var tier: int = 0 if id.is_empty() else _catalog.unit_prefix(id).tier
		feeble[tier] = feeble.get(tier, 0) + 1
	# The -2 tier holds only Feeble, so its 7 drops out: the rest out of 93.
	_check("reroll: Feeble's emptied tier drops out of the odds", (
			not feeble.has(-2)
			and _near((feeble.get(0, 0) as int), DRAWS, 3000.0 / 93.0)
			and _near((feeble.get(1, 0) as int), DRAWS, 3500.0 / 93.0)
	), str(feeble))
	var from_none: Dictionary[int, int] = {}
	for draw: int in DRAWS:
		var id: String = UnitPrefixDefinition.reroll(stream, _catalog, "")
		var tier: int = 0 if id.is_empty() else _catalog.unit_prefix(id).tier
		from_none[tier] = from_none.get(tier, 0) + 1
	_check("reroll: from no prefix always gains one, by the other tiers' odds", (
			not from_none.has(0)
			and _near((from_none.get(1, 0) as int), DRAWS, 3500.0 / 70.0)
			and _near((from_none.get(-2, 0) as int), DRAWS, 700.0 / 70.0)
	), str(from_none))


func _test_roll_edges() -> void:
	var empty: EffectCatalog.Index = EffectCatalog.Index.new()
	empty.finish()
	var lone: EffectCatalog.Index = _index_of([_prefix("lone", 1)])
	var stream: RngStream = RngStream.new(5)
	var none_only: bool = true
	var lone_or_none: Dictionary[String, bool] = {}
	for draw: int in 200:
		none_only = none_only and UnitPrefixDefinition.roll(stream, empty) == ""
		lone_or_none[UnitPrefixDefinition.roll(stream, lone)] = true
	_check("roll: a catalog with no prefixes always rolls none", none_only)
	_check("roll: tiers with no prefix drop out of the odds", (
			lone_or_none.size() == 2 and lone_or_none.has("lone") and lone_or_none.has("")
	), str(lone_or_none.keys()))
	_check("reroll: with nothing else to land on, it stays none and draws nothing", (
			UnitPrefixDefinition.reroll(stream, empty, "") == ""
			and UnitPrefixDefinition.reroll(stream, lone, "lone") == ""
	))
	_check("roll: a null stream or catalog rolls none", (
			UnitPrefixDefinition.roll(null, _catalog) == ""
			and UnitPrefixDefinition.roll(stream, null) == ""
	))


# Done when: a Basic or Legendary item never appears in a sellable pool. Unique items neither.
func _test_never_unsellable() -> void:
	var kinds: Array[EffectCatalog.Kind] = [
		EffectCatalog.Kind.WEAPON,
		EffectCatalog.Kind.EQUIPMENT,
		EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]
	var all: Array[ItemDefinition] = ItemPools.items_of(_catalog, kinds)
	var unsold: Dictionary[int, int] = {}
	for item: ItemDefinition in all:
		if not Prices.is_sellable(item.rarity):
			unsold[item.rarity] = unsold.get(item.rarity, 0) + 1
	_check("pools: the catalog has Basic, Legendary and Unique items to leave out", (
			unsold.has(BASIC) and unsold.has(LEGENDARY) and unsold.has(UNIQUE)
	), str(unsold))
	_check("pools: no pool of a Basic, Legendary or Unique rarity holds an item", (
			ItemPools.of_rarity(all, BASIC).is_empty()
			and ItemPools.of_rarity(all, LEGENDARY).is_empty()
			and ItemPools.of_rarity(all, UNIQUE).is_empty()
	))
	_check("pools: the drawn rarities are the sold ones", ItemPools.DRAWN_RARITIES == [
		COMMON, UNCOMMON, RARE,
	] and ItemPick.OFFERED_RARITIES == ItemPools.DRAWN_RARITIES)
	var stream: RngStream = RngStream.new(23)
	var drawn: Dictionary[int, int] = {}
	for draw: int in DRAWS:
		var kind: Array[EffectCatalog.Kind] = [kinds[draw % kinds.size()]]
		var item: ItemDefinition = ItemPools.draw(
				stream, ItemPools.items_of(_catalog, kind), stream.pick_index(3)
		)
		drawn[item.rarity] = drawn.get(item.rarity, 0) + 1
	_check("pools: %d draws over every kind find only Common, Uncommon and Rare" % [DRAWS], (
			drawn.size() == 3 and drawn.has(COMMON) and drawn.has(UNCOMMON) and drawn.has(RARE)
	), str(drawn))
	var unsold_only: Array[ItemDefinition] = [_item("basic", BASIC), _item("legend", LEGENDARY)]
	_check("pools: a pool of only unsold items draws nothing", (
			ItemPools.draw(stream, unsold_only, 0) == null
			and ItemPools.draw(stream, unsold_only, 2) == null
	))


func _test_draw_fallbacks() -> void:
	var items: Array[ItemDefinition] = [
		_item("c1", COMMON), _item("c2", COMMON), _item("r1", RARE),
	]
	var stream: RngStream = RngStream.new(2)
	_check("draw: an empty rarity falls to the lower one first", (
			ItemPools.draw(stream, items, 1).rarity == COMMON
	))
	var excluded: Dictionary[String, bool] = {"c1": true, "c2": true}
	_check("draw: with the lower ones taken, the higher one", (
			ItemPools.draw(stream, items, 1, excluded).id == "r1"
	))
	excluded["r1"] = true
	_check("draw: with every item taken, none", ItemPools.draw(stream, items, 0, excluded) == null)
	var weapons: Array[ItemDefinition] = [_weapon("w_axe", "axe"), _weapon("w_bow", "bow")]
	var usable: PackedStringArray = ["bow"]
	var is_usable: bool = true
	for draw: int in 50:
		is_usable = is_usable and ItemPools.draw(stream, weapons, 0, {}, usable).id == "w_bow"
	_check("draw: a usable type when one exists", is_usable)
	_check("draw: any type when none is usable", (
			ItemPools.draw(stream, weapons, 0, {}, PackedStringArray(["staff"])) != null
	))
	_check("draw: a null stream draws nothing", ItemPools.draw(null, items, 0) == null)
	var consumables: Array[ItemDefinition] = ItemPools.items_of(
			_catalog, [EffectCatalog.Kind.CONSUMABLE] as Array[EffectCatalog.Kind]
	)
	var ingredients: Array[ItemDefinition] = ItemPools.with_use_kinds(
			consumables, PackedStringArray(["ingredient"])
	)
	var only_ingredients: bool = not ingredients.is_empty()
	for item: ItemDefinition in ingredients:
		var consumable: ConsumableDefinition = item as ConsumableDefinition
		only_ingredients = only_ingredients and consumable.use_kind == "ingredient"
	_check("pools: a use-kind filter keeps only those consumables", only_ingredients)


# Done when: a seeded pool draw is stable.
func _test_draw_seeded() -> void:
	var texts: PackedStringArray = []
	for attempt: int in 2:
		var stream: RngStream = RngStream.new(31)
		var ids: PackedStringArray = []
		for draw: int in 200:
			var kind: Array[EffectCatalog.Kind] = [_kind_for(draw)]
			var item: ItemDefinition = ItemPools.draw(
					stream, ItemPools.items_of(_catalog, kind), draw % 3
			)
			ids.append(item.id)
		texts.append(",".join(ids))
	_check("draw: the same seed draws the same items", texts[0] == texts[1])
	_check("draw: stream 31's 200 draws are pinned", (
			texts[0].sha256_text() == GOLDEN_DRAWS_SHA
	), texts[0].sha256_text())


func _test_rune_draw() -> void:
	var runes: EffectCatalog.Index = _index_of([_rune("rune_a"), _rune("rune_b")])
	var stream: RngStream = RngStream.new(9)
	var seen: Dictionary[String, bool] = {}
	for draw: int in 100:
		seen[ItemPools.draw_rune(stream, runes).id] = true
	_check("runes: drawn evenly from the catalog's runes", seen.size() == 2, str(seen.keys()))
	var empty: EffectCatalog.Index = EffectCatalog.Index.new()
	empty.finish()
	_check("runes: none to draw from gives none", (
			ItemPools.draw_rune(stream, empty) == null and ItemPools.draw_rune(null, runes) == null
	))


# Each container draws from its own pool of the real catalog.
func _test_contents_pools() -> void:
	_check("contents: the house's use kinds are consumable use kinds", (
			_all_in(MapObjects.HOUSE_USE_KINDS, ContentIds.CONSUMABLE_USE_KINDS)
			and _all_in(MapObjects.SHELF_USE_KINDS, ContentIds.CONSUMABLE_USE_KINDS)
	))
	var problems: PackedStringArray = []
	var houses: int = 0
	var books: int = 0
	var shelf_runes: Dictionary[String, bool] = {}
	for stream_seed: int in 400:
		for kind: MapLayout.ObjectKind in [CHEST, HOUSE, FOOD_SHELF, BOOK_SHELF, WEAPON_RACK]:
			var contents: Dictionary = MapObjects.roll(kind, RngStream.new(stream_seed), _catalog)
			var id: String = contents.get(MapObjects.CONTENTS_ID_KEY, "")
			if kind == BOOK_SHELF:
				books += 1 if _catalog.rune(id) != null else 0
				shelf_runes[id] = true
				continue
			if kind == HOUSE and contents.get("kind") == "gold":
				continue
			houses += 1 if kind == HOUSE else 0
			var item: ItemDefinition = _catalog.item(id)
			if item == null or not Prices.is_sellable(item.rarity):
				problems.append("%s: %s" % [MapLayout.ObjectKind.find_key(kind), contents])
				continue
			var fits: bool = false
			match kind:
				CHEST:
					fits = (
							(item is WeaponDefinition or item is EquipmentDefinition
							or item is TrinketDefinition)
							and MapObjects.CHEST_RARITIES[item.rarity - 1] == contents["rarity"]
					)
				HOUSE:
					fits = MapObjects.HOUSE_USE_KINDS.has((item as ConsumableDefinition).use_kind)
				FOOD_SHELF:
					fits = (item as ConsumableDefinition).use_kind == "ingredient"
				WEAPON_RACK:
					fits = item is WeaponDefinition
			if not fits:
				problems.append("%s: %s" % [MapLayout.ObjectKind.find_key(kind), id])
	_check("contents: chests hold a weapon, equipment or trinket of their rarity; houses a potion, "
			+ "key, lockpick or stat booster; shelves an ingredient; racks a weapon; all sold", (
			problems.is_empty() and houses > 0
	), ", ".join(problems))
	_check("contents: every book shelf names a catalog rune, and over 400 every one of them", (
			books == 400
			and shelf_runes.size() == _catalog.all_of(EffectCatalog.Kind.RUNE).size()
	), ", ".join(PackedStringArray(shelf_runes.keys())))


func _test_house_odds() -> void:
	var counts: Dictionary[int, int] = {}
	var items: int = 0
	var seed_number: int = 0
	while items < DRAWS:
		var contents: Dictionary = MapObjects.roll(HOUSE, RngStream.new(seed_number), _catalog)
		seed_number += 1
		if not contents.has(MapObjects.CONTENTS_ID_KEY):
			continue
		var id: String = contents[MapObjects.CONTENTS_ID_KEY]
		var rarity: int = _catalog.item(id).rarity
		counts[rarity] = counts.get(rarity, 0) + 1
		items += 1
	_check("contents: a house's consumable is Common 37 / Uncommon 8 / Rare 3 (of 48)", (
			_near((counts.get(COMMON, 0) as int), DRAWS, 3700.0 / 48.0)
			and _near((counts.get(UNCOMMON, 0) as int), DRAWS, 800.0 / 48.0)
			and _near((counts.get(RARE, 0) as int), DRAWS, 300.0 / 48.0)
	), str(counts))


# The item is drawn after the gold and rarity, so those match a roll with no catalog.
func _test_contents_keep_their_draws() -> void:
	var same: bool = true
	for stream_seed: int in 200:
		for kind: MapLayout.ObjectKind in [CHEST, HOUSE, FOOD_SHELF, BOOK_SHELF, WEAPON_RACK]:
			var bare: Dictionary = MapObjects.roll(kind, RngStream.new(stream_seed))
			var full: Dictionary = MapObjects.roll(kind, RngStream.new(stream_seed), _catalog)
			full.erase(MapObjects.CONTENTS_ID_KEY)
			same = same and bare == full and not bare.has(MapObjects.CONTENTS_ID_KEY)
	_check("contents: the catalog adds the item and changes no gold or rarity", same)


func _test_contents_seeded() -> void:
	var parts: PackedStringArray = []
	for stream_seed: int in [1, 2, 3]:
		for kind: MapLayout.ObjectKind in [CHEST, HOUSE, FOOD_SHELF, WEAPON_RACK]:
			var contents: Dictionary = MapObjects.roll(kind, RngStream.new(stream_seed), _catalog)
			parts.append(str(contents.get(MapObjects.CONTENTS_ID_KEY, contents.get("amount", ""))))
	_check("contents: streams 1 to 3's chests, houses, shelves and racks are pinned", (
			",".join(parts) == GOLDEN_CONTENTS
	), ",".join(parts))


func _kind_for(draw: int) -> EffectCatalog.Kind:
	var kinds: Array[EffectCatalog.Kind] = [
		EffectCatalog.Kind.WEAPON,
		EffectCatalog.Kind.EQUIPMENT,
		EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]
	return kinds[draw % kinds.size()]


func _index_of(definitions: Array[Resource]) -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	for definition: Resource in definitions:
		index.add("res://fixture/%s.tres" % [EffectCatalog.id_of(definition)], definition)
	index.finish()
	return index


func _prefix(id: String, tier: int) -> UnitPrefixDefinition:
	var prefix: UnitPrefixDefinition = UnitPrefixDefinition.new()
	prefix.id = id
	prefix.display_name = id.capitalize()
	prefix.tier = tier
	return prefix


func _rune(id: String) -> RuneDefinition:
	var rune: RuneDefinition = RuneDefinition.new()
	rune.id = id
	rune.display_name = id.capitalize()
	return rune


func _item(id: String, rarity: ItemDefinition.Rarity) -> ItemDefinition:
	var item: TrinketDefinition = TrinketDefinition.new()
	item.id = id
	item.rarity = rarity
	return item


func _weapon(id: String, weapon_type: String) -> ItemDefinition:
	var weapon: WeaponDefinition = WeaponDefinition.new()
	weapon.id = id
	weapon.rarity = COMMON
	weapon.weapon_type = weapon_type
	return weapon


func _all_in(values: PackedStringArray, allowed: PackedStringArray) -> bool:
	for value: String in values:
		if not allowed.has(value):
			return false
	return true


func _shown(prefix_id: String) -> String:
	return "none" if prefix_id.is_empty() else prefix_id


func _near(count: int, total: int, percent: float) -> bool:
	return absf(float(count) / float(total) - percent / 100.0) <= TOLERANCE


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
