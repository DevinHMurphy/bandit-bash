# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_session.gd
# Author:
# Created:  October 28, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name CampaignSession
extends RefCounted
## One run in progress on the host: its streams, its id allocator, its campaign bus, its
## [member run] and the bridge into each battle. Built by [code]CampaignService[/code] when a run
## becomes active and closed when it ends; host and solo only. Consumers get single streams.[br]
## [b]The battle bridge:[/b] [method begin_battle] sets a [BattleRequest] up as a [CombatEncounter]
## (the run's from [method CampaignRunState.battle_request]): one [CombatSession] per seat, its
## objects, enemies and darkness, a copy of every run carrier (one per held copy of a heirloom or
## curse, with its saved campaign lane) and each army loaded and deployed. [method resume_battle]
## rebuilds a saved battle the same way and loads the save into it. [method collect_battle] writes
## campaign lanes back and gathers the [BattleResult] with the battle still on;
## [method end_battle] drops it. [member tally] and [member battle_grants] observe the battle and
## are saved with it; the run applies both at its end ([method CampaignRunState.apply_battle]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-003 - Send each co-op seat's opening-swap setting to the host (P11); no entry means
## on. Solo's comes from the battle screen's request (the player's settings).
## @todo: TOD-004 - Pass the enemy level modifiers (difficulty ladder, run modifiers) to the enemy
## draws.

## A battle began: its setup ran and its sessions are about to open, so a listener can connect to
## [signal CombatEncounter.session_opened] first.
signal combat_encounter_opened(encounter: CombatEncounter)

## A battle ended or the run was closed mid-battle; [param encounter] is closed.
signal combat_encounter_closed(encounter: CombatEncounter)

## A grant was received and recorded.
signal grant_recorded(grant: Grant)

## A campaign command resolved or was rejected ([method submit]); presentation plays its facts.
signal campaign_batch_resolved(batch: CampaignBatch)

## The campaign command [param seat] sent, stamped [param arrival], was rejected and changed
## nothing. Tells only that seat.
signal command_rejected(seat: int, arrival: int, reason: String)

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

## The run's campaign state: map, route, flow and each seat's part. Null until
## [code]CampaignService[/code] builds a new run or loads the saved one into it.
var run: CampaignRunState = null

## Every grant received this run, in order.
var grants: Array[Grant] = []

## The grants received since the battle in progress began, in order, for
## [method CampaignRunState.apply_battle]. Saved with the battle ([BattleTallySection]), so a
## resumed battle still applies the grants it received before the quit.
var battle_grants: Array[Grant] = []

## The XP actions each player unit has taken in the battle in progress, counted from every fact
## its maps record. Cleared at Begin, saved with the battle ([BattleTallySection]).
var tally: BattleTally = BattleTally.new()

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

# Each held heirloom or curse copy already made carriers, by _copy_key(), so a second battle
# doesn't add them again. A seat's k-th copy of an id is its k-th SeatRun entry of that id.
var _heirloom_carriers: Dictionary[String, HeirloomLane] = {}

# Setup steps other plans registered, applied to every battle: [step, Callable] pairs.
var _setup_steps: Array[Array] = []

# Ids of the maps the battle in progress could draw (its request's pool), for the result.
var _battle_pool_ids: PackedStringArray = []

# Ids of every army unit the battle's request named, in seat and roster order: the result reads
# each through its map, fallen ones included, which CombatState.units_of() leaves out.
var _battle_unit_ids: PackedStringArray = []

# The battle in progress's result once collect_battle() gathered it; null before.
var _collected: BattleResult = null

# The arrival stamp the next campaign command takes.
var _next_arrival: int = 1


## [param run_seed]: the campaign's seed. [param run_seats]: every seat of the run. Registers the
## darkness's sources and drain ([method DarknessSetup.draw]). The enemy steps (4 to 6) and the
## containers' contents ([method MapObjects.roll_contents]) read the battle's catalog, so each
## battle registers its own.
func _init(run_mode: CampaignData.Mode, run_seed: int, run_seats: PackedInt32Array) -> void:
	mode = run_mode
	seats = run_seats.duplicate()
	seats.sort()
	rng = RngStreams.new(run_seed)
	for seat: int in seats:
		ids.set_label(InstanceIdAllocator.seat_subject_id(seat), "army of seat %d" % [seat])
	add_setup_step(CombatEncounter.SetupStep.DARKNESS_SOURCES, DarknessSetup.draw)


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


