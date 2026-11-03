# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     wire_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: November 3, 2026
# ==============================================================================

extends RefCounted
## Cases for serialization, rejoin and repro (event bus plan EB7): commands and batches on the wire,
## snapshots of sessions and the encounter, client mirrors, repro dumps and the
## [InstanceIdSaveSection]s.
##
## Run by [code]tests/sessions/run_all.gd[/code] on its first frame. Mirrors are tested with
## several sessions in one process: a mirror is built the way its host was, then follows the host
## only through snapshots and batches that went through JSON, as a client's would. Several cases
## feed in bad data on purpose, so warnings and errors from them are expected.

const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Any fixed seeds and node: these cases compare runs with each other, never with golden numbers.
const STREAM_SEED: int = 0x5EED
const RUN_SEED: int = 0x3F9A12C077E1A
const FLOOR: int = 2
const NODE: int = 5

# Weapon presets from tests/combat/combat_world.gd: damage, AtkX, range min, range max, Hit, weight.
const PRESETS: Dictionary[String, Array] = {
	"sword": [5, 1, 1, 1, 80, 8],
	"gauntlets": [2, 2, 1, 1, 100, 1],
	"bow": [6, 1, 2, 3, 100, 5],
}

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_command_wire()
	_test_batch_wire()
	_test_snapshot_round_trip()
	_test_snapshot_refusals()
	_test_mirror_from_snapshot_and_catch_up()
	_test_mirror_resent_and_gap()
	_test_mirror_divergence()
	_test_modifier_gained_mid_attack()
	_test_multi_use_modifier_over_exchange()
	_test_dump_replay()
	_test_ids_after_resume()
	_test_id_section_rules()
	_test_encounter_snapshot()


func _test_command_wire() -> void:
	var walk: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3), Vector2i(1, 2)]
	var turn: UnitTurnCommand = UnitTurnCommand.new(
			1, "unit:3", UnitTurnCommand.Action.ATTACK, "enemy:4", walk
	)
	turn.item_id = "item:9"
	turn.weapon_id = "item:5"
	turn.based_on_seq = 12
	turn.arrival = 7
	var commands: Array[Command] = [
		turn,
		StartCommand.new(0),
		EndTurnCommand.new(2),
		CastRuneCommand.new(0, "rune:8", "unit:3", "unit:6"),
	]
	var same: bool = true
	for command: Command in commands:
		var back: Command = Command.from_wire(Kit.through_json(command.to_wire()) as Array)
		same = same and back != null and back.get_script() == command.get_script()
		same = same and back.to_wire() == command.to_wire()
	_check.call("wire: every command type survives JSON, whole floats read as ints", same)
	var read: UnitTurnCommand = Command.from_wire(
			Kit.through_json(turn.to_wire()) as Array
	) as UnitTurnCommand
	_check.call("wire: a unit turn keeps its path, action and ids", (
			read != null
			and read.path == walk
			and read.action == UnitTurnCommand.Action.ATTACK
			and read.seat == 1
			and typeof(read.seat) == TYPE_INT
			and read.based_on_seq == 12
			and read.item_id == "item:9"
			and read.weapon_id == "item:5"
	))

	print("    (warnings about malformed command data follow)")
	var half: Array = turn.to_wire()
	half[1] = 1.5
	var odd_path: Array = turn.to_wire()
	odd_path[9] = [0, 3, 1]
	var bad_action: Array = turn.to_wire()
	bad_action[5] = 99
	_check.call("wire: a fraction, an unknown type or action and a broken path are refused", (
			Command.from_wire(half) == null
			and Command.from_wire(["teleport", 0, "", -1, 0]) == null
			and Command.from_wire(bad_action) == null
			and Command.from_wire(odd_path) == null
			and Command.from_wire([]) == null
	))


func _test_batch_wire() -> void:
	var field: Field = Field.new()
	field.exchange(1)
	var batch: CombatSession.FactBatch = field.batches[field.batches.size() - 1]
	var back: CombatSession.FactBatch = Kit.batch_through_json(batch)
	_check.call("wire: a batch survives JSON with its facts and state hash", (
			back != null
			and not batch.facts.is_empty()
			and back.to_wire() == batch.to_wire()
			and back.state_hash == batch.state_hash
			and batch.state_hash != CombatSession.NO_HASH
			and back.facts[0].seq == batch.facts[0].seq
			and typeof(back.facts[0].seq) == TYPE_INT
	))
	print("    (warnings about malformed batch data follow)")
	var bad: Array = batch.to_wire()
	bad[2] = 0.5
	var bad_fact: Array = batch.to_wire()
	(bad_fact[10] as Array).append([1, 2])
	_check.call("wire: a batch with a fraction or a broken fact is refused", (
			CombatSession.FactBatch.from_wire(bad) == null
			and CombatSession.FactBatch.from_wire(bad_fact) == null
	))


