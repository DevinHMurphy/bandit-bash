# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     engine_cases.gd
# Author:
# Created:  October 26, 2026
# Modified: October 28, 2026
# ==============================================================================

extends RefCounted
## The effect engine's cases for tests/effects/run_all.gd: base stat keys and per-stat modifiers,
## the F4 blocks, registration and indexes, scope, dispatch and reaction order, and every block's
## runtime method ([method EffectCondition.test], [method TargetSelector.select],
## [method ValueSource.evaluate], [method EffectOperation.apply]).
##
## Runs on the test-only [code]fake_state.gd[/code] map, so no combat rules are involved. Reports
## each case through the check callable it is given.

# A preloaded script used as a type (gdscript.md, Naming): the fake state has no class name.
const FakeState = preload("res://tests/effects/harness/fake_state.gd")

# Short names for the sides and modes, to keep the cases readable.
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const OBJECT_SIDE: CombatFact.CombatSide = CombatFact.CombatSide.NONE
const ADD: Modifier.Mode = Modifier.Mode.ADD
const MULTIPLY: Modifier.Mode = Modifier.Mode.MULTIPLY
const THIS_UNIT: EffectDefinition.Scope = EffectDefinition.Scope.THIS_UNIT
const YOUR_UNIT: EffectDefinition.Scope = EffectDefinition.Scope.YOUR_UNIT
const ANY_ALLY_UNIT: EffectDefinition.Scope = EffectDefinition.Scope.ANY_ALLY_UNIT
const ANY_UNIT: EffectDefinition.Scope = EffectDefinition.Scope.ANY_UNIT
const TRAIT: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT
const ATTACKING: WhileAttackCondition.Role = WhileAttackCondition.Role.ATTACKING
const ATTACKED: WhileAttackCondition.Role = WhileAttackCondition.Role.ATTACKED

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_base_stat_keys()
	_test_per_stat_modifiers()
	_test_command_target_and_mend()
	_test_while_matchup()
	_test_while_attack()
	_test_extra_stance_loss()
	_test_registration_and_indexes()
	_test_scope()
	_test_dispatch_scope()
	_test_reaction_order()
	_test_counter_condition()
	_test_chance_condition()
	_test_while_conditions()
	_test_position_conditions()
	_test_selectors()
	_test_value_sources()
	_test_modify_that()
	_test_gain_resource_paths()
	_test_deal_splash()
	_test_change_base_stat()
	_test_always_on_modifiers()
	_test_add_timed_modifier()
	_test_content_errors()
	_test_queued_operations_wait()
	_test_window_releases_after_record()


func _test_base_stat_keys() -> void:
	var stats: PackedStringArray = ["HP", "MGT", "SPD", "DEF", "RES", "CON"]
	var appended: bool = true
	for i: int in stats.size():
		appended = appended and CombatValue.Key[stats[i]] == 16 + i
	_ok("f3: base stat keys appended after MOVEMENT", appended)
	_ok("f3: Stat enum has the seven stats", CombatValue.Stat.size() == 7)
	_ok(
			"f3: every stat has a key, MOV is MOVEMENT",
			CombatValue.STAT_KEYS.size() == 7
			and CombatValue.STAT_KEYS[CombatValue.Stat.MOV] == CombatValue.Key.MOVEMENT
			and CombatValue.STAT_KEYS[CombatValue.Stat.SPD] == CombatValue.Key.SPD
	)
	_same("f3: key name of a base stat", EffectDefinition.key_name(CombatValue.Key.SPD), "SPD")


func _test_per_stat_modifiers() -> void:
	var engine: EffectEngine = _world()
	var slower: ModifyValue = _modify_value(CombatValue.Key.SPD, ADD, -2.0)
	var no_speed: SetPermission = SetPermission.new()
	no_speed.permission = CampaignValue.Permission.STAT_CAN_GROW
	no_speed.allow = false
	no_speed.stat = CombatValue.Stat.SPD
	var more_might: ModifyValue = _modify_value(
			CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS, ADD, 1.0
	)
	more_might.stat = CombatValue.Stat.MGT
	var weights: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [slower, no_speed, more_might]
	)
	_same(
			"f3: Training Weights text names its stats",
			weights.describe(),
			"Always: -2 SPD, deny Stat Can Grow (SPD), +1 Level Up Guaranteed Gains (MGT)"
	)
	engine.set_base("p1", CombatValue.Key.SPD, 6.0)
	engine.register(_instance(
			"effect:tw", weights, EffectOwner.for_item("item:tw", "p1", 0, PLAYER),
			Modifier.SourceKind.EQUIPMENT
	))
	var sheet: StatSheet = engine.stats("p1")
	var gains: int = CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS
	var grow: int = CampaignValue.Permission.STAT_CAN_GROW
	_ok("f3: SPD -2 applies", sheet.get_value(CombatValue.Key.SPD) == 4.0)
	_ok(
			"f3: Speed can't grow, Might can",
			not sheet.is_allowed(grow, null, CombatValue.Stat.SPD)
			and sheet.is_allowed(grow, null, CombatValue.Stat.MGT)
	)
	_ok(
			"f3: guaranteed gain only for MGT",
			sheet.get_value(gains, null, CombatValue.Stat.MGT) == 1.0
			and sheet.get_value(gains, null, CombatValue.Stat.SPD) == 0.0
			and sheet.get_value(gains) == 0.0
	)
	_ok("f3: another unit keeps its Speed growth", engine.stats("p2").is_allowed(
			grow, null, CombatValue.Stat.SPD
	))


func _test_command_target_and_mend() -> void:
	var engine: EffectEngine = _world()
	_fake(engine).unit("p2").hp = 5
	var mend: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS,
			[],
			[_gain(GainResource.Pool.HP, CommandTarget.new(), _constant(10.0))]
	)
	_same("f4: Mend text", mend.describe(), "Always: heal the target for 10")

	var rune: EffectInstance = _instance(
			"effect:mend", mend, EffectOwner.for_rune("rune:1", 0), Modifier.SourceKind.RUNE
	)
	engine.register(rune)
	var ctx: EffectContext = EffectContext.new()
	ctx.command_target_id = "p2"
	_ok("f4: a command activates the rune", engine.activate(rune, ctx))
	engine.drain()
	_ok("f4: the command target was healed", _fake(engine).unit("p2").hp == 15)

	var empty: EffectContext = _context(engine, rune)
	_ok("f4: no command target selects nothing", CommandTarget.new().select(empty).is_empty())


