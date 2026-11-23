# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log_writer.gd
# Author:
# Created:  November 18, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name EventLogWriter
extends RefCounted
## The event log's words: turns each [CombatFact] as it plays into the [EventLog]'s lines and
## headers, in present tense, by name ([BattleText]) with tiles as (x, y).[br]
## Every [enum CombatFact.Kind] is in exactly one of [constant GROUP_OF_KIND] (its lines' group),
## [constant HEADER_KINDS] or [constant SILENT_KINDS] (no line of its own; most feed another's);
## [code]tests/ui/battle/hud/event_log_cases.gd[/code] fails on a kind in none.[br]
## [b]Stateful:[/b] a strike's facts make one line, written at its outcome; a move's start tile is
## tracked from the state at [method _init]; a run of darkness deepenings is one line whose count
## rises. Reading only: it never changes the session.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Which filter a line belongs to; [constant NONE] for headers and notes, which always show.
enum Group {
	## No filter: headers and notes.
	NONE = 0,
	## Attacks, counters, other damage, heals, shoves, Exposed, defeats.
	COMBAT = 1,
	## Moves, spawns, reinforcements.
	MOVEMENT = 2,
	## Map objects, items, weapon swaps, runes, waits.
	EVENTS = 3,
	## Activations, modifiers, Block, Stance, stat changes, the darkness advancing.
	EFFECTS = 4,
}

## How an entry is drawn.
enum Tone {
	## A line of its group.
	LINE = 0,
	## A turn and phase header, or the battle's end.
	HEADER = 1,
	## The darkness phase's header, on the darkness-filled row.
	DARKNESS_HEADER = 2,
	## A muted note with no group ("Battle resumed").
	NOTE = 3,
}

## The filter groups in the filter row's order.
const GROUPS: Array[Group] = [Group.COMBAT, Group.MOVEMENT, Group.EVENTS, Group.EFFECTS]

## The group of each kind that writes lines (ui-lift.md, Event log's table).
const GROUP_OF_KIND: Dictionary[CombatFact.Kind, Group] = {
	CombatFact.Kind.ATTACK_MADE: Group.COMBAT,
	CombatFact.Kind.MISSED: Group.COMBAT,
	CombatFact.Kind.DAMAGE_TAKEN: Group.COMBAT,
	CombatFact.Kind.DARKNESS_DAMAGE_TAKEN: Group.COMBAT,
	CombatFact.Kind.HEALED: Group.COMBAT,
	CombatFact.Kind.SHOVED_A_UNIT: Group.COMBAT,
	CombatFact.Kind.EXPOSED: Group.COMBAT,
	CombatFact.Kind.DEFEATED: Group.COMBAT,
	CombatFact.Kind.UNIT_MOVED: Group.MOVEMENT,
	CombatFact.Kind.UNIT_SPAWNED: Group.MOVEMENT,
	CombatFact.Kind.REINFORCEMENT_INCOMING: Group.MOVEMENT,
	CombatFact.Kind.REINFORCEMENT_ARRIVED: Group.MOVEMENT,
	CombatFact.Kind.OBJECT_USED: Group.EVENTS,
	CombatFact.Kind.OBJECT_STATE_CHANGED: Group.EVENTS,
	CombatFact.Kind.ITEM_USED: Group.EVENTS,
	CombatFact.Kind.WEAPON_SWAPPED: Group.EVENTS,
	CombatFact.Kind.RUNE_USED: Group.EVENTS,
	CombatFact.Kind.RUNE_DISCARDED: Group.EVENTS,
	CombatFact.Kind.UNIT_WAITED: Group.EVENTS,
	CombatFact.Kind.EFFECT_ACTIVATED: Group.EFFECTS,
	CombatFact.Kind.MODIFIER_GAINED: Group.EFFECTS,
	CombatFact.Kind.MODIFIER_EXPIRED: Group.EFFECTS,
	CombatFact.Kind.BLOCK_GAINED: Group.EFFECTS,
	CombatFact.Kind.BLOCK_LOST: Group.EFFECTS,
	CombatFact.Kind.STANCE_CHANGED: Group.EFFECTS,
	CombatFact.Kind.DARKNESS_ADVANCED: Group.EFFECTS,
	CombatFact.Kind.STAT_CHANGED: Group.EFFECTS,
	CombatFact.Kind.GROWTH_CHANGED: Group.EFFECTS,
}

