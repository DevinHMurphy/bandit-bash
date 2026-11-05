# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_view.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattleView
extends Node2D
## The battle board: the map scene for terrain, a [UnitToken] per unit, the [DarknessOverlay], turn
## input's overlays, path and cursor, and the [CameraRig], drawn from one [CombatSession] and
## animated by its facts.
##
## [method bind] builds the board from state ([BoardViewModel]); after that, facts reach it only
## through the session's [member CombatSession.playback], which [method advance] steps each frame:
## moves walk their path, damage and heal numbers rise, defeated units fade out, and a tile the
## darkness deepens is redrawn. Each fact's wait is the time its animation takes, so the next fact
## starts when it ends. The board steps its own tweens with the same time, so a test can drive it
## frame by frame without a running tree.[br]
## [b]Reading only:[/b] it never changes combat state and submits no command; turn input does
## ([BattleController]). Facts already queued at [method bind] are skipped, since the board is
## built from the state they led to.[br]
## [b]Turn input's pieces[/b] (the move, attack and enemy range [TileOverlay]s, the [PathPreview]
## and the [TileCursor]) are children here so they share the board's space and camera; the board
## only sizes them to the map, and [BattleController] says what they show.[br]
## [b]Faster playback:[/b] held fast-forward ([method set_fast_forward]) runs waits and animations
## [member fast_forward_speed] times faster, in order; [method skip_playback] plays everything
## queued at once behind the [SkipFade].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Playback ran out of facts and every animation that holds it has ended. Emitted once per stretch
## of playback, after the last fact's animation.
signal settled()

@export_group("Scenes")

## The token placed for each unit.[br]
## [b]Unset:[/b] no token is drawn and an error is reported at [method bind].
@export var token_scene: PackedScene = null

## The number shown for each damage or heal.[br]
## [b]Unset:[/b] no numbers are shown.
@export var damage_number_scene: PackedScene = null

## Whether the map scene's marker layers and marker nodes (deployment tiles, enemy slots) show.
## Off for play; on to check a map's authoring.
@export var show_markers: bool = false

@export_group("Pacing")

## How fast a unit walks along its path at playback speed 1.0 (Godot_FE
## [code]CController.gd[/code], [code]MOVEMENT_SPEED[/code] 96 × 5, with 32 px tiles).[br]
## [b]Units:[/b] pixels per second.
@export_range(16.0, 4000.0, 1.0) var move_speed: float = 480.0

## The pause after an enemy's move, before its action (Godot_FE [code]CController.gd[/code],
## [code]ai_perform_selected_action[/code]).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] no pause.
@export_range(0.0, 2.0, 0.01) var ai_action_pause: float = 0.1

## How long playback waits on a damage or heal number before the next fact; the number itself
## stays for its own [member DamageNumber.lifetime].[br]
## [b]Units:[/b] seconds.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.0, 2.0, 0.01) var number_hold: float = 0.35

## How long a defeated unit takes to fade out; playback waits for it.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it vanishes at once.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.0, 3.0, 0.01) var defeat_time: float = 0.4

## Game speed: every wait and animation is divided by it ([member FactPlayback.speed]). Held
## fast-forward multiplies it by [member fast_forward_speed] without changing it.[br]
## [b]1.0:[/b] normal speed. [b]2.0:[/b] twice as fast.
@export_range(0.1, 8.0, 0.1) var playback_speed: float = 1.0:
	set(value):
		playback_speed = value
		if _session != null:
			_session.playback.speed = playback_speed

## How many times faster every wait and animation runs while fast-forward is held
## ([method set_fast_forward]), on top of [member playback_speed]. The skip's fade isn't sped up.
## An options-menu setting later (combat UI plan, UI6).[br]
## [b]1.0:[/b] holding changes nothing. [b]4.0:[/b] a 0.4 s walk takes 0.1 s.
@export_range(1.0, 16.0, 0.5) var fast_forward_speed: float = 4.0

@export_group("")

# The session drawn; null before bind() and after unbind().
var _session: CombatSession = null

# The map scene's terrain layer, which tile positions come from.
var _terrain: TileMapLayer = null

# The token of each unit on the board, by unit id.
var _tokens: Dictionary[String, UnitToken] = {}

