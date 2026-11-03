# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_cases.gd
# Author:
# Created:  October 30, 2026
# Modified: November 3, 2026
# ==============================================================================

extends RefCounted
## Cases for the battle save (combat core plan CC8): [CombatUnitState] and [CombatState] capture,
## saved effect definitions ([EffectInstance] references, made and charge-free definitions), the
## [CombatStateSection] pair through a [SaveSectionRegistry], Save & Quit mid-phase then resume,
## mirrors after a weapon swap and a spawn, units on their way between maps, and a dump replayed
## from the middle of a battle.
##
## Run by [code]tests/sessions/run_all.gd[/code] on its first frame, after the wire cases, whose
## fixtures it reuses. Every save goes through JSON, as a file would. Several cases feed in bad data
## on purpose, so warnings and errors from them are expected.

# Preloaded scripts used as types (gdscript.md, Naming): the wire cases' fixtures (no class name).
const WireCases = preload("res://tests/sessions/wire_cases.gd")

const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const COMBAT: SaveSection.Block = SaveSection.Block.COMBAT

# The wire cases' run seed and node: these cases compare runs with each other, never with golden
# numbers.
const RUN_SEED: int = 0x3F9A12C077E1A
const FLOOR: int = 2
const NODE: int = 5

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_unit_state_round_trip()
	_test_combat_state_refusals()
	_test_carrier_references()
	_test_made_definitions()
	_test_charge_free_copy()
	_test_save_and_resume_same_facts()
	_test_staves_after_resume()
	_test_mirror_snapshot_after_swap_and_spawn()
	_test_mirror_follows_batches()
	_test_units_in_transit()
	_test_section_versions_and_partners()
	_test_core_kept_equal()
	_test_dump_replays_mid_battle()


func _test_unit_state_round_trip() -> void:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = "unit:7"
	unit.side = ENEMY
	unit.tile = Vector2i(3, 1)
	unit.movement_type = CombatGrid.MovementType.FLIER
	unit.tags = PackedStringArray(["flier", "beast"])
	unit.unit_type = "harpy"
	unit.hp = 11
	unit.block = 2
	unit.stance = 1
	unit.has_acted = true
	unit.tiles_moved = 3
	unit.movement_spent = 4
	unit.is_second_move_pending = true
	unit.has_been_shoved = true
	unit.has_used_sidearm = true
	unit.equipped_weapon_id = "item:2"
	unit.stowed_weapon_id = "item:3"
	unit.pouch_item_id = "item:4"
	unit.pouch_item_weight = 2
	unit.growth_changes = {CombatValue.Stat.RES: 5, CombatValue.Stat.MGT: 10}
	var data: Dictionary = WireCases.Kit.through_json(unit.capture()) as Dictionary
	var back: CombatUnitState = CombatUnitState.from_capture(data)
	_check.call("unit state: every field survives JSON, enums and growths by name", (
			back != null
			and back.capture() == unit.capture()
			and data["side"] == "ENEMY"
			and data["movement_type"] == "FLIER"
			and (data["growth_changes"] as Dictionary).has("RES")
			and typeof(back.hp) == TYPE_INT
	), str(data))
	var half: Dictionary = data.duplicate(true)
	half["hp"] = 2.5
	var side: Dictionary = data.duplicate(true)
	side["side"] = "MONSTER"
	var growth: Dictionary = data.duplicate(true)
	growth["growth_changes"] = {"LUCK": 5}
	_check.call("unit state: a fraction, an unknown side or stat is refused", (
			CombatUnitState.from_capture(half) == null
			and CombatUnitState.from_capture(side) == null
			and CombatUnitState.from_capture(growth) == null
			and CombatUnitState.from_capture({}) == null
	))


func _test_combat_state_refusals() -> void:
	var host: Skirmish = Skirmish.new()
	var data: Dictionary = WireCases.Kit.through_json(host.session.state.capture()) as Dictionary
	var copy: CombatState = CombatState.new(host.session.state.grid)
	_check.call("combat state: restores after JSON and captures again identically", (
			copy.restore(data) == OK
			and JSON.stringify(copy.capture()) == JSON.stringify(host.session.state.capture())
			and copy.occupant_at(host.session.state.tile_of(host.archer)) == host.archer
			and copy.weapon(host.bow_id) != null
			and not copy.map.opening_swap_open
	))
	var units: Array = data["units"]
	var repeated: Dictionary = data.duplicate(true)
	(repeated["units"] as Array).append((units[0] as Dictionary).duplicate(true))
	var stacked: Dictionary = data.duplicate(true)
	var moved: Dictionary = (stacked["units"] as Array)[1]
	moved["tile"] = ((stacked["units"] as Array)[0] as Dictionary)["tile"]
	var unarmed: Dictionary = data.duplicate(true)
	unarmed["weapons"] = []
	var before: String = JSON.stringify(copy.capture())
	_check.call("combat state: a repeated id, two units on a tile, a missing record are refused", (
			copy.restore(repeated) == ERR_INVALID_DATA
			and copy.restore(stacked) == ERR_INVALID_DATA
			and copy.restore(unarmed) == ERR_INVALID_DATA
			and copy.restore({}) == ERR_INVALID_DATA
			and JSON.stringify(copy.capture()) == before
	))


