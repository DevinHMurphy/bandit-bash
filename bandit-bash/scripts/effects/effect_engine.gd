# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_engine.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name EffectEngine
extends RefCounted
## One session's effects: registration, trigger dispatch, inline windows, the reaction queue, value
## queries and the resource paths every gain goes through.
##
## Rules code records every fact with [method record]. A fact whose kind is a trigger dispatches to
## the effects indexed under it whose scope sees the fact's actor, in reaction order (role, seat
## with enemies last, carrier kind with curses last, instance id). Inline operations change the
## action in flight at once; the rest wait in the [ReactionQueue] until [method drain]. A trigger
## with an inline window is opened with [method open_window] before its amount is committed.[br]
## [b]Pure:[/b] no nodes, autoloads, buses, global RNG or disk; the map is read and written through
## [member state], randomness goes through [member rolls], and problems are returned in
## [member diagnostics], never logged, so a sandboxed copy may run on a worker thread.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## A point where timed modifiers can come due. Rules code reports each with
## [method reach_boundary] at the points the combat core names.
enum Boundary {
	## An attack finished, hit or miss, counters included: spends one use of the attacker's "next
	## attack" modifiers added before the attack started.
	ATTACK_RESOLVED = 0,
	## An exchange's After Combat: ends [constant AddTimedModifier.End.THIS_EXCHANGE].
	EXCHANGE_END = 1,
	## A side's Phase End (combat core Phase End step 5): ends
	## [constant AddTimedModifier.End.UNTIL_PHASE_END] of this phase and
	## [constant AddTimedModifier.End.END_OF_NEXT_PHASE] of the phase before.
	PHASE_END = 2,
	## The battle ended: every timed modifier expires.
	COMBAT_END = 3,
}

## Triggers that fire before their amount is committed, so inline operations can change it
## (event bus plan, question 5).
const INLINE_TRIGGERS: Array[int] = [
	EffectTerms.Trigger.ATTACK_MADE,
	EffectTerms.Trigger.HIT_DEALT,
	EffectTerms.Trigger.HIT_TAKEN,
	EffectTerms.Trigger.CRIT_DEALT,
	EffectTerms.Trigger.CRIT_TAKEN,
	EffectTerms.Trigger.HEALED,
	EffectTerms.Trigger.HEALED_AN_ALLY,
	EffectTerms.Trigger.DARKNESS_DAMAGE_TAKEN,
	EffectTerms.Trigger.BLOCK_GAINED,
]

# The trigger of each combat fact kind that is one. Facts without an entry dispatch nothing.
const _COMBAT_TRIGGERS: Dictionary[int, int] = {
	CombatFact.Kind.PHASE_START: EffectTerms.Trigger.PHASE_START,
	CombatFact.Kind.UNIT_TURN_START: EffectTerms.Trigger.UNIT_TURN_START,
	CombatFact.Kind.BEFORE_COMBAT: EffectTerms.Trigger.BEFORE_COMBAT,
	CombatFact.Kind.AFTER_COMBAT: EffectTerms.Trigger.AFTER_COMBAT,
	CombatFact.Kind.UNIT_TURN_END: EffectTerms.Trigger.UNIT_TURN_END,
	CombatFact.Kind.PHASE_END: EffectTerms.Trigger.PHASE_END,
	CombatFact.Kind.ATTACK_MADE: EffectTerms.Trigger.ATTACK_MADE,
	CombatFact.Kind.HIT_DEALT: EffectTerms.Trigger.HIT_DEALT,
	CombatFact.Kind.HIT_TAKEN: EffectTerms.Trigger.HIT_TAKEN,
	CombatFact.Kind.MISSED: EffectTerms.Trigger.MISSED,
	CombatFact.Kind.DODGED: EffectTerms.Trigger.DODGED,
	CombatFact.Kind.DAMAGE_DEALT: EffectTerms.Trigger.DAMAGE_DEALT,
	CombatFact.Kind.DAMAGE_TAKEN: EffectTerms.Trigger.DAMAGE_TAKEN,
	CombatFact.Kind.CRIT_DEALT: EffectTerms.Trigger.CRIT_DEALT,
	CombatFact.Kind.CRIT_TAKEN: EffectTerms.Trigger.CRIT_TAKEN,
	CombatFact.Kind.EXPOSED: EffectTerms.Trigger.EXPOSED,
	CombatFact.Kind.DEFEATED_AN_ENEMY: EffectTerms.Trigger.DEFEATED_AN_ENEMY,
	CombatFact.Kind.DEFEATED: EffectTerms.Trigger.DEFEATED,
	CombatFact.Kind.HEALED_AN_ALLY: EffectTerms.Trigger.HEALED_AN_ALLY,
	CombatFact.Kind.HEALED: EffectTerms.Trigger.HEALED,
	CombatFact.Kind.USED_STAFF_ON_ALLY: EffectTerms.Trigger.USED_STAFF_ON_ALLY,
	CombatFact.Kind.DARKNESS_DAMAGE_TAKEN: EffectTerms.Trigger.DARKNESS_DAMAGE_TAKEN,
	CombatFact.Kind.OBJECT_USED: EffectTerms.Trigger.OBJECT_USED,
	CombatFact.Kind.SHOVED_A_UNIT: EffectTerms.Trigger.SHOVED_A_UNIT,
	CombatFact.Kind.SHOVED: EffectTerms.Trigger.SHOVED,
	CombatFact.Kind.BLOCK_GAINED: EffectTerms.Trigger.BLOCK_GAINED,
}

# Facts that change their actor's stat sheet inputs: a weapon swapped into the slot, a permanent
# stat change, a timed modifier gained or expired, a unit placed (arriving from another map).
# Recording one drops the actor's cached sheet, so a mirror that follows facts stays in step.
const _INVALIDATING_KINDS: Array[int] = [
	CombatFact.Kind.WEAPON_SWAPPED,
	CombatFact.Kind.STAT_CHANGED,
	CombatFact.Kind.MODIFIER_GAINED,
	CombatFact.Kind.MODIFIER_EXPIRED,
	CombatFact.Kind.UNIT_SPAWNED,
]

