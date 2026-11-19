# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     resume_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Battle save and resume cases for tests/sessions/run_all.gd, through the real
## [code]SaveService[/code]: the combat state and map sections, resuming a battle, after the
## darkness's arrival too, and the fallback. Skipped without a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# The battle the gameplay screen begins (gameplay.tscn's BattleScreen): M1 on floor 1, node 1.
# A preloaded script used as a type (gdscript.md, Naming): the helper has no class name.
const PackCatalog = preload("res://tests/enemies/pack_catalog.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const M1_FLOOR: int = 1
const M1_NODE: int = 1

# The turn the arrival resume case saves on: M1's turn par is 5, so the darkness arrives at the
# end of turn 4, turn 5's step creeps it onto the commander's tile, and turn 6's releases the next
# wave. On this seed a battle of End Turns only lasts into turn 8.
const ARRIVAL_SAVE_TURN: int = 6

# The hand-placed Brute's prefix and level in the combat state case: any prefix in the catalog.
const ELITE_PREFIX: String = "sturdy"
const ELITE_LEVEL: int = 3


func run() -> void:
	_run(_test_service_combat_state)
	_run(_test_service_combat_map)
	_run(_test_service_resume_battle)
	_run(_test_service_resume_after_arrival)
	_run(_test_service_resume_falls_back)


# The combat_state and effects sections through the real SaveService (combat core plan, CC8): a
# checkpoint mid-phase writes them at versions 3 and 1 with the core's turn and phase equal to the
# battle's, and a continued run holds them until they load into the battle rebuilt from Begin,
# an elite's prefix and level included.
func _test_service_combat_state() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service combat state: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var begun: int = service.call(&"begin_battle", _request(run, {0: ["Drengr", "Archer"]}))
	var session: CombatSession = run.encounter.get_session(0)
	var units: PackedStringArray = session.state.units_of(PLAYER)
	# In the swap window, as WireCases.Bridge does: a map with no enemy is won at turn 1.
	var sword: CombatState.WeaponStats = WireCases.Kit.weapon(
			run.ids.next_item_id("Sword"), "sword"
	)
	session.state.add_weapon(sword)
	var brute: CombatUnitState = CombatUnitState.new()
	brute.id = run.ids.next_enemy_id("Brute")
	brute.side = ENEMY
	brute.tile = Vector2i(3, 2)
	brute.hp = 40
	# An elite's prefix and level, which the unit detail shows: they must survive the resume.
	brute.prefix_id = ELITE_PREFIX
	brute.level = ELITE_LEVEL
	brute.equipped_weapon_id = sword.id
	session.add_unit(brute, WireCases.Kit.bases(40.0))
	session.flush("enemies")
	session.submit(StartCommand.new(0))
	session.submit(UnitTurnCommand.new(0, units[0], UnitTurnCommand.Action.WAIT, ""))
	session.resolve_queued()
	var saved: int = saves.call(&"save_checkpoint")
	var saved_hash: int = session.state_hash()
	var core: CombatData = saves.get(&"combat")
	var combat_path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)
	var sections: Dictionary = SaveFile.read(combat_path).envelope.get(SaveFile.KEY_SECTIONS, {})
	var versions: Array[int] = []
	for key: String in ["combat_state", "effects"]:
		var entry: Dictionary = sections.get(key, {})
		var version: float = entry.get("version", 0.0)
		versions.append(roundi(version))
	_check("service combat state: a checkpoint writes both sections and the core's turn", (
			begun == OK
			and saved == OK
			and versions == [3, 1]
			and core.turn == 1
			and core.phase == CombatData.Phase.PLAYER
			and session.state.unit(units[0]).has_acted
	), "%s, versions %s" % [error_string(saved), versions])

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var resumed: CampaignSession = service.get(&"session")
	var section: CombatStateSection = service.get(&"_combat_state")
	var map_section: CombatMapSection = service.get(&"_combat_map")
	var resume_point: int = saves.get(&"resume_point")
	var holding: bool = section.is_holding() and map_section.is_holding()
	var loaded: int = service.call(
			&"resume_battle", _request(resumed, {0: ["Drengr", "Archer"]})
	)
	var after_point: int = saves.get(&"resume_point")
	var again: CombatSession = resumed.encounter.get_session(0)
	_check("service combat state: a continued run loads the battle into its rebuilt one", (
			resume_point == CombatData.ResumePoint.BATTLE
			and holding
			and loaded == OK
			and after_point == CombatData.ResumePoint.BATTLE
			and not section.is_holding()
			and again.state_hash() == saved_hash
			and again.state.unit(units[0]).has_acted
			and again.state.has_unit(brute.id)
	), "resume point %d, %s, holding %s" % [resume_point, error_string(loaded), holding])
	var kept: CombatUnitState = (
			again.state.unit(brute.id) if again.state.has_unit(brute.id) else null
	)
	var detail: UnitDetailViewModel = UnitDetailViewModel.build(again, brute.id)
	_check("service combat state: a resumed elite keeps its prefix and level, and shows them", (
			kept != null
			and kept.prefix_id == ELITE_PREFIX
			and kept.level == ELITE_LEVEL
			and detail != null
			and detail.prefix_name == "Sturdy"
			and detail.level == ELITE_LEVEL
	), "%s, %s" % [
		"-" if kept == null else "%s level %d" % [kept.prefix_id, kept.level],
		"-" if detail == null else "%s level %d" % [detail.prefix_name, detail.level],
	])

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# The combat_map and entities sections through the real SaveService (combat map plan, MP8): a
# checkpoint after a unit searched the fixture's house writes both at version 1, and a continued
# run loads them, then the battle, into the battle rebuilt from Begin.
func _test_service_combat_map() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service combat map: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var begun: int = service.call(&"begin_battle", _request(run, {0: ["Drengr", "Archer"]}))
	var session: CombatSession = run.encounter.get_session(0)
	# In the swap window, as the combat state case does: a map with no enemy is won at turn 1.
	var sword: CombatState.WeaponStats = WireCases.Kit.weapon(
			run.ids.next_item_id("Sword"), "sword"
	)
	session.state.add_weapon(sword)
	var brute: CombatUnitState = CombatUnitState.new()
	brute.id = run.ids.next_enemy_id("Brute")
	brute.side = ENEMY
	brute.tile = Vector2i(3, 2)
	brute.hp = 40
	brute.equipped_weapon_id = sword.id
	session.add_unit(brute, WireCases.Kit.bases(40.0))
	session.flush("enemies")
	session.submit(StartCommand.new(0))
	session.resolve_queued()
	var house: MapState.ObjectState = session.state.map.objects_of(MapLayout.ObjectKind.HOUSE)[0]
	var searcher: String = ""
	var walk: Array[Vector2i] = []
	for start: Vector2i in [Vector2i(0, 3), Vector2i(1, 3)]:
		searcher = session.state.occupant_at(start)
		if not searcher.is_empty():
			var steps: Array = [start, house.tile]
			if start.x == 1:
				steps.insert(1, Vector2i(0, 3))
			walk.assign(steps)
			break
	session.submit(UnitTurnCommand.new(
			0, searcher, UnitTurnCommand.Action.USE_OBJECT, house.id, walk
	))
	session.resolve_queued()
	var saved: int = saves.call(&"save_checkpoint")
	var saved_hash: int = session.state_hash()
	var saved_map: String = JSON.stringify(session.snapshot()["map"])
	var combat_path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)
	var sections: Dictionary = SaveFile.read(combat_path).envelope.get(SaveFile.KEY_SECTIONS, {})
	var versions: Array[int] = []
	for key: String in ["combat_map", "entities"]:
		var entry: Dictionary = sections.get(key, {})
		var version: float = entry.get("version", 0.0)
		versions.append(roundi(version))
	_check("service combat map: a checkpoint writes both sections", (
			begun == OK
			and saved == OK
			and versions == [1, 2]
			and house.is_used
			and (session.state.map.found.get(0, []) as Array).size() == 1
	), "%s, versions %s" % [error_string(saved), versions])

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var resumed: CampaignSession = service.get(&"session")
	var section: CombatStateSection = service.get(&"_combat_state")
	var map_section: CombatMapSection = service.get(&"_combat_map")
	var holding: bool = map_section.is_holding() and section.is_holding()
	var loaded: int = service.call(
			&"resume_battle", _request(resumed, {0: ["Drengr", "Archer"]})
	)
	var after_point: int = saves.get(&"resume_point")
	var again: CombatSession = resumed.encounter.get_session(0)
	_check("service combat map: a continued run loads the map into its rebuilt battle", (
			holding
			and loaded == OK
			and after_point == CombatData.ResumePoint.BATTLE
			and not map_section.is_holding()
			and again.state_hash() == saved_hash
			and JSON.stringify(again.snapshot()["map"]) == saved_map
			and again.state.map.object(house.id).is_used
	), "%s, holding %s" % [error_string(loaded), holding])

	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# Battle resume through the real SaveService (combat core plan, CC10): the M1 battle played by one
