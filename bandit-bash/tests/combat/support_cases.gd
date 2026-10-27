# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     support_cases.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

extends RefCounted
## Support action cases for tests/combat/run_all.gd: golden fact logs for each staff kind, each
## Pouch item kind, a Sidearm swap, runes (Mend, Aegis, Shatter, Recall) and Wait, their legality,
## and per-map uses refilling between two battles while total uses don't.
##
## Item and rune effects are fixtures built from the effect blocks, with the values of items.md and
## weapons.md. Every scenario also asserts that the engine reported no diagnostics.

const CombatWorld: GDScript = preload("res://tests/combat/combat_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const POUCH: Modifier.SourceKind = Modifier.SourceKind.POUCH_ITEM
const WEAPON: Modifier.SourceKind = Modifier.SourceKind.WEAPON
const COMBAT_LANE: EffectDefinition.Lane = EffectDefinition.Lane.COMBAT
const CAMPAIGN_LANE: EffectDefinition.Lane = EffectDefinition.Lane.CAMPAIGN

# The seed of every scenario's stream.
const SEED: int = 20261027

# p1 and p2 (seat 0) side by side, e1 next to p2; Might 3 and Constitution 20 for everyone.
const BASES: Dictionary = {
	CombatValue.Key.MGT: 3.0,
	CombatValue.Key.SPD: 5.0,
	CombatValue.Key.DEF: 2.0,
	CombatValue.Key.CON: 20.0,
}

# Reviewed golden fact logs, one CombatFact.to_log_line() per fact, by fixture name.
const GOLDEN: Dictionary[String, Array] = {
	"block staff": [
		"s0#1 BLOCK_GAINED p1 <- p2 amount 6 (hp 0, block 6)",
		"s0#2 USED_STAFF_ON_ALLY p2 -> p1",
	],
	"heal staff": [
		"s0#1 HEALED_AN_ALLY p2 -> p1 amount 8 (hp 5, block 0)",
		"s0#2 HEALED p1 <- p2 amount 8 (hp 5, block 0)",
		"s0#3 EFFECT_ACTIVATED p2 effect effect:heal_uses",
		"s0#4 USED_STAFF_ON_ALLY p2 -> p1",
	],
	"attack staff": [
		"s0#1 EFFECT_ACTIVATED p2 effect effect:harm_uses",
		"s0#2 BEFORE_COMBAT p2 -> e1",
		"s0#3 BEFORE_COMBAT e1 -> p2",
		"s0#4 ATTACK_MADE p2 -> e1",
		"s0#5 HIT_DEALT p2 -> e1 amount 18 type magic",
		"s0#6 HIT_TAKEN e1 <- p2 amount 18 type magic",
		"s0#7 DAMAGE_DEALT p2 -> e1 amount 18 (hp 18, block 0) source attack type magic",
		"s0#8 DAMAGE_TAKEN e1 <- p2 amount 18 (hp 18, block 0) source attack type magic",
		"s0#9 STANCE_CHANGED e1 -> p2 amount -1",
		"s0#10 AFTER_COMBAT p2 -> e1",
		"s0#11 AFTER_COMBAT e1 -> p2",
	],
	"potion": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:item:potion",
		"s0#2 ITEM_USED p1 -> p1 item item:potion",
		"s0#3 HEALED p1 amount 8 (hp 8, block 0) source effect effect effect:item:potion",
	],
	"guard tonic": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:item:tonic",
		"s0#2 ITEM_USED p1 -> p2 item item:tonic",
		(
			"s0#3 BLOCK_GAINED p2 <- p1 amount 6 (hp 0, block 6) source effect"
			+ " effect effect:item:tonic"
		),
	],
	"elixir": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:item:elixir",
		"s0#2 ITEM_USED p1 -> p2 item item:elixir",
		(
			"s0#3 HEALED_AN_ALLY p1 -> p2 amount 20 (hp 19, block 0) source effect"
			+ " effect effect:item:elixir"
		),
		"s0#4 HEALED p2 <- p1 amount 20 (hp 19, block 0) source effect effect effect:item:elixir",
	],
	"stat booster": [
		"s0#1 EFFECT_ACTIVATED p1 effect effect:item:draught",
		"s0#2 ITEM_USED p1 -> p1 item item:draught",
		"s0#3 STAT_CHANGED p1 stat 1 amount 1 source effect effect effect:item:draught",
	],
	"sidearm swap": [
		"s0#1 WEAPON_SWAPPED p2 item w:axe",
		"s0#2 BEFORE_COMBAT p2 -> e1",
		"s0#3 BEFORE_COMBAT e1 -> p2",
		"s0#4 ATTACK_MADE p2 -> e1",
		"s0#5 HIT_DEALT p2 -> e1 amount 11 type physical",
		"s0#6 HIT_TAKEN e1 <- p2 amount 11 type physical",
		"s0#7 DAMAGE_DEALT p2 -> e1 amount 11 (hp 11, block 0) source attack type physical",
		"s0#8 DAMAGE_TAKEN e1 <- p2 amount 11 (hp 11, block 0) source attack type physical",
		"s0#9 STANCE_CHANGED e1 -> p2 amount -1",
		"s0#10 AFTER_COMBAT p2 -> e1",
		"s0#11 AFTER_COMBAT e1 -> p2",
	],
	"weapon swap as the action": [
		"s0#1 WEAPON_SWAPPED p1 item w:bow",
	],
	"runes": [
		"s0#1 EFFECT_ACTIVATED effect effect:rune:mend",
		"s0#2 RUNE_USED -> p2 item rune:mend tile (2, 1)",
		"s0#3 HEALED p2 amount 10 (hp 10, block 0) source effect effect effect:rune:mend",
		"s0#4 EFFECT_ACTIVATED effect effect:rune:aegis",
		"s0#5 RUNE_USED -> p1 item rune:aegis tile (1, 1)",
		"s0#6 BLOCK_GAINED p1 amount 6 (hp 0, block 6) source effect effect effect:rune:aegis",
		"s0#7 EFFECT_ACTIVATED effect effect:rune:shatter",
		"s0#8 RUNE_USED -> e1 item rune:shatter tile (3, 1)",
		"s0#9 STANCE_CHANGED e1 amount -2 source effect effect effect:rune:shatter",
		"s0#10 EXPOSED e1 effect effect:rune:shatter",
	],
	"recall": [
		"s0#1 UNIT_MOVED p1 tile (2, 1)",
		"s0#2 UNIT_MOVED p2 tile (1, 1)",
		"s0#3 RUNE_USED -> p1 item rune:recall tile (2, 1)",
	],
	"wait": [
		"s0#1 UNIT_WAITED p1",
	],
}

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_block_staff()
	_test_heal_staff()
	_test_attack_staff()
	_test_potion()
	_test_guard_tonic()
	_test_elixir()
	_test_stat_booster()
	_test_item_legality()
	_test_sidearm_swap()
	_test_swap_as_action()
	_test_runes()
	_test_recall()
	_test_wait()
	_test_uses_between_battles()