# Tweens playback waits for (moves, pans, fades), and cosmetic ones it doesn't (numbers); both
# stepped by advance(), never by the tree.
var _holding: Array[Tween] = []
var _cosmetic: Array[Tween] = []

# Each token's latest walk, by unit id.
var _walks: Dictionary[String, Tween] = {}

# The fact the bus last played and the wait it needs, for the duration hook; see _duration_of().
var _last_fact: CombatFact = null
var _last_duration: float = 0.0

var _is_settled: bool = true

var _is_fast_forward: bool = false

# --- The skip (meaningful while bound; skip_playback() starts it, advance() steps it) ----------
# None:       _skip_tween is null. Playback runs as usual.
# Fading out: _skip_tween darkens the SkipFade. Playback and animations run on as usual
#             underneath; is_settled() is false, so turn input waits.
# Black:      not a step of its own. In the advance() the fade out ends, every queued fact plays
#             at once (FactPlayback.is_fast_forward, its waits skipped) and every animation is
#             finished, then the fade in starts in the same call.
# Fading in:  _is_skip_clearing; nothing is left to play unless the flush stopped early.
# A fact the pause hook marks (FactPlayback.pause_hook: a boss combat, a player unit's death)
# stops the flush with playback paused before it (_skip_stopped); when the fade in ends,
# playback resumes and that fact plays at normal speed. Holding fast-forward doesn't speed the
# fades, and skip_playback() during a skip or with nothing to play does nothing.
var _skip_tween: Tween = null
var _is_skip_clearing: bool = false
var _skip_stopped: bool = false

# Seconds left of the fade _skip_tween plays.
var _skip_left: float = 0.0

@onready var _map_holder: Node2D = %MapHolder
@onready var _darkness: DarknessOverlay = %DarknessOverlay
@onready var _token_layer: Node2D = %Tokens
@onready var _number_layer: Node2D = %Numbers
@onready var _camera: CameraRig = %CameraRig
@onready var _move_overlay: TileOverlay = %MoveOverlay
@onready var _attack_overlay: TileOverlay = %AttackOverlay
@onready var _enemy_range_overlay: TileOverlay = %EnemyRangeOverlay
@onready var _path_preview: PathPreview = %PathPreview
@onready var _cursor: TileCursor = %TileCursor
@onready var _skip_fade: SkipFade = %SkipFade


func _exit_tree() -> void:
	unbind()


func _process(delta: float) -> void:
	advance(delta)


## Draws [param session]: instances its map scene, places a token per unit on its tile, draws the
## darkness, frames the map, and from then on plays its facts. Facts already queued are skipped
## (see the class doc). Binding again replaces the session drawn.
func bind(session: CombatSession) -> void:
	unbind()
	if session == null or session.setup == null or session.setup.map == null:
		push_error("BattleView: nothing to draw - the session has no map")
		return
	_session = session
	# The board is built from the state the queued facts led to, so they are played to no one.
	_session.playback.play_all()
	_clear_board()
	_build_map(session.setup.map)
	var model: BoardViewModel = BoardViewModel.build(session)
	for view: BoardViewModel.UnitView in model.units:
		_place_token(view)
	_darkness.show_layers(model.darkness)
	_camera.frame(map_rect())
	_session.playback.speed = playback_speed
	_session.playback.duration_hook = _duration_of
	_connect_bus(_session.bus)
	_is_settled = true


## Stops drawing the session: its bus is let go and its playback keeps no hook of the board's.
## A skip under way ends with the screen cleared, and fast-forward is let go; the board's other
## nodes stay as they are. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	_end_skip()
	_is_fast_forward = false
	_disconnect_bus(_session.bus)
	if _session.playback.duration_hook == _duration_of:
		_session.playback.duration_hook = Callable()
	_session = null