# script twice, uninterrupted and with Save & Quit then Continue mid turn 1 and mid turn 2 (after
# an enemy phase), records the same facts, mints the same ids and writes the same values back.
# The army is kept across the quits, as the run's saved roster will be (P08).
func _test_service_resume_battle() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service resume: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var straight: ResumeRun = _play_resume_script(saves, service, false)
	var resumed: ResumeRun = _play_resume_script(saves, service, true)
	var battle_point: int = CombatData.ResumePoint.BATTLE

	_check("service resume: each Continue resumes the saved battle, at its saved state", (
			straight.errors.is_empty()
			and resumed.errors.is_empty()
			and resumed.resumes == [OK, OK]
			and resumed.resume_points == [battle_point, battle_point]
			and resumed.saved_hashes == resumed.loaded_hashes
			and resumed.saved_seqs == resumed.loaded_seqs
			and resumed.saved_hashes == straight.saved_hashes
	), "%s; resumes %s at %s; hashes %s, loaded %s" % [
		resumed.errors, resumed.resumes, resumed.resume_points,
		resumed.saved_hashes, resumed.loaded_hashes,
	])
	_check("service resume: one save mid turn 1, one mid turn 2 after an enemy phase", (
			resumed.saved_turns == [1, 2] and straight.saved_turns == [1, 2]
	), str(resumed.saved_turns))
	_check("service resume: the same fact log as the uninterrupted battle", (
			not straight.facts.is_empty()
			and JSON.stringify(resumed.facts) == JSON.stringify(straight.facts)
	), "%d and %d facts" % [resumed.facts.size(), straight.facts.size()])
	_check("service resume: the id counter is the checkpoint's after each load", (
			resumed.loaded_next == resumed.saved_next and resumed.saved_next == straight.saved_next
	), "loaded %s, saved %s" % [resumed.loaded_next, resumed.saved_next])
	_check("service resume: ids go on as uninterrupted, none reused", (
			resumed.minted == straight.minted
			and resumed.next_after == straight.next_after
			and not resumed.known_at_last_save.has(resumed.minted)
	), "%s and %s" % [resumed.minted, straight.minted])
	_check("service resume: the darkness is rebuilt as Begin set it, not yet arrived", (
			resumed.darkness == straight.darkness
			and not resumed.darkness.is_empty()
			and not resumed.has_arrived
			and not straight.has_arrived
	), "%s and %s" % [resumed.darkness, straight.darkness])
	_check("service resume: write-back after it matches the uninterrupted battle's", (
			straight.counted.size() >= 2
			and _written_count(straight.written) == straight.counted.size()
			and JSON.stringify(resumed.written) == JSON.stringify(straight.written)
	), "counted %s; %s and %s" % [straight.counted, resumed.written, straight.written])
	return true


