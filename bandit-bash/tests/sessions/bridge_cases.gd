# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bridge_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## [CampaignSession] battle bridge cases for tests/sessions/run_all.gd: beginning and ending
## battles, grants, restarts, and armies loaded through [Loadout].

const LoadoutCases = preload("res://tests/content/loadout_cases.gd")


func run() -> void:
	_run(_test_bridge_begin_and_end)
	_run(_test_bridge_opening_swap_per_seat)
	_run(_test_bridge_cross_map_grants)
	_run(_test_dropped_grant_not_recorded)
	_run(_test_bridge_restart_rolls_the_same)
	_run(_test_bridge_close_mid_battle)
	_run(_test_rng_section_refuses_a_battle)
	_run(_test_bridge_loadout_equals_by_hand)
	_run(_test_bridge_loadout_writes_back)


# The opening-swap setting reaches each map per seat: on (the default, no entry) the map waits in
# the swap window at turn 0; off, turn 1's player Phase Start runs as the battle begins.
func _test_bridge_opening_swap_per_seat() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var request: CampaignSession.BattleRequest = _request(
			run, {0: ["Drengr", "Archer"], 1: ["Drengr", "Archer"]}
	)
	request.opening_swap[1] = false
	var battle: CombatEncounter = run.begin_battle(request)
	var on: CombatSession = battle.session_of_seat(0)
	var off: CombatSession = battle.session_of_seat(1)
	_check("swap setting: on by default, the window waits for Start", (
			on.state.map.opening_swap_open
			and on.state.turn == 0
			and on.state.seats_to_start == PackedInt32Array([0])
	))
	var kinds: PackedStringArray = []
	for fact: CombatFact in off.engine.fact_log:
		kinds.append(CombatFact.Kind.find_key(fact.kind) as String)
	_check("swap setting: off, turn 1 starts at once", (
			not off.state.map.opening_swap_open
			and off.state.turn == 1
			and kinds.has("PHASE_START")
	), " ".join(kinds))
	run.end_battle()
	return true


