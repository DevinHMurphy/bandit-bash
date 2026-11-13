# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_service.gd
# Author:
# Created:  October 28, 2026
# Modified: November 13, 2026
# ==============================================================================

extends Node
## Holds the live [CampaignSession] of the run in progress, wraps its battle bridge and campaign
## commands in the save checkpoints, and loads the content catalog in [code]_ready()[/code].
##
## Autoload [code]CampaignService[/code], after [code]SaveService[/code] and before
## [code]SceneRouter[/code]: the session outlives every screen, and its sections register before
## any save file opens. A session is built on [signal SaveService.campaign_activated] and closed
## on run end, save file close and campaign clear, so exactly one exists per run; a multiplayer
## client has none until transport (P10).[br]
## [b]Save sections,[/b] each handed the new session before [signal session_started], campaign
## before combat: [code]rng[/code] and [code]instance_ids[/code] in both blocks, the campaign's
## run sections ([RunSaveSections]), and the combat block's ([CombatStateSection],
## [CombatMapSection], [DarknessSaveSection], [BattleTallySection]). A run whose save holds no run
## sections, a new one included, is built by [RunStart] and saved at once. Every save made here
## first sets [member CampaignData.floors_climbed] to the run's floor, for Save Select.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Save system design): docs/design/save-system.md

## A run's session was built: connect here to follow its battles.
signal session_started(session: CampaignSession)

## A run's session was closed: its run ended, its save file closed, or another run replaced it.
signal session_ended(session: CampaignSession)

## The campaign map's rules data, read when a new run is built.
const MAP_RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

## Every seat's faction in a new run. The Mercenary is the MVP's only faction and is preselected
## until the run-start screens offer a choice.
const DEFAULT_FACTION_ID: String = "mercenary"

## The run in progress on this machine; null outside a run and on a multiplayer client.
var session: CampaignSession = null

var _campaign_rng: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
var _combat_rng: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
var _campaign_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.CAMPAIGN)
var _combat_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
var _combat_state: CombatStateSection = null
var _combat_map: CombatMapSection = CombatMapSection.new()
var _darkness: DarknessSaveSection = DarknessSaveSection.new()
var _battle_tally: BattleTallySection = BattleTallySection.new()
var _run_sections: RunSaveSections = RunSaveSections.new()

# The id counter the combat instance_ids section gave a session built to resume a battle, set
# again once the saved battle has loaded (the rebuild mints throwaway ids first); empty otherwise.
var _battle_ids: Dictionary = {}


func _ready() -> void:
	# The content catalog loads here, on the main thread, before anything can look content up from
	# a worker thread (EffectCatalog's class doc). No earlier autoload reads content.
	EffectCatalog.load_catalog()
	# The rng sections replace the placeholders SaveService reserved under their key.
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _campaign_rng)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_rng)
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _campaign_ids)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_ids)
	# The map before the flow, which is checked against it (RunSaveSections).
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _run_sections.map)
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _run_sections.flow)
	for seat_section: RunSaveSections.SeatSection in _run_sections.seat_sections:
		SaveService.register_player_section(seat_section)
	_combat_state = CombatStateSection.new(_combat_core)
	_combat_state.resolve = _find_definition
	# The effects section restores after combat_state, which it needs (CombatStateSection).
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_state)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_state.effects)
	# entities replaces the placeholder SaveService reserved under its key, and restores after
	# combat_map, which it needs (CombatMapSection).
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_map)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_map.entities)
	SaveService.register_section(SaveSection.Block.COMBAT, _darkness)
	SaveService.register_section(SaveSection.Block.COMBAT, _battle_tally)
	SaveService.register_section(SaveSection.Block.COMBAT, _battle_tally.grants)
	SaveService.campaign_activated.connect(_on_save_service_campaign_activated)
	SaveService.run_ended.connect(_on_save_service_run_ended)
	SaveService.save_file_closed.connect(_on_save_service_save_file_closed)
	SaveService.campaign_cleared.connect(_on_save_service_campaign_cleared)