# Battle resume across the darkness phase (darkness plan, DK5 and DK7): the M1 battle played to
# turn 6 (arrival in turn 4's darkness phase, par 5, then turn 5's creep), saved, then played on
# through turn 6's darkness phase (damage, the commander's tile being flooded, then the release);
# uninterrupted, and with Save & Quit then Continue at the save. The resumed battle has the saved
# layers, waves (reach and tiles entered), contacts and arrival, then the same facts and darkness
# as the uninterrupted one: nothing repeated, nothing lost.
func _test_service_resume_after_arrival() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service resume after arrival: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var straight: ResumeRun = _play_arrival_script(saves, service, false)
	var resumed: ResumeRun = _play_arrival_script(saves, service, true)

	_check("service resume after arrival: saved on turn 6, the wave crept and entered tiles", (
			straight.errors.is_empty()
			and resumed.errors.is_empty()
			and resumed.saved_turns == [ARRIVAL_SAVE_TURN]
			and straight.saved_turns == [ARRIVAL_SAVE_TURN]
			and resumed.has_arrived
			and resumed.saved_darkness.size() == 1
			and resumed.saved_darkness[0].contains("\"reach\":2")
			and resumed.saved_darkness[0].contains("\"DUSK\"")
	), "%s; %s; turns %s; %s" % [
		straight.errors, resumed.errors, resumed.saved_turns, resumed.saved_darkness,
	])
	_check("service resume after arrival: Continue loads the darkness, reach and entries too", (
			resumed.resumes == [OK]
			and resumed.resume_points == [CombatData.ResumePoint.BATTLE]
			and resumed.loaded_darkness == resumed.saved_darkness
			and resumed.saved_darkness == straight.saved_darkness
			and resumed.loaded_hashes == resumed.saved_hashes
			and resumed.saved_hashes == straight.saved_hashes
	), "resumes %s at %s;\n      loaded %s\n      saved  %s" % [
		resumed.resumes, resumed.resume_points, resumed.loaded_darkness, resumed.saved_darkness,
	])
	var after_save: Array = []
	for wire: Variant in straight.facts:
		var fact: CombatFact = CombatFact.from_wire(wire as Array)
		if fact != null and fact.seq > straight.saved_seqs[0]:
			after_save.append(fact)
	var releases: int = 0
	var hurt: int = 0
	for fact: CombatFact in after_save:
		var is_release: bool = (fact.flags & CombatFact.Flag.DARKNESS_RELEASED) != 0
		if fact.kind == CombatFact.Kind.DARKNESS_ADVANCED and is_release:
			releases += 1
		if fact.kind == CombatFact.Kind.DARKNESS_DAMAGE_TAKEN:
			hurt += 1
	_check("service resume after arrival: a release and darkness damage after the save", (
			releases >= 1 and hurt >= 1
	), "%d releases, %d hurt" % [releases, hurt])
	_check("service resume after arrival: the same fact log and darkness as uninterrupted", (
			not straight.facts.is_empty()
			and JSON.stringify(resumed.facts) == JSON.stringify(straight.facts)
			and resumed.darkness == straight.darkness
			and resumed.next_after == straight.next_after
	), "%d and %d facts;\n      %s\n      %s" % [
		resumed.facts.size(), straight.facts.size(), resumed.darkness, straight.darkness,
	])
	return true