func _test_bridge_begin_and_end() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr", "Archer"]})
	var a: String = request.armies[0].units[0].id
	var stubborn: EffectDefinition = _counting("stubborn", EffectTerms.Lane.CAMPAIGN)
	var counted: EffectInstance = _carrier(run, a, stubborn)
	counted.set_counter(EffectTerms.Lane.CAMPAIGN, 5)
	counted.set_counter(EffectTerms.Lane.COMBAT, 7)
	var flask: EffectDefinition = _hit_dealt_block("flask", 1.0)
	flask.charges = 3
	flask.charge_lane = EffectTerms.Lane.CAMPAIGN
	var charged: EffectInstance = _carrier(run, a, flask)
	charged.charges_left = 2
	var benched: EffectInstance = _carrier(run, "unit:99", _hit_dealt_block("benched", 1.0))
	var banner_definition: EffectDefinition = _every_hit_by_allies(3)
	banner_definition.scope = EffectTerms.Scope.YOUR_UNIT
	var banner: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			banner_definition,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	)
	run.add_carrier(banner)

	var events: Array[String] = []
	run.combat_encounter_opened.connect(func(encounter: CombatEncounter) -> void:
		events.append("encounter opened")
		encounter.session_opened.connect(
				func(session: CombatSession) -> void:
					events.append("s%d opened" % [session.session_id])
		)
	)
	run.combat_encounter_closed.connect(
			func(_encounter: CombatEncounter) -> void: events.append("encounter closed")
	)
	var battle: CombatEncounter = run.begin_battle(request)
	_check("bridge: begins", battle != null and run.encounter == battle)
	if battle == null:
		return true
	var session: CombatSession = battle.get_session(0)
	var copy: EffectInstance = session.engine.get_instance(counted.instance_id)
	_check("bridge: observers hear the encounter, then each session", (
			events == ["encounter opened", "s0 opened"]
	), str(events))
	_check("bridge: carriers registered as copies", copy != null and copy != counted)
	_check("bridge: campaign lane copied in, combat lane fresh", (
			copy.get_counter(EffectTerms.Lane.CAMPAIGN) == 5
			and copy.get_counter(EffectTerms.Lane.COMBAT) == 0
	))
	_check("bridge: a unit outside the battle brings nothing", (
			session.engine.get_instance(benched.instance_id) == null
	))
	_check("bridge: a Your Unit heirloom joins its seat's map", (
			session.engine.get_instance(banner.instance_id) != null
			and battle.get_cross_map_instances().is_empty()
	))
	_check("bridge: the army is deployed", (
			session.state.has_unit(a)
			and _layout_has_deployment(session, session.state.tile_of(a))
	))
	print("    (one error about a battle already on follows)")
	_check("bridge: one battle at a time", run.begin_battle(request) == null)

	var e: String = run.ids.next_enemy_id("Brute")
	var enemy: CombatUnitState = CombatUnitState.new()
	enemy.id = e
	enemy.side = ENEMY
	enemy.tile = Vector2i(3, 2)
	enemy.hp = 20
	session.add_unit(enemy, Battle.unit_bases())
	for i: int in 2:
		battle.submit(AttackFixture.new(0, a, e), 0)
	battle.resolve_queued()
	session.engine.add_growth(a, CombatValue.Stat.RES, 5)
	_check("bridge: the battle counts on the copies", (
			copy.get_counter(EffectTerms.Lane.CAMPAIGN) == 7
			and copy.get_counter(EffectTerms.Lane.COMBAT) == 0
			and counted.get_counter(EffectTerms.Lane.CAMPAIGN) == 5
	))

	var result: CampaignSession.BattleResult = run.end_battle()
	_check("bridge: campaign lanes written back", (
			counted.get_counter(EffectTerms.Lane.CAMPAIGN) == 7
			and charged.charges_left == 0
	), "%d, %d charges" % [
			counted.get_counter(EffectTerms.Lane.CAMPAIGN), charged.charges_left
	])
	_check("bridge: combat lanes dropped", counted.get_counter(EffectTerms.Lane.COMBAT) == 7)
	_check("bridge: growth changes left for the run flow", (
			result.growth_changes.has(a)
			and result.growth_changes[a] == {CombatValue.Stat.RES: 5}
	), str(result.growth_changes))
	_check("bridge: the encounter is closed and announced", (
			run.encounter == null
			and battle.is_closed
			and events[events.size() - 1] == "encounter closed"
	))
	_check("bridge: no battle, nothing to end", run.end_battle() == null)
	return true


# The same battle twice: once from unit and item instances through the loadout, once built by
# hand with the numbers unit-roster.md gives (Drengr; a Swift Archer+ with +1 MGT from an event).
# Deployment, every unit's state and values, and a real attack's facts must match line for line.
func _test_bridge_loadout_equals_by_hand() -> bool:
	var loaded: Array[String] = _loadout_battle(true)
	var by_hand: Array[String] = _loadout_battle(false)
	_check("loadout: a battle loaded from instances equals one built by hand", (
			not loaded.is_empty() and loaded == by_hand
	), _first_difference(loaded, by_hand))
	_check("loadout: the comparison covers deployment, values and an attack", (
			loaded.size() > 40
			and "\n".join(loaded).contains("HIT_DEALT")
			and "\n".join(loaded).contains("UNIT_SPAWNED")
	), str(loaded.size()))
	return true