func _test_block_staff() -> void:
	var world: Variant = _team()
	world.arm("p2", world.add_weapon("w:shelter", "shelter").id)
	_same("block staff: legal", _staff_reason(world, "p2", "p1"), "")
	var result: StaffResolver.Result = _staff(world, "p2", "p1")
	_ok("block staff: 3 + Might 3", result.amount == 6 and world.state.get_block("p1") == 6)
	_ok("block staff: the user acted", world.state.unit("p2").has_acted)
	_same("block staff: unlimited uses", _staff_reason(world, "p2", "p1"), "")
	_same("block staff: not on a foe", _staff_reason(world, "p2", "e1"), "not an ally")
	_golden("block staff", world)


func _test_heal_staff() -> void:
	var world: Variant = _team()
	world.arm("p2", world.add_weapon("w:heal", "minor_heal").id)
	world.add_effect("effect:heal_uses", _uses(3, COMBAT_LANE), "p2", WEAPON, "w:heal")
	_same("heal staff: not on a full ally", _staff_reason(world, "p2", "p1"), "not damaged")
	world.state.set_hp("p1", 15)
	var result: StaffResolver.Result = _staff(world, "p2", "p1")
	_ok("heal staff: 5 + Might 3, capped at maximum HP", result.amount == 5)
	_ok("heal staff: back to full", world.state.get_hp("p1") == 20)
	_golden("heal staff", world)
	for i: int in 2:
		world.state.set_hp("p1", 10)
		_staff(world, "p2", "p1")
	world.state.set_hp("p1", 10)
	_same("heal staff: 3 per map", _staff_reason(world, "p2", "p1"), "no uses left")
	_quiet(world)