# Saved effects name their carrier and their own id, never a place in its list (event bus plan,
# question 60c); a unit type's upgraded trait is found too.
func _test_carrier_references() -> void:
	var archer: UnitTypeDefinition = EffectCatalog.unit_type("archer")
	var potion: ConsumableDefinition = EffectCatalog.consumable("potion")
	var volley: EffectDefinition = archer.effects[0]
	var volley_plus: EffectDefinition = archer.upgraded_effects[0]
	var heal: EffectDefinition = potion.effects[0]
	_check.call("references: <carrier id>#<effect id>, upgraded effects included", (
			EffectInstance.catalog_reference(volley) == "archer#volley"
			and EffectInstance.catalog_reference(volley_plus) == "archer#volley_plus"
			and EffectInstance.catalog_reference(heal) == "potion#heal"
	), "%s %s %s" % [
		EffectInstance.catalog_reference(volley),
		EffectInstance.catalog_reference(volley_plus),
		EffectInstance.catalog_reference(heal),
	])
	_check.call("references: each names its definition back, and a wrong one names none", (
			EffectInstance.catalog_definition("archer#volley") == volley
			and EffectInstance.catalog_definition("archer#volley_plus") == volley_plus
			and EffectInstance.catalog_definition("potion#heal") == heal
			and EffectInstance.catalog_definition("potion#0") == null
			and EffectInstance.catalog_definition("potion#") == null
			and EffectInstance.catalog_definition("nothing#heal") == null
	))


# A definition the loadout makes (value and permission changes, no catalog entry) travels inside
# its instance and comes back as itself.
func _test_made_definitions() -> void:
	var made: EffectDefinition = EffectDefinition.new()
	made.id = "prefix"
	var hit: ModifyValue = ModifyValue.new()
	hit.key = CombatValue.Key.HIT
	hit.value = 10.0
	var growth: ModifyValue = ModifyValue.new()
	growth.key = CombatValue.Key.MGT
	growth.mode = Modifier.Mode.MULTIPLY
	growth.value = 1.5
	var skirmish: SetPermission = SetPermission.new()
	skirmish.permission = CombatValue.Permission.MAY_MOVE_AFTER_ACTING
	made.operations.assign([hit, growth, skirmish])
	var uses: EffectDefinition = EffectDefinition.new()
	uses.id = "uses"
	uses.charges = 3
	var owner: EffectOwner = EffectOwner.for_item("item:4", "unit:1", 0, PLAYER)
	var prefix: EffectInstance = EffectInstance.new(
			"effect:9", made, owner, Modifier.SourceKind.WEAPON, "Keen"
	)
	var staff: EffectInstance = EffectInstance.new(
			"effect:10", uses, owner.copy(), Modifier.SourceKind.WEAPON, "Minor Heal"
	)
	staff.spend_charge()
	var prefix_data: Dictionary = WireCases.Kit.through_json(prefix.capture()) as Dictionary
	var staff_data: Dictionary = WireCases.Kit.through_json(staff.capture()) as Dictionary
	var none: Callable = func(_reference: String) -> EffectDefinition:
		return null
	var prefix_back: EffectInstance = EffectInstance.from_capture(prefix_data, none)
	var staff_back: EffectInstance = EffectInstance.from_capture(staff_data, none)
	_check.call("made: described in the capture and rebuilt without any lookup", (
			prefix_data.has("made")
			and prefix_back != null
			and prefix_back.definition != made
			and prefix_back.definition.id == "prefix"
			and prefix_back.capture() == prefix.capture()
			and staff_back != null
			and staff_back.definition.charges == 3
			and staff_back.charges_left == 2
			and staff_back.capture() == staff.capture()
	), str(prefix_data.get("made", {})))
	var mode_back: ModifyValue = prefix_back.definition.operations[1] as ModifyValue
	var permission_back: SetPermission = prefix_back.definition.operations[2] as SetPermission
	_check.call("made: keys, modes, values and permissions by name", (
			mode_back != null
			and mode_back.mode == Modifier.Mode.MULTIPLY
			and is_equal_approx(mode_back.value, 1.5)
			and permission_back != null
			and permission_back.permission == CombatValue.Permission.MAY_MOVE_AFTER_ACTING
			and permission_back.allow
	))
	var catalog_heal: EffectInstance = EffectInstance.new(
			"effect:11",
			EffectCatalog.consumable("potion").effects[0],
			owner.copy(),
			Modifier.SourceKind.POUCH_ITEM
	)
	var bad: Dictionary = prefix_data.duplicate(true)
	var bad_operations: Array = (bad["made"] as Dictionary)["operations"]
	bad_operations.append(["modify", "combat.NOPE", "ADD", 1, ""])
	print("    (errors about a malformed made definition follow)")
	_check.call("made: a catalog effect is never described, and a broken one is refused", (
			not catalog_heal.capture().has("made")
			and EffectInstance.from_capture(bad, none) == null
	))


# An enemy's charge-free copy of a charged use (Loadout._without_charges) is captured by its
# original's reference and restored as a charge-free copy again; the original is never changed.
func _test_charge_free_copy() -> void:
	var original: EffectDefinition = WireCases.Kit.counted_block("fixture_use", 3)
	original.charges = 2
	var copy: EffectDefinition = original.duplicate()
	copy.charges = 0
	var instance: EffectInstance = EffectInstance.new(
			"effect:3",
			copy,
			EffectOwner.for_item("item:8", "enemy:2", -1, ENEMY),
			Modifier.SourceKind.WEAPON
	)
	var data: Dictionary = WireCases.Kit.through_json(instance.capture()) as Dictionary
	var lookup: Callable = func(reference: String) -> EffectDefinition:
		return original if reference == "fixture_use" else null
	var back: EffectInstance = EffectInstance.from_capture(data, lookup)
	_check.call("charge-free: restored unlimited, the shared definition unchanged", (
			back != null
			and back.definition != original
			and back.definition.charges == 0
			and back.charges_left == -1
			and back.definition.operations == original.operations
			and original.charges == 2
			and not data.has("made")
	), str(data))


