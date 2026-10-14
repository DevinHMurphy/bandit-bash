# Plan: Save System
**Date:** October 13, 2026
**Status:** Approved — revision 4 (October 14, 2026); implementing milestone by milestone

## Problem

`bandit-bash/` has no persistence. Nothing survives a quit: no profile, no run, no settings, no
suspended combat. Multiplayer can't resume a campaign with the same players. The screens are
placeholders with no way to pick a save, continue a run or resume a multiplayer campaign
(`scenes/screens/start_screen.tscn`, `main_menu.tscn`, `options_screen.tscn`).

The old build (`Godot_FE/`) is the cautionary reference. Its save layer failed in these ways
(`Godot_FE/docs/systems/02_save_and_persistence.md` §6, confirmed against
`Godot_FE/selected_save_file.gd` and `Godot_FE/overworld_new/player_overworld_data.gd`):

- One god-resource (`PlayerOverworldData`) mixes permanent profile, resettable run and derived
  flags. `reset_game_state()` has to know which fields are which.
- `SelectedSaveFile.save()` ignores the `ResourceSaver.save()` return code and writes in place.
  A crash mid-write can destroy the slot (`selected_save_file.gd:11`).
- No `schema_version`. Godot silently drops `.tres` properties that no longer exist, so a renamed
  `@export` resets saved data with no error.
- `SelectedSaveFile` has no `load()`. About 17 screens hand-roll `ResourceLoader.load(...)`, so
  each sees only what the previous screen last wrote to disk.
- Persisted collections are untyped, keyed by Resource objects, or reference `PackedScene`s
  (`player_overworld_data.gd:31`) instead of ids.
- Mid-battle state is not saved, and run loss does not save (doc 02 §6 `[VERIFY]`). Killing the
  process mid-battle resumes from before the battle.
- SFX volume is applied from the music setting (`Godot_FE/options/options_config.gd:33`).
- A `.tres` can embed script references, so loading one from an untrusted source is code
  execution. Doc 02 §6 says never deserialize a Resource received from a peer.

## Open Questions