func _test_snapshot_round_trip() -> void:
	var host: Field = Field.new()
	host.exchange(2)
	var taken: Dictionary = host.session.snapshot()
	var text: String = JSON.stringify(taken, "", true)
	var copy: Field = Field.new()
	var loaded: Error = copy.session.load_snapshot(
			JSON.parse_string(text) as Dictionary, copy.lookup()
	)
	var copy_uses: PackedInt32Array = []
	for timed: TimedModifier in copy.session.engine.get_timed_modifiers(copy.hero):
		copy_uses.append(timed.uses_left)
	var host_uses: PackedInt32Array = []
	for timed: TimedModifier in host.session.engine.get_timed_modifiers(host.hero):
		host_uses.append(timed.uses_left)
	_check.call("snapshot: loads after JSON and captures again identically", (
			loaded == OK
			and JSON.stringify(copy.session.snapshot(), "", true) == text
			and copy.session.state_hash() == host.session.state_hash()
	), error_string(loaded))
	_check.call("snapshot: counters, charges, deltas and timed modifiers come back", (
			copy.counter_of(copy.block_id) == host.counter_of(host.block_id)
			and copy.session.engine.get_instance(copy.boost_id).charges_left
			== host.session.engine.get_instance(host.boost_id).charges_left
			and copy.session.engine.get_deltas(copy.hero, CombatValue.Key.MGT).size()
			== host.session.engine.get_deltas(host.hero, CombatValue.Key.MGT).size()
			and not host_uses.is_empty()
			and copy_uses == host_uses
	), "uses %s and %s" % [copy_uses, host_uses])
	_check.call("snapshot: names the run seed, the build and the roll stream", (
			taken["run_seed"] == RunSeed.format(0)
			and taken["game_version"] == ProjectSettings.get_setting("application/config/version")
			and (taken["rolls"] as String).length() == 16
			and copy.session.last_seq() == host.session.last_seq()
	))
	# The units' HP and tiles aren't in a snapshot until P02 CC8, so only the stream is compared.
	var copy_rolls: LiveRolls = copy.session.engine.rolls as LiveRolls
	var host_rolls: LiveRolls = host.session.engine.rolls as LiveRolls
	_check.call("snapshot: a loaded session's roll stream goes on where the host's is", (
			copy_rolls.capture() == host_rolls.capture()
			and copy_rolls.roll_percent(50) == host_rolls.roll_percent(50)
			and copy_rolls.capture() == host_rolls.capture()
	))


func _test_snapshot_refusals() -> void:
	var host: Field = Field.new()
	host.exchange(1)
	var data: Dictionary = Kit.through_json(host.session.snapshot()) as Dictionary
	var target: Field = Field.new()
	var before: String = JSON.stringify(target.session.snapshot(), "", true)
	print("    (errors about snapshots that can't load follow)")
	var other_map: Dictionary = data.duplicate(true)
	(other_map["session"] as Dictionary)["session_id"] = 3
	var unknown: Callable = func(_reference: String) -> EffectDefinition:
		return null
	var results: Array[Error] = [
		target.session.load_snapshot(other_map, target.lookup()),
		target.session.load_snapshot(data, unknown),
		target.session.load_snapshot({"format": 99}, target.lookup()),
	]
	_check.call("snapshot: another map's, an unknown definition and another format are refused", (
			results == [ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA]
			and JSON.stringify(target.session.snapshot(), "", true) == before
	), str(results))


func _test_mirror_from_snapshot_and_catch_up() -> void:
	var host: Field = Field.new()
	host.exchange(1)
	var taken: Dictionary = Kit.through_json(host.session.snapshot()) as Dictionary
	var taken_at: int = host.session.last_seq()
	host.exchange(2)
	var mirror: Field = Field.new()
	var loaded: Error = mirror.session.load_snapshot(taken, mirror.lookup())
	var catch_up: CombatSession.FactBatch = CombatSession.FactBatch.new()
	catch_up.facts = host.session.facts_since(taken_at)
	catch_up.state_hash = host.session.state_hash()
	var applied: Error = mirror.session.apply_batch(Kit.batch_through_json(catch_up))
	_check.call("mirror: a snapshot plus the catch-up facts equals the host", (
			loaded == OK
			and applied == OK
			and not catch_up.facts.is_empty()
			and mirror.session.state_hash() == host.session.state_hash()
			and mirror.session.last_seq() == host.session.last_seq()
			and mirror.session.playback.pending() == catch_up.facts.size()
	), "%s, %s" % [error_string(loaded), error_string(applied)])
	_check.call("mirror: it rolled nothing and fired nothing itself", (
			mirror.session.engine.rolls.records.is_empty()
			and mirror.session.engine.diagnostics.is_empty()
	))


