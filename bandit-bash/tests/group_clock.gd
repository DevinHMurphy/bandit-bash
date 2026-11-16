# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     group_clock.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends RefCounted
## Times a suite's test groups for the test report: [method lap] closes the open group and opens
## the next, [method stop] closes the last, and each closed group prints one line,
## [code]TIME  <ms> ms  <group>[/code], that [code]tools/run_tests.sh[/code] reads. A group is a
## case file, an inline test function, or a phase of a case that runs over frames; it stays open
## across frames until the next lap, so waits count. Time outside any group isn't reported.[br]
## Static, one clock per process: a suite is one Godot process. No class name, so a suite reaches
## it through a preload before autoloads and the class cache matter.

# The line's prefix: tools/run_tests.sh and tools/test_report.awk match it, so they change with it.
const LINE_FORMAT: String = "TIME  %d ms  %s"

static var _group: String = ""
static var _started_msec: int = 0


## Closes the open group, printing its time, and opens [param group]. Call it before the group's
## first work, its case file's constructor included.
static func lap(group: String) -> void:
	stop()
	_group = group
	_started_msec = Time.get_ticks_msec()


## Closes the open group, printing its time; does nothing when none is open. Call it before the
## summary line, so the last group prints.
static func stop() -> void:
	if _group.is_empty():
		return
	print(LINE_FORMAT % [Time.get_ticks_msec() - _started_msec, _group])
	_group = ""
