# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     route_vote_status.gd
# Author:
# Created:  November 23, 2026
# Modified: November 24, 2026
# ==============================================================================

class_name RouteVoteStatus
extends VBoxContainer
## The co-op route vote in the campaign map's side panel: how many seats voted and how the node
## is drawn while the vote is open ([method show_vote]), then the node the votes drew
## ([method show_draw]) with Continue, which the screen waits on before it follows the run into
## the node. Continue is a [ReadyToggle], Ready with two seats or more; a press that takes Ready
## back reports nothing. Each seat's vote is a line naming its player. Hidden in solo.
##
## @tutorial(Co-op combat plan, Route votes): docs/plans/2026-11-20-coop-combat.md
## @todo: TOD-001 - Continue's Ready follows the ready gate (P18 RC4).

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions):
#   "ui_accept" -> Enter, Space; pad A [Cross]   (through the GUI, on Continue once a node is
#                  drawn: reports continued)
#   Mouse: a click on Continue.
# ============================================================

## The player pressed Continue after the draw: the screen moves on.
signal continued()

## Continue's least size, so it reads as a button at the side panel's width.[br]
## [b]Units:[/b] base units. [b](0, 0):[/b] as large as its text.
@export var continue_size: Vector2 = Vector2(120.0, 36.0):
	set(value):
		continue_size = value
		if not is_node_ready():
			return
		_continue_button.custom_minimum_size = continue_size

var _is_drawing: bool = false

@onready var _heading_label: Label = %Heading
@onready var _detail_label: Label = %Detail
@onready var _seats_label: Label = %Seats
@onready var _continue_button: ReadyToggle = %ContinueButton


func _ready() -> void:
	visible = false
	_continue_button.visible = false
	_continue_button.custom_minimum_size = continue_size
	_continue_button.pressed.connect(_on_continue_button_pressed)
	# Nothing else on the map takes focus during the draw; keys and pads stay on Continue.
	var self_path: NodePath = _continue_button.get_path_to(_continue_button)
	_continue_button.focus_neighbor_left = self_path
	_continue_button.focus_neighbor_right = self_path
	_continue_button.focus_neighbor_top = self_path
	_continue_button.focus_neighbor_bottom = self_path
	_continue_button.focus_next = self_path
	_continue_button.focus_previous = self_path


## Shows [param run]'s open vote for [param viewer]: the count, the rule and every seat's vote;
## hidden with one seat.
func show_vote(run: CampaignRunState, viewer: int) -> void:
	_is_drawing = false
	_continue_button.visible = false
	visible = run != null and run.seats.size() > 1
	if not visible:
		return
	var votes: Dictionary[int, int] = run.open_route_votes()
	_heading_label.text = "Team vote"
	_detail_label.text = "%d of %d voted · weighted draw" % [votes.size(), run.seats.size()]
	_show_seats(run, viewer, votes)


## Shows that [param run]'s votes drew node [param drawn] for [param viewer], with Continue.
## The votes are the draw's ([member CampaignRunState.route_votes]), kept after it.
func show_draw(run: CampaignRunState, viewer: int, drawn: int) -> void:
	_is_drawing = true
	visible = true
	var votes: Dictionary[int, int] = run.route_votes
	var count: int = 0
	for seat: int in votes:
		if votes[seat] == drawn:
			count += 1
	_heading_label.text = "The team drew %s" % [node_text(run.graph, drawn)]
	_detail_label.text = "%d of %d votes were for it." % [count, votes.size()]
	_show_seats(run, viewer, votes)
	# TODO(TOD-001): the ready gate drives Continue's Ready (P18 RC4).
	_continue_button.is_coop = run.seats.size() > 1
	_continue_button.set_ready(false)
	_continue_button.visible = true


## Whether a drawn node shows, waiting on Continue.
func is_drawing() -> bool:
	return _is_drawing


## The Continue button, a [ReadyToggle], for the screen's focus and for tests.
func get_continue_button() -> Button:
	return _continue_button


## The heading shown, for tests.
func get_heading() -> String:
	return _heading_label.text


## The detail line shown, for tests.
func get_detail() -> String:
	return _detail_label.text


## Each seat's vote as shown, one line each in seat order, for tests.
func get_seat_lines() -> PackedStringArray:
	if _seats_label.text.is_empty():
		return PackedStringArray()
	return _seats_label.text.split("\n")


# One line per seat: "You: Floor 3 · Camp", "Player 2: hasn't voted".
func _show_seats(run: CampaignRunState, viewer: int, votes: Dictionary[int, int]) -> void:
	var lines: PackedStringArray = []
	for seat: int in run.seat_numbers():
		var who: String = "You" if seat == viewer else CampaignLink.seat_name(seat)
		var vote: String = (
				node_text(run.graph, votes[seat]) if votes.has(seat) else "hasn't voted"
		)
		lines.append("%s: %s" % [who, vote])
	_seats_label.text = "\n".join(lines)


func _on_continue_button_pressed() -> void:
	if _is_drawing and not _continue_button.is_taking_back():
		continued.emit()


## Node [param node_id] of [param graph] as the map names it: "Floor 3 · Camp".
static func node_text(graph: CampaignGraph, node_id: int) -> String:
	if graph == null or not graph.has_node_id(node_id):
		return "?"
	var type_name: String = CampaignMapView.TYPE_NAMES.get(graph.type_of(node_id), "?")
	return "Floor %d · %s" % [graph.floor_of(node_id), type_name]
