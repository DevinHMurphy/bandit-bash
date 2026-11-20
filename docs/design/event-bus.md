# Event Bus and Effects

The living reference for how Bandit Bash's rules talk to each other and to the screen: facts, the
two buses, the effect engine, triggers, and the contract every piece of rules code keeps. It
describes the code on `dev`. The design and its history are in the
[event bus plan](../plans/2026-10-23-event-bus-and-effects.md); the trigger vocabulary is in
[effect-triggers.md](effect-triggers.md); the effect model's goals are in
[effects-system.md](effects-system.md). Where this page and the code disagree, the code is right
and this page is out of date.

Code paths are relative to `bandit-bash/`.

## The shape

```
Content       carrier definitions (.tres) with EffectDefinitions inside    read-only, by id
Model         session state + EffectInstances (counters, charges)         plain data, ids
Rules         resolvers → EffectEngine → ordered facts                    pure; host only
Session       CombatSession (one per map) · CampaignSession (one per run)
Presentation  CombatBus / CampaignBus signals during playback             every peer
```

Dependencies point down; information travels up as facts. Rules never wait on a screen.

| Need | Mechanism |
|------|-----------|
| An effect reacts ("Phase Start: gain 3 Block") | The engine's trigger dispatch |
| A number is computed (damage stage, Hit, gold, XP %) | A value query on a stat sheet, with a breakdown |
| A rules system tallies (XP, Standout, grades) | An engine observer, read-only, called at dispatch |
| Something is shown (HP bar, sound, banner) | A bus signal during playback |
| A player acts | A command to the session, validated at resolve time |
| The UI waits on something (an animation, a popup) | A `PresentationRequest`, presentation only |

## Facts

A fact is one thing that happened, in the past tense, carrying ids and never objects or Resources.

- **`CombatFact`** ([scripts/bus/combat_fact.gd](../../bandit-bash/scripts/bus/combat_fact.gd)):
  `kind`, `seq`, `session_id`, `actor_id`, `target_id`, `amount`, `hp_amount`, `block_amount`,
  `damage_type`, `source`, `source_effect_id`, `tile`, `flags`, `side`, `item_id`, `key` and
  `unit_types`. Kinds 0–46: every combat trigger, plus state kinds (moved, spawned, counters,
  timed modifiers, the darkness, objects, reinforcements, weapon swaps, runes, Wait, stat and
  growth changes). Each kind's doc in the enum says what its fields mean.
