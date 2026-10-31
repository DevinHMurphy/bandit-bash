# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_service.gd
# Author:
# Created:  October 28, 2026
# Modified: October 31, 2026
# ==============================================================================

extends Node
## Holds the live [CampaignSession] of the run in progress, and wraps its battle bridge in the save
## checkpoints.
##
## Registered as autoload [code]CampaignService[/code], after [code]SaveService[/code] (its
## [code]_ready()[/code] connects to it) and before [code]SceneRouter[/code]; its
## [code]_ready()[/code] also loads the content catalog ([method EffectCatalog.load_catalog]).
## [b]Why an autoload:[/b] the session must outlive every screen change, and the save sections it
## owns must register before any save file opens (campaign and run flow plan, question 1).[br]
## A session is built on [signal SaveService.campaign_activated] and closed on
## [signal SaveService.run_ended], [signal SaveService.save_file_closed] and
## [signal SaveService.campaign_cleared], so every way a run starts (new, continued, resumed, the
## debug panel's seed restart) leaves exactly one, and none outlives its campaign. On a
## multiplayer client there is none until transport (P10) delivers the host's snapshots (event
## bus plan, question 41).[br]
## [b]Save sections:[/b] the [code]rng[/code] ([RngSaveSection]) and [code]instance_ids[/code]
## ([InstanceIdSaveSection]) sections, one of each in the campaign and the combat block, and the
## combat block's [code]combat_state[/code] and [code]effects[/code] ([CombatStateSection]), which
## also keep the combat block's core turn and phase equal to the battle's. Each new session is
## handed to all of them before [signal session_started], campaign before combat, so a continued
## run's streams and id counter are restored before anything draws or mints.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Save system design): docs/design/save-system.md
##
## @todo: TOD-001 [HIGH] - On a BATTLE resume, rebuild the battle as Begin set it up and
## [method CombatStateSection.load_into] it (P02 CC10, battle resume, after P04 MP8).

## A run's session was built: connect here to follow its battles.
signal session_started(session: CampaignSession)

## A run's session was closed: its run ended, its save file closed, or another run replaced it.
signal session_ended(session: CampaignSession)

## The run in progress on this machine; null outside a run and on a multiplayer client.
var session: CampaignSession = null

var _campaign_rng: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
var _combat_rng: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
var _campaign_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.CAMPAIGN)
var _combat_ids: InstanceIdSaveSection = InstanceIdSaveSection.new(SaveSection.Block.COMBAT)
var _combat_state: CombatStateSection = null


func _ready() -> void:
	# The content catalog loads here, on the main thread, before anything can look content up from
	# a worker thread (EffectCatalog's class doc). No earlier autoload reads content.
	EffectCatalog.load_catalog()
	# The rng sections replace the placeholders SaveService reserved under their key.
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _campaign_rng)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_rng)
	SaveService.register_section(SaveSection.Block.CAMPAIGN, _campaign_ids)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_ids)
	_combat_state = CombatStateSection.new(_combat_core)
	# The effects section restores after combat_state, which it needs (CombatStateSection).
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_state)
	SaveService.register_section(SaveSection.Block.COMBAT, _combat_state.effects)
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


## Ends the battle in progress: writes campaign-lane values back
## ([method CampaignSession.write_back]), saves with [method SaveService.end_battle], then drops
## the battle ([method CampaignSession.end_battle]). Returns the result for the run flow; null with
## no battle, or when the save failed, in which case the battle stays in progress.
func end_battle() -> CampaignSession.BattleResult:
	if session == null or session.encounter == null:
		push_error("CampaignService: no battle in progress to end.")
		return null
	session.write_back()
	if SaveService.end_battle() != OK:
		return null
	return session.end_battle()


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
	if replacement != null:
		_attach_rng_sections(replacement)
		_attach_id_sections(replacement)
		# TODO(TOD-001): A BATTLE resume's held battle waits here for its rebuilt battle (CC10).
		_combat_state.attach(replacement)
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
# battle's later counter wins. As with the rng sections, a refusal leaves the data held.
func _attach_id_sections(built: CampaignSession) -> void:
	for section: InstanceIdSaveSection in [_campaign_ids, _combat_ids]:
		var err: Error = section.attach(built)
		if err != OK:
			push_error(
					"CampaignService: the instance_ids section refused the new session - %s"
					% [error_string(err)]
			)


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
