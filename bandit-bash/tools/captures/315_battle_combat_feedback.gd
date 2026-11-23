# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     315_battle_combat_feedback.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Combat feedback, staged in this throwaway run (said in a NOTE): the board rebuilt with the
## elite's mark and every token's profile mark; strikes' facts played on the board alone, the state
## untouched, each shot mid-play (a hit, a crit on an Exposed unit, Block absorbing a hit, a
## Stance break); then every banner over the heirloom bar's row. The board is rebuilt from the
## state after, and the phase banner left hidden.[br]
## Needs: the battle started with an elite among the enemies (310_battle_elite_board).

# How far into a staged strike the combat feedback shots are taken: mid-pop and mid-rise.
const FEEDBACK_STEP: float = 0.08

# The banners shot, in order, by the name each shot ends with.
const BANNERS: Array[String] = ["player", "enemy", "darkness", "victory", "defeat"]


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	var players: PackedStringArray = session.state.units_of(CombatFact.CombatSide.PLAYER)
	if enemies.size() < 3 or players.is_empty():
		note("combat feedback shots: too few units on the board")
		return true
	# The phase start's banner covers the map's top row while it shows, where M1's enemies stand.
	var hud: BattleHud = scene().call(&"get_hud")
	var banner: PhaseBanner = hud.get_phase_banner()
	banner.visible = false
	note("combat feedback shots: the phase banner hidden, as it covers the top row")
	view.bind(session)
	await frames(SETTLE_FRAMES)
	await capture("battle_elite_and_sides")
	note("combat feedback shots: strikes staged on the board only; the state is unchanged")
	await _strikes(view, session, players[0], enemies)
	settle(view)
	view.bind(session)
	for shown: int in BANNERS.size():
		match shown:
			0:
				banner.show_phase(CombatFact.CombatSide.PLAYER, session.state.turn)
			1:
				banner.show_phase(CombatFact.CombatSide.ENEMY, session.state.turn)
			2:
				banner.show_darkness()
			3:
				banner.show_result(true)
			4:
				banner.show_result(false)
		await fade_capture("battle_banner_%s" % [BANNERS[shown]])
	banner.visible = false
	await frames(SETTLE_FRAMES)
	return true


# The four strike shots: player unit [param a] hitting the first enemy, a crit on the second made
# Exposed first, the first enemy's hit absorbed by a's Block, and a Stance break on the third.
func _strikes(
		view: BattleView, session: CombatSession, a: String, enemies: PackedStringArray
) -> void:
	var hit_target: String = enemies[0]
	var crit_target: String = enemies[1]
	var break_target: String = enemies[2]
	var hit: Array[CombatFact] = _staged_strike(a, hit_target, 4, 4, 0, false)
	hit.append(_staged_fact(CombatFact.Kind.STANCE_CHANGED, hit_target, a, -1))
	await _feedback_shot(view, hit, "battle_strike_mid_play")
	var stance: int = view.token_of(crit_target).stance
	var exposed: Array[CombatFact] = [
		_staged_fact(CombatFact.Kind.STANCE_CHANGED, crit_target, a, -stance),
		_staged_fact(CombatFact.Kind.EXPOSED, crit_target, a),
	]
	session.playback.enqueue(exposed)
	settle(view)
	var crit: Array[CombatFact] = _staged_strike(a, crit_target, 9, 9, 0, true)
	await _feedback_shot(view, crit, "battle_crit_exposed")
	var block: Array[CombatFact] = [_staged_fact(CombatFact.Kind.BLOCK_GAINED, a, "", 3)]
	session.playback.enqueue(block)
	settle(view)
	var absorbed: Array[CombatFact] = _staged_strike(enemies[0], a, 5, 2, 3, false)
	absorbed.append(_staged_fact(CombatFact.Kind.STANCE_CHANGED, a, enemies[0], -1))
	await _feedback_shot(view, absorbed, "battle_block_absorbing")
	var broken: Array[CombatFact] = _staged_strike(a, break_target, 3, 3, 0, false)
	broken.append(_staged_fact(
			CombatFact.Kind.STANCE_CHANGED, break_target, a, -view.token_of(break_target).stance
	))
	broken.append(_staged_fact(CombatFact.Kind.EXPOSED, break_target, a))
	await _feedback_shot(view, broken, "battle_stance_break")


# Plays facts on the board alone, steps it FEEDBACK_STEP into their animations, and captures;
# then clears the last fact's wait. FactPlayback counts it down only as frames advance it, and
# settle() stops once the queue is empty, so the next shot, a frame later, would find most of it
# left and its first fact would miss the FEEDBACK_STEP point.
func _feedback_shot(view: BattleView, facts: Array[CombatFact], shot_name: String) -> void:
	view.get_session().playback.enqueue(facts)
	view.advance(0.0)
	view.advance(FEEDBACK_STEP)
	await capture(shot_name)
	settle(view)
	view.get_session().playback.play_all()


# One strike's facts as ExchangeResolver.attack and DamagePipeline.apply record them.
func _staged_strike(
		a: String, d: String, damage: int, to_hp: int, absorbed: int, is_crit: bool,
) -> Array[CombatFact]:
	var facts: Array[CombatFact] = [
		_staged_fact(CombatFact.Kind.ATTACK_MADE, a, d),
		_staged_fact(CombatFact.Kind.HIT_DEALT, a, d, damage),
		_staged_fact(CombatFact.Kind.HIT_TAKEN, d, a, damage),
	]
	if is_crit:
		facts.append(_staged_fact(CombatFact.Kind.CRIT_DEALT, a, d, damage))
		facts.append(_staged_fact(CombatFact.Kind.CRIT_TAKEN, d, a, damage))
	var taken: CombatFact = _staged_fact(CombatFact.Kind.DAMAGE_TAKEN, d, a, to_hp + absorbed)
	taken.hp_amount = to_hp
	taken.block_amount = absorbed
	taken.source = CombatFact.Source.ATTACK
	facts.append(taken)
	return facts


func _staged_fact(
		kind: CombatFact.Kind, actor: String, target: String, amount: int = 0,
) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor, target)
	fact.amount = amount
	return fact