# The CC8 row's check: Save & Quit mid-phase, then resume, gives the same fact log as playing on,
# after a weapon swap, a spawn, a pending second move and a growth change.
func _test_save_and_resume_same_facts() -> void:
	var host: Skirmish = Skirmish.new()
	host.act(UnitTurnCommand.new(0, host.freewing, UnitTurnCommand.Action.SWAP_WEAPON, ""))
	var spawned: String = host.spawn()
	host.session.engine.add_growth(host.archer, CombatValue.Stat.RES, 5)
	host.session.flush("ingredient")
	host.attack_or_wait(host.archer)
	var saved: Dictionary = host.save()
	var saved_at: int = host.session.last_seq()
	var pending: bool = host.session.state.unit(host.freewing).is_second_move_pending

	var resumed: Skirmish = Skirmish.resume(saved, host)
	var resumed_state: CombatState = resumed.session.state
	var growths: Dictionary[int, int] = resumed_state.unit(host.archer).growth_changes
	_check.call("resume: the battle loads into a battle rebuilt as Begin set it up", (
			resumed.load_error == OK
			and pending
			and resumed_state.unit(host.freewing).is_second_move_pending
			and resumed_state.unit(host.freewing).equipped_weapon_id == host.bow_id
			and host.session.state.has_unit(spawned)
			and resumed_state.has_unit(spawned)
			and growths.size() == 1
			and growths.get(CombatValue.Stat.RES, 0) == 5
			and resumed.session.last_seq() == saved_at
			and resumed.session.state_hash() == host.session.state_hash()
	), "%s; %s" % [error_string(resumed.load_error), Skirmish.difference(host, resumed)])

	var host_batches: int = host.batches.size()
	var resumed_batches: int = resumed.batches.size()
	for field: Skirmish in [host, resumed]:
		field.second_move(host.freewing)
		field.act(EndTurnCommand.new(0))
		field.attack_or_wait(host.freewing)
		field.attack_or_wait(host.archer)
		field.act(EndTurnCommand.new(0))
	var host_facts: Array = host.facts_after(saved_at)
	var resumed_facts: Array = resumed.facts_after(saved_at)
	var rejected: int = 0
	for batch: CombatSession.FactBatch in host.batches.slice(host_batches):
		rejected += 1 if batch.is_rejected() else 0
	for batch: CombatSession.FactBatch in resumed.batches.slice(resumed_batches):
		rejected += 1 if batch.is_rejected() else 0
	_check.call("resume: playing on gives the same facts, the second move included", (
			not host_facts.is_empty()
			and JSON.stringify(resumed_facts) == JSON.stringify(host_facts)
			and rejected == 0
			and host.moved_after(saved_at, host.freewing)
			and resumed.session.state_hash() == host.session.state_hash()
	), "%d and %d facts, %d rejected" % [host_facts.size(), resumed_facts.size(), rejected])
	_check.call("resume: ids minted after it match the original run's", (
			WireCases.Kit.mint(resumed.run.ids) == WireCases.Kit.mint(host.run.ids)
	))


# Staves through the real catalog's Minor Heal: a player's per-map uses stay spent after a resume,
# and an enemy's staff, which the loadout gives no uses, still heals (enemies and AI plan,
# question 18e). Both use effects restore as themselves, never from the catalog.
func _test_staves_after_resume() -> void:
	var host: Infirmary = Infirmary.new()
	for i: int in Infirmary.STAFF_USES:
		host.heal_both()
	var taken: Dictionary = WireCases.Kit.through_json(host.session.snapshot()) as Dictionary
	var copy: Infirmary = Infirmary.new(host)
	var loaded: Error = copy.session.load_snapshot(taken)
	var difference: String = Skirmish.difference_of(host.session, copy.session)
	var uses: EffectInstance = copy.uses_of(copy.medic)
	var healed: Dictionary[String, bool] = copy.heal_both()
	_check.call("staves: a snapshot of loaded units restores with no lookup but the catalog", (
			loaded == OK
			and difference == "same"
			and uses != null
			and uses.definition.id == "uses"
			and uses.definition.charges == Infirmary.STAFF_USES
			and uses.charges_left == 0
	), "%s; %s" % [error_string(loaded), difference])
	_check.call("staves: an enemy's staff still heals after its per-map uses, a player's doesn't", (
			copy.uses_of(copy.enemy_medic) == null
			and healed[copy.enemy_medic]
			and not healed[copy.medic]
	), str(healed))