## The kinds that write a header.
const HEADER_KINDS: Array[CombatFact.Kind] = [
	CombatFact.Kind.PHASE_START,
	CombatFact.Kind.COMBAT_ENDED,
]

## The kinds with no line of their own, each with why.
const SILENT_KINDS: Dictionary[CombatFact.Kind, String] = {
	CombatFact.Kind.UNIT_TURN_START: "every unit, every phase",
	CombatFact.Kind.UNIT_TURN_END: "every unit, every phase",
	CombatFact.Kind.PHASE_END: "the next phase's header stands for it",
	CombatFact.Kind.BEFORE_COMBAT: "tells an attack from a counter",
	CombatFact.Kind.AFTER_COMBAT: "the exchange's strikes stand for it",
	CombatFact.Kind.HIT_DEALT: "folded into the attack line",
	CombatFact.Kind.HIT_TAKEN: "folded into the attack line",
	CombatFact.Kind.DODGED: "folded into the attack line (the miss)",
	CombatFact.Kind.DAMAGE_DEALT: "folded into the attack line",
	CombatFact.Kind.CRIT_DEALT: "folded into the attack line",
	CombatFact.Kind.CRIT_TAKEN: "folded into the attack line",
	CombatFact.Kind.DEFEATED_AN_ENEMY: "folded into the defeat line",
	CombatFact.Kind.HEALED_AN_ALLY: "folded into the heal line",
	CombatFact.Kind.USED_STAFF_ON_ALLY: "its heal or Block line names the staff's user",
	CombatFact.Kind.SHOVED: "folded into the shove line",
	CombatFact.Kind.BLOCK_STANCE_REFRESHED: "every unit, every phase",
	CombatFact.Kind.COUNTER_CHANGED: "the heirloom bar shows counters (UL8)",
	CombatFact.Kind.UNIT_SENT: "an encounter fact, never on a map's log",
	CombatFact.Kind.UNIT_RETURNED: "an encounter fact, never on a map's log",
	CombatFact.Kind.AID_CALLED: "an encounter fact, never on a map's log",
	CombatFact.Kind.DARKNESS_WAVE_SPREAD: "for mirrors; the darkness spread line stands for it",
}

## The note a resumed battle's log starts with.
const RESUMED_TEXT: String = "Battle resumed"

## A phase header: [code]%d[/code] the turn, [code]%s[/code] the phase's name.
const PHASE_HEADER_FORMAT: String = "Turn %d · %s phase"

## Each side's phase name in [constant PHASE_HEADER_FORMAT].
const PHASE_NAMES: Dictionary[CombatFact.CombatSide, String] = {
	CombatFact.CombatSide.PLAYER: "Player",
	CombatFact.CombatSide.ENEMY: "Enemy",
}

## The darkness phase's name in [constant PHASE_HEADER_FORMAT].
const DARKNESS_PHASE_NAME: String = "Darkness"

## The words for damage by its [enum CombatFact.Source], outside a strike.
const DAMAGE_WORDS: Dictionary[CombatFact.Source, String] = {
	CombatFact.Source.SPLASH: "splash damage",
	CombatFact.Source.BUMP: "bump damage",
	CombatFact.Source.SPIKE: "spike damage",
	CombatFact.Source.DARKNESS: "darkness damage",
}

## The containers a looter empties: an enemy opening or searching one loots it.
const CONTAINERS: Array[MapLayout.ObjectKind] = [
	MapLayout.ObjectKind.CHEST,
	MapLayout.ObjectKind.HOUSE,
	MapLayout.ObjectKind.FOOD_SHELF,
	MapLayout.ObjectKind.BOOK_SHELF,
	MapLayout.ObjectKind.WEAPON_RACK,
]

var _session: CombatSession = null
var _next_id: int = 1

# Each unit's tile as played, for a move's start: seeded from the state at _init, then each move
# and spawn.
var _tiles: Dictionary[String, Vector2i] = {}

# The turn of the last Phase Start played (the state's at _init).
var _turn: int = 0

# The darkness phase as played: between an enemy Phase End and the next Phase Start; its header
# written at its first change (mirrors BattleView._is_darkness_change(): change both together).
var _is_darkness_window: bool = false
var _is_darkness_written: bool = false

