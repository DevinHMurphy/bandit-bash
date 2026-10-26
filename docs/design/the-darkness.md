# The Darkness

At turn par, darkness starts flowing into the map through its openings: hallways leading out of
the play area, staircases down, doorways into the dark. Like water, it keeps coming. Every few turns
a new wave pours out of each source and creeps across the map, running fastest toward the far end,
spreading sideways more slowly, and climbing back reluctantly. Wherever a wave crosses darkness that
is already there, that darkness deepens, so the tiles on and near a source become the deepest.

The darkness never hides anything and never blocks movement; it only hurts units that **stay** in
it. Lingering is the danger; moving forward is the answer.

**Status:** adopted October 20, 2026 as the game's turn-par pressure system. Adapted to this
design from an outside draft (not kept);
[Changes from the outside draft](#changes-from-the-outside-draft) lists what was changed and why.
**The MVP ships the first-pass damage model: percent of max HP by layer, not an attack (decided
October 23, 2026). It must be playtested; the alternatives below stay on the table.**
[game-vision.md](game-vision.md) wins where the two differ.

## The short version

- Every combat with a turn par gets the darkness, in solo and co-op. Survive and Defend maps don't.
- Players who beat turn par never see it. That is the same line as the +25% grade bonus.
- It flows from authored **sources** toward a **drain** set by the objective, deepening in three
  layers: Dusk, Gloom, Abyss.
- A unit that **ends its side's phase** on a dark tile takes damage; passing through is free. No
  unit is immune, bosses included. The damage model is a first pass, to be playtested.
- It eventually floods every tile, so every map is guaranteed to end. The map never ends early
  because of it: like fatigue in Hearthstone, it is a clock both sides play against, and outlasting
  it can be a deliberate plan. In co-op, nobody waits on a stalled teammate forever.

## Design goals

How it serves the [design pillars](game-vision.md#design-pillars):

| Pillar | How the darkness serves it |
|--------|----------------------------|
| Decrease run length | Turn par becomes a pressure wave, so standard combats stay near 2–5 minutes and key combats near 5–10 |
| Incentivize proactive players | Standing in darkness is a calculated trade, not a binary: dash through it, hold a chokepoint in it one more turn, or break a wall to open a lane |
| Reduce cognitive burden | One rule to learn ("don't linger"); layers shown as art; the damage number appears only in the move preview |
| Remove "hurry up and wait" | Every map is guaranteed to end, so co-op teammates never wait indefinitely |

It also urges the army forward: it flows from behind the army toward the far end of the map, so
retreating means moving toward the deepest darkness.

## How it plays

For players who are slower than par, it changes the questions each turn:

- Dash the Hakkapel through the darkness to flank, and end the move on dry ground.
- Hold a chokepoint in shallow darkness for one more turn at low HP.
- Stay out of the "river": the darkness runs fastest along the main path, so side rooms stay dry a
  little longer, but only for a while.
- Break a wall early for a shortcut, knowing it opens a path for the darkness too.
- Pull a wounded unit toward the front, because "back" is where the darkness is deepest.

## Rules

### Sources

- Darkness enters through **sources**: authored map features that lead out of the play area, such
  as hallways running off the map, staircases down, doorways, wells and collapsed walls. A source
  is one or more tiles of that feature.
- Every map with a turn par authors at least 2 source candidates; the map authoring check rejects a
  map with fewer.
- At combat start, the run's seeded stream picks which candidates are **active**, identically on
  every parallel co-op copy. Inactive candidates are ordinary terrain for that combat.
- Active sources are marked from turn 1: darkness pooling in the opening, plus a small counter on
  the source. Before turn par it shows the turns until the darkness arrives; afterwards, the turns
  until the next wave.

### The drain

The darkness flows "downhill" toward the map's **drain**, set by the objective:

| Objective | Drain |
|-----------|-------|
| Rout | The standable tile farthest (by walking distance) from the active sources; ties broken by the run's seed |
| Defeat the Leader | The leader's starting tile |
| Defeat the mini-boss | The mini-boss's starting tile |
| Seize | The seize tile |
| Defeat the boss | The boss's starting tile |
| Survive, Defend | No darkness: these maps already end on a turn count |

The drain is never shown; players read the flow from the darkness itself.

### Waves and creep

- **Floodable tiles** are tiles at least one [movement type](unit-roster.md#movement-and-tags) can
  stand on. Walls, closed doors and unbroken breakables block the darkness; units don't.
- **Height** of a tile is its 4-directional walking distance to the drain over floodable tiles. A
  tile that can't reach the drain has no height.
- **Step cost** for the darkness moving from one floodable tile to an adjacent one: downhill (to a
  lower height) 1; level (same height, or either tile has no height) 2; uphill (to a greater height)
  3.
- **Flow cost** of a tile for a source is the cheapest total step cost from any of that source's
  tiles to it.
- A **wave** has a reach that starts at 0 when it is released and grows by the creep speed every
  turn. A wave **enters** every tile whose flow cost is within its reach, each tile at most once.
- Each time a wave enters a tile, the tile deepens one layer: dry → Dusk → Gloom → Abyss. Abyss
  stays Abyss. A tile's layer is the number of waves that have entered it, from any source, up to 3.
- Waves never end and the darkness never recedes.
- When a breakable breaks, flow costs are recalculated, and every wave enters any newly reachable
  tiles within its reach.

### The darkness step

All changes to the darkness happen in one step at the end of every turn: after the enemy side's
[Phase End](game-vision.md#combat), before the player side's next Phase Start (Block and Stance
refresh, terrain healing, reinforcement arrival). In order:

1. **Creep:** every existing wave's reach grows by the creep speed, and it enters the tiles now
   within its reach.
2. **Release:** if a wave is due, every active source releases a new wave, which enters that
   source's own tiles.
3. **Erosion:** each breakable next to a flooded tile adds one turn of contact; a breakable that
   reaches the contact limit breaks and becomes floor.

The first wave is released in the darkness step at the end of the turn before turn par, so the
sources are dark when turn par begins. Further waves follow every wave interval.

### Arrival

When the first wave is released:

- Every enemy switches to aggressive AI (moves toward and attacks the nearest reachable target),
  except a boss that holds a fixed tile (throne, gate).
- [Reinforcement points](game-vision.md#combat-maps) stop spawning enemies. Points the player
  already closed stay closed and keep their XP reward.

### Layers and damage

**The damage model is a first pass and must be playtested.** The layers, and the rule that only
lingering hurts, are fixed. How the hurt is dealt may change. Candidates:

- **Percent of max HP by layer** (first pass, below): simple and scales with every unit.
- **A status effect:** each phase ended in darkness adds stacks of a "Shrouded" status, deeper
  layers adding more, using the [status stacking rules](game-vision.md#combat).
- **Flat damage that grows** with how many phases in a row the unit has ended in darkness, so a
  first linger is cheap and staying is not.

| Layer | Waves that have entered the tile | Damage to a unit that ends its side's phase on it (first pass) |
|-------|----------------------------------|-----------------------------------------------------------------|
| Dusk | 1 | 10% of max HP |
| Gloom | 2 | 25% of max HP |
| Abyss | 3 or more | 50% of max HP |

- Damage applies at each side's own **Phase End**, to that side's units on flooded tiles: player
  units at the end of the player phase, enemy units at the end of the enemy phase. It applies after
  that side's Phase End and Unit Turn End effects have resolved, so a Phase End heal lands first
  (combat core plan, question 12).
- Units that move through darkness without ending their side's phase in it take no damage.
- Damage uses the tile's layer at the moment it applies, is rounded down with a minimum of 1, and
  can defeat a unit. Permadeath applies as always; a commander defeated by the darkness ends a solo
  run, or returns after the combat at critical health in co-op.
- **No unit is immune**: bosses, mini-bosses and leaders take darkness damage like everyone else.
- It always fires its own trigger, **Darkness damage taken**, so effects can answer it (e.g. a
  heirloom: "Darkness damage taken −50%").
- **Not an attack (MVP, decided October 23, 2026).** This decides how the darkness meets Block and
  Stance; the other column is kept for playtesting:

| | Not an attack (MVP) | Counts as an attack |
|---|---|---|
| Damage stages | Skipped: no Mitigation, crit or Block | Passes through them, so Block and Mitigation reduce it |
| Stance | Never lost | Lost as for any hit that deals real damage, so lingering makes units Exposed to crits |
| Triggers | Only Darkness damage taken | Also Hit taken and Damage taken, so on-hit effects fire |
| Feel | A clean clock; Block can't make lingering free | Defensive builds can sit in it; lingering sets up enemy crits |

### Terrain

- **Breakables** (walls, debris): contact with the darkness cracks them, and the cracks show the
  turns left until they break. When they break, the darkness flows through and a new lane opens for
  both sides.
- **Locked doors don't erode.** They stay closed until opened with a lockpick or a lever, so the
  darkness can't open loot rooms for free; a closed door blocks the darkness like a wall.
- **Healing terrain** (Fort, Castle Gate, Throne, Camp tiles) doesn't heal a unit while its tile is
  flooded.
- Everything else works normally in the darkness: houses, chests, terrain avoid and DEF/RES bonuses,
  and movement costs.

### What the darkness does not do

- It never hides units, terrain or the danger zone. If fog of war is ever added, the two stay
  separate: fog is about vision, darkness is about time.
- It never slows, blocks or pushes units.

### Enemy AI

- Enemy AI never ends a move on a flooded tile if a dry tile serves the same goal.
- Enemies follow every darkness rule the player does.

### Guaranteed end

New waves keep coming, so every floodable tile is eventually entered by at least three waves and
becomes Abyss. A unit in Abyss is defeated within two of its own phases without healing, so every
map ends without a separate fail-safe.

The map **never ends early** because of the darkness; there is no automatic loss once it covers
the map. Like fatigue in Hearthstone, it is a clock both sides play against. Since no unit is
immune, outlasting it can be a deliberate plan: a sturdy army with healing can let the darkness
wear down the enemy, bosses included.

### Telegraph and readability

- **Sources** show pooling darkness and a counter from turn 1.
- **Layers** are shown by darkness density (three distinct shades or patterns), as art rather than
  UI, readable without relying on colour alone. Flow animation runs in the direction of travel.
- **Next change:** tiles that will darken or deepen at the end of the turn show creeping tendrils.
- **Damage:** when a unit is about to end its move on a flooded tile, the move preview shows the
  darkness damage it will take. This is the only place the number appears.
- **Breakables** in contact show cracks counting down to the break.
- The darkness has its own visual language (including torches, below), distinct from night.

### Co-op

On [parallel maps](game-vision.md#combat-maps):

- Each player's map gets the darkness at that map's own turn par, on its own turn counter.
- **Speed is the reward:** a player who wins before a teammate's turn par can
  [reinforce](game-vision.md#combat-maps) that teammate before the darkness arrives there.
- Each unfinished map's status, which senders use to choose where to reinforce, shows turns to par,
  or, once the darkness has arrived, how much of the map is dark.
- Reinforcements arrive on dry tiles next to the receiving player's commander
  ([game-vision.md](game-vision.md#combat-maps)); otherwise on the nearest dry tiles their movement
  type can stand on; otherwise on the lowest-layer tiles available. They then follow every darkness
  rule.
- A map where two players fight together (joining a teammate, or a later shared battle) has one
  darkness, on one turn counter.

### Darkness-reward effects (future)

Later, heirlooms and other effects can reward standing in the darkness by layer, turning the risk
up: e.g. "While on Gloom or deeper: +3 damage", or "Phase End, while on Abyss: gain 5 Block".
They use a While condition on the tile's layer (see [effect-triggers.md](effect-triggers.md)).
None are in v1.

### Torches: the Brazier

The darkness's torch is the **Brazier**, a neutral [map object](map-objects.md#new-objects) in the
MVP (decided October 23, 2026). A unit next to it lights or douses it as its action; while lit,
tiles within 2 tiles never deepen past Dusk. Braziers are the darkness's signature counterplay and
part of its visual identity: positions worth holding and fighting over, and the enemy AI douses
them.

## How it touches other systems

- **Grades:** beating turn par already earns +25% gold. With the darkness, it also means never
  facing it; the two reward the same thing.
- **Slow maps in co-op:** a slow map now costs units, because the darkness keeps deepening and
  nothing brings fallen units back. That is accepted: the answer is to be fast, or to be
  reinforced by a faster teammate before the darkness arrives.
- **Effects:** the Darkness damage taken trigger and a While condition on the tile's layer are in
  [effect-triggers.md](effect-triggers.md); heirlooms, traits and equipment can answer the darkness.
- **Save impact:** darkness state is battle state, saved in the `COMBAT` block: active sources, each
  wave's reach, each tile's layer, and each breakable's contact count. On parallel maps it is one
  state per map, which joins the already-noted save change to one battle state per player. Section
  keys and versions are chosen when the system is built.
- **Determinism:** active sources and Rout drain ties come from the run's seeded stream; everything
  else is computed from the map, so every client derives the same flow.

## Authoring guidelines

- Place source candidates behind or beside the player deployment zone, so the darkness flows past
  the player toward the enemy.
- Make sources read as places darkness would come from: openings out of the play area, stairs down,
  wells, broken walls.
- Give candidates on the same map different positions, so the darkness's path (and the map's safe
  side rooms) changes from run to run.
- Use breakables deliberately: they are timed gates that open new lanes once the darkness reaches
  them.
- Maps are small (standard 8×6 to 10×8), so check that the darkness doesn't cross the whole map in
  one or two waves; keep arrival tiles near the deployment zone but not on a source.

## Values (first pass, to tune in playtesting)

| Value | First pass |
|-------|------------|
| Source candidates per map | At least 2 (authored) |
| Active sources | Standard 1; key and boss 2 (picked by seed) |
| First wave | Released at the end of the turn before turn par |
| Wave interval | Every 2 turns |
| Creep speed | Reach grows by 2 per turn (2 tiles downhill, 1 level, under 1 uphill) |
| Step costs | Downhill 1, level 2, uphill 3 |
| Maximum layer | 3 (Abyss) |
| Dusk / Gloom / Abyss damage | 10% / 25% / 50% of max HP (damage model itself still to playtest) |
| Breakable contact limit | 3 turns |

All damage is rounded down, with a minimum of 1. Turn par values are set per map once the new maps
are designed.

## Changes from the outside draft

| Outside draft | Here | Why |
|---------------|------|-----|
| Escape objective and its drain | Removed; Defeat the Leader and Defeat the mini-boss added | Matches this design's objectives |
| Damage at the end of an allied NPC "other phase" | Two sides only | This design has no allied NPC phase |
| Rescued (carried) units | Removed | This design has no rescue or carry action |
| Units are "downed" | Units are defeated (permadeath); a fallen commander ends a solo run, or returns at critical health in co-op | Matches the army rules |
| Doors erode like breakables | Locked doors don't erode; breakable walls still do | Doors gate the lockpick and loot economy |
| Bosses and mini-bosses are immune | No unit is immune | Outlasting the darkness can be a player's plan |
| Damage model fixed at % of max HP | % of max HP is a first pass; a status or growing flat damage are candidates | Must be playtested |
| "Villages" | Houses | This design's interactable |
| Fog of War coexists | Only "if fog of war is added" | Fog of war isn't in this design |
| Damage rules against combat unstated | Its own trigger; whether it counts as an attack (Block, Stance, on-hit triggers) is open | Fits the Block, Stance and effects systems |
| Timing in generic phases | Placed in this design's turn phases (Phase End; before Phase Start) | Matches effect-triggers.md |
| "About 5 minutes" combats | Standard 2–5, key 5–10 minutes | This design's targets |
| Replaces a "closing labyrinth" | Not mentioned as a replacement | This design never had one |

## Open questions

- **Damage model:** the MVP ships percent of max HP, not an attack. Playtesting decides whether a
  status or flat damage that grows with time spent in it would play better.
- **Small maps:** whether the first-pass creep speed and wave interval suit FEH-scale maps.
- **Darkness-reward effects:** which heirlooms reward standing in the darkness, once the damage
  model settles.

## Playtest watch list

- How often the darkness arrives (are turn pars too tight or too loose?).
- How many turns maps last after arrival, and real minutes per turn.
- Whether players can read where the darkness is flowing before the tendrils show it.
- How often units are defeated by darkness damage, and at which layer.
- How often side rooms let players dodge the main flow, and for how long.
- How often breakables break before a map ends, and whether players break them deliberately.
- Whether the darkness stays readable on every biome's art.
- In co-op: how often a teammate is reinforced before their par, and how often a map is lost to the
  darkness.
- Whether outlasting the darkness (healing and sturdy units letting it wear down the enemy) is a
  fun plan or a stall that drags maps out, especially on boss maps.

## Alternatives considered (from the outside draft)

- **Rifts with a uniform flood:** darkness spread evenly from rift tiles and deepened one layer per
  turn. Replaced because sources read better as physical places, and wave-based creep behaves like
  water and gives the darkness a direction players can read.
- **Darkness that hunts the player:** waves path toward the nearest player unit. Not used, because a
  fixed drain keeps the flow predictable and the telegraph honest.
- **Heart contest:** a final-arena tile whose holder's side is spared the damage. Cut because it made
  a minor combat revolve around one tile.
- **Surge:** the front shoving units one tile forward. Cut; it was the only push in the system and
  added edge cases without changing the core decision.
