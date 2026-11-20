# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_view.gd
# Author:
# Created:  November 4, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleView
extends Node2D
## The battle board, drawn from one [CombatSession]: terrain, [MapObjectMark]s, a [UnitToken] per
## unit with its [UnitInfo] on the [UnitInfoLayer], the [DarknessOverlay], turn input's overlays,
## path, marks and cursor, the objective's tiles and [LeaderMark]s, and the [CameraRig] framing
## the map in [member map_area].[br]
## [method bind] builds it from state ([BoardViewModel]), skipping facts already queued; then
## facts reach it only through [member CombatSession.playback], which [method advance] steps each
## frame. Each fact plays its animation as it plays, never before: walks, pop-ups
## ([DamageNumber]), the [StrikeFeedback] look of each strike result, fades, values on tokens and
## the darkness. A fact's wait is its beat ([member strike_hold] and the rest of Pacing); the board
## steps its own tweens with the same time, so fast-forward and [method skip_playback] apply.[br]
## [b]Reading only:[/b] it changes no state and submits no command ([BattleController] does).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Playback ran out of facts and every animation that holds it has ended. Emitted once per stretch
## of playback, after the last fact's animation.
signal settled()

## A pop-up was placed on [param unit_id]'s token: a damage or heal number, a Miss or a Critical
## ([param style]), once per fact it shows, in every playback mode (a skip finishes it at once).
signal number_shown(unit_id: String, style: DamageNumber.Style)

## A strike result's look ([StrikeFeedback]) played on [param unit_id]'s token as its fact played:
## once per result, in every playback mode, even where the look does nothing.
signal feedback_played(unit_id: String, kind: StrikeFeedback.Kind)

## The walk [method stage_walk] started reached its last tile: [param unit_id]'s token stands
## there. Not emitted for a walk [method unstage_walk] or a bind cut short.
signal staged_walk_finished(unit_id: String)

## Turn [param turn]'s darkness phase began to play: the first fact after the enemy Phase End that
## hurts a unit, deepens or releases darkness, or erodes a breakable. Once per phase; never for a
## phase where nothing happens. A skip plays it too.
signal darkness_phase_started(turn: int)

# Facts whose actor took its action, which ends its turn; an attack's is the attacker's
# BEFORE_COMBAT and a swap's WEAPON_SWAPPED (see _on_fact_played). Mirrors CombatState.follow()'s
# _ACTION_KINDS in combat_state.gd: change both together, or tokens gray at the wrong time.
const _ACTION_KINDS: Array[CombatFact.Kind] = [
	CombatFact.Kind.ITEM_USED,
	CombatFact.Kind.SHOVED_A_UNIT,
	CombatFact.Kind.USED_STAFF_ON_ALLY,
	CombatFact.Kind.UNIT_WAITED,
	CombatFact.Kind.OBJECT_USED,
	CombatFact.Kind.WEAPON_SWAPPED,
]

@export_group("Scenes")

## The token placed for each unit.[br]
## [b]Unset:[/b] no token is drawn and an error is reported at [method bind].
@export var token_scene: PackedScene = null

## The pop-up shown for each damage, heal, Miss, Critical and Block absorbed ([DamageNumber]), on
## the [UnitInfoLayer].[br]
## [b]Unset:[/b] no numbers are shown.
@export var damage_number_scene: PackedScene = null

## The outline placed around each valid target while an action is aimed ([TargetMark]).[br]
## [b]Unset:[/b] no target is outlined; the cursor still shows the current one.
@export var target_mark_scene: PackedScene = null

## The outline placed on each enemy the objective marks, Defeat the Leader's or the Boss's
## ([LeaderMark]), as a child of its token.[br]
## [b]Unset:[/b] no enemy is outlined; the objective panel still names them.
@export var leader_mark_scene: PackedScene = null

## The mark placed on each map object that isn't a token: doors, levers, chests, searchables,
## passages and braziers ([MapObjectMark]), under the tokens.[br]
## [b]Unset:[/b] no object is drawn; the tile panel still names them.
@export var object_mark_scene: PackedScene = null

## Whether the map scene's marker layers and marker nodes (deployment tiles, enemy slots) show.
## Off for play; on to check a map's authoring. Map objects draw as marks either way.
@export var show_markers: bool = false

@export_group("Framing")

## The HUD's free space the camera fits the map into ([member CameraRig.screen_area]): a
## [Control] on a [CanvasLayer] with no offset or scale, whose rect is in screen pixels. The map
## is framed again whenever it resizes. Edit its offsets in the HUD scene to move the map.[br]
## [b]Unset:[/b] the map fits the whole screen less [member CameraRig.frame_margin].
@export var map_area: Control = null:
	set(value):
		if is_instance_valid(map_area) and map_area.resized.is_connected(_on_map_area_resized):
			map_area.resized.disconnect(_on_map_area_resized)
		map_area = value
		if is_instance_valid(map_area):
			map_area.resized.connect(_on_map_area_resized)
		if _session != null:
			_frame_map()

@export_group("Pacing")

## How fast a unit walks along its path at playback speed 1.0 (Godot_FE
## [code]CController.gd[/code], [code]MOVEMENT_SPEED[/code] 96 × 5, with 32 px tiles).[br]
## [b]Units:[/b] pixels per second.
@export_range(16.0, 4000.0, 1.0) var move_speed: float = 480.0

## The pause after an enemy's move, before its action (Godot_FE [code]CController.gd[/code],
## [code]ai_perform_selected_action[/code]).[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] no pause.
@export_range(0.0, 2.0, 0.01) var ai_action_pause: float = 0.1

## How long playback waits after a strike that hits or crits, before the next fact: Godot_FE
## waited out each strike's number (its [code]DamageNumbers[/code], 1.0 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] strikes don't hold playback.
@export_range(0.0, 3.0, 0.05) var strike_hold: float = 1.0

## How long playback waits after a strike that misses or deals 0 (Godot_FE's Miss and No Damage
## text, 0.75 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] they don't hold playback.
@export_range(0.0, 3.0, 0.05) var miss_hold: float = 0.75

## How long playback waits on a number that isn't a strike's: a heal, darkness damage, or damage
## with no roll (splash, bump, spike); the number stays for its own lifetime.[br]
## [b]Units:[/b] seconds at playback speed 1.0.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.0, 2.0, 0.01) var number_hold: float = 0.35