## Begins the battle [param request] describes: the encounter with its enemy draw
## ([method EnemySetup.draw]) and setup from fresh streams (a restart from Begin rolls the same),
## [signal combat_encounter_opened], one session per seat on its [code]COMBAT_ROLLS[/code] stream,
## then per map its objects, enemies, darkness step, reinforcement points, darkness damage, AI and
## intents ([method MapObjects.place], [method EnemySetup.place], [method Darkness.register],
## [method Reinforcements.register], [method Darkness.register_damage], [method EnemyAI.register],
## [method Intents.register]), carrier copies, its darkness ([method DarknessSetup.place], so Short
## Wick counts), each army deployed, and [method CombatSession.open_battle] as
## [member BattleRequest.opening_swap] says.
## Returns the encounter; null, with nothing begun, when a battle is already on, the run is closed,
## or setup fails.
func begin_battle(request: BattleRequest) -> CombatEncounter:
	if not _can_open_battle(request):
		return null
	var catalog: EffectCatalog.Index = _catalog_of(request)
	var battle: CombatEncounter = _set_up_battle(request, catalog)
	if battle == null:
		return null
	for seat: int in request.armies:
		_add_heirlooms(catalog, seat, request.armies[seat].heirloom_ids)
	_register_carriers(battle, request)
	for session: CombatSession in battle.get_sessions():
		DarknessSetup.place(session)
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
			# TODO(TOD-003): co-op seats' settings don't reach the host yet (P11); no entry means on,
			# the setting's default (SettingsData.DEFAULT_OPENING_SWAP).
			if request.opening_swap.get(seat, true):
				swap_seats.append(seat)
		session.open_battle(swap_seats)
	_log_battle("BATTLE START", request, battle)
	return battle


## Rebuilds the saved battle [param request] describes (the request Begin had) as
## [method begin_battle] set it up, without the loadout, the deployment and the opening, which the
## save replaces; then [code]load_saved.call(battle) -> Error[/code] loads the save into it, before
## anything draws from a [code]COMBAT_ROLLS[/code] stream. The write-back copies are then re-linked
## to the loaded battle by instance id (each carrier's copy, each of the request's unit instances
## the battle holds), so [method write_back] writes what an uninterrupted battle would, and each
## map's intents are computed, recording nothing.
## Returns the encounter; null, with nothing begun, when a battle is already on, the run is closed,
## setup fails or [param load_saved] returns an error.
func resume_battle(request: BattleRequest, load_saved: Callable) -> CombatEncounter:
	if not _can_open_battle(request) or not load_saved.is_valid():
		return null
	var catalog: EffectCatalog.Index = _catalog_of(request)
	var battle: CombatEncounter = _set_up_battle(request, catalog)
	if battle == null:
		return null
	for seat: int in request.armies:
		_place_heirloom_stand_ins(battle, catalog, seat, request.armies[seat].heirloom_ids)
	_register_carriers(battle, request)
	# With the army's effects registered as at Begin, so the darkness arrives as it did.
	for session: CombatSession in battle.get_sessions():
		DarknessSetup.place(session)
	var err: Error = load_saved.call(battle)
	if err != OK:
		push_error("CampaignSession: the saved battle didn't load - %s" % [error_string(err)])
		abandon_battle()
		return null
	_relink_battle(battle, request, catalog)
	for session: CombatSession in battle.get_sessions():
		Intents.refresh(session, catalog)
	_log_battle("BATTLE RESUMED", request, battle)
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


## Gathers what the battle in progress leaves for the run, with the battle still on: first
## [method write_back], then each player unit's HP, fall, permanent stat deltas, growth changes
## and reward values, each heirloom copy's campaign lane, the grants received, a copy of the
## tally, the map, whether every map was won, and each seat's [SeatOutcome]. Rewards read item
## and heirloom values here, since they count only in battle. Calling it again returns the same
## result. Returns null when no battle is on.
func collect_battle() -> BattleResult:
	if encounter == null:
		return null
	if _collected != null:
		return _collected
	write_back()
	var result: BattleResult = BattleResult.new()
	result.floor_number = encounter.floor_number
	result.node = encounter.node
	result.map_id = encounter.setup.map.id
	result.pool_ids = _battle_pool_ids.duplicate()
	result.grants = battle_grants.duplicate()
	result.tally.restore(tally.capture())
	var sessions: Array[CombatSession] = encounter.get_sessions()
	result.is_finished = not sessions.is_empty()
	result.is_won = not sessions.is_empty()
	for session: CombatSession in sessions:
		result.is_finished = result.is_finished and session.is_finished
		result.is_won = result.is_won and session.is_finished and session.is_won
	for unit_id: String in _battle_unit_ids:
		var holder: CombatSession = encounter.session_of_unit(unit_id)
		if holder != null:
			_collect_growth(result, holder, unit_id)
			_collect_unit(result, holder, unit_id)
	for seat: int in seats:
		var map: CombatSession = encounter.session_of_seat(seat)
		if map != null:
			result.seats[seat] = _collect_seat(result, map, seat)
	_collect_heirlooms(result)
	_collected = result
	return result


