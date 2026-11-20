# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_usable_by.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ItemUsableBy
extends HBoxContainer
## Who can use an offered item, at the bottom right of its [ItemOfferCard]. For a weapon: an
## [ItemUserIcon] for each of the seat's living units that can wield it ([method wielders]), in
## army order, at most [member max_icons], then "+n"; [member no_unit_text] when none can.
## Equipment and Pouch items fit any unit, so they show [member any_unit_text] instead.[br]
## The mouse over an icon shows its unit's name in a [GameTooltip]; over "+n", the names it hides.
## [method show_names_tip] lists every name, for the card's keyboard and pad focus. Shows only:
## takes no focus and reads no input.
##
## @tutorial(RF-032): docs/design/rebalance-and-features.md

const ICON_SCENE: PackedScene = preload("res://ui/campaign/item_user_icon.tscn")

## The unit sprites by unit type, as the board's tokens draw them.[br]
## [b]Unset:[/b] every icon shows its unit's initial.
@export var sprites: UnitSpriteTable = null

## The most icons shown; the rest are counted in "+n".[br]
## [b]1:[/b] one icon, then the count.
@export_range(1, 8, 1) var max_icons: int = 4

## Shown instead of icons for an item every unit can use (Equipment, Pouch items).
@export var any_unit_text: String = "Any unit"

# The wording (P15 question 24); RF-032 says only that such a weapon says so.
## Shown instead of icons for a weapon none of the seat's living units can wield.
@export var no_unit_text: String = "No unit can wield it"

## The count after the icons: [code]%d[/code] the units not shown.
@export var more_format: String = "+%d"

# The wording (P15 question 24); RF-032 sets none.
## The tooltip's heading over a list of names, on the card's focus or over "+n".
@export var names_title: String = "Can wield it"

# The gap (P15 question 24): the heirloom bar's; ui-style.md sets no distance.
## The space between the row's bottom edge and its tooltip.[br]
## [b]Units:[/b] base units. [b]0.0:[/b] the tooltip touches the row. 4 matches the heirloom bar's.
@export_range(0.0, 32.0, 1.0) var tooltip_gap: float = 4.0

# Every wielder's name in army order; empty for an item any unit uses, or none can wield.
var _names: PackedStringArray = []

@onready var _icons: HBoxContainer = %Icons
@onready var _more: Label = %More
@onready var _note: Label = %Note
@onready var _tooltip: GameTooltip = %Tooltip


func _ready() -> void:
	_tooltip.visible = false
	_more.mouse_entered.connect(_on_more_mouse_entered)
	_more.mouse_exited.connect(hide_tip)
	# A card's focus shows the tooltip while its row is still settling (cards refit over a few
	# frames), so the tooltip follows the row wherever it moves or grows.
	set_notify_transform(true)
	resized.connect(_place_tip)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_place_tip()


## Shows who of [param seat_run]'s living units can use [param definition], read from
## [param catalog] and named through [param ids] (null: by unit type). Hidden when
## [param seat_run] or [param definition] is null.
func show_users(
		definition: ItemDefinition,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator,
) -> void:
	for child: Node in _icons.get_children():
		_icons.remove_child(child)
		child.queue_free()
	_names.clear()
	hide_tip()
	visible = seat_run != null and definition != null and catalog != null
	if not visible:
		return
	var is_weapon: bool = definition is WeaponDefinition
	var units: Array[UnitInstance] = []
	if is_weapon:
		units = wielders(definition, seat_run, catalog)
	for index: int in units.size():
		var unit: UnitInstance = units[index]
		var shown_name: String = CombatResultsModel.unit_name(
				ids, seat_run, unit.instance_id, catalog
		)
		_names.append(shown_name)
		if index >= max_icons:
			continue
		var icon: ItemUserIcon = ICON_SCENE.instantiate()
		_icons.add_child(icon)
		var sprite: Texture2D = null if sprites == null else sprites.sprite_for(unit.unit_type_id)
		icon.show_unit(unit.instance_id, shown_name, sprite)
		icon.pointed.connect(_on_icon_pointed)
		icon.unpointed.connect(_on_icon_unpointed)
	var hidden: int = maxi(units.size() - max_icons, 0)
	_icons.visible = is_weapon and not units.is_empty()
	_more.visible = is_weapon and hidden > 0
	_more.text = more_format % [hidden]
	_note.visible = not is_weapon or units.is_empty()
	_note.text = any_unit_text if not is_weapon else no_unit_text