func _test_mirror_snapshot_after_swap_and_spawn() -> void:
	var host: Skirmish = Skirmish.new()
	host.act(UnitTurnCommand.new(0, host.freewing, UnitTurnCommand.Action.SWAP_WEAPON, ""))
	host.spawn()
	var mirror: CombatSession = Skirmish.bare_session()
	var loaded: Error = mirror.load_snapshot(
			WireCases.Kit.through_json(host.session.snapshot()) as Dictionary
	)
	_check.call("mirror: a snapshot after a swap and a spawn hashes as the host does", (
			loaded == OK
			and mirror.state_hash() == host.session.state_hash()
			and mirror.stats(host.freewing).get_int(CombatValue.Key.RANGE_MAX)
			== host.session.stats(host.freewing).get_int(CombatValue.Key.RANGE_MAX)
	), error_string(loaded))


# A mirror loaded once follows, hash for hash after every batch: a move that spends movement and a
# weapon swap (its bases and a pending second move), a reinforcement spawn with no snapshot, the
# move after acting, a whole turn of both sides and attacks (combat core plan, question 20).
func _test_mirror_follows_batches() -> void:
	var host: Skirmish = Skirmish.new()
	var mirror: CombatSession = Skirmish.bare_session()
	mirror.load_snapshot(WireCases.Kit.through_json(host.session.snapshot()) as Dictionary)
	var results: Array[Error] = []
	var sent: int = host.batches.size()
	host.act(UnitTurnCommand.new(
			0,
			host.freewing,
			UnitTurnCommand.Action.SWAP_WEAPON,
			"",
			host.step_path(host.freewing)
	))
	results.append_array(Skirmish.apply_since(host, mirror, sent))
	var walked: CombatUnitState = mirror.state.unit(host.freewing)
	_check.call("mirror: a move that spends movement and an action leaving a move pending", (
			results == [OK]
			and walked.tiles_moved == 1
			and walked.movement_spent > 0
			and walked.movement_spent == host.session.state.unit(host.freewing).movement_spent
			and walked.is_second_move_pending
			and walked.equipped_weapon_id == host.bow_id
			and mirror.state_hash() == host.session.state_hash()
	), str(results))

	sent = host.batches.size()
	var spawned: String = host.spawn()
	results = Skirmish.apply_since(host, mirror, sent)
	_check.call("mirror: a reinforcement spawn is placed from its batch, no snapshot needed", (
			results == [OK]
			and not host.batches[sent].spawned.is_empty()
			and mirror.state.has_unit(spawned)
			and mirror.state.tile_of(spawned) == host.session.state.tile_of(spawned)
			and mirror.bases_of(spawned) == host.session.bases_of(spawned)
			and mirror.state_hash() == host.session.state_hash()
	), str(results))

	sent = host.batches.size()
	host.second_move(host.freewing)
	results = Skirmish.apply_since(host, mirror, sent)
	var moved: CombatUnitState = mirror.state.unit(host.freewing)
	_check.call("mirror: the move after acting adds its tiles and ends the pending move", (
			results == [OK]
			and moved.tiles_moved == 2
			and not moved.is_second_move_pending
			and mirror.state_hash() == host.session.state_hash()
	), str(results))

	sent = host.batches.size()
	host.attack_or_wait(host.archer)
	host.act(EndTurnCommand.new(0))
	host.attack_or_wait(host.freewing)
	host.attack_or_wait(host.archer)
	results = Skirmish.apply_since(host, mirror, sent)
	_check.call("mirror: a turn of both sides and attacks, hash for hash", (
			results.count(OK) == results.size()
			and results.size() >= 4
			and mirror.state_hash() == host.session.state_hash()
			and mirror.state.turn == host.session.state.turn
	), str(results))


# Units sent from a won map are in the snapshot on their way, with their bases, weapons and effects,
# and arrive the same after a load (combat_encounter.gd's former TOD-001).
func _test_units_in_transit() -> void:
	var host: WireCases.Bridge = WireCases.Bridge.new(PackedInt32Array([0, 1]), true)
	var copy: WireCases.Bridge = WireCases.Bridge.new(PackedInt32Array([0, 1]), true)
	host.attack_all(0)
	var won: CombatSession = host.battle.get_session(0)
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	won.engine.record(ended)
	won.flush("won")
	var sent_id: String = host.units[0][0]
	var reason: String = host.battle.send_unit(sent_id, 0, 1, Vector2i(0, 3))
	var counter: int = 0
	for instance: EffectInstance in won.engine.get_instances():
		counter += 0 if instance.owner.holder_id != sent_id else 1
	var taken: Dictionary = WireCases.Kit.through_json(host.battle.snapshot()) as Dictionary
	print("    (no warning about units left out of a snapshot should follow)")
	var loaded: Error = copy.battle.load_snapshot(taken, copy.lookup())
	_check.call("transit: a unit on its way is in the snapshot and loads", (
			reason.is_empty()
			and counter == 0
			and loaded == OK
			and copy.battle.units_in_transit() == PackedStringArray([sent_id])
			and copy.battle.state_hash() == host.battle.state_hash()
	), "%s, %s" % [reason, error_string(loaded)])
	var host_arrived: PackedStringArray = host.battle.deliver_arrivals(1)
	var copy_arrived: PackedStringArray = copy.battle.deliver_arrivals(1)
	var host_map: CombatSession = host.battle.get_session(1)
	var copy_map: CombatSession = copy.battle.get_session(1)
	_check.call("transit: it arrives the same, with its effects and their counters", (
			host_arrived == PackedStringArray([sent_id])
			and copy_arrived == host_arrived
			and copy_map.state.tile_of(sent_id) == host_map.state.tile_of(sent_id)
			and copy_map.state_hash() == host_map.state_hash()
			and copy_map.bases_of(sent_id) == host_map.bases_of(sent_id)
	))