## Begins the battle [param request] describes, after the player presses Begin: sets it up
## ([method CampaignSession.begin_battle]), then saves it with [method SaveService.begin_battle], so
## the combat file holds the battle as set up. Returns [constant OK];
## [constant ERR_UNCONFIGURED] with no session; [constant ERR_CANT_CREATE] when setup failed; or
## the save error, with the battle dropped again.
func begin_battle(request: CampaignSession.BattleRequest) -> Error:
	if session == null:
		push_error("CampaignService: no run in progress to begin a battle in.")
		return ERR_UNCONFIGURED
	if session.begin_battle(request) == null:
		return ERR_CANT_CREATE
	var err: Error = SaveService.begin_battle()
	if err != OK:
		session.abandon_battle()
	return err


## Resumes the battle a continued run loaded ([constant CombatData.ResumePoint.BATTLE]) from
## [param request], the request Begin had, in save-system.md's order (Combat map): with the
## combat state, map and darkness sections all holding, the battle is rebuilt as Begin set it up
## ([method CampaignSession.resume_battle]), its maps loaded ([method CombatMapSection.load_into]),
## then their darkness ([method DarknessSaveSection.load_into]), then its units, turn and effects
## ([method CombatStateSection.load_into]), and the run's id counter set back to the combat
## checkpoint's. On any failure the saved battle is dropped
## ([method SaveService.drop_battle]) and begun again from Begin ([method begin_battle]), minting
## on from the run's counter. Returns [constant OK], resumed or restarted;
## [constant ERR_INVALID_PARAMETER] for null; [constant ERR_UNCONFIGURED] with no session or no
## saved battle loaded; [constant ERR_ALREADY_IN_USE] during a battle; or [method begin_battle]'s.
func resume_battle(request: CampaignSession.BattleRequest) -> Error:
	if request == null:
		return ERR_INVALID_PARAMETER
	if session == null:
		push_error("CampaignService: no run in progress to resume a battle in.")
		return ERR_UNCONFIGURED
	if session.encounter != null:
		push_error("CampaignService: a battle is already in progress.")
		return ERR_ALREADY_IN_USE
	if SaveService.combat == null or SaveService.resume_point != CombatData.ResumePoint.BATTLE:
		push_error("CampaignService: no saved battle to resume.")
		return ERR_UNCONFIGURED
	# ASSUMPTION: a combat file from before the darkness section holds no darkness, so its battle
	# restarts from Begin, as one missing any other combat section does, rather than resuming with
	# the darkness as setup placed it.
	if (
			not _combat_state.is_holding()
			or not _combat_map.is_holding()
			or not _darkness.is_holding()
	):
		push_warning("CampaignService: the combat file holds no whole battle to resume.")
	elif session.resume_battle(request, _load_saved_battle) != null:
		return OK
	var dropped: Error = SaveService.drop_battle()
	if dropped != OK:
		push_warning(
				"CampaignService: the old combat file wasn't deleted - %s" % [error_string(dropped)]
		)
	return begin_battle(request)


## Ends the battle in progress in save-system.md's order, so a crash at any point loses and repeats
## nothing: collects the result ([method CampaignSession.collect_battle]), swaps in the run with it
## applied ([method CampaignRunState.apply_battle]), saves with [method SaveService.end_battle],
## then drops the battle. A solo battle lost ends the run instead ([method SaveService.end_run]).
## Returns the result; null with no battle, or when the save failed, which puts the run back as it
## was and leaves the battle in progress.
func end_battle() -> CampaignSession.BattleResult:
	if session == null or session.encounter == null:
		push_error("CampaignService: no battle in progress to end.")
		return null
	var result: CampaignSession.BattleResult = session.collect_battle()
	var kept: CampaignRunState = session.run
	if kept != null:
		var applied: CampaignRunState = kept.apply_battle(result, session.ids)
		if applied == null:
			push_error("CampaignService: the battle's result couldn't be applied to the run.")
			return null
		session.run = applied
	_sync_floor()
	if session.mode == CampaignData.Mode.SOLO and result.is_finished and not result.is_won:
		var lost: CampaignSession = session
		lost.end_battle()
		var ended: Error = SaveService.end_run(false)
		if ended != OK:
			push_warning("CampaignService: the lost run ended with %s" % [error_string(ended)])
		return result
	if SaveService.end_battle() != OK:
		session.run = kept
		return null
	return session.end_battle()