- **`CampaignFact`** ([scripts/bus/campaign_fact.gd](../../bandit-bash/scripts/bus/campaign_fact.gd)):
  `kind`, `seq`, `seat`, `actor_id`, `target_id`, `definition_id`, `amount`, `source_effect_id`,
  `flags`. Kinds as they stand:

  | Value | Kind | Recorded by |
  |-------|------|-------------|
  | 0 | `GAINED` | Item placement, the battle's grants, event outcomes (heirloom, curse, rune), `RunOperations.grant_heirloom` (the starting heirloom) |
  | 1 | `COMBAT_ENDED` | The battle's results, one per seat; `amount` 1 for a win, 0 for a loss |
  | 2 | `LEVELED_UP` | The battle's results ([CampaignRunState.apply_battle](../../bandit-bash/scripts/campaign/campaign_run_state.gd)) |
  | 3, 4 | `EFFECT_ACTIVATED`, `COUNTER_CHANGED` | Reserved: no campaign engine records them yet |
  | 5–7 | `RUN_STARTED`, `NODE_CHOSEN`, `NODE_LEFT` | The run's start and the campaign commands |
  | 8, 9 | `ITEM_EQUIPPED`, `ITEM_SCRAPPED` | Item placement and the item pick; `ITEM_EQUIPPED` also `RunOperations.dismiss` (no `target_id`: to the convoy) and re-gearing at a Camp (`Regear`), `ITEM_SCRAPPED` also `RunOperations.scrap` (a convoy item) |
  | 10 | `GOLD_CHANGED` | Event outcomes (`definition_id` is the event), `RunOperations.grant_gold` (War Chest; a Treasure chest's gold, `treasure`) |
  | 11 | `HP_CHANGED` | Event outcomes, `RunOperations.upgrade` (a hurt unit's max-HP gain), a Camp's Feast (`camp_feast`) |
  | 12 | `UNIT_CHANGED` | Event outcomes: a stat, max HP, a pending level-up gain or a prefix; a Feast's cooked ingredient (`amount` its Hit) |
  | 13 | `ITEM_MODIFIED` | Event outcomes: a granted effect, stat deltas or a weapon prefix |
  | 14 | `UNIT_REVIVED` | Event outcomes (the revive shrine) |
  | 15 | `RUNE_DISCARDED` | Event outcomes: a rune left its slot to make room |
  | 16 | `EVENT_DRAWN` | `OpenEventCommand`: the run drew an event at a node (no seat) |
  | 17 | `EVENT_CHOOSING` | `EventChooserCommand`: a seat opened or closed an option's chooser |
  | 18 | `EVENT_CHOSEN` | `EventOptionCommand`: a seat chose an option; the option's own facts follow |
  | 19 | `EVENT_VOTED` | `EventVoteCommand`: a seat voted (or changed its vote) on a team-choice option |
  | 20 | `TEAM_OPTION_DRAWN` | `EventVoteCommand`, on the vote that completes the set: the votes drew the option (`amount`); belongs to no seat |
  | 21 | `UNIT_RECRUITED` | `RunOperations.recruit` and `replace` (Abundance, Mercenary Contract); `target_id` the unit replaced |
  | 22 | `UNIT_DISMISSED` | `RunOperations.dismiss` and `replace`: a living unit left for good, its items to the convoy first (`ITEM_EQUIPPED` each) |
  | 23 | `UNIT_UPGRADED` | `RunOperations.upgrade` (Veteran Company; a Camp's Train, `camp_train`) |
  | 24 | `ARMY_SIZE_CHANGED` | `RunOperations.grant_heirloom` when the heirloom moved max army size (Abundance); `amount` the change |
  | 25 | `FEAST_HELD` | `FeastCommand`: a seat held a Camp's Feast, cooking the actor (empty: none); the heals and cooked gains follow |
  | 26 | `ITEM_GIFTED` | `GiftItemCommand`: a seat gave a convoy item to the convoy of seat `amount` (co-op, at a Camp, an Armory or a Guildhall) |
  | 27 | `ITEM_BOUGHT` | `Armory.buy`: an item (or, with no actor, an heirloom) bought for `amount` gold after any trade-in; its `GAINED` carries `FLAG_BOUGHT` |
  | 28 | `ITEM_TRADED_IN` | `Armory.buy`: the replaced item traded in for `amount` gold off the price |
  | 29 | `UNIT_BOUGHT` | `Guildhall.buy_recruit`: a recruit bought for `amount` gold; `UNIT_RECRUITED` and any dismissal and hand-over facts follow |
  | 30 | `RUNE_BOUGHT` | `Guildhall.buy_rune`: a rune bought for `amount` gold; any `RUNE_DISCARDED`, then its `GAINED` with `FLAG_BOUGHT`, follow |
  | 31 | `PREFIX_REROLLED` | `Guildhall.reroll`: a unit's prefix re-rolled to `definition_id` for `amount` gold (0: free); an `HP_CHANGED` may follow |

- **Paired triggers are two facts.** A hit records `HIT_DEALT`, then `HIT_TAKEN`. `actor_id` is
  always the unit the kind is about, the one an effect's scope tests; `target_id` is the other
  party. Log lines draw received kinds as `<-`.
- **Enums on facts are append-only** with explicit values: they cross the network and sit in
  saves. `to_wire()` / `from_wire()` turn a fact into an array of primitives and back, accepting
  whole-number floats so facts survive JSON. `NO_TILE` is `(-1, -1)`.
- **Ids are opaque.** Instance ids (`unit:57`, `item:412`, `seat:0`) come only from the run's
  [InstanceIdAllocator](../../bandit-bash/scripts/sessions/instance_id_allocator.gd) and are never
  parsed; text comes from the session's `describe(id)`.

## Buses

A bus is presentation only. Nothing connected to one may change rules state, and effects never
listen to one.

- **`CombatBus`** ([scripts/bus/combat_bus.gd](../../bandit-bash/scripts/bus/combat_bus.gd)): one
  per combat session, with the channels `flow` (phases, unit turns, combat end), `unit` (moves,
  spawns, HP, Block, Stance, defeat, stats), `action` (exchanges, attacks, hits, shoves, objects,
  items, swaps, runes, Wait), `world` (the darkness, objects, reinforcement points) and `effect`
  (activations, counters, timed modifiers). Every typed signal carries the fact;
  `fact_played(fact)` fires after it for every fact. Connect as
  `bus.action.hit_taken.connect(...)`.
- **`CampaignBus`** ([scripts/bus/campaign_bus.gd](../../bandit-bash/scripts/bus/campaign_bus.gd)):
  one per run, held by `CampaignSession.bus`, with the channels `run` (the run, nodes, events,
  combats ending), `army` and `effect`. `AudioService` binds the campaign sounds' listener to it.
  [CampaignPlayback](../../bandit-bash/ui/campaign/campaign_playback.gd) plays the run's fact log
  on it when a campaign screen shows the facts: everything past `CampaignSession.played_seq`, so
  each fact plays once, in seq order, whether a command recorded it or not (the run's start, a
  battle's end, level-ups). The campaign map plays what is waiting when it opens and after each
  command; the victory sequence plays each level-up as its card shows. `played_seq` isn't saved,
  so a resumed run plays nothing from before the quit. Commands also announce their batch through
  `CampaignSession.campaign_batch_resolved`.
- **Playback.** [FactPlayback](../../bandit-bash/scripts/sessions/fact_playback.gd) plays a combat
  batch on its bus in fact order, at the game's speed, waiting each fact's duration; fast-forward
  stops before a fact its pause hook marks. Presentation may hold it on a `PresentationRequest`.
  The host plays its own batches and clients play the ones they receive, through the same queue.
- [BusTracer](../../bandit-bash/scripts/bus/bus_tracer.gd) records what any number of buses play,
  for tests and debugging.

## Sessions and commands

- **`CombatSession`** ([scripts/sessions/combat_session.gd](../../bandit-bash/scripts/sessions/combat_session.gd)):
  one map. It holds the rules state (`CombatState`, a `SandboxState`), the `EffectEngine`, the
  roll source (`LiveRolls` over its seat's `COMBAT_ROLLS` stream), the bus, the fact log and the
  command queue. Commands enter through `submit()`, stamped on arrival, and resolve one at a time;
  each resolves atomically (the action, every reaction, the drained queue), then its facts go out
  as one `FactBatch`. Engine diagnostics are logged at ERROR after every batch.
- **`CombatEncounter`** ([scripts/sessions/combat_encounter.gd](../../bandit-bash/scripts/sessions/combat_encounter.gd)):
  one combat node's sessions and everything that crosses maps: the ordered setup steps, cross-map
  effect instances, rune routing and units moving between maps. Sessions never reference each
  other.
- **`CampaignSession`** ([scripts/sessions/campaign_session.gd](../../bandit-bash/scripts/sessions/campaign_session.gd)):
  the run on the host: its streams, its id allocator, the campaign bus, the `CampaignRunState`,
  and the bridge into each battle (`begin_battle`, `resume_battle`, `collect_battle`,
  `end_battle`). It emits `combat_encounter_opened` / `_closed`; the encounter emits
  `session_opened` per map, so observers find sessions without an autoload.
- **Commands.** Combat commands extend [Command](../../bandit-bash/scripts/sessions/command.gd):
  `UnitTurnCommand` (path plus action, one command), `EndTurnCommand`, `StartCommand` (the opening
  swap), `CastRuneCommand`, `DiscardRuneCommand`. Campaign commands extend
  [CampaignCommand](../../bandit-bash/scripts/campaign/campaign_command.gd): `ChooseNodeCommand`,
  `LeaveNodeCommand`, `ItemPickCommand`, `OpenEventCommand`, and the `EventCommand`s
  `EventChooserCommand` and `EventOptionCommand`. Both kinds are checked against the state at resolve time, so the
  first arrival wins and a rejected command changes nothing and costs nothing. An attack, staff or
  shove command is stale, and rejected, if any fact on its map follows the `seq` its forecast was
  based on.
- **The enemy phase is one command.** The last seat's end turn resolves player Phase End, enemy
  Phase Start, every enemy turn, enemy Phase End, the darkness phase, reinforcement arrivals and
  the next player Phase Start with its intents, as one batch
  ([PhaseRunner](../../bandit-bash/scripts/combat/phase_runner.gd)).

## The effect engine

One [EffectEngine](../../bandit-bash/scripts/effects/effect_engine.gd) per combat session.

- **Registration.** [Loadout](../../bandit-bash/scripts/content/loadout.gd) turns units, items and
  heirlooms into `EffectInstance`s with an [EffectOwner](../../bandit-bash/scripts/effects/effect_owner.gd):
  a unit, an item (resolved to its holder), an army (a seat), a rune or a map object. Instances are
  indexed by trigger and by value key. An instance owned by a unit that isn't on the map, or by a
  weapon that isn't equipped, is dormant: no queries, no reactions, state kept.
- **Recording and dispatch.** Rules code records every fact with `record()`. A fact whose kind is a
  trigger dispatches to the instances under that trigger whose scope sees the fact's actor.
  Conditions are tested live. Reaction order: effects marked `resolves_first`, then role (the
  fact's actor, its target, others), seat (enemy owners last), carrier kind (curses last), then
  instance id.
- **Inline and queued.** An inline operation (`ModifyThat`: "that hit takes half damage", "that
  attack gains lifesteal") changes the action in flight and is allowed only on a trigger with an
  inline window. Rules code opens the window with `open_window()` before the amount is committed.
  The windows are `EffectEngine.INLINE_TRIGGERS`: Attack made, Hit dealt and taken, Crit dealt and
  taken, Healed, Healed an ally, Darkness damage taken and Block gained. Every other operation is
  queued in the [ReactionQueue](../../bandit-bash/scripts/effects/reaction_queue.gd) and resolves
  at the next `drain()`, at every step boundary. A chain stops at 16 generations and a step at 256
  reactions (map-object reactions count toward neither); the engine reports it in `diagnostics`.
- **Resource paths.** Every Block gain goes through `gain_block()` (the Block gained window,
  rounded half up, never below 0; denied by `CAN_GAIN_BLOCK`); a negative gain is `lose_block()`
  (`BLOCK_LOST`, no window). Healing goes through `heal()` (the Healed window and
  `HEALING_RECEIVED_PERCENT`), Stance through `change_stance()`, splash through `deal_splash()`.
  Each records its fact.
- **Value queries.** `session.stats(id)` / `engine.stats(id)` returns a
  [StatSheet](../../bandit-bash/scripts/effects/stat_sheet.gd); `get_value(key, ctx)` is exact and
  `get_int()` rounds once by the key's rule (`HALF_UP`, `FLOOR` or `EXACT`); `explain()` returns
  the [ValueBreakdown](../../bandit-bash/scripts/effects/value_breakdown.gd), one line per source.
  Modes apply in a fixed order: replace base, add, multiply, floor and cap, fixed, then the key
  class's rule clamps. Permissions: any denial beats any grant. The static part (bases, deltas,
  unconditional effects) is cached per subject and dropped by the facts that change it; the live
  part (conditional effects, timed modifiers, "that hit" modifiers) is computed on every query.
  Verify mode (debug builds and tests) rebuilds every cached read and reports a difference.
- **Keys.** [CombatValue](../../bandit-bash/scripts/effects/combat_value.gd) (0–999 values, 3000s
  permissions, plus the `Stat` enum), [DamageStage](../../bandit-bash/scripts/effects/damage_stage.gd)
  (1000s, all `EXACT`), [CampaignValue](../../bandit-bash/scripts/effects/campaign_value.gd)
  (2000s values, 4000s permissions). The blocks don't overlap, so one int names any key.
- **Timed modifiers** ([TimedModifier](../../bandit-bash/scripts/effects/timed_modifier.gd)) end at
  `THIS_EXCHANGE`, `UNTIL_PHASE_END`, `END_OF_NEXT_PHASE` or `THIS_COMBAT`, or after their uses.
  Rules code reports `reach_boundary()` with `ATTACK_RESOLVED`, `EXCHANGE_END`, `PHASE_END` or
  `COMBAT_END`; the engine records one `MODIFIER_EXPIRED` per modifier.
- **Counter lanes and charges.** The combat lane starts fresh in every battle (so per-map uses
  refill) and moves with an instance between maps; the campaign lane is copied in at battle start
  and written back by `CampaignSession.collect_battle()`.
- **Observers.** `add_observer()` and `add_context_observer()` are read-only listeners called at
  dispatch on the host: the battle tally, stats and grants.
- **Campaign grants.** A `CampaignGrant` operation (gold, heirloom, recruit, rune) appends a grant
  to `engine.grants` when its reaction resolves; the session hands it to
  `CampaignSession.receive_grant()`, and the run applies it when the battle ends.
- **Snapshots and mirrors.** `capture()` / `restore()` carry the engine as plain JSON (the
  `effects` save section and rejoin snapshots); a client mirror follows the host's facts with
  `follow()` and resolves nothing.

## Forecast and AI

A forecast is the real resolver run on a [Sandbox](../../bandit-bash/scripts/effects/sandbox.gd):
a copy of the engine and the state (`SandboxState.copy_for_sandbox()`), so the forecast equals what
executes. Nothing leaves it: no fact reaches a bus, no stream is drawn, and its grants list starts
empty.

Every random decision goes through a [RollSource](../../bandit-bash/scripts/effects/rolls/roll_source.gd)
(`roll_hit_2rn`, `roll_percent`, `pick_index`; a d100 is 0–99), which records each roll's odds:

| Source | Used by |
|--------|---------|
| `LiveRolls` | Real resolution: draws only from the stream it wraps |
| `ForecastRolls` | The player forecast and the AI's previews: hits land, chances fail |
| `ForcedRolls` | [ExchangeOutcome](../../bandit-bash/scripts/effects/exchange_outcome.gd)'s branch enumeration |
| `SampledRolls` | Sampling, seeded per candidate from `RngKey.mix()`, never a stream |

A sandbox shares no mutable state, so it may resolve on a worker thread, one thread at a time.

## Triggers

The trigger enum is `EffectTerms.Trigger`
([scripts/effects/effect_terms.gd](../../bandit-bash/scripts/effects/effect_terms.gd)); its words
and its effect-text heads are in [effect-triggers.md](effect-triggers.md).

- **Combat triggers** (1–27) map from `CombatFact` kinds in the engine. Moved after acting has no
  kind of its own: it is a `UNIT_MOVED` flagged `SECOND_MOVE`.
- **Campaign triggers** (100–102): Gained, Combat ended, Leveled up, all reaction-only. As it
  stands they are vocabulary only: no engine dispatches campaign facts, and no content uses them.
- **Campaign values** are read from the seat's subject (`seat:N`) on the battle's engine, where the
  army's heirloom carriers are registered: `COMBAT_GOLD`, `GRADE_BONUS_PERCENT` and
  `SHARED_XP_PERCENT` at the battle's end, `UNIT_XP_PERCENT` and the level-up keys on each unit at
  its end, `EXTRA_ENEMIES`, `DARKNESS_ARRIVAL_OFFSET` and `POUCH_ITEM_WEIGHT` at its start,
  `HEALING_RECEIVED_PERCENT` on every heal, `INTENTS_HIDDEN` on every intent draw. Outside a battle
  the campaign layer doesn't read its values yet (`item_placement.gd` and `event_context.gd`
  TOD-001), so `SCRAP_PERCENT`, `MAX_ARMY_SIZE` and the shop keys have no effect in play.
- **Defaults.** `CampaignValue.DEFAULT_BASES` start the percents at the rule's own value (grade
  bonus 25, scrap 20, XP, price and healing 100), so a modifier adds to it: Gilded Purse's +25 and
  Scrapper's Tongs' +20 are additions, and copies stack.

## The rules-code contract

The rules are in `.claude/rules/gdscript.md` §8.5; this is what they mean in practice.

- **Rules code is pure.** Resolvers, the engine, blocks, setup steps and hook registrations touch
  no node, scene tree, autoload (but `NetLog` on the main thread, through the session's logger),
  bus, global RNG or disk.
- **Rules never `await`.** A command resolves completely; presentation plays its facts afterwards
  and never drives rules. A player's answer that changes the game is a command.
- **Effects react through dispatch only,** never through `Signal.connect` on a bus.
- **Every state change records a fact,** through `EffectEngine.record()` in combat or
  `CampaignRunState.record()` on the campaign layer.
- **Definitions are read-only.** Changes live on instances: deltas, granted effects, counters,
  charges. The content test hashes every definition before and after its run.
- **Values are read through stat sheets,** never assembled by the caller.
- **Randomness comes from the roll source or stream handed in;** cosmetic randomness uses its own
  unsaved generator in presentation.
- **Turn-loop extensions plug into [CombatHooks](../../bandit-bash/scripts/combat/combat_hooks.gd):**
  `ARRIVALS`, `TERRAIN_HEALING_ALLOWED`, `PHASE_START_EFFECTS`, `PHASE_END_EFFECTS`,
  `ENEMY_COMMANDS`, `AFTER_ENEMY_PHASE` (the darkness phase, then reinforcement arrivals),
  `INTENTS`, `AFTER_STEP` (objective checks) and `OBJECT_OPERATIONS`. Each hook's doc gives its
  signature. Some run on a sandbox's stand-in session when intents foresee the enemy phase, so a
  registration reads and changes only the session it is handed.
- **Code that may run on a worker** (sandboxes, the AI's previews) doesn't log; it returns
  diagnostics for the main thread.

## Logging

`NetLog` ([scripts/autoload/net_log.gd](../../bandit-bash/scripts/autoload/net_log.gd)) has the
`COMBAT`, `EFFECTS`, `CAMPAIGN` and `AI` categories. Facts log through `to_log_line(describe)`,
for example `s0#143 HIT_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 6 …`; campaign facts
as `c#12 GAINED seat 0 …`. Hot paths check `would_log()` before building text.
`CombatSession.debug_dump()` writes the last snapshot, the commands since and their facts to
`user://logs/`, so a headless test can replay a bug.

## Tests

`tests/effects/` covers facts, buses, value queries and the engine; `tests/sessions/` commands,
sessions, saving, resuming and the wire format. Run them with
`sh bandit-bash/tools/run_tests.sh effects sessions`.