func _test_while_matchup() -> void:
	var engine: EffectEngine = _world()
	var advantage: WhileMatchupCondition = WhileMatchupCondition.new()
	var ctx: EffectContext = _context(engine, null)
	ctx.attacker_id = "p1"
	ctx.defender_id = "e1"
	ctx.initiator_id = "p1"
	ctx.matchup = WhileMatchupCondition.Matchup.ADVANTAGE
	ctx.subject_id = "p1"
	_ok("f4: the attacker has Advantage", advantage.test(ctx))
	ctx.subject_id = "e1"
	_ok("f4: the defender's result is the mirror", not advantage.test(ctx))
	var disadvantage: WhileMatchupCondition = WhileMatchupCondition.new()
	disadvantage.matchup = WhileMatchupCondition.Matchup.DISADVANTAGE
	_ok("f4: the defender has Disadvantage", disadvantage.test(ctx))
	ctx.subject_id = "p2"
	_ok("f4: a unit outside the exchange has no matchup", not advantage.test(ctx))

	var professional: EffectDefinition = _definition(
			EffectDefinition.Trigger.BEFORE_COMBAT,
			[advantage],
			[_block(3.0)]
	)
	_same(
			"f4: Professional text (unit-roster.md wording)",
			professional.describe(),
			"Before Combat, while this unit has triangle Advantage: gain 3 Block"
	)


func _test_while_attack() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	fake.unit("e1").tags = PackedStringArray(["Beast"])
	fake.unit("e1").unit_type = "Wolf"
	fake.weapon_types["w:bow"] = "Bow"
	engine.set_base("p1", CombatValue.Key.DAMAGE_TYPE, CombatFact.DamageType.MAGIC)
	var ctx: EffectContext = _context(engine, null)
	ctx.attacker_id = "p1"
	ctx.defender_id = "e1"
	ctx.initiator_id = "p1"
	ctx.weapon_id = "w:bow"
	ctx.subject_id = "p1"
	var beasts: WhileAttackCondition = _attack(ATTACKING, WhileAttackCondition.Kind.OPPONENT_TAG)
	beasts.type_name = "Beast"
	_ok("attack: no attack in flight, no pass", not beasts.test(ctx))
	ctx.attack_index = 0
	_ok("attack: against a Beast", beasts.test(ctx))
	ctx.subject_id = "e1"
	_ok("attack: only from the attacking side", not beasts.test(ctx))
	ctx.subject_id = "p1"
	beasts.type_name = "Flier"
	_ok("attack: not against a Flier", not beasts.test(ctx))
	var wolves: WhileAttackCondition = _attack(
			ATTACKING, WhileAttackCondition.Kind.OPPONENT_UNIT_TYPE
	)
	wolves.type_name = "Wolf"
	_ok("attack: against a unit type", wolves.test(ctx))

	ctx.subject_id = "e1"
	var magic: WhileAttackCondition = _attack(ATTACKED, WhileAttackCondition.Kind.DAMAGE_TYPE)
	_ok("attack: attacked with magic (the attacker's damage type)", magic.test(ctx))
	magic.damage_type = CombatFact.DamageType.PHYSICAL
	_ok("attack: not with physical", not magic.test(ctx))
	var bows: WhileAttackCondition = _attack(ATTACKED, WhileAttackCondition.Kind.WEAPON_TYPE)
	bows.type_name = "Bow"
	_ok("attack: attacked with a bow", bows.test(ctx))
	ctx.weapon_id = "w:other"
	_ok("attack: not with another weapon", not bows.test(ctx))
	var crit: WhileAttackCondition = _attack(ATTACKED, WhileAttackCondition.Kind.IS_CRIT)
	_ok("attack: no crit", not crit.test(ctx))
	ctx.is_crit = true
	_ok("attack: crit", crit.test(ctx))
	var by_opponent: WhileAttackCondition = _attack(
			ATTACKED, WhileAttackCondition.Kind.OPPONENT_TAG
	)
	by_opponent.type_name = "Beast"
	_ok("attack: the opponent is the attacker when attacked", not by_opponent.test(ctx))
	ctx.attack_index = -1
	_ok("attack: before or after combat, no pass", not crit.test(ctx))


func _test_extra_stance_loss() -> void:
	var first: CounterCondition = CounterCondition.new()
	first.mode = CounterCondition.Mode.FIRST
	var breaker_loss: ModifyThat = _modify_that(ModifyThat.What.EXTRA_STANCE_LOSS, ADD, 1.0)
	var breaker: EffectDefinition = _definition(
			EffectDefinition.Trigger.HIT_DEALT, [first], [breaker_loss]
	)
	_same(
			"f4: Breaker text (unit-roster.md wording)",
			breaker.describe(),
			"First Hit dealt this combat: the target loses 1 extra Stance"
	)
	_same(
			"f4: extra Stance loss on a hit taken names the hit",
			breaker_loss.describe_for_trigger(EffectDefinition.Trigger.HIT_TAKEN),
			"+1 extra Stance loss for that hit"
	)

	var engine: EffectEngine = _world()
	var instance: EffectInstance = _instance(
			"effect:breaker", breaker, _owner("p1"), TRAIT
	)
	var ctx: EffectContext = _context(engine, instance)
	breaker_loss.apply(ctx)
	_modify_that(ModifyThat.What.EXTRA_STANCE_LOSS, ADD, 2.0).apply(ctx)
	_ok("f4: extra Stance losses add up", ctx.extra_stance_loss() == 3.0)
	_ok("f4: no extra loss by default", EffectContext.new().extra_stance_loss() == 0.0)


