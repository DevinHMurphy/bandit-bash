# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_screen_fixture.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Shared setup for the event screen's cases and captures: test-only events built in code (none
## is real content: EV4 authors the 13), runs standing in an Unknown node with one open (through
## tests/events/event_fixture.gd), and an [EventPanel] laid out at 1280×720 whose commands go to
## the run as the screen sends them, refreshing or showing the rejection. Presses keys, pad
## buttons and clicks on the root viewport, and walks focus to a control by key or d-pad.[br]
## Every event but the forge uses the loaded catalog's content alone, so a run saved with one
## resumes on the game's catalog; the forge needs the base fixture's test-only prefix.

const EventFixture = preload("res://tests/events/event_fixture.gd")
const PANEL_SCENE: PackedScene = preload("res://ui/campaign/events/event_panel.tscn")

## The layout the panel runs at: the project's base viewport.
const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

## The trials: 0 "Steady Hand" (a chosen unit +2 MGT), 1 "Temper the Blade" (a chosen weapon
## +2 weight), 2 "Take the Prize" (a random rare weapon and a minor curse).
const TRIALS: String = "test_trials"
const STEADY_HAND: int = 0
const TEMPER: int = 1
const PRIZE: int = 2
const MGT_GAIN: int = 2
const WEIGHT_GAIN: float = 2.0

## The rune stone: 0 "Rune Stone" (a random rune), 1 "Pay the Tithe" (pay 500, needs 500, so
## a new run greys it out), 2 "Walk Away".
const RUNES: String = "test_runes"
const RUNE_STONE: int = 0
const TITHE: int = 1
const WALK_AWAY: int = 2
const TITHE_GOLD: int = 500

## The shrine: 0 "Offer a Prayer" (revive a fallen unit; needs one), 1 "Claim the Relic" (a
## rare heirloom).
const SHRINE: String = "test_shrine"
const PRAYER: int = 0

## The toll, a team choice: 0 "Pay" (-30 gold, needs 30), 1 "Fight" (a surprise combat), 2
## "Intimidate" (+40 gold and a minor curse).
const TOLL: String = "test_toll"
const PAY: int = 0
const FIGHT: int = 1
const INTIMIDATE: int = 2
const TOLL_GOLD: int = 30
const LOOT_GOLD: int = 40

## The mirror: 0 "Face Yourself" (re-roll a chosen unit's prefix: never the commander's), 1
## "Walk Away".
const MIRROR: String = "test_mirror"

## The forge: 0 "Heavy Bow" (the base fixture's bow-only test prefix on a chosen weapon), 1
## "Walk Away". Needs the base fixture's catalog.
const FORGE: String = "test_forge"

const MINOR: String = "minor"
const RARE: String = "rare"

# Presses a direction may take to walk focus to a control before it counts as unreachable.
const MAX_STEPS: int = 12

## The base event fixture: its test catalog, sessions and commands.
var base: EventFixture = EventFixture.new()

## The pool of the event [method session_with] last opened.
var pool: EventPool = null

## Every command the panels built, in order, and the batch of the last one sent.
var commands: Array[CampaignCommand] = []
var last_batch: CampaignBatch = null

var _root: Window = null


## [param root]: the root viewport, where panels are added and input is pushed. Null for a
## caller that only builds events.
func _init(root: Window = null) -> void:
	_root = root


## A new Mercenary run of [param seat_count] seats inside an Unknown node, with [param event] open
## from a pool of it alone ([member pool]). [param fallen] first moves each seat's first soldier
## to the fallen list; [param full_runes] fills every rune slot.
func session_with(
		event: EventDefinition,
		seat_count: int = 1,
		fallen: bool = false,
		full_runes: bool = false
) -> CampaignSession:
	var made: CampaignSession = base.unknown_session(seat_count)
	for seat: int in made.run.seat_numbers():
		var seat_run: SeatRun = made.run.seat_run(seat)
		if fallen:
			base.fell(seat_run, base.soldier(seat_run))
		if full_runes:
			fill_rune_slots(made, seat_run)
	pool = EventPool.new([event])
	last_batch = base.open(made, pool)
	return made