## Shows every wielder's name under the row, for the card's keyboard and pad focus. Does nothing
## for an item any unit uses, or one none can wield, whose row says so in words.
func show_names_tip() -> void:
	if _names.is_empty() or not is_visible_in_tree():
		return
	_show_tip(names_title, ", ".join(_names))


## Hides the tooltip.
func hide_tip() -> void:
	_tooltip.visible = false


## The names on the icons shown, in army order, for tests.
func get_icon_names() -> PackedStringArray:
	var shown: PackedStringArray = []
	for icon: ItemUserIcon in get_icons():
		shown.append(icon.unit_name)
	return shown


## The icons shown, in army order, for tests.
func get_icons() -> Array[ItemUserIcon]:
	var icons: Array[ItemUserIcon] = []
	if not _icons.visible:
		return icons
	for child: Node in _icons.get_children():
		if child is ItemUserIcon and not child.is_queued_for_deletion():
			icons.append(child as ItemUserIcon)
	return icons


## The "+n" count as shown; empty when every wielder has an icon.
func get_more_text() -> String:
	return _more.text if _more.visible else ""


## The words shown instead of icons ([member any_unit_text] or [member no_unit_text]); empty
## while icons show.
func get_note_text() -> String:
	return _note.text if _note.visible else ""


## The "+n" label, for tests that point at it.
func get_more_label() -> Label:
	return _more


## The tooltip, for tests that read it.
func get_tip() -> GameTooltip:
	return _tooltip


# The tooltip with tip_name and body, under the row, kept on screen.
func _show_tip(tip_name: String, body: String) -> void:
	_tooltip.show_tip(tip_name, body)
	_tooltip.visible = true
	_place_tip()
	# The tooltip refits a frame later when its text wraps; place it again then.
	_place_tip.call_deferred()


func _place_tip() -> void:
	if not is_instance_valid(_tooltip) or not _tooltip.visible:
		return
	var screen: Vector2 = get_viewport_rect().size
	var at: Vector2 = global_position + Vector2(0.0, size.y + tooltip_gap)
	at.x = clampf(at.x, 0.0, maxf(screen.x - _tooltip.size.x, 0.0))
	at.y = clampf(at.y, 0.0, maxf(screen.y - _tooltip.size.y, 0.0))
	_tooltip.global_position = at


func _on_icon_pointed(icon: ItemUserIcon) -> void:
	_show_tip(icon.unit_name, "")


func _on_icon_unpointed(_icon: ItemUserIcon) -> void:
	hide_tip()


func _on_more_mouse_entered() -> void:
	var rest: PackedStringArray = _names.slice(max_icons)
	if rest.is_empty():
		return
	_show_tip(names_title, ", ".join(rest))


## [param seat_run]'s living units that can use [param definition], in army order: for a weapon,
## those whose weapon types ([method ItemPlacement.weapon_types_of], an upgrade's included) hold
## its type; for any other item, every one. Empty for a null definition or seat run.
static func wielders(
		definition: ItemDefinition, seat_run: SeatRun, catalog: EffectCatalog.Index
) -> Array[UnitInstance]:
	var found: Array[UnitInstance] = []
	if definition == null or seat_run == null:
		return found
	var weapon: WeaponDefinition = definition as WeaponDefinition
	for unit: UnitInstance in seat_run.army:
		if weapon == null or ItemPlacement.weapon_types_of(unit, catalog).has(weapon.weapon_type):
			found.append(unit)
	return found
