# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_header.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name RunHeader
extends PanelContainer
## The strip along the top of every campaign screen: the screen's title, the floor reached and the
## seat's gold.
##
## Reading only: the screen calls [method show_run] after every change it makes. Takes no input.

## The screen's name, on the left.
@export var title: String = "":
	set(value):
		title = value
		if not is_node_ready():
			return
		_title_label.text = title

@onready var _title_label: Label = %Title
@onready var _floor_label: Label = %Floor
@onready var _gold_label: Label = %Gold


func _ready() -> void:
	_title_label.text = title


## Shows [param run]'s floor, out of its map's floors, and seat [param seat]'s gold.
func show_run(run: CampaignRunState, seat: int) -> void:
	var floors: int = run.graph.get_floor_count() if run.graph != null else 0
	_floor_label.text = "Floor %d / %d" % [run.floor_number, floors]
	var seat_run: SeatRun = run.seat_run(seat)
	_gold_label.text = "Gold %d" % [seat_run.gold if seat_run != null else 0]


## The floor text as shown, for tests.
func get_floor_text() -> String:
	return _floor_label.text


## The gold text as shown, for tests.
func get_gold_text() -> String:
	return _gold_label.text
