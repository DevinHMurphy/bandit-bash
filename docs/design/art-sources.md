# Art Sources

Where every piece of board and item art in `bandit-bash/assets/sprites/` came from (P15 UL2,
[ui-lift.md](ui-lift.md) decisions 1, 9 and 10). The rule: Godot_FE's art wherever it fits, one
consistent placeholder for the rest, nothing made from scratch. Every placeholder is also listed in
[rebalance-and-features.md](rebalance-and-features.md) RF-008 until the art pass.

**Status:** built November 19, 2026 (UL2). Picks marked *assumption* are Claude's (decision 10) and
are shown on the contact-sheet captures for the user's review.

Paths below are relative to `Godot_FE/resources/sprites/` unless they start with `assests/` (the
user's folder at the repo root). Nothing in Godot_FE was edited; files were copied, or cut from a
tile sheet one 32 px cell at a time.

## Licences

- **Godot_FE's art** is the project's own earlier build.
- **`blood_hound.png`** is the user's own art (November 19, 2026).
- **`hound.png`** is from the user's `assests/32rogues` pack (Seth Boyles, 2024; the wolf,
  `animals.txt` 6.g). Its licence allows commercial use but forbids redistributing the pack and
  any use "in conjunction with generative artificial intelligence projects". Copied on the user's
  word: the user keeps it (November 19, 2026), as all art is placeholder until an artist is
  contracted. Replace it before any release or public push.
- **`minor_golem.png`** (the Stonelet) is from the same `assests/32rogues` pack (Seth Boyles,
  2024), under the same licence note as `hound.png`: copied on the user's word (November 25, 2026),
  placeholder, replace it before any release or public push.

## Unit sprites

`assets/sprites/units/`, keyed in `unit_sprites.tres` by content id. All 32 × 32.

| Key | File | Source | Basis |
|-----|------|--------|-------|
| archer, battle_medic (`field_medic.png`), drengr, hakkapel | as before (M1) | `units/` | Exact |
| brawler, fighter, freewing, lance_armor, lancer, mage, sellsword, shaman, suncaster, thief, ward | same name | `units/<name>.png` | Exact |
| brute (`vandal.png`), crossbowman, hedge_healer (`healer.png`) | as before (M1) | `units/` | Exact |
| duelist | `duelist.png` | `units/duelist.png` | Exact |
| cutthroat | `bladehand.png` | `units/bladehand.png` | *Assumption*: paired knives, as its dagger; corsair rejected (sword-armed, too close to the Duelist) |
| hexer | `sea_witch.png` | `units/sea_witch.png` | *Assumption*; bone_mancer rejected (reads like the player Shaman) |
| hound | `hound.png` | `assests/hound.png` | The user's pick (32rogues wolf) |
| raider | `axe_cavalier.png` | `units/axe_cavalier.png` | *Assumption*: mounted, as the class; marauder rejected (on foot) |
| stonelet | `minor_golem.png` | `assests/32rogues` (the minor golem) | The user's pick (November 25, 2026); `bulwark.png`, the Shieldbearer's, is no longer mapped |
| warcaller | `banner_bearer.png` | `units/banner_bearer.png` | *Assumption*; sanctioner rejected |
| bloodhound | `blood_hound.png` | the user's own art (November 19, 2026) | The user's pick; replaced Godot_FE's `flesh_prowler.png` |
| brigand_captain | `destroyer.png` | `units/Destroyer.png` | *Assumption*; a tinted vandal and `tier4/captain.png` rejected |
| hex_matron | `herbalist.png` | `units/tier1/herbalist.png` | *Assumption*: crooked staff, earthy greens, so it reads apart from the pale, purple player Shaman and the Hexer (user, at review: bone_mancer read too close to the Shaman); dark_imp (purple again), bishop and Cleric (priests), goblin_caster (not human) and a tinted sea_witch rejected |
| stone_golem | `stone_golem_large.png` | the user's, sent November 25, 2026 (source to be given, P05 question 65) | The user's pick; `sword_armor.png`, the Iron Wall's, is no longer mapped |
| powder_baron | `gunner.png` | `units/gunner.png` | *Assumption*: a firearm, for the powder; a tinted vandal rejected |
| Wooden Debris, Stone Debris | `objects/wood_debris.png`, `objects/stone_debris_1.png` | `entities/debris/` | Exact (breakables key by their label) |
| Powder Keg | `objects/powder_keg.png` | `tilemaps/combat_map/tiles_dungeon_v1.1.png` cell (13, 18), a barrel | *Assumption*: Godot_FE has no keg |