## Steps playback and every animation by [param delta] seconds of real time
## ([member fast_forward_speed] times that while fast-forward is held), steps a skip's fade by
## [param delta] itself, and emits [signal settled] when all have run out. Called each frame by
## [method _process]; tests call it directly.
func advance(delta: float) -> void:
	if _session == null:
		return
	# Facts queued since the last step count as busy, so a batch that plays out within this step
	# still ends with settled.
	if not is_settled():
		_is_settled = false
	var real: float = maxf(delta, 0.0)
	# Scaling the time given to playback, not FactPlayback.speed, leaves the game speed (a lobby
	# setting, the same for every peer) untouched.
	var scaled: float = real * (fast_forward_speed if _is_fast_forward else 1.0)
	_session.playback.advance(scaled)
	var step: float = scaled * _session.playback.speed
	_step_tweens(_holding, step)
	_step_tweens(_cosmetic, step)
	_step_skip(real)
	if is_settled() and not _is_settled:
		_is_settled = true
		settled.emit()


## Whether playback has no fact queued, no animation holds it and no skip is under way.
func is_settled() -> bool:
	return _session == null or (
			_session.playback.pending() == 0 and _holding.is_empty() and _skip_tween == null
	)


## Holds fast-forward while [param is_held]: playback's waits and every animation run
## [member fast_forward_speed] times faster, in their order. [member playback_speed] is unchanged.
func set_fast_forward(is_held: bool) -> void:
	_is_fast_forward = is_held


## Whether fast-forward is held ([method set_fast_forward]).
func is_fast_forward() -> bool:
	return _is_fast_forward


## Skips the playback running: the screen fades to black ([SkipFade]), every queued fact then
## plays at once with its animation finished, and the screen fades back in. A fact
## [member FactPlayback.pause_hook] marks stops the skip early; the fade in shows it, then it plays
## at normal speed. Returns whether a skip started: not while one is under way or nothing plays.
func skip_playback() -> bool:
	if _skip_tween != null or is_settled():
		return false
	_skip_tween = _skip_fade.fade_out()
	_skip_left = _skip_fade.fade_out_time
	_is_skip_clearing = false
	_skip_stopped = false
	return true


## Whether a skip is under way ([method skip_playback]), from its fade out to the end of its
## fade in.
func is_skipping() -> bool:
	return _skip_tween != null


## The skip's fade, for reading how dark it is.
func get_skip_fade() -> SkipFade:
	return _skip_fade


## The session drawn; null when none is.
func get_session() -> CombatSession:
	return _session


## The token of [param unit_id]; null when it has none (not on the map, or defeated).
func token_of(unit_id: String) -> UnitToken:
	return _tokens.get(unit_id, null)


## The ids of every unit with a token, sorted.
func token_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray(_tokens.keys())
	ids.sort()
	return ids


## The darkness overlay, for reading what it draws.
func get_darkness() -> DarknessOverlay:
	return _darkness


## The overlay of the selected unit's move tiles (and the swap partners' tiles).
func get_move_overlay() -> TileOverlay:
	return _move_overlay


## The overlay of the selected unit's attack tiles, and of an action's targets.
func get_attack_overlay() -> TileOverlay:
	return _attack_overlay


## The overlay of the enemies whose range is toggled on.
func get_enemy_range_overlay() -> TileOverlay:
	return _enemy_range_overlay


## The walk drawn to the hovered tile.
func get_path_preview() -> PathPreview:
	return _path_preview


## The tile cursor.
func get_cursor() -> TileCursor:
	return _cursor


## The tile under [param board_position], a point in the board's space; it may be off the map.
## [constant CombatFact.NO_TILE] before [method bind].
func tile_at(board_position: Vector2) -> Vector2i:
	if _terrain == null:
		return CombatFact.NO_TILE
	return _terrain.local_to_map(_terrain.to_local(to_global(board_position)))


## The centre of [param tile] in the board's space.
func tile_to_position(tile: Vector2i) -> Vector2:
	if _terrain == null:
		return Vector2.ZERO
	return to_local(_terrain.to_global(_terrain.map_to_local(tile)))


## The map's area in the board's space; empty before [method bind].
func map_rect() -> Rect2:
	if _session == null or _terrain == null:
		return Rect2()
	var tiles: Rect2i = _session.layout.get_rect()
	var size: Vector2 = _tile_size()
	return Rect2(tile_to_position(tiles.position) - size * 0.5, Vector2(tiles.size) * size)


