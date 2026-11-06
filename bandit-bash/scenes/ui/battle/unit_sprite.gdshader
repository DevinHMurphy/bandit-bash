// ==============================================================================
// Bandit Bash
// Copyright (c) 2026 Derc Development
// Licensed under the MIT License. See LICENSE.
//
// File:     unit_sprite.gdshader
// Author:
// Created:  November 5, 2026
// Modified: November 5, 2026
// ==============================================================================
//
// A unit's sprite on the battle board (UnitToken): an outline in its side's colour, gray while
// the unit can't act, and a tint. Godot_FE's StrokeShader behaviour, rewritten: line_color,
// line_thickness, color_factor (here gray_amount) and modulate_color.
//
// The quad grows by line_thickness texels on every side, so the outline of a sprite that touches
// its image's edge isn't cut off; samples outside the image read as transparent. The node's own
// modulate (a defeated unit's fade) is carried from vertex() and applied last, because writing
// COLOR in fragment() would otherwise drop it.

shader_type canvas_item;

// The outline's colour; its alpha is how strongly it shows. UnitToken sets it by side.
uniform vec4 line_color : source_color = vec4(1.0);
// The outline's width, in texels. 0 draws none.
uniform float line_thickness : hint_range(0.0, 4.0, 0.5) = 1.0;
// How gray the sprite is: 0 in full colour, 1 fully gray.
uniform float gray_amount : hint_range(0.0, 1.0) = 0.0;
// Multiplies the sprite's colours, not its outline. White leaves it as drawn.
uniform vec4 modulate_color : source_color = vec4(1.0);

varying vec4 node_color;


void vertex() {
	node_color = COLOR;
	vec2 grow_texels = vec2(line_thickness);
	VERTEX += (UV * 2.0 - 1.0) * grow_texels;
	UV = (UV - 0.5) * (1.0 + 2.0 * grow_texels * TEXTURE_PIXEL_SIZE) + 0.5;
}


// 1.0 inside the image, 0.0 in the grown margin. TEXTURE can't be passed to a function, so the
// samples stay in fragment() and only this mask is shared.
float inside(vec2 uv) {
	vec2 within = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return within.x * within.y;
}


void fragment() {
	vec4 base = texture(TEXTURE, UV) * inside(UV);
	vec2 offset = TEXTURE_PIXEL_SIZE * line_thickness;
	vec2 left = UV + vec2(-offset.x, 0.0);
	vec2 right = UV + vec2(offset.x, 0.0);
	vec2 up = UV + vec2(0.0, -offset.y);
	vec2 down = UV + vec2(0.0, offset.y);
	vec2 up_left = UV + vec2(-offset.x, -offset.y);
	vec2 up_right = UV + vec2(offset.x, -offset.y);
	vec2 down_left = UV + vec2(-offset.x, offset.y);
	vec2 down_right = UV + vec2(offset.x, offset.y);
	float outline = texture(TEXTURE, left).a * inside(left);
	outline += texture(TEXTURE, right).a * inside(right);
	outline += texture(TEXTURE, up).a * inside(up);
	outline += texture(TEXTURE, down).a * inside(down);
	outline += texture(TEXTURE, up_left).a * inside(up_left);
	outline += texture(TEXTURE, up_right).a * inside(up_right);
	outline += texture(TEXTURE, down_left).a * inside(down_left);
	outline += texture(TEXTURE, down_right).a * inside(down_right);
	float edge_alpha = line_thickness > 0.0 ? min(outline, 1.0) * line_color.a : 0.0;
	// ASSUMPTION: Godot_FE weighed red as r * r, read as a typo for 0.21 beside the 0.71 and 0.07
	// it gave green and blue (Rec. 709's weights, rounded).
	float gray = dot(base.rgb, vec3(0.21, 0.71, 0.07));
	vec3 sprite = mix(base.rgb * modulate_color.rgb, vec3(gray), gray_amount);
	// The sprite drawn over its outline.
	float alpha = base.a + edge_alpha * (1.0 - base.a);
	vec3 rgb = sprite * base.a + line_color.rgb * edge_alpha * (1.0 - base.a);
	rgb = alpha > 0.0 ? rgb / alpha : vec3(0.0);
	COLOR = vec4(rgb, alpha) * node_color;
}
