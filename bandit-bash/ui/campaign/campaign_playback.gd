# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_playback.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name CampaignPlayback
extends RefCounted
## Plays the run's campaign facts on its [CampaignBus] when a campaign screen shows them, so the
## listeners (the campaign sounds) hear each fact once, in seq order. The facts come from the
## run's log, past [member CampaignSession.played_seq], which each play moves on: a command's
## facts and the ones no command records (the run's start, a battle's end and level-ups) alike.
## The map plays what is waiting when it opens and after a command; the victory sequence plays
## each level-up as its card shows ([method play_through]). Names no autoload, so a suite can
## call it. Presentation only; static, never instantiated.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## No limit for [method play_pending]: every fact still to play.
const ALL: int = -1


## Plays [param session]'s facts still to play, up to and including seq [param through_seq]
## ([constant ALL]: every one). Returns how many played; 0 with no session or run.
static func play_pending(session: CampaignSession, through_seq: int = ALL) -> int:
	if session == null or session.run == null or session.bus == null:
		return 0
	var played: int = 0
	for fact: CampaignFact in session.run.fact_log:
		if fact.seq <= session.played_seq:
			continue
		if through_seq != ALL and fact.seq > through_seq:
			break
		session.played_seq = fact.seq
		session.bus.play(fact)
		played += 1
	return played


## The first fact still to play of [param kind] for seat [param seat], about [param actor_id]
## when it isn't empty; null when none waits (a resumed run's log holds none from before).
static func next_pending(
		session: CampaignSession, kind: CampaignFact.Kind, seat: int, actor_id: String = ""
) -> CampaignFact:
	if session == null or session.run == null:
		return null
	for fact: CampaignFact in session.run.fact_log:
		if fact.seq <= session.played_seq or fact.kind != kind or fact.seat != seat:
			continue
		if actor_id.is_empty() or fact.actor_id == actor_id:
			return fact
	return null


## Plays [param fact] and every fact still to play before it. Returns false, playing nothing,
## for null or a fact already played.
static func play_through(session: CampaignSession, fact: CampaignFact) -> bool:
	if session == null or fact == null or fact.seq <= session.played_seq:
		return false
	return play_pending(session, fact.seq) > 0


## Plays [param session]'s facts still to play that come before the first waiting fact of
## [param kind] for [param seat]; every one when none of that kind waits. Returns how many played.
static func play_before(session: CampaignSession, kind: CampaignFact.Kind, seat: int) -> int:
	var first: CampaignFact = next_pending(session, kind, seat)
	if first == null:
		return play_pending(session)
	if first.seq - 1 <= session.played_seq:
		return 0
	return play_pending(session, first.seq - 1)