## How long a defeated unit takes to fade out; playback waits for it.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] it vanishes at once.
# ASSUMPTION: no basis in Godot_FE or the vision; for M1's tuning pass (plan, question 5).
@export_range(0.0, 3.0, 0.01) var defeat_time: float = 0.4

## How long playback waits on each tile the darkness deepens, so a spread plays tile by tile; a
## wave's release and a breakable's contact take no time.[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] a whole spread shows at once.
@export_range(0.0, 1.0, 0.01) var darkness_tile_hold: float = 0.08

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

@export_group("Critical hits")

## The colour a critically hit unit flashes toward (the segmented-bar addon's white flash).
@export var crit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## How long a critically hit unit's flash takes to fade (the addon's HP example, 0.1 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. [b]0.0:[/b] no flash.
@export_range(0.0, 1.0, 0.01) var crit_flash_time: float = 0.1

# ASSUMPTION: no basis (Godot_FE never shook the screen); a firm jolt, for the M2 exit playtest.
## How far the screen shakes on a critical hit, dying away over [member crit_shake_time].[br]
## [b]Units:[/b] screen pixels. [b]0.0:[/b] no shake.
@export_range(0.0, 32.0, 0.5) var crit_shake_strength: float = 4.0

## How long a critical hit's screen shake lasts (the addon's shake example, 0.3 s).[br]
## [b]Units:[/b] seconds at playback speed 1.0. Unused while [member crit_shake_strength] is 0.
@export_range(0.0, 2.0, 0.01) var crit_shake_time: float = 0.3

@export_group("")

# The session drawn; null before bind() and after unbind().
var _session: CombatSession = null

# The map scene's terrain layer, which tile positions come from.
var _terrain: TileMapLayer = null

# The token of each unit on the board, by unit id.
var _tokens: Dictionary[String, UnitToken] = {}

# Each unit's timed Block bans as played (BoardViewModel.is_block_ban), by unit id: two Haunted
# copies can pick one unit, so its mark goes only when the last ban expires. Absent: none.
var _block_bans: Dictionary[String, int] = {}

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

# The exchange whose two BEFORE_COMBAT facts are open, "attacker>defender", which tells the
# attacker's from the defender's as CombatState.follow() does; empty between exchanges.
var _open_exchange: String = ""

# Units struck by a crit whose Damage taken is still to come, which then shows as the Critical
# pop-up; cleared at every Attack made.
var _crit_shown: Dictionary[String, bool] = {}

# Each struck unit's hit damage from its Hit taken, before Block and before HP runs out, which its
# Damage taken (that carries only what Block took and what HP lost) reads to show the overkill;
# cleared at every Attack made.
var _hit_damage: Dictionary[String, int] = {}

# A strike's beat, moved from its Damage taken to the end of its tail: the struck unit's Stance
# loss and Exposed follow its damage, and a fact's wait plays after it, so the beat waits for
# them (_defer_beat()). _beat_next is the tail fact expected next; _beat_fact the fact that set
# it. _beat_unit is empty when no beat waits.
var _beat_unit: String = ""
var _beat_time: float = 0.0
var _beat_next: CombatFact.Kind = CombatFact.Kind.STANCE_CHANGED
var _beat_fact: CombatFact = null

# The side whose phase it is, as played: spent units gray only on this side.
var _phase_side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

# The darkness phase as played: _played_turn is the turn of the last Phase Start played (the
# state's at bind). Between an enemy Phase End and the next Phase Start, _is_darkness_window;
# _is_darkness_shown once that window's first darkness change has emitted darkness_phase_started.
var _played_turn: int = 0
var _is_darkness_window: bool = false
var _is_darkness_shown: bool = false

# Whether the unit infos must be put over their tokens again at the next advance(), with no tween
# moving anything: a token placed or the map framed.
var _is_info_dirty: bool = false

# --- The staged walk (stage_walk(); local, never in the session) ----------------------------
# None:     _staged_id is empty. Every token stands on its tile.
# Walking:  _staged_walk walks _staged_id's token from its tile to _staged_tile, stepped by
#           advance() as playback's walks are, but outside _holding: is_settled() stays true and
#           settled isn't emitted, as no fact plays. Ends with staged_walk_finished.
# Standing: _staged_walk is null; the token stands on _staged_tile while its tile is the unit's.
# unstage_walk() snaps it back at once from either. The unit's own UNIT_MOVED to _staged_tile
# ends it with no second walk (_on_unit_moved); any other move of it snaps it back first.
var _staged_id: String = ""
var _staged_tile: Vector2i = CombatFact.NO_TILE
var _staged_walk: Tween = null

# Seconds left of _staged_walk at speed 1.0: Tween.custom_step() reports a tween finished only on
# the step after the one that ends it (see _step_skip()).
var _staged_left: float = 0.0

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

# The leader marks shown, by the marked enemy's id; each is a child of that enemy's token.
var _leader_marks: Dictionary[String, LeaderMark] = {}

# The mark of each map object drawn (BoardViewModel.is_drawn), by object id.
var _object_marks: Dictionary[String, MapObjectMark] = {}

@onready var _map_holder: Node2D = %MapHolder
@onready var _darkness: DarknessOverlay = %DarknessOverlay
@onready var _object_layer: Node2D = %Objects
@onready var _seize_overlay: TileOverlay = %SeizeOverlay
@onready var _defend_overlay: TileOverlay = %DefendOverlay
@onready var _point_overlay: TileOverlay = %ReinforcementOverlay
@onready var _token_layer: Node2D = %Tokens
@onready var _camera: CameraRig = %CameraRig
@onready var _move_overlay: TileOverlay = %MoveOverlay
@onready var _attack_overlay: TileOverlay = %AttackOverlay
@onready var _enemy_range_overlay: TileOverlay = %EnemyRangeOverlay
@onready var _danger_overlay: TileOverlay = %DangerOverlay
@onready var _support_overlay: TileOverlay = %SupportOverlay
@onready var _enemy_support_overlay: TileOverlay = %EnemySupportOverlay
@onready var _danger_support_overlay: TileOverlay = %DangerSupportOverlay
@onready var _target_mark_layer: Node2D = %TargetMarks
@onready var _path_preview: PathPreview = %PathPreview
@onready var _cursor: TileCursor = %TileCursor
@onready var _skip_fade: SkipFade = %SkipFade
@onready var _info_layer: UnitInfoLayer = %UnitInfoLayer
@onready var _feedback: StrikeFeedback = %StrikeFeedback