func _test_section_versions_and_partners() -> void:
	var host: Skirmish = Skirmish.new()
	var saved: Dictionary = host.save()
	var entry: Dictionary = saved["combat_state"]
	var effects_entry: Dictionary = saved["effects"]
	_check.call("section: both keys at version 1, the roll streams left to the rng section", (
			WireCases.Kit.as_int(entry["version"]) == 1
			and WireCases.Kit.as_int(effects_entry["version"]) == 1
			and not JSON.stringify(entry["data"]).contains("\"rolls\"")
	))
	var newer: Dictionary = saved.duplicate(true)
	(newer["combat_state"] as Dictionary)["version"] = 2
	var zero: Dictionary = saved.duplicate(true)
	(zero["effects"] as Dictionary)["version"] = 0
	var effects_only: Dictionary = saved.duplicate(true)
	effects_only.erase("combat_state")
	var broken: Dictionary = saved.duplicate(true)
	var broken_data: Dictionary = (broken["combat_state"] as Dictionary)["data"]
	var broken_maps: Array = broken_data["sessions"]
	((broken_maps[0] as Dictionary)["combat_state"] as Dictionary)["turn"] = 1.5
	print("    (errors about refused combat sections follow)")
	var results: Array[Error] = []
	var holding: Array[bool] = []
	for sections: Dictionary in [newer, zero, effects_only, broken]:
		var registry: Registry = Registry.new()
		results.append(registry.sections.restore(COMBAT, sections))
		holding.append(registry.combat_state.is_holding())
	_check.call("section: a newer version, version 0, effects alone, a broken unit are refused", (
			results == [
				ERR_FILE_UNRECOGNIZED, ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA,
			]
			and not holding.has(true)
	), str(results))

	var state_only: Dictionary = saved.duplicate(true)
	state_only.erase("effects")
	var partial: Registry = Registry.new()
	var partial_result: Error = partial.sections.restore(COMBAT, state_only)
	var empty: Registry = Registry.new()
	var empty_result: Error = empty.sections.restore(COMBAT, {})
	var battle: CombatEncounter = Skirmish.new(false).battle
	_check.call("section: a missing section holds no battle, which restarts from Begin", (
			partial_result == OK
			and partial.combat_state.load_into(battle) == ERR_UNCONFIGURED
			and empty_result == OK
			and empty.combat_state.load_into(battle) == ERR_UNCONFIGURED
			and empty.combat_state.capture().is_empty()
	))
	var full: Registry = Registry.new()
	full.sections.restore(COMBAT, saved)
	var recaptured: Dictionary = WireCases.Kit.through_json(
			full.sections.capture(COMBAT, {})
	) as Dictionary
	_check.call("section: held data is saved again unchanged before it is loaded", (
			full.combat_state.is_holding()
			and JSON.stringify(recaptured["combat_state"]) == JSON.stringify(saved["combat_state"])
			and JSON.stringify(recaptured["effects"]) == JSON.stringify(saved["effects"])
	))


func _test_core_kept_equal() -> void:
	var core: CombatData = CombatData.new()
	core.turn = 9
	var provider: Callable = func() -> CombatData:
		return core
	var opening: Skirmish = Skirmish.new(true, false)
	var section: CombatStateSection = CombatStateSection.new(provider)
	section.attach(opening.run)
	section.capture()
	var in_window: Array = [core.turn, core.phase]
	opening.act(StartCommand.new(0))
	opening.act(EndTurnCommand.new(0))
	section.capture()
	_check.call("core: the combat block's turn and phase follow the battle's", (
			in_window == [1, CombatData.Phase.PLAYER]
			and core.turn == 2
			and opening.session.state.turn == 2
			and core.phase == CombatData.Phase.PLAYER
	), "%s, then turn %d" % [in_window, core.turn])


# A dump taken after a checkpoint in the middle of a battle replays from that checkpoint
# (combat_session.gd's former TOD-001).
func _test_dump_replays_mid_battle() -> void:
	var host: Skirmish = Skirmish.new()
	host.act(UnitTurnCommand.new(0, host.freewing, UnitTurnCommand.Action.SWAP_WEAPON, ""))
	host.attack_or_wait(host.archer)
	host.session.mark_checkpoint()
	host.second_move(host.freewing)
	host.act(EndTurnCommand.new(0))
	host.attack_or_wait(host.freewing)
	var path: String = host.session.debug_dump()
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(path) if not path.is_empty() else ""
	)
	var dump: Dictionary = parsed if parsed is Dictionary else {}
	var snapshot: Dictionary = dump.get("snapshot", {})
	var again: Skirmish = Skirmish.new(false)
	var loaded: Error = again.session.load_snapshot(snapshot)
	for wire: Variant in dump.get("commands", []):
		again.session.submit(Command.from_wire(wire as Array))
	again.session.resolve_queued()
	var snapshot_session: Dictionary = snapshot.get("session", {})
	var base: int = WireCases.Kit.as_int(snapshot_session.get("last_seq"))
	var recorded: Array = []
	for wire: Variant in dump.get("facts", []):
		recorded.append(CombatFact.from_wire(wire as Array).to_wire())
	_check.call("dump: replays from a checkpoint in the middle of a battle", (
			loaded == OK
			and base > 0
			and (dump.get("commands", []) as Array).size() == 3
			and not recorded.is_empty()
			and JSON.stringify(again.facts_after(base)) == JSON.stringify(recorded)
			and again.session.state_hash() == host.session.state_hash()
	), "%s, %d facts" % [error_string(loaded), recorded.size()])
	if not path.is_empty():
		DirAccess.remove_absolute(path)


