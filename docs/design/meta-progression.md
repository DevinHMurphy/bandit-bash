# Meta Progression

Everything that carries from one run to the next in Bandit Bash: the home base, unlocks, the
difficulty ladder, the almanac, statistics and the Hall of Heroes. It expands
[game-vision.md](game-vision.md), which wins where the two differ.

**Status:** designed October 24, 2026; not built. Every number is a first pass to tune in
playtesting.

## The short version

- **Sideways, not stronger.** Unlocks add variety (commanders, unit types, heirlooms, weapons,
  events), never permanent power. A new player and a veteran start a run equally strong. Challenge
  grows through a 10-level **difficulty ladder** above Normal, which replaces the Hard mode.
- **Every run counts.** Each run, won or lost, earns account XP that fills a fixed unlock track;
  some content unlocks from milestones instead.
- **The Waystation** is the home base: one illustrated hub screen with stations, a crossroads inn
  where commanders gather between campaigns.
- **Timing:** the MVP ships statistics recording (so data exists from the first build) and the
  Waystation as a static hub with only its war table. Everything else (unlocks, the ladder, the
  almanac, the Hall of Heroes, run history, achievements, the other stations) follows once one full
  run works.

## Pillars

| Pillar | How meta progression serves it |
|--------|--------------------------------|
| Reduce cognitive burden | One hub screen, no second economy; unlocks arrive one at a time on a visible track |
| Decrease run length | Losing still earns progress, so a short failed run is never wasted, and restarting is easy (`Godot_FE`'s 4–8 hour runs made players quit after a loss) |
| Incentivize proactive players | The run score pays for every turn-par and no-losses grade, so fast, clean play unlocks faster; the ladder's top rungs tighten turn par |
| Remove "hurry up and wait" | Unlock screens are short and skippable; co-op players progress together |

## The Waystation

A crossroads inn where every faction's commanders gather between campaigns: neutral ground for
future factions. It is **one illustrated hub screen** with clickable stations, like Darkest
Dungeon's Hamlet, not a walkable space.

| Station | What it does |
|---------|--------------|
| War table | Start a run: faction, commander, difficulty and ladder level |
| Library | The almanac: everything discovered |
| Trophy hall | Hall of Heroes, run history (the archive) and statistics |
| Training yard | Replayable tutorials first (Block, Stance, the triangle, the darkness); later a sandbox fight with any unlocked units and gear against chosen enemies, with nothing saved. Tutorial content is a separate design |

- **MVP:** the Waystation is a static hub with only the **war table**: it is where a run starts.
  The other stations appear when their systems ship.
- **Later:** it grows visibly with unlocks (a banner for each new commander, racks for new weapons),
  with no building system or currency.

## Unlocks

Locked content never appears anywhere in a run: not in recruit offers, shops, rewards, chests,
Treasure, events or the starting-heirloom offer. Curses are never locked.

### The starter core

A new profile starts with part of the MVP content, so a new player has fewer things to learn at
once (cognitive-burden pillar). The rest unlocks over the first runs, then post-MVP content.

| Kind | Open from the start | Locked |
|------|---------------------|--------|
| Commanders | Drengr | The 4 post-MVP Mercenary commanders ([milestones](#commander-milestones)) |
| Unit types | Sellsword, Fighter, Lancer, Archer, Battle Medic, Hakkapel, Thief, Mage (the plainest identities) | Brawler, Freewing, Lance Armor, Ward, Shaman, Suncaster |
| Heirlooms | Every Common and Uncommon; Rares **Ancestral Mail**, **Champion's Belt** and **Commander's Standard** | The other Rares (Muster Roll, Warhorse Lineage, Bloodhound's Collar, Gilded Purse) and the 4 Shop-tier heirlooms |
| Weapons and items | Every Basic, Common and Uncommon; Rare weapons **Spear**, **Twin Fang** and **Steppe Hornbow**; the Legendary **Eye Greatshield** (equipment any unit can use) | The other Rare weapons, Rare equipment and trinkets, and the other Legendaries |
| Events | The 8 reworked from `Godot_FE` | The 5 new ones: Broken Shrine of Valor (the revive shrine), Bandit Toll, Cursed Hoard, Mercenary Camp, Black Altar |
| Starting heirlooms | All 7 | — |
| Runes | All 7 | — |

The starter Rares and the Legendary are chosen to be easy to read, so a new player sees what a
Rare and a Legendary feel like. Legendaries stay near-impossible to find even once unlocked.

Consequences worth knowing: until the Mercenary Camp event and Muster Roll unlock, max army size
grows only through Abundance; until the revive shrine unlocks, nothing brings a fallen unit back.

### The unlock track

- **Earned by every run.** At the end of a run, won or lost, the player earns **account XP**
  from a run score: progress (floors climbed, combats won, key combats, the boss), plus a bonus for
  every turn-par and no-losses grade earned, multiplied by the difficulty-ladder level. Speed and
  clean play progress faster (proactive pillar); a lost run still earns its progress.
- **One unlock per step** on a fixed track, the same order for every profile. A unit type, an
  heirloom, a weapon or an event each takes one step.
- **Steps get more expensive**, linearly: the first step costs 45 XP and each step after costs 1
  more. (A compounding rise was considered and rejected: at +10% a step, the last of about 50
  steps would cost thousands of XP.)
- **Length:** about 15–20 runs to finish the track (roughly 15–25 hours at 60–80 minutes a run),
  about where Slay the Spire's unlocks end: about 4 unlocks a run early, 2 near the end.
  Post-MVP content extends it.

**Run score (first pass, to tune):**

| Earned | Account XP |
|--------|------------|
| Each floor climbed | 5 |
| Each standard combat won | 10 |
| Each key combat won | 25 |
| The boss defeated | 60 |
| Each grade bonus earned (turn par or no losses) | 5 |
| Total | × (1 + 0.25 × difficulty-ladder level) |

A typical win scores about 355; a typical loss around floor 10 about 145. With early runs
averaging about 200, the MVP track (about 50 steps, about 3,500 XP) takes 15–20 runs.

**End-of-run screen:** one skippable screen shows the score line by line, the account-XP bar
filling, then one card per unlock, plus any commander milestone or ladder level opened. In co-op,
each player sees their own.

### Commander milestones

Commanders unlock from milestones, not the track. Each is a real achievement and points at the
next thing to master. The first post-MVP wave is the four `Godot_FE` Mercenary commanders
(Destroyer, Iron Viper, Line Breaker, War Maiden); which commander goes with which milestone is
decided when they are designed. The Kingdom commanders (Centurion, Weapon Master, Mage Knight) wait
for their faction; the Night Blade waits too.

| Commander | Milestone |
|-----------|-----------|
| 1st | The Drengr: open from the start |
| 2nd | Reach the boss |
| 3rd | Win a run |
| 4th | Win at difficulty-ladder level 3 |
| 5th | Win at difficulty-ladder level 6 |

Winning at ladder level 10 earns a Waystation trophy (no content).

## Difficulty ladder

Every run is a **Normal** run; there is no separate Hard mode. Challenge above Normal comes from a
ladder of **10 levels**, in the spirit of Slay the Spire's Ascension and Balatro's Stakes. The
former Hard rules (prefixed enemies, +1 enemy level, turn par −1) are levels 1, 4 and 6.

- **Cumulative:** each level adds one rule on top of every level below it.
- **Per commander:** winning at level N with a commander opens level N + 1 for that commander.
  Level 1 opens after a Normal win with it.
- **Chosen at the war table**, with the commander. In co-op the host chooses, from levels open to
  the host's commander ([Co-op](#co-op)).
- **Score:** the run score is multiplied by (1 + 0.25 × level); Normal is level 0.
- **Timing:** the ladder ships with the rest of meta progression, after the MVP; the MVP is Normal
  only.

| Level | Name | New rule |
|-------|------|----------|
| 1 | Prefixed foes | Every enemy rolls a [prefix](unit-roster.md#prefixes) (Normal: only elites and the boss) |
| 2 | Elite pack | Every standard combat fields one elite (a prefix and a signature move) |
| 3 | Lean purses | Combat gold −20% |
| 4 | Seasoned foes | Every enemy is +1 level |
| 5 | Thin rations | Feast heals 25% instead of 35% |
| 6 | Short fuse | Every map's turn par is 1 lower: the darkness arrives a turn earlier and the speed bonus needs one turn less |
| 7 | Swarm | Standard combats field one more enemy |
| 8 | Warlords | Mini-bosses and the boss are +2 levels |
| 9 | Fewer fires | Every path has one Camp fewer (at least 1) |
| 10 | Marked | Every run starts with a random minor curse, named at the war table |

All values are first pass, to tune. Considered and dropped: shop prices +20% (Lean purses already
hits the economy) and a second turn-par cut.

## Almanac

The Waystation's **Library**: a reference to everything in the game, and a quiet "see them all"
goal.

**Categories:** commanders and unit types (traits, upgrades, stats); enemies (classes, elites,
mini-bosses, the boss, with traits, AI behavior and signature moves); weapons, equipment,
trinkets, consumables, ingredients and runes; heirlooms (by tier), starting heirlooms, events (with
their options) and curses.

**Entry states:**

| State | Shown as | Means |
|-------|----------|-------|
| Locked | A locked card that says how to unlock it | Still on the unlock track, or behind a commander milestone |
| Unseen | A silhouette | Unlocked, but never met in a run |
| Discovered | The full entry | Met at least once in a run: shown as an offer, obtained, fought or encountered |

**An entry shows** the game's generated effect text and numbers (the same text the game uses, so it
can't drift), plus the player's own numbers for it from [statistics](#statistics-and-hall-of-heroes):
times picked, runs won with it, enemies defeated. Lore text comes later.

**Rewards:** discovery never gives account XP or power; account XP stays about how runs are played.
Discovering every entry in a category earns a Waystation trophy.

## Statistics and Hall of Heroes

The Waystation's **Trophy hall**. Statistics **recording ships with the MVP**, so every run from the
first build counts; the screens that show them come after the MVP.

### Statistics

| Scope | Recorded |
|-------|----------|
| Account totals | Runs started, won and lost; floors climbed; combats won; play time; enemies defeated; units lost; gold earned; fastest win; best win streak |
| Per commander | Runs, wins, highest ladder level won, fastest win |
| Per entry | For every unit type, weapon, item, heirloom, rune, enemy and event: times offered, picked or met, runs won with it, enemies it defeated, times it was defeated (where each applies) |
| Per run | The archive record every ended run already writes: commander, ladder level, outcome, floor reached, roster, heirlooms, score, cause of loss |

- **Almanac discovery comes from these counters:** an entry is Discovered as soon as any of its
  per-entry counters is above 0, so there is no separate "seen" list to keep in sync.
- Counters are keyed by each entry's stable string id (see
  [Lessons from Godot_FE](#lessons-from-godot_fe)).

### Hall of Heroes

Every won run adds a **plaque**: commander, ladder level, date, and a snapshot of each surviving
unit (name, type, prefix, level, gear), plus the fallen. Plaques are plain data, never live units.

### Run history

A list of past runs, won and lost, read from the archive records the game already writes. Each
opens a summary: route, roster, heirlooms, score and cause of loss. This is the archive viewer the
save-system plan lists as later work.

### Achievements

Steam achievements that mirror the meta goals: commander milestones, ladder wins, almanac category
completions and a handful of feats (e.g. win with no unit lost). Stored in the profile's
`achievements` section and pushed to Steam. The exact list is designed after the MVP.

## Co-op

- **Whose unlocks:** things only one player gets (their item picks, Treasure and key-combat
  heirlooms, starting heirlooms, recruits they're offered) use that player's own unlocks. Shared
  things (shop stock, events, the Unknown pool) use the **host's**. A new player can join a
  veteran's campaign and see more than their own profile has.
- **Unlocks don't change mid-campaign:** they're only granted at run end, so each player's unlock
  set is sent to the host once when they join (or resume) and stays fixed for the campaign.
- **Progress:** each player earns account XP from **their own** score (floors, the combats they
  won on their own map, their own grades) × the ladder multiplier. Run-level milestones (reach the
  boss, win, ladder wins) count for every player, with their own commander. Each player's
  statistics record their own play.
- **Ladder and commanders:** the host chooses the ladder level from those open to the host's
  commander. Every player picks any commander they've unlocked; duplicates are allowed (the MVP has
  only the Drengr). A ladder win opens the next level for each player's own commander.

## Save impact

Per [save-system.md](save-system.md). Section keys are already reserved; versions are chosen when
each system is built.

| Block | Key | Holds | Per player | When |
|-------|-----|-------|------------|------|
| Profile | `statistics` | Account totals, per-commander and per-entry counters | Each player's own `profile.json` | MVP |
| Profile | `unlocks` | Account XP, unlocked ids by category, commander milestones reached, ladder levels open per commander | Own profile | After the MVP |
| Profile | `hall_of_heroes` | Plaques (plain-data snapshots) | Own profile | After the MVP |
| Profile | `achievements` | Achieved ids and when | Own profile | After the MVP |
| Campaign | core field | The run's ladder level | Once per campaign | With the ladder |
| Archive record | core fields | Run score and ladder level, added to the existing record | Every player's archive | MVP (score), ladder later |

- **Save-format change (🔴):** adding score and ladder level to the archive record changes
  `ArchiveRecord`'s core shape, so it needs a schema version bump and a migration step.
- **When stats are written:** counters from a battle live in the `COMBAT` block and are added to the
  profile at `end_battle()`; a battle restarted from Begin therefore never double-counts. Campaign
  events (floors, shops, events) are added at the checkpoint where they happen. The profile is
  already written at every checkpoint.
- **Co-op:** the host computes each player's counter changes and sends them with the checkpoint
  broadcast; each client adds them to its own `profile.json`, as play time already works.
- **Stable ids:** every unlock, counter and plaque refers to content by its string id, and the
  unlock ledger is reconciled with the game's content on every load (new ids get their default,
  removed ids are dropped).
- **The debug unlock-all toggle never writes to the profile.**

## Open questions

None block building statistics recording or the war table. Decided when their systems are built:

- **The track's order:** the exact sequence of the ~50 unlocks.
- **Commanders:** stats, traits and Commander Heirlooms for the four Mercenary commanders, and
  which milestone unlocks which.
- **Achievements:** the exact list.
- **Tutorials:** their content (a separate design).
- **Lore:** almanac flavour text.
- **Values:** every score value, step cost and ladder rule is first pass.

## Developer tools

- **Unlock-all toggle:** debug builds only. A debug-panel switch that treats everything as
  unlocked without changing the saved profile, so testing never corrupts real progress.
- **Dev console (future, out of this design's scope):** commands such as give item, give XP and
  toggle triggers, scoped separately when it's needed.

## Lessons from Godot_FE

From `Godot_FE/docs/systems/11_drafting_unlocks_meta.md` and `02_save_and_persistence.md`:

- Its unlock ledger was keyed by Resource objects, which broke across reloads and content patches.
  Key everything by stable string id.
- It never reconciled the ledger with new content on load, so content added later was missing.
  Reconcile on every load: add new ids with their default, drop removed ones.
- Its Hall of Heroes stored live units. Store snapshots (plain data) instead.
