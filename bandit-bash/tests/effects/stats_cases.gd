# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stats_cases.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

extends "res://tests/effects/golden_cases.gd"
## The stats(unit_id) read API's cases, for tests/effects/run_all.gd: cached sheets, fact-driven
## invalidation, cached values equal to a fresh computation after every kind of change, verify
## mode, and sandboxes copying the cached sheets. Shares the helpers of golden_cases.gd.

const HIT: int = CombatValue.Key.HIT


func run() -> void:
	_test_verify_on_in_this_build()
	_test_sheets_are_cached()
	_test_invalidating_facts()
	_test_cached_equals_fresh()
	_test_transfer_between_sessions()
	_test_verify_catches_a_stale_sheet()
	_test_sandbox_copies_sheets()
	_test_defeated_unit_goes_dormant()
	_test_weapon_swap_moves_effects()
	_test_sandbox_swap_stays_in_the_sandbox()


func _test_verify_on_in_this_build() -> void:
	var engine: EffectEngine = _battle(["p1"])
	_ok(
			"verify: on in debug builds, so the whole suite runs with it",
			OS.is_debug_build() and engine.verify
	)


func _test_sheets_are_cached() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var first: StatSheet = engine.stats("p1")
	var enemy: StatSheet = engine.stats("e1")
	_ok("cache: a second read returns the cached sheet", engine.stats("p1") == first)
	engine.set_base("p1", HIT, 90.0)
	var rebuilt: StatSheet = engine.stats("p1")
	_ok(
			"cache: a base change rebuilds it on the next read",
			rebuilt != first and rebuilt.get_value(HIT) == 90.0
	)
	_ok("cache: other subjects keep theirs", engine.stats("e1") == enemy)
	_clean("cache", engine)


func _test_invalidating_facts() -> void:
	var dropped: PackedStringArray = []
	var kinds: Array[CombatFact.Kind] = [
		CombatFact.Kind.WEAPON_SWAPPED,
		CombatFact.Kind.STAT_CHANGED,
		CombatFact.Kind.MODIFIER_GAINED,
		CombatFact.Kind.MODIFIER_EXPIRED,
		CombatFact.Kind.UNIT_SPAWNED,
	]
	for kind: CombatFact.Kind in kinds:
		var engine: EffectEngine = _battle(["p1", "e1"])
		var cached: StatSheet = engine.stats("p1")
		var other: StatSheet = engine.stats("e1")
		engine.record(CombatFact.new(kind, "p1"))
		if engine.stats("p1") != cached and engine.stats("e1") == other:
			dropped.append(CombatFact.Kind.find_key(kind) as String)
	_ok(
			"invalidation: each input fact drops its actor's sheet only",
			dropped.size() == 5, str(dropped)
	)
	var steady: EffectEngine = _battle(["p1", "e1"])
	var kept: StatSheet = steady.stats("p1")
	steady.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))
	_ok("invalidation: other facts keep the cache", steady.stats("p1") == kept)


func _test_cached_equals_fresh() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var sights: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 5.0)]
	)
	var scope: EffectInstance = _instance(
			"effect:sights", sights, EffectOwner.for_item("item:sights", "p2", 0, PLAYER),
			Modifier.SourceKind.EQUIPMENT, "Sights"
	)
	engine.register(scope)
	var equip: Callable = func() -> void:
		engine.set_holder("item:sights", "p1")
	var delta: Callable = func() -> void:
		var booster: ChangeBaseStat = ChangeBaseStat.new()
		booster.key = CombatValue.Key.MGT
		booster.value = 1.0
		booster.apply(_context(engine, scope))
	var gain: Callable = func() -> void:
		var banner: EffectDefinition = _definition(
				EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 10.0)]
		)
		banner.scope = YOUR_UNIT
		engine.register(_instance("effect:banner", banner, _army(), HEIRLOOM, "Banner"))
	var loss: Callable = func() -> void:
		engine.unregister("effect:banner")
	var timed_gained: Callable = func() -> void:
		var end: AddTimedModifier.End = AddTimedModifier.End.THIS_EXCHANGE
		engine.add_timed_modifier("p1", _hit_bonus("war horn"), end, 0)
	var timed_expired: Callable = func() -> void:
		engine.reach_boundary(EffectEngine.Boundary.EXCHANGE_END)
	var steps: Dictionary[String, Callable] = {
		"equip": equip,
		"delta": delta,
		"gain": gain,
		"loss": loss,
		"timed gained": timed_gained,
		"timed expired": timed_expired,
	}
	var expected: Dictionary[String, float] = {
		"equip": 85.0, "delta": 85.0, "gain": 95.0, "loss": 85.0, "timed gained": 100.0,
		"timed expired": 85.0,
	}
	var wrong: PackedStringArray = []
	for name: String in steps:
		engine.stats("p1").get_value(HIT)
		engine.stats("p1").get_value(CombatValue.Key.MGT)
		steps[name].call()
		var cached: float = engine.stats("p1").get_value(HIT)
		var fresh: float = engine.fresh_stats("p1").get_value(HIT)
		var might: bool = (
				engine.stats("p1").get_value(CombatValue.Key.MGT)
				== engine.fresh_stats("p1").get_value(CombatValue.Key.MGT)
		)
		if cached != fresh or cached != expected[name] or not might:
			wrong.append("%s: cached %s, fresh %s" % [name, cached, fresh])
	_ok(
			"invalidation: after each change the cached value equals a fresh one",
			wrong.is_empty(), str(wrong)
	)
	_ok(
			"invalidation: the delta reached MGT",
			engine.stats("p1").get_value(CombatValue.Key.MGT) == 1.0
	)
	_clean("cached equals fresh", engine)