func _test_bridge_loadout_writes_back() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "loadout_archer")
	archer.counters["loadout_archer_trait"] = 3
	var request: CampaignSession.BattleRequest = _loadout_request([archer], {})
	request.armies[0].heirloom_ids = PackedStringArray(["loadout_iron_heart"])
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check("loadout write back: begins", false)
		return true
	var session: CombatSession = battle.get_session(0)
	var trait_copy: EffectInstance = null
	var hearts: int = 0
	for instance: EffectInstance in session.engine.get_instances():
		if instance.definition.id == "loadout_archer_trait":
			trait_copy = instance
		elif instance.definition.id == "loadout_iron_heart_effect":
			hearts += 1
	_check("loadout write back: the trait's campaign lane is copied in", (
			trait_copy != null and trait_copy.get_counter(EffectTerms.Lane.CAMPAIGN) == 3
	))
	_check("loadout write back: the seat's heirloom joins its map", hearts == 1, str(hearts))
	if trait_copy != null:
		trait_copy.set_counter(EffectTerms.Lane.CAMPAIGN, 4)
	run.end_battle()
	var written: int = archer.counters.get("loadout_archer_trait", 0)
	_check("loadout write back: the trait's counter goes back to the unit", written == 4, (
			str(archer.counters)
	))
	battle = run.begin_battle(request)
	hearts = 0
	for instance: EffectInstance in battle.get_session(0).engine.get_instances():
		if instance.definition.id == "loadout_iron_heart_effect":
			hearts += 1
	_check("loadout write back: an heirloom is made a carrier once", hearts == 1, str(hearts))
	run.end_battle()
	return true


# Runs the comparison battle, [param from_instances] through the loadout or built by hand, and
# returns its lines: each unit's state and values after deployment, then every fact.
func _loadout_battle(from_instances: bool) -> Array[String]:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	# Every id is minted before the battle, so both runs name everything the same.
	var drengr_id: String = run.ids.next_unit_id("Drengr")
	var archer_id: String = run.ids.next_unit_id("Archer")
	var axe_id: String = run.ids.next_item_id("Simple Axe")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	var enemy_id: String = run.ids.next_enemy_id("Brute")
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	var request: CampaignSession.BattleRequest = null
	if from_instances:
		var drengr: UnitInstance = UnitInstance.new(drengr_id, "loadout_drengr")
		drengr.weapon_id = axe_id
		var archer: UnitInstance = UnitInstance.new(archer_id, "loadout_archer")
		archer.weapon_id = bow_id
		archer.prefix_id = "loadout_swift"
		archer.is_upgraded = true
		archer.stat_deltas.append(ItemInstance.StatDelta.new(
				CombatValue.Key.MGT, 1.0, "dark_goblet", "Dark Goblet"
		))
		request = _loadout_request([drengr, archer], {
			axe_id: ItemInstance.new(axe_id, "loadout_simple_axe"),
			bow_id: ItemInstance.new(bow_id, "loadout_simple_bow"),
		})
	else:
		request = _loadout_request([], {})
		var army: CampaignSession.Army = request.armies[0]
		army.units = [
			_hand_unit(drengr_id, "loadout_drengr", "", 24, axe_id, []),
			_hand_unit(archer_id, "loadout_archer", "bow", 13, bow_id, []),
		]
		army.commander_id = drengr_id
		# unit-roster.md: Drengr 24/5/6/3/2/5/13, Stance 3; Archer 13/5/8/0/0/5/6, Stance 1,
		# Swift +3 SPD, Archer+ +2 MGT +1 SPD, and +1 MGT from the event.
		army.bases[drengr_id] = _hand_bases([24, 5, 6, 3, 2, 5, 13], 3)
		army.bases[archer_id] = _hand_bases([13, 8, 12, 0, 0, 5, 6], 1)
		army.weapons = [
			_hand_weapon(
					axe_id, "Simple Axe", "axe", 10, WeaponTriangle.Profile.POWER, 1, 65, 15, []
			),
			_hand_weapon(bow_id, "Simple Bow", "bow", 6, WeaponTriangle.Profile.NONE, 3, 100, 5, [
				"flier",
			]),
		]
		army.weapons[1].range_min = 2
		run.add_carrier(EffectInstance.new(
				run.ids.next_effect_id(),
				catalog.unit_type("loadout_archer").upgraded_effects[0],
				EffectOwner.for_unit(archer_id, 0, PLAYER),
				Modifier.SourceKind.UNIT_TRAIT,
				"Volley+"
		))
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		return []
	var session: CombatSession = battle.get_session(0)
	var enemy: CombatUnitState = CombatUnitState.new()
	enemy.id = enemy_id
	enemy.side = ENEMY
	enemy.tile = Vector2i(3, 2)
	enemy.hp = 20
	session.add_unit(enemy, Battle.unit_bases())

	var lines: Array[String] = []
	for unit_id: String in session.state.unit_ids():
		lines.append_array(_unit_lines(session, unit_id))
	# The opening swap window holds turn 1 until the enemy is on the map; then, within the bow's
	# range of the enemy wherever deployment put the Archer, it attacks.
	session.state.move_unit(archer_id, Vector2i(3, 0))
	session.submit(StartCommand.new(0))
	session.submit(UnitTurnCommand.new(0, archer_id, UnitTurnCommand.Action.ATTACK, enemy_id))
	session.resolve_queued()
	for fact: CombatFact in session.engine.fact_log:
		lines.append(fact.to_log_line())
	run.end_battle()
	return lines