# The run of darkness deepenings being counted, and its count; null between runs.
var _spread: Entry = null
var _spread_tiles: int = 0

# The exchange as its Before Combat facts opened it.
var _exchange_attacker: String = ""
var _exchange_defender: String = ""

# The strike under way, from its Attack made to its outcome; _strike_attacker empty when none.
var _strike_attacker: String = ""
var _strike_defender: String = ""
var _strike_is_counter: bool = false
var _strike_hit: int = -1
var _strike_crit: bool = false


func _init(session: CombatSession) -> void:
	_session = session
	if session == null:
		return
	_turn = session.state.turn
	for unit_id: String in session.state.unit_ids():
		_tiles[unit_id] = session.state.tile_of(unit_id)


## The entries [param fact] writes, new or updated (an updated entry keeps its
## [member Entry.id]), in order; empty for none.
func write(fact: CombatFact) -> Array[Entry]:
	var written: Array[Entry] = []
	if _session == null or fact == null:
		return written
	if fact.kind != CombatFact.Kind.DARKNESS_ADVANCED or _is_release(fact):
		_spread = null
	if _ends_strike(fact.kind):
		_append(written, _flush_strike())
	_note_darkness(fact, written)
	match fact.kind:
		CombatFact.Kind.PHASE_START:
			_turn = fact.amount
			_is_darkness_window = false
			_exchange_attacker = ""
			_exchange_defender = ""
			_append(written, _header(PHASE_HEADER_FORMAT % [
				_turn, PHASE_NAMES.get(fact.side, "?"),
			], Tone.HEADER))
		CombatFact.Kind.PHASE_END:
			if fact.side == CombatFact.CombatSide.ENEMY:
				_is_darkness_window = true
				_is_darkness_written = false
		CombatFact.Kind.COMBAT_ENDED:
			var won: bool = fact.side == CombatFact.CombatSide.PLAYER
			_append(written, _header("%s on turn %d" % [
				"Victory" if won else "Defeat", fact.amount,
			], Tone.HEADER))
		CombatFact.Kind.BEFORE_COMBAT:
			var is_reply: bool = (
					fact.actor_id == _exchange_defender and fact.target_id == _exchange_attacker
			)
			if not is_reply:
				_exchange_attacker = fact.actor_id
				_exchange_defender = fact.target_id
		_:
			_write_kind(fact, written)
	return written


## The note a resumed battle starts with ([constant RESUMED_TEXT]).
func resumed_entry() -> Entry:
	var entry: Entry = _new_entry(Group.NONE, Tone.NOTE)
	entry.add(RESUMED_TEXT)
	return entry


## The display name of filter [param group].
static func group_name(group: Group) -> String:
	return (Group.find_key(group) as String).capitalize()


func _write_kind(fact: CombatFact, written: Array[Entry]) -> void:
	match GROUP_OF_KIND.get(fact.kind, Group.NONE):
		Group.COMBAT:
			_write_combat(fact, written)
		Group.MOVEMENT:
			_append(written, _movement_line(fact))
		Group.EVENTS:
			_append(written, _event_line(fact))
		Group.EFFECTS:
			_write_effect(fact, written)
		_:
			_note_strike(fact)


# Hit taken and Crit taken fill the strike under way; the other silent kinds write nothing.
func _note_strike(fact: CombatFact) -> void:
	if _strike_attacker.is_empty() or fact.actor_id != _strike_defender:
		return
	if fact.kind == CombatFact.Kind.HIT_TAKEN:
		_strike_hit = fact.amount
	elif fact.kind == CombatFact.Kind.CRIT_TAKEN:
		_strike_crit = true


# --- Combat -----------------------------------------------------------------------------------


