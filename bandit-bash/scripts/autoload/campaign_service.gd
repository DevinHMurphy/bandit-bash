# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_service.gd
# Author:
# Created:  October 28, 2026
# Modified: November 23, 2026
# ==============================================================================

extends Node
## Holds the live [CampaignSession] of the run in progress, wraps its battle bridge and campaign
## commands in the save checkpoints, and loads the content catalog in [code]_ready()[/code].
##
## Autoload [code]CampaignService[/code], after [code]SaveService[/code] and before
## [code]SceneRouter[/code]: the session outlives every screen, and its sections register before
## any save file opens. The host's and solo's session is built on
## [signal SaveService.campaign_activated] and closed on run end, save file close and campaign
## clear. A client's is the host's [ClientMirror], built while the host's campaign replica is
## held (and kept through a reconnect), never saved; its commands go to the host, and a rejoin
## takes it to the run's screen. While the run is paused every command settles "paused".
## [b]Save sections,[/b] campaign before combat: [code]rng[/code], [code]instance_ids[/code], the
## run's ([RunSaveSections], [EventSaveSection]) and the battle's; a run with none is built by
## [RunStart] and saved at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Save system design): docs/design/save-system.md

## A run's session was built: connect here to follow its battles.
signal session_started(session: CampaignSession)

## A run's session was closed: its run ended, its save file closed, or another run replaced it.
signal session_ended(session: CampaignSession)

## Clients only: the host settled the combat command this machine sent through
## [method submit_combat] for the map [param session_id]; [param reason] is empty when it
## resolved, else why it was refused. Its batches have reached the mirror by then.
signal combat_settled(session_id: int, reason: String)

## The campaign map's rules data, read when a new run is built.
const MAP_RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

## Every seat's faction in a new run. The Mercenary is the MVP's only faction and is preselected
## until the run-start screens offer a choice.
const DEFAULT_FACTION_ID: String = "mercenary"

# Why a command settled while the run is paused: NetRelay's word for its clients' commands.
const _PAUSED: String = "paused"

## The run in progress on this machine; on a multiplayer client, the mirror of the host's
## ([member CampaignSession.is_mirror]) once its first capture arrived. Null outside a run.
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
var _events: EventSaveSection = EventSaveSection.new()

# The id counter the combat instance_ids section gave a session built to resume a battle, set
# again once the saved battle has loaded (the rebuild mints throwaway ids first); empty otherwise.
var _battle_ids: Dictionary = {}

# The seat local_seat() returns; back to the host seat with every new session.
var _local_seat: int = CampaignData.HOST_SEAT

# A client's mirror of the host's run, and the campaign seed it mirrors; null elsewhere.
var _mirror: ClientMirror = null
var _mirror_seed: int = 0

# The map each combat command this client sent is for, by token, until it settles.
var _sent_combat: Dictionary[int, int] = {}

# A client that rejoined a run in progress goes to the run's screen on its next sync.
var _moves_on_sync: bool = false


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
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _events)
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
	SaveService.register_section(SaveSection.Block.COMBAT, _battle_tally.stats)
	SaveService.campaign_activated.connect(_on_save_service_campaign_activated)
	SaveService.run_ended.connect(_on_save_service_run_ended)
	SaveService.save_file_closed.connect(_on_save_service_save_file_closed)
	SaveService.campaign_cleared.connect(_on_save_service_campaign_cleared)


# A client mirrors the host's run while it holds the host's campaign (the replica SaveService
# keeps), through a reconnect too, and runs the mirror's request clock; a new run's replica
# starts a new mirror. A reconnect means the screen moves once the client is back.
func _process(delta: float) -> void:
	var replica: CampaignData = SaveService.multiplayer_replica
	var is_reconnecting: bool = _mirror != null and SteamNetwork.is_reconnecting()
	if replica == null or not (_is_client() or is_reconnecting):
		_drop_mirror()
		return
	if is_reconnecting:
		_moves_on_sync = true
	if _mirror != null and _mirror_seed != replica.run_seed:
		_drop_mirror()
	if _mirror == null:
		_start_mirror(replica.run_seed)
	_mirror.advance(delta)