# Plays the arrival script on a new solo run's M1 battle: Start, then End Turn until turn
# ARRIVAL_SAVE_TURN; a checkpoint; then End Turn twice (turn 6's darkness phase, its damage and
# release, then turn 7's). With [param quits], the checkpoint is followed by a quit and a Continue.
# [member ResumeRun.darkness] is the darkness at the end, as captured.
func _play_arrival_script(saves: Node, service: Node, quits: bool) -> ResumeRun:
	var result: ResumeRun = ResumeRun.new()
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var built: StartingArmy = StartingArmy.build(EffectCatalog.index(), "mercenary", run.ids)
	if service.call(&"begin_battle", _m1_request(run, built)) != OK:
		result.errors.append("begin")
		return result
	_resume_step(result, run, StartCommand.new(0))
	var session: CombatSession = run.encounter.get_session(0)
	while session.state.turn < ARRIVAL_SAVE_TURN and result.errors.is_empty():
		_resume_step(result, run, EndTurnCommand.new(0))
		session = run.encounter.get_session(0)

	result.saved_turns.append(session.state.turn)
	result.saved_hashes.append(session.state_hash())
	result.saved_seqs.append(session.last_seq())
	result.saved_darkness.append(JSON.stringify(session.state.map.darkness.capture()))
	result.has_arrived = session.state.map.has_darkness_arrived
	if saves.call(&"save_checkpoint") != OK:
		result.errors.append("save")
	if quits:
		saves.call(&"close_save_file")
		saves.call(&"open_save_file", 1)
		saves.call(&"continue_solo_run")
		run = service.get(&"session")
		result.resume_points.append(saves.get(&"resume_point"))
		result.resumes.append(service.call(&"resume_battle", _m1_request(run, built)))
		if run.encounter == null:
			result.errors.append("resume")
			return result
		session = run.encounter.get_session(0)
		result.loaded_hashes.append(session.state_hash())
		result.loaded_darkness.append(JSON.stringify(session.state.map.darkness.capture()))

	_resume_step(result, run, EndTurnCommand.new(0))
	_resume_step(result, run, EndTurnCommand.new(0))
	session = run.encounter.get_session(0)
	result.darkness = JSON.stringify(session.state.map.darkness.capture())
	result.next_after = run.ids.get_next_value()
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return result


