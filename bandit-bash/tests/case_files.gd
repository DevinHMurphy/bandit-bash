# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     case_files.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Finds and runs a suite's case files, so adding one edits no shared file. Every
## [code]*_cases.gd[/code] under [code]res://tests/[/code] declares the suite that runs it,
## [code]const SUITE: String = "ui/display"[/code], named as [code]tools/run_tests.sh[/code] prints
## it; a subclass inherits its parent's, as Godot forbids redeclaring it. A file declaring a top
## folder with parts ([code]map_set[/code]) is shared by those parts, which build it themselves.[br]
## Files are read as text, never loaded, until their own suite builds them: UI cases name
## autoloads, which a suite running in [code]_init[/code] can't compile. Every suite checks every
## file and prints one FAIL line per missing or unknown declaration, and nothing when all are
## fine, so the case counts hold.[br]
## No class name, so a suite reaches it through a preload before autoloads and the class cache.

const GroupClock = preload("res://tests/group_clock.gd")

const TESTS_DIR: String = "res://tests/"
const CASES_SUFFIX: String = "_cases.gd"
const RUN_ALL_FILE: String = "run_all.gd"

# The declarations, matched as whole lines; a case file writes them exactly so.
const SUITE_LINE: String = "(?m)^const SUITE: String = \"([^\"]*)\"\\s*$"
const NEEDS_USER_FOLDER_LINE: String = "(?m)^const NEEDS_TEST_USER_FOLDER: bool = true\\s*$"
const EXTENDS_LINE: String = "(?m)^extends \"(res://[^\"]+\\.gd)\"\\s*$"

# Why a file that needs a test user folder was skipped: tools/run_tests.sh fails a suite whose
# output holds this text, since under the runner every suite has one.
const NO_USER_FOLDER: String = "needs a test user folder"

# The most parents followed to find an inherited declaration: guards a cycle of extends.
const MAX_PARENTS: int = 8


## Runs the case files declaring the suite of [param suite] (a run_all.gd, passing itself), in
## [code]res://[/code] path order: laps the group clock with each file's name, builds it and calls
## its [code]run()[/code]. Returns the built files in that order. [param context] is the second
## [code]_init[/code] argument for files that take one. A file declaring
## [code]NEEDS_TEST_USER_FOLDER[/code] is passed to [param skip] as (name, reason) instead when
## [param has_user_folder] is false.
static func run(
		suite: Object,
		check: Callable,
		context: Variant = null,
		has_user_folder: bool = true,
		skip: Callable = Callable(),
) -> Array[RefCounted]:
	var found: Array[RefCounted] = []
	var script: Script = suite.get_script() as Script
	if script == null:
		check.call("case files: the suite has a script", false, str(suite))
		return found
	for path: String in paths(suite_name(script.resource_path), check):
		var file_name: String = path.get_file().get_basename()
		if not has_user_folder and _needs_user_folder(path):
			if skip.is_valid():
				skip.call(file_name, NO_USER_FOLDER)
			continue
		GroupClock.lap(file_name)
		var cases: RefCounted = _build(path, check, context)
		if cases != null:
			cases.call(&"run")
			found.append(cases)
	return found


## The case files declaring [param suite], sorted by path, after checking every case file under
## [code]res://tests/[/code]: each one with no declaration, or one naming no suite or folder of
## parts, fails once through [param check].
static func paths(suite: String, check: Callable) -> PackedStringArray:
	var suites: Dictionary[String, bool] = {}
	var folders: Dictionary[String, bool] = {}
	_find_suites(suites, folders)
	var mine: PackedStringArray = []
	for path: String in _case_paths(TESTS_DIR):
		var declared: String = _declared_suite(path)
		if declared.is_empty():
			check.call("case files: %s declares no SUITE" % [path], false, (
					"add const SUITE: String = \"<suite>\", named as the runner prints it"
			))
		elif not suites.has(declared) and not folders.has(declared):
			check.call("case files: %s declares an unknown suite" % [path], false, (
					"\"%s\" has no run_all.gd, nor parts with one" % [declared]
			))
		elif declared == suite:
			mine.append(path)
	mine.sort()
	return mine


## The suite a run_all.gd at [param run_all_path] is: its folder under [code]res://tests/[/code].
static func suite_name(run_all_path: String) -> String:
	return run_all_path.trim_prefix(TESTS_DIR).trim_suffix("/" + RUN_ALL_FILE)


# Builds the case file at path with the check, and the context too when its _init takes two
# arguments. Fails through check, returning null, when it can't.
static func _build(path: String, check: Callable, context: Variant) -> RefCounted:
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		check.call("case files: %s loads" % [path], false, "see the error above")
		return null
	var needed: int = _required_arguments(script)
	var cases: RefCounted = null
	if needed == 1:
		cases = script.new(check)
	elif needed == 2 and context != null:
		cases = script.new(check, context)
	else:
		check.call("case files: %s can be built" % [path], false, (
				"_init needs %d arguments; the suite gives the check%s" % [
					needed, "" if context == null else " and its context",
				]
		))
		return null
	if not cases.has_method(&"run"):
		check.call("case files: %s has run()" % [path], false, "")
		return null
	return cases


# The arguments the script's _init, its own or inherited, needs: those without a default.
static func _required_arguments(script: GDScript) -> int:
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == "_init":
			var arguments: Array = method["args"]
			var defaults: Array = method["default_args"]
			return arguments.size() - defaults.size()
	return 0


# The suite the case file at path declares, or its nearest parent script's; "" for none.
static func _declared_suite(path: String) -> String:
	var suite_line: RegEx = RegEx.create_from_string(SUITE_LINE)
	var extends_line: RegEx = RegEx.create_from_string(EXTENDS_LINE)
	var current: String = path
	for _parent: int in MAX_PARENTS:
		if not FileAccess.file_exists(current):
			return ""
		var text: String = FileAccess.get_file_as_string(current)
		var declared: RegExMatch = suite_line.search(text)
		if declared != null:
			return declared.get_string(1)
		var parent: RegExMatch = extends_line.search(text)
		if parent == null:
			return ""
		current = parent.get_string(1)
	return ""


static func _needs_user_folder(path: String) -> bool:
	var needs: RegEx = RegEx.create_from_string(NEEDS_USER_FOLDER_LINE)
	return needs.search(FileAccess.get_file_as_string(path)) != null


# Every *_cases.gd under dir, at any depth.
static func _case_paths(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(CASES_SUFFIX):
			found.append(dir.path_join(file))
	for child: String in DirAccess.get_directories_at(dir):
		found.append_array(_case_paths(dir.path_join(child)))
	return found


# The suites as tools/run_tests.sh finds them: tests/<name>/run_all.gd is suite <name>; in a
# folder without one, each tests/<name>/<part>/run_all.gd is suite <name>/<part>, and <name> is a
# folder of parts.
static func _find_suites(
		suites: Dictionary[String, bool], folders: Dictionary[String, bool]
) -> void:
	for folder: String in DirAccess.get_directories_at(TESTS_DIR):
		if FileAccess.file_exists(TESTS_DIR.path_join(folder).path_join(RUN_ALL_FILE)):
			suites[folder] = true
			continue
		for part: String in DirAccess.get_directories_at(TESTS_DIR.path_join(folder)):
			var part_dir: String = TESTS_DIR.path_join(folder).path_join(part)
			if FileAccess.file_exists(part_dir.path_join(RUN_ALL_FILE)):
				suites["%s/%s" % [folder, part]] = true
				folders[folder] = true
