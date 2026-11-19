# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_recap_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitRecapRow
extends Button
## One unit's row in the victory recap: its name, the Standout or Fallen tag in words, its battle
## stats, the XP it earned and how, and its [XpBar].
##
## A [Button] so it takes focus with the row looks (rest, hover, focus outline) and the recap's
## scroll follows a pad's focus; pressing it does nothing. Its height follows its content. A
## fallen unit has no XP line or bar, and its name is muted. A report saved before battle stats
## shows "—" for them.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## What the stats read when the report has none.
const NO_STATS: String = "Kills — · Damage dealt — · Damage taken — · Healed —"

var _line: CombatResultsModel.XpLine = null

@onready var _content: MarginContainer = %Content
@onready var _name_label: Label = %Name
@onready var _tag_label: Label = %Tag
@onready var _stats_label: Label = %Stats
@onready var _xp_label: Label = %Xp
@onready var _xp_bar: XpBar = %XpBar


func _ready() -> void:
	_content.minimum_size_changed.connect(_fit)
	_fit()


## Shows [param line], its bar still at the XP it has now; [param per_level] is XP per level.
func show_line(line: CombatResultsModel.XpLine, per_level: int) -> void:
	_line = line
	_name_label.text = line.name
	_name_label.theme_type_variation = &"MutedLabel" if line.is_fallen else &"HeaderLabel"
	var is_standout: bool = line.award != null and line.award.is_standout
	_tag_label.text = "Fallen" if line.is_fallen else ("Standout" if is_standout else "")
	_tag_label.visible = not _tag_label.text.is_empty()
	_stats_label.text = stats_text(line.stats)
	_xp_label.visible = line.award != null
	_xp_bar.visible = line.award != null
	if line.award == null:
		return
	_xp_label.text = xp_text(line.award)
	_xp_bar.show_still(line.level, line.xp, per_level)


## Readies the bar's fill from the XP before the combat; false for a row with no bar.
func prepare_fill(per_level: int) -> bool:
	if _line == null or _line.award == null:
		return false
	_xp_bar.prepare(_line.level_before, _line.xp_before, _line.award.total, per_level)
	return true


## The row's bar.
func get_xp_bar() -> XpBar:
	return _xp_bar


## The line shown; null before [method show_line].
func get_line() -> CombatResultsModel.XpLine:
	return _line


## The stats line, for tests.
func get_stats_text() -> String:
	return _stats_label.text


## The tag shown ("Standout", "Fallen"), empty for none, for tests.
func get_tag_text() -> String:
	return _tag_label.text if _tag_label.visible else ""


# The button sizes to its content, which it doesn't lay out itself.
func _fit() -> void:
	custom_minimum_size = Vector2(0.0, _content.get_combined_minimum_size().y)


## [param stats] (indexed by [enum BattleStats.Stat]) as the row reads them; [constant NO_STATS]
## when empty.
static func stats_text(stats: PackedInt32Array) -> String:
	if stats.size() < BattleStats.STAT_IDS.size():
		return NO_STATS
	return "Kills %d · Damage dealt %d · Damage taken %d · Healed %d" % [
		stats[BattleStats.Stat.KILLS], stats[BattleStats.Stat.DAMAGE_DEALT],
		stats[BattleStats.Stat.DAMAGE_TAKEN], stats[BattleStats.Stat.HEALED],
	]


## [param award] as the row reads it: [code]+23 XP: shared 15 · personal 3 · Standout 5[/code],
## the Standout part only for the Standout, and the unit's own percent when it isn't 100.
static func xp_text(award: XpAward) -> String:
	var parts: PackedStringArray = ["shared %d" % [award.shared], "personal %d" % [award.personal]]
	if award.is_standout:
		parts.append("Standout %d" % [award.standout])
	if award.percent != 100:
		parts.append("×%d%%" % [award.percent])
	return "+%d XP: %s" % [award.total, " · ".join(parts)]
