# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     capture_screens.gd
# Author:
# Created:  November 18, 2026
# Modified: November 23, 2026
# ==============================================================================

extends SceneTree
## Screenshots every screen at one window size, for checking the UI's layout by eye (UI style
## guide: base 1280×720, shown at 1920×1080 and the Steam Deck's 1280×800). Runs each group in
## [code]tools/captures/[/code] in its file number's order on one throwaway run; each shot is
## [code]<out>/<size>/<nn>_<name>.png[/code], with visible text under [constant MIN_FONT_SIZE] base
## units and visible controls outside the window listed, and their count printed at the end.[br]
## To add shots, add [code]tools/captures/<number>_<name>.gd[/code] extending
## [code]capture_group.gd[/code] by path; its number places it; its doc names what it needs.[br]
## Run it through [code]tools/run_captures.sh[/code] (or [code].cmd[/code]): the run writes save
## file 1, so the tool refuses any user folder but the throwaway one that script makes (see
## [constant USER_DIR_PREFIX]). Authoring tooling: nothing in the game loads it. Never names an
## autoload (a [code]--script[/code] run compiles before they register); it reaches them as nodes.
## @tutorial(UI style guide): docs/design/ui-style.md

const CaptureGroup = preload("res://tools/captures/capture_group.gd")

# The groups' folder: every [code]<number>_<name>.gd[/code] in it is a group.
const GROUP_DIR: String = "res://tools/captures"

## The tool runs only when a folder on the user folder's path starts with this: the name
## tools/run_captures.sh gives its throwaway folder, so the two change together. A name, not a
## comparison with the default path, so any folder the script didn't make is refused too.
const USER_DIR_PREFIX: String = "bandit_bash_captures"

## The style guide's floor for text, in base units.
const MIN_FONT_SIZE: int = 14

var _out_dir: String = ""
var _size: Vector2i = Vector2i(1280, 720)
var _shot: int = 0
var _issues: int = 0


func _initialize() -> void:
	if not _is_throwaway_user_dir():
		push_error((
			"CaptureScreens: refusing to run in the user folder %s, which isn't a throwaway one:"
			+ " run bandit-bash/tools/run_captures.sh (or run_captures.cmd) instead"
		) % [OS.get_user_data_dir()])
		quit(1)
		return
	if not _read_args():
		quit(1)
		return
	_run.call_deferred()


# Whether user:// sits under a folder named for run_captures.sh's throwaway one. Reads the folder
# Godot actually resolved, so an override.cfg or a project setting can't slip past it.
func _is_throwaway_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with(USER_DIR_PREFIX):
			return true
	return false


func _read_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		if args[i] == "--out":
			_out_dir = args[i + 1]
		elif args[i] == "--size":
			var parts: PackedStringArray = args[i + 1].split("x")
			if parts.size() == 2:
				_size = Vector2i(parts[0].to_int(), parts[1].to_int())
	if _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		push_error("CaptureScreens: run windowed with -- --out <dir> [--size WxH]")
		return false
	_out_dir = _out_dir.path_join("%dx%d" % [_size.x, _size.y])
	return DirAccess.make_dir_recursive_absolute(_out_dir) == OK


# Sizes the window, then runs the groups in order until one ends the run.
func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = _size
	root.position = Vector2i.ZERO
	for _frame: int in CaptureGroup.SETTLE_FRAMES:
		await process_frame
	if root.size != _size:
		print("NOTE  the window is %s, not %s (screen %s)" % [
			root.size, _size, DisplayServer.screen_get_size(),
		])
	for group: CaptureGroup in _load_groups():
		group.attach(self, _capture)
		var goes_on: bool = await group.run()
		if not goes_on:
			break
	print("--- %d shots, %d issues ---" % [_shot, _issues])
	quit(0)


# Every group in GROUP_DIR, by file number, then name where numbers tie. A file that doesn't load
# as a group is skipped with a FAIL line.
func _load_groups() -> Array[CaptureGroup]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(GROUP_DIR):
		if file.get_extension() == "gd" and file.get_slice("_", 0).is_valid_int():
			files.append(file)
	files.sort_custom(_is_group_before)
	var groups: Array[CaptureGroup] = []
	for file: String in files:
		var script: GDScript = load(GROUP_DIR.path_join(file))
		var group: CaptureGroup = null
		if script != null and script.can_instantiate():
			group = script.new() as CaptureGroup
		if group == null:
			print("FAIL  %s didn't load as a capture group" % [file])
			continue
		groups.append(group)
	return groups


func _is_group_before(a: String, b: String) -> bool:
	var a_number: int = a.get_slice("_", 0).to_int()
	var b_number: int = b.get_slice("_", 0).to_int()
	if a_number != b_number:
		return a_number < b_number
	return a < b


# Saves the window as the next shot and lists its text and clipping issues.
func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path: String = _out_dir.path_join("%02d_%s.png" % [_shot, shot_name])
	var image: Image = root.get_texture().get_image()
	var err: Error = image.save_png(path)
	print("SHOT  %s%s" % [path, "" if err == OK else " (%s)" % [error_string(err)]])
	for issue: String in _issues_in(root):
		_issues += 1
		print("  ISSUE  %s: %s" % [shot_name, issue])


# Visible text under the floor, and visible controls reaching outside the window.
func _issues_in(top: Node) -> PackedStringArray:
	var found: PackedStringArray = []
	var bounds: Rect2 = root.get_visible_rect().grow(0.5)
	for node: Node in top.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree():
			continue
		var size: int = _font_size_of(control)
		if size > 0 and size < MIN_FONT_SIZE and _has_text(control):
			found.append("%s text at %d" % [control.get_path(), size])
		# A scroll container's content may run past it; the container itself is checked.
		if _is_scrolled(control):
			continue
		# On screen, through any camera or canvas layer above it.
		var to_screen: Transform2D = control.get_global_transform_with_canvas()
		var rect: Rect2 = to_screen * Rect2(Vector2.ZERO, control.size)
		if rect.has_area() and not bounds.encloses(rect):
			found.append("%s outside the window %s" % [control.get_path(), rect])
	return found


func _font_size_of(control: Control) -> int:
	if control is RichTextLabel:
		return control.get_theme_font_size(&"normal_font_size")
	if control is Label or control is Button or control is LineEdit:
		return control.get_theme_font_size(&"font_size")
	return 0


func _has_text(control: Control) -> bool:
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).get_parsed_text().is_empty()
	if control is Button:
		return not (control as Button).text.is_empty()
	return true


func _is_scrolled(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false