## Resolves [param command] on the run ([method CampaignSession.submit]) and, when it resolved,
## saves with [method SaveService.save_checkpoint], so a chosen node or a purchase survives a
## quit. Returns the batch; null with no session. A failed save is reported and the change kept
## in memory, for the next checkpoint to write.
func submit_command(command: CampaignCommand) -> CampaignBatch:
	if session == null:
		push_error("CampaignService: no run in progress to command.")
		return null
	var batch: CampaignBatch = session.submit(command)
	if batch != null and not batch.is_rejected():
		_sync_floor()
		var err: Error = SaveService.save_checkpoint()
		if err != OK:
			push_error(
					"CampaignService: saving after \"%s\" failed - %s"
					% [batch.label, error_string(err)]
			)
	return batch


# The rng sections let go of the previous session first, so a section that refuses the
# replacement never keeps reading a closed run.
func _replace_session(replacement: CampaignSession) -> void:
	var previous: CampaignSession = session
	session = replacement
	_campaign_rng.detach()
	_combat_rng.detach()
	_campaign_ids.detach()
	_combat_ids.detach()
	_combat_state.detach()
	_combat_map.detach()
	_darkness.detach()
	_battle_tally.detach()
	_run_sections.detach()
	_battle_ids = {}
	if replacement != null:
		_attach_rng_sections(replacement)
		_attach_id_sections(replacement)
		_attach_run_sections(replacement)
		# A saved battle stays held until resume_battle() loads it.
		_combat_state.attach(replacement)
		_combat_map.attach(replacement)
		_darkness.attach(replacement)
		_battle_tally.attach(replacement)
	if previous != null:
		previous.close()
		session_ended.emit(previous)
	if replacement != null:
		session_started.emit(replacement)


# Applies the streams SaveService restored for this run to the session just built. A refusal
# can't happen on a new session (it has no battle, and restore checked the data); if it does, the
# held data stays held and is saved again unchanged.
func _attach_rng_sections(built: CampaignSession) -> void:
	for section: RngSaveSection in [_campaign_rng, _combat_rng]:
		var err: Error = section.attach(built)
		if err != OK:
			push_error(
					"CampaignService: the rng section refused the new session - %s"
					% [error_string(err)]
			)


# Applies the id counter SaveService restored for this run, campaign then combat, so a resumed
# battle's later counter wins, and keeps it for resume_battle(). As with the rng sections, a
# refusal leaves the data held.
func _attach_id_sections(built: CampaignSession) -> void:
	for section: InstanceIdSaveSection in [_campaign_ids, _combat_ids]:
		var err: Error = section.attach(built)
		if err != OK:
			push_error(
					"CampaignService: the instance_ids section refused the new session - %s"
					% [error_string(err)]
			)
	if SaveService.resume_point == CombatData.ResumePoint.BATTLE:
		_battle_ids = built.ids.capture()


# Builds the session's run from the saved run sections, after the streams and the id counter.
# A save holding none (a new run, whose first save comes before its session; a crash between that
# save and this one; a save from before the run sections) gets a new run from the seed, which is
# the same run, saved at once unless a battle is in progress (campaign writes keep Begin's
# sections then, and the battle's end saves it).
func _attach_run_sections(built: CampaignSession) -> void:
	var err: Error = _run_sections.attach(built)
	if err == ERR_DOES_NOT_EXIST:
		built.run = _build_new_run(built)
		var campaign: CampaignData = SaveService.campaign
		if built.run != null and campaign != null and not campaign.combat_in_progress:
			campaign.floors_climbed = built.run.floor_number
			var saved: Error = SaveService.save_checkpoint()
			if saved != OK:
				push_error("CampaignService: the new run wasn't saved - %s" % [error_string(saved)])
	elif err != OK:
		push_error("CampaignService: the saved run can't load - %s" % [error_string(err)])