# Reaction-order rank of an enemy owner's seat: after every player seat (question 6).
const _ENEMY_SEAT_RANK: int = 1 << 20

## The session (map) this engine belongs to; stamped on every fact it records.
var session_id: int = 0

## The rules state effects read and the resource paths write. Never null in use.
var state: SandboxState = null

## Where every random decision goes: [LiveRolls] for real resolution, another source in a sandbox.
var rolls: RollSource = null

## Problems found while resolving: content errors, reaction caps hit. Returned, never logged, so the
## main thread can log them after a sandbox finishes.
var diagnostics: PackedStringArray = []

## Every fact recorded, in [member CombatFact.seq] order.
var fact_log: Array[CombatFact] = []

## Every campaign grant applied here, in order: [CampaignGrant] adds one when its reaction
## resolves, so a reaction a cap drops grants nothing. A sandbox's copy starts its own empty list,
## so forecasts grant nothing. The session hands them to the campaign session.
var grants: Array[Grant] = []

## Verify mode: every cached [method stats] read is also built fresh, and a difference is reported
## in [member diagnostics]. On in tests and debug builds, off in release.
var verify: bool = OS.is_debug_build()

var _instances: Dictionary[String, EffectInstance] = {}

# Triggered instances per trigger, each an Array[EffectInstance] in registration order.
var _by_trigger: Dictionary[int, Array] = {}

# Always-on instances without conditions: part of every stat sheet they apply to.
var _unconditional: Array[EffectInstance] = []

# Always-on instances with conditions, per key they modify: checked live on every query.
var _conditional_by_key: Dictionary[int, Array] = {}

# Inline windows opened but not yet recorded, by fact.
var _windows: Dictionary[CombatFact, InlineWindow] = {}

# The window being opened: side facts and queued reactions wait in it until its fact is recorded.
var _opening: InlineWindow = null

# Generation of the reaction being resolved; 0 while rules code records facts.
var _generation: int = 0

var _observers: Array[Callable] = []

var _context_observers: Array[Callable] = []

# Value queries in progress, by subject, key and stat, so a condition that reads the value it
# modifies sees the static part instead of recursing.
var _querying: Dictionary[String, bool] = {}

# Everything that changes as the session resolves, apart from the instances: what a sandbox copies.
var _run: RunState = null


## [param run]: the state a sandbox starts from ([method copy_for_sandbox]); null for a new
## battle.
func _init(
		rules_state: SandboxState,
		roll_source: RollSource,
		session: int = 0,
		run: RunState = null
) -> void:
	state = rules_state
	rolls = roll_source
	session_id = session
	_run = run if run != null else RunState.new()


## Adds [param instance] to the engine. Its combat lane starts fresh (battle start) unless
## [param keep_combat_lane] (a unit moving between maps keeps its state).
func register(instance: EffectInstance, keep_combat_lane: bool = false) -> void:
	if instance == null or instance.definition == null:
		diagnostics.append("EffectEngine: register needs an instance with a definition")
		return
	if _instances.has(instance.instance_id):
		diagnostics.append("EffectEngine: %s is already registered" % [instance.instance_id])
		return
	if not keep_combat_lane:
		instance.reset_lane(EffectTerms.Lane.COMBAT)
	_instances[instance.instance_id] = instance
	_index(instance)
	_run.sheets.clear()


## Removes the instance [param instance_id]. Returns it, with its state, or null if unknown.
func unregister(instance_id: String) -> EffectInstance:
	var instance: EffectInstance = _instances.get(instance_id, null)
	if instance == null:
		return null
	_instances.erase(instance_id)
	_unindex(instance)
	_run.sheets.clear()
	return instance


## The registered instance [param instance_id], or null.
func get_instance(instance_id: String) -> EffectInstance:
	return _instances.get(instance_id, null)


## Every registered instance, by instance id.
func get_instances() -> Array[EffectInstance]:
	var list: Array[EffectInstance] = []
	list.assign(_instances.values())
	list.sort_custom(func(a: EffectInstance, b: EffectInstance) -> bool:
		return a.instance_id < b.instance_id
	)
	return list


## Moves every instance owned by [param owner_id] (an item) to [param holder_id]; empty: the item
## is held by nobody.
func set_holder(owner_id: String, holder_id: String) -> void:
	for instance: EffectInstance in _instances.values():
		if instance.owner.owner_id == owner_id and instance.owner.kind == EffectOwner.Kind.ITEM:
			instance.owner.holder_id = holder_id
	_run.sheets.clear()


## Sets the base of [param key] for [param subject_id], such as its unit type's base stat.
func set_base(subject_id: String, key: int, value: float, label: String = "") -> void:
	_base_sheet(subject_id).set_base(key, value, label)
	_run.sheets.erase(subject_id)


## Adds a sourced permanent change to [param subject_id] (a stat booster, an item's delta). Kept as
## a modifier, so breakdowns name it.
func add_delta(subject_id: String, modifier: Modifier) -> void:
	_base_sheet(subject_id).add_modifier(modifier)
	_run.sheets.erase(subject_id)


## The permanent deltas of [param subject_id] on [param key], for the campaign bridge to write back.
func get_deltas(subject_id: String, key: int, stat: int = Modifier.NO_STAT) -> Array[Modifier]:
	return _base_sheet(subject_id).get_modifiers(key, stat)


## Adds [param points] percentage points to [param unit_id]'s growth for [param stat] (an
## [enum CombatValue.Stat]) in the state, for the battle-end bridge, and records
## [constant CombatFact.Kind.GROWTH_CHANGED]. Growths change no combat value, so no sheet drops.
func add_growth(unit_id: String, stat: int, points: int, source_effect_id: String = "") -> void:
	state.add_growth(unit_id, stat, points)
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.GROWTH_CHANGED, unit_id)
	fact.amount = points
	fact.key = stat
	fact.source_effect_id = source_effect_id
	fact.source = _source_of(source_effect_id)
	record(fact)