func _ready() -> void:
	_camera.framed.connect(_on_camera_rig_framed)


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
	_phase_side = session.state.phase_side
	_played_turn = session.state.turn
	_is_darkness_window = false
	_is_darkness_shown = false
	_build_map(session.setup.map)
	var model: BoardViewModel = BoardViewModel.build(session)
	for object_view: BoardViewModel.ObjectView in model.objects:
		_place_object_mark(object_view)
	for view: BoardViewModel.UnitView in model.units:
		_place_token(view)
	_darkness.show_layers(model.darkness)
	_frame_map()
	_session.playback.speed = playback_speed
	_session.playback.duration_hook = _duration_of
	_connect_bus(_session.bus)
	_is_settled = true
	_open_exchange = ""
	_crit_shown.clear()
	_hit_damage.clear()
	_release_beat(null)
	_follow_info()


## Stops drawing the session: its bus is let go and its playback keeps no hook of the board's.
## A skip under way ends with the screen cleared, and fast-forward is let go; the board's other
## nodes stay as they are. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	_end_skip()
	unstage_walk()
	_is_fast_forward = false
	_disconnect_bus(_session.bus)
	if _session.playback.duration_hook == _duration_of:
		_session.playback.duration_hook = Callable()
	_session = null


## Steps playback and every animation, a staged walk included, by [param delta] seconds of real
## time ([member fast_forward_speed] times that while fast-forward is held), steps a skip's fade by
## [param delta] itself, puts the unit infos over their tokens if anything can have moved, and
## emits [signal settled] when all have run out. Called each frame by [method _process]; tests
## call it directly.
func advance(delta: float) -> void:
	if _session == null:
		return
	# Facts queued since the last step count as busy, so a batch that plays out within this step
	# still ends with settled.
	if not is_settled():
		_is_settled = false
	# Only a tween (a walk, a pan, a shake, a fade) or a skip's flush moves a token or the camera.
	var can_move: bool = (
			not _holding.is_empty() or not _cosmetic.is_empty() or _skip_tween != null
			or _staged_walk != null or _session.playback.pending() > 0
	)
	var real: float = maxf(delta, 0.0)
	# Scaling the time given to playback, not FactPlayback.speed, leaves the game speed (a lobby
	# setting, the same for every peer) untouched.
	var scaled: float = real * (fast_forward_speed if _is_fast_forward else 1.0)
	_session.playback.advance(scaled)
	# A strike's beat still waiting when the queue runs out has no tail left to follow, so it is
	# dropped rather than given to the next batch's first fact.
	if not _beat_unit.is_empty() and _session.playback.pending() == 0:
		_release_beat(null)
	var step: float = scaled * _session.playback.speed
	_step_tweens(_holding, step)
	_step_tweens(_cosmetic, step)
	var arrived: String = _step_staged_walk(step)
	_step_skip(real)
	if can_move or _is_info_dirty:
		_follow_info()
	if not arrived.is_empty():
		staged_walk_finished.emit(arrived)
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


## How many times faster than real time the board's animations run now: the game speed, times
## [member fast_forward_speed] while fast-forward is held. Other timed pieces (the phase banner)
## read it to keep pace. 1.0 before [method bind].
func time_scale() -> float:
	if _session == null:
		return 1.0
	var speed: float = _session.playback.speed if _session.playback.speed > 0.0 else 1.0
	return speed * (fast_forward_speed if _is_fast_forward else 1.0)


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


## The mark of map object [param object_id]; null when it has none (a breakable, or none set).
func object_mark_of(object_id: String) -> MapObjectMark:
	return _object_marks.get(object_id, null)


## The ids of every map object with a mark, sorted.
func object_mark_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray(_object_marks.keys())
	ids.sort()
	return ids


## The darkness overlay, for reading what it draws.
func get_darkness() -> DarknessOverlay:
	return _darkness


## The overlay of the selected unit's move tiles (and the swap partners' tiles).
func get_move_overlay() -> TileOverlay:
	return _move_overlay


## The overlay of the selected unit's attack tiles, and of the targets of an action that isn't
## support (Attack, Shove, Use, Rune).
func get_attack_overlay() -> TileOverlay:
	return _attack_overlay


## The overlay of the enemies whose range is toggled on.
func get_enemy_range_overlay() -> TileOverlay:
	return _enemy_range_overlay


## The overlay of the danger zone: every tile an enemy could attack next turn.
func get_danger_overlay() -> TileOverlay:
	return _danger_overlay


## The purple overlay of the selected unit's support tiles (Block and heal staves), and of a
## support action's targets.
func get_support_overlay() -> TileOverlay:
	return _support_overlay


## The purple overlay of the support tiles of the enemies whose range is toggled on.
func get_enemy_support_overlay() -> TileOverlay:
	return _enemy_support_overlay


## The purple overlay of the danger zone's support tiles: every tile an enemy could heal or
## Block next turn that none could attack.
func get_danger_support_overlay() -> TileOverlay:
	return _danger_support_overlay


## Outlines each target [param marks] lists, in place of those outlined
## ([member target_mark_scene] instances, one per mark).
func show_target_marks(marks: Array[TargetMark.Spec]) -> void:
	clear_target_marks()
	if target_mark_scene == null:
		return
	for spec: TargetMark.Spec in marks:
		var mark: TargetMark = target_mark_scene.instantiate()
		_target_mark_layer.add_child(mark)
		mark.show_mark(spec)
		mark.position = tile_to_position(spec.tile)


## Draws [param view]'s objective on the board: its seize and defend tiles, its open
## reinforcement points, and a [LeaderMark] on each marked enemy still on the map, removing the
## marks of enemies no longer marked. Every objective's tiles are drawn whatever the objective, as
## a map only authors the markers its objective uses. Null clears them all. Reads the view only.
func show_objective(view: HudViewModel.ObjectiveView) -> void:
	var empty: Array[Vector2i] = []
	_seize_overlay.show_tiles(empty if view == null else view.seize_tiles)
	_defend_overlay.show_tiles(empty if view == null else view.defend_tiles)
	_point_overlay.show_tiles(empty if view == null else view.open_point_tiles())
	var marked: PackedStringArray = [] if view == null else view.marked_left_ids
	for unit_id: String in _leader_marks.keys():
		var shown: LeaderMark = _leader_marks[unit_id]
		var token: UnitToken = token_of(unit_id)
		# A token that faded out took its mark with it, so only a live one keeps its mark.
		if marked.has(unit_id) and is_instance_valid(shown) and shown.get_parent() == token:
			continue
		_leader_marks.erase(unit_id)
		if is_instance_valid(shown):
			shown.queue_free()
	if leader_mark_scene == null:
		return
	for unit_id: String in marked:
		var token: UnitToken = token_of(unit_id)
		if token == null or _leader_marks.has(unit_id):
			continue
		var mark: LeaderMark = leader_mark_scene.instantiate()
		token.add_child(mark)
		_leader_marks[unit_id] = mark