func _write_combat(fact: CombatFact, written: Array[Entry]) -> void:
	match fact.kind:
		CombatFact.Kind.ATTACK_MADE:
			_strike_attacker = fact.actor_id
			_strike_defender = fact.target_id
			_strike_is_counter = (
					fact.actor_id == _exchange_defender and fact.target_id == _exchange_attacker
			)
			_strike_hit = -1
			_strike_crit = false
		CombatFact.Kind.MISSED:
			if fact.actor_id == _strike_attacker:
				_append(written, _strike_line("miss"))
				_strike_attacker = ""
		CombatFact.Kind.DAMAGE_TAKEN:
			var is_strike: bool = (
					fact.source == CombatFact.Source.ATTACK
					and not _strike_attacker.is_empty()
					and fact.actor_id == _strike_defender
			)
			if is_strike:
				_append(written, _strike_line(_strike_outcome(fact)))
				_strike_attacker = ""
			else:
				_append(written, _damage_line(fact))
		CombatFact.Kind.DARKNESS_DAMAGE_TAKEN:
			var entry: Entry = _line(Group.COMBAT)
			entry.add("%s takes %d darkness damage" % [_name(fact.actor_id), fact.amount])
			_append(written, entry)
		CombatFact.Kind.HEALED:
			_append(written, _heal_line(fact))
		CombatFact.Kind.SHOVED_A_UNIT:
			_append(written, _line(Group.COMBAT).add("%s shoves %s" % [
				_name(fact.actor_id), _name(fact.target_id),
			]))
		CombatFact.Kind.EXPOSED:
			_append(written, _line(Group.COMBAT).add("%s is Exposed" % [_name(fact.actor_id)]))
		CombatFact.Kind.DEFEATED:
			# A breakable's end is its object's line ("breaks", "explodes").
			if _session.state.side_of(fact.actor_id) == CombatFact.CombatSide.NONE:
				return
			var entry: Entry = _line(Group.COMBAT)
			if fact.target_id.is_empty():
				entry.add("%s is defeated" % [_name(fact.actor_id)])
			else:
				entry.add("%s defeats %s" % [_name(fact.target_id), _name(fact.actor_id)])
			_append(written, entry)


# A strike's damage as the board shows it: past Block, overkill included, with what Block took.
func _strike_outcome(fact: CombatFact) -> String:
	var past_block: int = fact.hp_amount
	if _strike_hit >= 0:
		past_block = maxi(_strike_hit - fact.block_amount, 0)
	var outcome: String = "%d damage" % [past_block]
	if _strike_crit:
		outcome += ", crit"
	if fact.block_amount > 0:
		outcome += " (%d blocked)" % [fact.block_amount]
	return outcome


func _strike_line(outcome: String) -> Entry:
	return _line(Group.COMBAT).add("%s %s %s: %s" % [
		_name(_strike_attacker),
		"counters" if _strike_is_counter else "attacks",
		_name(_strike_defender),
		outcome,
	])


# A strike that ended with no miss and no damage through (fully countered): "no damage".
func _flush_strike() -> Entry:
	if _strike_attacker.is_empty():
		return null
	var entry: Entry = _strike_line("no damage, crit" if _strike_crit else "no damage")
	_strike_attacker = ""
	return entry


func _damage_line(fact: CombatFact) -> Entry:
	var words: String = DAMAGE_WORDS.get(fact.source, "damage")
	var entry: Entry = _line(Group.COMBAT).add("%s takes %d %s" % [
		_name(fact.actor_id), fact.amount, words,
	])
	if fact.block_amount > 0:
		entry.add(" (%d blocked)" % [fact.block_amount])
	_add_source(entry, fact)
	return entry


func _heal_line(fact: CombatFact) -> Entry:
	var entry: Entry = _line(Group.COMBAT)
	var is_by_unit: bool = (
			not fact.target_id.is_empty()
			and fact.target_id != fact.actor_id
			and _session.state.has_unit(fact.target_id)
	)
	if is_by_unit:
		entry.add("%s heals %s: +%d HP" % [
			_name(fact.target_id), _name(fact.actor_id), fact.hp_amount,
		])
		return entry
	entry.add("%s regains %d HP" % [_name(fact.actor_id), fact.hp_amount])
	_add_source(entry, fact)
	return entry


# --- Movement ---------------------------------------------------------------------------------