func _test_mirror_resent_and_gap() -> void:
	var host: Field = Field.new()
	var mirror: Field = Field.new()
	mirror.session.load_snapshot(
			Kit.through_json(host.session.snapshot()) as Dictionary, mirror.lookup()
	)
	host.exchange(3)
	var results: Array[Error] = []
	for batch: CombatSession.FactBatch in host.batches:
		results.append(mirror.session.apply_batch(Kit.batch_through_json(batch)))
	var synced: bool = mirror.session.state_hash() == host.session.state_hash()
	var charges: int = mirror.session.engine.get_instance(mirror.boost_id).charges_left
	var deltas: int = mirror.session.engine.get_deltas(mirror.hero, CombatValue.Key.MGT).size()
	var resent: Error = mirror.session.apply_batch(
			Kit.batch_through_json(host.batches[1])
	)
	_check.call("mirror: every batch applies and matches the host's hash", (
			synced and not results.has(ERR_INVALID_DATA) and results.count(OK) == results.size()
	), str(results))
	_check.call("mirror: a resent batch doesn't apply twice", (
			resent == OK
			and mirror.session.state_hash() == host.session.state_hash()
			and mirror.session.engine.get_instance(mirror.boost_id).charges_left == charges
			and mirror.session.engine.get_deltas(mirror.hero, CombatValue.Key.MGT).size() == deltas
	), error_string(resent))

	var sent: int = host.batches.size()
	host.exchange(2)
	var skipped: CombatSession.FactBatch = Kit.batch_through_json(host.batches[sent])
	var later: CombatSession.FactBatch = Kit.batch_through_json(host.batches[sent + 1])
	print("    (a WARN about a mirror gap follows)")
	var early: Error = mirror.session.apply_batch(later)
	var stuck: bool = mirror.session.state_hash() != host.session.state_hash()
	var in_order: Array[Error] = [
		mirror.session.apply_batch(skipped), mirror.session.apply_batch(later),
	]
	_check.call("mirror: a missing batch is a gap, and applying it then catches up", (
			early == ERR_PARAMETER_RANGE_ERROR
			and stuck
			and in_order == [OK, OK]
			and mirror.session.state_hash() == host.session.state_hash()
	), "%s %s" % [error_string(early), in_order])
	var foreign: CombatSession.FactBatch = CombatSession.FactBatch.new()
	foreign.session_id = 4
	_check.call("mirror: another map's batch is refused", (
			mirror.session.apply_batch(foreign) == ERR_INVALID_PARAMETER
			and mirror.session.apply_batch(null) == ERR_INVALID_PARAMETER
	))


func _test_mirror_divergence() -> void:
	var host: Field = Field.new()
	var mirror: Field = Field.new()
	mirror.session.load_snapshot(
			Kit.through_json(host.session.snapshot()) as Dictionary, mirror.lookup()
	)
	host.exchange(1)
	var first: Error = mirror.session.apply_batch(
			Kit.batch_through_json(host.batches[host.batches.size() - 1])
	)
	# A change no fact announced: the mirror's state now differs from the host's.
	mirror.session.engine.add_delta(mirror.hero, Modifier.new(
			CombatValue.Key.DEF, Modifier.Mode.ADD, 5.0, Modifier.SourceKind.UNIT_TRAIT, "", "bug"
	))
	host.exchange(1)
	print("    (a WARN about a mirror hash mismatch follows)")
	var diverged: Error = mirror.session.apply_batch(
			Kit.batch_through_json(host.batches[host.batches.size() - 1])
	)
	_check.call("mirror: a diverged mirror reports a hash mismatch", (
			first == OK and diverged == ERR_INVALID_DATA
	), "%s, %s" % [error_string(first), error_string(diverged)])


func _test_modifier_gained_mid_attack() -> void:
	var host: Field = Field.new()
	var steady_id: String = host.add_effect(host.hero, Kit.steady())
	var mirror: Field = Field.new()
	mirror.add_effect(mirror.hero, Kit.steady())
	mirror.session.load_snapshot(
			Kit.through_json(host.session.snapshot()) as Dictionary, mirror.lookup()
	)
	host.session.submit(MidAttackFixture.new(host.hero, host.foe, steady_id))
	host.session.resolve_queued()
	var during: Error = mirror.session.apply_batch(
			Kit.batch_through_json(host.batches[host.batches.size() - 1])
	)
	var host_held: Array[TimedModifier] = host.session.engine.get_timed_modifiers(host.hero)
	var mirror_held: Array[TimedModifier] = mirror.session.engine.get_timed_modifiers(mirror.hero)
	_check.call("timed: a modifier gained mid-attack isn't spent by that attack, host and mirror", (
			during == OK
			and host_held.size() == 1
			and host_held[0].uses_left == 1
			and mirror_held.size() == 1
			and mirror_held[0].uses_left == 1
	), error_string(during))
	host.session.submit(MidAttackFixture.new(host.hero, host.foe, ""))
	host.session.resolve_queued()
	var after: Error = mirror.session.apply_batch(
			Kit.batch_through_json(host.batches[host.batches.size() - 1])
	)
	_check.call("timed: the next attack spends it on both", (
			after == OK
			and host.session.engine.get_timed_modifiers(host.hero).is_empty()
			and mirror.session.engine.get_timed_modifiers(mirror.hero).is_empty()
			and mirror.session.state_hash() == host.session.state_hash()
	), error_string(after))