# One map begun through the campaign bridge on the fixture map: a Freewing (sword in hand, bow
# stowed, "may move after acting") and an Archer, then a sword-wielding Brute at the enemy slot,
# placed in the opening swap window, then the seat's Start. Built the same way every time, ids
# included.
class Skirmish:
	extends RefCounted

	var run: CampaignSession = null
	var battle: CombatEncounter = null
	var session: CombatSession = null
	var batches: Array[CombatSession.FactBatch] = []
	var freewing: String = ""
	var archer: String = ""
	var bow_id: String = ""
	var enemy: String = ""
	## The result of loading a save, for a resumed battle; OK otherwise.
	var load_error: Error = OK

	var _sections: Registry = null

	## [param is_set_up]: the enemy is placed. [param is_started]: the seat sends Start.
	## [param saved]: for [method resume], the COMBAT block sections to load once it is rebuilt.
	func _init(is_set_up: bool = true, is_started: bool = true, saved: Dictionary = {}) -> void:
		run = CampaignSession.new(CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0]))
		_sections = Registry.new()
		if saved.is_empty():
			_sections.attach(run)
		else:
			# The streams go on from the save before the battle draws, as CampaignService attaches
			# its sections. The id counter waits until the battle is rebuilt as at Begin (below).
			load_error = _sections.sections.restore(COMBAT, saved)
			_sections.rng.attach(run)
			_sections.combat_state.attach(run)
			_sections.combat_map.attach(run)
		var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
		request.floor_number = FLOOR
		request.node = NODE
		var map: CombatMapDefinition = CombatMapDefinition.new()
		map.id = "map_a"
		map.scene = FIXTURE_SCENE
		request.pool.append(map)
		var army: CampaignSession.Army = CampaignSession.Army.new()
		var sword: CombatState.WeaponStats = WireCases.Kit.weapon(
				run.ids.next_item_id("Sword"), "sword"
		)
		var bow: CombatState.WeaponStats = WireCases.Kit.weapon(run.ids.next_item_id("Bow"), "bow")
		var other_bow: CombatState.WeaponStats = WireCases.Kit.weapon(
				run.ids.next_item_id("Bow"), "bow"
		)
		bow_id = bow.id
		army.weapons.assign([sword, bow, other_bow])
		var first: CombatUnitState = _unit("Freewing", sword.id)
		first.stowed_weapon_id = bow.id
		var second: CombatUnitState = _unit("Archer", other_bow.id)
		freewing = first.id
		archer = second.id
		army.units.assign([first, second])
		for unit: CombatUnitState in army.units:
			army.bases[unit.id] = WireCases.Kit.bases(20.0)
		request.armies[0] = army
		request.opening_swap[0] = true
		run.add_carrier(EffectInstance.new(
				run.ids.next_effect_id("Skirmisher"),
				Skirmish.skirmisher(),
				EffectOwner.for_unit(freewing, 0, PLAYER),
				Modifier.SourceKind.UNIT_TRAIT,
				"Skirmisher"
		))
		battle = run.begin_battle(request)
		session = battle.get_session(0)
		session.batch_resolved.connect(_on_batch_resolved)
		if not saved.is_empty():
			# The maps first, then the battle, whose reload carries them (CombatMapSection).
			if load_error == OK:
				load_error = _sections.combat_map.load_into(battle)
			if load_error == OK:
				load_error = _sections.combat_state.load_into(battle)
			# The resume flow sets the battle's id counter again once the battle is rebuilt.
			var counter: Dictionary = (saved["instance_ids"] as Dictionary)["data"]
			run.ids.restore(counter)
			return
		if not is_set_up:
			return
		var enemy_sword: CombatState.WeaponStats = WireCases.Kit.weapon(
				run.ids.next_item_id("Sword"), "sword"
		)
		session.state.add_weapon(enemy_sword)
		var brute: CombatUnitState = CombatUnitState.new()
		brute.id = run.ids.next_enemy_id("Brute")
		brute.side = ENEMY
		brute.tile = Vector2i(3, 2)
		brute.hp = 40
		brute.equipped_weapon_id = enemy_sword.id
		session.add_unit(brute, WireCases.Kit.bases(40.0))
		session.flush("enemies")
		session.mark_checkpoint()
		enemy = brute.id
		if is_started:
			act(StartCommand.new(0))

	## A battle rebuilt as Begin set up [param like]'s, with [param saved] (from [method save])
	## loaded into it, as a resumed battle is.
	static func resume(saved: Dictionary, like: Skirmish) -> Skirmish:
		var resumed: Skirmish = Skirmish.new(false, false, saved)
		resumed.enemy = like.enemy
		return resumed

	## A session on the fixture map with nothing on it: a client's mirror before its snapshot.
	static func bare_session() -> CombatSession:
		var grid: MapGrid = MapGrid.new(WireCases.Kit.fixture_layout())
		return CombatSession.new(
				0,
				PackedInt32Array([0]),
				grid,
				LiveRolls.new(RngStream.new(0)),
				InstanceIdAllocator.new()
		)

	## Which snapshot parts of two fields' maps differ, for a failing case's detail.
	static func difference(first: Skirmish, second: Skirmish) -> String:
		return Skirmish.difference_of(first.session, second.session)

	## Which snapshot parts of two maps differ, rolls left out.
	static func difference_of(first: CombatSession, second: CombatSession) -> String:
		var a: Dictionary = first.snapshot()
		var b: Dictionary = second.snapshot()
		var parts: PackedStringArray = []
		for part: String in ["session", "combat_state", "effects"]:
			var a_text: String = JSON.stringify(a.get(part), "", true)
			var b_text: String = JSON.stringify(b.get(part), "", true)
			if a_text == b_text:
				continue
			var at: int = 0
			while at < mini(a_text.length(), b_text.length()) and a_text[at] == b_text[at]:
				at += 1
			parts.append("%s differs at: %s | %s" % [
				part, a_text.substr(maxi(0, at - 60), 140), b_text.substr(maxi(0, at - 60), 140),
			])
		return "same" if parts.is_empty() else "; ".join(parts)

	## "May move after acting" (Skirmisher): a definition no catalog has, as the loadout makes.
	static func skirmisher() -> EffectDefinition:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = "skirmisher"
		var permission: SetPermission = SetPermission.new()
		permission.permission = CombatValue.Permission.MAY_MOVE_AFTER_ACTING
		definition.operations.append(permission)
		return definition

	## The COMBAT block's sections now, through a registry and JSON, as a combat file holds them.
	func save() -> Dictionary:
		return WireCases.Kit.through_json(_sections.sections.capture(COMBAT, {})) as Dictionary

	func act(command: Command) -> void:
		session.submit(command)
		session.resolve_queued()

	## [param unit_id] attacks the enemy if its weapon reaches it, else waits.
	func attack_or_wait(unit_id: String) -> void:
		var stats: StatSheet = session.stats(unit_id)
		var distance: int = session.engine.tile_distance(unit_id, enemy)
		var reaches: bool = (
				distance >= stats.get_int(CombatValue.Key.RANGE_MIN)
				and distance <= stats.get_int(CombatValue.Key.RANGE_MAX)
		)
		var action: UnitTurnCommand.Action = (
				UnitTurnCommand.Action.ATTACK if reaches else UnitTurnCommand.Action.WAIT
		)
		act(UnitTurnCommand.new(0, unit_id, action, enemy if reaches else ""))

	## [param unit_id]'s move after acting, one step to the first free tile next to it.
	func second_move(unit_id: String) -> void:
		act(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.MOVE, "", step_path(unit_id)))

	## A path of one step from [param unit_id]'s tile to the first free tile next to it.
	func step_path(unit_id: String) -> Array[Vector2i]:
		var state: CombatState = session.state
		var from: Vector2i = state.tile_of(unit_id)
		var movement: CombatGrid.MovementType = state.unit(unit_id).movement_type
		for next: Vector2i in state.grid.neighbors(from):
			if state.occupant_at(next).is_empty() and state.can_stand(next, movement):
				return [from, next]
		return [from]

	## Applies every batch [param host] sent from index [param from] on to [param mirror], each
	## after a trip through JSON. Returns each result.
	static func apply_since(host: Skirmish, mirror: CombatSession, from: int) -> Array[Error]:
		var results: Array[Error] = []
		for batch: CombatSession.FactBatch in host.batches.slice(from):
			results.append(mirror.apply_batch(WireCases.Kit.batch_through_json(batch)))
		return results

	## A second Brute arriving mid-phase on the free tile nearest the first, as a reinforcement
	## does. Returns its id.
	func spawn() -> String:
		var sword: CombatState.WeaponStats = WireCases.Kit.weapon(
				run.ids.next_item_id("Sword"), "sword"
		)
		session.state.add_weapon(sword)
		var brute: CombatUnitState = CombatUnitState.new()
		brute.id = run.ids.next_enemy_id("Brute")
		brute.side = ENEMY
		brute.hp = 40
		brute.equipped_weapon_id = sword.id
		brute.tile = Pathing.nearest_free_tile(
				session.state, session.state.tile_of(enemy), CombatGrid.MovementType.DEFAULT
		)
		session.add_unit(brute, WireCases.Kit.bases(40.0))
		session.flush("reinforcement")
		return brute.id

	## Every fact after [param seq], as wire arrays.
	func facts_after(seq: int) -> Array:
		var wires: Array = []
		for fact: CombatFact in session.engine.fact_log:
			if fact.seq > seq:
				wires.append(fact.to_wire())
		return wires

	## Whether [param unit_id] moved after [param seq].
	func moved_after(seq: int, unit_id: String) -> bool:
		for fact: CombatFact in session.engine.fact_log:
			var is_move: bool = fact.kind == CombatFact.Kind.UNIT_MOVED
			if fact.seq > seq and is_move and fact.actor_id == unit_id:
				return true
		return false

	func _unit(unit_type: String, weapon_id: String) -> CombatUnitState:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = run.ids.next_unit_id(unit_type)
		unit.seat = 0
		unit.unit_type = unit_type
		unit.hp = 20
		unit.equipped_weapon_id = weapon_id
		return unit

	func _on_batch_resolved(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)