func _movement_line(fact: CombatFact) -> Entry:
	var entry: Entry = _line(Group.MOVEMENT)
	match fact.kind:
		CombatFact.Kind.UNIT_MOVED:
			var from: Vector2i = _tiles.get(fact.actor_id, CombatFact.NO_TILE)
			_tiles[fact.actor_id] = fact.tile
			var verb: String = "is moved"
			if (fact.flags & CombatFact.Flag.SECOND_MOVE) != 0:
				verb = "moves again"
			elif fact.amount > 0:
				verb = "moves"
			entry.add("%s %s " % [_name(fact.actor_id), verb])
			if from == CombatFact.NO_TILE:
				entry.add("to ").add_tile(fact.tile)
			else:
				entry.add_tile(from).add(" → ").add_tile(fact.tile)
		CombatFact.Kind.UNIT_SPAWNED:
			_tiles[fact.actor_id] = fact.tile
			entry.add("%s appears at " % [_name(fact.actor_id)]).add_tile(fact.tile)
		CombatFact.Kind.REINFORCEMENT_INCOMING:
			entry.add("Reinforcements at ").add_tile(fact.tile)
			if fact.amount <= 1:
				entry.add(" next turn")
			else:
				entry.add(" in %d turns" % [fact.amount])
			if not fact.unit_types.is_empty():
				entry.add(": %s" % [", ".join(_type_names(fact.unit_types))])
		CombatFact.Kind.REINFORCEMENT_ARRIVED:
			var arrive: String = (
					"reinforcement arrives" if fact.amount == 1 else "reinforcements arrive"
			)
			entry.add("%d %s at " % [fact.amount, arrive]).add_tile(fact.tile)
	return entry


# --- Events -----------------------------------------------------------------------------------


func _event_line(fact: CombatFact) -> Entry:
	var entry: Entry = _line(Group.EVENTS)
	var actor: String = _name(fact.actor_id)
	match fact.kind:
		CombatFact.Kind.OBJECT_USED:
			entry.add("%s uses %s at " % [actor, _name(fact.target_id)]).add_tile(fact.tile)
			if not fact.item_id.is_empty():
				entry.add(" with %s" % [_name(fact.item_id)])
		CombatFact.Kind.OBJECT_STATE_CHANGED:
			_object_line(fact, entry)
		CombatFact.Kind.ITEM_USED:
			if fact.target_id.is_empty() or fact.target_id == fact.actor_id:
				entry.add("%s uses %s" % [actor, _name(fact.item_id)])
			else:
				entry.add("%s uses %s on %s" % [
					actor, _name(fact.item_id), _name(fact.target_id),
				])
		CombatFact.Kind.WEAPON_SWAPPED:
			entry.add("%s swaps to %s" % [actor, _name(fact.item_id)])
		CombatFact.Kind.RUNE_USED:
			entry.add("%s cast" % [_name(fact.item_id)])
			if _session.state.has_unit(fact.target_id):
				entry.add(" on %s" % [_name(fact.target_id)])
			if fact.tile != CombatFact.NO_TILE:
				entry.add(" at " if not _session.state.has_unit(fact.target_id) else " ")
				entry.add_tile(fact.tile)
		CombatFact.Kind.RUNE_DISCARDED:
			entry.add("%s discarded" % [_name(fact.item_id)])
		CombatFact.Kind.UNIT_WAITED:
			entry.add("%s waits" % [actor])
	return entry