## The units outlined as marked enemies now, for tests.
func get_leader_marked() -> PackedStringArray:
	var shown: PackedStringArray = []
	for unit_id: String in _leader_marks:
		if is_instance_valid(_leader_marks[unit_id]):
			shown.append(unit_id)
	return shown


## The seize tiles' overlay.
func get_seize_overlay() -> TileOverlay:
	return _seize_overlay


## The defend tiles' overlay.
func get_defend_overlay() -> TileOverlay:
	return _defend_overlay


## The open reinforcement points' overlay.
func get_point_overlay() -> TileOverlay:
	return _point_overlay


## Shows the range-tracked icon on the tokens of [param unit_ids], the units the enemy range
## toggle tracks, and on no other token.
func show_range_tracked(unit_ids: PackedStringArray) -> void:
	for unit_id: String in _tokens:
		_tokens[unit_id].show_range_tracked(unit_ids.has(unit_id))


## While [param model]'s forecast is open, flashes each unit it changes
## ([member ForecastViewModel.flashes]): its HP bar from its HP to its HP after, and its Stance
## pips from its Stance down to its Stance after (question 34 (1)). Every flash restarts, so the
## bars shown pulse together. Units it leaves as they are, and every unit when [param model] is
## null, flash nothing. Reads the model only.
func show_forecast_preview(model: ForecastViewModel) -> void:
	for unit_id: String in _tokens:
		var token: UnitToken = _tokens[unit_id]
		var flash: ForecastViewModel.Flash = null if model == null else model.flash_of(unit_id)
		if flash != null and flash.changes_hp():
			token.show_hp_preview(flash.hp_after)
		else:
			token.clear_hp_preview()
		if flash != null and flash.breaks_stance():
			token.show_stance_preview(flash.stance_after)
		else:
			token.clear_stance_preview()


## Walks [param unit_id]'s token along [param path] (its tiles in order from the unit's own, as
## [method TurnInputModel.path_to] gives the command's) at [member move_speed], fast-forward and
## [member playback_speed] applying, then leaves it standing on the last tile, emitting
## [signal staged_walk_finished] on arrival (question 34 (3)). Local only: no state changes, and
## [member UnitToken.tile] stays the unit's tile. A walk already staged is snapped back first.
## Returns false, staging nothing, with no token or a path of fewer than two tiles.
func stage_walk(unit_id: String, path: Array[Vector2i]) -> bool:
	unstage_walk()
	var token: UnitToken = token_of(unit_id)
	if token == null or path.size() < 2:
		return false
	var walk: Tween = token.create_tween()
	walk.pause()
	var at: Vector2 = token.position
	var seconds: float = 0.0
	for i: int in range(1, path.size()):
		var next: Vector2 = tile_to_position(path[i])
		var step_time: float = at.distance_to(next) / move_speed
		walk.tween_property(token, ^"position", next, step_time)
		seconds += step_time
		at = next
	_staged_id = unit_id
	_staged_tile = path[path.size() - 1]
	_staged_walk = walk
	_staged_left = seconds
	return true


## Ends a staged walk at once, walking or standing: the token snaps back to its unit's tile. Does
## nothing when none is staged.
func unstage_walk() -> void:
	if _staged_id.is_empty():
		return
	var token: UnitToken = token_of(_staged_id)
	_end_staged_walk()
	if token != null:
		token.position = tile_to_position(token.tile)
	if _session != null:
		_follow_info()


## The unit whose walk is staged, walking or standing; empty for none.
func get_staged_unit() -> String:
	return _staged_id


## The tile the staged walk ends on; [constant CombatFact.NO_TILE] with none.
func get_staged_tile() -> Vector2i:
	return _staged_tile


## Whether a staged walk is still walking (not yet at its tile).
func is_staged_walking() -> bool:
	return _staged_walk != null


## The layer of the units' bars, numbers and icons.
func get_info_layer() -> UnitInfoLayer:
	return _info_layer


## The camera rig, for reading where it looks.
func get_camera_rig() -> CameraRig:
	return _camera


## Outlines no target.
func clear_target_marks() -> void:
	for child: Node in _target_mark_layer.get_children():
		_target_mark_layer.remove_child(child)
		child.queue_free()


## The target outlines shown, in the order given.
func get_target_marks() -> Array[TargetMark]:
	var marks: Array[TargetMark] = []
	for child: Node in _target_mark_layer.get_children():
		var mark: TargetMark = child as TargetMark
		if mark != null:
			marks.append(mark)
	return marks


