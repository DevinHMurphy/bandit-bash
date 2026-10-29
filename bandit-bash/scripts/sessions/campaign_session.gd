# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_session.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name CampaignSession
extends RefCounted
## One run in progress on the host: its stream registry, its id allocator, its campaign bus, and
## the bridge into each battle.
##
## Built by the [code]CampaignService[/code] autoload when a run becomes active and closed when it
## ends. Host and solo only: a multiplayer client holds none until client mirrors (EB7) and
## transport (P10) exist (event bus plan, question 41). Rules code never sees [member rng]: this
## session hands each consumer the one stream it needs.[br]
## [b]The battle bridge:[/b] [method begin_battle] builds the [CombatEncounter], runs its setup,
## opens one [CombatSession] per seat, registers copies of the run's effect carriers (in the
## encounter for cross-map scopes) with their campaign-lane counters, loads each army's unit
## instances ([Loadout]) and deploys each army.
## [method write_back] copies campaign-lane counters and charges back before
## [code]SaveService.end_battle()[/code]; [method end_battle] then drops the battle and its combat
## lanes. Observers find each battle through [signal combat_encounter_opened].[br]
## [b]Grants:[/b] [CampaignGrant]s that apply in battle reach [method receive_grant] after their
## batch, which records and reports them; no save section is registered yet (question 42).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Apply recorded grants: gold, heirlooms, recruits and runes (P08).
## @todo: TOD-002 - Hand the reinforcement waves P05's group source; the base draws no group.

## A battle began: its setup ran and its sessions are about to open, so a listener can connect to
## [signal CombatEncounter.session_opened] first.
signal combat_encounter_opened(encounter: CombatEncounter)

## A battle ended or the run was closed mid-battle; [param encounter] is closed.
signal combat_encounter_closed(encounter: CombatEncounter)

## A grant was received and recorded.
signal grant_recorded(grant: Grant)

# The NetLog autoload's script, for its type and enums; see CombatSession.logger().
const NetLogScript = preload("res://scripts/autoload/net_log.gd")

## Which campaign slot the run belongs to.
var mode: CampaignData.Mode = CampaignData.Mode.SOLO

## The run's seats, ascending; solo is seat 0.
var seats: PackedInt32Array = []

## The run's live random streams. Held here only; consumers are handed single streams.
var rng: RngStreams = null

## Mints every instance id of the run.
var ids: InstanceIdAllocator = InstanceIdAllocator.new()

## Presentation signals for campaign facts.
var bus: CampaignBus = CampaignBus.new()

## The battle in progress; null outside one.
var encounter: CombatEncounter = null

## Every grant received this run, in order.
var grants: Array[Grant] = []

## Whether [method close] was called: the run ended or its save file closed.
var is_closed: bool = false

## The per-draw trace flag handed to every battle's sessions
## ([member CombatSession.is_tracing_draws]). Off by default.
var is_tracing_draws: bool = false

# The run's effect carriers on the campaign layer (unit traits, items, heirlooms, curses), by
# instance id: the side that keeps campaign-lane values between battles.
var _carriers: Dictionary[String, EffectInstance] = {}

# The copies registered in the battle in progress, by instance id.
var _battle_copies: Dictionary[String, EffectInstance] = {}

# The units the battle in progress loaded from instances, for write_back().
var _loaded: Array[Loadout.LoadedUnit] = []

# Heirlooms already made carriers, as "seat:content id", so a second battle doesn't add them again.
var _heirloom_carriers: Dictionary[String, bool] = {}

# Setup steps other plans registered, applied to every battle: [step, Callable] pairs.
var _setup_steps: Array[Array] = []

# Grants received since the battle began.
var _battle_grants: Array[Grant] = []

# Where reinforcement waves' groups come from, for setup step 5 and their arrivals.
# TODO(TOD-002): P05's enemy groups; this base draws none, so no point sends a wave yet.
var _wave_groups: Reinforcements.GroupSource = Reinforcements.GroupSource.new()