# A map object's change: the object is the actor, what caused it the target.
# Closing, searching, lighting, dousing, breaking, a point's closing, the darkness's touch and
# erosion, and a thrown keg's landing (the target its thrower) and fuse are worded as opening,
# looting and exploding are.
func _object_line(fact: CombatFact, entry: Entry) -> void:
	var object_name: String = _name(fact.actor_id)
	var by: String = ""
	if _session.state.has_unit(fact.target_id):
		by = _name(fact.target_id)
	var is_looter: bool = (
			not by.is_empty()
			and _session.state.side_of(fact.target_id) == CombatFact.CombatSide.ENEMY
			and CONTAINERS.has(_object_kind(fact.actor_id))
	)
	match fact.key:
		MapObjects.Change.OPENED, MapObjects.Change.SEARCHED:
			var verb: String = "opens" if fact.key == MapObjects.Change.OPENED else "searches"
			if is_looter:
				verb = "loots"
			if by.is_empty():
				var is_opened: bool = fact.key == MapObjects.Change.OPENED
				var passive: String = "opens" if is_opened else "is searched"
				entry.add("%s at " % [object_name]).add_tile(fact.tile).add(" %s" % [passive])
			else:
				entry.add("%s %s %s at " % [by, verb, object_name]).add_tile(fact.tile)
		MapObjects.Change.CLOSED:
			entry.add("%s at " % [object_name]).add_tile(fact.tile).add(" closes")
		MapObjects.Change.LIT, MapObjects.Change.DOUSED:
			var is_lit: bool = fact.key == MapObjects.Change.LIT
			if by.is_empty():
				entry.add("%s at " % [object_name]).add_tile(fact.tile)
				entry.add(" is lit" if is_lit else " is doused")
			else:
				entry.add("%s %s %s at " % [by, "lights" if is_lit else "douses", object_name])
				entry.add_tile(fact.tile)
		MapObjects.Change.DESTROYED:
			var is_keg: bool = _object_kind(fact.actor_id) == MapLayout.ObjectKind.POWDER_KEG
			entry.add("%s at " % [object_name]).add_tile(fact.tile)
			entry.add(" explodes" if is_keg else " breaks")
		MapObjects.Change.POINT_CLOSED:
			if by.is_empty():
				entry.add("The reinforcement point at ").add_tile(fact.tile).add(" closes")
			else:
				entry.add("%s closes the reinforcement point at " % [by]).add_tile(fact.tile)
		MapObjects.Change.CONTACTED:
			entry.add("The darkness touches %s at " % [object_name]).add_tile(fact.tile)
			entry.add(" (%d %s)" % [fact.amount, "turn" if fact.amount == 1 else "turns"], true)
		MapObjects.Change.ERODED:
			entry.add("The darkness erodes %s at " % [object_name]).add_tile(fact.tile)
		MapObjects.Change.LANDED:
			if by.is_empty():
				entry.add("%s lands at " % [object_name])
			else:
				entry.add("%s throws %s: it lands at " % [by, object_name])
			entry.add_tile(fact.tile).add(", lit")
		MapObjects.Change.FUSE_BURNED:
			entry.add("%s's fuse burns down" % [object_name])
			entry.add(" (%d left)" % [fact.amount], true)
		_:
			entry.add("%s at " % [object_name]).add_tile(fact.tile).add(" changes")


# --- Effects ----------------------------------------------------------------------------------


func _write_effect(fact: CombatFact, written: Array[Entry]) -> void:
	var actor: String = _name(fact.actor_id)
	match fact.kind:
		CombatFact.Kind.EFFECT_ACTIVATED:
			_append(written, _activation_line(fact))
		CombatFact.Kind.MODIFIER_GAINED, CombatFact.Kind.MODIFIER_EXPIRED:
			_append(written, _modifier_line(fact))
		CombatFact.Kind.BLOCK_GAINED:
			if fact.amount <= 0:
				return
			var entry: Entry = _line(Group.EFFECTS).add("%s gains %d Block" % [actor, fact.amount])
			_add_source(entry, fact)
			_append(written, entry)
		CombatFact.Kind.BLOCK_LOST:
			var entry: Entry = _line(Group.EFFECTS).add("%s loses %d Block" % [
				actor, absi(fact.amount),
			])
			_add_source(entry, fact)
			_append(written, entry)
		CombatFact.Kind.STANCE_CHANGED:
			if fact.amount == 0:
				return
			var entry: Entry = _line(Group.EFFECTS).add("%s %s %d Stance" % [
				actor, "gains" if fact.amount > 0 else "loses", absi(fact.amount),
			])
			_add_source(entry, fact)
			_append(written, entry)
		CombatFact.Kind.STAT_CHANGED:
			var entry: Entry = _line(Group.EFFECTS).add("%s's %s %+d" % [
				actor, _stat_name(fact.key), fact.amount,
			])
			_add_source(entry, fact)
			_append(written, entry)
		CombatFact.Kind.GROWTH_CHANGED:
			var entry: Entry = _line(Group.EFFECTS).add("%s's %s growth %+d%%" % [
				actor, _stat_name(fact.key), fact.amount,
			])
			_add_source(entry, fact)
			_append(written, entry)
		CombatFact.Kind.DARKNESS_ADVANCED:
			_darkness_line(fact, written)