| # | Question | Answer |
|---|----------|--------|
| 1 | File format | **Answered.** Plain JSON. |
| 2 | Save file layout | **Answered.** 3 save files. Each holds a profile, settings, and two campaign slots: single player and multiplayer. |
| 3 | Run loss | **Answered.** Final. The ended run is written to the archive. |
| 4 | Where the multiplayer campaign lives | **Answered.** In the host's save file, multiplayer slot. Read-only to players. Identified by save-file number, no name. |
| 5 | Multiplayer resume requirement | **Answered.** Every original player must be in the lobby and ready. The host can invite missing players through the Steam overlay. |
| 6 | Inventory, roster and convoy in multiplayer | **Answered.** All per player, including the convoy. There is no shared convoy, so players can't take each other's items. Quick transfer between players is a gameplay feature outside this plan; the per-player layout supports it. |
| 7 | Player name | **Answered.** The Steam persona name is displayed. Not editable. The profile caches the last-seen name so a save file still shows a name when Steam is unavailable. |
| 8 | Combat block | **Answered.** A stub now. The upcoming RNG manager saves its state in both the campaign and the combat file, so reloading can't re-roll outcomes. |
| 9 | Run archive | **Answered.** Written in this plan (milestone M7). An archive viewer screen comes later. |
| 10 | Settings scope and menu flow | **Answered.** Settings per save file. A save file is always chosen first, every launch, in the style of The Binding of Isaac: Start → Save Select → Main Menu. Options is reachable only from the Main Menu, so the start screen's Options button is removed. |
| 11 | Client-side record of a joined campaign | **Answered.** None; resume is host-driven. Losing the host's file loses the campaign, which is acceptable for a roguelite. Every player still gets the run in their own archive when it ends (row 23). |
| 12 | Mapping a connected peer to a saved Steam id | **Answered.** `SteamMultiplayerPeer.get_steam_id_for_peer_id(peer_id: int) -> int`, verified with `ClassDB` against the installed GodotSteam. Behavior over a live connection is confirmed in M10. Fallback: players pick their seat and the host confirms. |
| 13 | Save triggers | **Answered.** New run: when the player presses Start (first save). Room entered. Battle: when the player presses Begin after prep (first combat save), then at the end of every player phase; in multiplayer, once every player has ended their turn. Battle ended. Save & Quit. Run ended. Settings: Apply on the options screen writes `settings.json` and nothing else. |
| 14 | SFX volume | **Answered.** Fixed: SFX reads `sfx_volume` and drives the SFX audio bus. |
| 15 | Crash mid-battle with no usable combat save | **Answered.** Retry the battle from Begin. `# NOTE:` this lets a player retry by killing the process before the first combat save lands; revisit if it matters in play. |
| 16 | Per-player data in the section contract | **Answered.** Option A, seat parameter. The host writes every player's data into the `players` array. |
| 17 | Game version source | **Answered.** `application/config/version` in `project.godot`, added as `0.1.0` (placeholder value). |
| 18 | Version check before and after joining | **Answered.** Lobby data shown before joining (`Steam.setLobbyData` / `getLobbyData`, verified to exist), plus a host-side handshake that refuses a mismatch. |
| 19 | File naming | **Answered.** `.json`, `.json.tmp`, `.json.bak`. Tamper resistance later. |
| 20 | Client's own profile in multiplayer | **Answered.** Each client writes its own profile when the host broadcasts a checkpoint. |
| 21 | Player count | **Answered.** Fixed when the campaign starts; 1 to 4 (`steam_network.gd:55`). |
| 22 | Game browser and lobby visibility | **Answered.** Lobbies stay friends-only (`steam_network.gd:47-49`). Since `Steam.requestLobbyList()` doesn't return friends-only lobbies, a browser (M12) lists friends currently in a Bandit Bash lobby. |
| 23 | Which multiplayer runs go to every player's archive | **Answered.** Every ended run, won or lost. |
| 24 | Apply volumes to audio | **Answered.** A stub. There's no audio system yet, so `SettingsData` stores and reports the values, and its `apply()` is a marked TODO that holds the old dB mapping for the audio system to use. No bus layout is created. |
| 25 | Debug Save panel | **Answered.** Kept. Settings Apply writes only `settings.json`, so it can't fire campaign checkpoints, combat phases, or a win or loss; the panel is the only way to test those until gameplay exists. Debug builds only (`OS.is_debug_build()`). |
| 26 | Accepting an invite when the game isn't running | **Answered.** Invites are handled while running now (`Steam.join_requested`, verified to exist). The `+connect_lobby` launch argument (kit `07_STEAM_API_REFERENCE.md:39`) comes with M12. |
| 27 | Which save file an accepted invite uses | **Answered.** The last selected save file. If none is recorded or it was deleted, the first non-empty save file. If all are empty, a new one is created in save 1. Save Select is skipped. |
| 28 | Settings before a save file is chosen | **Answered.** At boot, apply the last selected save file's settings (defaults if none), so the start screen and Save Select already sound right. |
| 29 | Accepting an invite during a solo run | **Answered.** Show a prompt, "Save & Quit and join?". Yes saves the run, then joins; No ignores the invite. Outside gameplay the join is immediate. |

## Scope

**In scope**
- Save files, campaign slots, settings, profile, combat stub, archive writing.
- Atomic writes with backup recovery; versioning and migrations; game version stamp.
- Section registry, including per-player sections.
- Combat crash protection and continuous play time.
- Multiplayer: host-side campaign, resume lobby with ready check, Steam overlay invites, accepting
  invites while running, version check, per-player archive on run end.
- The UI for all of the above (see "UI changes"), as functional placeholder screens.
- A debug-only Save panel for testing.
- Integration context for future work.

**Later (reserved in the format, not built here)**
- Archive viewer screen. Tamper resistance. Game browser (row 22, M12). Cold-start invites.
- The unlock, statistics, achievements and Hall of Heroes systems that fill the scaffolded
  sections. The RNG manager that fills the reserved `rng` sections.

**Out of scope**
- Final UI art and layout; screens stay functional placeholders like the existing ones.
- Run setup (seed entry, difficulty, modifiers): owned by the campaign system. Start writes the
  first save with whatever that system provides.
- Concrete unit, item, enemy, entity and map fields. Item transfer between players.
- Reconnecting to a live match after a drop (kit `02_REQUIREMENTS.md:116`). Resume always goes
  through the lobby.