# How many values the resume script set (7) a write-back brought back: in a unit or item instance's
# counters, or a carrier's campaign lane.
func _written_count(written: Dictionary) -> int:
	var found: int = 0
	# Untyped: an instance's entry is [counters, charges], a carrier's its count.
	for key: Variant in written:
		var entry: Variant = written[key]
		if entry is int and entry == 7:
			found += 1
		elif entry is Array:
			for count: Variant in ((entry as Array)[0] as Dictionary).values():
				if count is int and count == 7:
					found += 1
	return found


# A saved battle that can't be resumed restarts from Begin: a combat file without the combat state
# pair (not holding), then one whose map id isn't the rebuilt battle's (load_into refuses).
func _test_service_resume_falls_back() -> bool:
	if not _has_test_user_dir():
		_skips += 1
		print("SKIP  service resume fallback: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var no_battle: int = service.call(&"resume_battle", _m1_request(
			service.get(&"session") as CampaignSession, null
	))
	_check("service resume fallback: nothing to resume outside a saved battle", (
			no_battle == ERR_UNCONFIGURED
	), error_string(no_battle))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	var combat_path: String = (
			(saves.call(&"get_save_file_dir", 1) as String)
			+ CombatData.get_file_name(CampaignData.Mode.SOLO)
	)

	var cases: Dictionary[String, Callable] = {
		# Both: effects alone refuses to load without combat_state, which is BATTLE_RETRY at once.
		"without combat_state and effects": func(sections: Dictionary) -> void:
			sections.erase("combat_state")
			sections.erase("effects"),
		"for another map": func(sections: Dictionary) -> void:
			var data: Dictionary = (sections["combat_map"] as Dictionary)["data"]
			((data["sessions"] as Array)[0] as Dictionary)["map_id"] = "another_map",
	}
	for label: String in cases:
		# A run of its own each time: a restart's save moves the campaign past the old combat file.
		SaveFile.delete_folder("user://saves/")
		saves.call(&"open_save_file", 1)
		saves.call(&"start_new_solo_run", RUN_SEED)
		var run: CampaignSession = service.get(&"session")
		var begun: int = service.call(&"begin_battle", _m1_request(run, null))
		run.encounter.submit(StartCommand.new(0), 0)
		run.encounter.resolve_queued()
		saves.call(&"save_checkpoint")
		saves.call(&"close_save_file")
		var broken: Dictionary = SaveFile.read(combat_path).envelope
		cases[label].call(broken[SaveFile.KEY_SECTIONS] as Dictionary)
		SaveFile.write(combat_path, broken)
		saves.call(&"open_save_file", 1)
		saves.call(&"continue_solo_run")
		var continued: CampaignSession = service.get(&"session")
		var point: int = saves.get(&"resume_point")
		print("    (a warning or error about a battle that restarts from Begin follows)")
		var err: int = service.call(&"resume_battle", _m1_request(continued, null))
		var session: CombatSession = (
				null if continued.encounter == null else continued.encounter.get_session(0)
		)
		var after: int = saves.get(&"resume_point")
		_check("service resume fallback: a file %s restarts the battle from Begin" % [label], (
				begun == OK
				and point == CombatData.ResumePoint.BATTLE
				and err == OK
				and after == CombatData.ResumePoint.BATTLE_RETRY
				and saves.get(&"combat") != null
				and SaveFile.exists(combat_path)
				and session != null
				and session.state.map.opening_swap_open
		), "%s, point %d then %d" % [error_string(err), point, after])
		saves.call(&"abandon_run", CampaignData.Mode.SOLO)
		saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return true