## Terrain

`assets/sprites/terrain/terrain_atlas.png` replaces the greybox gradient as the texture of
`maps/greybox_tile_set.tres`, cell for cell, so no map was repainted. One tile per terrain: rivers,
walls and cliffs don't join up (accepted by the user for UL2). Sheets: OW =
`Overworld_Tileset.png`, DG = `tiles_dungeon_v1.1.png`, both in `tilemaps/combat_map/`. "Over" means
a transparent Godot_FE piece laid on a ground tile, as Godot_FE drew it on two layers. Where
Godot_FE tagged a terrain, its most-used tile in Godot_FE's maps was taken.

| Terrain | Cell | Basis |
|---------|------|-------|
| bridge | OW (17, 0) | Godot_FE tag |
| broken_wall | DG (7, 1), rubble on flagstones | *Assumption*: walkable rubble |
| camp | OW (16, 4), a hut on grass | *Assumption* |
| castle_gate | OW (11, 11) over OW (0, 0) | Godot_FE tag |
| cliff | OW (1, 12) | Godot_FE tag |
| cracked_wall | `entities/breakable_terrain/breakable_wall_h.png` over DG (0, 0) | Godot_FE's cracked wall |
| floor | DG (0, 0) | Godot_FE tag |
| forest | OW (6, 8) over OW (0, 0) | Godot_FE tag |
| fort | OW (9, 14) over OW (0, 0) | Godot_FE tag |
| house | OW (9, 13) over OW (0, 0) | Godot_FE tag |
| knoll | OW (12, 5), a low mound | *Assumption* |
| mountain | OW (11, 5), a rock peak | *Assumption*: Godot_FE's mountain tag sits on a plain tile |
| ocean | OW (21, 14) | Godot_FE tag |
| peak | OW (8, 5) | Godot_FE tag |
| pillar | DG (7, 18) over DG (0, 0) | Godot_FE tag |
| pit | DG (15, 1) | Godot_FE tag |
| plain | OW (0, 0) | Godot_FE tag |
| river | OW (20, 1) | Godot_FE tag |
| road | OW (1, 17), packed sand | *Assumption* |
| ruins | OW (10, 14) over OW (0, 0) | *Assumption* |
| short_grass | OW (1, 0), grass with tufts | *Assumption* |
| stairs | DG (7, 16) over DG (0, 0) | Godot_FE tag |
| thicket | OW (1, 9) over OW (0, 0) | Godot_FE tag |
| throne | DG (13, 17) over DG (0, 0) | Godot_FE tag |
| wall | DG (2, 8) | Godot_FE tag |
| waterfall | OW (36, 0) | Godot_FE tag |
| wooded_knoll | OW (6, 7) over OW (12, 5) | *Assumption*: a tree on the knoll |
| spiked_wall, spilled_oil | the greybox colour, kept | **Placeholder**: no fitting tile |

The marker cells (29–47) keep their greybox colours; they show only with a map's markers on.

## Map objects

`assets/sprites/objects/`, set on `ui/battle/board/map_object_mark.tscn`. A spent object is also
drawn at 45% opacity.

| State | File | Source |
|-------|------|--------|
| Chest (opened: dimmed) | `chest.png` | `entities/chests/chest.png` |
| Key door, closed / open (dimmed) | `door_h.png` | `entities/doors/door_h.png` |
| Lever door, closed / open (dimmed) | `door_gate_h.png` | `entities/doors/door_gate_h.png` |
| Lever | `lever.png` | DG (0, 19) |
| Food shelf / searched | `food_counter.png` / `food_counter_empty.png` | `entities/search/` |
| Book shelf / searched | `book_shelf.png` / `book_shelf_empty.png` | `entities/search/` |
| Weapon rack / searched | `weapon_rack_full_1.png` / `weapon_rack_empty.png` | `entities/search/` |
| Passage end | `passage.png` | DG (8, 16), stairs (*assumption*: Godot_FE built no passage) |
| Brazier lit / out | `brazier_lit.png` / `brazier_unlit.png` | DG (0, 15) / (4, 15), a wall torch (*assumption*) |
| House, searched or not | none | **Placeholder**: "?" in `accent` on the dark circle |
| Lit keg's fuse | the keg sprite plus a `FuseBadge` | number on a `danger_fill` chip |