## The read API: the values of [param subject_id] (a unit, or a seat's subject id). The static
## part (bases, deltas, unconditional effects) is cached until a change to its inputs drops it:
## registration, a holder, a base or delta, or a fact that touches them; the live part is added on
## every query. Read it again after a change instead of holding it.
func stats(subject_id: String) -> StatSheet:
	var cached: StatSheet = _run.sheets.get(subject_id, null)
	if cached != null and not _watch_holds(subject_id):
		cached = null
	if cached == null:
		cached = fresh_stats(subject_id)
		_run.sheets[subject_id] = cached
		_watch(subject_id)
	elif verify:
		_verify_sheet(cached, fresh_stats(subject_id))
	return cached


## The sheet [method stats] would build for [param subject_id] if nothing were cached. Verify mode
## compares every cached read with it; tests use it directly.
func fresh_stats(subject_id: String) -> StatSheet:
	var sheet: StatSheet = StatSheet.new(subject_id, self)
	var base: StatSheet = _run.base_sheets.get(subject_id, null)
	if base != null:
		sheet = base.copy_for(self)
	for instance: EffectInstance in _unconditional:
		if applies_to(instance, subject_id):
			for modifier: Modifier in _modifiers_of(instance):
				sheet.add_modifier(modifier)
	return sheet


## The live modifiers of [param key] for [param subject_id]: timed modifiers it holds, conditional
## always-on effects whose conditions pass now, and the "that" modifiers of [param ctx]. Called by
## [StatSheet].
func live_modifiers(
		subject_id: String, key: int, ctx: EffectContext, stat: int = Modifier.NO_STAT
) -> Array[Modifier]:
	var live: Array[Modifier] = []
	for timed: TimedModifier in _run.timed:
		if (
				timed.holder_id == subject_id
				and timed.modifier.key == key
				and timed.modifier.stat == stat
		):
			live.append(timed.modifier)
	if _conditional_by_key.has(key):
		var guard: String = "%s|%d|%d" % [subject_id, key, stat]
		if not _querying.has(guard):
			_querying[guard] = true
			live.append_array(_conditional_modifiers(subject_id, key, ctx, stat))
			_querying.erase(guard)
	if ctx != null:
		for modifier: Modifier in ctx.that_modifiers(key):
			if modifier.stat == stat:
				live.append(modifier)
	return live


## Records [param fact]: stamps its session and [member CombatFact.seq], logs it, tells the
## observers, and dispatches its trigger. Inline operations change [param ctx] (a fresh context
## when null). A fact opened with [method open_window] only releases its waiting reactions.
func record(fact: CombatFact, ctx: EffectContext = null) -> void:
	fact.session_id = session_id
	fact.seq = _run.next_seq
	_run.next_seq += 1
	fact_log.append(fact)
	if fact.kind == CombatFact.Kind.PHASE_START:
		_run.phase += 1
		_run.in_phase = true
	elif fact.kind == CombatFact.Kind.ATTACK_MADE:
		_run.attacks += 1
		_run.attack_of[fact.actor_id] = _run.attacks
	if _INVALIDATING_KINDS.has(fact.kind):
		_run.sheets.erase(fact.actor_id)
	for observer: Callable in _observers:
		observer.call(fact)
	for observer: Callable in _context_observers:
		observer.call(fact, ctx)

	var window: InlineWindow = _windows.get(fact, null)
	if window != null:
		_windows.erase(fact)
		for side_fact: CombatFact in window.side_facts:
			record(side_fact)
		for reaction: ReactionQueue.Reaction in window.reactions:
			_run.queue.push(reaction)
		return
	var trigger: int = _COMBAT_TRIGGERS.get(fact.kind, -1)
	if trigger >= 0:
		_dispatch(fact, trigger, ctx, null)


## Opens [param fact]'s inline window before its amount is committed: matching effects are tested
## now and their inline operations change [param ctx]; their queued operations, counter changes
## and activations wait until [method record] records the finished fact.
func open_window(fact: CombatFact, ctx: EffectContext) -> void:
	if _windows.has(fact):
		return
	var trigger: int = _COMBAT_TRIGGERS.get(fact.kind, -1)
	if not INLINE_TRIGGERS.has(trigger):
		diagnostics.append("EffectEngine: %s has no inline window" % [_kind_name(fact.kind)])
		return
	fact.session_id = session_id
	var window: InlineWindow = InlineWindow.new()
	_windows[fact] = window
	var outer: InlineWindow = _opening
	_opening = window
	_dispatch(fact, trigger, ctx, window)
	_opening = outer


## Fires [param instance] without a trigger, for a command: a rune cast, a Pouch item used. Its
## conditions and charges apply; its operations queue with [param ctx] (its command target).
## Returns whether it fired.
func activate(instance: EffectInstance, ctx: EffectContext) -> bool:
	ctx.engine = self
	ctx.instance = instance
	ctx.subject_id = _this_unit(instance, ctx.command_target_id)
	ctx.is_query = false
	if not _passes(instance, ctx):
		return false
	_fire(instance, ctx, EffectTerms.Trigger.ALWAYS)
	return true


## Starts a new resolution step for the per-step reaction cap: one unit's turn, one phase
## boundary, the darkness step or reinforcement arrival.
func begin_step() -> void:
	_run.queue.begin_step()