# The COMBAT block's sections registered as CampaignService registers them: rng, instance ids,
# combat_state and effects, then combat_map and entities. SaveService reserves entities first, so
# its slot comes before every other section here, as it does in a real save.
class Registry:
	extends RefCounted

	var sections: SaveSectionRegistry = SaveSectionRegistry.new()
	var rng: RngSaveSection = RngSaveSection.new(COMBAT)
	var ids: InstanceIdSaveSection = InstanceIdSaveSection.new(COMBAT)
	var combat_state: CombatStateSection = CombatStateSection.new()
	var combat_map: CombatMapSection = CombatMapSection.new()

	func _init() -> void:
		combat_state.resolve = Registry.find_definition
		sections.register(COMBAT, RawSaveSection.new("entities"))
		sections.register(COMBAT, rng)
		sections.register(COMBAT, ids)
		sections.register(COMBAT, combat_state)
		sections.register(COMBAT, combat_state.effects)
		sections.register(COMBAT, combat_map)
		sections.register(COMBAT, combat_map.entities)

	func attach(run: CampaignSession) -> void:
		rng.attach(run)
		ids.attach(run)
		combat_state.attach(run)
		combat_map.attach(run)

	## A saved effect's definition as CampaignService finds it: a map object's reaction, else the
	## catalog's.
	static func find_definition(reference: String) -> EffectDefinition:
		var own: EffectDefinition = MapObjects.map_definition(reference)
		return own if own != null else EffectInstance.catalog_definition(reference)