func _test_transfer_between_sessions() -> void:
	var from: EffectEngine = _battle(["p1", "e1"])
	var to: EffectEngine = _battle(["p1", "e2"])
	var counted: CounterCondition = CounterCondition.new()
	counted.count = 10
	var keen: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 5.0)]
	)
	var instance: EffectInstance = _instance("effect:keen", keen, _owner("p1"), TRAIT, "Keen")
	from.register(instance)
	instance.set_counter(EffectTerms.Lane.COMBAT, 3)
	var arriving: EffectDefinition = _definition(
			EffectTerms.Trigger.HIT_TAKEN, [counted], [_block(1.0)]
	)
	var bulwark: EffectInstance = _instance("effect:bw", arriving, _owner("p1"), TRAIT, "Bulwark")
	from.register(bulwark)
	bulwark.set_counter(EffectTerms.Lane.COMBAT, 7)
	_ok("transfer: read on the old map", from.stats("p1").get_value(HIT) == 85.0)
	to.stats("p1").get_value(HIT)
	for id: String in ["effect:keen", "effect:bw"]:
		to.register(from.unregister(id), true)
	to.record(CombatFact.new(CombatFact.Kind.UNIT_SPAWNED, "p1"))
	_ok(
			"transfer: the new map's cached value equals a fresh one, and both maps are current",
			to.stats("p1").get_value(HIT) == 85.0 and to.fresh_stats("p1").get_value(HIT) == 85.0
			and from.stats("p1").get_value(HIT) == 80.0
	)
	_ok(
			"transfer: the unit keeps its counters",
			bulwark.get_counter(EffectTerms.Lane.COMBAT) == 7
	)
	_clean("transfer (from)", from)
	_clean("transfer (to)", to)


func _test_verify_catches_a_stale_sheet() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var sights: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 5.0)]
	)
	var item: EffectInstance = _instance(
			"effect:sights",
			sights,
			EffectOwner.for_item("item:sights", "p2", 0, PLAYER),
			Modifier.SourceKind.EQUIPMENT,
			"Sights"
	)
	engine.register(item)
	engine.stats("p1").get_value(HIT)
	# A change behind the engine's back: no set_holder, no fact. Only verify mode can see it.
	item.owner.holder_id = "p1"
	engine.stats("p1")
	_ok(
			"verify: a cached read that differs from a fresh one is reported",
			engine.diagnostics.size() == 1 and engine.diagnostics[0].contains("out of date"),
			str(engine.diagnostics)
	)
	var quiet: EffectEngine = _battle(["p1", "p2", "e1"])
	quiet.verify = false
	var other: EffectInstance = item.copy()
	other.owner.holder_id = "p2"
	quiet.register(other)
	quiet.stats("p1")
	other.owner.holder_id = "p1"
	quiet.stats("p1")
	_ok("verify: off, the same read is trusted", quiet.diagnostics.is_empty())


func _test_sandbox_copies_sheets() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var cached: StatSheet = engine.stats("p1")
	var sandbox: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var copied: StatSheet = sandbox.engine.stats("p1")
	_ok(
			"sandbox sheets: copied, linked to the sandbox, with the same values",
			copied != cached and copied.get_value(HIT) == cached.get_value(HIT)
			and sandbox.engine.verify == engine.verify
	)
	sandbox.engine.set_base("p1", HIT, 10.0)
	_ok(
			"sandbox sheets: a change in the sandbox never reaches the real sheet",
			engine.stats("p1") == cached and cached.get_value(HIT) == 80.0
			and sandbox.engine.stats("p1").get_value(HIT) == 10.0
	)
	_clean("sandbox sheets", sandbox.engine)