## Resolves the reaction queue until it is empty: a step boundary. Reactions past a cap are dropped
## with a diagnostic; what already resolved stays.
func drain() -> void:
	while not _run.queue.is_empty():
		var reaction: ReactionQueue.Reaction = _run.queue.pop()
		if not reaction.exempt:
			if reaction.generation > ReactionQueue.MAX_DEPTH:
				diagnostics.append(
						"EffectEngine: chain of %s stopped at depth %d"
						% [reaction.instance.instance_id, ReactionQueue.MAX_DEPTH]
				)
				continue
			if _run.queue.resolved_this_step >= ReactionQueue.MAX_PER_STEP:
				diagnostics.append(
						"EffectEngine: step stopped at %d reactions, dropping %s"
						% [ReactionQueue.MAX_PER_STEP, reaction.instance.instance_id]
				)
				continue
			_run.queue.resolved_this_step += 1
		var outer: int = _generation
		_generation = reaction.generation
		reaction.ctx.engine = self
		for operation: EffectOperation in reaction.operations:
			operation.apply(reaction.ctx)
		reaction.ctx.engine = null
		_generation = outer


## The number of reactions waiting for [method drain].
func pending_reactions() -> int:
	return _run.queue.size()


## Reactions resolved since [method begin_step], map-object reactions excluded: how close the step
## came to [constant ReactionQueue.MAX_PER_STEP].
func reactions_this_step() -> int:
	return _run.queue.resolved_this_step


## Gives [param holder_id] [param modifier] until [param end] or for [param uses] attacks (0: no
## limit), and records [constant CombatFact.Kind.MODIFIER_GAINED]. One added between phases
## belongs to the next phase to start.
func add_timed_modifier(
		holder_id: String,
		modifier: Modifier,
		end: AddTimedModifier.End,
		uses: int,
		source_effect_id: String = ""
) -> void:
	if not state.has_unit(holder_id):
		return
	var timed: TimedModifier = TimedModifier.new()
	timed.holder_id = holder_id
	timed.modifier = modifier
	timed.end = end
	timed.uses_left = maxi(uses, 0)
	timed.phase = _run.phase if _run.in_phase else _run.phase + 1
	timed.attacks_before = _run.attacks
	timed.source_effect_id = source_effect_id
	_run.timed.append(timed)
	var fact: CombatFact = _new_fact(CombatFact.Kind.MODIFIER_GAINED, holder_id)
	fact.source_effect_id = source_effect_id
	record(fact)


## The timed modifiers [param holder_id] holds, in the order gained.
func get_timed_modifiers(holder_id: String) -> Array[TimedModifier]:
	var held: Array[TimedModifier] = []
	for timed: TimedModifier in _run.timed:
		if timed.holder_id == holder_id:
			held.append(timed)
	return held


## Expires the timed modifiers due at [param boundary] and records one
## [constant CombatFact.Kind.MODIFIER_EXPIRED] each, in the order they were gained.
## [param subject_id]: the attacker, for [constant ATTACK_RESOLVED]; ignored otherwise.
func reach_boundary(boundary: Boundary, subject_id: String = "") -> void:
	var expired: Array[TimedModifier] = []
	for timed: TimedModifier in _run.timed:
		if _comes_due(timed, boundary, subject_id):
			expired.append(timed)
	if boundary == Boundary.PHASE_END:
		_run.in_phase = false
	for timed: TimedModifier in expired:
		_run.timed.erase(timed)
		var fact: CombatFact = _new_fact(CombatFact.Kind.MODIFIER_EXPIRED, timed.holder_id)
		fact.source_effect_id = timed.source_effect_id
		record(fact)


## Whether [param other_id] is on [param side] of [param reference_side]: an ally shares the side,
## an enemy is on the other one, and any is every unit and object.
func matches_side(
		reference_side: CombatFact.CombatSide,
		other_id: String,
		side: EffectTerms.UnitSide
) -> bool:
	var other_side: CombatFact.CombatSide = state.side_of(other_id)
	match side:
		EffectTerms.UnitSide.ALLY:
			return other_side == reference_side and other_side != CombatFact.CombatSide.NONE
		EffectTerms.UnitSide.ENEMY:
			return (
					other_side != reference_side
					and other_side != CombatFact.CombatSide.NONE
					and reference_side != CombatFact.CombatSide.NONE
			)
	return true


## Tiles up plus tiles across between two units, ignoring terrain; -1 if either has no tile. A unit
## defeated this step keeps its tile, so a broken keg's splash still has a center.
func tile_distance(from_id: String, to_id: String) -> int:
	var from_tile: Vector2i = state.tile_of(from_id)
	var to_tile: Vector2i = state.tile_of(to_id)
	if from_tile == CombatFact.NO_TILE or to_tile == CombatFact.NO_TILE:
		return -1
	return absi(from_tile.x - to_tile.x) + absi(from_tile.y - to_tile.y)


## A scratch copy for a [Sandbox], resolving with [param roll_source]: the state's
## [method SandboxState.copy_for_sandbox], copies of every instance (counters and charges), timed
## modifiers, base values, deltas, waiting reactions and the phase and attack counts, so facts
## continue from this engine's [member CombatFact.seq]. Its fact log and diagnostics start empty
## and it has no observers of either kind. Nothing it does reaches this engine. Main thread only.
func copy_for_sandbox(roll_source: RollSource) -> EffectEngine:
	var run: RunState = _run.copy()
	var copy: EffectEngine = EffectEngine.new(
			state.copy_for_sandbox(), roll_source, session_id, run
	)
	var copies: Dictionary[String, EffectInstance] = {}
	for instance: EffectInstance in get_instances():
		var instance_copy: EffectInstance = instance.copy()
		copies[instance.instance_id] = instance_copy
		copy.register(instance_copy, true)
	run.queue = _run.queue.copy_for(copies)
	# Sheets are copied, not re-derived, after the registrations above cleared the copy's cache.
	for subject_id: String in _run.sheets:
		run.sheets[subject_id] = _run.sheets[subject_id].copy_for(copy)
	run.watch_ids = _run.watch_ids.duplicate()
	run.watch_awake = _run.watch_awake.duplicate()
	copy.verify = verify
	return copy


