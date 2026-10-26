# Plan: RNG Streams
**Date:** October 26, 2026
**Status:** **Approved** October 26, 2026 (review fixes: `TEAM_CHOICE`, per-seat encounter additions, 16-bit-limb mixer, integer weights, starting-heirloom draws); R1–R3 built October 26, 2026 (126 headless tests pass). Orchestrator ID
**P13** ([game-orchestrator.md](game-orchestrator.md)). Answers question 2 of the
[campaign and run flow stub](2026-10-24-campaign-run-flow.md).

Every random result in Bandit Bash, from the campaign map to a hit roll, comes from a seeded,
named stream derived from the run seed, so a run is reproducible on the host, a save and resume
can't reroll anything, and one system's draws can never shift another's. This plan builds that
foundation and the rules every gameplay plan follows when it rolls.

## Problem

- **No RNG manager exists.** The save system reserves `rng` sections in the campaign and combat
  files and notes that a resumed enemy phase replays identically "only once the RNG manager saves
  its state" (save-system.md, Battles). P01 expects a seeded stream injected into every
  `CombatSession` (EB4's `LiveRolls`, EB6's sessions). No plan owned it (orchestrator).
- **The run seed is a placeholder:** `save_service.gd:343` and `:397` set `CampaignData.run_seed`
  from a bare `randi()`, marked `# ASSUMPTION` until run setup chooses one.