# Plays the resume script on a new solo run's M1 battle: Start; a campaign-lane count on a loaded
# unit effect and on the heirloom's copy; then a unit's move and Wait (a checkpoint), End Turn,
# another unit's move and Wait (a checkpoint), End Turn and one more Wait; then the battle's end.
# With [param quits], each checkpoint is followed by a quit and a Continue, and the battle is
# resumed from a request holding the army kept from Begin.
func _play_resume_script(saves: Node, service: Node, quits: bool) -> ResumeRun:
	var result: ResumeRun = ResumeRun.new()
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = service.get(&"session")
	var built: StartingArmy = StartingArmy.build(EffectCatalog.index(), "mercenary", run.ids)
	if service.call(&"begin_battle", _m1_request(run, built)) != OK:
		result.errors.append("begin")
		return result
	_resume_step(result, run, StartCommand.new(0))
	var session: CombatSession = run.encounter.get_session(0)
	for instance: EffectInstance in session.engine.get_instances():
		var owner_id: String = instance.owner.owner_id
		var is_loaded: bool = not instance.definition.resource_path.is_empty()
		if (
				instance.owner.kind == EffectOwner.Kind.ARMY
				or (is_loaded and owner_id == built.units[0].instance_id)
		):
			instance.set_counter(EffectTerms.Lane.CAMPAIGN, 7)
			result.counted.append(instance.instance_id)

	for turn: int in [1, 2]:
		_resume_step(result, run, _wait_step(run, 0))
		session = run.encounter.get_session(0)
		result.saved_turns.append(session.state.turn)
		result.saved_hashes.append(session.state_hash())
		result.saved_seqs.append(session.last_seq())
		result.saved_next.append(run.ids.get_next_value())
		result.known_at_last_save = run.ids.capture()["labels"]
		result.has_arrived = result.has_arrived or session.state.map.has_darkness_arrived
		if saves.call(&"save_checkpoint") != OK:
			result.errors.append("save %d" % [turn])
		if quits:
			saves.call(&"close_save_file")
			saves.call(&"open_save_file", 1)
			saves.call(&"continue_solo_run")
			run = service.get(&"session")
			result.resume_points.append(saves.get(&"resume_point"))
			result.resumes.append(service.call(&"resume_battle", _m1_request(run, built)))
			if run.encounter == null:
				result.errors.append("resume %d" % [turn])
				return result
			session = run.encounter.get_session(0)
			result.loaded_hashes.append(session.state_hash())
			result.loaded_seqs.append(session.last_seq())
			result.loaded_next.append(run.ids.get_next_value())
		var turn_before: int = session.state.turn
		_resume_step(result, run, EndTurnCommand.new(0))
		if run.encounter.get_session(0).state.turn != turn_before + 1:
			result.errors.append("end turn %d" % [turn])
	_resume_step(result, run, _wait_step(run, 1))
	session = run.encounter.get_session(0)
	var darkness: DarknessState = session.state.map.darkness
	result.darkness = "%d sources, drain %s, first release %d" % [
		darkness.sources.size(), darkness.drain, darkness.first_release,
	]
	result.has_arrived = result.has_arrived or session.state.map.has_darkness_arrived
	result.minted = run.ids.next_effect_id()
	result.next_after = run.ids.get_next_value()

	if service.call(&"end_battle") == null:
		result.errors.append("end battle")
	for unit: UnitInstance in built.units:
		result.written[unit.instance_id] = [unit.counters.duplicate(), unit.charges.duplicate()]
	for item_id: String in built.items:
		var item: ItemInstance = built.items[item_id]
		result.written[item_id] = [item.counters.duplicate(), item.charges.duplicate()]
	for instance_id: String in result.counted:
		var carrier: EffectInstance = run.get_carrier(instance_id)
		if carrier != null:
			result.written[instance_id] = carrier.get_counter(EffectTerms.Lane.CAMPAIGN)
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	return result