## Pans the camera to [param tile], kept inside the map ([method CameraRig.pan_to]). The pan is
## cosmetic: playback doesn't wait for it, so input isn't held back. Does nothing before
## [method bind].
func focus_tile(tile: Vector2i) -> void:
	if _session == null:
		return
	var pan: Tween = _camera.pan_to(tile_to_position(tile))
	if pan != null:
		_cosmetic.append(pan)


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
## or a token with no unit, a token on the wrong tile or position, or showing the wrong HP, Stance,
## Block, turn or phase, or its info drawing other HP or Stance than the token holds; a drawn map
## object with no mark, or a mark off its tile or showing another state. Empty when they agree.
## A staged walk's token ([method stage_walk]) is placed right on its staged tile once it stands
## there, and anywhere while it walks; its tile must still be the unit's. For tests and debugging;
## meaningful once [method is_settled].
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
		var shown_at: Vector2i = tile
		if unit_id == _staged_id:
			shown_at = _staged_tile
		var is_placed: bool = token.position.is_equal_approx(tile_to_position(shown_at))
		if unit_id == _staged_id and _staged_walk != null:
			is_placed = true
		if token.tile != tile or not is_placed:
			found.append("%s shown at %s (%s), is at %s" % [
				unit_id, token.tile, token.position, tile,
			])
		if token.hp != state.get_hp(unit_id):
			found.append("%s shows %d HP, has %d" % [unit_id, token.hp, state.get_hp(unit_id)])
		var unit: CombatUnitState = state.unit(unit_id)
		if token.stance != unit.stance:
			found.append("%s shows %d Stance, has %d" % [unit_id, token.stance, unit.stance])
		if token.block != unit.block:
			found.append("%s shows %d Block, has %d" % [unit_id, token.block, unit.block])
		if (
				token.has_acted != unit.has_acted
				or token.is_second_move_pending != unit.is_second_move_pending
		):
			found.append("%s shows acted %s (second move %s), is %s (%s)" % [
				unit_id, token.has_acted, token.is_second_move_pending, unit.has_acted,
				unit.is_second_move_pending,
			])
		if token.is_phase_side != (token.side == state.phase_side):
			found.append("%s shows its side's phase %s, phase is %s's" % [
				unit_id, token.is_phase_side, CombatFact.CombatSide.find_key(state.phase_side),
			])
		found.append_array(_info_mismatches(token))
	for unit_id: String in _tokens:
		if not state.has_unit(unit_id):
			found.append("%s has a token but is not on the map" % [unit_id])
	if object_mark_scene != null:
		found.append_array(_object_mismatches(state))
	return found


# Drops every token, number and animation of a previous bind.
func _clear_board() -> void:
	for tween: Tween in _holding + _cosmetic:
		if tween.is_valid():
			tween.kill()
	_holding.clear()
	_cosmetic.clear()
	_walks.clear()
	_end_staged_walk()
	_tokens.clear()
	_block_bans.clear()
	_leader_marks.clear()
	_object_marks.clear()
	for child: Node in _object_layer.get_children():
		_object_layer.remove_child(child)
		child.queue_free()
	_info_layer.clear()
	clear_target_marks()
	for overlay: TileOverlay in [_seize_overlay, _defend_overlay, _point_overlay]:
		overlay.clear()
	for child: Node in _token_layer.get_children():
		_token_layer.remove_child(child)
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
	var overlays: Array[TileOverlay] = [
		_seize_overlay, _defend_overlay, _point_overlay,
		_danger_overlay, _danger_support_overlay, _enemy_range_overlay, _enemy_support_overlay,
		_move_overlay, _attack_overlay, _support_overlay,
	]
	for overlay: TileOverlay in overlays:
		overlay.tile_size = _tile_size()
		overlay.origin = origin
	_cursor.tile_size = _tile_size()


# Frames the map in map_area's screen rect (empty while it is unset or has no size yet).
func _frame_map() -> void:
	_camera.screen_area = Rect2()
	if is_instance_valid(map_area):
		_camera.screen_area = map_area.get_global_rect()
	_camera.frame(map_rect())


func _tile_size() -> Vector2:
	if _terrain == null or _terrain.tile_set == null:
		return Vector2(32.0, 32.0)
	return Vector2(_terrain.tile_set.tile_size)


func _place_object_mark(view: BoardViewModel.ObjectView) -> void:
	if object_mark_scene == null:
		return
	var mark: MapObjectMark = object_mark_scene.instantiate()
	_object_layer.add_child(mark)
	mark.show_object(view, tile_to_position(view.tile))
	_object_marks[view.id] = mark


# Each drawn object of state with no mark, or a mark off its tile or showing another state.
func _object_mismatches(state: CombatState) -> PackedStringArray:
	var found: PackedStringArray = []
	for view: BoardViewModel.ObjectView in BoardViewModel.objects_of(state):
		var mark: MapObjectMark = object_mark_of(view.id)
		if mark == null or mark.view == null:
			found.append("%s has no mark" % [view.id])
			continue
		var shown: BoardViewModel.ObjectView = mark.view
		if not mark.position.is_equal_approx(tile_to_position(view.tile)):
			found.append("%s's mark is at %s, not on %s" % [view.id, mark.position, view.tile])
		if (
				shown.is_open != view.is_open
				or shown.is_used != view.is_used
				or shown.is_lit != view.is_lit
		):
			found.append("%s's mark shows open %s, used %s, lit %s; is %s, %s, %s" % [
				view.id, shown.is_open, shown.is_used, shown.is_lit,
				view.is_open, view.is_used, view.is_lit,
			])
	return found


func _place_token(view: BoardViewModel.UnitView) -> void:
	if token_scene == null:
		push_error("BattleView: no token scene set")
		return
	var token: UnitToken = token_scene.instantiate()
	_token_layer.add_child(token)
	_info_layer.add_info(view.id, token)
	token.show_unit(view)
	if view.can_gain_block:
		_block_bans.erase(view.id)
	else:
		_block_bans[view.id] = 1
	token.show_phase(view.side == _phase_side)
	token.position = tile_to_position(view.tile)
	_tokens[view.id] = token
	_is_info_dirty = true


func _connect_bus(bus: CombatBus) -> void:
	for link: Array in _bus_links(bus):
		var played: Signal = link[0]
		var handler: Callable = link[1]
		played.connect(handler)


func _disconnect_bus(bus: CombatBus) -> void:
	for link: Array in _bus_links(bus):
		var played: Signal = link[0]
		var handler: Callable = link[1]
		if played.is_connected(handler):
			played.disconnect(handler)


# Each bus signal the board plays, with its handler. fact_played comes after a fact's own signal,
# so a token's turn follows the fact's other effects on it.
func _bus_links(bus: CombatBus) -> Array[Array]:
	var links: Array[Array] = [
		[bus.unit.moved, _on_unit_moved],
		[bus.unit.spawned, _on_unit_spawned],
		[bus.unit.defeated, _on_unit_defeated],
		[bus.unit.healed, _on_unit_healed],
		[bus.unit.darkness_damage_taken, _on_unit_darkness_damage_taken],
		[bus.unit.block_gained, _on_unit_block_gained],
		[bus.unit.block_lost, _on_unit_block_lost],
		[bus.unit.stance_changed, _on_unit_stance_changed],
		[bus.unit.exposed, _on_unit_exposed],
		[bus.unit.block_stance_refreshed, _on_unit_block_stance_refreshed],
		[bus.action.hit_taken, _on_action_hit_taken],
		[bus.action.damage_taken, _on_action_damage_taken],
		[bus.action.missed, _on_action_missed],
		[bus.action.crit_taken, _on_action_crit_taken],
		[bus.effect.modifier_gained, _on_effect_modifier_gained],
		[bus.effect.modifier_expired, _on_effect_modifier_expired],
		[bus.flow.phase_started, _on_flow_phase_started],
		[bus.flow.phase_ended, _on_flow_phase_ended],
		[bus.world.darkness_advanced, _on_world_darkness_advanced],
		[bus.world.object_state_changed, _on_world_object_state_changed],
		[bus.fact_played, _on_fact_played],
	]
	return links


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
	# Waits are skipped, so a strike's beat still waiting has nothing left to hold.
	_release_beat(null)
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