func _test_registration_and_indexes() -> void:
	var engine: EffectEngine = _world()
	var block: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START,
			[],
			[_block(1.0)]
	)
	var b: EffectInstance = _instance("effect:b", block, _owner("p2"), TRAIT)
	var a: EffectInstance = _instance("effect:a", block, _owner("p1"), TRAIT)
	engine.register(b)
	engine.register(a)
	_ok("index: instances listed by id", _ids(engine.get_instances()) == "effect:a,effect:b")
	engine.register(a)
	_ok("index: a second registration is refused", engine.diagnostics.size() == 1)

	engine.record(_phase_fact(PLAYER))
	engine.drain()
	_ok(
			"index: both phase effects fired",
			_fake(engine).unit("p1").block == 1 and _fake(engine).unit("p2").block == 1
	)
	_ok("index: unregister returns the instance", engine.unregister("effect:a") == a)
	engine.record(_phase_fact(PLAYER))
	engine.drain()
	_ok("index: an unregistered effect no longer fires", _fake(engine).unit("p1").block == 1)

	var always: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [_block(1.0)]
	)
	engine.register(_instance("effect:c", always, _owner("p1"), TRAIT))
	engine.record(_phase_fact(PLAYER))
	engine.drain()
	_ok("index: an Always effect never dispatches", _fake(engine).unit("p1").block == 1)

	var counted: EffectInstance = _instance(
			"effect:d", block, _owner("p1"), TRAIT
	)
	counted.set_counter(EffectDefinition.Lane.COMBAT, 4)
	counted.set_counter(EffectDefinition.Lane.CAMPAIGN, 9)
	engine.register(counted)
	_ok(
			"index: registering starts the combat lane fresh, keeps the campaign lane",
			counted.get_counter(EffectDefinition.Lane.COMBAT) == 0
			and counted.get_counter(EffectDefinition.Lane.CAMPAIGN) == 9
	)
	engine.unregister("effect:d")
	counted.set_counter(EffectDefinition.Lane.COMBAT, 4)
	engine.register(counted, true)
	_ok(
			"index: a transfer keeps the combat lane",
			counted.get_counter(EffectDefinition.Lane.COMBAT) == 4
	)


func _test_scope() -> void:
	var engine: EffectEngine = _world()
	var p1: EffectOwner = _owner("p1")
	var army: EffectOwner = EffectOwner.for_army("seat:0", 0)
	var enemy: EffectOwner = _owner("e1")
	var cases: Array = [
		[p1, "p1", THIS_UNIT, true], [p1, "p2", THIS_UNIT, false],
		[p1, "p2", YOUR_UNIT, true], [p1, "q1", YOUR_UNIT, false],
		[p1, "e1", YOUR_UNIT, false], [p1, "keg", YOUR_UNIT, false],
		[p1, "q1", ANY_ALLY_UNIT, true], [p1, "e1", ANY_ALLY_UNIT, false],
		[p1, "e1", ANY_UNIT, true], [p1, "keg", ANY_UNIT, false],
		[army, "p1", YOUR_UNIT, true], [army, "q1", YOUR_UNIT, false],
		[army, "p1", THIS_UNIT, false], [enemy, "e2", YOUR_UNIT, true],
		[enemy, "p1", ANY_ALLY_UNIT, false],
	]
	var wrong: PackedStringArray = []
	for row: Array in cases:
		var owner: EffectOwner = row[0]
		if engine.in_scope(owner, row[1] as String, row[2] as EffectDefinition.Scope) != row[3]:
			wrong.append("%s %s %d" % [owner.owner_id, row[1], row[2]])
	_ok("scope: owner-relative scopes", wrong.is_empty(), ", ".join(wrong))
	_same(
			"scope: units in Your Unit scope, in map order",
			",".join(engine.units_in_scope(army, YOUR_UNIT)),
			"p1,p2"
	)


func _test_dispatch_scope() -> void:
	var engine: EffectEngine = _world()
	var gain: GainResource = _gain(GainResource.Pool.BLOCK, Owner.new(), _constant(1.0))
	var allies: EffectDefinition = _definition(EffectDefinition.Trigger.HIT_TAKEN, [], [gain])
	allies.scope = ANY_ALLY_UNIT
	var yours: EffectDefinition = _definition(EffectDefinition.Trigger.HIT_TAKEN, [], [gain])
	yours.scope = YOUR_UNIT
	engine.register(_instance("effect:ally", allies, _owner("p1"), TRAIT))
	engine.register(_instance("effect:yours", yours, _owner("p2"), TRAIT))
	engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "q1", "e1"))
	engine.drain()
	_ok(
			"dispatch: a partner's hit reaches Any Ally Unit, not Your Unit",
			_fake(engine).unit("p1").block == 1 and _fake(engine).unit("p2").block == 0
	)

	var phase: EffectDefinition = _definition(EffectDefinition.Trigger.PHASE_START, [], [gain])
	engine.register(_instance("effect:p", phase, _owner("q1"), TRAIT))
	engine.register(_instance("effect:e", phase, _owner("e1"), TRAIT))
	engine.record(_phase_fact(ENEMY))
	engine.drain()
	_ok(
			"dispatch: Phase Start matches the owner's side only",
			_fake(engine).unit("e1").block == 1 and _fake(engine).unit("q1").block == 0
	)

	var unheld: EffectOwner = EffectOwner.for_item("item:bag", "", 0, PLAYER)
	engine.register(_instance("effect:bag", phase, unheld, TRAIT))
	_fake(engine).unit("e1").defeated = true
	var before: int = engine.fact_log.size()
	engine.record(_phase_fact(ENEMY))
	engine.record(_phase_fact(PLAYER))
	engine.drain()
	_ok(
			"dispatch: no effect of a defeated unit or an unheld item fires",
			engine.fact_log.size() == before + 2 + 2,
			_log_tail(engine, before)
	)


func _test_reaction_order() -> void:
	var engine: EffectEngine = _world()
	var mark: EffectDefinition = _definition(
			EffectDefinition.Trigger.HIT_TAKEN,
			[],
			[_gain(GainResource.Pool.STANCE, null, _constant(0.0))]
	)
	mark.scope = ANY_UNIT
	var army: EffectOwner = EffectOwner.for_army("seat:0", 0)
	var held_by_p1: EffectOwner = EffectOwner.for_item("item:w", "p1", 0, PLAYER)
	# Ids are chosen against the expected order, so only the rules can produce it.
	var instances: Array[EffectInstance] = [
		_instance("a-curse", mark, army, Modifier.SourceKind.CURSE),
		_instance("b-enemy", mark, _owner("e2"), TRAIT),
		_instance("c-heirloom", mark, army, Modifier.SourceKind.HEIRLOOM),
		_instance("d-partner", mark, _owner("q1"), TRAIT),
		_instance("e-weapon", mark, held_by_p1, Modifier.SourceKind.WEAPON),
		_instance("f-trait", mark, _owner("p1"), TRAIT),
		_instance("g-target", mark, _owner("e1"), TRAIT),
		_instance("h-actor", mark, _owner("p2"), TRAIT),
		_instance("i-actor", mark, _owner("p2"), TRAIT),
	]
	var expected: String = (
			"h-actor,i-actor,g-target,f-trait,e-weapon,c-heirloom,a-curse,d-partner,b-enemy"
	)
	var orders: PackedStringArray = []
	for shuffle: int in 3:
		var shuffled: EffectEngine = _world()
		_fake(shuffled).unit("p1").weapon = "item:w"
		var copies: Array[EffectInstance] = []
		for instance: EffectInstance in instances:
			copies.append(instance.copy())
		_shuffle(copies, shuffle)
		for instance: EffectInstance in copies:
			shuffled.register(instance)
		shuffled.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p2", "e1"))
		orders.append(_activations(shuffled))
	_same("order: role, seat (enemies last), carrier kind (curses last), id", orders[0], expected)
	_ok(
			"order: registration order never matters",
			orders[0] == orders[1] and orders[1] == orders[2]
	)