## How the board differs from the session's state, one line per difference: a unit with no token
## or a token with no unit, a token on the wrong tile or position, or showing the wrong HP. Empty
## when they agree. For tests and debugging; meaningful once [method is_settled].
func mismatches() -> PackedStringArray:
	var found: PackedStringArray = []
	if _session == null:
		return found
	var state: CombatState = _session.state
	for unit_id: String in state.unit_ids():
		var token: UnitToken = token_of(unit_id)
		if token == null:
			found.append("%s has no token" % [unit_id])
			continue
		var tile: Vector2i = state.tile_of(unit_id)
		if token.tile != tile or not token.position.is_equal_approx(tile_to_position(tile)):
			found.append("%s shown at %s, is at %s" % [unit_id, token.tile, tile])
		if token.hp != state.get_hp(unit_id):
			found.append("%s shows %d HP, has %d" % [unit_id, token.hp, state.get_hp(unit_id)])
	for unit_id: String in _tokens:
		if not state.has_unit(unit_id):
			found.append("%s has a token but is not on the map" % [unit_id])
	return found


# Drops every token, number and animation of a previous bind.
func _clear_board() -> void:
	for tween: Tween in _holding + _cosmetic:
		if tween.is_valid():
			tween.kill()
	_holding.clear()
	_cosmetic.clear()
	_walks.clear()
	_tokens.clear()
	for layer: Node2D in [_token_layer, _number_layer]:
		for child: Node in layer.get_children():
			layer.remove_child(child)
			child.queue_free()


# The map scene for terrain, under MapHolder; only its terrain layer shows unless show_markers.
func _build_map(definition: CombatMapDefinition) -> void:
	for child: Node in _map_holder.get_children():
		_map_holder.remove_child(child)
		child.queue_free()
	_terrain = null
	if definition.scene == null:
		push_error("BattleView: map %s has no scene" % [definition.id])
		return
	var map_root: Node = definition.scene.instantiate()
	_map_holder.add_child(map_root)
	_terrain = map_root.get_node_or_null(NodePath(MapLoader.TERRAIN_LAYER)) as TileMapLayer
	if _terrain == null:
		push_error("BattleView: map %s has no %s layer" % [definition.id, MapLoader.TERRAIN_LAYER])
		return
	if not show_markers:
		for child: Node in map_root.get_children():
			var item: CanvasItem = child as CanvasItem
			if item != null and child != _terrain:
				item.visible = false
	var origin: Vector2 = tile_to_position(Vector2i.ZERO) - _tile_size() * 0.5
	_darkness.tile_size = _tile_size()
	_darkness.origin = origin
	for overlay: TileOverlay in [_move_overlay, _attack_overlay, _enemy_range_overlay]:
		overlay.tile_size = _tile_size()
		overlay.origin = origin
	_cursor.tile_size = _tile_size()


func _tile_size() -> Vector2:
	if _terrain == null or _terrain.tile_set == null:
		return Vector2(32.0, 32.0)
	return Vector2(_terrain.tile_set.tile_size)


func _place_token(view: BoardViewModel.UnitView) -> void:
	if token_scene == null:
		push_error("BattleView: no token scene set")
		return
	var token: UnitToken = token_scene.instantiate()
	_token_layer.add_child(token)
	token.show_unit(view)
	token.position = tile_to_position(view.tile)
	_tokens[view.id] = token


func _connect_bus(bus: CombatBus) -> void:
	bus.unit.moved.connect(_on_unit_moved)
	bus.unit.spawned.connect(_on_unit_spawned)
	bus.unit.defeated.connect(_on_unit_defeated)
	bus.unit.healed.connect(_on_unit_healed)
	bus.unit.darkness_damage_taken.connect(_on_unit_darkness_damage_taken)
	bus.action.damage_taken.connect(_on_action_damage_taken)
	bus.world.darkness_advanced.connect(_on_world_darkness_advanced)


func _disconnect_bus(bus: CombatBus) -> void:
	var links: Array[Array] = [
		[bus.unit.moved, _on_unit_moved],
		[bus.unit.spawned, _on_unit_spawned],
		[bus.unit.defeated, _on_unit_defeated],
		[bus.unit.healed, _on_unit_healed],
		[bus.unit.darkness_damage_taken, _on_unit_darkness_damage_taken],
		[bus.action.damage_taken, _on_action_damage_taken],
		[bus.world.darkness_advanced, _on_world_darkness_advanced],
	]
	for link: Array in links:
		var played: Signal = link[0]
		var handler: Callable = link[1]
		if played.is_connected(handler):
			played.disconnect(handler)