- Steam Cloud, importing `Godot_FE` saves, timed autosave.
- Unlock gating in multiplayer drafts (doc 02 §9 leaves this to the drafting system).

## Legacy Behavior (ports from Godot_FE only)

Files read: `selected_save_file.gd` · `overworld_new/player_overworld_data.gd` ·
`overworld_new/campaign_save_info.gd` (empty stub) · `options/options_config.gd` ·
`Game Start Screen/start_screen.gd` (slot handling, by search) ·
`docs/systems/02_save_and_persistence.md` · `docs/systems/assets/templates/save_service.gd`.

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `start_screen.gd:13-15` | 3 save slots, "Slot N - LOAD" buttons, delete removes the directory | Keep count and delete; Change shape | Each save file has a solo and a multiplayer slot (row 2). Delete asks for confirmation. |
| `selected_save_file.gd:8-12` | In-place write, return code ignored | Change | Atomic write with backup. |
| `player_overworld_data.gd:5-7` | Profile inside the run resource | Change | Separate `profile.json`. Hall of Heroes kept as a scaffolded section. |
| `player_overworld_data.gd:9-27` | Seed, difficulty, modifiers, map, floors, combat maps, last room, gold, shop level, convoy | Keep intent | Seed, difficulty and modifiers in campaign `core`; the rest in sections when their systems are ported. Convoy per player (row 6). |
| `player_overworld_data.gd:30-40` | Level, prep flags, party lists, `unit_positions` | Keep intent; Change shape | Level by id; units by `uid`. `battle_prep_complete` is never set in the old code (doc 02 §4) and isn't carried over. |
| `player_overworld_data.gd:44-936` | `temp_name_list` | Drop | Dead data (doc 02 §6 `[DEAD]`). |
| `options_config.gd:13-15` | Volumes 0–10, default 5 | Keep | Carried unchanged. |
| `options_config.gd:21-33` | 0 mutes; master `v - 5` dB; music and SFX `v - 20` dB | Keep values; Defer applying | Kept as named constants in the `SettingsData.apply()` stub for the audio system (row 24). `# NOTE:` master at 10 is +5 dB, above unity; carried as-is. |
| `options_config.gd:33` | SFX volume read from `music_volume` | Change | Bug; fixed per row 14. |
| `Combat.combat_loss()` (doc 02 §5) | Run loss resets in memory, no save | Change | Loss is final, saved and archived. |

Tuning values carried over: volume range 0–10, default 5 (`options_config.gd:13-15`); dB offsets
−5 master, −20 music, −20 SFX, 0 = mute (`options_config.gd:21-33`); 3 save files
(`start_screen.gd:13-15`).

## Approach

### Layout

```
user://saves/last_selected.json          which save file was chosen last (rows 27, 28)
user://saves/save_N/                     N = 1..3
├── profile.json                         Steam name cache, play time, unlocks, achievements, stats
├── settings.json                        player-editable (row 10)
├── campaign_solo.json                   single-player campaign slot
├── combat_solo.json                     single-player combat file, only while in battle
├── campaign_multi.json                  multiplayer campaign slot (host only)
├── combat_multi.json                    multiplayer combat file, only while in battle
└── archive/<mode>_<ended_at>.json       one per ended run
```

Every file is a JSON envelope:

```json
{
  "schema_version": 1,
  "game_version": "0.1.0",
  "saved_at": 1760000000,
  "checkpoint_seq": 42,
  "core": { },
  "sections": { "<key>": { "version": 1, "data": { } } }
}
```

- `core`: typed fields this plan owns. `sections`: data owned by individual systems.
- `checkpoint_seq`: campaign and combat files only; see "Combat crash protection".
- `game_version`: the build that wrote the file. A newer one is refused; an older one migrates.
- Only `settings.json` is meant to be edited by players.

### Writing and recovering a file

| File | Meaning |
|------|---------|
| `X.json` | The live save. |
| `X.json.tmp` | A write in progress, or a finished write not yet promoted. |
| `X.json.bak` | The previous good save. |

Two extra files, not one: if the backup were also the file being written, a crash during that
write would destroy the only good copy.

