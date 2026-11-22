# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_link.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name CampaignLink
extends RefCounted
## A campaign screen's tie to the run's [CampaignSession] for the seat it acts for: it sends that
## seat's commands and reports what settled, from the session's signals alone, so a screen works
## the same whether its answer comes back at once (solo, the host) or later (a client's mirror).
##
## [method send] submits through the submit function it was made with
## ([method CampaignService.submit_command], which saves) and ignores its return. Every batch that
## changed the run, any seat's, comes back as [signal batch_resolved], so a teammate's purchase or
## Leave rebuilds the screen too; then the seat's own batches answer its sends in order, calling
## each one's callback. A refusal of the seat's own command comes back as [signal refused].
## [b]Order:[/b] what settles while a send is under way is held until the submit returns, so the
## save comes first and a follow-up send never runs inside the session's own submit. Also names
## seats for display ([method seat_name]). Names no autoload. Close it when the screen leaves the
## tree ([method close]).
##
## @tutorial(Co-op combat plan, Screens): docs/plans/2026-11-20-coop-combat.md
## @todo: TOD-001 - Name teammates by their Steam names once the UI can read them (P10 NT5).

## A batch resolved and changed the run, sent by any seat: rebuild from the run as it is now.
## [param is_answer]: it answers one of this link's sends ([method moves_with]).
signal batch_resolved(batch: CampaignBatch, is_answer: bool)

## A command of [member seat] was refused and changed nothing. [param reason] names seats as
## players in co-op ([method name_seats]); solo shows the rules' words unchanged.
signal refused(reason: String)

# A seat as rules text names it, for name_seats().
const _SEAT_PATTERN: String = "\\bseat (\\d+)\\b"

## The session followed; null after [method close].
var session: CampaignSession = null

## The seat the screen acts for ([method CampaignService.local_seat]).
var seat: int = CampaignData.HOST_SEAT

# The callbacks of this seat's commands sent and not yet settled, oldest first: a seat's commands
# settle in the order it sent them. An empty Callable for a send with no follow-up.
var _waiting: Array[Callable] = []

# Called as submit(command) to send a command; its return is ignored.
var _submit: Callable = Callable()

# Whether a send's submit is under way; what settles meanwhile waits in _held.
var _is_sending: bool = false

# What settled during a send, oldest first, each to report once the submit returns.
var _held: Array[Callable] = []


## Follows [param followed] for seat [param local], sending through [param submit], called as
## [code]submit(command)[/code] ([method CampaignService.submit_command] on every screen).
func _init(followed: CampaignSession, local: int, submit: Callable) -> void:
	session = followed
	seat = local
	_submit = submit
	if session == null:
		return
	session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	session.command_rejected.connect(_on_session_command_rejected)


## Sends [param command], which must be [member seat]'s, and calls [param on_resolved] with its
## batch once it resolves, after [signal batch_resolved]; a refusal calls nothing and emits
## [signal refused]. Both come after the submit returns. Does nothing after [method close].
func send(command: CampaignCommand, on_resolved: Callable = Callable()) -> void:
	if session == null or command == null or not _submit.is_valid():
		return
	if command.seat != seat:
		push_error("CampaignLink: a command of seat %d sent for seat %d" % [command.seat, seat])
		return
	_waiting.append(on_resolved)
	var was_sending: bool = _is_sending
	_is_sending = true
	_submit.call(command)
	_is_sending = was_sending
	if not was_sending:
		_report_held()


## Whether the run has more than one seat.
func is_coop() -> bool:
	return session != null and session.seats.size() > 1


## Every seat of the run but [member seat], ascending.
func teammates() -> PackedInt32Array:
	var others: PackedInt32Array = []
	if session == null:
		return others
	for other: int in session.seats:
		if other != seat:
			others.append(other)
	return others


## Whether the screen follows the run when [param batch] moves it elsewhere: an answer to one of
## its own sends ([param is_answer]), or a teammate's batch. The seat's own commands sent
## elsewhere (the host's rolls, a tool staging the run) never move it, as no screen ever did.
func moves_with(batch: CampaignBatch, is_answer: bool) -> bool:
	return is_answer or batch.seat != seat


## Whether [param batch] changed [member seat]'s part: sent by it, or a fact of it records the
## seat (a teammate's Feast heals every seat's units).
func touches_seat(batch: CampaignBatch) -> bool:
	if batch.seat == seat:
		return true
	for fact: CampaignFact in batch.facts:
		if fact.seat == seat:
			return true
	return false


## [param reason] as the screen shows it: in co-op each "seat N" named as its player.
func shown_reason(reason: String) -> String:
	return name_seats(reason) if is_coop() else reason


## Stops following the session and drops the sends still waiting.
func close() -> void:
	if session != null:
		if session.campaign_batch_resolved.is_connected(_on_session_campaign_batch_resolved):
			session.campaign_batch_resolved.disconnect(_on_session_campaign_batch_resolved)
		if session.command_rejected.is_connected(_on_session_command_rejected):
			session.command_rejected.disconnect(_on_session_command_rejected)
	session = null
	_waiting.clear()
	_held.clear()


# Reports what settled during the send just finished, in order; a follow-up send's own reports
# join the same queue behind them.
func _report_held() -> void:
	while not _held.is_empty() and session != null:
		var report: Callable = _held.pop_front()
		report.call()


func _report_resolved(batch: CampaignBatch) -> void:
	if session == null:
		return
	# Taken off before the screen hears of it, so a command the screen sends or causes meanwhile
	# (RunScreen.go() rolling an Unknown) is never read as this one's answer.
	var is_answer: bool = batch.seat == seat and not _waiting.is_empty()
	var on_resolved: Callable = Callable()
	if is_answer:
		on_resolved = _waiting.pop_front()
	batch_resolved.emit(batch, is_answer)
	if on_resolved.is_valid() and session != null:
		on_resolved.call(batch)


func _report_refused(reason: String) -> void:
	if session == null:
		return
	if not _waiting.is_empty():
		_waiting.pop_front()
	refused.emit(shown_reason(reason))


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	if batch == null or batch.is_rejected():
		return
	if _is_sending:
		_held.append(_report_resolved.bind(batch))
		return
	_report_resolved(batch)


func _on_session_command_rejected(rejected_seat: int, _arrival: int, reason: String) -> void:
	if rejected_seat != seat:
		return
	if _is_sending:
		_held.append(_report_refused.bind(reason))
		return
	_report_refused(reason)


## The name [param shown_seat] is shown by: "Player 1" for the host seat, counting up.
static func seat_name(shown_seat: int) -> String:
	# TODO(TOD-001): a Steam name, once the UI can read each seat's.
	return "Player %d" % [shown_seat + 1]


## [param text] with every "seat N" the rules write replaced by [method seat_name] of N.
static func name_seats(text: String) -> String:
	var pattern: RegEx = RegEx.create_from_string(_SEAT_PATTERN)
	var named: String = text
	var hits: Array[RegExMatch] = pattern.search_all(text)
	hits.reverse()
	for hit: RegExMatch in hits:
		var number: int = hit.get_string(1).to_int()
		named = named.left(hit.get_start()) + seat_name(number) + named.substr(hit.get_end())
	return named