# FactPlayback's duration hook. The bus plays a fact before playback asks for its wait, so the
# handler that just animated it has recorded the wait; any other fact takes no time.
func _duration_of(fact: CombatFact) -> float:
	return _last_duration if fact == _last_fact else 0.0


func _hold_for(fact: CombatFact, seconds: float) -> void:
	_last_fact = fact
	_last_duration = seconds


func _step_tweens(tweens: Array[Tween], step: float) -> void:
	var index: int = 0
	while index < tweens.size():
		var tween: Tween = tweens[index]
		if tween.is_valid() and tween.custom_step(step):
			index += 1
		else:
			tweens.remove_at(index)


# Steps the skip's fade by delta seconds of real time; see the skip block above.
func _step_skip(delta: float) -> void:
	if _skip_tween == null:
		return
	# Tween.custom_step() reports a tween finished only on the step after the one that ends it, so
	# the fade's own time decides when it is done.
	if _skip_tween.is_valid():
		_skip_tween.custom_step(delta)
	_skip_left -= delta
	if _skip_left > 0.0:
		return
	if not _is_skip_clearing:
		_flush_playback()
		_skip_tween = _skip_fade.fade_in()
		_skip_left = _skip_fade.fade_in_time
		_is_skip_clearing = true
		return
	_skip_tween = null
	_is_skip_clearing = false
	_skip_fade.clear()
	if _skip_stopped:
		_skip_stopped = false
		_session.playback.resume()


# Plays every queued fact now with its wait skipped, stopping before a fact the pause hook marks,
# then finishes every animation those facts started.
func _flush_playback() -> void:
	var playback: FactPlayback = _session.playback
	var was_paused: bool = playback.is_paused
	playback.is_fast_forward = true
	playback.play_all()
	playback.is_fast_forward = false
	_skip_stopped = playback.is_paused and not was_paused
	_step_tweens(_holding, INF)
	_step_tweens(_cosmetic, INF)


# Ends a skip under way at once: the screen clears, and playback resumes if the skip paused it.
func _end_skip() -> void:
	if _skip_tween != null and _skip_tween.is_valid():
		_skip_tween.kill()
	_skip_tween = null
	_is_skip_clearing = false
	_skip_fade.clear()
	if _skip_stopped and _session != null:
		_session.playback.resume()
	_skip_stopped = false