# A request on the fixture map whose seat 0 loads [param units] carrying [param items], from the
# loadout fixture tree. The map opens in the swap window, so turn 1 waits for a Start command.
func _loadout_request(
		units: Array[UnitInstance], items: Dictionary
) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = Battle.pool(["map_a"])
	request.catalog = EffectCatalog.load_tree(LoadoutCases.TREE)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = units
	army.item_instances.assign(items)
	request.armies[0] = army
	return request


func _hand_unit(
		id: String, unit_type: String, role: String, hp: int, weapon_id: String, tags: Array
) -> CombatUnitState:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.seat = 0
	unit.unit_type = unit_type
	unit.role = role
	unit.hp = hp
	unit.equipped_weapon_id = weapon_id
	unit.tags = PackedStringArray(tags)
	return unit


# HP, MGT, SPD, DEF, RES, MOV, CON in unit-roster.md's order, and the Stance.
func _hand_bases(stats: Array[int], stance: int) -> Dictionary:
	var keys: Array[int] = [
		CombatValue.Key.HP, CombatValue.Key.MGT, CombatValue.Key.SPD, CombatValue.Key.DEF,
		CombatValue.Key.RES, CombatValue.Key.MOVEMENT, CombatValue.Key.CON,
	]
	var bases: Dictionary = {CombatValue.Key.STANCE_MAX: float(stance)}
	for i: int in keys.size():
		bases[keys[i]] = float(stats[i])
	return bases


func _hand_weapon(
		id: String,
		label: String,
		weapon_type: String,
		damage: int,
		profile: WeaponTriangle.Profile,
		range_max: int,
		hit: int,
		weight: int,
		effective: Array
) -> CombatState.WeaponStats:
	var weapon: CombatState.WeaponStats = CombatState.WeaponStats.new()
	weapon.id = id
	weapon.label = label
	weapon.weapon_type = weapon_type
	weapon.damage = damage
	weapon.profile = profile
	weapon.range_max = range_max
	weapon.hit = hit
	weapon.weight = weight
	weapon.effective_against = PackedStringArray(effective)
	return weapon


# One unit's state and the combat values the battle reads, one line each.
func _unit_lines(session: CombatSession, unit_id: String) -> Array[String]:
	var unit: CombatUnitState = session.state.unit(unit_id)
	var lines: Array[String] = [
		"%s %s role %s tile %s hp %d stance %d block %d move %d tags %s weapon %s" % [
			unit_id, unit.unit_type, unit.role, unit.tile, unit.hp, unit.stance, unit.block,
			unit.movement_type, unit.tags, unit.equipped_weapon_id,
		],
	]
	var sheet: StatSheet = session.engine.stats(unit_id)
	for key: int in CombatValue.Key.values():
		lines.append("%s %s %d" % [unit_id, CombatValue.Key.find_key(key), sheet.get_int(key)])
	lines.append("%s ATTACK %d" % [unit_id, sheet.get_int(DamageStage.Key.ATTACK)])
	var weapon: CombatState.WeaponStats = session.state.equipped_weapon(unit_id)
	if weapon != null:
		lines.append("%s weapon %s %s %d %d %d-%d %d %d %s %s" % [
			unit_id, weapon.label, weapon.weapon_type, weapon.damage, weapon.profile,
			weapon.range_min, weapon.range_max, weapon.hit, weapon.weight,
			weapon.effective_against, weapon.crit_x,
		])
	return lines