func _test_counter_condition() -> void:
	var engine: EffectEngine = _world()
	var third: CounterCondition = CounterCondition.new()
	third.count = 3
	var instance: EffectInstance = _instance(
			"effect:third",
			_definition(EffectDefinition.Trigger.HIT_TAKEN, [third], [_block(1.0)]),
			_owner("p1"),
			TRAIT
	)
	engine.register(instance)
	for i: int in 6:
		engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))
	engine.drain()
	_ok("counter: every 3rd of 6 events fires twice", _fake(engine).unit("p1").block == 2)
	_same("counter: each change is a fact", _counter_amounts(engine), "1,2,0,1,2,0")

	var first: CounterCondition = CounterCondition.new()
	first.mode = CounterCondition.Mode.FIRST
	first.lane = EffectDefinition.Lane.CAMPAIGN
	var once: EffectInstance = _instance(
			"effect:first",
			_definition(EffectDefinition.Trigger.HIT_DEALT, [first], [_block(1.0)]),
			_owner("p2"),
			TRAIT
	)
	engine.register(once)
	for i: int in 3:
		engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, "p2", "e1"))
	engine.drain()
	_ok("counter: First fires once per lane period", _fake(engine).unit("p2").block == 1)
	_ok(
			"counter: lanes count apart, and the fact names the lane",
			once.get_counter(EffectDefinition.Lane.CAMPAIGN) == 1
			and once.get_counter(EffectDefinition.Lane.COMBAT) == 0
			and _last_of(engine, CombatFact.Kind.COUNTER_CHANGED).key
			== EffectDefinition.Lane.CAMPAIGN
	)
	once.reset_lane(EffectDefinition.Lane.CAMPAIGN)
	_ok(
			"counter: a lane reset starts First over",
			once.get_counter(EffectDefinition.Lane.CAMPAIGN) == 0
	)

	var query: EffectContext = _context(engine, instance)
	query.is_query = true
	_ok(
			"counter: a value query never passes or counts",
			not third.test(query) and instance.get_counter(EffectDefinition.Lane.COMBAT) == 0
	)


func _test_chance_condition() -> void:
	var engine: EffectEngine = _world(PackedInt32Array([1, 0]))
	var quarter: ChanceCondition = ChanceCondition.new()
	quarter.chance_percent = 25
	var ctx: EffectContext = _context(engine, null)
	_ok(
			"chance: a forced success passes, a forced failure doesn't",
			quarter.test(ctx) and not quarter.test(ctx)
	)
	var record: RollRecord = engine.rolls.records[0]
	_ok(
			"chance: one percent roll recorded with its odds",
			engine.rolls.records.size() == 2 and record.kind == RollRecord.Kind.PERCENT
			and record.value == 25 and is_equal_approx(record.probability, 0.25)
	)
	ctx.is_query = true
	_ok(
			"chance: a value query never rolls",
			not quarter.test(ctx) and engine.rolls.records.size() == 2
	)


func _test_while_conditions() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	var ctx: EffectContext = _exchange_context(engine, "p1", "e1", "p1")
	ctx.subject_id = "p1"

	var exposed: WhileStateCondition = WhileStateCondition.new()
	var opponent_exposed: WhileStateCondition = WhileStateCondition.new()
	opponent_exposed.subject = WhileStateCondition.Subject.OPPONENT
	fake.unit("e1").stance = 0
	_ok("while: Exposed tests this unit's Stance", not exposed.test(ctx))
	_ok("while: the opponent's state", opponent_exposed.test(ctx))
	ctx.subject_id = "p2"
	_ok("while: no opponent outside the exchange", not opponent_exposed.test(ctx))
	ctx.subject_id = "p1"

	var low_hp: WhileCompareCondition = WhileCompareCondition.new()
	low_hp.quantity = WhileCompareCondition.Quantity.HP_PERCENT
	low_hp.comparison = WhileCompareCondition.Comparison.LOWER_THAN
	low_hp.against = WhileCompareCondition.Against.THRESHOLD
	low_hp.threshold = 50.0
	fake.unit("p1").hp = 10
	_ok("compare: half HP is not below half", not low_hp.test(ctx))
	fake.unit("p1").hp = 9
	_ok("compare: below half HP", low_hp.test(ctx))

	var faster: WhileCompareCondition = WhileCompareCondition.new()
	faster.key = CombatValue.Key.ATTACK_SPEED
	engine.set_base("p1", CombatValue.Key.ATTACK_SPEED, 7.0)
	engine.set_base("e1", CombatValue.Key.ATTACK_SPEED, 7.0)
	_ok("compare: a tie fails (strict)", not faster.test(ctx))
	engine.set_base("p1", CombatValue.Key.ATTACK_SPEED, 8.0)
	_ok("compare: higher than the opponent", faster.test(ctx))

	var defender: WhileRoleCondition = WhileRoleCondition.new()
	defender.role = WhileRoleCondition.Role.DEFENDER
	_ok("role: the initiator isn't the defender", not defender.test(ctx))
	ctx.subject_id = "e1"
	_ok("role: the defender", defender.test(ctx))
	ctx.initiator_id = ""
	_ok("role: outside an exchange no role holds", not defender.test(ctx))

	var gloom: WhileLayerCondition = WhileLayerCondition.new()
	gloom.layer = WhileLayerCondition.Layer.GLOOM
	gloom.or_deeper = true
	fake.unit("e1").layer = WhileLayerCondition.Layer.ABYSS
	_ok("layer: Abyss is Gloom or deeper", gloom.test(ctx))
	gloom.or_deeper = false
	_ok("layer: Abyss isn't exactly Gloom", not gloom.test(ctx))