## Fills every rune slot of [param seat_run] with a rune of the catalog, in id order.
func fill_rune_slots(made: CampaignSession, seat_run: SeatRun) -> void:
	var runes: Array[Resource] = base.catalog.all_of(EffectCatalog.Kind.RUNE)
	for index: int in seat_run.rune_slots.size():
		var rune: RuneDefinition = runes[index % runes.size()] as RuneDefinition
		seat_run.rune_slots[index] = SeatRun.RuneSlot.new(made.ids.next_rune_id(rune.id), rune.id)


## A panel on [param seat]'s part of [param made]'s open event ([member pool], the base catalog),
## laid out at [constant SCREEN_SIZE], its commands sent to the run as the screen sends them.
func open_panel(made: CampaignSession, seat: int = 0) -> EventPanel:
	var panel: EventPanel = PANEL_SCENE.instantiate()
	_root.add_child(panel)
	# Anchored top-left, so its size holds at SCREEN_SIZE whatever the window is.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = SCREEN_SIZE
	panel.command_ready.connect(_on_panel_command_ready.bind(panel, made))
	panel.open(made, seat, pool, base.catalog)
	lay_out(panel)
	panel.focus_first()
	return panel


## Removes and frees [param panel].
func close_panel(panel: EventPanel) -> void:
	_root.remove_child(panel)
	panel.free()


## Sorts [param control]'s containers twice, parents first, as a frame's deferred sort would.
func lay_out(control: Control) -> void:
	for _pass: int in 2:
		for node: Node in control.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


## Presses [param target] with [param device] ("key", "mouse" or "pad"): a click on it, or focus
## walked to it from the focused control along [param direction] ("right" or "down") by arrow
## key or d-pad, then Enter or A. Returns false, pressing nothing, when focus can't reach it.
func press(device: String, target: Control, direction: String = "right") -> bool:
	if device == "mouse":
		click(target)
		return true
	for _step: int in MAX_STEPS:
		if _root.gui_get_focus_owner() == target:
			break
		if device == "key":
			press_key(KEY_RIGHT if direction == "right" else KEY_DOWN)
		else:
			press_pad(JOY_BUTTON_DPAD_RIGHT if direction == "right" else JOY_BUTTON_DPAD_DOWN)
	if _root.gui_get_focus_owner() != target:
		return false
	if device == "key":
		press_key(KEY_ENTER)
	else:
		press_pad(JOY_BUTTON_A)
	return true


## Backs out with [param device]: Esc, B, or a click on [param back_button].
func back(device: String, back_button: Control) -> void:
	match device:
		"key":
			press_key(KEY_ESCAPE)
		"pad":
			press_pad(JOY_BUTTON_B)
		_:
			click(back_button)


## A left click at the middle of [param control], its panel laid out first.
func click(control: Control) -> void:
	var panel: Control = control
	while panel != null and not panel is EventPanel:
		panel = panel.get_parent_control()
	if panel != null:
		lay_out(panel)
	var point: Vector2 = control.get_global_rect().get_center()
	for is_down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_down
		_root.push_input(event, true)


## A press and release of [param key], by its physical position and its keycode.
func press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = is_down
		_root.push_input(event, true)


## A press and release of the pad's [param button].
func press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		_root.push_input(event, true)


## The first of [param buttons] whose text starts with [param prefix]; null for none.
static func button_starting(buttons: Array[Button], prefix: String) -> Button:
	for button: Button in buttons:
		if button.text.begins_with(prefix):
			return button
	return null


## The trials (see [constant TRIALS]).
static func trials() -> EventDefinition:
	var steady: StatOutcome = StatOutcome.new()
	steady.target = EventOutcome.Target.CHOSEN
	steady.stat = CombatValue.Stat.MGT
	steady.amount = MGT_GAIN
	var temper: ItemModificationOutcome = ItemModificationOutcome.new()
	temper.stat_deltas = {CombatValue.Key.NET_WEIGHT: WEIGHT_GAIN}
	var prize: ItemGrantOutcome = ItemGrantOutcome.new()
	prize.random = ItemGrantOutcome.RandomItem.RARE_WEAPON
	return _event(TRIALS, "Trial of the Three Doors", false, [
		_option("Steady Hand", "A chosen unit gains +2 MGT.", [steady]),
		_option("Temper the Blade", "A chosen weapon gains +2 weight.", [temper]),
		_option("Take the Prize", "Gain a random rare weapon.", [prize], null, MINOR),
	])