func _first_difference(a: Array[String], b: Array[String]) -> String:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return "line %d: %s | %s" % [i, a[i], b[i]]
	return "%d lines vs %d" % [a.size(), b.size()]


func _test_bridge_cross_map_grants() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([1, 0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr"], 1: ["Archer"]})
	var a0: String = request.armies[0].units[0].id
	var a1: String = request.armies[1].units[0].id
	# "Every 2nd Hit dealt by Any Ally Unit: gain 50 gold" on seat 0's army.
	var purse: EffectDefinition = _every_hit_by_allies(2)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 50
	purse.operations.assign([gold])
	var heirloom: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			purse,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	)
	run.add_carrier(heirloom)
	var recorded: Array[CampaignSession.Grant] = []
	run.grant_recorded.connect(
			func(grant: CampaignSession.Grant) -> void: recorded.append(grant)
	)
	var battle: CombatEncounter = run.begin_battle(request)
	var e0: String = _add_enemy(run, battle.get_session(0))
	var e1: String = _add_enemy(run, battle.get_session(1))
	_check("grants: the heirloom went to the encounter", (
			battle.get_cross_map_instances().size() == 1
			and battle.get_cross_map_instances()[0].instance_id == heirloom.instance_id
	))

	var sandbox: Sandbox = Sandbox.new(battle.get_session(0).engine, ForecastRolls.new())
	for i: int in 2:
		sandbox.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, a0, e0))
	sandbox.engine.drain()
	_check("grants: a forecast grants nothing", (
			sandbox.engine.grants.size() == 1
			and battle.get_session(0).engine.grants.is_empty()
			and recorded.is_empty()
			and run.grants.is_empty()
	))

	battle.submit(AttackFixture.new(0, a0, e0), 0)
	battle.resolve_queued()
	_check("grants: nothing before the effect fires", run.grants.is_empty())
	battle.submit(AttackFixture.new(1, a1, e1), 1)
	battle.resolve_queued()
	var grant: CampaignSession.Grant = null if run.grants.is_empty() else run.grants[0]
	_check("grants: recorded for the owner's seat when it fires", (
			run.grants.size() == 1
			and recorded.size() == 1
			and grant.seat == 0
			and grant.grant == CampaignGrant.Grant.GOLD
			and grant.amount == 50
			and grant.source_effect_id == heirloom.instance_id
			and grant.describe() == "gold 50"
	))
	_check("grants: no diagnostics", battle.get_session(1).engine.diagnostics.is_empty())
	var result: CampaignSession.BattleResult = run.end_battle()
	_check("grants: the battle's grants come with its result", (
			result.grants.size() == 1 and result.grants[0] == grant
	))
	return true


func _test_dropped_grant_not_recorded() -> bool:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	# "Hit dealt: gain 1 gold", one reaction per hit.
	var tithe: EffectDefinition = _hit_dealt_block("tithe", 1.0)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 1
	tithe.operations.assign([gold])
	world.add_trait(a, tithe)
	var received: Array[int] = []
	world.session.grant_received.connect(
			func(_seat: int, _grant: int, amount: int, _id: String, _effect: String) -> void:
				received.append(amount)
	)
	print("    (one error about a step stopped at 256 reactions follows)")
	world.session.submit(HitsFixture.new(0, a, ReactionQueue.MAX_PER_STEP + 1))
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	_check("grants: a reaction dropped by the cap grants nothing", (
			received.size() == ReactionQueue.MAX_PER_STEP
			and world.session.engine.grants.size() == ReactionQueue.MAX_PER_STEP
			and batch.diagnostics.size() == 1
			and batch.diagnostics[0].contains("step stopped")
	), "%d grants" % [received.size()])
	return true