- **`Godot_FE`'s failure to avoid:** about 21 files drew from the one global RNG, so any unrelated
  draw (a sound's pitch, a UI roll) shifted every later outcome; its seed was re-seeded on Continue
  and lost whenever a sound played (game-vision.md, Campaign map; `10_campaign_and_run_loop.md`
  §6). Its draft rolled inside UI `_ready` handlers, so redrawing a screen changed results
  (`11_drafting_unlocks_meta.md` §6).
- **Its template's trap:** `Godot_FE/docs/systems/assets/templates/seeded_streams.gd` derives
  streams with Godot's `hash()`, which isn't guaranteed stable across engine versions, so an engine
  upgrade could silently change every stream.

## Open Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | Who owns the streams | Plain object owned by the run / a new `Rng` autoload | Plain object | **Answered October 26, 2026:** a plain `RngStreams` object held by `CampaignSession` and handed down; its save sections are registered by whichever autoload owns `CampaignSession` (P08 question 1). No new autoload. |
| 2 | How values are derived | Keyed per node, running within / running named streams / one stream | Keyed per node | **Answered:** every node and combat gets streams seeded from a **key** (run seed, purpose, floor, node, seat, index), not from earlier draws; inside one node a stream runs normally. |
| 3 | Co-op layout | Shared world, personal rewards / everything per player | Shared world | **Answered:** the world is shared; every reward and every random outcome for a player rolls per seat (see [Co-op layout](#co-op-layout)). In a shared event, each player's random reward is their own. |
| 3b | Chest and house loot on parallel map copies | Per player / shared | Per player | **Answered:** per player. Same chest, same tile, different contents per seat. |
| 4 | Run seed | Random, shown, debug entry / random hidden / player-entered | Random, shown, debug entry | **Answered:** random at run start; shown on the pause and results screens and in repro dumps; typing a seed is a debug option in the MVP. |
| 5 | Generator and derivation | Godot RNG + own key hash / own generator too | Godot RNG + own hash | **Answered:** Godot's `RandomNumberGenerator` (PCG32) per stream; keyed seeds from our own SplitMix64 mixer, never `hash()`; golden tests pin both. |
| 6 | Determinism across game updates | Same build only / pinned across updates | Same build only | **Answered:** guaranteed within one build. After an update that changes content, future rolls in a resumed run may differ; past results are never rerolled. |

No open questions remain.

## Scope

**In scope**

- The run seed: generation, its 52-bit range, display format, debug entry.
- `RngKey`: the purpose catalog and the SplitMix64 derivation of a stream seed from a key.
- `RngStream`: a wrapper over one `RandomNumberGenerator` with the draw helpers every plan uses
  (ranges, percent checks, weighted picks, shuffles) and state capture and restore.
- `RngStreams`: one run's registry of live streams, created lazily by key and dropped when their
  node or battle ends.
- The co-op layout: which keys are shared and which carry a seat.
- Save and resume: the campaign and combat `rng` sections.
- Injection contracts for P01 (sessions, `LiveRolls`, the sandbox) and the rules every plan
  follows when it rolls, including cosmetic randomness.
- Debug support: seed in repro dumps, stream creation logging.

**Out of scope**

- The draws themselves: each plan rolls its own results through these streams (P02 combat rolls,
  P04 spawns and loot, P05 AI, P06 darkness sources, P08 map, nodes, rewards, shops and level-ups,
  P09 events).
- P01's `SampledRolls` for AI sampling stays seeded from the session `seq` and the candidate, never
  from a stream; it reuses this plan's mixer.
- Rising Unknown-node odds: that's campaign state (P08), not randomness.
- A player-facing "seeded run" mode (post-MVP).

## Design Basis

- save-system.md: reserved `rng` sections, checkpoints, `BATTLE` and `BATTLE_RETRY` resume, the JSON
  rule that integers above 2^53 are strings.
- game-vision.md: Campaign map ("seeded and saved… its own RNG stream"), Unknown rolls ("from the
  run's seeded stream"), Combat maps (enemies, spawns and loot "from the run's seeded stream"),
  Multiplayer maps (parallel copies: same map, same seed), Co-op ownership.
- the-darkness.md (active sources from the run's seeded stream, identical on every copy),
  map-objects.md (objects placed from candidates by the seed), events.md (curses drawn from the
  seeded stream), unit-roster.md (Guildhall offers rolled from the seed).
- P01: roll sources (`LiveRolls`, `ForecastRolls`, `ForcedRolls`, `SampledRolls`), sessions, the
  host as the only resolver, determinism and repro dumps.
- Not covered by gameplay design otherwise; nothing needed is under "Still open".

## Legacy Behavior

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| ~21 files (`10` §6) | `randf()`, `randi()`, `pick_random()` on the global RNG | Drop | Every gameplay draw goes through a stream |
| `10` §6 | Global seed re-seeded on Continue; lost when a sound played | Drop | Stream state is saved; cosmetic randomness is separate |
| `11` §6 | Draft randomness inside UI `_ready` / focus handlers | Drop | Rules generate offers once; UI never rolls |
| `templates/seeded_streams.gd` | Named streams from one run seed, created lazily; snapshot and restore | Keep (shape) | Same idea, keyed per node |
| `templates/seeded_streams.gd` | `hash("%d:%s")` derivation | Change | Godot's `hash()` isn't guaranteed stable; SplitMix64 instead |
| `CustomUtilityLibrary.random_rolls_bool` | 2RN as the integer average of two d100 | Keep (semantics) | Rolled by P01's roll sources over a stream |

No tuning values are carried over.

## Approach

### Keys and derivation

A **key** names one stream: `(purpose, floor, node, seat, index)`.

- `purpose` is an `RngPurpose` enum value: **append-only with explicit values**, never strings, so
  renaming a purpose can't change any seed.
- `floor` and `node` locate the campaign node (`-1` for run-level streams); `seat` is `-1` for
  shared streams; `index` separates several streams of one purpose in one node (e.g. an authored
  chest's index on the map), `-1` when unused.
- **Seed = SplitMix64 chained over the run seed and the five parts.** GDScript's `int` is signed
  64-bit, and even two 32-bit halves multiplied together overflow it, so the mixer never relies on
  overflow: multiplication is done in **16-bit limbs** (every partial product stays below 2^32),
  additions are masked to 64 bits, and right shifts are **masked logical shifts** (GDScript's `>>`
  is arithmetic on negative values). Reference SplitMix64 vectors pin its output.
- **Chaining** (as built): the state starts at 0 and folds in each value as
  `splitmix64(state ^ value)`, so a single value gives standard SplitMix64 output.
- **Save key** (as built): the five parts as numbers joined by `:`, purpose first (e.g. `9:2:5:0:-1`),
  read back by `RngKey.from_save_key()`. Numbers, not names, so renaming a purpose changes no save.
- A stream's sequence depends only on its key, so a new purpose, a new node type or an extra draw in
  one system never changes another stream.

### Purpose catalog (MVP)

Shared streams have no seat; personal streams carry the player's seat.

| Purpose | Key | Shared or per seat | Used for (owner) |
|---------|-----|--------------------|------------------|
| `MAP_GENERATION` | run | Shared | The campaign map graph (P08) |
| `ROUTE_DRAW` | floor | Shared | Drawing the next node from route votes (P08) |
| `UNKNOWN_RESOLUTION` | node | Shared | What a `?` becomes (P08) |
| `EVENT_DRAW` | node | Shared | Which event appears (P09) |
| `TEAM_CHOICE` | node | Shared | The vote-weighted draw that decides a team-choice event's option, after every player has voted (P09) |
| `EVENT_OUTCOME` | node, seat | Per seat | Random rewards and named curses of an event option, per player, including team events' rewards (P09) |
| `STARTING_OFFER` | run, seat | Per seat | The 1-of-3 starting heirlooms, then the chosen one's own draws: Family Relic's heirloom, Ancestral Weapon's three weapons, Abundance's and Mercenary Contract's recruit offers (P08) |
| `SHOP_STOCK` | node | Shared | Armory stock and Guildhall recruits and runes, with recruits' prefixes (P08) |
| `PREFIX_REROLL` | node, seat | Per seat | Guildhall prefix re-rolls (P08) |
| `REWARD` | node, seat | Per seat | The combat item pick, the key-combat heirloom, Treasure (chest size, heirloom, gold, Legendary find) (P08) |
| `LEVEL_UPS` | node, seat | Per seat | Level-up growth rolls and random guaranteed gains, in roster order (P08) |
| `ENCOUNTER_SETUP` | node | Shared | Map choice from the pool, enemy groups, spawns, enemy prefixes, object placement, active darkness sources, and **every reinforcement wave's group**: all drawn once at battle start (see [Shared streams are drawn once](#shared-streams-are-drawn-once)), identical on every parallel copy (P04, P05, P06) |
| `ENCOUNTER_SETUP` | node, seat | Per seat | **Per-player additions** to that player's copy, drawn at battle start right after the shared setup: e.g. the Hunted curse's extra enemy (P04, P05) |
| `MAP_LOOT` | node, seat, index | Per seat | The contents of the authored chest, house or shelf `index` on that seat's map copy; `index` is a stable per-map container index authored by P04 (P04) |
| `COMBAT_ROLLS` | node, seat | Per seat (one per session) | Hit, crit and Chance rolls and random target selectors during the battle (P02 through P01's `LiveRolls`) |

- **Combat calculations are isolated.** Each battle gives each player a fresh `COMBAT_ROLLS`
  stream used for nothing but that battle's hit, crit and Chance rolls and random targets. Map
  population (`ENCOUNTER_SETUP`), container loot (`MAP_LOOT`), post-combat rewards (`REWARD`) and
  level-ups (`LEVEL_UPS`) never draw from it, so no combat roll can change what is found or
  earned, and nothing carries over from one battle to the next. (Confirmed October 26, 2026;
  finer splits per roll kind or per unit owner on a shared map were considered and not needed.)
- A purpose a plan needs later is appended here and in the enum, with its owner.
- Key-combat and boss maps follow the same keys; a scripted boss map simply draws nothing from
  `ENCOUNTER_SETUP` beyond what its script allows.
- A shared event that leads to a surprise combat uses that node's `ENCOUNTER_SETUP` like any combat.

### Co-op layout

Decided October 26, 2026 (question 3): **the world is shared; anything that's a reward or a random
outcome for a player is per seat.** Two players at the same event see the same scene and options;
if both choose "gain a rare heirloom", each rolls their own. Parallel combat copies have identical
maps, spawns and objects, but each player's chest holds their own loot, and each map's rolls are its
own. Only the host ever rolls (P01), so peers never need matching streams.

### Shared streams are drawn once

A shared stream must give every player the same result, but each parallel map copy is a separate
session on the host, and copies reach the same moment at different times. If two copies drew from
one shared running stream during a battle, each draw would shift the other copy's next draw and the
"identical" copies would diverge. So:

- **A shared stream is drawn at one moment, by one owner,** before anything that differs per player
  can interleave: `ENCOUNTER_SETUP` by the `CombatEncounter` at battle start, `SHOP_STOCK` on
  entering the shop, `EVENT_DRAW` and `UNKNOWN_RESOLUTION` on entering the node, `TEAM_CHOICE`
  once every vote is in, `MAP_GENERATION` at run start, `ROUTE_DRAW` once per floor.
- **Per-player differences use a seat key, never the shared one.** A curse or effect that changes
  only one player's map (Hunted) draws from that seat's `ENCOUNTER_SETUP` key, so the shared copies
  stay identical.
- **Anything shared that happens later in a battle is pre-drawn at setup.** Every reinforcement
  wave's enemy group is part of the setup result; a session later reads its wave from that result
  and never rolls it.
- **Sessions receive setup results, never the setup stream.**
- A test asserts that every shared purpose is drawn only inside its one owner's setup call (built
  with the owners: P01 EB6 for `ENCOUNTER_SETUP`, P08 for the campaign purposes; see R6).

### Running within a node

Inside one key a stream runs normally: a battle's `COMBAT_ROLLS` stream advances with every roll
for the whole battle; a Guildhall's `PREFIX_REROLL` stream advances with each re-roll in that visit.

- **Savescum-proof:** a stream's state is saved at every checkpoint, so Save & Quit and resume
  continues the same sequence, and the result of an event or a reward screen is fixed by its key
  before the player sees it. A battle restarted from Begin (`BATTLE_RETRY`, when the combat file is
  lost) replays the same rolls without any saved capture: a battle's streams start fresh from their
  keys, so they are simply re-derived.
- **Order inside a node matters, order across nodes doesn't:** opening chests in a different order
  doesn't change their contents (each chest has its own `index`), but attacking in a different
  order changes which roll each attack gets, as in any tactics game.

### Lifetime and ownership

- **`RngStreams`** (one per run) is held by `CampaignSession`. It creates a stream on first use of a
  key, keeps it while its node or battle is active, and drops it when that node ends, so a save
  holds only the live streams.
- **Rules code never sees the registry.** `CampaignSession` hands each consumer the stream it needs:
  the `CombatEncounter` gets the `ENCOUNTER_SETUP` stream, draws the whole setup with it at battle
  start and gives every session the same results; each `CombatSession` gets its seat's
  `COMBAT_ROLLS` stream (wrapped by P01's `LiveRolls`) and that seat's `MAP_LOOT` lookup. This
  satisfies gdscript.md §8.5 (no autoloads, no global RNG in rules).
- **Sandboxes never touch a live stream:** forecasts and AI simulation use P01's `ForecastRolls`,
  `ForcedRolls` and `SampledRolls`. `SampledRolls` seeds itself with this plan's mixer from the
  session `seq` and the candidate, never from a stream.
- **Cosmetic randomness** (animation variance, audio pitch, particle jitter, camera shake) uses a
  separate, unsaved generator per peer in presentation code, never a stream, so it can never shift
  a gameplay result.

### Run seed

- Generated at run start from a non-gameplay source, limited to **52 bits** so it fits a JSON
  number exactly (save-system.md data rules) and `CampaignData.run_seed` keeps its current type and
  format: no save migration.
- **Shown** on the pause and results screens and written into repro dumps, formatted as 13 hex
  digits in groups (e.g. `3F9A-12C0-77E1-A`), so a bug report can name it.
- **Debug entry:** a debug-panel field (and a command-line option for headless tests) starts a run
  from a typed seed. No player-facing seed entry in the MVP.
- Replaces the `randi()` placeholder in `save_service.gd` (both `# ASSUMPTION` sites).

### API sketch

| Class | Public surface |
|-------|----------------|
| `RngKey` | `enum RngPurpose` (values 0–13 in catalog order; `ENCOUNTER_SETUP` is one purpose, shared or per seat by `seat`); the constructor and five fields (`purpose`, `floor_number`, `node`, `seat`, `index`; `floor_number` because `floor` is a Godot built-in); `static func derive_seed(run_seed, purpose, floor_number, node, seat, index) -> int`; `static func mix(values: PackedInt64Array) -> int` (the SplitMix64 chain, also used by `SampledRolls`); `func to_save_key() -> String`; `static func from_save_key(text) -> RngKey` (null if invalid) |
| `RngStream` | `RngStream.new(stream_seed)`; `randi_range(min, max)`, `randf()`, `roll_percent(chance) -> bool` (one roll), `pick_index(count)`, `pick_weighted(weights: PackedInt32Array) -> int` (integer weights and an integer roll, so results are exact on every platform; every weight in the design docs is an integer), `shuffle_indices(count) -> PackedInt32Array`, `capture() -> String` (state), `restore(state: String) -> bool`. `pick_index(1)` and `randi_range(n, n)` use no draw (Godot's behavior; still deterministic) |
| `RngStreams` | `stream(key) -> RngStream`, `drop_node(floor, node)`, `capture_campaign() / restore_campaign() -> bool`, `capture_combat() / restore_combat() -> bool` (all-or-nothing: one bad entry restores nothing, like `SaveSection.restore`; combat holds `COMBAT_ROLLS` and `MAP_LOOT`, campaign everything else, `ENCOUNTER_SETUP` neither), `run_seed` (read-only) |
| `RunSeed` | `generate() -> int`, `format(seed) -> String`, `parse(text) -> int` (debug entry) |

P01's 2RN hit roll is built on `RngStream` by `LiveRolls` (P02 need N8). Weighted picks replace
`Godot_FE`'s three separate rarity-roll copies (`10` §7).

### What P13 needs from other plans

Like P02's needs, these are amended into the plans that own them before their steps are built.
R-N1–R-N4 were amended into P01 on October 26, 2026
([Amendments from P02 and P13](2026-10-23-event-bus-and-effects.md#amendments-from-p02-and-p13));
R-N5 and R-N6 wait on P04 and P08.

| # | Plan | Need |
|---|------|------|
| R-N1 | P01 EB4 | `LiveRolls` wraps an `RngStream` given at construction; its 2RN and one-roll methods (P02 need N8) draw only from it |
| R-N2 | P01 EB4 | `SampledRolls` seeds itself with `RngKey.mix()` over the session `seq` and the candidate, never a stream |
| R-N3 | P01 EB6 | `CombatEncounter` receives the `ENCOUNTER_SETUP` stream and draws the whole setup once at battle start; each `CombatSession` receives its seat's `COMBAT_ROLLS` stream and a `MAP_LOOT` lookup, never the registry |
| R-N4 | P01 EB7 | Snapshots and repro dumps include the run seed, the build version and the live stream states |
| R-N5 | P04 | Every chest, house and shelf has a stable authored index per map (the `MAP_LOOT` key's `index`) |
| R-N6 | P08 | `CampaignSession` holds `RngStreams`; its owner autoload registers the two `rng` save sections (question 1) |

### Logging

- DEBUG (gated by `NetLog.would_log()`): each stream's creation with its key and derived seed.
- A per-draw trace is available behind a separate debug flag for desync and determinism hunts; off
  by default.
- Repro dumps (P01) record the run seed, the build version and every live stream's state.

## Save Impact

- **Campaign `rng` section** (reserved key), version 1: the live campaign streams, as
  `{save_key: state}` with the state as a string (64-bit, above JSON's 2^53). Seeds aren't stored:
  they are re-derived from the key and the run seed. A `SaveSection` (all seats' streams live in
  one registry on the host).
- **Combat `rng` section** (reserved key), version 1: the live battle streams (every seat's
  `COMBAT_ROLLS` and opened `MAP_LOOT` streams), same shape. Written at Begin, at every
  player-phase checkpoint and at battle end. `ENCOUNTER_SETUP` isn't saved: it is fully drawn at
  battle start and its results are battle state (P04's `enemy_units` and `entities` sections).
  `BATTLE_RETRY` needs nothing from this section: the battle's streams are re-derived from their
  keys.
- **`CampaignData.run_seed`** keeps its key and type; new seeds are below 2^52. No migration.
- **Registration:** both sections are registered from the autoload that owns `CampaignSession`
  (P08 question 1), as save-system.md requires; until P08 answers it, they can't be wired.

## Work Breakdown

| Step | Files | Description | Risk | Gate | Verification |
|------|-------|-------------|------|------|--------------|
| R1 Keys and mixer | `scripts/rng/rng_key.gd`, `tests/rng/run_all.gd` | `RngPurpose`, SplitMix64 `mix` (16-bit limbs, masked shifts) and `derive_seed`, save keys | 🟢 | Approval | Reference SplitMix64 vectors, including inputs with the top bit set; adding a purpose leaves existing seeds unchanged |
| R2 Streams | `scripts/rng/rng_stream.gd` | Draw helpers, capture and restore as strings | 🟢 | R1 | Golden first draws of a known seed (pins PCG32); capture → restore continues identically; states above 2^53 survive a JSON round trip; `pick_weighted` distribution test |
| R3 Registry | `scripts/rng/rng_streams.gd` | Lazy creation, drop per node, campaign and combat capture and restore | 🟢 | R2 | Draws on one key never change another; two seats get different `REWARD` streams and the same `ENCOUNTER_SETUP` stream |
| R4 Run seed | `scripts/rng/run_seed.gd`, `scripts/autoload/save_service.gd` (two `ASSUMPTION` sites), debug panel field | 52-bit generation, format and parse, debug entry; replaces `randi()` | 🟡 edits an existing autoload | R1 | New runs get seeds below 2^52; format → parse round trip; a typed seed reproduces a run |
| R5 Save sections | `scripts/rng/rng_save_section.gd` (campaign and combat) | The two `rng` sections | 🟡 save format (filling reserved sections) | P08 question 1 (owner autoload) | Save, quit, resume mid-battle and mid-event reproduces the same results; `BATTLE_RETRY` replays the Begin rolls |
| R6 Injection | P01 EB4 `LiveRolls` and EB6 session wiring (done in P01's steps against this contract) | Sessions receive streams, never the registry. The owner that creates streams logs each creation at DEBUG with its key and seed, and carries the per-draw trace flag (see [Logging](#logging)); the registry stays pure, with no `NetLog` | 🟡 | EB4, EB6 | P01's golden logs run on seeded streams; "every shared purpose is drawn only inside its one owner's setup call" (EB6 for `ENCOUNTER_SETUP`, P08 for the campaign purposes) |
| R7 Docs | `docs/design/save-system.md` (describe the `rng` sections), orchestrator, campaign stub question 2 | Living docs | 🟢 | R5 | Review |

R1–R3 are pure and can start as soon as this plan is approved; they unblock EB4's `LiveRolls` and
P02's golden-log tests.

**Rule added to `.claude/rules/gdscript.md` §8.5** (approved October 26, 2026): "Gameplay
randomness comes only from an `RngStream` handed to the code; cosmetic randomness uses its own
unsaved generator in presentation code and never a stream."

## Breaking Changes

No breaking changes. `save_service.gd` changes only where its run seed comes from; existing saves'
32-bit seeds remain valid 52-bit seeds.

## Verification

- `godot --headless --path bandit-bash --script res://tests/rng/run_all.gd` (new suite) covering the
  tests in each step above.
- `--check-only` on every new or changed script; `--import` after adding the new `class_name`s.
- Determinism: a scripted campaign slice (map generation, an event, a shop, a battle with a fixed
  command list) produces the same results twice, and after a save and resume at each checkpoint.
- Co-op layout: with two seats, shared keys produce identical results and personal keys differ.

## Rollback

R1–R3 add new files only. R4 restores the two `randi()` lines in `save_service.gd`. R5 fills
reserved sections; an older build that doesn't know them keeps them untouched (save-system.md:
unknown section data is preserved), so reverting is safe.
