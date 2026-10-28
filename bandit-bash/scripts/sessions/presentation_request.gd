# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     presentation_request.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name PresentationRequest
extends RefCounted
## Something presentation waits on without rules waiting: an animation finishing, a choice popup
## answered.
##
## Completion lives on the request object, never on handshake signals between rules and screens
## (the old bus design's D5). Whatever shows the thing completes the request; whatever waits
## connects to [signal completed] or hands the request to [method FactPlayback.hold].[br]
## [b]Presentation only:[/b] rules code never makes, waits on or reads one; a player's answer that
## changes the game goes to the session as a command.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Emitted once, when the request is completed or cancelled.
## [param result]: the answer; null when cancelled or when there is nothing to answer.
signal completed(result: Variant)

## What the request is for, in debug text, such as [code]"hit animation unit:57"[/code].
var label: String = ""

## Whether it has been completed or cancelled.
var is_done: bool = false

## Whether it was cancelled instead of answered.
var is_cancelled: bool = false

## The answer given to [method complete]: whatever the asker expects (a choice index, an id), or
## null when there is none or it was cancelled.
var result: Variant = null


func _init(request_label: String = "") -> void:
	label = request_label


## Completes the request with [param answer] and emits [signal completed]. Ignored once done.
func complete(answer: Variant = null) -> void:
	if is_done:
		return
	is_done = true
	result = answer
	completed.emit(answer)


## Completes the request with no answer, marking it cancelled. Ignored once done.
func cancel() -> void:
	if is_done:
		return
	is_cancelled = true
	complete(null)