func _test_attack_staff() -> void:
	var world: Variant = _team()
	world.arm("p2", world.add_weapon("w:harm", "harm").id)
	world.add_effect("effect:harm_uses", _uses(2, COMBAT_LANE), "p2", WEAPON, "w:harm")
	world.state.set_hp("e1", 60)
	world.engine.set_base("e1", CombatValue.Key.HP, 60.0)
	var result: ExchangeResolver.Result = _attack(world, "p2", "e1")
	_ok("attack staff: an ordinary attack", result.is_legal and not result.can_counter)
	_ok("attack staff: 15 + Might 3, Magic against RES 0", world.state.get_hp("e1") == 42)
	_golden("attack staff", world)
	_attack(world, "p2", "e1")
	_same(
			"attack staff: 2 per map",
			ExchangeResolver.check(world.engine, world.state, "p2", "e1"),
			"no uses left"
	)
	_quiet(world)


func _test_potion() -> void:
	var world: Variant = _team()
	_give(world, "p1", "item:potion", _heal_item(8.0, 1, COMBAT_LANE))
	world.state.set_hp("p1", 5)
	var result: ItemUseResolver.Result = _use(world, "p1", "p1", "item:potion")
	_ok("potion: heals 8 on itself", result.is_legal and world.state.get_hp("p1") == 13)
	_ok("potion: stays in the Pouch", not result.is_consumed)
	_golden("potion", world)
	world.state.unit("p1").has_acted = false
	_same("potion: 1 per map", _use_reason(world, "p1", "p1", "item:potion"), "no uses left")


func _test_guard_tonic() -> void:
	var world: Variant = _team()
	_give(world, "p1", "item:tonic", _block_item(6.0, 1, COMBAT_LANE))
	_use(world, "p1", "p2", "item:tonic")
	_ok("guard tonic: an adjacent ally gains 6 Block", world.state.get_block("p2") == 6)
	_golden("guard tonic", world)


func _test_elixir() -> void:
	var world: Variant = _team()
	var full: StatOf = StatOf.new()
	full.key = CombatValue.Key.HP
	full.subject = CommandTarget.new()
	var heal: GainResource = GainResource.new()
	heal.pool = GainResource.Pool.HP
	heal.target = CommandTarget.new()
	heal.amount = full
	_give(world, "p1", "item:elixir", _item([heal], 1, CAMPAIGN_LANE))
	world.state.set_hp("p2", 1)
	var result: ItemUseResolver.Result = _use(world, "p1", "p2", "item:elixir")
	_ok("elixir: heals to full", world.state.get_hp("p2") == 20)
	_ok("elixir: used up", result.is_consumed and world.state.unit("p1").pouch_item_id.is_empty())
	_golden("elixir", world)


func _test_stat_booster() -> void:
	var world: Variant = _team()
	var boost: ChangeBaseStat = ChangeBaseStat.new()
	boost.target = CommandTarget.new()
	boost.key = CombatValue.Key.MGT
	boost.value = 1.0
	_give(world, "p1", "item:draught", _item([boost], 1, CAMPAIGN_LANE))
	_use(world, "p1", "p1", "item:draught")
	_ok("booster: +1 Might for good", world.engine.stats("p1").get_int(CombatValue.Key.MGT) == 4)
	_ok(
			"booster: a sourced delta for the bridge",
			world.engine.get_deltas("p1", CombatValue.Key.MGT).size() == 1
	)
	_golden("stat booster", world)


func _test_item_legality() -> void:
	var world: Variant = _team()
	_give(world, "p1", "item:potion", _heal_item(8.0, 1, COMBAT_LANE))
	_same(
			"item: not in its Pouch",
			_use_reason(world, "p2", "p2", "item:potion"),
			"not in its Pouch"
	)
	world.state.move_unit("p2", Vector2i(5, 5))
	_same("item: an ally too far", _use_reason(world, "p1", "p2", "item:potion"), "not adjacent")
	world.state.move_unit("e1", Vector2i(1, 2))
	_same("item: never on a foe", _use_reason(world, "p1", "e1", "item:potion"), "not an ally")
	var trinket: Variant = _team()
	_give(trinket, "p1", "item:ring", _always_item(CombatValue.Key.HIT, 5.0))
	_same(
			"item: a trinket has nothing to use",
			_use_reason(trinket, "p1", "p1", "item:ring"),
			"nothing to use"
	)
	_ok("item: refusals record nothing", world.engine.fact_log.is_empty())
	_quiet(world)
	_quiet(trinket)