# "Drengr's Iron Skin activates": the unit first. A rune's and a map object's activations are
# their cast and object lines; an army's (heirlooms, curses) is the army's.
func _activation_line(fact: CombatFact) -> Entry:
	var instance: EffectInstance = _session.engine.get_instance(fact.source_effect_id)
	var effect_name: String = _effect_name(fact.source_effect_id)
	if instance != null:
		match instance.owner.kind:
			EffectOwner.Kind.RUNE, EffectOwner.Kind.MAP_OBJECT:
				return null
			EffectOwner.Kind.ARMY:
				# An heirloom or curse has no unit, so the army stands first.
				return _line(Group.EFFECTS).add("The army's %s activates" % [effect_name])
	if not _session.state.has_unit(fact.actor_id):
		return _line(Group.EFFECTS).add("%s activates" % [effect_name])
	return _line(Group.EFFECTS).add("%s's %s activates" % [_name(fact.actor_id), effect_name])


# "Drengr gains +2 MGT until Phase End (Battle Cry)", "Drengr's Battle Cry wears off (+2 MGT)".
# The duration is the effect text's (AddTimedModifier), not "for 2 turns".
func _modifier_line(fact: CombatFact) -> Entry:
	var actor: String = _name(fact.actor_id)
	var effect_name: String = _effect_name(fact.source_effect_id)
	var modifier: AddTimedModifier = _timed_modifier(fact)
	var entry: Entry = _line(Group.EFFECTS)
	var change: String = ""
	var is_permission: bool = false
	if modifier != null:
		change = EffectTerms.describe_modifier(modifier.key, modifier.mode, modifier.value)
		is_permission = (
				modifier.mode == Modifier.Mode.GRANT or modifier.mode == Modifier.Mode.DENY
		)
	if fact.kind == CombatFact.Kind.MODIFIER_EXPIRED:
		entry.add("%s's %s wears off" % [actor, effect_name])
		if not change.is_empty():
			entry.add(" (%s)" % [change], true)
		return entry
	if change.is_empty():
		return entry.add("%s gains %s" % [actor, effect_name])
	var duration: String = modifier.describe_duration()
	entry.add("%s %s%s %s" % [actor, "" if is_permission else "gains ", change, duration])
	entry.add(" (%s)" % [effect_name], true)
	return entry


func _darkness_line(fact: CombatFact, written: Array[Entry]) -> void:
	if _is_release(fact):
		var arrived: bool = (fact.flags & CombatFact.Flag.DARKNESS_ARRIVED) != 0
		_append(written, _line(Group.EFFECTS).add(
				"The darkness arrives" if arrived else "A darkness wave rises"
		))
		return
	if _spread == null:
		_spread = _line(Group.EFFECTS)
		_spread_tiles = 0
	_spread_tiles += 1
	_spread.pieces.clear()
	_spread.muted.clear()
	_spread.add("The darkness spreads: %d %s" % [
		_spread_tiles, "tile deepens" if _spread_tiles == 1 else "tiles deepen",
	])
	_append(written, _spread)


# The darkness phase's header, at its first change of anything (a hurt, a deepening or release,
# an erosion), as BattleView announces it.
func _note_darkness(fact: CombatFact, written: Array[Entry]) -> void:
	if not _is_darkness_window or _is_darkness_written or not _is_darkness_change(fact):
		return
	_is_darkness_written = true
	_append(written, _header(
			PHASE_HEADER_FORMAT % [_turn, DARKNESS_PHASE_NAME], Tone.DARKNESS_HEADER
	))


# --- Helpers ----------------------------------------------------------------------------------


func _new_entry(group: Group, tone: Tone) -> Entry:
	var entry: Entry = Entry.new()
	entry.id = _next_id
	entry.group = group
	entry.tone = tone
	_next_id += 1
	return entry


func _line(group: Group) -> Entry:
	return _new_entry(group, Tone.LINE)


func _header(text: String, tone: Tone) -> Entry:
	return _new_entry(Group.NONE, tone).add(text)


func _name(id: String) -> String:
	return BattleText.name_of(_session, id)


# A carrier's display name ("Iron Skin"), else its definition's id, readable.
func _effect_name(effect_id: String) -> String:
	var instance: EffectInstance = _session.engine.get_instance(effect_id)
	if instance == null:
		return "an effect"
	if not instance.label.is_empty():
		return instance.label
	if instance.definition != null and not instance.definition.id.is_empty():
		return instance.definition.id.capitalize()
	return "an effect"