func _test_position_conditions() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	var ctx: EffectContext = _exchange_context(engine, "p1", "e1", "p1")
	ctx.subject_id = "p1"
	ctx.distance = 2
	engine.set_base("p1", CombatValue.Key.RANGE_MAX, 2.0)
	var at_max: WhilePositionCondition = _position(WhilePositionCondition.Kind.AT_MAXIMUM_RANGE)
	_ok("position: at maximum range", at_max.test(ctx))
	ctx.distance = 1
	_ok("position: not at maximum range", not at_max.test(ctx))

	fake.unit("p1").moved = 3
	var moved: WhilePositionCondition = _position(WhilePositionCondition.Kind.MOVED_AT_LEAST)
	moved.tiles = 3
	_ok("position: moved 3+ tiles", moved.test(ctx))
	_ok("position: has moved", not _position(WhilePositionCondition.Kind.HAS_NOT_MOVED).test(ctx))

	var vanguard: WhilePositionCondition = _position(
			WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY
	)
	_ok("position: p2 is closer to an enemy than p1", not vanguard.test(ctx))
	ctx.subject_id = "p2"
	_ok("position: no ally closer than p2", vanguard.test(ctx))

	var adjacent_enemy: WhilePositionCondition = _position(WhilePositionCondition.Kind.ADJACENT_TO)
	adjacent_enemy.side = EffectDefinition.UnitSide.ENEMY
	_ok("position: p2 is adjacent to an enemy", adjacent_enemy.test(ctx))
	ctx.subject_id = "p1"
	_ok("position: p1 isn't", not adjacent_enemy.test(ctx))
	var within: WhilePositionCondition = _position(WhilePositionCondition.Kind.WITHIN)
	within.side = EffectDefinition.UnitSide.ENEMY
	within.tiles = 2
	_ok("position: an enemy within 2 tiles", within.test(ctx))


func _test_selectors() -> void:
	var engine: EffectEngine = _world(PackedInt32Array([1]))
	var instance: EffectInstance = _instance(
			"effect:s", _definition(EffectDefinition.Trigger.HIT_TAKEN, [], []),
			_owner("p2"), TRAIT
	)
	var ctx: EffectContext = _context(engine, instance)
	ctx.fact = CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1")
	_same("select: owner", ",".join(Owner.new().select(ctx)), "p2")
	_same("select: fact actor", ",".join(FactActor.new().select(ctx)), "p1")
	_same("select: fact target", ",".join(FactTarget.new().select(ctx)), "e1")
	ctx.fact = CombatFact.new(CombatFact.Kind.HEALED, "p1")
	_ok("select: no fact target", FactTarget.new().select(ctx).is_empty())

	var around: Area = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ANY, false)
	_same("select: adjacent units, friend or foe", ",".join(around.select(ctx)), "p1,e1")
	var allies: Area = _area(Area.Center.OWNER, 2, EffectDefinition.UnitSide.ALLY, true)
	_same("select: this unit and allies within 2", ",".join(allies.select(ctx)), "p1,p2,q1")
	var enemies: Area = _area(Area.Center.FACT_ACTOR, 4, EffectDefinition.UnitSide.ENEMY, false)
	_same("select: enemies around that unit", ",".join(enemies.select(ctx)), "e1,e2")
	var sanctuary: Area = _area(
			Area.Center.COMMAND_TARGET, 1, EffectDefinition.UnitSide.ALLY, true
	)
	_ok("select: no command, no target area", sanctuary.select(ctx).is_empty())
	ctx.command_target_id = "p1"
	_same(
			"select: the target and allies adjacent to it",
			",".join(sanctuary.select(ctx)),
			"p1,p2,q1"
	)
	sanctuary.include_center = false
	ctx.command_target_id = "e1"
	_same("select: allies adjacent to an enemy target", ",".join(sanctuary.select(ctx)), "p2")
	ctx.command_target_id = ""

	var scope: AllOfScope = AllOfScope.new()
	_same("select: your units", ",".join(scope.select(ctx)), "p1,p2")
	var pick: RandomOf = RandomOf.new()
	pick.from = scope
	_same("select: a random one of your units (forced pick 1)", ",".join(pick.select(ctx)), "p2")
	var record: RollRecord = engine.rolls.records[0]
	_ok(
			"select: the pick is recorded with its odds",
			record.kind == RollRecord.Kind.PICK and record.value == 2
			and is_equal_approx(record.probability, 0.5)
	)
	var nobody: RandomOf = RandomOf.new()
	nobody.from = FactTarget.new()
	_ok(
			"select: no candidates, no roll",
			nobody.select(ctx).is_empty() and engine.rolls.records.size() == 1
	)
	_ok("select: a decided pick is no placeholder", not record.is_placeholder)
	var forecast: ForecastRolls = ForecastRolls.new()
	_ok("select: a forecast keeps the first candidate", forecast.pick_index(3) == 0)
	_ok(
			"select: a forecast's pick is marked random (question 35)",
			forecast.records[0].is_placeholder and forecast.records[0].kind == RollRecord.Kind.PICK
	)
	forecast.roll_hit_2rn(50)
	_ok("select: a forecast's hit is no placeholder", not forecast.records[1].is_placeholder)


func _test_value_sources() -> void:
	var engine: EffectEngine = _world()
	var instance: EffectInstance = _instance(
			"effect:v", _definition(EffectDefinition.Trigger.HEALED, [], []),
			_owner("p2"), TRAIT
	)
	instance.set_counter(EffectDefinition.Lane.COMBAT, 4)
	var ctx: EffectContext = _context(engine, instance)
	ctx.fact = CombatFact.new(CombatFact.Kind.HEALED, "p2")
	ctx.fact.amount = 10
	ctx.fact.hp_amount = 4
	_ok("value: constant", _constant(2.5).evaluate(ctx) == 2.5)
	var overheal: PercentOfFact = PercentOfFact.new()
	overheal.field = PercentOfFact.Field.OVERHEAL
	_ok("value: 100% of that overheal", overheal.evaluate(ctx) == 6.0)
	overheal.percent = 50.0
	_ok("value: 50% of that overheal", overheal.evaluate(ctx) == 3.0)
	var hp_part: PercentOfFact = PercentOfFact.new()
	hp_part.field = PercentOfFact.Field.HP_AMOUNT
	_ok("value: the HP part", hp_part.evaluate(ctx) == 4.0)

	engine.set_base("p2", CombatValue.Key.MOVEMENT, 5.0)
	var movement: StatOf = StatOf.new()
	movement.key = CombatValue.Key.MOVEMENT
	_ok("value: this unit's Movement", movement.evaluate(ctx) == 5.0)
	var count: CountOf = CountOf.new()
	count.selector = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ALLY, false)
	count.each = 2.0
	_ok("value: 2 per adjacent ally", count.evaluate(ctx) == 2.0)
	_ok("value: its count this combat", CounterValue.new().evaluate(ctx) == 4.0)