func _test_multi_use_modifier_over_exchange() -> void:
	var host: Field = Field.new()
	var mirror: Field = Field.new()
	mirror.session.load_snapshot(
			Kit.through_json(host.session.snapshot()) as Dictionary, mirror.lookup()
	)
	host.exchange(1)
	var results: Array[Error] = []
	for batch: CombatSession.FactBatch in host.batches:
		results.append(mirror.session.apply_batch(Kit.batch_through_json(batch)))
	var made: Dictionary[String, int] = {host.hero: 0, host.foe: 0}
	for fact: CombatFact in host.batches[host.batches.size() - 1].facts:
		if fact.kind == CombatFact.Kind.ATTACK_MADE:
			made[fact.actor_id] += 1
	var host_hero: Array[TimedModifier] = host.session.engine.get_timed_modifiers(host.hero)
	var host_foe: Array[TimedModifier] = host.session.engine.get_timed_modifiers(host.foe)
	var mirror_hero: Array[TimedModifier] = mirror.session.engine.get_timed_modifiers(mirror.hero)
	var mirror_foe: Array[TimedModifier] = mirror.session.engine.get_timed_modifiers(mirror.foe)
	_check.call("timed: AtkX 2 and a counter each spend only their own unit's uses", (
			made[host.hero] >= 2
			and made[host.foe] >= 1
			and host_hero.size() == 1
			and host_hero[0].uses_left == Field.FOCUS_USES - made[host.hero]
			and host_foe.size() == 1
			and host_foe[0].uses_left == Field.FOCUS_USES - made[host.foe]
	), "attacks %s" % [made])
	_check.call("timed: the mirror spends the same uses", (
			results.count(OK) == results.size()
			and mirror_hero.size() == 1
			and mirror_hero[0].uses_left == host_hero[0].uses_left
			and mirror_foe.size() == 1
			and mirror_foe[0].uses_left == host_foe[0].uses_left
			and mirror.session.state_hash() == host.session.state_hash()
	), str(results))


func _test_dump_replay() -> void:
	var first: Bridge = Bridge.new(PackedInt32Array([0]), false)
	var s0: CombatSession = first.battle.get_session(0)
	first.attack_all(0)
	s0.submit(EndTurnCommand.new(0))
	s0.resolve_queued()
	first.attack_all(0)
	var path: String = s0.debug_dump()
	var file_text: String = FileAccess.get_file_as_string(path) if not path.is_empty() else ""
	var dump: Dictionary = {}
	var parsed: Variant = JSON.parse_string(file_text)
	if parsed is Dictionary:
		dump = parsed
	var snapshot: Dictionary = dump.get("snapshot", {})
	_check.call("dump: written to user://logs with the run seed, the build and the streams", (
			path.begins_with(CombatSession.DUMP_DIR)
			and dump.get("run_seed", "") == RunSeed.format(RUN_SEED)
			and dump.get("game_version", "") == ProjectSettings.get_setting(
					"application/config/version"
			)
			and dump.get("rolls", "") == (s0.engine.rolls as LiveRolls).capture()
			and (snapshot.get("rolls", "") as String).length() == 16
			and snapshot.get("run_seed", "") == RunSeed.format(RUN_SEED)
			and dump.get("complete", false) == true
			and (dump.get("commands", []) as Array).size() >= 3
	), path)

	var again: Bridge = Bridge.new(PackedInt32Array([0]), false, false)
	var r0: CombatSession = again.battle.get_session(0)
	var loaded: Error = r0.load_snapshot(snapshot, again.lookup())
	for wire: Variant in dump.get("commands", []):
		r0.submit(Command.from_wire(wire as Array))
	r0.resolve_queued()
	var replayed: Array = []
	var base: int = Kit.as_int((snapshot.get("session", {}) as Dictionary).get("last_seq"))
	for fact: CombatFact in r0.engine.fact_log:
		if fact.seq > base:
			replayed.append(fact.to_wire())
	var recorded: Array = []
	for wire: Variant in dump.get("facts", []):
		recorded.append(CombatFact.from_wire(wire as Array).to_wire())
	_check.call("dump: replaying it headless reproduces the same facts", (
			loaded == OK
			and not recorded.is_empty()
			and JSON.stringify(replayed) == JSON.stringify(recorded)
			and r0.state_hash() == s0.state_hash()
	), "%s, %d and %d facts" % [error_string(loaded), replayed.size(), recorded.size()])
	if not path.is_empty():
		DirAccess.remove_absolute(path)