## Adds a read-only listener called with every fact as it is recorded, on the host (XP tally,
## Standout, objectives). It must not change rules state.
func add_observer(observer: Callable) -> void:
	_observers.append(observer)


## Adds a read-only listener called as [code]observer(fact, ctx)[/code] with every fact as it is
## recorded, after the [method add_observer] listeners: [param ctx] is the context the fact was
## recorded with ("that attack", "that hit", with its inline changes so far), or null when none.
## Read-only like any observer: it must change neither rules state nor the context. The forecast
## reads each hit's own context through it ([CombatForecast]).
func add_context_observer(observer: Callable) -> void:
	_context_observers.append(observer)


## Whether [param unit_id] is in [param scope] relative to [param owner] (effect-triggers.md,
## Scopes). Map objects are in no scope wider than This unit.
func in_scope(owner: EffectOwner, unit_id: String, scope: EffectTerms.Scope) -> bool:
	if unit_id.is_empty():
		return false
	if scope == EffectTerms.Scope.THIS_UNIT:
		return unit_id == owner.holder_id
	var side: CombatFact.CombatSide = state.side_of(unit_id)
	if side == CombatFact.CombatSide.NONE:
		return false
	match scope:
		EffectTerms.Scope.YOUR_UNIT:
			return side == owner.side and state.seat_of(unit_id) == owner.seat
		EffectTerms.Scope.ANY_ALLY_UNIT:
			return side == owner.side
	return true


## Every unit on the map in [param scope] relative to [param owner], in the state's order.
func units_in_scope(owner: EffectOwner, scope: EffectTerms.Scope) -> PackedStringArray:
	var units: PackedStringArray = []
	for unit_id: String in state.unit_ids():
		if in_scope(owner, unit_id, scope):
			units.append(unit_id)
	return units


## Whether [param instance]'s always-on modifiers apply to [param subject_id]: its own subject, or a
## unit in its scope.
func applies_to(instance: EffectInstance, subject_id: String) -> bool:
	return _reaches(instance, subject_id) and not is_dormant(instance)


## Whether [param instance] sleeps: owned by a unit, or by an item a unit carries, while that unit
## isn't on the map (defeated, or not placed), or a weapon that isn't in its holder's Weapon slot.
## A dormant instance adds nothing to queries and reacts to nothing; its counters and charges
## are kept. Army, rune and map-object instances never sleep.
func is_dormant(instance: EffectInstance) -> bool:
	var owner: EffectOwner = instance.owner
	if owner.kind != EffectOwner.Kind.UNIT and owner.kind != EffectOwner.Kind.ITEM:
		return false
	if not state.has_unit(owner.holder_id):
		return true
	return (
			owner.kind == EffectOwner.Kind.ITEM
			and instance.source_kind == Modifier.SourceKind.WEAPON
			and state.equipped_weapon_id(owner.holder_id) != owner.owner_id
	)


## The one path for every Block gain: opens the [constant CombatFact.Kind.BLOCK_GAINED] window,
## rounds the shaped amount half up, never below 0, and records the gain.
## [param giver_id]: the unit giving it, if another unit does. Returns the Block gained.
func gain_block(
		unit_id: String, amount: float, giver_id: String = "", source_effect_id: String = ""
) -> int:
	if not state.has_unit(unit_id):
		return 0
	var fact: CombatFact = _new_fact(
			CombatFact.Kind.BLOCK_GAINED, unit_id, _other(giver_id, unit_id)
	)
	fact.source_effect_id = source_effect_id
	fact.source = _source_of(source_effect_id)
	var ctx: EffectContext = EffectContext.new()
	open_window(fact, ctx)
	var gained: int = maxi(_half_up(ctx.shaped_amount(amount).total), 0)
	state.set_block(unit_id, state.get_block(unit_id) + gained)
	fact.amount = gained
	fact.block_amount = gained
	record(fact, ctx)
	return gained


## Takes up to [param amount] Block from [param unit_id], outside damage: a loss with no window
## ([constant CombatFact.Kind.BLOCK_LOST]). Records nothing when no Block was lost.
func lose_block(unit_id: String, amount: float, source_effect_id: String = "") -> int:
	if not state.has_unit(unit_id):
		return 0
	var block: int = state.get_block(unit_id)
	var lost: int = clampi(_half_up(amount), 0, block)
	if lost == 0:
		return 0
	state.set_block(unit_id, block - lost)
	var fact: CombatFact = _new_fact(CombatFact.Kind.BLOCK_LOST, unit_id)
	fact.amount = lost
	fact.block_amount = lost
	fact.source_effect_id = source_effect_id
	fact.source = _source_of(source_effect_id)
	record(fact)
	return lost


## The one path for every heal: opens the Healed an ally (when another unit heals) and Healed
## windows, applies the healed unit's [constant CampaignValue.HEALING_RECEIVED_PERCENT], rounds half
## up at the end, never below 0, caps it at maximum HP, and records both facts. Their
## [member CombatFact.amount] is the heal and [member CombatFact.hp_amount] what reached HP.
## Returns the HP restored.
func heal(
		unit_id: String, amount: float, healer_id: String = "", source_effect_id: String = ""
) -> int:
	if not state.has_unit(unit_id):
		return 0
	var healer: String = _other(healer_id, unit_id)
	var ctx: EffectContext = EffectContext.new()
	var ally_fact: CombatFact = null
	if not healer.is_empty():
		ally_fact = _new_fact(CombatFact.Kind.HEALED_AN_ALLY, healer, unit_id)
		ally_fact.source_effect_id = source_effect_id
		open_window(ally_fact, ctx)
	var fact: CombatFact = _new_fact(CombatFact.Kind.HEALED, unit_id, healer)
	fact.source_effect_id = source_effect_id
	open_window(fact, ctx)

	var sheet: StatSheet = stats(unit_id)
	var received: float = sheet.get_value(CampaignValue.Key.HEALING_RECEIVED_PERCENT, ctx) / 100.0
	var healed: int = maxi(_half_up(ctx.shaped_amount(amount).total * received), 0)
	var hp: int = state.get_hp(unit_id)
	var max_hp: int = sheet.get_int(CombatValue.Key.HP)
	var restored: int = clampi(healed, 0, maxi(max_hp - hp, 0))
	state.set_hp(unit_id, hp + restored)
	for healed_fact: CombatFact in [ally_fact, fact]:
		if healed_fact == null:
			continue
		healed_fact.amount = healed
		healed_fact.hp_amount = restored
		healed_fact.source = _source_of(source_effect_id)
		record(healed_fact, ctx)
	return restored


