# Enemy Packs

A planning doc for the enemy groups a run fields: which packs exist, what size they are at each
difficulty step, which pack goes with each mini-boss, and where the Duelist appears. It works out
what [enemy-roster.md](enemy-roster.md) and [game-vision.md](game-vision.md#run-structure) leave
open. Nothing here is decided until it is in [Decisions](#decisions), and the vision and
enemy-roster.md are updated through the ideation thread.

**Status:** draft, opened November 15, 2026 (user). Feeds P05 (packs, EN7's leaders and
mini-bosses) and P04 MP10 (the M2 map set).

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

## Proposals still open

First-pass directions for the gaps the decisions below don't settle yet. None is a decision.

- **The M1 Pack (gap 4):** remove it from the draw and keep it only for tests and the M1 map.
- **Leaders (gap 5):** the leader is an elite of one of its pack's classes, placed in the map's
  leader slot, and counts toward the step's enemy count.
- **Mini-boss pairings (gap 2):** each mini-boss's key packs are built around its own class's
  pack: Brigand Captain (Brute) with the War Band or Field Hospital, Bloodhound with the Hunting
  Party, Hex Matron with Hex and Knife, Iron Wall with Shield and Bolt.

## Open questions

1. **How do normal and hard relate to the steps?** Either (a) hard means bigger: normal variants
   are the core 3 and hard variants add units for step 2's 4 and step 3's 5; or (b) hard means
   later in a step, Slay the Spire style: each step's first combats draw the basic pool and later
   ones the hard pool, each sized to the step's count. Recommended: (b), with every variant sized
   to its step's count, because it keeps the vision's 3/4/5 counts and gives each step its own
   escalation. Under (b), how many standard combats per step draw the basic pool before the hard
   pool opens? (Slay the Spire uses 3 in its first act and 2 after; no Bandit Bash basis yet.)
2. **Key combats:** do key packs replace the vision's "step count +1 to +3, plus the mini-boss"
   rule outright, so a key pack may field fewer enemies than a standard one? Recommended: yes; the
   vision update goes through the ideation thread.
3. **The Duelist:** in hard and key packs instead of the earlier hand-placed lean, or both?
   Recommended: packs only, so MP10 needs no hand-placed slots.
4. Is the M1 Pack retired from the draw? Recommended: yes (proposal above).
5. Does a leader count toward the step's enemy count, and which class can lead? Recommended: the
   proposal above.

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