func _test_ids_after_resume() -> void:
	var first: Bridge = Bridge.new(PackedInt32Array([0]), false)
	var campaign_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.CAMPAIGN)
	var combat_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
	campaign_ids.attach(first.run)
	combat_ids.attach(first.run)
	first.attack_all(0)
	var checkpoint: Dictionary = Kit.through_json(combat_ids.capture()) as Dictionary
	var at_begin: Dictionary = Kit.through_json(first.ids_at_begin) as Dictionary
	var expected: PackedStringArray = Kit.mint(first.run.ids)

	var resumed: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var resumed_campaign: InstanceIdSaveSection = InstanceIdSaveSection.new(
			SaveSection.Block.CAMPAIGN
	)
	var resumed_combat: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
	var restored: Array[Error] = [
		resumed_campaign.restore(at_begin),
		resumed_combat.restore(checkpoint),
		resumed_campaign.attach(resumed),
		resumed_combat.attach(resumed),
	]
	var unit_id: String = first.units[0][0]
	_check.call("ids: ids minted after a resume match the original run", (
			restored == [OK, OK, OK, OK]
			and Kit.mint(resumed.ids) == expected
			and resumed.ids.label_of(unit_id) == first.run.ids.label_of(unit_id)
			and not resumed.ids.label_of(unit_id).is_empty()
	), "%s; %s" % [restored, expected])

	var retried: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var retry_campaign: InstanceIdSaveSection = InstanceIdSaveSection.new(
			SaveSection.Block.CAMPAIGN
	)
	var retry_combat: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
	retry_campaign.restore(at_begin)
	retry_combat.restore(checkpoint)
	# BATTLE_RETRY resets the combat block before the session is built.
	retry_combat.reset()
	retry_campaign.attach(retried)
	retry_combat.attach(retried)
	_check.call("ids: a battle restarted from Begin mints from Begin's counter", (
			retried.ids.get_next_value() == Kit.as_int(at_begin["next"])
			and retried.ids.next_item_id("Sword") == first.swords[0]
			and retried.ids.next_enemy_id("Brute") == first.enemies[0]
	))


func _test_id_section_rules() -> void:
	var fresh: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.CAMPAIGN)
	var blank: Dictionary = fresh.capture()
	_check.call("id section: with no session it writes a fresh counter it can read back", (
			Kit.as_int(blank.get("next")) == InstanceIdAllocator.FIRST_VALUE
			and fresh.restore(Kit.through_json(blank) as Dictionary) == OK
	))
	print("    (errors about refused instance ids follow)")
	var holding: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
	var refused: Array[Error] = [
		holding.restore({"next": 0, "labels": {}}),
		holding.restore({"next": 4.5, "labels": {}}),
		holding.restore({"next": 4, "labels": {"unit:1": 3}}),
		holding.restore({"labels": {}}),
	]
	var in_battle: Bridge = Bridge.new(PackedInt32Array([0]), false)
	holding.restore({"next": 40, "labels": {}})
	var busy: Error = holding.attach(in_battle.run)
	_check.call("id section: bad data is refused, and held data never lands mid-battle", (
			refused == [ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA, ERR_INVALID_DATA]
			and busy == ERR_ALREADY_IN_USE
			and in_battle.run.ids.get_next_value() != 40
			and holding.attach(null) == ERR_INVALID_PARAMETER
	), "%s %s" % [refused, error_string(busy)])


func _test_encounter_snapshot() -> void:
	var host: Bridge = Bridge.new(PackedInt32Array([0, 1]), true)
	for seat: int in [0, 1]:
		host.attack_all(seat)
	var heirloom: EffectInstance = host.battle.get_cross_map_instances()[0]
	var taken: Dictionary = Kit.through_json(host.battle.snapshot()) as Dictionary
	var copy: Bridge = Bridge.new(PackedInt32Array([0, 1]), true)
	var loaded: Error = copy.battle.load_snapshot(taken, copy.lookup())
	var shared: EffectInstance = copy.battle.get_cross_map_instances()[0]
	_check.call("encounter: a snapshot restores every map and the cross-map counters", (
			loaded == OK
			and heirloom.get_counter(EffectTerms.Lane.COMBAT) > 0
			and shared.get_counter(EffectTerms.Lane.COMBAT)
			== heirloom.get_counter(EffectTerms.Lane.COMBAT)
			and copy.battle.state_hash() == host.battle.state_hash()
			and copy.battle.get_session(0).state_hash() == host.battle.get_session(0).state_hash()
			and copy.battle.get_session(1).state_hash() == host.battle.get_session(1).state_hash()
	), error_string(loaded))
	_check.call("encounter: every map's engine holds the one cross-map object", (
			copy.battle.get_session(0).engine.get_instance(shared.instance_id) == shared
			and copy.battle.get_session(1).engine.get_instance(shared.instance_id) == shared
	))

	var resent: CombatSession.FactBatch = CombatSession.FactBatch.new()
	resent.facts = host.battle.fact_log.duplicate()
	var stale: Error = copy.battle.apply_batch(Kit.batch_through_json(resent))
	var ahead: CombatSession.FactBatch = CombatSession.FactBatch.new()
	var skipped: CombatFact = CombatFact.new(CombatFact.Kind.COUNTER_CHANGED)
	skipped.seq = host.battle.fact_log.size() + 2
	ahead.facts.append(skipped)
	print("    (a WARN about an encounter mirror gap follows)")
	_check.call("encounter: facts it has are skipped, and a gap is reported", (
			stale == OK
			and copy.battle.fact_log.is_empty()
			and copy.battle.apply_batch(ahead) == ERR_PARAMETER_RANGE_ERROR
	), error_string(stale))


