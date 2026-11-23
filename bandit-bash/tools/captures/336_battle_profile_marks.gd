# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     336_battle_profile_marks.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The weapon-profile marks (RF-039): the board with every profile on both sides, the tokens'
## marks given Power, Balance, Nimble and None in turn for the shot (drawing only, said in a NOTE,
## each token's own profile shown again after; a side with fewer than four units takes the rest
## in a second shot, "_2"); each board again in greyscale, a full-screen
## luminance overlay above every layer, so side and profile can be checked without colour; and the
## pause menu's board key. The unit detail's marks show in 330_battle_details' shots. Nothing in
## the battle is changed, so it ends idle in the player phase as it began.[br]
## Needs: the battle started (300_battle_start); runs after 335_battle_detail_keywords.

# The profiles handed out to each side's tokens in turn.
const PROFILES: Array[WeaponTriangle.Profile] = [
	WeaponTriangle.Profile.POWER,
	WeaponTriangle.Profile.BALANCE,
	WeaponTriangle.Profile.NIMBLE,
	WeaponTriangle.Profile.NONE,
]

# Above the pause menu's layer 10 and every other screen layer.
const GREY_LAYER: int = 100

# Rec. 601 luma: what a greyscale print or a colour-blind check sees as brightness.
const GREY_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_nearest;
void fragment() {
	vec3 seen = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(vec3(dot(seen, vec3(0.299, 0.587, 0.114))), 1.0);
}
"""


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	var players: PackedStringArray = session.state.units_of(CombatFact.CombatSide.PLAYER)
	var enemies: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	var fewest: int = mini(players.size(), enemies.size())
	if fewest == 0:
		fail("the board has no player or no enemy for the profile marks shot")
		return true
	# A side with fewer units than profiles takes the rest in a second pass, and so on.
	var passes: int = ceili(float(PROFILES.size()) / float(fewest))
	note("profile marks shot: Power, Balance, Nimble, None given in turn to %d players and %d "
			% [players.size(), enemies.size()]
			+ "enemies over %d pass(es) (drawing only)" % [passes])
	for pass_index: int in passes:
		_stage(view, players, pass_index)
		_stage(view, enemies, pass_index)
		var suffix: String = "" if pass_index == 0 else "_%d" % [pass_index + 1]
		await frames(SETTLE_FRAMES)
		await capture("battle_profile_marks" + suffix)
		var grey: CanvasLayer = _grey_overlay()
		scene().add_child(grey)
		await frames(SETTLE_FRAMES)
		await capture("battle_profile_marks_grey" + suffix)
		grey.free()
	for unit_id: String in view.token_ids():
		var token: UnitToken = view.token_of(unit_id)
		token.show_profile(session.state.weapon_profile_of(
				session.state.equipped_weapon_id(unit_id)
		))
	var pause: Node = scene().get_node(^"PauseMenu")
	pause.call(&"open")
	pause.call(&"open_board_key")
	await frames(SETTLE_FRAMES)
	if not pause.call(&"is_board_key_open"):
		fail("the pause menu's board key didn't open")
	await capture("battle_board_key")
	pause.call(&"close")
	await frames(SETTLE_FRAMES)
	return true


# Gives units' tokens the profiles in turn, pass_index passes of the side's count along.
func _stage(view: BattleView, units: PackedStringArray, pass_index: int) -> void:
	for index: int in units.size():
		var token: UnitToken = view.token_of(units[index])
		if token != null:
			token.show_profile(PROFILES[(index + pass_index * units.size()) % PROFILES.size()])


# A layer drawing the screen below it in greyscale; it takes no input.
func _grey_overlay() -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = GREY_LAYER
	var shader: Shader = Shader.new()
	shader.code = GREY_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var cover: ColorRect = ColorRect.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.material = material
	layer.add_child(cover)
	return layer
