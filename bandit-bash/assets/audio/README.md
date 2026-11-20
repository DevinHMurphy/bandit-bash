# Audio assets

Godot_FE's whole current sound set, copied unchanged for AU1 ([audio.md](../../../docs/design/audio.md)):
all 8 music tracks and 54 sounds, in Godot_FE's folder layout. **Placeholders** under RF-008 until AU2
replaces them. The user holds the licence for this set, so it may ship (November 19, 2026).

Every file has a cue in `res://data/audio/cues/` (same folders, file named by cue id), and code plays the
cue id, never the file. **Source** paths are under `Godot_FE/resources/`. The UI bus follows the SFX
volume. Left behind: Godot_FE's 6 superseded files (`combat/attack/old/crit_old.wav`, `old/hit.wav`,
`old/no_damage_old.wav`, `ui/menu_back_old.wav`, `ui/menu_confirm_old.wav`, `ui/menu_cursor_old.wav`)
and `music/Menu_-_Dreaming_Darkly.m4a`, a copy of the `.ogg` that Godot can't import.

Random pitch 0.75–1.25 (Godot_FE's range) on `sword_swing_light`, `flesh_impact`, `no_damage`,
`entity_hit` and `unit_heal`, the cues Godot_FE randomized. Every other cue plays at its recorded pitch.
Voice limits: 4 per sound effect and 2 per UI sound, both `# ASSUMPTION` (Godot_FE had no limit).

## Music

| File | Source | Cue id | Where it plays |
|------|--------|--------|----------------|
| `music/Menu_-_Dreaming_Darkly.ogg` | `music/Menu_-_Dreaming_Darkly.ogg` | `menu_dreaming_darkly` | Start, Save Select, Main Menu, Options, New Run, Lobby, campaign map, node placeholder (Godot_FE: menus and campaign map) |
| `music/Menu_-_Adventures_Await.ogg` | `music/Menu_-_Adventures_Await.ogg` | `menu_adventures_await` | A standard or key battle before turn 1, the opening swap (Godot_FE: battle prep) |
| `music/Menu_-_Noble_Kingdom.ogg` | `music/Menu_-_Noble_Kingdom.ogg` | `menu_noble_kingdom` | A standard or key battle's player phase (Godot_FE: player phase) |
| `music/Action_-_Knightly_Fighting.ogg` | `music/Action_-_Knightly_Fighting.ogg` | `action_knightly_fighting` | A standard or key battle's enemy phase (Godot_FE: enemy phase) |
| `music/Menu_-_Epic_Entrance.ogg` | `music/Menu_-_Epic_Entrance.ogg` | `menu_epic_entrance` | The Powder Baron's map before turn 1 (Godot_FE: boss battle prep) |
| `music/Boss_-_Perilous_Prince.ogg` | `music/Boss_-_Perilous_Prince.ogg` | `boss_perilous_prince` | The Powder Baron's map, player phase (Godot_FE: boss player phase) |
| `music/Action_-_Surge_Forward.ogg` | `music/Action_-_Surge_Forward.ogg` | `action_surge_forward` | The Powder Baron's map, enemy phase (Godot_FE: boss enemy phase) |
| `music/Action_-_Treasure_Hunters.ogg` | `music/Action_-_Treasure_Hunters.ogg` | `action_treasure_hunters` | Unmapped: Godot_FE never played it; waits for AU2's music plan |

Key combats use the standard tracks (`# ASSUMPTION`: Godot_FE had no key combats). Save Select, New
Run, Lobby and the node placeholder keep the menu track (no Godot_FE equivalent). The results screens
keep whatever plays.

## Sounds in use

| File | Source | Cue id | Where it plays |
|------|--------|--------|----------------|
| `sounds/ui/menu_cursor.ogg` | same | `menu_cursor` | Focus moving between controls; a focused slider's step (UI hook) |
| `sounds/ui/menu_confirm.ogg` | same | `menu_confirm` | Any button press (UI hook) |
| `sounds/ui/menu_back.ogg` | same | `menu_back` | A Back button's press: a `NavButton` set to Go Back, or the `ui_sound_back` group (UI hook) |
| `sounds/ui/menu_back.ogg` | same | `ui_refused` | A click or accept on a disabled control (UI hook; `# ASSUMPTION`: Godot_FE had no refused sound) |
| `sounds/ui/campaign_map/campaign_map_room_hovered.ogg` | same | `campaign_map_room_hovered` | Focus on a campaign map node (`MapNodeButton`, as Godot_FE's rooms), and the mouse moving onto a reachable one (`# ASSUMPTION`: Godot_FE sounded on focus only) |
| `sounds/combat/move_tile.ogg` | same | `move_tile` | The battle cursor stepping to a new tile (`BattleController`) |
| `sounds/combat/unit_select.ogg` | same | `unit_select` | Picking a unit to move, or to swap in the opening swap |
| `sounds/combat/unit_confirm.ogg` | same | `unit_confirm` | Accepting a move tile |
| `sounds/combat/unit_return.ogg` | same | `unit_return` | Cancel snapping a moved unit back |
| `sounds/combat/attack/sword_swing_light.ogg` | same | `sword_swing_light` | Every attack, hit or miss (`ATTACK_MADE`) |
| `sounds/combat/attack/old/miss.wav` | same | `unit_miss` | A miss (`MISSED`) |
| `sounds/combat/attack/flesh_impact.ogg` | same | `flesh_impact` | A hit that deals damage (`HIT_DEALT`) |
| `sounds/combat/attack/no_damage.ogg` | same | `no_damage` | A hit for 0 (`HIT_DEALT/no_damage`) |
| `sounds/combat/attack/Entity_hit.ogg` | same | `entity_hit` | A hit on a map object (`HIT_DEALT/on_object`) |
| `sounds/combat/attack/crit_sound.ogg` | same | `crit_sound` | A critical hit, over the hit's impact (`CRIT_DEALT`) |
| `sounds/combat/weapon_break.ogg` | same | `weapon_break` | A unit's Stance broken, Exposed (`EXPOSED`; weapon durability, its first use, isn't in the game) |
| `sounds/ui/inventory/shield_equip.ogg` | same | `block_gained` | Block gained outside a refresh (`BLOCK_GAINED`), on the SFX bus: a second cue on the shield's file, as combat sounds stay off the UI bus |
| `sounds/combat/heal.wav` | same | `unit_heal` | A unit healed (`HEALED`) |
| `sounds/combat/Friendly_unit_die.ogg` | same | `friendly_unit_die` | A player unit defeated (`DEFEATED/player_actor`) |
| `sounds/combat/level_win.ogg` | same | `level_win` | The battle won (`COMBAT_ENDED/player_side`) |
| `sounds/combat/rewards/gold_rewarded.ogg` | same | `gold_rewarded` | The victory's Grade stage (gold collected); scrapping the item pick |
| `sounds/combat/rewards/item_obtained.ogg` | same | `item_obtained` | Taking the item pick, equipped or to the convoy |
| `sounds/ui/level_up/level_up.ogg` | same | `level_up` | Each level-up card in the victory recap: the card plays its `LEVELED_UP` fact (`CampaignPlayback`), which the campaign listener sounds once. A resumed recap's cards are silent (the fact log isn't saved) |
| `sounds/ui/campaign_map/battle_map_enter.ogg` | same | `battle_map_enter` | Choosing a combat node, Standard, Key or Boss (`NODE_CHOSEN/combat`, as Godot_FE's battle rooms) |
| `sounds/ui/overworld/begin_campaign.ogg` | same | `begin_campaign` | A new run's map first showing (`RUN_STARTED`, Godot_FE's campaign start); a continued run doesn't sound it |

