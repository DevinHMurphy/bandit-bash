# Enemy Packs

A planning doc for the enemy groups a run fields: which packs exist, what size they are at each
difficulty step, which pack goes with each mini-boss, and where the Duelist appears. It works out
what [enemy-roster.md](enemy-roster.md) and [game-vision.md](game-vision.md#run-structure) leave
open. Nothing here is decided until it is in [Decisions](#decisions), and the vision and
enemy-roster.md are updated through the ideation thread.

**Status:** rules decided November 15, 2026 (user); the pack lists are still to write. Feeds
P05 EN17 (pack pools), EN7 (leaders), EN8 (mini-bosses) and P04 MP10 (the M2 map set).

## Where it stands

**The rules packs must meet** (game-vision.md, Run structure and Objectives; enemy-roster.md):

| Combat | Enemies | Level (Normal) | Objectives |
|--------|---------|----------------|------------|
| Standard, step 1 (floors 1–5) | 3 | 1 | Rout, or Defeat the Leader for very short fights |
| Standard, step 2 (floors 6–11) | 4 | 3 | Same |
| Standard, step 3 (floors 12–17) | 5 | 5 | Same |
| Key combat | Its step's standard count +1 to +3, plus the mini-boss | Step +1; mini-boss +2 | Defeat the mini-boss, Seize, Survive or Defend |
| Boss (floor 18) | Fully scripted, fixed placement | Baron 8 | Defeat the Powder Baron |

- Enemy count never scales with the player's army size.
- Leaders and mini-bosses are elites: a class plus a prefix and a signature move. Leaders and
  mini-bosses are +2 levels over their step's enemies.
- The Hunted curse adds one standard-class enemy per copy, in a free enemy slot (P05 question 40).
  MP10 maps leave at least 2 slots free beyond their largest pack.

**What the code does today** (P05 EN6, EN10; `scripts/enemies/enemy_setup.gd`):

- Setup step 4 draws **one pack per map**, evenly from every pack in `data/enemies/packs/`, with the
  shared `ENCOUNTER_SETUP` stream. A pack with a varying count (the Hunting Party's 2–3 Hounds) then
  draws that count.
- Each reinforcement wave draws one whole pack the same way (step 5).
- Hunted draws a class evenly from the classes that appear in packs (step 6).
- The leader slot is never filled yet (EN7).

**The packs** (enemy-roster.md; data in `data/enemies/packs/`):

| Pack | Units | Size |
|------|-------|------|
| Shield and Bolt | Shieldbearer, 2 Crossbowmen | 3 |
| Hex and Knife | Hexer, 2 Cutthroats | 3 |
| Field Hospital | Hedge Healer, Brute, Shieldbearer | 3 |
| War Band | Warcaller, Brute, 2 Hounds | 4 |
| Hunting Party | Raider, 2–3 Hounds | 3–4 |
| M1 Pack (from M1) | Brute, Crossbowman, Hedge Healer | 3 |

How often each class appears across the five design packs: Shieldbearer 2, Brute 2, Hound 2,
Crossbowman 1, Cutthroat 1, Hexer 1, Hedge Healer 1, Warcaller 1, Raider 1, **Duelist 0**.

## Gaps

1. **Step 2 and step 3 can't be filled.** Every pack is 3 or 4 units, and a map draws one pack, so
   no standard combat reaches step 3's 5, and step 2's 4 comes only from the War Band or a
   three-Hound Hunting Party.
2. **Key combats have no rule** for their +1 to +3 enemies or for which pack fights beside each
   mini-boss.
3. **The Duelist never appears.** It isn't in any pack, so neither setup nor Hunted fields it.
4. **The M1 Pack is still drawn** as a sixth pack in every standard combat.
5. **Defeat the Leader** needs a leader with its pack: which class, and whether the leader counts
   toward the step's enemy count.
6. **Reinforcement waves** send a whole pack each. A Survive map with several waves may field far
   more enemies than its step suggests.
7. **No pack weighting:** every pack is equally likely at every step and on every objective.

## Still to write

**The pack lists.** Every decision below is a rule; none names units. Before P05 EN17 can build,
each pack needs its basic and hard variant at each step (3, 4 and 5 units), the Duelist's hard and
key packs, and each mini-boss's key packs. A starting point for the key packs: each mini-boss's
are built around its own class's pack (Brigand Captain, a Brute, with the War Band or Field
Hospital; Bloodhound with the Hunting Party; Hex Matron with Hex and Knife; Iron Wall with Shield
and Bolt).

## Open questions

None. The pack lists above are content to write, not a rule to decide.

## Decisions

Decided by the user, November 15, 2026. The vision and enemy-roster.md are updated through the
ideation thread.

1. **Packs have a normal and a hard variant (gap 1).** Unit types and combinations drive the
   difficulty and vary play. A hard variant adds the extra unit that fills the step's count.
2. **Key combats draw from their own key-combat packs (gap 2).** These are more interesting than a
   standard pack plus extra units: harder combinations, or fewer but more powerful units. This
   changes the vision's "+1 to +3" rule.
3. **Basic and hard pools, Slay the Spire style (gaps 3 and 7).** After enough combats in a stretch
   of the run, combats draw from a harder pool of more unique and challenging packs. The Duelist
   stops being absent: classes like it can join the basic or hard packs.
4. **Waves and objective-specific packs are settled in playtesting (gap 6).** The user's guess is
   that Defend maps field packs with more units, each weaker.
5. **Basic and hard mean later in a step, not bigger.** Every variant is sized to its step's count
   (3, 4, 5), so the vision's counts stand. In each step, the first **2** standard combats draw the
   basic pool and later ones the hard pool. The 2 is a first value to tune in playtesting (Slay the
   Spire uses 3 in its first act and 2 after).
6. **Key packs replace the "+1 to +3, plus the mini-boss" rule.** A key pack may field fewer
   enemies than a standard one, when they are stronger. The vision update goes through the
   ideation thread.
7. **The Duelist goes in hard and key packs only,** not hand-placed, so maps need no Duelist slots.
8. **The M1 Pack is retired from the draw.** It stays for tests and the M1 map.
9. **A leader is an elite of one of its pack's classes,** placed in the map's leader slot, and
   counts toward the step's enemy count.
