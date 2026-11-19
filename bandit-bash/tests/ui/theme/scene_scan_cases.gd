# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     scene_scan_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## The scenes, scripts and project settings against the shared theme, for the ui/theme suite: no
## [code].tscn[/code] under [code]ui/[/code] sets a colour, font, font size or style box override,
## or a theme of its own, except the three scenes the darkness phase (DK7) owns; no
## [code].gd[/code] under [code]ui/[/code] writes a token's colour as a literal; the project's base
## viewport, stretch, window, theme and pointer-focus settings; the red and blue tile overlays
## drawing their tokens. Reads files as text, so no scene is loaded but the overlays.

const UI_FOLDER: String = "res://ui/"

# Scenes DK7 is changing on its own branch; their overrides wait for a follow-up after both merge.
const EXEMPT_SCENES: PackedStringArray = [
	"res://ui/battle/hud/phase_banner.tscn",
	"res://ui/battle/hud/turn_bar.tscn",
	"res://ui/battle/board/darkness_overlay.tscn",
]

# A scene line that sets a look outside the theme.
const OVERRIDE_PREFIXES: PackedStringArray = [
	"theme_override_colors/", "theme_override_fonts/", "theme_override_font_sizes/",
	"theme_override_styles/",
]

# The red and blue tile overlays and their tokens.
const OVERLAYS: Dictionary[String, StringName] = {
	"res://ui/battle/board/move_overlay.tscn": UiTokens.BLOCK,
	"res://ui/battle/board/attack_overlay.tscn": UiTokens.DANGER,
	"res://ui/battle/board/enemy_range_overlay.tscn": UiTokens.DANGER,
	"res://ui/battle/board/danger_overlay.tscn": UiTokens.DANGER,
}

var _check: Callable
var _root: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the overlays are added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	_test_scenes()
	_test_scripts()
	_test_project()
	_test_overlays()


func _test_scenes() -> void:
	var scenes: PackedStringArray = files_under(UI_FOLDER, ".tscn")
	var found: PackedStringArray = []
	for path: String in scenes:
		if EXEMPT_SCENES.has(path):
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var line: String = lines[i]
			var is_override: bool = false
			for prefix: String in OVERRIDE_PREFIXES:
				is_override = is_override or line.begins_with(prefix)
			var is_own_theme: bool = (
					line.begins_with("[sub_resource type=\"Theme\"")
					or line.begins_with("theme = SubResource(")
			)
			if is_override or is_own_theme:
				found.append("%s:%d %s" % [path, i + 1, line])
	_check.call("scenes: none of %d under ui/ sets a colour, font, size or style override" % [
		scenes.size(),
	], found.is_empty() and scenes.size() > 50, "; ".join(found))


# A Color(r, g, b[, a]) literal with a token's red, green and blue, in any script under ui/.
func _test_scripts() -> void:
	var literal: RegEx = RegEx.create_from_string(
			"Color\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)"
	)
	var hex: RegEx = RegEx.create_from_string("Color\\(\"#?([0-9a-fA-F]{6})")
	var tokens: Array[Color] = []
	for token: StringName in UiTokens.ALL:
		tokens.append(UiTokens.color(token))
	var scripts: PackedStringArray = files_under(UI_FOLDER, ".gd")
	var found: PackedStringArray = []
	for path: String in scripts:
		var text: String = FileAccess.get_file_as_string(path)
		var colours: Array[Color] = []
		for hit: RegExMatch in literal.search_all(text):
			colours.append(Color(
					hit.get_string(1).to_float(), hit.get_string(2).to_float(),
					hit.get_string(3).to_float()
			))
		for hit: RegExMatch in hex.search_all(text):
			colours.append(Color(hit.get_string(1)))
		for colour: Color in colours:
			for token: Color in tokens:
				if _same_rgb(colour, token):
					found.append("%s %s" % [path, colour])
	_check.call("scripts: none of %d under ui/ writes a token's colour as a literal" % [
		scripts.size(),
	], found.is_empty() and scripts.size() > 50, "; ".join(found))


func _test_project() -> void:
	var settings: Dictionary[String, Variant] = {
		"display/window/size/viewport_width": 1280,
		"display/window/size/viewport_height": 720,
		"display/window/size/mode": DisplayServer.WINDOW_MODE_MAXIMIZED,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "expand",
		"gui/theme/custom": "res://ui/theme/game_theme.tres",
		"gui/common/show_focus_state_on_pointer_event": 0,
	}
	var wrong: PackedStringArray = []
	for key: String in settings:
		if ProjectSettings.get_setting(key) != settings[key]:
			wrong.append("%s is %s" % [key, ProjectSettings.get_setting(key)])
	_check.call("project: 1280×720 base, canvas_items, expand, maximized, theme, focus", (
			wrong.is_empty()
	), "; ".join(wrong))


func _test_overlays() -> void:
	var wrong: PackedStringArray = []
	for path: String in OVERLAYS:
		var scene: PackedScene = load(path)
		var overlay: TileOverlay = scene.instantiate()
		_root.add_child(overlay)
		var token: Color = UiTokens.color(OVERLAYS[path])
		var fill: Color = overlay.drawn_fill_color()
		var edge: Color = overlay.drawn_edge_color()
		if (
				overlay.color_token != OVERLAYS[path]
				or not _same_rgb(fill, token)
				or not is_equal_approx(fill.a, overlay.fill_color.a)
				or not _same_rgb(edge, token)
		):
			wrong.append("%s fill %s edge %s" % [path.get_file(), fill, edge])
		overlay.free()
	_check.call("overlays: move draws block, attack, enemy range and danger draw danger", (
			wrong.is_empty()
	), "; ".join(wrong))


func _same_rgb(a: Color, b: Color) -> bool:
	return Color(a, 1.0).is_equal_approx(Color(b, 1.0))


## Every file under [param folder], at any depth, whose name ends with [param suffix], sorted.
static func files_under(folder: String, suffix: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(suffix):
			found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(files_under(folder.path_join(sub), suffix))
	found.sort()
	return found