# Helpers the cases and the fixtures below share.
class Kit:
	extends RefCounted

	static func through_json(value: Variant) -> Variant:
		return JSON.parse_string(JSON.stringify(value))


	static func batch_through_json(batch: CombatSession.FactBatch) -> CombatSession.FactBatch:
		return CombatSession.FactBatch.from_wire(Kit.through_json(batch.to_wire()) as Array)


	static func fact_lines(batch: CombatSession.FactBatch) -> String:
		var lines: PackedStringArray = []
		for fact: CombatFact in batch.facts:
			lines.append(fact.to_log_line())
		return "\n".join(lines)


	static func as_int(value: Variant) -> int:
		if not (value is int or value is float):
			return -1
		var number: float = value
		return roundi(number)


	# Three ids of different kinds, in a fixed order.
	static func mint(ids: InstanceIdAllocator) -> PackedStringArray:
		return PackedStringArray([
			ids.next_enemy_id("Brute"), ids.next_item_id("Iron Axe"), ids.next_effect_id(),
		])


	static func fixture_layout() -> MapLayout:
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = "fixture"
		definition.scene = FIXTURE_SCENE
		return MapLoader.load_layout(definition)


	static func weapon(weapon_id: String, preset: String) -> CombatState.WeaponStats:
		var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
		var columns: Array = PRESETS[preset]
		stats.id = weapon_id
		stats.label = preset.capitalize()
		stats.damage = columns[0]
		stats.atk_x = columns[1]
		stats.range_min = columns[2]
		stats.range_max = columns[3]
		stats.hit = columns[4]
		stats.weight = columns[5]
		return stats


	static func bases(hp: float) -> Dictionary:
		return {
			CombatValue.Key.HP: hp,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		}


	# The real catalog without its packs: setup step 4 draws from every pack (EnemySetup.draw), so
	# a battle on this draws no enemies and a case can place its own on the enemy slot.
	static func catalog_without_packs() -> EffectCatalog.Index:
		var real: EffectCatalog.Index = EffectCatalog.index()
		var index: EffectCatalog.Index = EffectCatalog.Index.new()
		for id: String in real.ids():
			if not real.is_of(id, EffectCatalog.Kind.PACK):
				index.add(real.path_of(id), real.definition(id))
		index.finish()
		return index


	# "Hit dealt: gain 1 Block", every [param every]th hit this combat: a counter.
	static func counted_block(id: String, every: int) -> EffectDefinition:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = id
		definition.trigger = EffectTerms.Trigger.HIT_DEALT
		var counter: CounterCondition = CounterCondition.new()
		counter.count = every
		definition.conditions.append(counter)
		var gain: GainResource = GainResource.new()
		gain.pool = GainResource.Pool.BLOCK
		var amount: Constant = Constant.new()
		amount.value = 1.0
		gain.amount = amount
		definition.operations.append(gain)
		return definition


	# "Hit dealt: +1 Might", [param charges] times a combat: charges and permanent deltas.
	static func boosting(id: String, charges: int) -> EffectDefinition:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = id
		definition.trigger = EffectTerms.Trigger.HIT_DEALT
		definition.charges = charges
		var change: ChangeBaseStat = ChangeBaseStat.new()
		change.key = CombatValue.Key.MGT
		change.value = 1.0
		definition.operations.append(change)
		return definition


	# "Before Combat: +10 Hit on its next [param uses] attacks this combat", the second of two
	# operations, so the fact's operation index is not 0.
	static func focus(id: String, uses: int) -> EffectDefinition:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = id
		definition.trigger = EffectTerms.Trigger.BEFORE_COMBAT
		var crit: AddTimedModifier = AddTimedModifier.new()
		crit.key = CombatValue.Key.CRIT_CHANCE
		crit.value = 5.0
		crit.end = AddTimedModifier.End.THIS_EXCHANGE
		var hit: AddTimedModifier = AddTimedModifier.new()
		hit.key = CombatValue.Key.HIT
		hit.value = 10.0
		hit.end = AddTimedModifier.End.THIS_COMBAT
		hit.uses = uses
		definition.operations.assign([crit, hit])
		return definition


	# "+15 Hit on its next attack this combat", fired by a command.
	static func steady() -> EffectDefinition:
		var definition: EffectDefinition = EffectDefinition.new()
		definition.id = "steady"
		var hit: AddTimedModifier = AddTimedModifier.new()
		hit.key = CombatValue.Key.HIT
		hit.value = 15.0
		hit.end = AddTimedModifier.End.THIS_COMBAT
		hit.uses = 1
		definition.operations.append(hit)
		return definition