## The streams [method CampaignRunState.apply_battle] draws [param result]'s rewards from: each
## seat's [code]REWARD[/code] and [code]LEVEL_UPS[/code] streams for the battle's node. They are
## the run's live streams, saved with the campaign; a failed save restores them
## ([code]CampaignService.end_battle()[/code]).
func reward_rolls(result: BattleResult) -> RewardRolls:
	var rolls: RewardRolls = RewardRolls.new()
	if result == null:
		return rolls
	for seat: int in seats:
		rolls.reward[seat] = rng.stream(RngKey.new(
				RngKey.RngPurpose.REWARD, result.floor_number, result.node, seat
		))
		rolls.level_ups[seat] = rng.stream(RngKey.new(
				RngKey.RngPurpose.LEVEL_UPS, result.floor_number, result.node, seat
		))
	return rolls


## Ends the battle in progress: its result is collected ([method collect_battle]) if it wasn't
## yet, the encounter closed and [signal combat_encounter_closed] emitted; every combat lane is
## dropped with it. Apply the result to the run and save it first
## ([code]CampaignService.end_battle()[/code]). Returns the result; null when no battle is on.
func end_battle() -> BattleResult:
	if encounter == null:
		return null
	var result: BattleResult = collect_battle()
	var map_id: String = result.map_id
	abandon_battle()

	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net != null:
		net.info(NetLogScript.Category.CAMPAIGN, "BATTLE END map %s" % [map_id])
	return result


## Stamps [param command] on arrival and resolves it on [member run] at once
## ([method CampaignRunState.resolve]), so the first arrival wins. Rejected, changing nothing,
## with no run, a closed run or a battle in progress. Emits [signal campaign_batch_resolved], and
## [signal command_rejected] for a rejection; logs it at INFO. Returns the batch; null for null.
## Saving is the caller's ([code]CampaignService.submit_command()[/code]).
func submit(command: CampaignCommand) -> CampaignBatch:
	if command == null:
		push_error("CampaignSession: submit needs a command")
		return null
	command.arrival = _next_arrival
	_next_arrival += 1
	var batch: CampaignBatch = null
	if run == null or is_closed or encounter != null:
		batch = CampaignBatch.new()
		batch.seat = command.seat
		batch.arrival = command.arrival
		batch.label = command.get_label()
		batch.rejected_reason = (
				"a battle is in progress" if encounter != null else "no run is in progress"
		)
	else:
		batch = run.resolve(command)
	if batch.is_rejected():
		command_rejected.emit(batch.seat, batch.arrival, batch.rejected_reason)
	_log_campaign_batch(batch)
	campaign_batch_resolved.emit(batch)
	return batch


## Records a grant from an effect that fired in battle and reports it at INFO; the run applies it
## when the battle ends ([method CampaignRunState.apply_battle]), through [member battle_grants].
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
	battle_grants.append(record)
	grant_recorded.emit(record)
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
	_collected = null
	for session: CombatSession in closed.get_sessions():
		if session.grant_received.is_connected(receive_grant):
			session.grant_received.disconnect(receive_grant)
		if session.fact_recorded.is_connected(_on_session_fact_recorded):
			session.fact_recorded.disconnect(_on_session_fact_recorded)
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


func _can_open_battle(request: BattleRequest) -> bool:
	if is_closed or encounter != null or request == null:
		push_error("CampaignSession: can't begin a battle now")
		return false
	return true


func _catalog_of(request: BattleRequest) -> EffectCatalog.Index:
	return request.catalog if request.catalog != null else EffectCatalog.index()