# Steps the staged walk by step seconds at speed 1.0; returns its unit when it arrives in this
# step, else empty.
func _step_staged_walk(step: float) -> String:
	if _staged_walk == null:
		return ""
	if _staged_walk.is_valid():
		_staged_walk.custom_step(step)
	_staged_left -= step
	if _staged_left > 0.0:
		return ""
	if _staged_walk.is_valid():
		_staged_walk.custom_step(INF)
		_staged_walk.kill()
	_staged_walk = null
	var token: UnitToken = token_of(_staged_id)
	if token != null:
		token.position = tile_to_position(_staged_tile)
	return _staged_id


# Drops the staged walk, leaving its token where it is.
func _end_staged_walk() -> void:
	if _staged_walk != null and _staged_walk.is_valid():
		_staged_walk.kill()
	_staged_walk = null
	_staged_id = ""
	_staged_tile = CombatFact.NO_TILE
	_staged_left = 0.0


# A pop-up of style over token on the info layer, stacked on the unit's others (beside the newest
# when is_beside); an amount style only when amount is above 0, a Stance change when it isn't 0.
func _show_number(
		token: UnitToken, amount: int, style: DamageNumber.Style, is_beside: bool = false,
) -> void:
	var is_amount: bool = style in [
		DamageNumber.Style.DAMAGE, DamageNumber.Style.HEAL, DamageNumber.Style.BLOCK,
		DamageNumber.Style.BLOCK_GAINED, DamageNumber.Style.BLOCK_LOST,
	]
	if damage_number_scene == null or (is_amount and amount <= 0):
		return
	if style == DamageNumber.Style.STANCE and amount == 0:
		return
	var number: DamageNumber = damage_number_scene.instantiate()
	_info_layer.add_popup(number, token.global_position, token.unit_id, is_beside)
	_cosmetic.append(number.show_style(style, amount))
	number_shown.emit(token.unit_id, style)


# Plays kind's look on token ([StrikeFeedback]) with the board's other cosmetic tweens.
func _play_feedback(token: UnitToken, kind: StrikeFeedback.Kind) -> void:
	if is_instance_valid(_feedback):
		for tween: Tween in _feedback.play(kind, token, _camera):
			_cosmetic.append(tween)
	feedback_played.emit(token.unit_id, kind)


# A cosmetic tween (a Stance drop's lag, a flash, a shake), stepped with the board's animations.
func _add_cosmetic(tween: Tween) -> void:
	if tween != null:
		_cosmetic.append(tween)


# Puts each unit's info over its token as the camera draws the board now.
func _follow_info() -> void:
	_is_info_dirty = false
	_info_layer.follow(_camera.board_to_screen())


# Each unit's info drawing other HP or Stance than its token holds.
func _info_mismatches(token: UnitToken) -> PackedStringArray:
	var found: PackedStringArray = []
	if not is_instance_valid(token.info):
		found.append("%s has no info" % [token.unit_id])
		return found
	var bar: HpBar = token.info.get_hp_bar()
	if roundi(bar.value) != token.hp or bar.get_text() != bar.text_of(token.hp, token.max_hp):
		found.append("%s's HP bar shows %d (%s), token %d of %d" % [
			token.unit_id, roundi(bar.value), bar.get_text(), token.hp, token.max_hp,
		])
	var pips: StancePips = token.info.get_stance_pips()
	if pips.stance != token.stance or pips.stance_max != token.stance_max:
		found.append("%s's pips show %d of %d, token %d of %d" % [
			token.unit_id, pips.stance, pips.stance_max, token.stance, token.stance_max,
		])
	return found


func _max_hp_of(unit_id: String, fallback: int) -> int:
	if not _session.state.has_unit(unit_id):
		return fallback
	return _session.stats(unit_id).get_int(CombatValue.Key.HP)