func _test_modify_that() -> void:
	var engine: EffectEngine = _world()
	var instance: EffectInstance = _instance(
			"effect:bulwark", _definition(EffectDefinition.Trigger.HIT_TAKEN, [], []),
			_owner("p1"), TRAIT, "Bulwark"
	)
	var ctx: EffectContext = _context(engine, instance)
	_modify_that(ModifyThat.What.VALUE, MULTIPLY, 0.5, DamageStage.Key.MULTIPLIERS).apply(ctx)
	var flag: ModifyThat = _modify_that(ModifyThat.What.FLAG, ADD, 0.0)
	flag.flag = ModifyThat.Flag.SKIP_MITIGATION
	flag.apply(ctx)
	_modify_that(ModifyThat.What.AMOUNT, ADD, -1.0).apply(ctx)
	engine.set_base("e1", DamageStage.Key.MULTIPLIERS, 8.0)
	var breakdown: ValueBreakdown = engine.stats("e1").explain(DamageStage.Key.MULTIPLIERS, ctx)
	_same(
			"that: a stage modifier joins queries with the context",
			breakdown.to_text(),
			"8 base ×0.5 Bulwark = 4"
	)
	_ok(
			"that: without the context it doesn't",
			engine.stats("e1").get_value(DamageStage.Key.MULTIPLIERS) == 8.0
	)
	_ok(
			"that: flags turn on",
			ctx.has_flag(ModifyThat.Flag.SKIP_MITIGATION)
			and not ctx.has_flag(ModifyThat.Flag.LIFESTEAL)
	)
	_ok("that: the amount is shaped exactly", ctx.shaped_amount(2.5).total == 1.5)


func _test_gain_resource_paths() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	var healer: EffectInstance = _instance(
			"effect:h", _definition(EffectDefinition.Trigger.ALWAYS, [], []),
			_owner("p2"), TRAIT
	)
	var ctx: EffectContext = _context(engine, healer)
	fake.unit("p1").hp = 10
	var heal_p1: GainResource = _gain(
			GainResource.Pool.HP,
			_area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ALLY, false),
			_constant(14.5)
	)
	heal_p1.apply(ctx)
	_same(
			"gain: a heal by another unit is Healed an ally, then Healed, overheal kept",
			_log_tail(engine, 0),
			"s0#1 HEALED_AN_ALLY p2 -> p1 amount 15 (hp 10, block 0) source effect effect effect:h"
			+ " | s0#2 HEALED p1 <- p2 amount 15 (hp 10, block 0) source effect effect effect:h"
	)
	_ok("gain: healed to maximum HP", fake.unit("p1").hp == 20)

	var start: int = engine.fact_log.size()
	_block(2.5).apply(ctx)
	_block(-2.0).apply(ctx)
	_block(-5.0).apply(ctx)
	_same(
			"gain: Block rounds half up; a negative amount is a loss of what there is",
			_log_tail(engine, start),
			"s0#3 BLOCK_GAINED p2 amount 3 (hp 0, block 3) source effect effect effect:h"
			+ " | s0#4 BLOCK_LOST p2 amount 2 (hp 0, block 2) source effect effect effect:h"
			+ " | s0#5 BLOCK_LOST p2 amount 1 (hp 0, block 1) source effect effect effect:h"
	)
	start = engine.fact_log.size()
	_block(-1.0).apply(ctx)
	_ok("gain: losing Block from none records nothing", engine.fact_log.size() == start)

	_gain(GainResource.Pool.STANCE, null, _constant(-5.0)).apply(ctx)
	_gain(GainResource.Pool.STANCE, null, _constant(5.0)).apply(ctx)
	_same(
			"gain: Stance stops at 0 (Exposed) and at its maximum",
			_log_tail(engine, start),
			"s0#6 STANCE_CHANGED p2 amount -2 source effect effect effect:h"
			+ " | s0#7 EXPOSED p2 effect effect:h"
			+ " | s0#8 STANCE_CHANGED p2 amount 2 source effect effect effect:h"
	)


func _test_deal_splash() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	fake.unit("p2").block = 1
	fake.unit("e1").hp = 2
	var cleave: EffectInstance = _instance(
			"effect:cleave", _definition(EffectDefinition.Trigger.HIT_DEALT, [], []),
			_owner("p2"), TRAIT
	)
	var splash: DealSplash = DealSplash.new()
	splash.target = _area(Area.Center.OWNER, 1, EffectDefinition.UnitSide.ANY, false)
	splash.amount = _constant(2.0)
	splash.apply(_context(engine, cleave))
	_same(
			"splash: Block absorbs, then HP; a defeat names the source",
			_log_tail(engine, 0),
			"s0#1 DAMAGE_TAKEN p1 <- p2 amount 2 (hp 2, block 0) source splash effect effect:cleave"
			+ " | s0#2 DAMAGE_TAKEN e1 <- p2 amount 2 (hp 2, block 0) source splash"
			+ " effect effect:cleave"
			+ " | s0#3 DEFEATED e1 <- p2 effect effect:cleave"
			+ " | s0#4 DEFEATED_AN_ENEMY p2 -> e1 effect effect:cleave"
	)
	_ok("splash: the defeated unit leaves the map", not engine.state.has_unit("e1"))


func _test_change_base_stat() -> void:
	var engine: EffectEngine = _world()
	engine.set_base("p1", CombatValue.Key.MGT, 4.0, "Fighter base")
	var booster: ChangeBaseStat = ChangeBaseStat.new()
	booster.key = CombatValue.Key.MGT
	booster.value = 1.0
	var instance: EffectInstance = _instance(
			"effect:tonic", _definition(EffectDefinition.Trigger.ALWAYS, [], [booster]),
			EffectOwner.for_item("item:tonic", "p1", 0, PLAYER),
			Modifier.SourceKind.POUCH_ITEM,
			"Might Tonic"
	)
	booster.apply(_context(engine, instance))
	_same(
			"base stat: a sourced permanent delta",
			engine.stats("p1").explain(CombatValue.Key.MGT).to_text(),
			"4 Fighter base +1 Might Tonic = 5"
	)
	_ok(
			"base stat: the bridge can read it back",
			engine.get_deltas("p1", CombatValue.Key.MGT).size() == 1
	)