Save: (1) write `X.json.tmp`, close, read back and parse; on failure delete it and return the error.
(2) Replace `X.json.bak` with the current `X.json`. (3) Rename `X.json.tmp` to `X.json`.

Load: parse each of the three that exists; truncated JSON fails to parse. Use the one with the
highest `checkpoint_seq` (`saved_at` when there is none), promote it to `X.json`, and report when
recovery happened (the UI shows a notice). If none parse, return an error and leave the files.

A crash during (1) leaves the live file untouched; between (2) and (3) the `.tmp` is complete and
load promotes it; after (3) the save is done.

### Blocks

**Profile** (`profile.json`):

| Field | Where | Notes |
|-------|-------|-------|
| `last_steam_name` | core | Refreshed from Steam on every load; shown when Steam is unavailable. |
| `play_time_seconds` | core | Total across all runs. See "Play time". |
| `created_at` | core | Unix seconds, UTC. |
| `unlocks`, `achievements`, `statistics`, `hall_of_heroes` | sections, scaffolded | Registered at version 1 with empty data until their systems exist. |

**Settings** (`settings.json`): `core` only. Starts with `master_volume`, `music_volume`,
`sfx_volume` (0–10, default 5). New settings are added as fields of `SettingsData`.

**Campaign** (`campaign_solo.json`, `campaign_multi.json`):

| Field | Where | Notes |
|-------|-------|-------|
| `mode` | core | `solo` or `multiplayer`. |
| `seed`, `difficulty`, `modifiers` | core | Ids, not enum ints. Generated results are saved too, so a generator change can't break a run in progress. |
| `play_time_seconds`, `started_at`, `last_opened` | core | Seconds; timestamps are Unix seconds, UTC. |
| `combat_in_progress` | core | See "Combat crash protection". |
| `level_id`, `floors_climbed`, `combat_maps_completed`, `progress` | core / sections | Carried by intent (`player_overworld_data.gd:16-18`). |
| `rng` | section, reserved | Owned by the upcoming RNG manager (row 8). |
| `players[]` | core | One entry per seat: `seat`, `steam_id` (string, empty in solo), `sections` (roster, inventory, convoy, economy). |
| `multiplayer` | core, multiplayer only | `host_steam_id`, `required_steam_ids`. |

**Combat** (`combat_solo.json`, `combat_multi.json`), a stub: `core` holds turn and phase;
`sections` reserves `enemy_units`, `entities` and `rng`. Player units carry their persisted `uid`
and owning seat.

**Archive record** (`archive/<mode>_<ended_at>.json`): `mode`, `outcome` (won or lost),
`started_at`, `ended_at`, `play_time_seconds`, `seed`, `difficulty`, `floors_climbed`, the
players' Steam ids and names, and a copy of each player's roster section. Plain data, so the host
can send it to clients. The viewer screen is later.

### Combat crash protection

1. **Begin pressed** (after battle prep): set `combat_in_progress = true`; write the combat file,
   then the campaign, with the same `checkpoint_seq`. Quitting during prep resumes at the "room
   entered" checkpoint; prep is redone at no cost.
2. **End of every player phase** (multiplayer: after every player has ended their turn), and
   **Save & Quit**: write the combat file, then the campaign, with a new shared `checkpoint_seq`.
   The combat file is overwritten, never deleted on resume.
3. **Battle ends:** clear `combat_in_progress`, write the campaign (now carrying the battle's
   results), then delete the combat file.

**Invariant:** while `combat_in_progress` is true, everything the battle changes (unit HP, items
used, deaths) lives only in the combat file. The campaign file still holds the state from when
Begin was pressed. That is what makes "retry the battle" possible without a separate snapshot.

Load:

| `combat_in_progress` | Combat file | Result |
|----------------------|-------------|--------|
| false | none | Normal resume. |
| false | present | Crash during step 1 or 3. Delete it; resume normally. |
| true | `checkpoint_seq` equals the campaign's | Resume the battle at the start of the next enemy phase. |
| true | exactly the campaign's + 1 | Crash between the two writes; the combat file is complete and newer. Resume from it. |
| true | missing or any other seq | Retry the battle from Begin (row 15). The UI says so. |