## Intent and mark icons

`assets/sprites/icons/`, white Godot_FE glyph icons tinted with each intent's theme colour.

| Mark | File | Source |
|------|------|--------|
| Attack intent | `physical_damage_icon.png` | `icons/damage_icons/` |
| Heal intent | `support_icon.png` | `icons/unit_action_icons/` |
| Guard intent | `wait_icon.png` | `icons/unit_action_icons/` |
| Advance intent | `arrow_icon.png` | `icons/` |
| Object-use intent (was "¤") | `interact_icon.png` | `icons/unit_action_icons/` |
| Signature intent (was "§") | `skill_icon.png` | `icons/unit_action_icons/` |
| Block ban (was "Ø" alone) | `shield_icon.png`, the "Ø" kept over it | `icons/weapon_icons/` |

## Item icons

`assets/sprites/items/<kind>/`, set as each item's `icon`. 158 items: **90** match a Godot_FE file
by name (copied under that name), **59** are matched by hand, **9** take a per-kind fallback (Godot_FE's
white weapon and item glyph icons). Every hand match and fallback is an *assumption*:

| Item | Source | Copied as | Basis |
|------|--------|-----------|-------|
| `all_seeing_hands` | `items/weapons/fist/eye_fist.png` | `weapons/eye_fist.png` | hand |
| `arming_sword` | `items/weapons/swords/steel_sword.png` | `weapons/steel_sword.png` | hand |
| `armorbreaker` | `items/weapons/dagger/sword_breaker.png` | `weapons/sword_breaker.png` | hand |
| `ash_spear` | `items/weapons/lance/slim_lance.png` | `weapons/slim_lance.png` | hand |
| `bearded_axe` | `items/weapons/axes/steel_axe.png` | `weapons/steel_axe.png` | hand |
| `boar_spear` | `items/weapons/lance/steel_lance.png` | `weapons/steel_lance.png` | hand |
| `brass_knuckles` | `items/weapons/fist/brassknuckles.png` | `weapons/brassknuckles.png` | hand |
| `bulls_draught` | `icons/ui_icons/icon_potion.png` | `consumables/icon_potion.png` | fallback |
| `butchers_knife` | `items/weapons/dagger/heavy_knife.png` | `weapons/heavy_knife.png` | hand |
| `cestus` | `items/weapons/fist/steel_guantlets.png` | `weapons/steel_guantlets.png` | hand |
| `earthsplitter` | `items/weapons/nature/living_roots.png` | `weapons/living_roots.png` | hand |
| `emberglass_vial` | `items/equipment/vial_of_quiet_flame.png` | `consumables/vial_of_quiet_flame.png` | hand |
| `everbloom` | `items/weapons/staff/everbloom_staff.png` | `weapons/everbloom_staff.png` | hand |
| `everwall` | `icons/weapon_icons/staff_icon.png` | `weapons/staff_icon.png` | fallback |
| `eye_shield` | `items/weapons/shield/Eye Greatshield.png` | `equipment/eye_greatshield.png` | hand |
| `fangs` | `items/sharp_claws.png` | `weapons/sharp_claws.png` | hand |
| `far_ward` | `items/weapons/staff/imbue_staff.png` | `weapons/imbue_staff.png` | hand |
| `finesse_filet` | `items/consumables/stat_boosters/skill/finesse_fillet.png` | `consumables/finesse_fillet.png` | hand |
| `gladius` | `items/weapons/swords/short_sword.png` | `weapons/short_sword.png` | hand |
| `guard_tonic` | `items/consumables/elixir_small.png` | `consumables/elixir_small.png` | hand |
| `guard_tonic_plus` | `items/consumables/refillable_potion.png` | `consumables/refillable_potion.png` | hand |
| `harm` | `items/weapons/staff/harm_staff.png` | `weapons/harm_staff.png` | hand |
| `headsmans_axe` | `items/weapons/axes/great_axe.png` | `weapons/great_axe.png` | hand |
| `heartbeet` | `items/consumables/stat_boosters/health/heart_beet.png` | `consumables/heart_beet.png` | hand |
| `heartseeker` | `items/weapons/swords/killer_sword.png` | `weapons/killer_sword.png` | hand |
| `hunters_bow` | `items/weapons/bow/long_bow.png` | `weapons/long_bow.png` | hand |
| `key` | `items/consumables/keys/chest_key.png` | `consumables/chest_key.png` | hand |
| `large_potion_plus` | `items/consumables/large_potion+.png` | `consumables/large_potion+.png` | hand |
| `loaded_die` | `items/equipment/loaded_dice.png` | `trinkets/loaded_dice.png` | hand |
| `lockpick` | `items/consumables/keys/skeleton_key.png` | `consumables/skeleton_key.png` | hand |
| `lumen` | `items/weapons/light/Lumen_tome.png` | `weapons/lumen_tome.png` | hand |
| `mystifying_incense` | `items/equipment/mystifing_incense.png` | `trinkets/mystifing_incense.png` | hand |
| `ogre_knuckles` | `items/weapons/fist/devilsknuckles.png` | `weapons/devilsknuckles.png` | hand |
| `potion_plus` | `items/consumables/potion+.png` | `consumables/potion+.png` | hand |
| `precise_pepper` | `items/consumables/stat_boosters/skill/true_pepper.png` | `consumables/true_pepper.png` | hand |
| `rampart` | `icons/weapon_icons/staff_icon.png` | `weapons/staff_icon.png` | fallback |
| `recover` | `items/weapons/staff/recover_staff.png` | `weapons/recover_staff.png` | hand |
| `recurve_bow` | `items/weapons/bow/reinforced_bow.png` | `weapons/reinforced_bow.png` | hand |
| `rondel` | `items/weapons/dagger/steel_dagger.png` | `weapons/steel_dagger.png` | hand |
| `ruin` | `items/weapons/staff/destroy_staff.png` | `weapons/destroy_staff.png` | hand |
| `runewart` | `items/consumables/stat_boosters/magic/rune_wart.png` | `consumables/rune_wart.png` | hand |
| `rushraddish` | `items/consumables/stat_boosters/speed/rush_raddish.png` | `consumables/rush_raddish.png` | hand |
| `sanctuary` | `icons/weapon_icons/staff_icon.png` | `weapons/staff_icon.png` | fallback |
| `shelter` | `icons/weapon_icons/staff_icon.png` | `weapons/staff_icon.png` | fallback |
| `short_quiver` | `icons/item_icons/equipment_icon.png` | `equipment/equipment_icon.png` | fallback |
| `simple_anima` | `items/weapons/nature/fire_tome.png` | `weapons/fire_tome.png` | hand |
| `simple_axe` | `items/weapons/axes/iron_axe.png` | `weapons/iron_axe.png` | hand |
| `simple_bow` | `items/weapons/bow/iron_bow.png` | `weapons/iron_bow.png` | hand |
| `simple_coating` | `icons/item_icons/equipment_icon.png` | `equipment/equipment_icon.png` | fallback |
| `simple_dagger` | `items/weapons/dagger/iron_dagger.png` | `weapons/iron_dagger.png` | hand |
| `simple_dark` | `items/weapons/dark/shade_tome.png` | `weapons/shade_tome.png` | hand |
| `simple_gauntlets` | `items/weapons/fist/iron_guantlets.png` | `weapons/iron_guantlets.png` | hand |
| `simple_holy` | `items/weapons/light/ray_tome.png` | `weapons/ray_tome.png` | hand |
| `simple_lance` | `items/weapons/lance/iron_lance.png` | `weapons/iron_lance.png` | hand |
| `simple_quiver` | `icons/item_icons/equipment_icon.png` | `equipment/equipment_icon.png` | fallback |
| `simple_sword` | `items/weapons/swords/iron_blade.png` | `weapons/iron_blade.png` | hand |
| `spirit_coating` | `items/equipment/magic_whetstone.png` | `equipment/magic_whetstone.png` | hand |
| `starforged_blade` | `items/weapons/swords/valor_sword.png` | `weapons/valor_sword.png` | hand |
| `steppe_hornbow` | `items/weapons/bow/steel_bow.png` | `weapons/steel_bow.png` | hand |
| `stiletto` | `items/weapons/dagger/knife.png` | `weapons/knife.png` | hand |
| `stone_fists` | `items/weapons/fist/iron_guantlets.png` | `weapons/iron_guantlets.png` | fallback: the Simple Gauntlets' icon, until art (P05 question 62) |
| `stonedragon_tail` | `items/consumables/stat_boosters/defense/stonewyvern_tail.png` | `consumables/stonewyvern_tail.png` | hand |
| `throwing_hatchet` | `items/weapons/axes/hatchet.png` | `weapons/hatchet.png` | hand |
| `twin_fang` | `items/weapons/swords/scimitar.png` | `weapons/scimitar.png` | hand |
| `whisperknife` | `items/weapons/dagger/tanto.png` | `weapons/tanto.png` | hand |
| `wind` | `items/weapons/nature/wind_tome.png` | `weapons/wind_tome.png` | hand |
| `woodsmans_axe` | `items/weapons/axes/short_axe.png` | `weapons/short_axe.png` | hand |
| `wyvern_pike` | `items/weapons/lance/great_lance.png` | `weapons/great_lance.png` | hand |