# One map with a gauntlet-wielding hero (AtkX 2) next to a sword-wielding foe that counters, both
# with HP 200, a counter, a charged stat booster and a "next attacks" modifier on the hero and the
# same modifier on the foe. Built the same way every time, ids included, so a mirror can be built
# beside a host.
class Field:
	extends RefCounted

	# More than the hero's attacks in two exchanges (AtkX 2, doubled by Attack Speed), so a
	# modifier outlives an exchange.
	const FOCUS_USES: int = 9

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null
	var definitions: Dictionary[String, EffectDefinition] = {}
	var batches: Array[CombatSession.FactBatch] = []
	var hero: String = ""
	var foe: String = ""
	var block_id: String = ""
	var boost_id: String = ""

	func _init() -> void:
		var grid: MapGrid = MapGrid.new(Kit.fixture_layout())
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(STREAM_SEED))
		session = CombatSession.new(0, PackedInt32Array([0]), grid, rolls, ids)
		session.engine.verify = true
		session.batch_resolved.connect(_on_batch_resolved)
		hero = add_unit("Brawler", PLAYER, 0, Vector2i(2, 2), "gauntlets")
		foe = add_unit("Brute", ENEMY, -1, Vector2i(3, 2), "sword")
		block_id = add_effect(hero, Kit.counted_block("bulwark", 3))
		boost_id = add_effect(hero, Kit.boosting("tonic", 2))
		add_effect(hero, Kit.focus("focus", FOCUS_USES))
		add_effect(foe, Kit.focus("focus", FOCUS_USES))

	func add_unit(
			unit_type: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i,
			preset: String
	) -> String:
		var held: CombatState.WeaponStats = Kit.weapon(
				ids.next_item_id(preset.capitalize()), preset
		)
		session.state.add_weapon(held)
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = ids.next_unit_id(unit_type) if side == PLAYER else ids.next_enemy_id(unit_type)
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.unit_type = unit_type
		unit.hp = 200
		unit.equipped_weapon_id = held.id
		session.add_unit(unit, Kit.bases(200.0))
		return unit.id

	func add_effect(unit_id: String, definition: EffectDefinition) -> String:
		definitions[definition.id] = definition
		var state: CombatState = session.state
		var instance: EffectInstance = EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_unit(unit_id, state.seat_of(unit_id), state.side_of(unit_id)),
				Modifier.SourceKind.UNIT_TRAIT,
				definition.id.capitalize()
		)
		session.engine.register(instance)
		return instance.instance_id

	# Finds this field's definitions by id, as the catalog would.
	func lookup() -> Callable:
		var known: Dictionary[String, EffectDefinition] = definitions
		return func(reference: String) -> EffectDefinition:
			return known.get(reference, null)

	# [param times] exchanges of the hero on the foe, one command each.
	func exchange(times: int) -> void:
		for i: int in times:
			session.submit(ExchangeFixture.new(hero, foe))
		session.resolve_queued()

	func counter_of(instance_id: String) -> int:
		return session.engine.get_instance(instance_id).get_counter(EffectTerms.Lane.COMBAT)

	func _on_batch_resolved(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)