# A staged walk to the move's tile already walked it (question 34 (3)): the token takes its new tile
# where it stands, with no second walk and no wait. Any other move of a staged unit snaps it back
# first, so the walk starts from its tile.
func _on_unit_moved(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null or fact.tile == CombatFact.NO_TILE:
		return
	if fact.actor_id == _staged_id:
		var is_walked: bool = fact.amount > 0 and fact.tile == _staged_tile
		if not is_walked:
			unstage_walk()
		else:
			_step_staged_walk(INF)
			_end_staged_walk()
			token.tile = fact.tile
			token.position = tile_to_position(fact.tile)
			_is_info_dirty = true
			_hold_for(fact, 0.0)
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
	if fact.actor_id == _staged_id:
		_end_staged_walk()
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
	_show_number(token, fact.amount, DamageNumber.Style.HEAL)
	_hold_for(fact, number_hold)


# Darkness damage skips Block and every stage (the darkness plan), so all of it reaches HP.
func _on_unit_darkness_damage_taken(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_hp(token.hp - fact.amount, _max_hp_of(fact.actor_id, token.max_hp))
	_show_number(token, fact.amount, DamageNumber.Style.DAMAGE)
	_hold_for(fact, number_hold)


# A struck unit's Hit taken: its amount is the hit's damage before Block and before HP runs out,
# which the Damage taken that follows lacks (see _on_action_damage_taken()). A hit for 0 (fully
# countered) has no Damage taken, so it shows "No damage" here and holds for miss_hold, as
# Godot_FE's No Damage did.
func _on_action_hit_taken(fact: CombatFact) -> void:
	_hit_damage[fact.actor_id] = fact.amount
	var token: UnitToken = token_of(fact.actor_id)
	if token == null or fact.amount > 0:
		return
	_show_number(token, 0, DamageNumber.Style.NO_DAMAGE)
	_play_feedback(token, StrikeFeedback.Kind.NO_DAMAGE)
	_hold_for(fact, miss_hold)


# One rule for every hit's numbers (question 30 (c)): the number is the damage past Block,
# overkill included (the Hit taken's damage less what Block absorbed), as a Critical pop-up after
# a crit and a plain number otherwise; then a small Block number beside it when Block absorbed
# any. A strike holds for strike_hold. Damage with no Hit taken before it (splash, a bump, a
# spike, an effect) shows what reached HP, plays the splash look and holds for number_hold.
func _on_action_damage_taken(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_hp(token.hp - fact.hp_amount, _max_hp_of(fact.actor_id, token.max_hp))
	token.show_block(token.block - fact.block_amount)
	var is_strike: bool = _hit_damage.has(fact.actor_id)
	var is_crit: bool = _crit_shown.has(fact.actor_id)
	# ASSUMPTION: splash facts carry no damage before HP runs out (SplashResolver records only
	# what Block took and HP lost), so a splash's overkill can't show; HP's loss stands for it.
	var past_block: int = fact.hp_amount
	if is_strike:
		past_block = maxi(_hit_damage[fact.actor_id] - fact.block_amount, 0)
	if is_crit:
		# ASSUMPTION: a crit Block took whole still shows "Critical 0", as a crit is news even
		# when Block takes it; a plain hit Block took whole shows only the Block number.
		_show_number(token, past_block, DamageNumber.Style.CRITICAL)
	else:
		_show_number(token, past_block, DamageNumber.Style.DAMAGE)
	var is_beside: bool = is_crit or past_block > 0
	_show_number(token, fact.block_amount, DamageNumber.Style.BLOCK, is_beside)
	if not is_strike:
		_play_feedback(token, StrikeFeedback.Kind.SPLASH)
	elif not is_crit and past_block > 0:
		_play_feedback(token, StrikeFeedback.Kind.HIT)
	if fact.block_amount > 0:
		_play_feedback(token, StrikeFeedback.Kind.BLOCK_ABSORBED)
	_crit_shown.erase(fact.actor_id)
	_hit_damage.erase(fact.actor_id)
	if is_strike:
		_defer_beat(fact, token, strike_hold)
	else:
		_hold_for(fact, number_hold)


# One fact per missed strike: the attacker's Missed (its Dodged twin is the same strike), so the
# Miss rises over the unit that dodged, as Godot_FE drew it, and holds for miss_hold.
func _on_action_missed(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.target_id)
	if token == null:
		return
	_show_number(token, 0, DamageNumber.Style.MISS)
	_play_feedback(token, StrikeFeedback.Kind.MISS)
	_hold_for(fact, miss_hold)


# One fact per critical hit: the struck unit's Crit taken (Crit dealt is the same strike). It
# flashes, shakes and pops at once; its Critical pop-up waits for the Damage taken that follows,
# which knows what Block absorbed. A crit fully countered (0 damage) has no Damage taken, so it
# shows "Critical 0" over the hit's "No damage" and holds for strike_hold itself.
func _on_action_crit_taken(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	_add_cosmetic(token.flash(crit_flash_color, crit_flash_time))
	_add_cosmetic(_camera.shake(crit_shake_strength, crit_shake_time))
	_play_feedback(token, StrikeFeedback.Kind.CRIT)
	if fact.amount > 0:
		_crit_shown[fact.actor_id] = true
		return
	_show_number(token, 0, DamageNumber.Style.CRITICAL)
	_hold_for(fact, strike_hold)


# A side's Phase Start: its spent units gray from now on, the other side's show in colour.
func _on_flow_phase_started(fact: CombatFact) -> void:
	_phase_side = fact.side
	_played_turn = fact.amount
	_is_darkness_window = false
	for token: UnitToken in _tokens.values():
		token.show_phase(token.side == _phase_side)


# The darkness phase follows the enemy Phase End (Darkness.register).
func _on_flow_phase_ended(fact: CombatFact) -> void:
	if fact.side != CombatFact.CombatSide.ENEMY:
		return
	_is_darkness_window = true
	_is_darkness_shown = false


# Emits darkness_phase_started at the darkness phase's first change of anything.
func _note_darkness_phase(fact: CombatFact) -> void:
	if not _is_darkness_window or _is_darkness_shown or not _is_darkness_change(fact):
		return
	_is_darkness_shown = true
	darkness_phase_started.emit(_played_turn)


func _on_effect_modifier_gained(fact: CombatFact) -> void:
	_count_block_ban(fact, 1)


func _on_effect_modifier_expired(fact: CombatFact) -> void:
	_count_block_ban(fact, -1)


# Adds change to the actor's timed Block bans when fact is one (BoardViewModel.is_block_ban), and
# shows its mark while any is left.
func _count_block_ban(fact: CombatFact, change: int) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null or not BoardViewModel.is_block_ban(_session, fact):
		return
	var held: int = _block_bans.get(fact.actor_id, 0)
	var bans: int = maxi(held + change, 0)
	if bans == 0:
		_block_bans.erase(fact.actor_id)
	else:
		_block_bans[fact.actor_id] = bans
	token.show_block_ban(bans > 0)


# A gain's word ("+2 Block") rises with no wait; a refresh's clearing is not a loss.
func _on_unit_block_gained(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_block(token.block + fact.amount)
	_show_number(token, fact.amount, DamageNumber.Style.BLOCK_GAINED)


func _on_unit_block_lost(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	token.show_block(token.block - fact.amount)
	_show_number(token, fact.amount, DamageNumber.Style.BLOCK_LOST)


# Its amount is the change, never taking Stance below 0. Its word rises with no wait (the hit's
# own beat holds playback), and a loss plays the Stance-lost look.
func _on_unit_stance_changed(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	var stance_max: int = _stance_max_of(fact.actor_id, token.stance_max)
	_add_cosmetic(token.show_stance(token.stance + fact.amount, stance_max))
	_show_number(token, fact.amount, DamageNumber.Style.STANCE)
	if fact.amount < 0:
		_play_feedback(token, StrikeFeedback.Kind.STANCE_LOST)
	if _is_beat_tail(fact):
		if token.stance == 0:
			_beat_next = CombatFact.Kind.EXPOSED
			_beat_fact = fact
		else:
			_release_beat(fact)


# Stance reached 0: the "Exposed" chip and the Stance-broken look, with no wait of its own.
func _on_unit_exposed(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	_show_number(token, 0, DamageNumber.Style.EXPOSED)
	_play_feedback(token, StrikeFeedback.Kind.STANCE_BROKEN)
	if _is_beat_tail(fact):
		_release_beat(fact)


# Holds seconds after fact (a strike's Damage taken), or after its tail when one follows: a unit
# left standing with Stance loses Stance next (DamagePipeline.apply), and one brought to 0 is
# Exposed after that (EffectEngine.change_stance). A fact off that forecast releases the beat.
func _defer_beat(fact: CombatFact, token: UnitToken, seconds: float) -> void:
	_release_beat(null)
	if token.hp <= 0 or token.stance <= 0:
		_hold_for(fact, seconds)
		return
	_hold_for(fact, 0.0)
	_beat_unit = fact.actor_id
	_beat_time = seconds
	_beat_next = CombatFact.Kind.STANCE_CHANGED
	_beat_fact = fact


func _is_beat_tail(fact: CombatFact) -> bool:
	return not _beat_unit.is_empty() and fact.kind == _beat_next and fact.actor_id == _beat_unit


# Gives the waiting beat to fact's wait (none when fact is null) and clears it.
func _release_beat(fact: CombatFact) -> void:
	if _beat_unit.is_empty():
		return
	if fact != null:
		var own: float = _last_duration if fact == _last_fact else 0.0
		_hold_for(fact, maxf(own, _beat_time))
	_beat_unit = ""
	_beat_fact = null


# Block to 0 and Stance to its maximum, at the unit's side's Phase Start; _on_fact_played clears
# its turn.
func _on_unit_block_stance_refreshed(fact: CombatFact) -> void:
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	var stance_max: int = _stance_max_of(fact.actor_id, token.stance_max)
	token.show_block(0)
	_add_cosmetic(token.show_stance(stance_max, stance_max))


# Every fact, after its own signal: whether its actor has acted and may still move, by the same
# rules as CombatState.follow() (see _ACTION_KINDS). The exchange is tracked whoever has a token.
func _on_fact_played(fact: CombatFact) -> void:
	_note_darkness_phase(fact)
	# A strike's beat still waiting past a fact that isn't its tail plays after that fact.
	if not _beat_unit.is_empty() and fact != _beat_fact:
		_release_beat(fact)
	if fact.kind == CombatFact.Kind.ATTACK_MADE:
		_crit_shown.clear()
		_hit_damage.clear()
	var is_attack: bool = false
	if fact.kind == CombatFact.Kind.BEFORE_COMBAT:
		if _open_exchange == "%s>%s" % [fact.target_id, fact.actor_id]:
			_open_exchange = ""
		else:
			_open_exchange = "%s>%s" % [fact.actor_id, fact.target_id]
			is_attack = true
	var token: UnitToken = token_of(fact.actor_id)
	if token == null:
		return
	var acted: bool = token.has_acted or is_attack or _ACTION_KINDS.has(fact.kind)
	var pending: bool = (
			token.is_second_move_pending
			or (fact.flags & CombatFact.Flag.SECOND_MOVE_PENDING) != 0
	)
	match fact.kind:
		CombatFact.Kind.BLOCK_STANCE_REFRESHED:
			acted = false
			pending = false
		CombatFact.Kind.UNIT_MOVED:
			# Only a unit's own walk counts; after its action, that walk is its second move.
			if fact.amount > 0 and acted:
				pending = false
		CombatFact.Kind.UNIT_WAITED:
			# Unflagged, it is a Wait after acting, which ends the second move.
			if (fact.flags & CombatFact.Flag.SECOND_MOVE_PENDING) == 0:
				pending = false
	if acted != token.has_acted or pending != token.is_second_move_pending:
		token.show_turn(acted, pending)


func _stance_max_of(unit_id: String, fallback: int) -> int:
	if not _session.state.has_unit(unit_id):
		return fallback
	return _session.stats(unit_id).get_int(CombatValue.Key.STANCE_MAX)


# One fact per tile that deepens, its amount the new layer (darkness plan, question 4), held for
# darkness_tile_hold; a wave's release has no tile and draws nothing by itself.
func _on_world_darkness_advanced(fact: CombatFact) -> void:
	if fact.tile == CombatFact.NO_TILE:
		return
	var layer: int = fact.amount
	if layer <= WhileLayerCondition.Layer.DRY:
		layer = _session.state.map.darkness.layer_at(fact.tile)
	_darkness.show_layer(fact.tile, layer)
	_hold_for(fact, darkness_tile_hold)


# A door opened or closed, a container opened or searched, a brazier lit or doused: its mark shows
# the fact's change (MapObjects.Change) at once, with no wait. A thrown keg's fuse burning down
# shows on its token's fuse badge. Other changes draw nothing.
func _on_world_object_state_changed(fact: CombatFact) -> void:
	if fact.key == MapObjects.Change.FUSE_BURNED:
		var keg: UnitToken = token_of(fact.actor_id)
		if keg != null:
			keg.show_fuse(fact.amount)
		return
	var mark: MapObjectMark = object_mark_of(fact.actor_id)
	if mark == null or mark.view == null:
		return
	var shown: BoardViewModel.ObjectView = mark.view
	match fact.key:
		MapObjects.Change.OPENED:
			if shown.kind == MapLayout.ObjectKind.DOOR:
				shown.is_open = true
			else:
				shown.is_used = true
		MapObjects.Change.CLOSED:
			shown.is_open = false
		MapObjects.Change.SEARCHED:
			shown.is_used = true
		MapObjects.Change.LIT:
			shown.is_lit = true
		MapObjects.Change.DOUSED:
			shown.is_lit = false
		_:
			return
	mark.refresh()


func _on_camera_rig_framed() -> void:
	_is_info_dirty = true


func _on_map_area_resized() -> void:
	if _session != null:
		_frame_map()


# The facts the darkness phase records (Darkness): damage, deepening and releases, and erosion.
static func _is_darkness_change(fact: CombatFact) -> bool:
	match fact.kind:
		CombatFact.Kind.DARKNESS_DAMAGE_TAKEN, CombatFact.Kind.DARKNESS_ADVANCED:
			return true
		CombatFact.Kind.OBJECT_STATE_CHANGED:
			return fact.key == MapObjects.Change.CONTACTED or fact.key == MapObjects.Change.ERODED
	return false
