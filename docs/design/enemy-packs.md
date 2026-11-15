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

## Proposals

First-pass directions for the ideation thread to accept, change or reject. None is a decision.

- **Sizes by step (gap 1):** each pack lists a core of 3 and the units it adds at step 2 (+1) and
  step 3 (+2), so a pack keeps its puzzle as it grows. For example, Shield and Bolt adds a third
  Crossbowman at step 2 and a Cutthroat at step 3. The data already supports a varying count per
  class; a per-step count would be a small P05 change. The alternative, two small packs per map at
  step 3, mixes puzzles and makes intents harder to read.
- **Mini-boss packs (gap 2):** each mini-boss leads the pack built on its own class, which already
  pairs one to one:

  | Mini-boss | Built on | Leads |
  |-----------|----------|-------|
  | Brigand Captain | Brute | War Band or Field Hospital |
  | Bloodhound | Hound | Hunting Party |
  | Hex Matron | Hexer | Hex and Knife |
  | Iron Wall | Shieldbearer | Shield and Bolt |

  The +1 to +3 enemies come from that pack's step sizes plus one, two or three of its own classes.
- **The Duelist (gap 3), the user's lean:** a hand-placed guard on key and boss maps, not a pack
  unit. Its Guard behaviour (it holds its ground and gains Block when attacked) suits a fixed post
  such as a Seize tile, a Defend approach or the Baron's throne room. MP10's key maps and P05
  EN11's boss map would place it by hand in authored slots, and Hunted would keep drawing only pack
  classes.
- **The M1 Pack (gap 4):** remove it from the draw and keep it only for tests and the M1 map.
- **Leaders (gap 5):** the leader is an elite of one of its pack's classes, placed in the map's
  leader slot, and counts toward the step's enemy count.
- **Waves (gap 6):** a wave sends a pack's core of 3 at most, or a map authors its wave sizes.
- **Weighting (gap 7):** equal odds for now; tune in playtesting.

## Open questions

1. Per-step pack sizes, or two packs per map at step 3?
2. Which pack each mini-boss leads, and where the +1 to +3 come from?
3. The Duelist: hand-placed on key and boss maps only, or also in a pack?
4. Is the M1 Pack retired from the draw?
5. Does a leader count toward the step's enemy count, and which class can lead?
6. How big is a reinforcement wave?
7. Should any pack be limited to certain steps or objectives?

## Decisions

None yet.