# A battle begun through the campaign bridge on the fixture map, with no packs to draw from: each
# seat's two bowmen (range 2-3) deployed, a trait with a counter on seat 0's first unit, optionally
# a cross-map heirloom, then a sword-wielding enemy on each map at its enemy slot, placed in the
# opening swap window. Each map
# checkpoints there, so a dump replays from that point, then each seat's Start begins turn 1.
# Built the same way every time.
class Bridge:
	extends RefCounted

	var run: CampaignSession = null
	var battle: CombatEncounter = null
	var definitions: Dictionary[String, EffectDefinition] = {}
	var units: Dictionary[int, PackedStringArray] = {}
	var enemies: Dictionary[int, String] = {}
	var swords: PackedStringArray = []
	var ids_at_begin: Dictionary = {}

	func _init(seats: PackedInt32Array, with_heirloom: bool, is_started: bool = true) -> void:
		var mode: CampaignData.Mode = (
				CampaignData.Mode.MULTIPLAYER if seats.size() > 1 else CampaignData.Mode.SOLO
		)
		run = CampaignSession.new(mode, RUN_SEED, seats)
		var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
		request.floor_number = FLOOR
		request.node = NODE
		var map: CombatMapDefinition = CombatMapDefinition.new()
		map.id = "map_a"
		map.scene = FIXTURE_SCENE
		request.pool.append(map)
		request.catalog = Kit.catalog_without_packs()
		for seat: int in seats:
			var army: CampaignSession.Army = CampaignSession.Army.new()
			var unit_ids: PackedStringArray = []
			for i: int in 2:
				var bow: CombatState.WeaponStats = Kit.weapon(
						run.ids.next_item_id("Bow"), "bow"
				)
				var unit: CombatUnitState = CombatUnitState.new()
				unit.id = run.ids.next_unit_id("Archer")
				unit.seat = seat
				unit.unit_type = "Archer"
				unit.hp = 20
				unit.equipped_weapon_id = bow.id
				army.units.append(unit)
				army.weapons.append(bow)
				army.bases[unit.id] = Kit.bases(20.0)
				unit_ids.append(unit.id)
			request.armies[seat] = army
			# On, so each map waits in the swap window while its enemy is placed: a map with no
			# enemy at turn 1 is won at once.
			request.opening_swap[seat] = true
			units[seat] = unit_ids
		_add_carrier(
				Kit.counted_block("watch", 2),
				EffectOwner.for_unit(units[seats[0]][0], seats[0], PLAYER),
				Modifier.SourceKind.UNIT_TRAIT
		)
		if with_heirloom:
			# Every 10th: no case lands that many hits, so its count only rises.
			var ledger: EffectDefinition = Kit.counted_block("ledger", 10)
			ledger.scope = EffectTerms.Scope.ANY_ALLY_UNIT
			(ledger.operations[0] as GainResource).target = FactActor.new()
			_add_carrier(
					ledger,
					EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(seats[0]), seats[0]),
					Modifier.SourceKind.HEIRLOOM
			)
		battle = run.begin_battle(request)
		ids_at_begin = run.ids.capture()
		for session: CombatSession in battle.get_sessions():
			var seat: int = session.seats[0]
			var sword: CombatState.WeaponStats = Kit.weapon(
					run.ids.next_item_id("Sword"), "sword"
			)
			session.state.add_weapon(sword)
			var enemy: CombatUnitState = CombatUnitState.new()
			enemy.id = run.ids.next_enemy_id("Brute")
			enemy.side = ENEMY
			enemy.tile = Vector2i(3, 2)
			enemy.hp = 40
			enemy.equipped_weapon_id = sword.id
			session.add_unit(enemy, Kit.bases(40.0))
			session.flush("enemies")
			session.mark_checkpoint()
			enemies[seat] = enemy.id
			swords.append(sword.id)
		# Not started: a dump's replay sends the recorded Start itself.
		if not is_started:
			return
		for session: CombatSession in battle.get_sessions():
			session.submit(StartCommand.new(session.seats[0]))
			session.resolve_queued()

	# Each of [param seat]'s units in bow range of its map's enemy attacks it, one command each.
	func attack_all(seat: int) -> void:
		var session: CombatSession = battle.session_of_seat(seat)
		var enemy_tile: Vector2i = session.state.tile_of(enemies[seat])
		for unit_id: String in units[seat]:
			var tile: Vector2i = session.state.tile_of(unit_id)
			var distance: int = absi(tile.x - enemy_tile.x) + absi(tile.y - enemy_tile.y)
			if distance >= 2 and distance <= 3:
				session.submit(UnitTurnCommand.new(
						seat, unit_id, UnitTurnCommand.Action.ATTACK, enemies[seat]
				))
		session.resolve_queued()

	func lookup() -> Callable:
		var known: Dictionary[String, EffectDefinition] = definitions
		return func(reference: String) -> EffectDefinition:
			return known.get(reference, null)

	func _add_carrier(
			definition: EffectDefinition, owner: EffectOwner, kind: Modifier.SourceKind
	) -> void:
		definitions[definition.id] = definition
		run.add_carrier(EffectInstance.new(run.ids.next_effect_id(), definition, owner, kind))


# One exchange of its unit on a target, as an attack command resolves one; the turn is reset
# first so a unit can attack again.
class ExchangeFixture:
	extends Command

	var target: String = ""

	func _init(unit_id: String, target_id: String) -> void:
		seat = 0
		actor_id = unit_id
		target = target_id

	func get_label() -> String:
		return "exchange"

	func resolve(session: CombatSession) -> void:
		session.state.unit(actor_id).has_acted = false
		ExchangeResolver.resolve(session.engine, session.state, actor_id, target)


# One attack of its unit made by hand: Attack made, then (with an effect) the effect fires and its
# reaction resolves while the attack is under way, then the attack resolves.
class MidAttackFixture:
	extends Command

	var target: String = ""
	var effect_id: String = ""

	func _init(unit_id: String, target_id: String, fired_effect_id: String) -> void:
		seat = 0
		actor_id = unit_id
		target = target_id
		effect_id = fired_effect_id

	func get_label() -> String:
		return "attack by hand"

	func resolve(session: CombatSession) -> void:
		var engine: EffectEngine = session.engine
		engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))
		if not effect_id.is_empty():
			engine.activate(engine.get_instance(effect_id), EffectContext.new())
			engine.drain()
		engine.reach_boundary(EffectEngine.Boundary.ATTACK_RESOLVED, actor_id)