func _test_sidearm_swap() -> void:
	var world: Variant = _team()
	world.add_weapon("w:sword", "sword")
	world.add_weapon("w:axe", "axe")
	world.arm("p2", "w:sword", "w:axe")
	world.add_effect("effect:sidearm", _sidearm(), "p2")
	var sword_hit: int = world.engine.stats("p2").get_int(CombatValue.Key.HIT)
	_ok("sidearm: Hit 80 with the sword", sword_hit == 80)
	_same("sidearm: a free swap", _swap(world, "p2", true), "")
	_ok("sidearm: holds the axe", world.state.equipped_weapon_id("p2") == "w:axe")
	_ok("sidearm: Hit 65 with the axe", world.engine.stats("p2").get_int(CombatValue.Key.HIT) == 65)
	_ok("sidearm: hasn't acted", not world.state.unit("p2").has_acted)
	_same("sidearm: once per turn", _swap(world, "p2", true), "Sidearm already used this turn")
	# A sure hit, so the attack shows the axe's damage.
	world.add_effect("effect:sure", _always_item(CombatValue.Key.HIT, 35.0), "p2")
	_attack(world, "p2", "e1")
	_ok("sidearm: then attacks with the axe", _last_attack_amount(world) == 10 + 3 - 2)
	_golden("sidearm swap", world)


func _test_swap_as_action() -> void:
	var world: Variant = _team()
	world.add_weapon("w:sword", "sword")
	world.add_weapon("w:bow", "bow")
	world.arm("p1", "w:sword", "w:bow")
	_same("swap: no free swap without Sidearm", _swap(world, "p1", true), "no Sidearm")
	_same("swap: as the action", _swap(world, "p1", false), "")
	_ok("swap: ends the turn", world.state.unit("p1").has_acted)
	_ok(
			"swap: the bow's range now",
			world.engine.stats("p1").get_int(CombatValue.Key.RANGE_MAX) == 3
	)
	_same("swap: not twice", _swap(world, "p1", false), "already acted")
	var bare: Variant = _team()
	_same("swap: nothing stowed", _swap(bare, "p1", false), "no stowed weapon")
	_golden("weapon swap as the action", world)


func _test_runes() -> void:
	var world: Variant = _team()
	var mend: EffectInstance = _rune(world, "rune:mend", _rune_gain(GainResource.Pool.HP, 10.0))
	var aegis: EffectInstance = _rune(world, "rune:aegis", _rune_gain(GainResource.Pool.BLOCK, 6.0))
	var shatter: EffectInstance = _rune(
			world, "rune:shatter", _rune_gain(GainResource.Pool.STANCE, -2.0)
	)
	world.state.set_hp("p2", 5)
	_same("rune: Mend", RuneResolver.cast(world.engine, world.state, 0, mend, "p2"), "")
	_ok("rune: Mend heals 10", world.state.get_hp("p2") == 15)
	_same("rune: Aegis", RuneResolver.cast(world.engine, world.state, 0, aegis, "p1"), "")
	_ok("rune: Aegis gives 6 Block", world.state.get_block("p1") == 6)
	_same("rune: Shatter", RuneResolver.cast(world.engine, world.state, 0, shatter, "e1"), "")
	_ok("rune: Shatter Exposes", world.state.get_stance("e1") == 0)
	_ok("rune: the slots empty", world.state.rune_slots[0].is_empty())
	_ok("rune: outside the action economy", not world.state.unit("p1").has_acted)
	_same(
			"rune: single use",
			RuneResolver.cast(world.engine, world.state, 0, mend, "p2"),
			"not in the seat's rune slots"
	)
	_golden("runes", world)