## [param run_seed]: the campaign's seed. [param run_seats]: every seat of the run. Registers the
## combat map's own setup steps: the reinforcement waves ([method Reinforcements.draw_waves]) and
## each container's contents ([method MapObjects.roll_contents]).
func _init(run_mode: CampaignData.Mode, run_seed: int, run_seats: PackedInt32Array) -> void:
	mode = run_mode
	seats = run_seats.duplicate()
	seats.sort()
	rng = RngStreams.new(run_seed)
	for seat: int in seats:
		ids.set_label(InstanceIdAllocator.seat_subject_id(seat), "army of seat %d" % [seat])
	add_setup_step(
			CombatEncounter.SetupStep.REINFORCEMENT_WAVES,
			Reinforcements.draw_waves.bind(_wave_groups)
	)
	add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, MapObjects.roll_contents)


## Adds [param instance] to the run's carriers: a unit trait, an item's effect, a heirloom or a
## curse, with its owner. Its campaign-lane counter and charges live here between battles. Returns
## false for an instance already added.
func add_carrier(instance: EffectInstance) -> bool:
	if instance == null or _carriers.has(instance.instance_id):
		return false
	_carriers[instance.instance_id] = instance
	return true


## The carrier [param instance_id] on the campaign layer; null when unknown.
func get_carrier(instance_id: String) -> EffectInstance:
	return _carriers.get(instance_id, null)


## Registers [param run] for [param step] in every battle this run begins, after the steps
## registered before it ([method CombatEncounter.add_setup_step]).
func add_setup_step(step: CombatEncounter.SetupStep, run: Callable) -> void:
	_setup_steps.append([step, run])


## Begins the battle [param request] describes: builds the encounter, runs its setup from fresh
## setup streams (so a restart from Begin rolls the same), emits [signal combat_encounter_opened],
## opens one session per seat with its seat's [code]COMBAT_ROLLS[/code] stream, places each map's
## objects ([method MapObjects.place]) and reinforcement points ([method Reinforcements.register]),
## registers copies of the carriers of the units and armies in the battle, deploys each army, then
## opens each map's battle
## ([method CombatSession.open_battle]): the opening swap window for the seats whose
## [member BattleRequest.opening_swap] setting is on, turn 1's player Phase Start otherwise. Returns
## the encounter; null, with nothing begun, when a battle is already on, the run is closed, or setup
## fails.
func begin_battle(request: BattleRequest) -> CombatEncounter:
	if is_closed or encounter != null or request == null:
		push_error("CampaignSession: can't begin a battle now")
		return null
	var battle: CombatEncounter = CombatEncounter.new(
			request.floor_number, request.node, seats, ids
	)
	for entry: Array in _setup_steps:
		var step: CombatEncounter.SetupStep = entry[0]
		var run: Callable = entry[1]
		battle.add_setup_step(step, run)
	var streams: CombatEncounter.SetupStreams = CombatEncounter.SetupStreams.new(
			rng.run_seed, request.floor_number, request.node
	)
	var err: Error = battle.run_setup(request.pool, streams)
	if err != OK:
		push_error("CampaignSession: battle setup failed - %s" % [error_string(err)])
		return null

	encounter = battle
	_battle_grants.clear()
	combat_encounter_opened.emit(battle)
	var rolls: Dictionary[int, RngStream] = {}
	for seat: int in seats:
		rolls[seat] = _combat_rolls(request.floor_number, request.node, seat)
	battle.open_sessions(rolls)
	for session: CombatSession in battle.get_sessions():
		session.is_tracing_draws = is_tracing_draws
		session.grant_received.connect(receive_grant)
		# Before deployment, so no unit takes a breakable's tile.
		MapObjects.place(session)
		# P06's darkness step registers before this (reinforcements.gd:TOD-001).
		Reinforcements.register(session, _wave_groups)
	var catalog: EffectCatalog.Index = (
			request.catalog if request.catalog != null else EffectCatalog.index()
	)
	for seat: int in request.armies:
		_add_heirlooms(catalog, seat, request.armies[seat].heirloom_ids)
	_register_carriers(battle, request)
	for seat: int in seats:
		var army: Army = request.armies.get(seat, null)
		var session: CombatSession = battle.session_of_seat(seat)
		if army == null:
			continue
		var units: Array[CombatUnitState] = army.units.duplicate()
		var bases: Dictionary[String, Dictionary] = army.bases.duplicate()
		var commander_id: String = army.commander_id
		for weapon: CombatState.WeaponStats in army.weapons:
			session.state.add_weapon(weapon)
		# Effects before deployment, so the full Stance set at placement counts them.
		for loaded: Loadout.LoadedUnit in _load_army(catalog, army, seat):
			for weapon: CombatState.WeaponStats in loaded.weapons:
				session.state.add_weapon(weapon)
			for instance: EffectInstance in loaded.effects:
				session.engine.register(instance)
			units.append(loaded.state)
			bases[loaded.state.id] = loaded.bases
			if commander_id.is_empty() and catalog.commander(loaded.state.unit_type) != null:
				commander_id = loaded.state.id
		session.deploy(units, bases, commander_id)
		session.flush("deployment")
	for session: CombatSession in battle.get_sessions():
		var swap_seats: PackedInt32Array = []
		for seat: int in session.seats:
			if request.opening_swap.get(seat, true):
				swap_seats.append(seat)
		session.open_battle(swap_seats)

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net != null:
		net.info(
				NetLogScript.Category.CAMPAIGN,
				"BATTLE START floor %d node %d map %s seats %s"
				% [request.floor_number, request.node, battle.setup.map.id, seats]
		)
	return battle