## For heirlooms and curses (not used yet)

UL8's heirloom placeholders stay. Godot_FE icons no item uses that would fit, for a later pass:

| Heirloom or curse | Candidate |
|-------------------|-----------|
| Gilded Purse, Warlord's Spoils, Bounty Ledger | `items/treasure/treasure_coins_small`, `_medium`, `_large`; `diamond`, `emerald` |
| War Ledger, Merchant's Ledger | `items/equipment/ink_well.png` |
| Guild Charter, Membership Seal | `items/equipment/ashen_seal.png` |
| Overflowing Cup | `items/treasure/wine.png` |
| Veteran's Medal | `icons/campaign_map_icons/icon_trophy.png` |
| Tactical Map | `icons/campaign_map_icons/icon_target.png` |
| Tinker's Token, Scrapper's Tongs | `icons/campaign_map_icons/icon_hammer.png` |
| Bloodied Banner, Commander's Standard | `icons/weapon_icons/banner_icon.png` |
| Muster Roll | `icons/ui_icons/army_icon.png` |
| Burglar's Roll | `items/consumables/keys/door_key.png` |
| Warhorse Lineage, Horsebane Charm | `icons/unit_trait_icons/Mounted_icon.png` |
| Ancestral Mail | `icons/amor_icon.png` |
| Iron Heart | `status_effects/Healing_2.png` |
| Haunted | `items/equipment/cursed_skull.png` |
| Cursed Blood | `status_effects/Poison_3.png` |
| Ill Omen | `icons/campaign_map_icons/icon_dice.png` |
| Hunted | `icons/campaign_map_icons/icon_target_2.png` |
| Clouded Sight | `items/equipment/memory_glass.png` |
| Brittle Guard | `items/equipment/ironwood_fragment.png` |
| Shaken Footing, Leaden Boots | `items/equipment/bounce_boots.png` |
| Others | `items/equipment/gale_feather`, `runed_quartz`, `shadecap_band`, `bridge_support`; `stat_boosters/strength/power_rune`; `items/treasure/spices` |

## Event art

`assets/sprites/events/`, set as each event's `art` ([events.md](events.md)). All 384 × 256, copied
under their Godot_FE names from `events/`, each the background its Godot_FE event used (P09 EV4,
decision 50). Bandit Toll, Cursed Hoard, Mercenary Camp and The Black Altar have no Godot_FE
scene, so no art: the event screen shows its placeholder.

| Event | File | Basis |
|-------|------|-------|
| `broken_shrine_of_valor` | `broken_shrine_of_valor_background.png` | name |
| `cavern_of_echoing_steel` | `cavern_of_echoing_steel_background.png` | name |
| `clockwork_hermit` | `clockwerk_hermit_background.png` | Godot_FE event's file |
| `dark_goblet` | `dark_goblet_background.png` | name |
| `festival_of_embers` | `festival_of_embers_background.png` | name |
| `frozen_armory` | `frozen_armory_background.png` | name |
| `ghastly_library` | `whispering_library_background.png` | Godot_FE event's file |
| `mirror_of_doubt` | `mirror_of_doubt_background.png` | name |
| `whispering_oak` | `whispering_oak_background.png` | name |
