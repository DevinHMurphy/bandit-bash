# Multiplayer Combat Options

**Status:** October 20, 2026. **Decided:** Option B (parallel maps) for the MVP, Option D (hybrid)
as the target; reinforcing a teammate, with the sender choosing (R1 + R2); the team wins if anyone
wins. **Decided October 20:** no retreat and no recovery mechanics in co-op: permadeath applies to
every unit as in solo (the only way back is a rare revive event), and the negative feedback loop is
accepted; a commander that falls in co-op returns at critical health
([below](#when-a-commander-falls)). All recorded in [game-vision.md](game-vision.md#combat-maps).

**The question:** in co-op, do players fight one battle together, or each on their own map? Small
Fire Emblem Heroes–scale maps keep solo combats short, but they don't stretch to four armies, and
building larger maps for every player count is a lot of design work.

## What any option has to work with

These are already decided or built:

| Fact | Source |
|------|--------|
| 1–4 players (`DEFAULT_MAX_PLAYERS = 4`), set when a campaign starts; a forfeit can lower it (decided October 24, 2026) | `steam_network.gd`, save-system.md |
| Each player has their own army: 4–6 units typical, up to 8, led by a commander | game-vision.md |
| The whole army deploys in every combat; army size works like Slay the Spire's energy | game-vision.md |
| Maps are small: standard 8×6 to 10×8, key about 12×10, boss larger | game-vision.md |
| Standard combats should take 2–5 minutes | game-vision.md |
| The team travels one shared campaign map and votes on the route | game-vision.md |
| The host resolves everything; clients send commands and replay events | effects-system.md, `Godot_FE` multiplayer plan |
| One combat save file per campaign, holding one turn number and one phase | `combat_data.gd`, save-system.md |
| Effect scopes include Any Ally Unit (co-op partners' units); phases are per map (event bus plan, question 11) | effect-triggers.md |
| Each player gets their own combat Standout and their own Feast | game-vision.md, items.md |

For scale: four players with typical armies field 16–24 units. A solo standard map holds 4–6.

## Option A: one shared battle, maps sized per player count

Everyone deploys onto one map. Each map is authored in variants for 1–4 players, or as one map
whose extra deployment zones and enemy groups switch on with the player count.

- **Co-op feel:** the strongest. Armies fight side by side; Any Ally Unit effects, Phalanx and
  Radiance work across players.
- **Design cost:** the highest. Every map needs four sizes or a scaling layout, all balanced.
- **Pacing:** players act at the same time in the shared phase, but enemy phases grow with the
  enemy count; a four-player standard combat could run well past 5 minutes.
- **Save and network:** fits what exists: one battle, units tagged with their owner's seat.
- **Risk:** the most work for the number of maps the MVP needs, and the hardest to balance.

**A2: shared battle with a deployment cap.** Each player deploys only part of their army (e.g. 2–3
units each), so maps stay near solo size. Cheaper, but it breaks two decided rules: the whole army
deploys, and army size means more actions.

## Option B: parallel maps

Each player fights their own copy of the same combat at the same time: same map, same seed, their
own army. The combat ends when everyone has finished.

- **Co-op feel:** the weakest in combat; co-op lives on the campaign layer (route votes, shared
  run). Partners can watch each other's maps.
- **Design cost:** the lowest. Every map is authored once, at solo size, and solo balance carries
  over unchanged.
- **Pacing:** every player keeps the solo pace. Whoever finishes first waits for the others.
- **Save and network:** a **save-format change**: the combat block holds one turn and phase; this
  needs one battle state per seat. The host runs one simulation per player.
- **Effects:** Any Ally Unit only reaches partner maps for effects that aren't positional; the
  shared player phase becomes one phase per map.
- **Light links** can add co-op feel at low cost, for example:
  - runes can be used on a partner's map (**adopted for the MVP**, October 23, 2026: any player, during
    that map's player phase, whether or not their own map is finished);
  - closing a reinforcement point on one map delays reinforcements on every map;
  - a team objective counter spans all maps (e.g. "the team must free 3 houses").

## Option C: one shared battle on a sector map

One battle on a map built from modules: each player starts in their own solo-sized sector, and the
sectors connect to a shared center (e.g. the boss's arena). Players fight apart at first and meet in
the middle.

- **Co-op feel:** strong, with a natural rhythm: separate fronts, then a joint push.
- **Design cost:** medium, but up front. Sectors are authored once and stitched together by player
  count; it needs a stitching system and connector rules.
- **Pacing:** sector fights run at solo pace in the shared phase; enemy phases still grow with the
  number of sectors.
- **Save and network:** fits the existing single-battle save.
- **Risk:** the stitching system is new work, and fronts can feel like parallel maps until they
  meet.

## Option D: hybrid by combat type

Standard combats run as **parallel maps** (Option B): fast, cheap, solo-balanced. Key and boss
combats are **shared** (Option A or C): the big moments happen together.

- **Co-op feel:** good where it matters most; boss fights are team events.
- **Design cost:** low for the many standard maps; shared design work only for the small key and
  boss pools.
- **Pacing:** standard fights keep solo pace; shared fights can afford to run longer.
- **Save and network:** needs both modes, parallel and shared.
- **Risk:** two combat modes to build and test.

## Comparison

| | A: shared, sized | A2: shared, capped | B: parallel | C: sectors | D: hybrid |
|---|---|---|---|---|---|
| Co-op feel in combat | Strongest | Strong | Weak (links help) | Strong | Good at key moments |
| Map design cost | Highest | Low | Lowest | Medium, up front | Low, then medium |
| Keeps "whole army deploys" | Yes | **No** | Yes | Yes | Yes |
| Standard combat pace | Slow at 4 players | Solo-like | Solo | Solo-like, longer enemy phases | Solo |
| Save format | Fits | Fits | Needs per-seat battles | Fits | Needs both |
| Build effort for the MVP | High | Low | Low | High | Low (B first) |

## Recommendation

**Ship Option B for the MVP, with one or two light links, and aim for Option D afterwards.**

- B is the cheapest path to a playable co-op MVP: no map scaling, solo balance carries over, and it
  matches the concern that larger maps would take great design work.
- D keeps the door open: once the MVP plays well, shared boss fights (and later key combats) give
  co-op its big moments, and only those few maps need multi-player design.
- If shared play inside combat is essential from day one, choose C over A: it scales by adding
  authored sectors instead of re-authoring every map.

## When one player loses

On parallel maps, players can finish differently: one wins while another is losing or has lost.
Three questions sit underneath:

1. **Can a struggling player be helped** before they lose?
2. **What does losing a map cost** that player, and the team?
3. **What happens to a player whose commander falls?** In solo it ends the run; in co-op that
   would knock a friend out of a run the others are still playing.

### Help before losing

**H1. Reinforce (send units).** When a player wins their map, they can send some of their
surviving units onto a teammate's map that is still being fought. The units arrive at the start of
the next player phase, on the map's deployment edge or a reinforcement point, and their owner
controls them there.

- Turns parallel maps into shared fighting at exactly the moment it matters, with no new map work.
- Winners stay busy instead of waiting.
- Sent units can die (permadeath), so helping is a real risk, not a free win.
- Decide: how many units can be sent (all, or up to a number); whether they arrive at full HP or as
  they finished; whether sent units earn XP and count toward the Standout on the partner's map (recommended:
  yes, for their owner).
- Needs: deployment-edge or reinforcement-point tiles on every map (reinforcement points are
  already planned), and the host merging two players' units onto one map.

**H2. Support from afar.** A player who has finished (won or lost) can act on teammates' maps
without units: use their own runes there, or pick one small team buff per partner phase.

- Cheaper than H1 and keeps every player engaged, including the one who lost.
- Weaker co-op feel than H1; it's a side panel, not fighting together.

### Losing a map

**L1. The team wins if anyone wins.** *(Decided.)* The combat counts as won for the team when at
least one player wins. A player who fails their map's objective gets no gold, XP or Standout for it, and
their fallen units stay dead. Simple, and keeps the run moving.

**Rejected October 20, 2026** (no retreat or extra lives anywhere in the game):

- **L2. Retreat:** a player could leave their map before losing to save surviving units.
- **L3. Overflow battle:** fallen units were captured, not dead, and a team rescue skirmish could
  free them.

### When a commander falls

**Rejected October 20:** **C1. Downed, not dead** (a fallen co-op commander came back after the
combat). A commander's fall is final, as in solo.

**Decided October 20: C4. Back at critical health.** A commander that falls in co-op returns after
the combat at critical health (first pass: 10% of max HP, at least 1), with no other cost. That
player's map is lost and their fallen units stay dead; the run is lost only if every player's
commander falls in the same combat. In solo, a fallen commander still ends the run.

Not chosen:

- **C2. Eliminated:** that player's run would end while the team played on.
- **C3. Team loss:** any commander falling would end the run for everyone.

### Choosing whom to reinforce (3–4 players)

With more than two players, a winner may have several teammates still fighting. Options:

- **R1. Sender chooses.** The winner sees every ongoing map with a short status (turn, units left,
  enemies left) and picks one. Full player agency; risks everyone piling onto one map.
- **R2. Call for aid.** A struggling player raises a flag on their map, shown to everyone who has
  finished. Senders still choose, but the flag says where help is wanted. Communication without
  voice chat.
- **R3. Automatic.** Units go to the map in the most danger (e.g. fewest units left relative to
  enemies). No decision, but no agency, and "danger" is hard to judge well.
- **R4. Split.** A sender can divide their units between several maps. Most flexible; spreads help
  thin and adds decisions.

**Decided: R1 + R2.** The sender chooses, helped by each map's status and any call-for-aid
flags. Each sender commits all the units they send to one map (no splitting, no hopping between
maps), but different senders can help different maps, and a map can receive several senders. If a
map ends before sent units arrive, they return unharmed.

### Recommendation

For the MVP: **H1 (reinforce) + L1 (team wins if anyone wins)**, with R1 + R2 for choosing whom to
reinforce. Decided October 17, revised October 20 to drop retreat (L2) and downed commanders (C1).

- H1 prevents losses before they happen and is the most co-op answer that parallel maps can give
  without new map work. With permadeath final, it is now the main way the team protects a
  struggling player.
- A fallen commander returns at critical health (C4), so a player is never knocked out of the run.

## Co-op deployment and reinforcement arrival

**Decided October 23, 2026** (recorded in [game-vision.md](game-vision.md#combat-maps)):

- **Arrival:** reinforcements arrive at the start of the receiving map's next player phase, on dry
  tiles next to the receiving player's **commander**; if those are taken, on the nearest dry tiles;
  then on the darkness's fallback. The commander is the rally point, so no banner object is needed
  and help lands where the fight is.
- **Sending:** any subset of surviving units, at their current HP, including the commander. A sent
  commander that falls counts toward "every commander fell" as normal.
- **XP:** sent units earn personal bonus XP toward the same per-combat cap, not shared XP a second
  time; the Standout stays on each player's own map.
- **Turns:** each parallel map runs on its own turn counter, so players never wait on each other's
  phases.

Still open: **two players on one map** in later shared battles (how the deployment zone is shared).

The ideas that led here, kept for reference:

- **Arrive on friendly units:** reinforcements appear next to the receiving player's units rather
  than on fixed tiles, so help lands where the fight is. Arriving might take an extra turn (sent
  this phase, placed next phase), so help can't be instant.
- **The darkness floods fixed zones:** darkness sources are authored behind or beside the
  deployment zone, so a fixed arrival zone is among the first places to flood. Arrival points
  need to move with the fight, not stay where the army started.
- **A rally banner:** the receiving player places a banner (or a rally item) on their map to mark
  where reinforcements arrive. It gives them a real decision (where is it safe, where is help
  needed) and solves the darkness problem. Open: whether it costs an action, whether it can be
  moved, and what happens if the banner's tile floods or an enemy stands on it.
- **Sending commanders:** an earlier draft forbade it, to keep downed-commander rules simple and
  to stop a player stranding their commander on a losing map. Downed commanders are gone, and a
  co-op commander that falls returns at critical health anyway, so that reason no longer holds.
  Allowing it adds a choice (the commander is often the strongest unit). Open edge: whether a
  commander falling on a teammate's map counts toward "every commander fell", the whole-team
  loss.
- **Two players on one map** (later shared battles): how the deployment zone is shared, e.g. one
  block per player, arranged at the same time in prep.


## Recovering from a lost map (closed)

**Decided October 20, 2026: no recovery mechanics.** Permadeath applies in co-op as in solo, with no
retreat; the only way back for a fallen unit is a rare revive event, and a fallen commander returns
at critical health. A player who loses most of their army is weaker for the next
combat and likelier to lose again. That negative feedback loop is known and accepted as part of the
design principles; the team's answer is to protect each other during combat, by reinforcing.

[The darkness](the-darkness.md) sharpens this: a map that runs past turn par floods, so a slow
player loses units to the darkness as well as to enemies. It also gives reinforcement a deadline:
winning before a teammate's par lets help arrive before the darkness.

Strategies considered and not adopted:

| Strategy | What it was | Why not |
|----------|-------------|---------|
| S1. Fall back | A downed commander's map ended at once and survivors retreated | Retreat and downed commanders are out |
| S2. Captured, not dead | Units fallen on a lost map could be ransomed or rescued | An extra life |
| S3. Levies | Temporary units refilled a weakened army to a floor | The loop is accepted; not adopted |
| S4. Join a teammate | A weakened player fought on a teammate's map until rebuilt | The loop is accepted; not adopted |

Still usable without softening permadeath, if wanted later: each player's copy of a map scaling its
enemy count to that player's army (the vision already aims standard combats at "a similar number to
the player").

## Disconnects and forfeits

**Decided October 24, 2026** (recorded in [game-vision.md](game-vision.md#combat-maps)):

- A disconnect **pauses the game** for everyone until the player reconnects (a timer shows); they
  rejoin from a snapshot, which the event bus plan already supports.
- After a waiting period (first pass: 2 minutes), the host can **remove** the disconnected player,
  which counts as a forfeit.
- Any **non-host** player can **forfeit** at any time: their army and map leave the match, their
  seat is removed from the campaign save, and their run is archived for them as lost. The rest play
  on. This changes the save rule that the player count is fixed for a campaign's life; the format
  change belongs to the multiplayer plans.
- A **host** disconnect ends the match for everyone; the host resumes from its last checkpoint.

## Questions any option raises

- **Commander death and losing a map:** see [When one player loses](#when-one-player-loses).
- **Gold and loot:** decided October 23, 2026: per player, except one shared shop stock (see
  Co-op ownership in [game-vision.md](game-vision.md#combat-maps)).
- **Enemy scaling** for shared fights: more enemies, stronger enemies, or both.
- **Turn timers:** whether shared phases need a timer so one slow player can't stall the others.