## Copies every registered carrier's campaign-lane counter, and its charges when they refill per
## run, back from the battle to the campaign layer, and each loaded unit's to its unit and item
## instances ([method Loadout.LoadedUnit.write_back]). Combat lanes stay behind. Call before
## [code]SaveService.end_battle()[/code]; calling it twice changes nothing more.
func write_back() -> void:
	for loaded: Loadout.LoadedUnit in _loaded:
		loaded.write_back()
	for instance_id: String in _battle_copies:
		var copy: EffectInstance = _battle_copies[instance_id]
		var carrier: EffectInstance = _carriers.get(instance_id, null)
		if carrier == null:
			continue
		carrier.set_counter(
				EffectTerms.Lane.CAMPAIGN, copy.get_counter(EffectTerms.Lane.CAMPAIGN)
		)
		if carrier.definition.charge_lane == EffectTerms.Lane.CAMPAIGN:
			carrier.charges_left = copy.charges_left


## Ends the battle in progress: [method write_back], then the result is collected, the encounter
## closed and [signal combat_encounter_closed] emitted; every combat lane is dropped with it.
## Returns what the run flow applies afterwards; null when no battle is on.
func end_battle() -> BattleResult:
	if encounter == null:
		return null
	write_back()
	var result: BattleResult = BattleResult.new()
	result.grants = _battle_grants.duplicate()
	for session: CombatSession in encounter.get_sessions():
		for unit_id: String in session.state.units_of(CombatFact.CombatSide.PLAYER):
			if encounter.session_of_unit(unit_id) == session:
				_collect_growth(result, session, unit_id)
	var map_id: String = encounter.setup.map.id
	abandon_battle()

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net != null:
		net.info(NetLogScript.Category.CAMPAIGN, "BATTLE END map %s" % [map_id])
	return result


## Records a grant from an effect that fired in battle and reports it at INFO.
## [param grant]: a [enum CampaignGrant.Grant]. Connected to every session's
## [signal CombatSession.grant_received].
func receive_grant(
		seat: int, grant: int, amount: int, definition_id: String, source_effect_id: String
) -> void:
	var record: Grant = Grant.new()
	record.seat = seat
	record.grant = grant as CampaignGrant.Grant
	record.amount = amount
	record.definition_id = definition_id
	record.source_effect_id = source_effect_id
	grants.append(record)
	_battle_grants.append(record)
	grant_recorded.emit(record)
	# TODO(TOD-001): Apply the grant to the seat's gold, heirlooms, roster or rune slots (P08).
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net != null:
		net.info(
				NetLogScript.Category.CAMPAIGN,
				"GRANT seat %d %s from %s"
				% [seat, record.describe(), describe(source_effect_id)]
		)