# A map with two Battle Medics loaded through the real catalog with a Minor Heal each (3 uses per
# map), one a player's and one an enemy's, each next to a wounded ally of its side.
class Infirmary:
	extends RefCounted

	## Minor Heal's uses per map (data/items/weapons/staff/minor_heal.tres).
	const STAFF_USES: int = 3

	var session: CombatSession = null
	var medic: String = ""
	var enemy_medic: String = ""
	var _patients: Dictionary[String, String] = {}

	## [param like]: null loads and places the units; else the map is empty for a snapshot of
	## [param like], whose ids it names its units by.
	func _init(like: Infirmary = null) -> void:
		session = Skirmish.bare_session()
		if like != null:
			medic = like.medic
			enemy_medic = like.enemy_medic
			_patients = like._patients.duplicate()
			return
		var ids: InstanceIdAllocator = session.ids
		medic = _load(ids.next_unit_id("Battle Medic"), PLAYER, 0, Vector2i(1, 1), ids)
		enemy_medic = _load(ids.next_enemy_id("Battle Medic"), ENEMY, -1, Vector2i(3, 1), ids)
		_patients[medic] = _patient(ids.next_unit_id("Archer"), PLAYER, 0, Vector2i(1, 2))
		_patients[enemy_medic] = _patient(ids.next_enemy_id("Brute"), ENEMY, -1, Vector2i(4, 1))

	## Each medic heals its wounded ally once; returns whether each one's heal landed, by medic.
	func heal_both() -> Dictionary[String, bool]:
		var landed: Dictionary[String, bool] = {}
		for healer: String in [medic, enemy_medic]:
			var before: int = session.engine.fact_log.size()
			var seat: int = session.state.seat_of(healer)
			session.submit(HealFixture.new(healer, _patients[healer], seat))
			session.resolve_queued()
			landed[healer] = false
			for i: int in range(before, session.engine.fact_log.size()):
				var fact: CombatFact = session.engine.fact_log[i]
				if fact.kind == CombatFact.Kind.HEALED and fact.actor_id == _patients[healer]:
					landed[healer] = true
		return landed

	## The use effect counting [param unit_id]'s staff's uses; null when it has none.
	func uses_of(unit_id: String) -> EffectInstance:
		var staff_id: String = session.state.equipped_weapon_id(unit_id)
		var found: Array[EffectInstance] = ItemUseResolver.use_effects(session.engine, staff_id)
		return null if found.is_empty() else found[0]

	func _load(
			id: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i,
			ids: InstanceIdAllocator
	) -> String:
		var staff_id: String = ids.next_item_id("Minor Heal")
		var unit: UnitInstance = UnitInstance.new(id, "battle_medic")
		unit.weapon_id = staff_id
		var items: Dictionary[String, ItemInstance] = {
			staff_id: ItemInstance.new(staff_id, "minor_heal"),
		}
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(
				EffectCatalog.index(), unit, items, side, seat, ids
		)
		for record: CombatState.WeaponStats in loaded.weapons:
			session.state.add_weapon(record)
		for instance: EffectInstance in loaded.effects:
			session.engine.register(instance)
		loaded.state.tile = tile
		session.add_unit(loaded.state, loaded.bases)
		return id

	func _patient(id: String, side: CombatFact.CombatSide, seat: int, tile: Vector2i) -> String:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.hp = 20
		session.add_unit(unit, WireCases.Kit.bases(20.0))
		return id


# One staff use by its unit on a wounded ally, as a staff command resolves one; the turn is reset
# and the ally wounded first, so a staff can be used again and always has someone to heal.
class HealFixture:
	extends Command

	var target: String = ""

	func _init(unit_id: String, target_id: String, unit_seat: int) -> void:
		actor_id = unit_id
		target = target_id
		seat = unit_seat

	func get_label() -> String:
		return "heal"

	func resolve(session: CombatSession) -> void:
		session.state.unit(actor_id).has_acted = false
		session.state.set_hp(target, 1)
		StaffResolver.resolve(session.engine, session.state, actor_id, target)