func _test_defeated_unit_goes_dormant() -> void:
	var engine: EffectEngine = _battle(["p1", "p2", "e1"])
	var fake: FakeState = _fake(engine)
	var rally: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 10.0)]
	)
	rally.scope = YOUR_UNIT
	engine.register(_instance("effect:rally", rally, _owner("p1"), TRAIT, "Rally"))
	var banner: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 5.0)]
	)
	banner.scope = YOUR_UNIT
	engine.register(_instance("effect:banner", banner, _army(), HEIRLOOM, "Banner"))
	var third: CounterCondition = CounterCondition.new()
	third.count = 3
	var guard: EffectDefinition = _definition(
			EffectTerms.Trigger.HIT_TAKEN, [third], [_block(1.0)]
	)
	var counted: EffectInstance = _instance("effect:guard", guard, _owner("p1"), TRAIT, "Guard")
	engine.register(counted)
	_ok("dormant: the aura reaches an ally", engine.stats("p2").get_value(HIT) == 95.0)
	engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))
	engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))

	# Defeated behind the engine's back: no fact. The cached sheet must notice on its own.
	fake.unit("p1").defeated = true
	_ok(
			"dormant: a defeated unit's aura leaves the sheets; the army's stays",
			engine.stats("p2").get_value(HIT) == 85.0
	)
	var activations: int = _count(engine, CombatFact.Kind.EFFECT_ACTIVATED)
	engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))
	_ok(
			"dormant: it reacts to nothing and keeps its counters",
			_count(engine, CombatFact.Kind.EFFECT_ACTIVATED) == activations
			and counted.get_counter(EffectTerms.Lane.COMBAT) == 2
	)
	fake.unit("p1").defeated = false
	_ok("dormant: back on the map, it wakes", engine.stats("p2").get_value(HIT) == 95.0)
	_clean("dormant defeated unit", engine)


func _test_weapon_swap_moves_effects() -> void:
	var engine: EffectEngine = _swap_battle()
	var fake: FakeState = _fake(engine)
	_ok("weapons: only the equipped sword counts", engine.stats("p1").get_value(HIT) == 90.0)
	engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, "p1", "e1"))
	engine.drain()
	fake.unit("p1").weapon = "item:bow"
	var swapped: CombatFact = CombatFact.new(CombatFact.Kind.WEAPON_SWAPPED, "p1")
	swapped.item_id = "item:bow"
	engine.record(swapped)
	engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, "p1", "e1"))
	engine.drain()
	_ok(
			"weapons: a swap moves the effects to the bow",
			engine.stats("p1").get_value(HIT) == 100.0 and fake.unit("p1").block == 1
	)
	_clean("weapon swap", engine)


func _test_sandbox_swap_stays_in_the_sandbox() -> void:
	var engine: EffectEngine = _swap_battle()
	var cached: StatSheet = engine.stats("p1")
	var sandbox: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var branch: FakeState = sandbox.engine.state
	branch.unit("p1").weapon = "item:bow"
	var swapped: CombatFact = CombatFact.new(CombatFact.Kind.WEAPON_SWAPPED, "p1")
	swapped.item_id = "item:bow"
	sandbox.engine.record(swapped)
	_ok(
			"weapons: the branch swapped to the bow",
			sandbox.engine.stats("p1").get_value(HIT) == 100.0
	)
	_ok(
			"weapons: the real state's effects are as they were",
			_fake(engine).unit("p1").weapon == "item:sword" and engine.stats("p1") == cached
			and cached.get_value(HIT) == 90.0
	)
	_clean("sandbox swap", sandbox.engine)


# p1 holds a sword (+10 Hit, "Attack made: gain 1 Block") in its Weapon slot and a stowed bow
# (+20 Hit).
func _swap_battle() -> EffectEngine:
	var engine: EffectEngine = _battle(["p1", "e1"])
	_fake(engine).unit("p1").weapon = "item:sword"
	var sword: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 10.0)]
	)
	var sword_guard: EffectDefinition = _definition(
			EffectTerms.Trigger.ATTACK_MADE, [], [_block(1.0)]
	)
	var bow: EffectDefinition = _definition(
			EffectTerms.Trigger.ALWAYS, [], [_modify_value(HIT, ADD, 20.0)]
	)
	var weapon: Modifier.SourceKind = Modifier.SourceKind.WEAPON
	engine.register(_instance("effect:sword", sword, _p1_item("item:sword"), weapon, "Sword"))
	engine.register(
			_instance("effect:guard", sword_guard, _p1_item("item:sword"), weapon, "Sword")
	)
	engine.register(_instance("effect:bow", bow, _p1_item("item:bow"), weapon, "Bow"))
	return engine