## Drops the battle in progress without writing anything back and emits
## [signal combat_encounter_closed]: for a battle whose Begin save failed, or a run that ends
## mid-battle. Does nothing outside a battle.
func abandon_battle() -> void:
	if encounter == null:
		return
	var closed: CombatEncounter = encounter
	encounter = null
	_battle_copies.clear()
	_loaded.clear()
	for session: CombatSession in closed.get_sessions():
		if session.grant_received.is_connected(receive_grant):
			session.grant_received.disconnect(receive_grant)
	closed.close()
	combat_encounter_closed.emit(closed)


## Closes the run's session: a battle in progress is dropped without writing back, and nothing is
## begun again.
func close() -> void:
	if is_closed:
		return
	if encounter != null:
		abandon_battle()
	is_closed = true


## [param id] in log text: from the battle in progress when it knows it, else the allocator.
func describe(id: String) -> String:
	return ids.describe(id) if encounter == null else encounter.describe(id)


# Registers a copy of each carrier whose owner is in the battle: a unit's or item's on its
# holder's map, an army's on its seat's map or, for a cross-map scope, in the encounter. A copy
# keeps the campaign lane and starts its combat lane fresh.
func _register_carriers(battle: CombatEncounter, request: BattleRequest) -> void:
	var in_battle: Dictionary[String, int] = {}
	for seat: int in request.armies:
		for unit: CombatUnitState in request.armies[seat].units:
			in_battle[unit.id] = seat
		for unit: UnitInstance in request.armies[seat].unit_instances:
			in_battle[unit.instance_id] = seat
	var carrier_ids: Array[String] = []
	carrier_ids.assign(_carriers.keys())
	carrier_ids.sort()
	for instance_id: String in carrier_ids:
		var carrier: EffectInstance = _carriers[instance_id]
		var owner: EffectOwner = carrier.owner
		var seat: int = owner.seat
		if owner.kind == EffectOwner.Kind.UNIT or owner.kind == EffectOwner.Kind.ITEM:
			if not in_battle.has(owner.holder_id):
				continue
			seat = in_battle[owner.holder_id]
		elif owner.kind != EffectOwner.Kind.ARMY:
			continue
		var session: CombatSession = battle.session_of_seat(seat)
		if session == null:
			continue
		var copy: EffectInstance = carrier.copy()
		if not battle.add_cross_map(copy):
			session.engine.register(copy)
		_battle_copies[instance_id] = copy


# Loads each of the army's unit instances (Loadout.load_unit), reporting what was wrong with their
# data. Returns the units that loaded, in roster order; they are kept for write_back().
func _load_army(catalog: EffectCatalog.Index, army: Army, seat: int) -> Array[Loadout.LoadedUnit]:
	var units: Array[Loadout.LoadedUnit] = []
	for unit: UnitInstance in army.unit_instances:
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(
				catalog, unit, army.item_instances, CombatFact.CombatSide.PLAYER, seat, ids
		)
		for problem: String in loaded.problems:
			push_error("CampaignSession: %s" % [problem])
		if loaded.is_loaded():
			units.append(loaded)
			_loaded.append(loaded)
	return units


# Makes each heirloom of [param heirloom_ids] a carrier of the run for [param seat], once.
func _add_heirlooms(
		catalog: EffectCatalog.Index, seat: int, heirloom_ids: PackedStringArray
) -> void:
	for heirloom_id: String in heirloom_ids:
		var key: String = "%d:%s" % [seat, heirloom_id]
		if _heirloom_carriers.has(key):
			continue
		if catalog.heirloom(heirloom_id) == null:
			push_error("CampaignSession: heirloom \"%s\" is not in the catalog" % [heirloom_id])
			continue
		for instance: EffectInstance in Loadout.heirloom_effects(catalog, heirloom_id, seat, ids):
			add_carrier(instance)
		_heirloom_carriers[key] = true


func _collect_growth(result: BattleResult, session: CombatSession, unit_id: String) -> void:
	var changes: Dictionary[int, int] = session.state.unit(unit_id).growth_changes
	if changes.is_empty():
		return
	result.growth_changes[unit_id] = changes.duplicate()