## Begins the battle [param request] describes, after the player presses Begin: each seat it left
## without an opening-swap entry takes the one its player sent the host
## ([method NetRelay.seat_settings]), the battle is set up ([method CampaignSession.begin_battle]),
## then saved with [method SaveService.begin_battle], so the combat file holds it as set up.
## Returns [constant OK]; [constant ERR_UNCONFIGURED] with no session; [constant ERR_CANT_CREATE]
## when setup failed; or the save error, with the battle dropped again.
func begin_battle(request: CampaignSession.BattleRequest) -> Error:
	if session == null:
		push_error("CampaignService: no run in progress to begin a battle in.")
		return ERR_UNCONFIGURED
	_fill_seat_settings(request)
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
## applied and its rewards rolled ([method CampaignRunState.apply_battle], rules from
## [constant CombatRewardRules.DEFAULT_PATH]), saves with [method SaveService.end_battle], then
## drops the battle. A lost run ends instead, for every seat ([method SaveService.end_run]): a
## solo battle lost, a co-op run lost ([method CombatEncounter.is_run_lost], so before every map
## has ended), or a co-op Boss no map beat. Returns the result; null with no battle, or when
## applying or the save failed, which puts the run, its campaign streams and its id counter back,
## leaving the battle in progress.
func end_battle() -> CampaignSession.BattleResult:
	if session == null or session.encounter == null:
		push_error("CampaignService: no battle in progress to end.")
		return null
	var result: CampaignSession.BattleResult = session.collect_battle()
	var was_run_lost: bool = session.encounter.is_run_lost()
	var kept: CampaignRunState = session.run
	# The rewards draw from the live streams and mint ids, so a retry must start from here again.
	var streams_before: Dictionary[String, String] = session.rng.capture_campaign()
	var ids_before: Dictionary = session.ids.capture()
	if kept != null:
		var applied: CampaignRunState = kept.apply_battle(
				result,
				session.ids,
				session.reward_rolls(result),
				CombatRewardRules.load_default(),
				EffectCatalog.index()
		)
		if applied == null:
			push_error("CampaignService: the battle's result couldn't be applied to the run.")
			_put_back(kept, streams_before, ids_before)
			return null
		session.run = applied
	_sync_floor()
	if _is_battle_losing_run(result, was_run_lost):
		var lost: CampaignSession = session
		lost.end_battle()
		var ended: Error = SaveService.end_run(false)
		if ended != OK:
			push_warning("CampaignService: the lost run ended with %s" % [error_string(ended)])
		return result
	if SaveService.end_battle() != OK:
		_put_back(kept, streams_before, ids_before)
		return null
	return session.end_battle()


## Resolves [param command] on the run ([method CampaignSession.submit]) and, when it resolved,
## saves with [method SaveService.save_checkpoint], so a chosen node or a purchase survives a
## quit. Returns the batch; null with no session. A failed save is reported and the change kept
## in memory, for the next checkpoint to write. On a multiplayer client nothing resolves here:
## the command goes to the host ([method ClientMirror.submit_campaign]), the mirror announces
## what it did on the session's signals, and null is returned. While the run is paused it is
## refused "paused" ([signal CampaignSession.command_rejected]) before anything resolves.
func submit_command(command: CampaignCommand) -> CampaignBatch:
	if _mirror != null and not NetGate.has_session(NetRelay.multiplayer):
		if command != null and _mirror.session != null:
			_mirror.session.command_rejected.emit(local_seat(), 0, _PAUSED)
		return null
	if _is_client():
		if _mirror != null:
			_mirror.submit_campaign(command)
		else:
			NetRelay.send_campaign(command)
		return null
	if session == null:
		push_error("CampaignService: no run in progress to command.")
		return null
	if command != null and NetRelay.is_paused():
		return _refuse_paused(command)
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


