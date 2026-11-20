# P00 decisions: Save system

The answered questions of [the plan](../2026-10-13-save-system.md), moved here unchanged on November 9, 2026. Numbers are stable: code and plans cite them. To read one question: `grep -n "^| 34 |" P00-save-system.md`.

## Questions

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

| 30 | Where in the phase order the end-of-phase battle save lands (BUG-024) | **BF6 default, to confirm.** As the phase's last End Turn resolves, before its playback. That command resolves the player Phase End, the whole enemy phase, the hooks after it (darkness, reinforcements) and the next player Phase Start, intents included, so the save holds the start of the next player phase; a resume re-runs none of it and doesn't show the enemy phase's playback again. Saving once the playback settles was rejected: a crash while the enemy phase plays would lose the whole phase. `# ASSUMPTION:` in `ui/battle/battle_screen.gd`. |
| 31 | A player phase end that finishes the battle | **BF6 default, to confirm.** No checkpoint; the battle's end (`CampaignService.end_battle()`) saves it, as a battle won mid-phase already is. |
| 32 | A failed end-of-phase save | **BF6 default, to confirm.** Logged as an error and play goes on: the previous save stays on disk and the next checkpoint writes the change, as a failed campaign command's save does (`CampaignService.submit_command`). The player isn't told; Save & Quit still reports its own failure. |
