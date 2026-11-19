# Rebalance and Feature Updates

The one place for playtest feedback and for the tuning and feature changes it leads to. Entries
start here as ideas; the user accepts them; the orchestrator turns accepted ones into build steps.
Every entry targeted at M2 is built before M2 is marked complete.

**Status:** ideation, opened November 18, 2026 (user). Nothing here changes the game until it is
**Accepted** and built. Accepted rules that change the vision go through the ideation thread;
values that only tune live here and in the data.

## How it works

1. **Log.** Write playtest notes in the [Inbox](#inbox) in any form: what you did, what happened,
   how it felt. A date and the map or unit is enough.
2. **Triage** (orchestrator). Each note becomes one or more entries in
   [Entries](#entries), or goes elsewhere:
   - a defect (something doesn't work as designed) → [bug-tracker.md](../plans/bug-tracker.md);
   - a rule the vision states differently → the ideation thread (design items);
   - everything else (a value, a feel, a missing feature) → an entry here.
3. **Decide** (user). Each entry gets a status: **Open** (logged, not decided), **Accepted**
   (do it, with a target), **Rejected** (with why), **Parked** (after the MVP).
4. **Build** (orchestrator). Accepted entries are batched into build steps: tuning into a
   **rebalance pass** (RB1, RB2...), features into the plan that owns the system. The entry
   records its step, then **Done** with the commit.

**Targets:** **M2** (built before M2 is complete), **M3** (before the solo run is complete),
**Later**.

**Tuning values:** an accepted value changes the data, the design doc that lists it (for example
unit-roster.md) and the tests that check it, in one change, as the November 17 rebalance did.

## Inbox

Raw playtest notes, newest first. The orchestrator empties this into Entries.

- *(empty)*

## Entries

IDs are permanent. **Type:** Balance (a value), Feature (new or changed behaviour), Feel (UI,
pacing, readability).

| ID | Logged | Area | Type | What | Proposal | Status | Target | Step |
|----|--------|------|------|------|----------|--------|--------|------|
| RF-001 | November 17, 2026 (user) | Units | Balance | The starting army felt fragile | Drengr HP 24 → 40 and a Simple Sword instead of the Simple Axe; Archer HP 13 → 21; Hakkapel HP 22 → 36 | **Done** (84d0a4e) | M2 | — |
| RF-002 | November 16, 2026 (MP10a report) | Maps | Balance | Turn par on all ten M2 maps is a first guess (`# ASSUMPTION` in each map's `.tres`) | Set each par from playtest turn counts | Open | M2 | — |
| RF-003 | November 17, 2026 (EN7 report) | Maps | Balance | `bandit_camp` at step 1 was won on turn 1 by killing the Hexer leader | Watch in play; move the leader slot back, or add cover in front of it | Open | M2 | — |
| RF-004 | November 15, 2026 (enemy-packs.md decision 4) | Enemies | Balance | Reinforcement waves send a whole basic or hard pack at the step's size (`# ASSUMPTION` in `WaveGroups.draw_group`) | Settle wave sizes in play; the user's guess is that Defend maps field more but weaker units | Open | M2 | — |
| RF-005 | November 15, 2026 (enemy-packs.md decision 5) | Enemies | Balance | The first 2 standard combats of each step draw the basic pool | Tune the 2 in play | Open | M2 | — |
| RF-006 | November 16, 2026 (P03 question 8) | Economy | Balance | Modified-item point values: AtkX 3, Range 2, weight −0.25 (`# ASSUMPTION` in `prices.gd`) | Tune once events modify items in play | Open | M3 | — |
| RF-007 | November 16, 2026 (UI13 report) | Runes | Feature | A rune can only be cast from a unit's own menu, so once every unit has acted none can be cast; the vision puts runes outside the action economy | A battle-level Runes entry (key, pad button, HUD button) usable at any time in the player phase | **Done** (UI14, merged November 18, 2026) | M2 | P07 UI14 |
| RF-008 | November 15–19, 2026 (UI12, UI13, EN7, MP12, UI14, UL1, UL4, UL5, UL8, AU1, UL2 reports) | UI | Feel | **Replaced in UL2** (November 19, 2026; every source in [art-sources.md](art-sources.md)): the "¤" object intent, "§" signature and the other intent glyphs (Godot_FE action icons, tinted by each intent's theme colour); the "Ø" Block ban (now Godot_FE's shield with the "Ø" over it); the board's map-object symbols (Godot_FE entity and dungeon-tile art); the terrain's greybox colours (Godot_FE tiles); letter tokens for every unit type, enemy class, mini-boss, the Powder Baron and the breakables (sprites); the reward row's "?" on item picks (item icons). **Still placeholders:** the house searchable (its "?" on the dark circle); the Spiked Wall and Spilled Oil terrain (greybox colours); 9 items' per-kind fallback icons (Godot_FE's white glyph icons; art-sources.md); one tile per terrain, so rivers, walls and cliffs don't join up; the board's 45% dim on spent objects; the fuse badge's `danger_fill` chip; the sprite picks marked as assumptions in `unit_sprite_table.gd`; gold Recall pick, the rune preview's "Now / After"; the rune bar's circle slots, gold focus ring, ✕, 0.35 dim, top-right place (it briefly overlaps the save indicator) and which art goes with which rune (UI14; the alphabetical match confirmed by the user November 18, 2026); the event log's group icons, drawn shapes in `accent` on a `panel` circle (UL4); the victory reward row's "?" mark on a `panel` circle, for a reward without art (UL5, `reward_icon.gd`); the heirloom bar's icons (UL8, `assets/sprites/heirlooms/`): one flat white symbol per kind (profile, behavior, economy and Shop, army, commander, curse) tinted `accent` (curses `danger`, spent ones `text_muted`) on the rune slot's circle, the generic "?" mark for an heirloom without art, the ready look's inner `accent` ring and `accent` count chip, the 0.6 s pulse, and the bar's place at the left of the battle HUD's top strip; kept by UL1: three Stance pip colours (change, overflow, preview), the darkness damage preview's lilac, the campaign map's 8 node colours and letters, letter tokens as the fallback for a type with no sprite; third-party placeholder art: the Hound's `hound.png` (32rogues, Seth Boyles: no redistribution, no use with generative-AI projects; kept by the user November 19, 2026, as all art is placeholder until an artist is contracted); placeholder audio: Godot_FE's 8 tracks and 54 sounds, licensed, and the `ui_refused` cue borrowing `menu_back.ogg` (AU1, `bandit-bash/assets/audio/README.md`) | Replace in the art pass (the audio in AU2) before any release or public push, or confirm | Open | Later | P15 UL2 (part) |
| RF-009 | November 5, 2026 (M1) | All | Balance | M1's tuning pass was deferred to M2's playtest | Fold into the first rebalance pass | Open | M2 | — |
| RF-010 | November 18, 2026 (user) | Enemies | Feature | The Shieldbearer is too strong. It should be an interesting enemy that asks the player to strip its Stance and pick favourable engagements | A trait that grants DEF from current Stance (proposed: +2 DEF per Stance point); base DEF greatly reduced (proposed 7 → 1, so with the Iron Shield's +2 it has 9 at full Stance 3, as now, falling 2 per Stance lost to 3 when Exposed); less movement (proposed MOV 5 → 4) and less damage (proposed MGT 2 → 1); its Simple Lance (Balance) becomes an enemy-only **Shield** weapon with a neutral profile. See [RF-010 notes](#rf-010-notes) | **Done** (EN18, e13ec8a: Braced and the Shieldmace on the None profile; P05 question 45) | M2 | P05 EN18 |
| RF-011 | November 18, 2026 (EN8, EN18 reports) | Enemies | Balance | Mini-boss signature moves as built: Command raises Stance past the maximum (every 3rd enemy Phase Start); Fortify's Block on your units is cleared by your own Phase Start refresh, so it helps them only through the enemy phase; Hex Storm targets by foes within 2 tiles (`# ASSUMPTION`); the Bloodhound's move is named "Blood Scent" (a placeholder name); with Braced (EN18), Command lifts an escorting Shieldbearer to Stance 4 and DEF 11 (Brigand Captain, steps 2–3) | Watch in play: Command's over-max Stance, Fortify's cooldown, Hex Storm's reach; name the Bloodhound's move | Open | M2 | — |
| RF-012 | November 18, 2026 (EN8 report) | UI | Feel | The danger zone doesn't show the Bloodhound's second move after a kill | Show it, or accept it as a surprise the intent warns of | **Rejected** (user, November 18, 2026: leave it; the danger zone already shows the kill, and the event log (UL4) shows the move) | M2 | — |
| RF-013 | November 18, 2026 (EN8 report) | Progression | Balance | Godot_FE gave +40 XP for defeating a boss; EN8 dropped it | Decide whether mini-bosses and the Powder Baron give bonus XP | **Rejected** (user, November 18, 2026: no kill bonus; the vision's shared XP by combat type (key 70, boss 100) already rewards the larger fights, and a kill bonus would bring back funnelling) | M2 | — |
| RF-014 | November 18, 2026 (user) | Darkness | Feature | The darkness spreads inside the end-of-turn step with no time to watch it | A darkness phase of its own (banner, turn-bar entry, the spread played tile by tile), and maybe its damage moved into it, damage before the creep, both sides at once ([ui-lift.md](ui-lift.md#darkness-phase), P06 DK7). Moving the damage changes the-darkness.md through the ideation thread | **Done** (DK7, 2d7c269; P06 question 16) | M2 | P06 DK7 |
| RF-015 | November 18, 2026 (EN18 report) | Enemies | Balance | The reworked Shieldbearer: the Shieldmace attacks for 5 (4 + MGT 1), so 1–2 damage a hit against DEF 3–4, and it barely threatens anyone; a Hedge Healer's Field Dressing (+1 Stance) gives it back 2 DEF, which may make the Field Hospital too sticky | Watch both in play; raise the Shieldmace's damage if it stops mattering | Open | M2 | — |
| RF-016 | November 18, 2026 (user, via EN18 report) | Enemies | Feature | A Guard that plugs holes: Shieldbearers take chokepoints and key tiles to keep player units from reaching their ranged allies | A new Guard target rule (the AI already scores tiles and knows which player units reach which tiles); a P05 step | Open | Later | — |
| RF-017 | November 18, 2026 (DK7 report) | Darkness | Balance | With damage in the darkness phase, a player unit takes the enemy phase's hits and then the darkness's in one turn, with no Phase End heal between; enemy "until Phase End" modifiers no longer reduce darkness damage; the spread plays at 0.08 s a tile, the banner's 1 s fade overlaps the damage numbers, and its violet text sat on a panel (fixed in UL1F: `text` on a `darkness` fill, 5.00:1) | Watch how often the darkness finishes off player units; tune the tile pace | Open | M2 | — |
| RF-018 | November 18, 2026 (EN11 report) | Enemies | Balance | Keg Barrage's first values: every 2nd enemy phase (first on phase 2), reach 5 by grid distance ignoring walls (`KegBarrage.REACH`), the thrown keg's fuse 2 enemy phases (`MapObjects.FUSE_PHASES`), and a lit keg blowing at its first darkness contact (`LIT_CONTACT_LIMIT` 1) | Tune in play | Open | M2 | — |
| RF-019 | November 18, 2026 (EN11 report) | Maps | Balance | `powder_keep`: 8 guards at level 6 (step 3's 5 + 1, as in a key combat) and turn par 14, the low end of the vision's 14–18 (both `# ASSUMPTION` in the map's `.tres`); the Baron at level 8, always Stalwart; a level 5 test army lost on turn 6 headless | Settle in play | Open | M2 | — |
| RF-020 | November 18, 2026 (EN11 report) | Enemies | Feature | The boss fight has no scripted beats beyond the barrage and the darkness. Godot_FE's boss map sent reinforcement waves on turns 4, 7 and 11 (dropped, P05 question 46); a half-HP second phase is another candidate | Decide after the first boss playtest: waves, a second phase, or neither | Open | M2 | — |
| RF-021 | November 18, 2026 (EN11 report) | UI | Feel | A lit keg's fuse count isn't shown on the board | Show the fuse on the keg's mark (P15 UL2, map objects as icons) | **Built** (UL2, November 19, 2026: the enemy Phase Ends left, the current one included, as a number on a `danger_fill` chip on the keg's token, counting down as each fuse burns; awaiting merge) | M2 | P15 UL2 |
| RF-022 | November 18, 2026 (UL4 report) | UI | Feel | The event log doesn't say what was looted ("Cutthroat loots Chest at (4, 2)"): no fact carries the item taken | Name the item, which needs a fact change | Open | Later | — |
| RF-023 | November 19, 2026 (UL3 report) | Darkness | Feel | The darkness layers read close together: Dusk was raised to 0.45 (RF-017), next to Gloom 0.50 and Abyss 0.70 | First pass 0.45 / 0.60 / 0.75 (UL3, marked ASSUMPTION in `darkness_overlay.gd`); settle at the M2 exit playtest | Open | M2 | RB1 |
| RF-024 | November 19, 2026 (AU1 report) | Audio | Feel | AU1's first-pass mix, marked ASSUMPTION: 4 voices per sound effect and 2 per UI sound, a 1 s crossfade, ducking at -10 dB over 0.25 s (unused), key combats on the standard battle tracks, Save Select / New Run / Lobby / the node placeholder on the menu track, the refused sound borrowing `menu_back.ogg`, a disabled campaign map node playing the refused sound. The agent couldn't listen; a probe confirmed playback | Listen and settle at the M2 exit playtest | Open | M2 | RB1 |
| RF-025 | November 19, 2026 (UL2 report) | UI | Feel | The board has no elite marker: an elite (a prefixed enemy, a leader) shows only by name in the panels and the unit detail; the leader keeps its outline | Decide at the M2 exit playtest; a board marker would go in UL6 | Open | M2 | P15 UL6 |
| RF-026 | November 19, 2026 (UL2 report) | UI | Feel | Side reads only by outline colour on the board (colour-blind check); no sprite is shared between sides, but nothing besides the colour marks a side | A shape per side on the token (base or HP bar), in UL6 | Open | M2 | P15 UL6 |
| RF-027 | November 19, 2026 (UL6 estimate) | UI | Feel | Strike pacing follows Godot_FE: each hit or crit waits its number's full 1.0 s and a Miss or No damage 0.75 s, so a two-hit attack with a counter takes about 3 s at speed 1 and an enemy phase of five attackers 10–15 s (M1 used a 0.35 s hold) | Judge at the M2 exit playtest; the values are `@export`s | Open | M2 | RB1 |

## Entry notes

### RF-010 notes

Today (`data/enemies/shieldbearer.tres`, enemy-roster.md): HP 25, MGT 2, SPD 2, DEF 7 (+2 from the
Iron Shield, which also gives 1 Block Before Combat), RES 1, MOV 5, Stance 3, Heavy movement,
Armored, a Simple Lance (Balance). Its trait is **Shield Wall** (Phase Start: every adjacent unit,
friend or foe, gains 2 Block).

Accepted November 18, 2026 (user) with the recommendations below: the new trait replaces Shield Wall,
"less speed" is MOV, and the neutral Shield is a Standoff against every profile (the vision update
goes through the ideation thread).

1. **Shield Wall:** the new trait replaces it (recommended: one trait per class, and Shield Wall's
   Block on its neighbours is part of why it feels strong), or joins it. Replacing it changes the
   Field Hospital and Shield and Bolt puzzles' text in enemy-roster.md.
2. **"Less speed":** movement (MOV 5 → 4, recommended; it is already Heavy) or the SPD stat (already
   2, the lowest of any class).
3. **The neutral Shield weapon:** the triangle has no neutral attacking profile (None is the
   healer's staff, which never attacks). A Standoff against every profile is a new rule for
   game-vision.md's Weapon Profile Triangle, so it goes through the ideation thread.
4. **Fully mitigated hits don't cost Stance** (game-vision.md, Stance and Exposure). At full Stance
   with 9 DEF, weak hits do nothing and so can't start the strip. The counterplay is Stance removal
   that doesn't need damage (the Shatter rune, the Hexer's Curse on its own pack), strong hitters,
   and favourable matchups. That is the intended puzzle, but the values should leave the player's
   starting army a way in.
5. **The Iron Wall** (P05 EN8's mini-boss, built on the Shieldbearer, with Fortify) inherits the
   rework.
6. **Build:** DEF from current Stance needs a value the effect system may not have yet, so this is
   a feature step in P05 (after EN8), not a values-only rebalance pass.

## Rebalance passes

Built batches of accepted entries.

| Step | Entries | Status |
|------|---------|--------|
| *(none yet)* | | |
