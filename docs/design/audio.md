# Audio

The scope for the game's sound: the audio layer every screen and feature plays through (M2) and
the sound design and music that fill it later (M5). This scope doc is plan **P16 Audio** on the
[orchestrator](../plans/game-orchestrator.md), as [ui-lift.md](ui-lift.md) is for P15.

**Status:** scoped November 19, 2026 (user; the four questions answered as recommended, see
[Decisions](#decisions)). AU1 is an M2 item, built beside P15 UL2 so UL6 and UL7 wire their
sounds in as they build; built November 19, 2026 on `feature/AU1`, awaiting merge. The audio
direction is open, for an ideation pass before AU2.

## Where it stands

**AU1 built** November 19, 2026 (`feature/AU1`, not merged yet):

- **The layer:** buses Master, Music, SFX and UI (`data/audio/bus_layout.tres`); the
  `AudioService` autoload (cues by id with a voice limit, music with a crossfade, stop and duck);
  cues as `AudioCue` resources in `data/audio/cues/`, loaded by `AudioCueCatalog`, its own walk
  of that folder, which `EffectCatalog` now skips; `SettingsData.apply()` sets the buses, closing
  `TOD-001`, and the Options sliders are heard live (leaving Options puts the saved levels back).
- **UI sounds:** a tree-wide hook (`UiSoundHook`), not a component in the shared scenes. It plays
  focus, press, Back and refused for every button, slider and focus change, with the
  `ui_sound_off` group to opt out, so no scene has sound code. Focus moves sound; a screen's first
  focus and a click's don't. On the menu screens Esc and pad B press the Back button (its
  `ui_cancel` shortcut, P15 UL7), so they sound as Back.
- **Facts to cues:** one `FactCueListener` per bus reads a `FactCueMap`, one line per rule
  (`"HIT_DEALT/no_damage": "no_damage"`). Combat: swing on every attack, miss, hit, no damage, hit
  on an object, crit, heal, a player unit's death, victory, and the phase banner's music change.
  Campaign facts play from P15 UL7: the campaign screens play the run's facts on its
  `CampaignBus` as they show them (`CampaignPlayback`), so `LEVELED_UP` sounds the level-up once
  per recap card, `NODE_CHOSEN` on a combat node `battle_map_enter` (the `combat` shape, the
  node's type read through a lookup the service binds), and `RUN_STARTED` `begin_campaign`. The
  run's fact log isn't saved, so a resumed run replays none of them.
- **The sound set:** 62 files from Godot_FE (8 tracks, 53 current sounds and the old `miss.wav`)
  in `bandit-bash/assets/audio/`, Godot_FE's folder layout, 63 cues (`ui_refused` reuses
  `menu_back.ogg`). In use today: 7 tracks (menus and campaign map; prep, player and enemy phase
  per battle, the boss set on the Powder Baron's map) and 23 sound cues (UI hook, campaign map
  nodes, board input, combat facts, victory sequence, and from UL7 a combat node chosen and the
  run's start). Unmapped: `Action_-_Treasure_Hunters` and 32 sounds waiting for their screen
  (shop, Guildhall training, equip and convoy, draft, the Treasure, event and recruit nodes' enter
  sounds, resurrect, promotion, weapon durability, UL6's magic hits and walk). The full table is [assets/audio/README.md](../../bandit-bash/assets/audio/README.md).
  Placeholders under RF-008.

Found November 19, 2026, before AU1:

- **Nothing plays.** `bandit-bash/` has no audio bus layout, no players and no sound files.
- **Settings are ready.** `settings.json` saves `master_volume`, `music_volume` and `sfx_volume`
  (int 0–10, default 5; [save-system.md](save-system.md)). `SettingsData.apply()` is a stub
  (`TOD-001`: apply the volumes to audio buses once an audio system exists). The Options screen's
  sliders save but change nothing.
- **Deferred so far:** P07 left audio out of M1 and M2; ui-lift.md lists it out of scope; UL5
  dropped Godot_FE's XP tick sound.
- **Godot_FE** (read-only) has `audio_manager/audio_manager.gd` (keyed music and sound libraries,
  one music player, a pitch-randomized play), `default_bus_layout.tres` (no named buses), about 55
  sounds in `resources/sounds/` (combat, attack, rewards, campaign map, inventory, level-up, shop,
  draft, training grounds) and 8 tracks in `resources/music/`. Its pitch randomizing calls the
  global RNG, which is why its seeds broke when a sound played (game-vision.md); that is not
  ported.

## Steps

| Step | What | Plans touched | Needs |
|------|------|---------------|-------|
| **AU1 Audio foundation** ✅ (merged November 19, 2026) | Named buses; the `AudioService` autoload; cues as data; settings applied to the buses; the shared UI sound hook; the fact-to-cue listener pattern with a first handful of cues; Godot_FE's sounds and music as placeholders. [Details](#au1-audio-foundation) | P07, P08, P15 screens | UL1 ✅ |
| **AU2+ Sound design** | The full combat cue set, music per screen and run stage, darkness ambience (an Ambience bus), the mix pass. Waits for the [audio direction](#open-questions) | P16 | AU1; the audio direction |

UL6 (combat feedback) and UL7 (campaign and menus) wire their sounds onto AU1 as they build; later
screens (P08 RN6 onward, P09) do the same.

## AU1 Audio foundation

- **Buses:** Master, with Music, SFX and UI under it. UI follows the SFX slider for now, so
  `settings.json` doesn't change. Ambience joins in AU2.
- **`AudioService` autoload:** plays a sound cue by id on its bus, with a voice limit per cue; plays
  music by id with a crossfade; stops and ducks. Presentation only: rules code never calls it
  (gdscript.md §8.5).
- **Cues as data:** a cue resource per sound (stream or streams, bus, volume, pitch range, voice
  limit), in `data/audio/`. A missing cue logs once and plays nothing.
- **Randomness:** pitch and stream variation use the service's own unsaved generator, never the
  global RNG or a run stream, so a sound can never change a seed.
- **Settings:** `SettingsData.apply()` sets the bus volumes (0 mutes), closing `TOD-001`; the
  Options sliders take effect live.
- **UI hook:** one hook on the whole scene tree (the viewport's focus changes, and each button and
  slider as it enters the tree) for focus, press, back and refused (a disabled option says why,
  ui-style.md), with an opt-out group. No per-scene sound code. (User, November 19, 2026: the
  tree-wide hook instead of a component the shared scenes use.)
- **Facts to cues:** one listener pattern on `CombatBus` and `CampaignBus` that maps fact kinds to
  cues as they play, proved with a handful (hit, miss, crit, level-up, phase banner). UL6 adds
  the rest.
- **Godot_FE's audio is the sound set** (user, November 19, 2026): all 8 tracks in
  `resources/music/` and every current sound in `resources/sounds/` (52 files), copied into
  `bandit-bash/assets/audio/` in Godot_FE's folder layout, each with a cue. The 7 superseded `old`
  files stay behind, except `combat/attack/old/miss.wav`, the only miss sound. Each cue is mapped
  to its use where the game has one today; the rest wait for their screen (shop, Guildhall,
  equip, the campaign map's node types). As built: 53 current sounds plus `miss.wav` (decision
  12). Placeholders under RF-008 until AU2. **Licensed:** the user
  holds the licence for this set (November 19, 2026), so it may ship; the aim is still to replace
  it in AU2 before release.
- **Tests:** suites run with the dummy audio driver; cases cover cue lookup, bus volumes from
  settings, the voice limit, the UI hook and the fact listener.
- **Co-op and saves:** local only, nothing networked; no save change.

## Open questions

- **Audio direction** (for AU2, ideation): the music's style and how it follows the run (per
  screen, per step, the darkness), how loud combat feedback is next to music, and which sounds are
  signature (the darkness, the Powder Baron's kegs). In the design queue for M5.

## Decisions

Decided by the user, November 19, 2026, as recommended:

1. **P16 Audio,** with AU1 in M2, built beside UL2 so it precedes UL6 and UL7. P09 EV1 moves to the
   round after UL6 and UL7.
2. **Buses:** Master, Music, SFX and UI; UI follows the SFX slider for now (no settings change);
   Ambience joins in AU2.
3. **Godot_FE's sounds and music** are the placeholders, as its art is: the whole current set, not
   a sample.
4. **A new autoload,** `AudioService`, is approved.

AU1's build questions, decided by the user November 19, 2026, as recommended:

5. **The UI hook is tree-wide,** with an opt-out group; Back is a `NavButton` set to Go Back or a
   button in `ui_sound_back`.
6. **Refused** plays `menu_back.ogg` as `ui_refused` until AU2 (Godot_FE had no refused sound).
7. **Attack cues layer as Godot_FE's did:** the swing on every attack, then the impact, no-damage
   or object sound, a crit's sound over its impact; a miss adds `miss.wav`, which Godot_FE never
   played.
8. **Music follows Godot_FE:** the menu track on menus and the campaign map; in battle a prep
   track before turn 1, then the player and enemy phase tracks as each Phase Start plays (the
   phase banner's cue); the boss set on the Powder Baron's map; key combats use the standard set.
9. **Level-up and rewards:** the `CampaignBus` listener carries the level-up rule, silent until
   campaign facts play; until then the victory recap plays it per card, the Grade stage plays
   the gold sound and the item pick the item or scrap sound.
10. **Board input** (select, confirm, return, the cursor's step) plays from `BattleController`.
11. **Options sliders** are heard live; leaving Options puts the saved levels back.
12. **The whole current set** is copied, `walk_stone.wav` included: 53 current sounds and
    `miss.wav`, not the 52 first counted; the `.m4a` duplicate stays behind.