## The rune stone (see [constant RUNES]).
static func runes() -> EventDefinition:
	var stone: RuneOutcome = RuneOutcome.new()
	stone.is_random = true
	var tithe: GoldOutcome = GoldOutcome.new()
	tithe.amount = -TITHE_GOLD
	var needs: EventRequirements = EventRequirements.new()
	needs.gold = TITHE_GOLD
	return _event(RUNES, "The Humming Stone", false, [
		_option("Rune Stone", "Gain a random rune.", [stone]),
		_option("Pay the Tithe", "Pay 500 gold.", [tithe], needs),
		_option("Walk Away", "Nothing happens.", []),
	])


## The shrine (see [constant SHRINE]).
static func shrine() -> EventDefinition:
	var needs: EventRequirements = EventRequirements.new()
	needs.needs_fallen_unit = true
	var relic: HeirloomOutcome = HeirloomOutcome.new()
	relic.tier = RARE
	var event: EventDefinition = _event(SHRINE, "A Broken Shrine", false, [
		_option("Offer a Prayer", "One fallen unit returns at critical health.", [
			ReviveOutcome.new(),
		], needs),
		_option("Claim the Relic", "Gain a rare heirloom.", [relic]),
	])
	event.eligibility = EventDefinition.Eligibility.FALLEN_UNIT
	return event


## The toll (see [constant TOLL]).
static func toll() -> EventDefinition:
	var pay: GoldOutcome = GoldOutcome.new()
	pay.amount = -TOLL_GOLD
	var needs: EventRequirements = EventRequirements.new()
	needs.gold = TOLL_GOLD
	var loot: GoldOutcome = GoldOutcome.new()
	loot.amount = LOOT_GOLD
	return _event(TOLL, "A Toll on the Road", true, [
		_option("Pay", "Each player loses 30 gold.", [pay], needs),
		_option("Fight", "A surprise Standard combat for the whole team.", [
			SurpriseCombatOutcome.new(),
		]),
		_option("Intimidate", "Each player gains 40 gold.", [loot], null, MINOR),
	])


## The mirror (see [constant MIRROR]).
static func mirror() -> EventDefinition:
	return _event(MIRROR, "A Mirror of Doubt", false, [
		_option("Face Yourself", "Re-roll a chosen unit's prefix.", [PrefixRerollOutcome.new()]),
		_option("Walk Away", "Nothing happens.", []),
	])


## The forge (see [constant FORGE]).
static func forge() -> EventDefinition:
	var heavy: WeaponPrefixOutcome = WeaponPrefixOutcome.new()
	heavy.prefix_id = EventFixture.HEAVY_BOW
	return _event(FORGE, "A Cold Forge", false, [
		_option("Heavy Bow", "A chosen bow becomes Heavy.", [heavy]),
		_option("Walk Away", "Nothing happens.", []),
	])


func _on_panel_command_ready(
		command: CampaignCommand, panel: EventPanel, made: CampaignSession
) -> void:
	commands.append(command)
	last_batch = made.submit(command) if command != null else null
	if last_batch == null or last_batch.is_rejected():
		panel.show_problem("Can't do that: %s." % [
			last_batch.rejected_reason if last_batch != null else "no command",
		])
		return
	panel.refresh()


static func _event(
		id: String, title: String, is_team: bool, options: Array[EventOption]
) -> EventDefinition:
	var event: EventDefinition = EventDefinition.new()
	event.id = id
	event.title = title
	event.text = "A test-only event: %s. Its options try each part of the event screen." % [id]
	event.is_team_choice = is_team
	event.options = options
	return event


static func _option(
		title: String,
		text: String,
		outcomes: Array[EventOutcome],
		requirements: EventRequirements = null,
		curse_tier: String = ""
) -> EventOption:
	var option: EventOption = EventOption.new()
	option.title = title
	option.text = text
	option.outcomes = outcomes
	option.requirements = requirements
	option.curse_tier = curse_tier
	return option