func _test_bridge_restart_rolls_the_same() -> bool:
	var summaries: PackedStringArray = []
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	run.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	var again: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	again.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	for campaign: CampaignSession in [run, run, again]:
		var battle: CombatEncounter = campaign.begin_battle(_request(campaign, {}))
		summaries.append(battle.setup.summary())
		battle.get_session(0).engine.rolls.roll_percent(50)
		campaign.end_battle()
	_check("restart: the same node set up twice in one run gives the same results", (
			summaries[1] == summaries[0]
	))
	_check("restart: a fresh run with the same seed gives the same results", (
			summaries[2] == summaries[0]
	))
	_check("restart: the sessions roll from the registry's COMBAT_ROLLS", (
			run.rng.stream(Battle.rolls_key(0)).capture()
			!= Battle.fresh_stream(RngKey.RngPurpose.COMBAT_ROLLS, 0, -1).capture()
	))
	return true


func _test_bridge_close_mid_battle() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr"]})
	var a: String = request.armies[0].units[0].id
	var stubborn: EffectDefinition = _counting("stubborn", EffectTerms.Lane.CAMPAIGN)
	var counted: EffectInstance = _carrier(run, a, stubborn)
	var closed: Array[CombatEncounter] = []
	run.combat_encounter_closed.connect(
			func(encounter: CombatEncounter) -> void: closed.append(encounter)
	)
	var battle: CombatEncounter = run.begin_battle(request)
	var e: String = _add_enemy(run, battle.get_session(0))
	battle.submit(AttackFixture.new(0, a, e), 0)
	battle.resolve_queued()
	run.close()
	_check("close: a battle in progress is dropped and announced", (
			run.is_closed and run.encounter == null and closed == [battle] and battle.is_closed
	))
	_check("close: nothing is written back", (
			counted.get_counter(EffectTerms.Lane.CAMPAIGN) == 0
	))
	print("    (one error about beginning a battle on a closed run follows)")
	_check("close: nothing begins again", run.begin_battle(request) == null)
	return true


# A restore replaces stream objects, so held data must never be applied to a run whose battle
# sessions already hold their streams.
func _test_rng_section_refuses_a_battle() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = run.begin_battle(_request(run, {}))
	var rolls: RngStream = run.rng.stream(Battle.rolls_key(0))
	battle.get_session(0).engine.rolls.roll_percent(50)
	var before: String = rolls.capture()
	var fresh_state: String = Battle.fresh_stream(RngKey.RngPurpose.COMBAT_ROLLS, 0, -1).capture()
	var saved: Dictionary = {Battle.rolls_key(0).to_save_key(): fresh_state}
	var section: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
	section.restore(saved)
	print("    (one error about restoring into a battle in progress follows)")
	var err: Error = section.attach(run)
	_check("rng section: attach refuses a run with a battle on", (
			err == ERR_ALREADY_IN_USE
			and is_same(run.rng.stream(Battle.rolls_key(0)), rolls)
			and rolls.capture() == before
	), error_string(err))
	_check("rng section: and keeps the data held", section.capture() == saved)
	run.end_battle()
	return true


# Adds [param definition] to the run as a trait of [param unit_id] (seat 0). Returns the carrier.
func _carrier(
		run: CampaignSession, unit_id: String, definition: EffectDefinition
) -> EffectInstance:
	var instance: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			definition,
			EffectOwner.for_unit(unit_id, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	run.add_carrier(instance)
	return instance


# "Hit dealt: count toward 100 in [param lane]" — a counter that never passes in these cases.
func _counting(id: String, lane: EffectTerms.Lane) -> EffectDefinition:
	var definition: EffectDefinition = _hit_dealt_block(id, 1.0, 100)
	var counter: CounterCondition = definition.conditions[0] as CounterCondition
	counter.lane = lane
	return definition


func _layout_has_deployment(session: CombatSession, tile: Vector2i) -> bool:
	return session.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT).has(tile)


# Records [member count] hits by its unit in one command, so one step queues that many reactions.
class HitsFixture:
	extends Command

	var count: int = 0

	func _init(sender: int, unit_id: String, hits: int) -> void:
		seat = sender
		actor_id = unit_id
		count = hits

	func resolve(session: CombatSession) -> void:
		for i: int in count:
			session.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, actor_id))
