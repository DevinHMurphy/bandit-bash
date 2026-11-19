# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     net_case_base.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Shared by the net suite's case files: reporting through the runner's check, the scene tree's
## root for the cases that reach autoloads, and a logger that keeps engine errors.

var _report: Callable
var _root: Window


func _init(check: Callable, root: Window) -> void:
	_report = check
	_root = root


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)


# Keeps every engine or script error logged while it is added with OS.add_logger. The engine may
# call a logger from any thread, so the list is locked.
class ErrorCatcher:
	extends Logger

	var _errors: PackedStringArray = []
	var _lock: Mutex = Mutex.new()

	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			_is_editor_notified: bool,
			_error_type: int,
			_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_errors.append("%s (%s:%d, %s)" % [
			rationale if not rationale.is_empty() else code, file, line, function,
		])
		_lock.unlock()

	## Every error logged while it was added.
	func get_errors() -> PackedStringArray:
		_lock.lock()
		var copy: PackedStringArray = _errors.duplicate()
		_lock.unlock()
		return copy