func _test_recall() -> void:
	var world: Variant = _team()
	world.state.rune_slots[0] = PackedStringArray(["rune:recall", "rune:recall2"])
	_same(
			"recall: swaps two of the seat's units",
			RuneResolver.recall(world.engine, world.state, 0, "rune:recall", "p1", "p2"),
			""
	)
	_ok(
			"recall: tiles swapped",
			world.state.tile_of("p1") == Vector2i(2, 1)
			and world.state.tile_of("p2") == Vector2i(1, 1)
	)
	_ok("recall: neither unit's move", world.state.tiles_moved("p1") == 0)
	_golden("recall", world)

	# p2, a flier, now stands on water p1 can't stand on.
	world.grid.forbid(Vector2i(1, 1), CombatGrid.MovementType.DEFAULT)
	world.state.unit("p2").movement_type = CombatGrid.MovementType.FLIER
	var start: int = world.engine.fact_log.size()
	_same(
			"recall: refused when a unit can't stand on the other's tile",
			RuneResolver.recall(world.engine, world.state, 0, "rune:recall2", "p1", "p2"),
			"a unit can't stand on the other's tile"
	)
	_ok("recall: a refusal records nothing", world.engine.fact_log.size() == start)
	_same(
			"recall: not an enemy",
			RuneResolver.recall(world.engine, world.state, 0, "rune:recall2", "p1", "e1"),
			"not two of the seat's units"
	)
	_quiet(world)


func _test_wait() -> void:
	var world: Variant = _team()
	_ok("wait: ends the turn", world.state.wait(world.engine, "p1"))
	_ok("wait: acted", world.state.unit("p1").has_acted)
	_ok("wait: not twice", not world.state.wait(world.engine, "p1"))
	_golden("wait", world)


func _test_uses_between_battles() -> void:
	var staff_uses: EffectInstance = null
	var potion_uses: EffectInstance = null
	var elixir_uses: EffectInstance = null
	for battle: int in 2:
		var world: Variant = _team()
		world.arm("p2", world.add_weapon("w:heal", "minor_heal").id)
		if staff_uses == null:
			staff_uses = world.add_effect(
					"effect:heal_uses", _uses(3, COMBAT_LANE), "p2", WEAPON, "w:heal"
			)
			potion_uses = _give(world, "p1", "item:potion", _heal_item(8.0, 1, COMBAT_LANE))
			elixir_uses = _give(world, "p1", "item:elixir", _heal_item(20.0, 1, CAMPAIGN_LANE))
			world.state.unit("p1").pouch_item_id = "item:potion"
		else:
			# The same instances move into the next battle with their items.
			world.engine.register(staff_uses)
			world.engine.register(potion_uses)
			world.engine.register(elixir_uses)
			world.state.unit("p1").pouch_item_id = "item:potion"
		_ok(
				"uses: battle %d starts with 3 staff uses" % [battle + 1],
				staff_uses.charges_left == 3
		)
		_ok(
				"uses: battle %d starts with its potion use" % [battle + 1],
				potion_uses.charges_left == 1
		)
		if battle == 0:
			for i: int in 3:
				world.state.set_hp("p1", 10)
				world.state.unit("p2").has_acted = false
				_staff(world, "p2", "p1")
			world.state.set_hp("p1", 10)
			_use(world, "p1", "p1", "item:potion")
			world.state.unit("p1").pouch_item_id = "item:elixir"
			world.state.unit("p1").has_acted = false
			_use(world, "p1", "p1", "item:elixir")
			_ok("uses: battle 1 spends them all", not staff_uses.has_charge())
		else:
			_ok("uses: the Elixir stays spent", elixir_uses.charges_left == 0)
		_quiet(world)


# p1 at (1, 1) and p2 at (2, 1) on seat 0, e1 at (3, 1); 20 HP and Stance 2 each. Rolls come from
# a seeded stream; a case that attacks makes its hits sure.
func _team() -> Variant:
	var world: Variant = CombatWorld.new(LiveRolls.new(RngStream.new(SEED)))
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1), BASES)
	world.add_unit("p2", PLAYER, 0, Vector2i(2, 1), BASES)
	world.add_unit("e1", ENEMY, -1, Vector2i(3, 1), BASES)
	return world


func _staff(world: Variant, user: String, target: String) -> StaffResolver.Result:
	world.engine.begin_step()
	return StaffResolver.resolve(world.engine, world.state, user, target)


func _staff_reason(world: Variant, user: String, target: String) -> String:
	return StaffResolver.check(world.engine, world.state, user, target)


func _attack(world: Variant, attacker: String, defender: String) -> ExchangeResolver.Result:
	world.engine.begin_step()
	return ExchangeResolver.resolve(world.engine, world.state, attacker, defender)


