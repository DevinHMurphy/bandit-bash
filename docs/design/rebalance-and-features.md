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
| RF-008 | November 15–18, 2026 (UI12, UI13, EN7, MP12, UI14, UL1, UL4 reports) | UI | Feel | Placeholder glyphs and colours: "¤" object intent, "Ø" Block ban, "§" signature, gold Recall pick, the rune preview's "Now / After"; the board's map-object symbols and their dimmed spent look (MP12, `map_object_mark.gd`); the rune bar's circle slots, gold focus ring, ✕, 0.35 dim, top-right place (it briefly overlaps the save indicator) and which art goes with which rune (UI14; the alphabetical match confirmed by the user November 18, 2026); the event log's group icons, drawn shapes in `accent` on a `panel` circle (UL4); kept by UL1: three Stance pip colours (change, overflow, preview), the darkness damage preview's lilac, the campaign map's 8 node colours and letters, letter tokens for units without sprites | Replace in the art pass, or confirm | Open | Later | — |
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
| RF-021 | November 18, 2026 (EN11 report) | UI | Feel | A lit keg's fuse count isn't shown on the board | Show the fuse on the keg's mark (P15 UL2, map objects as icons) | Open | M2 | P15 UL2 |
| RF-022 | November 18, 2026 (UL4 report) | UI | Feel | The event log doesn't say what was looted ("Cutthroat loots Chest at (4, 2)"): no fact carries the item taken | Name the item, which needs a fact change | Open | Later | — |

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