func _test_always_on_modifiers() -> void:
	var engine: EffectEngine = _world()
	var fake: FakeState = _fake(engine)
	fake.unit("p2").weapon = "item:staff"
	var hit: int = CombatValue.Key.HIT
	engine.set_base("p1", hit, 70.0)
	engine.set_base("p2", hit, 70.0)
	var sharp: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS, [], [_modify_value(hit, ADD, 10.0)]
	)
	sharp.scope = YOUR_UNIT
	var army: EffectOwner = EffectOwner.for_army("seat:0", 0)
	engine.register(
			_instance("effect:banner", sharp, army, Modifier.SourceKind.HEIRLOOM, "Banner")
	)
	var desperate: EffectDefinition = _definition(
			EffectDefinition.Trigger.ALWAYS,
			[WhileStateCondition.new()],
			[_modify_value(hit, ADD, 15.0)]
	)
	engine.register(_instance("effect:desperate", desperate, _owner("p1"), TRAIT, "Desperate"))
	var counter: SetPermission = SetPermission.new()
	counter.permission = CombatValue.Permission.CAN_COUNTER
	counter.allow = false
	var staff: EffectDefinition = _definition(EffectDefinition.Trigger.ALWAYS, [], [counter])
	var held_by_p2: EffectOwner = EffectOwner.for_item("item:staff", "p2", 0, PLAYER)
	engine.register(
			_instance("effect:staff", staff, held_by_p2, Modifier.SourceKind.WEAPON, "Staff")
	)

	_same(
			"always: a heirloom reaches your units",
			engine.stats("p2").explain(hit).to_text(),
			"70 base +10 Banner = 80"
	)
	_ok(
			"always: a conditional modifier is off while its condition fails",
			engine.stats("p1").get_value(hit) == 80.0
	)
	fake.unit("p1").stance = 0
	_same(
			"always: and on, live, once it holds (trait before heirloom: canonical order)",
			engine.stats("p1").explain(hit).to_text(),
			"70 base +15 Desperate +10 Banner = 95"
	)
	_ok(
			"always: a permission denial",
			not engine.stats("p2").is_allowed(CombatValue.Permission.CAN_COUNTER)
			and engine.stats("p1").is_allowed(CombatValue.Permission.CAN_COUNTER)
	)
	_ok("always: the heirloom's seat has it too", engine.stats("seat:0").get_value(hit) == 10.0)


func _test_add_timed_modifier() -> void:
	var engine: EffectEngine = _world()
	engine.set_base("p1", CombatValue.Key.HIT, 70.0)
	var horn: AddTimedModifier = AddTimedModifier.new()
	horn.key = CombatValue.Key.HIT
	horn.value = 15.0
	horn.end = AddTimedModifier.End.THIS_COMBAT
	horn.uses = 1
	var instance: EffectInstance = _instance(
			"effect:momentum", _definition(EffectDefinition.Trigger.MISSED, [], [horn]),
			_owner("p1"), TRAIT, "Momentum"
	)
	horn.apply(_context(engine, instance))
	_same(
			"timed: gained with a fact",
			_log_tail(engine, 0),
			"s0#1 MODIFIER_GAINED p1 effect effect:momentum"
	)
	_ok(
			"timed: held and read live",
			engine.get_timed_modifiers("p1").size() == 1
			and engine.stats("p1").get_value(CombatValue.Key.HIT) == 85.0
	)


func _test_content_errors() -> void:
	var engine: EffectEngine = _world()
	var lifesteal: ModifyThat = _modify_that(ModifyThat.What.FLAG, ADD, 0.0)
	var misplaced: EffectDefinition = _definition(
			EffectDefinition.Trigger.PHASE_START, [], [lifesteal]
	)
	engine.register(_instance("effect:x", misplaced, _owner("p1"), TRAIT))
	engine.record(_phase_fact(PLAYER))
	_ok(
			"content: an inline operation on a trigger without a window is reported",
			engine.diagnostics.size() == 1 and engine.diagnostics[0].contains("no inline window")
	)
	var grant: CampaignGrant = CampaignGrant.new()
	grant.apply(_context(engine, engine.get_instance("effect:x")))
	_ok("content: a campaign grant joins the engine's grants", (
			engine.diagnostics.size() == 1
			and engine.grants.size() == 1
			and engine.grants[0].source_effect_id == "effect:x"
	))


func _test_queued_operations_wait() -> void:
	var engine: EffectEngine = _world()
	var block: EffectDefinition = _definition(
			EffectDefinition.Trigger.HIT_TAKEN, [], [_block(2.0)]
	)
	engine.register(_instance("effect:q", block, _owner("p1"), TRAIT))
	engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1"))
	_ok(
			"queue: a queued operation waits for the step boundary",
			engine.pending_reactions() == 1 and _fake(engine).unit("p1").block == 0
	)
	engine.drain()
	_ok(
			"queue: drained at the boundary",
			engine.pending_reactions() == 0 and _fake(engine).unit("p1").block == 2
	)


func _test_window_releases_after_record() -> void:
	var engine: EffectEngine = _world()
	var tenth: CounterCondition = CounterCondition.new()
	var both: EffectDefinition = _definition(
			EffectDefinition.Trigger.HIT_TAKEN,
			[tenth],
			[
				_modify_that(ModifyThat.What.VALUE, MULTIPLY, 0.5, DamageStage.Key.MULTIPLIERS),
				_block(1.0),
			]
	)
	engine.register(_instance("effect:w", both, _owner("p1"), TRAIT))
	var hit: CombatFact = CombatFact.new(CombatFact.Kind.HIT_TAKEN, "p1", "e1")
	var ctx: EffectContext = EffectContext.new()
	engine.open_window(hit, ctx)
	_ok(
			"window: inline operations act at once; nothing is recorded yet",
			ctx.that_modifiers(DamageStage.Key.MULTIPLIERS).size() == 1
			and engine.fact_log.is_empty() and engine.pending_reactions() == 0
	)
	hit.amount = 4
	engine.record(hit, ctx)
	_same(
			"window: the fact first, then its counter and activation",
			_log_tail(engine, 0),
			"s0#1 HIT_TAKEN p1 <- e1 amount 4 | s0#2 COUNTER_CHANGED p1 lane 0 effect effect:w"
			+ " | s0#3 EFFECT_ACTIVATED p1 effect effect:w"
	)
	_ok("window: its queued operation is released", engine.pending_reactions() == 1)