## Changes [param unit_id]'s Stance by [param delta] (rounded half up), between 0 and its maximum,
## and records [constant CombatFact.Kind.STANCE_CHANGED], then [constant CombatFact.Kind.EXPOSED]
## when it reaches 0. Records nothing when Stance doesn't change. Returns the change.
func change_stance(
		unit_id: String, delta: float, source_id: String = "", source_effect_id: String = ""
) -> int:
	if not state.has_unit(unit_id):
		return 0
	var old: int = state.get_stance(unit_id)
	var step: int = _half_up(delta)
	var stance: int = maxi(old + step, 0)
	if step > 0:
		stance = maxi(mini(stance, stats(unit_id).get_int(CombatValue.Key.STANCE_MAX)), old)
	if stance == old:
		return 0
	state.set_stance(unit_id, stance)
	var fact: CombatFact = _new_fact(
			CombatFact.Kind.STANCE_CHANGED, unit_id, _other(source_id, unit_id)
	)
	fact.amount = stance - old
	fact.source_effect_id = source_effect_id
	fact.source = _source_of(source_effect_id)
	record(fact)
	if stance == 0:
		var exposed: CombatFact = _new_fact(
				CombatFact.Kind.EXPOSED, unit_id, _other(source_id, unit_id)
		)
		exposed.source_effect_id = source_effect_id
		record(exposed)
	return stance - old


## Deals [param amount] splash damage (rounded half up) to [param target_id] through the combat
## core's splash rule ([method SandboxState.deal_splash]).
func deal_splash(
		source_id: String, target_id: String, amount: float, source_effect_id: String = ""
) -> void:
	if not state.has_unit(target_id):
		return
	var damage: int = maxi(_half_up(amount), 0)
	state.deal_splash(self, source_id, target_id, damage, source_effect_id)


## Records that [param instance]'s counter in [param lane] changed. Called by [CounterCondition].
func counter_changed(instance: EffectInstance, lane: EffectTerms.Lane) -> void:
	var fact: CombatFact = _new_fact(CombatFact.Kind.COUNTER_CHANGED, instance.owner.subject_id())
	fact.amount = instance.get_counter(lane)
	fact.source_effect_id = instance.instance_id
	fact.key = lane
	_side_fact(fact)


func _dispatch(
		fact: CombatFact, trigger: int, ctx: EffectContext, window: InlineWindow
) -> void:
	var matched: Array[EffectInstance] = []
	for instance: EffectInstance in _by_trigger.get(trigger, []):
		if _sees_fact(instance, fact):
			matched.append(instance)
	if matched.is_empty():
		return
	matched.sort_custom(func(a: EffectInstance, b: EffectInstance) -> bool:
		return _reacts_before(a, b, fact)
	)

	var action: EffectContext = ctx if ctx != null else EffectContext.new()
	var saved_instance: EffectInstance = action.instance
	var saved_fact: CombatFact = action.fact
	var saved_subject: String = action.subject_id
	action.engine = self
	action.is_query = false
	for instance: EffectInstance in matched:
		action.instance = instance
		action.fact = fact
		action.subject_id = _this_unit(instance, fact.actor_id)
		if _passes(instance, action):
			_fire(instance, action, trigger, window)
	action.instance = saved_instance
	action.fact = saved_fact
	action.subject_id = saved_subject


# Spends a charge, records the activation, applies inline operations and queues the rest.
func _fire(
		instance: EffectInstance, ctx: EffectContext, trigger: int, window: InlineWindow = null
) -> void:
	instance.spend_charge()
	var activated: CombatFact = _new_fact(
			CombatFact.Kind.EFFECT_ACTIVATED, instance.owner.subject_id()
	)
	activated.source_effect_id = instance.instance_id
	_side_fact(activated)

	var queued: Array[EffectOperation] = []
	for operation: EffectOperation in instance.definition.operations:
		if operation == null:
			continue
		if not operation.is_inline():
			queued.append(operation)
		elif INLINE_TRIGGERS.has(trigger):
			operation.apply(ctx)
		else:
			diagnostics.append(
					"EffectEngine: inline operation of %s on a trigger with no inline window"
					% [instance.instance_id]
			)
	if queued.is_empty():
		return

	var reaction: ReactionQueue.Reaction = ReactionQueue.Reaction.new()
	reaction.instance = instance
	reaction.ctx = ctx.copy_for_reaction()
	reaction.ctx.engine = null
	reaction.ctx.owner_tile = state.tile_of(instance.owner.holder_id)
	reaction.operations = queued
	reaction.exempt = instance.owner.kind == EffectOwner.Kind.MAP_OBJECT
	reaction.generation = _generation if reaction.exempt else _generation + 1
	if window != null:
		window.reactions.append(reaction)
	else:
		_run.queue.push(reaction)


# Every condition, in authored order, then a charge: checked once per fire. A failed condition
# stops the test, so later counters don't advance. A condition about "this unit" with no unit to
# test (an army's effect on a phase fact) is a content error.
func _passes(instance: EffectInstance, ctx: EffectContext) -> bool:
	for condition: EffectCondition in instance.definition.conditions:
		if condition == null:
			continue
		if ctx.subject_id.is_empty() and condition.names_this_unit():
			diagnostics.append(
					"EffectEngine: %s tests \"this unit\" on a fact with no unit"
					% [instance.instance_id]
			)
			return false
		if not condition.test(ctx):
			return false
	return instance.has_charge()