# Resolves command on the run's battle and adds every fact recorded since the last one added, by
# seq, so a resumed session's log, which starts empty, follows on.
func _resume_step(result: ResumeRun, run: CampaignSession, command: Command) -> void:
	run.encounter.submit(command, 0)
	for batch: CombatSession.FactBatch in run.encounter.resolve_queued():
		if batch.is_rejected():
			result.errors.append("%s: %s" % [batch.label, batch.rejected_reason])
	for fact: CombatFact in run.encounter.get_session(0).engine.fact_log:
		if fact.seq > result.last_seq:
			result.facts.append(fact.to_wire())
			result.last_seq = fact.seq


# The index-th unit of seat 0 that can act, its commander left out (a walk toward the enemies could
# lose the battle): a Wait one tile away, the first such move tile in move_tiles order.
func _wait_step(run: CampaignSession, index: int) -> UnitTurnCommand:
	var session: CombatSession = run.encounter.get_session(0)
	var acting: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var commander_id: String = session.commander_ids.get(0, "")
	acting.erase(commander_id)
	var unit_id: String = acting[index]
	var origin: Vector2i = session.state.tile_of(unit_id)
	var goal: Vector2i = origin
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		if session.state.grid.distance(tile, origin) == 1:
			goal = tile
			break
	var walk: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, goal)
	return UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", walk)


# The gameplay screen's request for the M1 battle (gameplay.tscn: M1, floor 1, node 1), with
# built's army; a new mercenary army when built is null. On the real catalog with the M1 pack its
# only pack, so the battle the script was written against is the one drawn.
func _m1_request(run: CampaignSession, built: StartingArmy) -> CampaignSession.BattleRequest:
	var catalog: EffectCatalog.Index = PackCatalog.with_only(EffectCatalog.index(), "m1_pack")
	var army_of: StartingArmy = (
			built if built != null else StartingArmy.build(catalog, "mercenary", run.ids)
	)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = army_of.units
	army.item_instances = army_of.items
	army.heirloom_ids = army_of.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = M1_FLOOR
	request.node = M1_NODE
	request.pool = [load(M1_DEFINITION) as CombatMapDefinition]
	request.catalog = catalog
	request.armies[0] = army
	return request


# What one play of the resume script recorded (_play_resume_script).
class ResumeRun:
	extends RefCounted

	var errors: PackedStringArray = []
	# Every fact of the battle's map as wire arrays, in seq order, and the last seq added.
	var facts: Array = []
	var last_seq: int = 0
	# Per Continue: resume_point, then resume_battle()'s error.
	var resume_points: Array[int] = []
	var resumes: Array[int] = []
	# Per checkpoint, as saved and (with quits) as loaded.
	var saved_turns: Array[int] = []
	var saved_hashes: Array[int] = []
	var loaded_hashes: Array[int] = []
	var saved_seqs: Array[int] = []
	var loaded_seqs: Array[int] = []
	var saved_next: Array[int] = []
	var loaded_next: Array[int] = []
	# The allocator's labels at the last checkpoint: every id minted until then.
	var known_at_last_save: Dictionary = {}
	# The effect instances given a campaign-lane count of 7.
	var counted: PackedStringArray = []
	var darkness: String = ""
	var has_arrived: bool = false
	# Per checkpoint, the darkness captured as saved and (with quits) as loaded.
	var saved_darkness: PackedStringArray = []
	var loaded_darkness: PackedStringArray = []
	# The id minted after the last command, and the counter after it.
	var minted: String = ""
	var next_after: int = 0
	# After the battle's end: [counters, charges] by unit or item id, and each counted carrier's
	# campaign lane by id.
	var written: Dictionary = {}