A crash during an enemy phase resumes at the end of the preceding player phase, so the enemy
phase replays. It replays identically only once the RNG manager saves its state (row 8); until
then it can roll differently. `# ASSUMPTION`

### Play time

`SaveService` measures elapsed time with `Time.get_ticks_msec()`. On every campaign or combat save
(every trigger in row 13 except settings), it adds the time since the last flush to the active
campaign and the profile. The flush point moves only after the write succeeds, so nothing is
counted twice. Each checkpoint therefore also writes `profile.json`. Settings Apply never touches
either file. Unmeasured; expected cheap.

### Per-player sections

A per-player system extends `PlayerSaveSection` and implements `capture(seat)`,
`restore(seat, data, version)`, `reset(seat)` and `migrate(data, from_version)`. It registers once;
`SaveService` calls it for each entry in `players`. Seats are stable ids for the campaign's life.
Solo is the same path with seat 0. Missing data for a seat loads via `reset(seat)`. Only the host
writes the array; a client's copy of its own run is a replica (kit P16), never written.

### Multiplayer flow

**Resume:**
1. Host opens their save file, chooses Multiplayer → Resume Campaign. `SaveService` loads
   `campaign_multi.json` and the lobby opens in resume mode.
2. The lobby lists every required player with a status: missing, joined, ready. The host can open
   the Steam overlay to invite (`Steam.activateGameOverlayInviteDialog(lobby_id)`).