# Whether the instance's always-on modifiers reach the subject, asleep or not: its own subject, or
# a unit in its scope.
func _reaches(instance: EffectInstance, subject_id: String) -> bool:
	if subject_id.is_empty():
		return false
	if instance.owner.subject_id() == subject_id:
		return true
	return in_scope(instance.owner, subject_id, instance.definition.scope)


# Whether the fact is about a unit in the instance's scope. Phase facts have no actor: they match
# the owner's side. A dormant instance sees nothing.
func _sees_fact(instance: EffectInstance, fact: CombatFact) -> bool:
	var owner: EffectOwner = instance.owner
	if is_dormant(instance):
		return false
	if fact.actor_id.is_empty():
		return fact.side != CombatFact.CombatSide.NONE and fact.side == owner.side
	return in_scope(owner, fact.actor_id, instance.definition.scope)


# Reaction order (question 6): the fact's actor, then its target, then others; seat ascending with
# enemies last; carrier kind (curses last); instance id.
func _reacts_before(a: EffectInstance, b: EffectInstance, fact: CombatFact) -> bool:
	var role_a: int = _role_rank(a, fact)
	var role_b: int = _role_rank(b, fact)
	if role_a != role_b:
		return role_a < role_b
	var seat_a: int = _seat_rank(a.owner)
	var seat_b: int = _seat_rank(b.owner)
	if seat_a != seat_b:
		return seat_a < seat_b
	if a.source_kind != b.source_kind:
		return a.source_kind < b.source_kind
	return a.instance_id < b.instance_id


# Remembers which unconditional instances reach the subject and whether each is awake, so a read
# notices a unit leaving the map or a weapon swap even when no fact announced it.
func _watch(subject_id: String) -> void:
	var ids: PackedStringArray = []
	var awake: PackedByteArray = []
	for instance: EffectInstance in _unconditional:
		if _reaches(instance, subject_id):
			ids.append(instance.instance_id)
			awake.append(0 if is_dormant(instance) else 1)
	_run.watch_ids[subject_id] = ids
	_run.watch_awake[subject_id] = awake


# Whether every watched instance of the subject is as awake as when its sheet was built.
func _watch_holds(subject_id: String) -> bool:
	var ids: PackedStringArray = _run.watch_ids.get(subject_id, PackedStringArray())
	var awake: PackedByteArray = _run.watch_awake.get(subject_id, PackedByteArray())
	for i: int in ids.size():
		var instance: EffectInstance = _instances.get(ids[i], null)
		if instance == null or (0 if is_dormant(instance) else 1) != awake[i]:
			return false
	return true


# Verify mode: every static answer of the cached sheet must equal the fresh one's, for every key
# and stat either holds.
func _verify_sheet(cached: StatSheet, fresh: StatSheet) -> void:
	var slots: Array[Vector2i] = cached.get_slots()
	for slot: Vector2i in fresh.get_slots():
		if not slots.has(slot):
			slots.append(slot)
	for slot: Vector2i in slots:
		var same: bool = true
		if _is_permission(slot.x):
			same = (
					cached.explain_static_permission(slot.x, slot.y).is_allowed()
					== fresh.explain_static_permission(slot.x, slot.y).is_allowed()
			)
		else:
			same = is_equal_approx(
					cached.explain_static(slot.x, slot.y).total,
					fresh.explain_static(slot.x, slot.y).total
			)
		if not same:
			diagnostics.append(
					"EffectEngine: cached sheet of %s is out of date for key %d (stat %d)"
					% [cached.subject_id, slot.x, slot.y]
			)


func _comes_due(timed: TimedModifier, boundary: Boundary, subject_id: String) -> bool:
	match boundary:
		Boundary.ATTACK_RESOLVED:
			if timed.uses_left <= 0 or timed.holder_id != subject_id:
				return false
			if _run.attack_of.get(subject_id, 0) <= timed.attacks_before:
				return false
			timed.uses_left -= 1
			return timed.uses_left == 0
		Boundary.EXCHANGE_END:
			return timed.end == AddTimedModifier.End.THIS_EXCHANGE
		Boundary.PHASE_END:
			if timed.end == AddTimedModifier.End.UNTIL_PHASE_END:
				return timed.phase <= _run.phase
			if timed.end == AddTimedModifier.End.END_OF_NEXT_PHASE:
				return timed.phase + 1 <= _run.phase
			return false
	return true


func _role_rank(instance: EffectInstance, fact: CombatFact) -> int:
	var holder: String = instance.owner.holder_id
	if holder.is_empty():
		return 2
	if holder == fact.actor_id:
		return 0
	return 1 if holder == fact.target_id else 2


func _seat_rank(owner: EffectOwner) -> int:
	match owner.side:
		CombatFact.CombatSide.ENEMY:
			return _ENEMY_SEAT_RANK
		CombatFact.CombatSide.NONE:
			return _ENEMY_SEAT_RANK + 1
	return owner.seat


func _conditional_modifiers(
		subject_id: String, key: int, ctx: EffectContext, stat: int
) -> Array[Modifier]:
	var found: Array[Modifier] = []
	var query: EffectContext = ctx if ctx != null else EffectContext.new()
	var saved_instance: EffectInstance = query.instance
	var saved_subject: String = query.subject_id
	var saved_query: bool = query.is_query
	query.engine = self
	query.is_query = true
	for instance: EffectInstance in _conditional_by_key[key]:
		if not applies_to(instance, subject_id):
			continue
		query.instance = instance
		query.subject_id = _this_unit(instance, subject_id)
		if not _passes(instance, query):
			continue
		for modifier: Modifier in _modifiers_of(instance):
			if modifier.key == key and modifier.stat == stat:
				found.append(modifier)
	query.instance = saved_instance
	query.subject_id = saved_subject
	query.is_query = saved_query
	return found