## The one way a combat command enters the battle, for the host's screens and the relay alike:
## routes [param command] to the map [param session_id] ([method CombatEncounter.submit]), then
## resolves everything queued ([method CombatEncounter.resolve_queued]) and returns its map
## batches. On a multiplayer client it goes to the host instead, returning none, and
## [signal combat_settled] follows once the host's batches have reached the mirror. None, too,
## with no battle in progress, a null command or a mirror's battle off the network (reported).
## While the run is paused the map rejects it "paused" ([method CombatSession.reject]); a client
## reconnecting to its host settles it "paused" at once.
func submit_combat(command: Command, session_id: int) -> Array[CombatSession.FactBatch]:
	var batches: Array[CombatSession.FactBatch] = []
	if _mirror != null and not NetGate.has_session(NetRelay.multiplayer):
		combat_settled.emit(session_id, _PAUSED)
		return batches
	if _is_client():
		_follow_relay_settles()
		var token: int = NetRelay.NO_TOKEN
		if _mirror != null:
			token = _mirror.submit_combat(command, session_id)
		else:
			token = NetRelay.send_combat(command, session_id)
		if token != NetRelay.NO_TOKEN:
			_sent_combat[token] = session_id
		return batches
	if command == null or session == null or session.encounter == null:
		push_error("CampaignService: no command, or no battle in progress to command.")
		return batches
	if session.is_mirror:
		push_error("CampaignService: a mirror's battle resolves nothing; it isn't sent either.")
		return batches
	if NetRelay.is_paused():
		var map: CombatSession = session.encounter.get_session(session_id)
		if map != null:
			batches.append(map.reject(command, _PAUSED))
		return batches
	session.encounter.submit(command, session_id)
	batches = session.encounter.resolve_queued()
	return batches


## Host only: [param seat], a non-host player, leaves the run for good, as a forfeit or, with
## [param is_removed], the host's removal after a drop (P11 CO18 calls it for both). A forfeit's
## archive record is built first ([method SaveService.archive_forfeit]); then the rules
## ([method CampaignSession.forfeit_seat]); then the seat leaves the campaign's players and the
## checkpoint is saved. A rejection changes nothing and drops the record. Returns the batch; null
## with no session or on a client. A failed save is reported and the change kept in memory.
func forfeit_seat(seat: int, is_removed: bool = false) -> CampaignBatch:
	if session == null or _is_client():
		push_error("CampaignService: only the host's run can lose a seat.")
		return null
	var is_member: bool = session.run != null and session.run.seats.has(seat)
	if not is_removed and is_member and seat != CampaignData.HOST_SEAT:
		SaveService.archive_forfeit(seat)
	var batch: CampaignBatch = session.forfeit_seat(seat, is_removed)
	if batch == null or batch.is_rejected():
		SaveService.take_forfeit_record(seat)
		return batch
	var removed: Error = SaveService.remove_player(seat)
	if removed != OK:
		push_error("CampaignService: seat %d stayed in the campaign - %s" % [
			seat, error_string(removed),
		])
	_sync_floor()
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		push_error("CampaignService: saving seat %d's forfeit failed - %s" % [
			seat, error_string(err),
		])
	return batch


## The seat this machine plays, which every campaign screen acts for and shows: the host seat
## ([constant CampaignData.HOST_SEAT]) in solo and on the host, unless [method set_local_seat]
## chose another; on a client, its own ([method ClientMirror.local_seat]). Screens read it, never
## [code]session.seats[0][/code].
func local_seat() -> int:
	if _mirror != null:
		return _mirror.local_seat()
	return _local_seat


## Makes [param seat] the one [method local_seat] returns, for tests that act as a teammate and
## for a client's join. Returns false, changing nothing, with no session or a seat it doesn't
## hold. A new session goes back to the host seat.
func set_local_seat(seat: int) -> bool:
	if session == null or not session.seats.has(seat):
		push_error("CampaignService: seat %d isn't in the run in progress." % [seat])
		return false
	_local_seat = seat
	return true