# The part of a battle's start Begin and a resume share: the encounter and its setup,
# combat_encounter_opened, the sessions on their COMBAT_ROLLS streams and each map's objects,
# enemies and hooks. Null, with nothing begun, when setup fails.
func _set_up_battle(request: BattleRequest, catalog: EffectCatalog.Index) -> CombatEncounter:
	var battle: CombatEncounter = CombatEncounter.new(
			request.floor_number, request.node, seats, ids
	)
	battle.run_seed = rng.run_seed
	# Bound per battle: the enemy draws read this battle's catalog and floor, and the waves' arrivals
	# build their units from the same source.
	# TODO(TOD-004): Pass the enemy level modifiers (the difficulty ladder's, run modifiers') once
	# they exist; none until then.
	var level_modifier: int = 0
	var waves: EnemySetup.WaveGroups = EnemySetup.WaveGroups.new(
			catalog, request.floor_number, level_modifier, request.standard_combats_in_step
	)
	# A fresh stream from its run key each battle, so the order is the same at every key combat
	# and nothing about it is saved; a standard map ignores the id.
	var order: RngStream = RngStream.new(RngKey.derive_seed(
			rng.run_seed, RngKey.RngPurpose.MINI_BOSS_DRAW, -1, -1, -1, -1
	))
	var mini_boss_id: String = EnemySetup.mini_boss_for(
			catalog, order, request.key_combats_before
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.ENEMY_SLOTS,
			EnemySetup.draw.bind(
					catalog,
					request.floor_number,
					level_modifier,
					request.standard_combats_in_step,
					mini_boss_id
			)
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.REINFORCEMENT_WAVES, Reinforcements.draw_waves.bind(waves)
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.SEAT_ADDITIONS,
			EnemySetup.draw_additions.bind(
					catalog, request.floor_number, level_modifier, _extra_enemies(catalog, request)
			)
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.CONTAINER_CONTENTS, MapObjects.roll_contents.bind(catalog)
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
	battle_grants.clear()
	tally.clear()
	_collected = null
	_battle_pool_ids = []
	for map: CombatMapDefinition in request.pool:
		if map != null:
			_battle_pool_ids.append(map.id)
	_battle_unit_ids = []
	var army_seats: Array[int] = []
	army_seats.assign(request.armies.keys())
	army_seats.sort()
	for seat: int in army_seats:
		for unit: CombatUnitState in request.armies[seat].units:
			_battle_unit_ids.append(unit.id)
		for unit: UnitInstance in request.armies[seat].unit_instances:
			_battle_unit_ids.append(unit.instance_id)
	combat_encounter_opened.emit(battle)
	var rolls: Dictionary[int, RngStream] = {}
	for seat: int in seats:
		rolls[seat] = _combat_rolls(request.floor_number, request.node, seat)
	battle.open_sessions(rolls)
	for session: CombatSession in battle.get_sessions():
		session.is_tracing_draws = is_tracing_draws
		session.grant_received.connect(receive_grant)
		session.fact_recorded.connect(_on_session_fact_recorded)
		# Before deployment, so no unit takes a breakable's tile.
		MapObjects.place(session)
		# Before deployment too, which ranks its tiles by the enemies' tiles.
		EnemySetup.place(session, catalog)
		# First on AFTER_ENEMY_PHASE, before the reinforcement arrivals (the-darkness.md, The
		# darkness step); its damage after the point closing on PHASE_END_EFFECTS.
		Darkness.register(session)
		Reinforcements.register(session, waves)
		Darkness.register_damage(session)
		EnemyAI.register(session, catalog)
		Intents.register(session, catalog)
	return battle


# Each seat's extra enemies (EnemySetup.extra_enemies) from its army's heirlooms and curses, by
# seat; a seat with none has no entry.
func _extra_enemies(catalog: EffectCatalog.Index, request: BattleRequest) -> Dictionary[int, int]:
	var extra: Dictionary[int, int] = {}
	for seat: int in request.armies:
		var army: Army = request.armies[seat]
		var count: int = 0 if army == null else EnemySetup.extra_enemies(
				catalog, army.heirloom_ids, seat
		)
		if count > 0:
			extra[seat] = count
	return extra


# A resume's stand-ins for the seat's heirlooms the run holds no carrier of: registered as Begin
# registers their copies, so DarknessSetup.place reads the same army, and replaced by the save.
# NOTE: Never add them as carriers. Their ids are minted before the saved counter is set again, so
# the resumed battle mints the same ids later; the saved copies become the carriers instead
# (_adopt_heirlooms).
func _place_heirloom_stand_ins(
		battle: CombatEncounter,
		catalog: EffectCatalog.Index,
		seat: int,
		heirloom_ids: PackedStringArray
) -> void:
	var session: CombatSession = battle.session_of_seat(seat)
	if session == null:
		return
	var copies: Dictionary[String, int] = {}
	for heirloom_id: String in heirloom_ids:
		var copy: int = copies.get(heirloom_id, 0)
		copies[heirloom_id] = copy + 1
		if _heirloom_carriers.has(_copy_key(seat, heirloom_id, copy)):
			continue
		for stand_in: EffectInstance in Loadout.heirloom_effects(catalog, heirloom_id, seat, ids):
			if not battle.add_cross_map(stand_in):
				session.engine.register(stand_in)


# Points the write-back at the loaded battle's instances, which replaced the rebuilt ones: each
# carrier's copy by its id (dropped when the battle holds none), the seat's heirlooms' saved
# copies as their carriers, and each unit instance the battle holds through a loadout on a
# throwaway allocator, whose homes are matched to the loaded effects (Loadout.LoadedUnit.relink).
func _relink_battle(
		battle: CombatEncounter, request: BattleRequest, catalog: EffectCatalog.Index
) -> void:
	var relinked: Dictionary[String, EffectInstance] = {}
	for instance_id: String in _battle_copies:
		var loaded: EffectInstance = _battle_instance(battle, instance_id)
		if loaded != null:
			relinked[instance_id] = loaded
	_battle_copies = relinked
	var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
	for seat: int in request.armies:
		var army: Army = request.armies[seat]
		_adopt_heirlooms(battle, catalog, seat, army.heirloom_ids)
		for unit: UnitInstance in army.unit_instances:
			var holder: CombatSession = battle.session_of_unit(unit.instance_id)
			if holder == null:
				continue
			var loaded: Loadout.LoadedUnit = Loadout.load_unit(
					catalog, unit, army.item_instances, CombatFact.CombatSide.PLAYER, seat, scratch
			)
			if not loaded.is_loaded():
				continue
			var restored: Array[EffectInstance] = holder.engine.get_instances()
			loaded.relink(restored)
			_loaded.append(loaded)


# A resumed run holds no carrier of its heirlooms (carriers live only in a session; the run saves
# each copy's campaign lane in its heirlooms section), so each copy's saved battle copy becomes its
# carrier under the battle copy's id, made as Begin made it, and counts as a carrier of the run from
# then on, as after Begin. Copies of one id are matched in order: the k-th held to the k-th loaded.
func _adopt_heirlooms(
		battle: CombatEncounter,
		catalog: EffectCatalog.Index,
		seat: int,
		heirloom_ids: PackedStringArray
) -> void:
	var session: CombatSession = battle.session_of_seat(seat)
	if session == null:
		return
	var taken: Dictionary[String, bool] = {}
	var copies: Dictionary[String, int] = {}
	for heirloom_id: String in heirloom_ids:
		var copy: int = copies.get(heirloom_id, 0)
		copies[heirloom_id] = copy + 1
		var key: String = _copy_key(seat, heirloom_id, copy)
		if _heirloom_carriers.has(key) or catalog.heirloom(heirloom_id) == null:
			continue
		var lane: HeirloomLane = HeirloomLane.new(seat, heirloom_id, copy)
		var scratch: InstanceIdAllocator = InstanceIdAllocator.new()
		for made: EffectInstance in Loadout.heirloom_effects(catalog, heirloom_id, seat, scratch):
			for loaded: EffectInstance in session.engine.get_instances():
				if (
						taken.has(loaded.instance_id)
						or _carriers.has(loaded.instance_id)
						or loaded.owner.kind != EffectOwner.Kind.ARMY
						or loaded.owner.seat != seat
						or loaded.source_kind != made.source_kind
						or loaded.definition.id != made.definition.id
				):
					continue
				taken[loaded.instance_id] = true
				add_carrier(EffectInstance.new(
						loaded.instance_id, made.definition, made.owner, made.source_kind, made.label
				))
				_battle_copies[loaded.instance_id] = loaded
				lane.carrier_ids.append(loaded.instance_id)
				break
		_heirloom_carriers[key] = lane


# The battle's instance with instance_id, on whichever map holds it; null when none does.
func _battle_instance(battle: CombatEncounter, instance_id: String) -> EffectInstance:
	for session: CombatSession in battle.get_sessions():
		var found: EffectInstance = session.engine.get_instance(instance_id)
		if found != null:
			return found
	return null


# One INFO line per campaign command, then one per fact it recorded.
func _log_campaign_batch(batch: CampaignBatch) -> void:
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net == null:
		return
	var outcome: String = (
			"rejected: %s" % [batch.rejected_reason] if batch.is_rejected()
			else "%d facts" % [batch.facts.size()]
	)
	net.info(
			NetLogScript.Category.CAMPAIGN,
			"COMMAND seat %d #%d %s, %s" % [batch.seat, batch.arrival, batch.label, outcome]
	)
	for fact: CampaignFact in batch.facts:
		net.info(NetLogScript.Category.CAMPAIGN, fact.to_log_line(describe))


func _log_battle(what: String, request: BattleRequest, battle: CombatEncounter) -> void:
	var net: NetLogScript = CombatSession.logger(
			NetLogScript.Level.INFO, NetLogScript.Category.CAMPAIGN
	)
	if net != null:
		net.info(
				NetLogScript.Category.CAMPAIGN,
				"%s floor %d node %d map %s seats %s"
				% [what, request.floor_number, request.node, battle.setup.map.id, seats]
		)


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


# Makes each copy in heirloom_ids (an id repeats once per copy held) carriers of the run for seat,
# once per copy, each with the campaign lane its SeatRun entry saved.
func _add_heirlooms(
		catalog: EffectCatalog.Index, seat: int, heirloom_ids: PackedStringArray
) -> void:
	var copies: Dictionary[String, int] = {}
	for heirloom_id: String in heirloom_ids:
		var copy: int = copies.get(heirloom_id, 0)
		copies[heirloom_id] = copy + 1
		var key: String = _copy_key(seat, heirloom_id, copy)
		if _heirloom_carriers.has(key):
			continue
		if catalog.heirloom(heirloom_id) == null:
			push_error("CampaignSession: heirloom \"%s\" is not in the catalog" % [heirloom_id])
			continue
		var owned: SeatRun.OwnedHeirloom = _owned_copy(seat, heirloom_id, copy)
		var lane: HeirloomLane = HeirloomLane.new(seat, heirloom_id, copy)
		for instance: EffectInstance in Loadout.heirloom_effects(catalog, heirloom_id, seat, ids):
			if owned != null:
				_copy_lane_in(instance, owned)
			add_carrier(instance)
			lane.carrier_ids.append(instance.instance_id)
		_heirloom_carriers[key] = lane


# The run's copy-th held copy of heirloom_id for seat; null when the run holds no such copy.
func _owned_copy(seat: int, heirloom_id: String, copy: int) -> SeatRun.OwnedHeirloom:
	var seat_run: SeatRun = null if run == null else run.seat_run(seat)
	if seat_run == null:
		return null
	var seen: int = 0
	for owned: SeatRun.OwnedHeirloom in seat_run.heirlooms:
		if owned.heirloom_id != heirloom_id:
			continue
		if seen == copy:
			return owned
		seen += 1
	return null


func _collect_growth(result: BattleResult, session: CombatSession, unit_id: String) -> void:
	var changes: Dictionary[int, int] = session.state.unit(unit_id).growth_changes
	if changes.is_empty():
		return
	result.growth_changes[unit_id] = changes.duplicate()


# A player unit's HP (UnitInstance.FULL_HP at its battle maximum), max HP, whether it fell, the
# permanent deltas its map gained (a stat booster's, a Hit booster's), its XP percent and its
# level-up values: Loadout registers the deltas a unit already had as effects, so the engine's
# deltas are only the battle's own.
func _collect_unit(result: BattleResult, session: CombatSession, unit_id: String) -> void:
	var state: CombatUnitState = session.state.unit(unit_id)
	var sheet: StatSheet = session.stats(unit_id)
	var outcome: UnitOutcome = UnitOutcome.new()
	outcome.seat = state.seat
	outcome.is_fallen = state.is_defeated
	outcome.max_hp = sheet.get_int(CombatValue.Key.HP)
	outcome.hp = 0
	if not state.is_defeated:
		outcome.hp = UnitInstance.FULL_HP if state.hp >= outcome.max_hp else maxi(state.hp, 0)
	outcome.xp_percent = sheet.get_int(CampaignValue.Key.UNIT_XP_PERCENT)
	outcome.level_up = LevelUp.Values.read(sheet)
	for key: int in CombatValue.PERMANENT_KEYS.values():
		for delta: Modifier in session.engine.get_deltas(unit_id, key):
			outcome.stat_deltas.append(ItemInstance.StatDelta.new(
					delta.key, delta.value, delta.source_id, delta.label
			))
	result.units[unit_id] = outcome


# The seat's map at its end, after its units are collected: won or not, the turn, par and turns
# early, objective and combat type, units lost, and the seat's reward values.
func _collect_seat(result: BattleResult, map: CombatSession, seat: int) -> SeatOutcome:
	var outcome: SeatOutcome = SeatOutcome.new()
	outcome.seat = seat
	outcome.is_won = map.is_finished and map.is_won
	outcome.turn = map.state.turn
	if map.setup != null and map.setup.map != null:
		var definition: CombatMapDefinition = map.setup.map
		outcome.turn_par = definition.turn_par
		outcome.objective = definition.objective
		outcome.combat_type = definition.combat_type
		outcome.turns_early = Objectives.turns_early(map)
	for unit_id: String in result.units:
		var unit: UnitOutcome = result.units[unit_id]
		if unit.seat == seat and unit.is_fallen:
			outcome.units_lost += 1
	var sheet: StatSheet = map.engine.stats(InstanceIdAllocator.seat_subject_id(seat))
	outcome.combat_gold = sheet.get_int(CampaignValue.Key.COMBAT_GOLD)
	outcome.grade_bonus_percent = sheet.get_int(CampaignValue.Key.GRADE_BONUS_PERCENT)
	outcome.shared_xp_percent = sheet.get_int(CampaignValue.Key.SHARED_XP_PERCENT)
	return outcome


# Each held heirloom copy's campaign lane, from its carriers (write_back() has run): counters by
# effect id (0 left out), and charges for the effects whose charges last the run.
func _collect_heirlooms(result: BattleResult) -> void:
	var keys: Array[String] = []
	keys.assign(_heirloom_carriers.keys())
	keys.sort()
	for key: String in keys:
		var held: HeirloomLane = _heirloom_carriers[key]
		var lane: HeirloomLane = HeirloomLane.new(held.seat, held.heirloom_id, held.copy)
		for carrier_id: String in held.carrier_ids:
			var carrier: EffectInstance = _carriers.get(carrier_id, null)
			if carrier == null:
				continue
			var effect_id: String = carrier.definition.id
			var count: int = carrier.get_counter(EffectTerms.Lane.CAMPAIGN)
			if count != 0:
				lane.counters[effect_id] = count
			if carrier.definition.charge_lane == EffectTerms.Lane.CAMPAIGN:
				lane.charges[effect_id] = carrier.charges_left
		result.heirlooms.append(lane)


# The battle's XP tally hears every fact of every map, on the map that holds its unit.
func _on_session_fact_recorded(fact: CombatFact) -> void:
	if encounter == null:
		return
	# An object fact's unit is its target; every other counted fact's is its actor.
	var unit_id: String = (
			fact.target_id if fact.kind == CombatFact.Kind.OBJECT_STATE_CHANGED
			or fact.kind == CombatFact.Kind.BLOCK_GAINED else fact.actor_id
	)
	if unit_id.is_empty():
		return
	var holder: CombatSession = encounter.session_of_unit(unit_id)
	if holder != null:
		tally.record(fact, holder.state)


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


# Sets a new carrier's campaign-lane counter, and its charges when they last the run, from the
# copy's saved entry, by effect id; an effect with no entry keeps its fresh values.
static func _copy_lane_in(instance: EffectInstance, owned: SeatRun.OwnedHeirloom) -> void:
	var effect_id: String = instance.definition.id
	if owned.counters.has(effect_id):
		instance.set_counter(EffectTerms.Lane.CAMPAIGN, owned.counters[effect_id])
	var lasts_run: bool = instance.definition.charge_lane == EffectTerms.Lane.CAMPAIGN
	if lasts_run and owned.charges.has(effect_id):
		instance.charges_left = owned.charges[effect_id]


# A held copy's key: "seat:content id:copy", the copy counted from 0 in gain order.
static func _copy_key(seat: int, heirloom_id: String, copy: int) -> String:
	return "%d:%s:%d" % [seat, heirloom_id, copy]


## What a battle begins from: its node, its map pool and each seat's army, as unit and item
## instances for [Loadout], plain combat data, or both.
class BattleRequest:
	extends RefCounted

	## The campaign floor of the combat node.
	var floor_number: int = -1
	## The combat node on its floor.
	var node: int = -1
	## The standard combats the run entered on earlier floors of this node's difficulty step
	## ([method CampaignRunState.standard_combats_in_step]): it picks the basic or hard pack pool
	## ([method EnemySetup.pool_for]). [b]0:[/b] the basic pool.
	var standard_combats_in_step: int = 0
	## The key combats the run entered on earlier floors
	## ([method CampaignRunState.key_combats_before]): on a key map, the place of its mini-boss in
	## the run's order ([method EnemySetup.mini_boss_for]). [b]0:[/b] the run's first mini-boss.
	var key_combats_before: int = 0
	## The maps the node can draw from, in a fixed order.
	var pool: Array[CombatMapDefinition] = []
	## Each seat's army, by seat. A seat without one gets an empty map.
	var armies: Dictionary[int, Army] = {}
	## The content the loadout reads. [b]Null:[/b] the loaded catalog
	## ([method EffectCatalog.index]); tests pass a fixture tree.
	var catalog: EffectCatalog.Index = null
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
	## Content ids of the seat's heirlooms and curses in gain order, its Commander Heirloom
	## included, an id repeated once per copy held. Each copy is made carriers of the run the first
	## time a battle names it, so its campaign lane lasts the run
	## ([method Loadout.heirloom_effects]). [b]Empty:[/b] none.
	var heirloom_ids: PackedStringArray = []


## What a battle leaves for the run to apply ([method CampaignRunState.apply_battle]).
class BattleResult:
	extends RefCounted

	## The battle's campaign floor and node, as its request named them.
	var floor_number: int = -1
	## See [member floor_number].
	var node: int = -1
	## Content id of the map setup drew.
	var map_id: String = ""
	## Ids of the maps the battle could draw (its request's pool), in order: on a refill, the
	## whole pool.
	var pool_ids: PackedStringArray = []
	## Whether every map's combat ended.
	var is_finished: bool = false
	## Whether every map's combat ended in a player win.
	var is_won: bool = false
	## Each player unit of the battle, by unit id.
	var units: Dictionary[String, UnitOutcome] = {}
	## Growth changes gained this battle, by unit id: stat ([enum CombatValue.Stat]) to percentage
	## points (event bus plan, fix F11).
	var growth_changes: Dictionary[String, Dictionary] = {}
	## Each held heirloom or curse copy's campaign lane after the battle.
	var heirlooms: Array[HeirloomLane] = []
	## Grants received during the battle, in order.
	var grants: Array[Grant] = []
	## The XP actions each player unit took, a copy of [member CampaignSession.tally].
	var tally: BattleTally = BattleTally.new()
	## Each seat's map at the battle's end, by seat; a seat with no map has no entry.
	var seats: Dictionary[int, SeatOutcome] = {}


## One seat's map at a battle's end, and the reward values its heirlooms set, for the rewards.
class SeatOutcome:
	extends RefCounted

	## The seat.
	var seat: int = -1
	## Whether its map ended in a player win.
	var is_won: bool = false
	## The turn its map ended on.
	var turn: int = 0
	## Its map's turn par; 0 when the map sets none.
	var turn_par: int = 0
	## The turns a Survive or Defend map ended early ([method Objectives.turns_early]); 0 otherwise.
	var turns_early: int = 0
	## Its map's objective.
	var objective: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
	## Its map's combat type.
	var combat_type: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
	## How many of the seat's units fell, its commander included.
	var units_lost: int = 0
	## Whether its map received units another player sent; such a map earns no speed bonus. Always
	## false until co-op sends units (P11).
	var has_received_units: bool = false
	## [constant CampaignValue.Key.COMBAT_GOLD] of the seat (Bounty Ledger).[br]
	## [b]Units:[/b] gold.
	var combat_gold: int = 0
	## [constant CampaignValue.Key.GRADE_BONUS_PERCENT] of the seat (Gilded Purse).[br]
	## [b]Units:[/b] percent.
	var grade_bonus_percent: int = 0
	## [constant CampaignValue.Key.SHARED_XP_PERCENT] of the seat (Veteran's Medal).[br]
	## [b]Units:[/b] percent.
	var shared_xp_percent: int = 100


## The streams a battle's rewards draw from, by seat ([method CampaignSession.reward_rolls]).
class RewardRolls:
	extends RefCounted

	## Each seat's [code]REWARD[/code] stream: its item pick.
	var reward: Dictionary[int, RngStream] = {}
	## Each seat's [code]LEVEL_UPS[/code] stream: its units' level-ups, in roster order.
	var level_ups: Dictionary[int, RngStream] = {}


## One player unit at a battle's end.
class UnitOutcome:
	extends RefCounted

	## The unit's seat.
	var seat: int = -1
	## Its HP; [constant UnitInstance.FULL_HP] at its maximum.
	var hp: int = UnitInstance.FULL_HP
	## Its max HP in the battle, items included.
	var max_hp: int = 0
	## Whether it fell.
	var is_fallen: bool = false
	## The permanent changes it gained in this battle, Hit included, each with its source.
	var stat_deltas: Array[ItemInstance.StatDelta] = []
	## [constant CampaignValue.Key.UNIT_XP_PERCENT] of the unit (Family Ring).[br]
	## [b]Units:[/b] percent.
	var xp_percent: int = 100
	## Its level-up values (Training Weights, Royal Crest, Resonant Ore); null: none read.
	var level_up: LevelUp.Values = null


## One held copy of a heirloom or curse: which, and its campaign lane by effect id.
class HeirloomLane:
	extends RefCounted

	## The seat that holds it.
	var seat: int = -1
	## Content id of its [HeirloomDefinition] or [CurseDefinition].
	var heirloom_id: String = ""
	## Which copy of [member heirloom_id] the seat holds, from 0 in gain order.
	var copy: int = 0
	## Campaign-lane counters by effect id; an effect at 0 is left out.
	var counters: Dictionary[String, int] = {}
	## Charges left by effect id, for effects whose charges last the run.
	var charges: Dictionary[String, int] = {}
	## Instance ids of the copy's carriers in the session; empty in a [BattleResult].
	var carrier_ids: PackedStringArray = []

	func _init(holder_seat: int = -1, content_id: String = "", copy_index: int = 0) -> void:
		seat = holder_seat
		heirloom_id = content_id
		copy = copy_index


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
