# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     raw_save_section.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

class_name RawSaveSection
extends SaveSection
## Holds a section's slot in the file for a system that doesn't exist yet.
##
## Keeps whatever data it is given and writes it back unchanged, so a file written today already
## has the section, and nothing saved there is lost. When the real system arrives it registers
## its own [SaveSection] under the same key, replacing this one, and reads the data at version 1.

var _key: String = ""
var _data: Dictionary = {}


## [param key]: the section key to hold, e.g. [code]"unlocks"[/code].
func _init(key: String) -> void:
	_key = key


func get_key() -> String:
	return _key


func get_version() -> int:
	return 1


func capture() -> Dictionary:
	return _data.duplicate(true)


func restore(data: Dictionary) -> Error:
	_data = data.duplicate(true)
	return OK


func reset() -> void:
	_data = {}
