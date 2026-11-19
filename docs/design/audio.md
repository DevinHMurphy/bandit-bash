# Audio

The scope for the game's sound: the audio layer every screen and feature plays through (M2) and
the sound design and music that fill it later (M5). This scope doc is plan **P16 Audio** on the
[orchestrator](../plans/game-orchestrator.md), as [ui-lift.md](ui-lift.md) is for P15.

**Status:** scoped November 19, 2026 (user; the four questions answered as recommended, see
[Decisions](#decisions)). AU1 is an M2 item, built beside P15 UL2 so UL6 and UL7 wire their
sounds in as they build. The audio direction is open, for an ideation pass before AU2.

## Where it stands

Found November 19, 2026:

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
| **AU1 Audio foundation** | Named buses; the `AudioService` autoload; cues as data; settings applied to the buses; the shared UI sound hook; the fact-to-cue listener pattern with a first handful of cues; Godot_FE's sounds and music as placeholders. [Details](#au1-audio-foundation) | P07, P08, P15 screens | UL1 ✅ |
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
- **UI hook:** one reusable component the shared button and focus scenes use, for focus, press,
  back and refused (a disabled option says why, ui-style.md). No per-scene sound code.
- **Facts to cues:** one listener pattern on `CombatBus` and `CampaignBus` that maps fact kinds to
  cues as they play, proved with a handful (hit, miss, crit, level-up, phase banner). UL6 adds
  the rest.
- **Godot_FE's audio is the sound set** (user, November 19, 2026): all 8 tracks in
  `resources/music/` and every current sound in `resources/sounds/` (52 files), copied into
  `bandit-bash/assets/audio/` in Godot_FE's folder layout, each with a cue. The 7 superseded `old`
  files stay behind, except `combat/attack/old/miss.wav`, the only miss sound. Each cue is mapped
  to its use where the game has one today; the rest wait for their screen (shop, Guildhall,
  equip, the campaign map's node types). Placeholders under RF-008 until AU2.
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