func _use(world: Variant, user: String, target: String, item: String) -> ItemUseResolver.Result:
	world.engine.begin_step()
	return ItemUseResolver.resolve(world.engine, world.state, user, target, item)


func _use_reason(world: Variant, user: String, target: String, item: String) -> String:
	return ItemUseResolver.check(world.engine, world.state, user, target, item)


func _swap(world: Variant, unit_id: String, is_free: bool) -> String:
	world.engine.begin_step()
	return WeaponSwap.resolve(world.engine, world.state, unit_id, is_free)


# Puts item_id in unit_id's Pouch with definition as its use effect; returns the instance.
func _give(
		world: Variant, unit_id: String, item_id: String, definition: EffectDefinition
) -> EffectInstance:
	world.state.unit(unit_id).pouch_item_id = item_id
	return world.add_effect("effect:" + item_id, definition, unit_id, POUCH, item_id)


# A rune in seat 0's slots, with definition as its effect.
func _rune(world: Variant, rune_id: String, definition: EffectDefinition) -> EffectInstance:
	if not world.state.rune_slots.has(0):
		world.state.rune_slots[0] = PackedStringArray()
	world.state.rune_slots[0].append(rune_id)
	var owner: EffectOwner = EffectOwner.for_rune(rune_id, 0)
	var instance: EffectInstance = EffectInstance.new(
			"effect:" + rune_id, definition, owner, Modifier.SourceKind.RUNE, rune_id
	)
	world.engine.register(instance)
	return instance


# A use-only effect: its charges count a staff's uses.
func _uses(charges: int, lane: EffectDefinition.Lane) -> EffectDefinition:
	return _item([], charges, lane)


func _heal_item(amount: float, charges: int, lane: EffectDefinition.Lane) -> EffectDefinition:
	return _item([_gain_to_target(GainResource.Pool.HP, amount)], charges, lane)


func _block_item(amount: float, charges: int, lane: EffectDefinition.Lane) -> EffectDefinition:
	return _item([_gain_to_target(GainResource.Pool.BLOCK, amount)], charges, lane)


func _rune_gain(pool: GainResource.Pool, amount: float) -> EffectDefinition:
	return _item([_gain_to_target(pool, amount)], 0, COMBAT_LANE)


func _gain_to_target(pool: GainResource.Pool, amount: float) -> GainResource:
	var constant: Constant = Constant.new()
	constant.value = amount
	var gain: GainResource = GainResource.new()
	gain.pool = pool
	gain.target = CommandTarget.new()
	gain.amount = constant
	return gain


func _item(operations: Array, charges: int, lane: EffectDefinition.Lane) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.operations.assign(operations)
	definition.charges = charges
	definition.charge_lane = lane
	return definition


func _always_item(key: int, value: float) -> EffectDefinition:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = Modifier.Mode.ADD
	modify.value = value
	return _item([modify], 0, COMBAT_LANE)


# Sidearm: always allowed a free weapon swap.
func _sidearm() -> EffectDefinition:
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	return _item([grant], 0, COMBAT_LANE)


func _last_attack_amount(world: Variant) -> int:
	var engine: EffectEngine = world.engine
	for fact: CombatFact in engine.fact_log:
		if fact.kind == CombatFact.Kind.HIT_DEALT:
			return fact.amount
	return -1


# Compares the log from start on with GOLDEN[name]; on a mismatch prints the actual log as a
# GDScript array for review. Also checks the engine reported no diagnostics.
func _golden(name: String, world: Variant, start: int = 0) -> void:
	var lines: Array[String] = world.log_lines(start)
	var expected: Array = GOLDEN.get(name, [])
	var same: bool = lines.size() == expected.size()
	for i: int in mini(lines.size(), expected.size()):
		same = same and lines[i] == expected[i]
	if not same:
		var listing: PackedStringArray = []
		for line: String in lines:
			listing.append("\t\t\"%s\"," % [line])
		print("GOLDEN \"%s\": [\n%s\n\t]," % [name, "\n".join(listing)])
	_ok("golden: %s" % [name], same)
	_quiet(world)


func _quiet(world: Variant) -> void:
	var engine: EffectEngine = world.engine
	_ok("diagnostics: none", engine.diagnostics.is_empty(), str(engine.diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