# A new run for every seat of the session, each with DEFAULT_FACTION_ID: the map from the run's
# MAP_GENERATION stream, the armies minted from its allocator. Null, reported, without map rules.
func _build_new_run(built: CampaignSession) -> CampaignRunState:
	var rules: CampaignMapRules = load(MAP_RULES_PATH) as CampaignMapRules
	if rules == null:
		push_error("CampaignService: no campaign map rules at %s" % [MAP_RULES_PATH])
		return null
	var factions: Dictionary[int, String] = {}
	for seat: int in built.seats:
		factions[seat] = DEFAULT_FACTION_ID
	var map_stream: RngStream = built.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION))
	var start: RunStart = RunStart.build(
			rules, map_stream, EffectCatalog.index(), factions, built.ids
	)
	for problem: String in start.problems:
		push_error("CampaignService: new run - %s" % [problem])
	return start.run


# Loads the held battle into battle, rebuilt as Begin set it up (save-system.md, Combat map, steps
# 2 to 5): its maps, then their darkness, then its units, turn and effects (whose reload carries
# the maps and darkness), then the combat checkpoint's id counter, then the XP tally and grants.
func _load_saved_battle(battle: CombatEncounter) -> Error:
	var err: Error = _combat_map.load_into(battle)
	if err == OK:
		err = _darkness.load_into(battle)
	if err == OK:
		err = _combat_state.load_into(battle)
	if err == OK and not _battle_ids.is_empty():
		# Captured from an allocator, so it can't be refused.
		err = session.ids.restore(_battle_ids)
		_battle_ids = {}
	if err == OK:
		err = _battle_tally.load_into(session)
	return err


# Sets the active campaign's floor, which Save Select shows, to the run's.
func _sync_floor() -> void:
	var campaign: CampaignData = SaveService.campaign
	if campaign != null and session != null and session.run != null:
		campaign.floors_climbed = session.run.floor_number


# A saved effect's definition, for the combat sections: a map object's own reaction (a powder
# keg's), which no catalog holds, else the catalog's.
func _find_definition(reference: String) -> EffectDefinition:
	var own: EffectDefinition = MapObjects.map_definition(reference)
	return own if own != null else EffectInstance.catalog_definition(reference)


# The combat block's data, which the combat_state section keeps equal to the battle; null outside
# a battle.
func _combat_core() -> CombatData:
	return SaveService.combat


func _on_save_service_campaign_activated(mode: CampaignData.Mode, resumed: bool) -> void:
	if SteamNetwork.has_active_session() and not SteamNetwork.is_authoritative():
		_replace_session(null)
		return
	var campaign: CampaignData = SaveService.campaign
	if campaign == null:
		_replace_session(null)
		return
	var seats: PackedInt32Array = []
	for player: CampaignData.PlayerRun in campaign.players:
		seats.append(player.seat)
	if seats.is_empty():
		seats.append(CampaignData.HOST_SEAT)
	_replace_session(CampaignSession.new(mode, campaign.run_seed, seats))
	NetLog.info(
			NetLog.Category.CAMPAIGN,
			"%s %s run, seed %s, seats %s."
			% [
				"Resumed" if resumed else "New",
				(CampaignData.Mode.find_key(mode) as String).to_lower(),
				RunSeed.format(campaign.run_seed),
				seats,
			]
	)


func _on_save_service_run_ended(_mode: CampaignData.Mode, _won: bool) -> void:
	_replace_session(null)


func _on_save_service_save_file_closed() -> void:
	_replace_session(null)


func _on_save_service_campaign_cleared() -> void:
	_replace_session(null)