# --- Helpers -------------------------------------------------------------------------------------


# A map with two units of seat 0, a partner's unit (seat 1), two enemies and a powder keg:
#   p1 (0,0)  p2 (1,0)  e1 (2,0)  .  e2 (4,0)
#   q1 (0,1)                                      keg (6,6)
func _world(outcomes: PackedInt32Array = PackedInt32Array()) -> EffectEngine:
	var fake: FakeState = FakeState.new()
	fake.add("p1", PLAYER, 0, Vector2i(0, 0))
	fake.add("p2", PLAYER, 0, Vector2i(1, 0))
	fake.add("q1", PLAYER, 1, Vector2i(0, 1))
	fake.add("e1", ENEMY, -1, Vector2i(2, 0))
	fake.add("e2", ENEMY, -1, Vector2i(4, 0))
	fake.add("keg", OBJECT_SIDE, -1, Vector2i(6, 6), 1)
	var engine: EffectEngine = EffectEngine.new(fake, ForcedRolls.new(outcomes))
	for id: String in ["p1", "p2", "q1", "e1", "e2"]:
		engine.set_base(id, CombatValue.Key.HP, 20.0)
		engine.set_base(id, CombatValue.Key.STANCE_MAX, 2.0)
	return engine


# The engine's fake state, typed so its setup methods can be called.
func _fake(engine: EffectEngine) -> FakeState:
	return engine.state


func _instance(
		id: String,
		definition: EffectDefinition,
		owner: EffectOwner,
		kind: Modifier.SourceKind,
		label: String = ""
) -> EffectInstance:
	return EffectInstance.new(id, definition, owner, kind, label)


func _context(engine: EffectEngine, instance: EffectInstance) -> EffectContext:
	var ctx: EffectContext = EffectContext.new()
	ctx.engine = engine
	ctx.instance = instance
	if instance != null:
		ctx.subject_id = instance.owner.subject_id()
	return ctx


func _exchange_context(
		engine: EffectEngine, attacker: String, defender: String, initiator: String
) -> EffectContext:
	var ctx: EffectContext = _context(engine, null)
	ctx.attacker_id = attacker
	ctx.defender_id = defender
	ctx.initiator_id = initiator
	return ctx


func _definition(
		trigger: EffectDefinition.Trigger, conditions: Array, operations: Array
) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = trigger
	definition.conditions.assign(conditions)
	definition.operations.assign(operations)
	return definition


# "Gain <amount> Block" for the owner.
func _block(amount: float) -> GainResource:
	return _gain(GainResource.Pool.BLOCK, null, _constant(amount))


# The owner of a unit's trait on the standard map: its seat and side.
func _owner(unit_id: String) -> EffectOwner:
	if unit_id.begins_with("e"):
		return EffectOwner.for_unit(unit_id, -1, ENEMY)
	return EffectOwner.for_unit(unit_id, 1 if unit_id == "q1" else 0, PLAYER)


func _gain(pool: GainResource.Pool, target: TargetSelector, amount: ValueSource) -> GainResource:
	var gain: GainResource = GainResource.new()
	gain.pool = pool
	gain.target = target
	gain.amount = amount
	return gain


func _constant(value: float) -> Constant:
	var constant: Constant = Constant.new()
	constant.value = value
	return constant


func _modify_value(key: int, mode: Modifier.Mode, value: float) -> ModifyValue:
	var modify: ModifyValue = ModifyValue.new()
	modify.key = key
	modify.mode = mode
	modify.value = value
	return modify


func _modify_that(
		what: ModifyThat.What, mode: Modifier.Mode, value: float, key: int = 0
) -> ModifyThat:
	var modify: ModifyThat = ModifyThat.new()
	modify.what = what
	modify.mode = mode
	modify.value = value
	modify.key = key
	return modify


func _area(
		center: Area.Center, radius: int, side: EffectDefinition.UnitSide, include_center: bool
) -> Area:
	var area: Area = Area.new()
	area.center = center
	area.radius = radius
	area.side = side
	area.include_center = include_center
	return area


func _attack(
		role: WhileAttackCondition.Role, kind: WhileAttackCondition.Kind
) -> WhileAttackCondition:
	var condition: WhileAttackCondition = WhileAttackCondition.new()
	condition.role = role
	condition.kind = kind
	return condition


func _position(kind: WhilePositionCondition.Kind) -> WhilePositionCondition:
	var condition: WhilePositionCondition = WhilePositionCondition.new()
	condition.kind = kind
	return condition


func _phase_fact(side: CombatFact.CombatSide) -> CombatFact:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	fact.side = side
	return fact


# Deterministic reorderings: 0 keeps the order, 1 reverses it, 2 rotates it by 4.
func _shuffle(list: Array[EffectInstance], variant: int) -> void:
	if variant == 1:
		list.reverse()
	elif variant == 2:
		for i: int in 4:
			list.push_back(list.pop_front())


func _ids(instances: Array[EffectInstance]) -> String:
	var ids: PackedStringArray = []
	for instance: EffectInstance in instances:
		ids.append(instance.instance_id)
	return ",".join(ids)


# The instance ids of every EFFECT_ACTIVATED fact, in log order.
func _activations(engine: EffectEngine) -> String:
	var ids: PackedStringArray = []
	for fact: CombatFact in engine.fact_log:
		if fact.kind == CombatFact.Kind.EFFECT_ACTIVATED:
			ids.append(fact.source_effect_id)
	return ",".join(ids)


func _last_of(engine: EffectEngine, kind: CombatFact.Kind) -> CombatFact:
	for i: int in range(engine.fact_log.size() - 1, -1, -1):
		if engine.fact_log[i].kind == kind:
			return engine.fact_log[i]
	return CombatFact.new(CombatFact.Kind.PHASE_START)


func _counter_amounts(engine: EffectEngine) -> String:
	var amounts: PackedStringArray = []
	for fact: CombatFact in engine.fact_log:
		if fact.kind == CombatFact.Kind.COUNTER_CHANGED:
			amounts.append(str(fact.amount))
	return ",".join(amounts)


# The log lines from index `start` on, joined by " | ".
func _log_tail(engine: EffectEngine, start: int) -> String:
	var lines: PackedStringArray = []
	for i: int in range(start, engine.fact_log.size()):
		lines.append(engine.fact_log[i].to_log_line())
	return " | ".join(lines)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