3. Each joiner must first pick their own save file (their profile receives the run's progress).
   On `SteamNetwork.peer_connected`, the host looks up the peer's Steam id
   (`get_steam_id_for_peer_id`), checks it against `required_steam_ids` and the version handshake,
   and disconnects anyone who fails, with a reason the client shows.
4. Each player presses Ready. Ready state is built on the host (kit rule 13) and broadcast.
5. The host's Resume button enables only when every required player is present and ready. It
   sends the run state to every client and moves everyone to loading through
   `SceneRouter.goto_screen_for_everyone()`.

There is no mid-gameplay rejoin: a player who drops leaves the others to finish or Save & Quit.

**New campaign:** same lobby without the required list. Pressing Start locks the current members
as the campaign's players (row 21) and writes the first save.

**Checkpoints:** the host writes `campaign_multi.json` with every player's data, then broadcasts
the checkpoint; each client writes its own `profile.json` (row 20).

**Run end:** the host writes the archive record, broadcasts it, and each client writes it to its
own `archive/` (rows 11, 23). Then the host's multiplayer slot is cleared.

**Version:** the host sets `game_version` as lobby data; the lobby screen shows a mismatch before
joining; the host re-checks in a handshake RPC and refuses mismatches.

**Invites:** accepting a Steam invite while the game runs fires `Steam.join_requested` (kit 🔵:
exists, not confirmed in live runs). Before joining, the save file is picked without showing Save
Select (row 27): the last selected one; else the first non-empty one; else a new save 1. During a
solo run the player is asked to Save & Quit first (row 29). `SteamNetwork` holds the pending lobby
id while this happens.

GodotSteam calls this flow relies on, verified with `ClassDB` against the installed 4.23.1
extension: `SteamMultiplayerPeer.get_steam_id_for_peer_id(peer_id: int) -> int`,
`Steam.activateGameOverlayInviteDialog(lobby_id: int)`, `Steam.setLobbyData(lobby, key, value)`,
`Steam.getLobbyData(lobby, key) -> String`, `Steam.setLobbyMemberData(lobby, key, value)`,
`Steam.getLobbyMemberData(lobby, user, key) -> String`, signal `Steam.join_requested`. Live
behavior is still unconfirmed until M9–M11.

### UI changes

| Screen | Today | Change |
|--------|-------|--------|
| Start (`start_screen.tscn`) | Play → Main Menu, Options, Quit | Play → **Save Select**. Options button removed (row 10). |
| **Save Select** (new) | — | Shown every launch; there is no way past it without choosing. Three cards: save number, Steam name, total play time, solo slot summary (floor, last opened), multiplayer slot summary (players, last opened), or "Empty". Focus starts on the last selected file. Choosing an empty card creates that save file. Delete with confirmation. Notice when a file was recovered from backup or couldn't be read. Back → Start. |
| Main Menu (`main_menu.tscn`) | Solo, Multiplayer, Options, Back to Start | Header shows the save file. **Solo:** Continue Run, or New Run when empty; Abandon Run (with confirmation, archived as lost). **Multiplayer:** Host New Campaign, Resume Campaign (when the slot has one), Join. Options. Back → Save Select. |
| **New Run** (new, placeholder) | — | Start button only. Pressing it writes the first save (row 13). Run setup belongs to the campaign system. |
| Options (`options_screen.tscn`) | Placeholder note | Reached from the Main Menu only. Master, Music and SFX sliders (0–10) and an Apply button. Apply writes only the open save file's `settings.json`; Back discards unapplied changes. No audible effect until an audio system exists (row 24). |
| Lobby (`lobby_screen.tscn`) | Host, join by code, member list, Start, Leave | New-campaign or resume mode. Invite Friends button (host). Ready toggle (everyone). Member list shows status, version mismatch and seat. In resume mode, required players who haven't joined are listed as missing. Start / Resume enabled only when allowed. Join rejection reasons shown. |
| Loading (`loading_gate.tscn`) | Placeholder | Loads a saved run or battle when resuming. |
| Gameplay (`gameplay.tscn`) | Placeholder | Pause menu with Save & Quit (host only in multiplayer; clients get Leave). A small "Saving…" indicator and an error notice on failure. Debug-only Save panel (row 25). |
| Results (`results_screen.tscn`) | Next Round / Leave Match | Shows the run's outcome and "Saved to archive". |

Menu flow, modelled on The Binding of Isaac's (title, file select, then a per-file main menu):

```
Start        Play -> Save Select                      Quit
Save Select  choose a file -> Main Menu               Back -> Start
Main Menu    Solo: Continue Run | New Run -> New Run screen
             Multiplayer: Host New | Resume | Join -> Lobby
             Options -> Options                       Back -> Save Select
Options      Apply (writes settings.json only)        Back -> Main Menu
Any screen   accepted invite -> save file picked by row 27 -> Lobby
```

`SceneRouter.Screen` gains `SAVE_SELECT = 7` and `NEW_RUN = 8`, appended (the enum is append-only,
`scene_router.gd:40-41`). The flow comment in `scene_router.gd` is updated in the same change, and
SAVE_SELECT also ends any lobby session, like START and MAIN_MENU.

### Classes and files

| File | Kind | Role |
|------|------|------|
| `scripts/autoload/save_service.gd` | autoload `SaveService` | Save-file and slot selection, load/save, section registry, checkpoints, play time, signals. |
| `scripts/save/save_file.gd` | `SaveFile` | Atomic write and recovery for one file. The only code that touches save files, so tamper resistance can be added there later. |
| `scripts/save/save_section.gd` | `SaveSection` | `@abstract` contract for file-level data. |
| `scripts/save/player_save_section.gd` | `PlayerSaveSection` | `@abstract` contract for per-player data. |
| `scripts/save/save_migrations.gd` | `SaveMigrations` | Version tables for the envelope and `core`. |
| `scripts/save/profile_data.gd`, `settings_data.gd`, `campaign_data.gd`, `combat_data.gd`, `archive_record.gd` | `ProfileData`, `SettingsData`, `CampaignData`, `CombatData`, `ArchiveRecord` | Typed `core` fields with `to_dict()` / `from_dict()`. |
| `scenes/screens/save_select_screen.tscn` + script | screen | Save Select. |
| `scenes/screens/new_run_screen.tscn` + script | screen | New Run placeholder. |
| `scenes/ui/pause_menu.tscn` + script | UI | Save & Quit / Leave. |
| `scenes/debug/save_debug_panel.tscn` + script | debug UI | Row 25. |

Edited: `project.godot` (autoload line; `config/version` already added), `scene_router.gd`,
`steam_network.gd`, and the scenes and scripts listed in "UI changes".

Code rules, each verified on Godot 4.7.1 with a throwaway probe:
- `JSON.parse` returns every number as a float and every key as a string, so `from_dict()` converts
  every int and key explicitly.
- Steam ids are strings in files. Probe: `76561198000000001` round-tripped as a number came back as
  `76561198000000000`.
- Writes pass `full_precision = true` to `JSON.stringify(data, indent, sort_keys, full_precision)`.
  Probe: the default wrote `0.30000000000000004` as `0.3`.
- `DirAccess.rename_absolute` replaces an existing file on Windows. Probe: returned `OK`, new
  content in place.

Also: Unregistered sections are kept on re-save and dropped on a new run.
Missing sections load via `reset()`. Every failure reaches the caller as an `Error` or a signal.

### Tamper resistance (later)

Players can edit `profile.json` today. `SaveFile` is the only reader and writer, so a keyed hash or
an encoded body (`FileAccess.open_encrypted_with_pass`) can be added there without touching
callers. Neither stops a determined player, since the key ships with the game; both stop casual
edits. Settings stay plain.

### Integration with future work

None made yet; needs approval (touches `CLAUDE.md` and the plan template).

1. `docs/design/save-system.md`: the living contract (layout, envelope, recovery, sections, ids,
   versioning). Written in M13.
2. `CLAUDE.md` §1 "Ask when": "the change adds state that must survive a restart, quit or resume:
   read `docs/design/save-system.md` and state the save impact." §4: checkbox "Save impact stated."
3. A `## Save Impact` section in the plan template (`docs/standards/gdscript-reference.md` §1).
4. A `@tutorial` link in every `SaveSection` / `PlayerSaveSection` implementer's class doc.

## Work Breakdown

Each milestone is one commit or a small group of commits, ends in something you can run and check,
and doesn't depend on later ones. On Windows, save files are under
`%APPDATA%\Godot\app_userdata\Bandit Bash\saves\` and open in any text editor.

Every milestone also runs the `CLAUDE.md` §3 checks (`--import` after new classes, `--check-only` on
each changed script) with the Godot binary recorded in `CLAUDE.md`.

| # | Milestone | What gets built | Risk | How you test it |
|---|-----------|-----------------|------|-----------------|
| M1 | File layer | `SaveFile`, `SaveMigrations`, headless tests in `tests/save/` | 🟢 | Run `godot --headless --path bandit-bash --script res://tests/save/run_all.gd`; every case prints PASS: round trip, each crash point recovers, all-corrupt reports an error, newer `game_version` refused, Steam id survives as a string, floats keep full precision. |
| M2 | Save files and Save Select | `SaveService` (save-file part), `ProfileData`, `last_selected.json`, Save Select screen, Start → Save Select, Options removed from Start, SceneRouter enum | 🟡 | Launch, Play → three empty saves; there is no way to the Main Menu without choosing one. Choose save 2 → Main Menu. Quit, relaunch: focus starts on save 2, which shows your Steam name and play time. Back from Main Menu returns to Save Select. Delete with confirmation. Corrupt `profile.json` by hand → the card shows a recovery notice and loads the backup. |
| M3 | Settings (stub) | `SettingsData` with stubbed `apply()`, Options sliders and Apply | 🟢 | Move sliders, Apply: only `settings.json` changes (check timestamps on the other files). Back without Apply discards. Switch save files: each keeps its own values. Relaunch: the last selected file's values load at boot (row 28). No sound changes; that's expected. |
| M4 | Solo campaign slot | `CampaignData`, Main Menu solo buttons, New Run screen, debug panel (checkpoint, win, lose) | 🟡 | New Run → Start → `campaign_solo.json` appears. Debug "Room entered" bumps `checkpoint_seq`. Quit and Continue resumes. Play time rises in both files on each save. Abandon → slot empties. |
| M5 | Sections | `SaveSection`, `PlayerSaveSection`, scaffolded profile sections, reserved `rng` | 🟡 | Headless: per-player section called once per seat with 1, 2 and 4 seats; unknown section survives a re-save and is dropped on a new run. In game: `profile.json` shows the four empty sections. |
| M6 | Combat stub and crash protection | `CombatData`, `combat_in_progress`, debug Begin / End Player Phase / End Battle | 🟡 | Begin, end two player phases, kill the game from Task Manager, relaunch, Continue → resumes in battle at the right phase. Kill between Begin and the first save landing → battle restarts with a notice. Each row of the load table has a matching debug scenario. |
| M7 | Run end and archive (solo) | `ArchiveRecord`, Results screen text | 🟢 | Debug "Win run" and "Lose run": slot empties, a file appears in `archive/`, Results says "Saved to archive". |
| M8 | Pause menu, Save & Quit | Pause menu, "Saving…" indicator, failure notice | 🟢 | Save & Quit mid-run and mid-battle → main menu → Continue resumes. Make the save folder read-only → failure notice appears and the game doesn't quit. |
| M9 | Lobby: version, invites, ready | `game_version` lobby data and handshake, Invite Friends, `join_requested`, Ready toggle | 🔴 | Two machines or two Steam accounts. Invite through the overlay; accept while running → joiner lands in the lobby using their last selected save file. Delete that file first and repeat → the first non-empty file is used; with all empty → save 1 is created. Accept during a solo run → the Save & Quit prompt appears. Change one build's version → join refused with a reason. Ready toggles show on both screens. **Untested live until you run this.** |
| M10 | Multiplayer campaign save | Host writes `campaign_multi.json` with every player; client profile writes; Steam id lookup in `SteamNetwork` | 🔴 | Start a 2-player campaign; the host's file has two `players` entries with the right Steam ids; the client's `profile.json` play time rises at each checkpoint; the client has no campaign file. |
| M11 | Multiplayer resume and archive | Resume Campaign, required-player list, Resume button gating, archive broadcast | 🔴 | Host Save & Quit; both relaunch; host Resume Campaign → client shows as missing; invite; client joins → Resume enables only after both Ready. A third account is refused. Debug "Win run" → both players get the archive file. |
| M12 | Friends' lobby browser and cold-start invites | List of friends in a Bandit Bash lobby with Join; `+connect_lobby` launch argument | 🟡 | A friend hosts → their lobby appears in your list → Join works. Accept an invite with the game closed → it launches into the lobby with the row 27 save file. Final scope to be confirmed against your ticket. |
| M13 | Integration docs | `docs/design/save-system.md`, `CLAUDE.md`, plan template | 🟢 | Needs approval. Review the text. |
| Later | Archive viewer, tamper resistance | — | — | — |

Tests under `bandit-bash/tests/save/` exercise `SaveFile` and the data classes directly, writing to
`user://test_saves/`. They can't use `SaveService`: autoloads are not loaded in `--script` mode
(verified with the probe), which is why `SaveFile` and the data classes don't depend on it.

Performance: unmeasured. A checkpoint writes up to three small files. Benchmark only if files grow.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| Start screen Play target | Scene property | `MAIN_MENU` (`start_screen.tscn`) | `SAVE_SELECT` | Suggested | `start_screen.tscn` | 🟡 |
| Start screen Options button | Scene node | present | removed (row 10) | Suggested | `start_screen.tscn` | 🟡 |
| Main Menu Solo button | Scene node | NavButton → `LOADING` | handled by a main-menu script | Suggested | `main_menu.tscn` | 🟡 |
| `SceneRouter.Screen` | Enum | 7 values | `SAVE_SELECT = 7`, `NEW_RUN = 8` appended | Suggested | `.tscn` files storing `target_screen` | 🟢 |
| `SteamNetwork` API | Public methods | — | peer-to-Steam-id lookup, pending invite, lobby data helpers | Suggested | callers of `SteamNetwork` | 🟢 |
| `project.godot` | Setting | — | `config/version="0.1.0"` | Applied | `project.godot` | 🟢 |

New public surface (contract-setting, not breaking): autoload `SaveService`; `class_name`s
`SaveFile`, `SaveSection`, `PlayerSaveSection`, `SaveMigrations`, `ProfileData`, `SettingsData`,
`CampaignData`, `CombatData`, `ArchiveRecord`; the on-disk format; the version handshake and ready
RPCs.

## Verification

Per milestone, in the "How you test it" column. Across all of them:
- The headless suite (M1, M5) passes on every commit after M1.
- `--check-only` is clean on every changed script.
- Multiplayer milestones (M9–M11) stay **untested live** until you run the two-machine steps.

## Rollback

Each milestone is its own commit; revert it. Scene changes (M2, M4, M8, M9) revert with their
commit. Save files under `user://saves/` are inert without the code; delete the folder to start
clean.