## Ends the run as won from its Boss's Results ([method CampaignRunState.is_boss_beaten]):
## archives it through [method SaveService.end_run], which closes the session. The run waits at
## the Boss's results until then, so a quit before it shows the same Results again; leaving the
## node first would save a run on the last floor with nowhere to go. Returns [constant OK];
## [constant ERR_UNCONFIGURED] with no run; [constant ERR_UNAVAILABLE] unless its Boss is beaten;
## or [method SaveService.end_run]'s error, the run ended all the same.
func end_won_run() -> Error:
	if session == null or session.run == null:
		push_error("CampaignService: no run in progress to end.")
		return ERR_UNCONFIGURED
	if not session.run.is_boss_beaten():
		push_error("CampaignService: the run's Boss isn't beaten, so it can't end as won.")
		return ERR_UNAVAILABLE
	return SaveService.end_run(true)


# Whether this machine is a multiplayer client, whose commands only the host resolves. Asked of
# NetRelay's API, the one its RPCs travel on.
func _is_client() -> bool:
	return not NetGate.is_authoritative(NetRelay.multiplayer)


# Whether the battle that left result, now applied to the run, ends the run as lost: a battle of
# one map lost (solo, a 1-seat multiplayer run, or a co-op one with one map left in play); a co-op
# run lost (was_run_lost, read before the battle closed); or a co-op battle over at its node that
# didn't reach its results (a Boss no map beat; CampaignRunState.apply_battle).
func _is_battle_losing_run(
		result: CampaignSession.BattleResult, was_run_lost: bool
) -> bool:
	if session.mode == CampaignData.Mode.SOLO or result.seats.size() <= 1:
		return result.is_finished and not result.is_won
	if was_run_lost:
		return true
	var run: CampaignRunState = session.run
	return (
			result.is_finished and result.seats.size() > 1 and run != null
			and run.flow.stage == RunFlow.Stage.NODE
			and run.floor_number == result.floor_number and run.node == result.node
	)


# A mirror of the run seeded run_seed on NetRelay, shown as the session once its first capture
# arrives, asking for it now.
func _start_mirror(run_seed: int) -> void:
	_replace_session(null)
	_follow_relay_settles()
	_mirror = ClientMirror.new(NetRelay, run_seed)
	_mirror_seed = run_seed
	_mirror.session_built.connect(_on_mirror_session_built)
	_mirror.sync_gave_up.connect(_on_mirror_sync_gave_up)
	# After the mirror's own, so the sync has applied when the screen moves.
	NetRelay.sync_received.connect(_on_net_relay_sync_received)
	# A normal start sends a client to Loading before its mirror exists; one still in the lobby
	# joined a run in progress.
	_moves_on_sync = SceneRouter.current_screen == SceneRouter.Screen.LOBBY
	_mirror.start()


# Closes the mirror and lets its session go; nothing when there is none.
func _drop_mirror() -> void:
	if _mirror == null:
		return
	var dropped: ClientMirror = _mirror
	_mirror = null
	_sent_combat.clear()
	_moves_on_sync = false
	if NetRelay.sync_received.is_connected(_on_net_relay_sync_received):
		NetRelay.sync_received.disconnect(_on_net_relay_sync_received)
	var mirrored: CampaignSession = dropped.session
	dropped.close()
	if mirrored != null and session == mirrored:
		session = null
		session_ended.emit(mirrored)


func _follow_relay_settles() -> void:
	if not NetRelay.command_settled.is_connected(_on_net_relay_command_settled):
		NetRelay.command_settled.connect(_on_net_relay_command_settled)