The fact rules are `res://data/audio/maps/combat_facts.tres` and `campaign_facts.tres`. The music is
`res://data/audio/maps/music.tres`.

## Sounds waiting for their screen

| File | Source | Cue id | Where it plays |
|------|--------|--------|----------------|
| `sounds/combat/attack/sword_swing_heavy.ogg` | same | `sword_swing_heavy` | Unmapped: UL6 found no use for it (Godot_FE never played it) |
| `sounds/combat/attack/fire_spell_hit.wav` | same | `fire_spell_hit` | Unmapped: waits for UL6's magic hits (Godot_FE never played it) |
| `sounds/combat/attack/wind_spell_hit.wav` | same | `wind_spell_hit` | Unmapped: waits for UL6's magic hits (Godot_FE never played it) |
| `sounds/combat/walk_stone.wav` | same | `walk_stone` | Unmapped: waits for UL6's unit walk (Godot_FE never played it) |
| `sounds/combat/weapon_expended.ogg` | same | `weapon_expended` | Unmapped: waits for weapon durability (not in the game) |
| `sounds/combat/rewards/bonus_experience_rewarded.ogg` | same | `bonus_experience_rewarded` | Unmapped: waits for a bonus-XP reward (none today) |
| `sounds/ui/level_up/level_up_point.ogg` | same | `level_up_point` | Unmapped: waits for a level-up card that reveals gains one by one |
| `sounds/ui/level_up/experience_point.ogg` | same | `experience_point` | Unmapped: UL5 dropped the XP tick |
| `sounds/ui/campaign_map/event_map_enter.ogg` | same | `event_map_enter` | An event opening at an Unknown node: the event screen plays its `EVENT_DRAWN` fact (`CampaignPlayback`); a continued run doesn't sound it |
| `sounds/ui/campaign_map/treasure_map_enter.ogg` | same | `treasure_map_enter` | Unmapped: waits for the Treasure node (RN7) |
| `sounds/ui/campaign_map/recruit_map_enter.ogg` | same | `recruit_map_enter` | Unmapped: waits for recruiting (the Guildhall, RN9) |
| `sounds/ui/draft/draft_hover.ogg` | same | `draft_hover` | Unmapped: waits for a draft screen |
| `sounds/ui/draft/draft_confirm.ogg` | same | `draft_confirm` | Unmapped: waits for a draft screen |
| `sounds/ui/shop/item_buy.ogg` | same | `item_buy` | Unmapped: waits for the shop |
| `sounds/ui/shop/item_sell.ogg` | same | `item_sell` | Unmapped: waits for the shop |
| `sounds/ui/training_grounds/bonus_experience_point.ogg` | same | `bonus_experience_point` | Unmapped: waits for Guildhall training |
| `sounds/ui/training_grounds/bonus_experience_spend.ogg` | same | `bonus_experience_spend` | Unmapped: waits for Guildhall training |
| `sounds/ui/inventory/axe_equip.ogg` | same | `axe_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/bow_equip.ogg` | same | `bow_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/dagger_equip.ogg` | same | `dagger_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/fist_equip.ogg` | same | `fist_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/lance_equip.ogg` | same | `lance_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/magic_equip.ogg` | same | `magic_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/shield_equip.ogg` | same | `shield_equip` | Unmapped: waits for the equip screen (`block_gained` plays the file in battle) |
| `sounds/ui/inventory/staff_equip.ogg` | same | `staff_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/sword_equip.ogg` | same | `sword_equip` | Unmapped: waits for the equip screen |
| `sounds/ui/inventory/item_from_convoy.ogg` | same | `item_from_convoy` | Unmapped: waits for the convoy screen |
| `sounds/ui/inventory/store_item.ogg` | same | `store_item` | Unmapped: waits for the convoy screen |
| `sounds/ui/inventory/potion_use.ogg` | same | `potion_use` | Unmapped: waits for UL6's Pouch item use |
| `sounds/ui/graveyard/resurrect.ogg` | same | `resurrect` | A fallen unit returning (`UNIT_REVIVED`: the revive shrine's prayer, played by the event screen) |
| `sounds/ui/promotion/promotion.ogg` | same | `promotion` | Unmapped: waits for promotion |

Summary: 62 files, 64 cues (`ui_refused` reuses `menu_back.ogg`, `block_gained` `shield_equip.ogg`). In use: 7
tracks and 25 sound cues (24 files). Unmapped: 1 track and 31 sounds.