# The seat's COMBAT_ROLLS stream for the battle, logged at DEBUG with its key and seed.
func _combat_rolls(floor_number: int, node: int, seat: int) -> RngStream:
	var key: RngKey = RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, floor_number, node, seat, -1)
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.DEBUG, NetLogScript.Category.COMBAT
	)
	if net != null:
		var stream_seed: int = RngKey.derive_seed(
				rng.run_seed, key.purpose, floor_number, node, seat, -1
		)
		net.debug(
				NetLogScript.Category.COMBAT,
				"stream COMBAT_ROLLS key %s seed %d" % [key.to_save_key(), stream_seed]
		)
	return rng.stream(key)


## What a battle begins from: its node, its map pool and each seat's army, as unit and item
## instances for [Loadout], plain combat data, or both.
class BattleRequest:
	extends RefCounted

	## The campaign floor of the combat node.
	var floor_number: int = -1
	## The combat node on its floor.
	var node: int = -1
	## The maps the node can draw from, in a fixed order.
	var pool: Array[CombatMapDefinition] = []
	## Each seat's army, by seat. A seat without one gets an empty map.
	var armies: Dictionary[int, Army] = {}
	## The content the loadout reads. [b]Null:[/b] the loaded catalog
	## ([method EffectCatalog.index]); tests pass a fixture tree.
	var catalog: EffectCatalog.Index = null
	# ASSUMPTION: a seat with no entry has the setting on, until P07 owns the setting's default.
	## Each seat's opening-swap setting, by seat (the setting itself is P07's): on, its map opens in
	## the swap window before turn 1 and waits for its Start command; off, turn 1 starts at once. A
	## seat with no entry has it on.
	var opening_swap: Dictionary[int, bool] = {}


## One seat's army for a battle: units already in combat form ([member units]), units to load
## ([member unit_instances]), or both; loaded units deploy after the others, in roster order.
class Army:
	extends RefCounted

	## The units in roster order, not yet on a map; ids minted by the run's allocator.
	var units: Array[CombatUnitState] = []
	## Each unit's base values (value key to number), by unit id.
	var bases: Dictionary[String, Dictionary] = {}
	## The records of the weapons the units hold.
	var weapons: Array[CombatState.WeaponStats] = []
	## The commander's id; empty when the army has none here. [b]Empty with
	## [member unit_instances]:[/b] the loaded unit whose type is a commander.
	var commander_id: String = ""
	## Units to load ([method Loadout.load_unit]), in roster order. Their campaign-lane counters
	## and charges are written back to them at battle end. [b]Empty:[/b] none.
	var unit_instances: Array[UnitInstance] = []
	## The item instances [member unit_instances] carry, by instance id.
	var item_instances: Dictionary[String, ItemInstance] = {}
	## Content ids of the seat's heirlooms and curses, its Commander Heirloom included. Each is
	## made a carrier of the run the first time a battle names it, so its campaign lane lasts the
	## run ([method Loadout.heirloom_effects]). [b]Empty:[/b] none.
	var heirloom_ids: PackedStringArray = []


## What a battle leaves for the run flow to apply (P08).
class BattleResult:
	extends RefCounted

	## Growth changes gained this battle, by unit id: stat ([enum CombatValue.Stat]) to percentage
	## points (event bus plan, fix F11).
	var growth_changes: Dictionary[String, Dictionary] = {}
	## Grants received during the battle, in order.
	var grants: Array[Grant] = []


## One grant received from an effect: who gets what, and from which effect.
class Grant:
	extends RefCounted

	## The seat that gets it.
	var seat: int = -1
	## What is granted.
	var grant: CampaignGrant.Grant = CampaignGrant.Grant.GOLD
	## Gold, for [constant CampaignGrant.Grant.GOLD].
	var amount: int = 0
	## The heirloom, unit type or rune granted; may be empty.
	var definition_id: String = ""
	## The effect instance that granted it.
	var source_effect_id: String = ""

	## The grant in words, such as [code]gold 50[/code] or [code]rune mend[/code].
	func describe() -> String:
		var kind: String = (CampaignGrant.Grant.find_key(grant) as String).to_lower()
		if grant == CampaignGrant.Grant.GOLD:
			return "%s %d" % [kind, amount]
		return kind if definition_id.is_empty() else "%s %s" % [kind, definition_id]