# The shortest walk from `from` to `to` over the grid's move costs for the mover's movement type,
# avoiding tiles shown holding the other side's units. Facts carry only where a walk stopped, so
# this is a picture of the walk, not the walk the rules checked; with none found, a straight line.
# ASSUMPTION: the walked path isn't in UNIT_MOVED (combat_fact.gd); a cheapest path is shown.
func _display_path(unit_id: String, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var straight: Array[Vector2i] = [from, to]
	var state: CombatState = _session.state
	var mover: CombatUnitState = state.unit(unit_id)
	if mover == null or from == to:
		return straight
	var blocked: Dictionary[Vector2i, bool] = {}
	for other_id: String in _tokens:
		if state.side_of(other_id) != mover.side:
			blocked[_tokens[other_id].tile] = true
	# Dijkstra over a map of tens of tiles: a linear scan for the cheapest open tile is enough.
	var cost: Dictionary[Vector2i, int] = {from: 0}
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var best: int = 0
		for i: int in range(1, open.size()):
			if cost[open[i]] < cost[open[best]]:
				best = i
		var at: Vector2i = open[best]
		open.remove_at(best)
		if at == to:
			break
		for next: Vector2i in state.grid.neighbors(at):
			var step_cost: int = state.grid.move_cost(next, mover.movement_type)
			if step_cost <= 0 or (blocked.has(next) and next != to):
				continue
			var total: int = cost[at] + step_cost
			if cost.has(next) and cost[next] <= total:
				continue
			cost[next] = total
			came_from[next] = at
			open.append(next)
	if not came_from.has(to):
		return straight
	var path: Array[Vector2i] = [to]
	while path[0] != from:
		path.push_front(came_from[path[0]])
	return path


# Walks token along path (or slides it, for a forced move), after a pan to it when an enemy moves.
# A walk still playing ends first, so two never pull one token. Returns the seconds playback waits
# at speed 1.0.
func _animate_move(token: UnitToken, path: Array[Vector2i], is_enemy: bool) -> float:
	var previous: Tween = _walks.get(token.unit_id, null)
	if previous != null and previous.is_valid():
		previous.custom_step(INF)
	var seconds: float = 0.0
	if is_enemy:
		var pan: Tween = _camera.pan_to(token.position)
		if pan != null:
			_holding.append(pan)
			seconds += _camera.pan_time
	var walk: Tween = token.create_tween()
	walk.pause()
	if seconds > 0.0:
		walk.tween_interval(seconds)
	var at: Vector2 = token.position
	for i: int in range(1, path.size()):
		var next: Vector2 = tile_to_position(path[i])
		var step_time: float = at.distance_to(next) / move_speed
		walk.tween_property(token, ^"position", next, step_time)
		seconds += step_time
		at = next
	_holding.append(walk)
	_walks[token.unit_id] = walk
	if is_enemy:
		seconds += ai_action_pause
	return seconds


func _show_number(token: UnitToken, amount: int, is_heal: bool) -> void:
	if damage_number_scene == null or amount <= 0:
		return
	var number: DamageNumber = damage_number_scene.instantiate()
	_number_layer.add_child(number)
	number.position = token.position
	_cosmetic.append(number.play(amount, is_heal))


func _max_hp_of(unit_id: String, fallback: int) -> int:
	if not _session.state.has_unit(unit_id):
		return fallback
	return _session.stats(unit_id).get_int(CombatValue.Key.HP)


func _on_unit_moved(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null or fact.tile == CombatFact.NO_TILE:
		return
	var from: Vector2i = token.tile
	token.tile = fact.tile
	# A forced move (shove, slide, swap, passage) has no walk of its own: it slides straight.
	var path: Array[Vector2i] = [from, fact.tile]
	if fact.amount > 0:
		path = _display_path(fact.actor_id, from, fact.tile)
	var is_enemy: bool = _session.state.side_of(fact.actor_id) == CombatFact.CombatSide.ENEMY
	_hold_for(fact, _animate_move(token, path, is_enemy))


func _on_unit_spawned(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token != null:
		token.tile = fact.tile
		token.position = tile_to_position(fact.tile)
		return
	var view: BoardViewModel.UnitView = BoardViewModel.unit_view(_session, fact.actor_id)
	view.tile = fact.tile
	_place_token(view)


func _on_unit_defeated(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	_tokens.erase(fact.actor_id)
	_walks.erase(fact.actor_id)
	if defeat_time <= 0.0:
		token.queue_free()
		return
	var fade: Tween = token.create_tween()
	fade.pause()
	fade.tween_property(token, ^"modulate:a", 0.0, defeat_time)
	fade.tween_callback(token.queue_free)
	_holding.append(fade)
	_hold_for(fact, defeat_time)


func _on_unit_healed(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_hp(token.hp + fact.hp_amount, _max_hp_of(fact.actor_id, token.max_hp))
	_show_number(token, fact.amount, true)
	_hold_for(fact, number_hold)


# Darkness damage skips Block and every stage (the darkness plan), so all of it reaches HP.
func _on_unit_darkness_damage_taken(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_hp(token.hp - fact.amount, _max_hp_of(fact.actor_id, token.max_hp))
	_show_number(token, fact.amount, false)
	_hold_for(fact, number_hold)


func _on_action_damage_taken(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_hp(token.hp - fact.hp_amount, _max_hp_of(fact.actor_id, token.max_hp))
	_show_number(token, fact.amount, false)
	_hold_for(fact, number_hold)


# One fact per tile that deepens, its amount the new layer (darkness plan, question 4); a wave's
# release has no tile and draws nothing by itself.
func _on_world_darkness_advanced(fact: CombatFact) -> void:
	if fact.tile == CombatFact.NO_TILE:
		return
	var layer: int = fact.amount
	if layer <= WhileLayerCondition.Layer.DRY:
		layer = _session.state.map.darkness.layer_at(fact.tile)
	_darkness.show_layer(fact.tile, layer)