# A session from this machine's own save ends; a client's mirror follows the host instead.
func _close_own_session() -> void:
	if _mirror == null:
		_replace_session(null)


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
	_events.detach()
	_battle_ids = {}
	_local_seat = CampaignData.HOST_SEAT
	if replacement != null:
		_attach_rng_sections(replacement)
		_attach_id_sections(replacement)
		_attach_run_sections(replacement)
		# After the run is built: the events go into it. A run that can't load keeps them held.
		var events_err: Error = _events.attach(replacement)
		if events_err != OK:
			push_error("CampaignService: the events can't load - %s" % [error_string(events_err)])
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
			rules, map_stream, EffectCatalog.index(), factions, built.ids,
			built.starting_offer_streams()
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


# A battle's end that didn't save: the run, its campaign streams and its id counter as they were
# before it, so ending it again rolls and mints the same.
func _put_back(
		run: CampaignRunState, streams: Dictionary[String, String], counter: Dictionary
) -> void:
	session.run = run
	_sync_floor()
	# Captured from the same registry and allocator, so neither can be refused.
	session.rng.restore_campaign(streams)
	session.ids.restore(counter)


# The host's own campaign command while the run is paused: refused as a client's would be, its
# seat told, nothing stamped, resolved or saved.
func _refuse_paused(command: CampaignCommand) -> CampaignBatch:
	var batch: CampaignBatch = CampaignBatch.new()
	batch.seat = command.seat
	batch.label = command.get_label()
	batch.rejected_reason = _PAUSED
	session.command_rejected.emit(batch.seat, batch.arrival, batch.rejected_reason)
	return batch


# Fills request's opening-swap entry for every seat of the run it has none for (the screen sets
# only this machine's) from the settings that seat's player sent the host. A seat that sent none
# keeps no entry, which CampaignSession.begin_battle() reads as the setting's default, on.
func _fill_seat_settings(request: CampaignSession.BattleRequest) -> void:
	if request == null:
		return
	for seat: int in session.seats:
		if request.opening_swap.has(seat):
			continue
		var sent: Variant = NetRelay.seat_settings(seat).get(SettingsData.OPENING_SWAP_KEY, null)
		if sent is bool:
			request.opening_swap[seat] = sent


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
		_close_own_session()
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
	_close_own_session()


func _on_save_service_save_file_closed() -> void:
	_close_own_session()


func _on_save_service_campaign_cleared() -> void:
	_close_own_session()


func _on_mirror_session_built(built: CampaignSession) -> void:
	session = built
	session_started.emit(built)


func _on_mirror_sync_gave_up(attempts: int) -> void:
	push_warning("CampaignService: the host sent no state after %d requests." % [attempts])


# A client that rejoined goes to the run's screen once the host's state has reached its mirror:
# its old screen shows a battle the mirror rebuilt, or no run at all.
func _on_net_relay_sync_received(
		_run: Dictionary, _battle: Dictionary, _facts: Array, screen: int
) -> void:
	if not _moves_on_sync or session == null or session.run == null:
		return
	_moves_on_sync = false
	var target: SceneRouter.Screen = _rejoin_screen(session, screen)
	NetLog.info(
			NetLog.Category.SCENE,
			"Rejoined the run; going to %s." % [SceneRouter.Screen.find_key(target)]
	)
	SceneRouter.goto_screen(target)


# A combat command this client sent settled; a campaign one is the mirror's to announce.
func _on_net_relay_command_settled(token: int, reason: String) -> void:
	if not _sent_combat.has(token):
		return
	var session_id: int = _sent_combat[token]
	_sent_combat.erase(token)
	combat_settled.emit(session_id, reason)


# The screen a rejoined client opens on run_session, its mirror: the battle screen when the
# host's sync says a battle is open (screen), else the run's own for this seat (RunScreen.of()).
static func _rejoin_screen(run_session: CampaignSession, screen: int) -> SceneRouter.Screen:
	if screen == SceneRouter.Screen.GAMEPLAY:
		return SceneRouter.Screen.GAMEPLAY
	return RunScreen.of(run_session)