# What caused an amount, in parentheses: its effect, else the other party.
func _add_source(entry: Entry, fact: CombatFact) -> void:
	var source: String = ""
	if not fact.source_effect_id.is_empty():
		source = _effect_name(fact.source_effect_id)
	elif not fact.target_id.is_empty() and fact.target_id != fact.actor_id:
		source = _name(fact.target_id)
	if not source.is_empty():
		entry.add(" (%s)" % [source], true)


# The AddTimedModifier a modifier fact names: its effect's operation at the fact's key.
func _timed_modifier(fact: CombatFact) -> AddTimedModifier:
	var instance: EffectInstance = _session.engine.get_instance(fact.source_effect_id)
	if instance == null or instance.definition == null:
		return null
	var operations: Array[EffectOperation] = instance.definition.operations
	if fact.key < 0 or fact.key >= operations.size():
		return null
	return operations[fact.key] as AddTimedModifier


func _object_kind(object_id: String) -> MapLayout.ObjectKind:
	var object: MapState.ObjectState = _session.state.map.objects.get(object_id, null)
	return MapLayout.ObjectKind.NONE if object == null else object.kind


func _type_names(types: PackedStringArray) -> PackedStringArray:
	var names: PackedStringArray = []
	for type_id: String in types:
		var enemy: EnemyClassDefinition = EffectCatalog.enemy_class(type_id)
		if enemy != null and not enemy.display_name.is_empty():
			names.append(enemy.display_name)
			continue
		var unit: UnitTypeDefinition = EffectCatalog.unit_type(type_id)
		if unit != null and not unit.display_name.is_empty():
			names.append(unit.display_name)
		else:
			names.append(type_id.capitalize())
	return names


func _ends_strike(kind: CombatFact.Kind) -> bool:
	return kind in [
		CombatFact.Kind.ATTACK_MADE, CombatFact.Kind.AFTER_COMBAT, CombatFact.Kind.BEFORE_COMBAT,
		CombatFact.Kind.PHASE_START, CombatFact.Kind.PHASE_END, CombatFact.Kind.UNIT_TURN_END,
		CombatFact.Kind.COMBAT_ENDED,
	]


static func _append(written: Array[Entry], entry: Entry) -> void:
	if entry != null:
		written.append(entry)


static func _is_release(fact: CombatFact) -> bool:
	return (
			fact.kind == CombatFact.Kind.DARKNESS_ADVANCED
			and (fact.flags & CombatFact.Flag.DARKNESS_RELEASED) != 0
	)


static func _is_darkness_change(fact: CombatFact) -> bool:
	match fact.kind:
		CombatFact.Kind.DARKNESS_DAMAGE_TAKEN, CombatFact.Kind.DARKNESS_ADVANCED:
			return true
		CombatFact.Kind.OBJECT_STATE_CHANGED:
			return fact.key == MapObjects.Change.CONTACTED or fact.key == MapObjects.Change.ERODED
	return false


static func _stat_name(stat: int) -> String:
	if stat == CombatValue.HIT_STAT:
		return "Hit"
	var found: Variant = CombatValue.Stat.find_key(stat)
	return "stat %d" % [stat] if found == null else (found as String)


## One line or header: its text in pieces, each drawn plain or muted (tiles, sources).
class Entry:
	extends RefCounted

	## Unique within its writer; an entry written again with the same id replaces the first.
	var id: int = 0
	## Its filter; [constant Group.NONE] always shows.
	var group: Group = Group.NONE
	## How it is drawn.
	var tone: Tone = Tone.LINE
	## The text, in order.
	var pieces: PackedStringArray = []
	## Whether each piece is drawn muted.
	var muted: Array[bool] = []

	## Adds [param text], muted when [param is_muted]. Returns this entry.
	func add(text: String, is_muted: bool = false) -> Entry:
		pieces.append(text)
		muted.append(is_muted)
		return self

	## Adds [param tile] as "(x, y)", muted. Returns this entry.
	func add_tile(tile: Vector2i) -> Entry:
		return add("(%d, %d)" % [tile.x, tile.y], true)

	## The whole text, unstyled.
	func text() -> String:
		return "".join(pieces)