# The modifiers an always-on instance's operations give, sourced to it.
func _modifiers_of(instance: EffectInstance) -> Array[Modifier]:
	var modifiers: Array[Modifier] = []
	for operation: EffectOperation in instance.definition.operations:
		var modifier: Modifier = null if operation == null else operation.make_modifier(instance)
		if modifier != null:
			modifiers.append(modifier)
	return modifiers


func _index(instance: EffectInstance) -> void:
	var trigger: int = instance.definition.trigger
	if trigger != EffectTerms.Trigger.ALWAYS:
		if not _by_trigger.has(trigger):
			var list: Array[EffectInstance] = []
			_by_trigger[trigger] = list
		_by_trigger[trigger].append(instance)
		return
	if _modifiers_of(instance).is_empty():
		return
	if instance.definition.conditions.is_empty():
		_unconditional.append(instance)
		return
	for modifier: Modifier in _modifiers_of(instance):
		if not _conditional_by_key.has(modifier.key):
			var keyed: Array[EffectInstance] = []
			_conditional_by_key[modifier.key] = keyed
		if not _conditional_by_key[modifier.key].has(instance):
			_conditional_by_key[modifier.key].append(instance)


func _unindex(instance: EffectInstance) -> void:
	for list: Array in _by_trigger.values():
		list.erase(instance)
	_unconditional.erase(instance)
	for list: Array in _conditional_by_key.values():
		list.erase(instance)


func _base_sheet(subject_id: String) -> StatSheet:
	if not _run.base_sheets.has(subject_id):
		_run.base_sheets[subject_id] = StatSheet.new(subject_id)
	return _run.base_sheets[subject_id]


# Records an engine-made side fact (an activation, a counter change) now, or after the fact whose
# window is being opened.
func _side_fact(fact: CombatFact) -> void:
	if _opening != null:
		_opening.side_facts.append(fact)
	else:
		record(fact)


func _new_fact(kind: CombatFact.Kind, actor_id: String = "", target_id: String = "") -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor_id, target_id)
	fact.session_id = session_id
	return fact


# The unit "this unit" means for an instance: its own unit for a unit, item or object effect;
# otherwise (an army or a rune) the unit the fact or query is about, which may be empty.
static func _this_unit(instance: EffectInstance, about_id: String) -> String:
	var holder: String = instance.owner.holder_id
	return about_id if holder.is_empty() else holder


static func _is_permission(key: int) -> bool:
	return (
			CombatValue.Permission.values().has(key)
			or CampaignValue.Permission.values().has(key)
	)


# Amounts stay exact through their window and round once, halves up, when applied (question 17).
static func _half_up(value: float) -> int:
	return ValueBreakdown.round_to_int(value, ValueBreakdown.Rounding.HALF_UP)


static func _other(other_id: String, unit_id: String) -> String:
	return "" if other_id == unit_id else other_id


static func _source_of(source_effect_id: String) -> CombatFact.Source:
	return CombatFact.Source.NONE if source_effect_id.is_empty() else CombatFact.Source.EFFECT


static func _kind_name(kind: int) -> String:
	var name: Variant = CombatFact.Kind.find_key(kind)
	return "KIND_%d" % [kind] if name == null else (name as String)


## One campaign grant an effect applied: who gets what, and from which effect. Plain data.
class Grant:
	extends RefCounted

	## The seat that gets it: the effect owner's.
	var seat: int = -1
	## What is granted: a [enum CampaignGrant.Grant].
	var grant: int = 0
	## Gold, for [constant CampaignGrant.Grant.GOLD].
	var amount: int = 0
	## The heirloom, unit type or rune granted; may be empty.
	var definition_id: String = ""
	## The effect instance that granted it.
	var source_effect_id: String = ""


# An inline window opened but not yet recorded: what waits for its fact.
class InlineWindow:
	extends RefCounted

	## Side facts (activations, counter changes) recorded right after the window's fact.
	var side_facts: Array[CombatFact] = []
	## Queued reactions released when the window's fact is recorded.
	var reactions: Array[ReactionQueue.Reaction] = []


# What changes as a session resolves, apart from the instances; copied whole for a sandbox.
class RunState:
	extends RefCounted

	## The next fact's [member CombatFact.seq].
	var next_seq: int = 1
	## Phases started this battle, both sides.
	var phase: int = 0
	## Whether a phase is under way (between Phase Start and Phase End).
	var in_phase: bool = false
	## Attacks started this battle.
	var attacks: int = 0
	## The number of the attack each unit has under way or made last.
	var attack_of: Dictionary[String, int] = {}
	## Timed modifiers held, in the order gained.
	var timed: Array[TimedModifier] = []
	## Base values and permanent deltas per subject, each a sheet without an engine.
	var base_sheets: Dictionary[String, StatSheet] = {}
	## Reactions waiting for the next drain.
	var queue: ReactionQueue = ReactionQueue.new()
	## Cached stat sheets per subject, each linked to its engine; a missing entry is rebuilt on its
	## next read.
	var sheets: Dictionary[String, StatSheet] = {}
	## Per cached sheet: the instances that reach its subject, and whether each was awake.
	var watch_ids: Dictionary[String, PackedStringArray] = {}
	## Parallel to [member watch_ids]: 1 awake, 0 dormant.
	var watch_awake: Dictionary[String, PackedByteArray] = {}

	## A copy sharing nothing mutable. The queue and the sheets are left empty: they must point at
	## the copied instances and engine, so [method EffectEngine.copy_for_sandbox] copies them.
	func copy() -> RunState:
		var run: RunState = RunState.new()
		run.next_seq = next_seq
		run.phase = phase
		run.in_phase = in_phase
		run.attacks = attacks
		run.attack_of = attack_of.duplicate()
		for held: TimedModifier in timed:
			run.timed.append(held.copy())
		for subject_id: String in base_sheets:
			run.base_sheets[subject_id] = base_sheets[subject_id].copy_for(null)
		return run
