# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     input_device_adapter.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name InputDeviceAdapter
extends Node
## Which kind of device the player is using now, for the battle UI's glyphs: keyboard and mouse,
## an Xbox pad, a PlayStation pad or another pad (combat UI plan, question 32 (1)).
##
## The one place the game talks to the Input Helper addon ([code]addons/input_helper/[/code]):
## it listens to the addon's [code]device_changed[/code] signal and turns the addon's device name
## into a [enum Family], emitting [signal family_changed] mid-stage, with no restart. Everything
## else reads [method get_family]. Only the addon's device detection is used; its rebinding and
## its saved bindings are not, so nothing is written to disk.[br]
## [b]The addon[/b] is reached as the [code]/root/InputHelper[/code] node, not by its autoload
## name, so scripts and tests that compile before autoloads exist can load this one. Without the
## addon the family stays [constant KEYBOARD_MOUSE] and a warning is reported once.[br]
## The addon waits a second between two changes (some pads report twice on Windows) and counts a
## mouse move only past its threshold (100 px² of motion), so a twitch of the mouse doesn't
## switch glyphs.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ============================================================
# INPUT MAP SETUP: none read. The addon classifies every raw input event itself (keys, mouse
# buttons and mouse motion: keyboard; joypad buttons and motion past its deadzone: a pad by its
# reported name); this node only maps the name it reports.
# ============================================================

## The family changed to [param family].
signal family_changed(family: Family)

## Device families the glyphs are drawn for.
enum Family {
	## Keyboard and mouse.
	KEYBOARD_MOUSE = 0,
	## An Xbox or XInput pad.
	XBOX = 1,
	## A PlayStation pad.
	PLAYSTATION = 2,
	## Any other pad: Switch, Steam Deck, or one the addon can't name.
	OTHER_PAD = 3,
}

## The addon's autoload, as a node path from the tree's root.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

## The addon's device names, simplified and granular, and the family each is drawn as. A name
## not listed is [constant Family.OTHER_PAD].
const FAMILY_BY_DEVICE: Dictionary[String, Family] = {
	"keyboard": Family.KEYBOARD_MOUSE,
	"xbox": Family.XBOX,
	"xbox_one": Family.XBOX,
	"xbox_series": Family.XBOX,
	"playstation": Family.PLAYSTATION,
	"playstation3": Family.PLAYSTATION,
	"playstation4": Family.PLAYSTATION,
	"playstation5": Family.PLAYSTATION,
}

var _family: Family = Family.KEYBOARD_MOUSE

# The addon's node; null without the addon.
var _helper: Node = null


func _ready() -> void:
	_helper = get_node_or_null(HELPER_PATH)
	if _helper == null:
		push_warning("InputDeviceAdapter: no Input Helper autoload; glyphs stay keyboard and mouse")
		return
	_helper.connect(&"device_changed", _on_input_helper_device_changed)
	var device: String = str(_helper.get(&"device"))
	_family = family_of(device)


func _exit_tree() -> void:
	if is_instance_valid(_helper) and _helper.is_connected(
			&"device_changed", _on_input_helper_device_changed
	):
		_helper.disconnect(&"device_changed", _on_input_helper_device_changed)


## The family in use now.
func get_family() -> Family:
	return _family


## Whether the family in use is a pad.
func is_pad() -> bool:
	return _family != Family.KEYBOARD_MOUSE


## Whether the Input Helper addon was found.
func has_helper() -> bool:
	return is_instance_valid(_helper)


func _on_input_helper_device_changed(device: String, _device_index: int) -> void:
	var family: Family = family_of(device)
	if family == _family:
		return
	_family = family
	family_changed.emit(family)


## The family the addon's [param device] name is drawn as.
static func family_of(device: String) -> Family:
	var family: Family = FAMILY_BY_DEVICE.get(device, Family.OTHER_PAD)
	return family
