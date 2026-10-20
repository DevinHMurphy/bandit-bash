# Multiplayer Combat Options

**Status:** October 16, 2026. **Decided:** Option B (parallel maps) for the MVP, Option D (hybrid)
as the target; recorded in [game-vision.md](game-vision.md#combat-maps). **Decided October 17:**
reinforce, retreat, the team wins if anyone wins, downed commanders in co-op, and choosing whom
to reinforce (R1 + R2) ([below](#when-one-player-loses)). **Open:**
[recovering from a lost map](#recovering-from-a-lost-map-open).

**The question:** in co-op, do players fight one battle together, or each on their own map? Small
Fire Emblem Heroes–scale maps keep solo combats short, but they don't stretch to four armies, and
building larger maps for every player count is a lot of design work.

## What any option has to work with

These are already decided or built:

| Fact | Source |
|------|--------|
| 1–4 players (`DEFAULT_MAX_PLAYERS = 4`), fixed when a campaign starts | `steam_network.gd`, save-system.md |
| Each player has their own army: 3–6 units typical, up to 10, led by a commander | game-vision.md |
| The whole army deploys in every combat; army size works like Slay the Spire's energy | game-vision.md |
| Maps are small: standard 8×6 to 10×8, key about 12×10, boss larger | game-vision.md |
| Standard combats should take 2–5 minutes | game-vision.md |
| The team travels one shared campaign map and votes on the route | game-vision.md |
| The host resolves everything; clients send commands and replay events | effects-system.md, `Godot_FE` multiplayer plan |
| One combat save file per campaign, holding one turn number and one phase | `combat_data.gd`, save-system.md |
| Effect scopes include Any Ally Unit (co-op partners' units), and all players share one player phase | effect-triggers.md |
| Each player gets their own combat MVP and their own Feast | game-vision.md, items.md |

For scale: four players with typical armies field 12–24 units. A solo standard map holds 3–6.

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
  - runes can be used on a partner's map;
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
  they finished; whether sent units earn XP and count toward MVP on the partner's map (recommended:
  yes, for their owner).
- Needs: deployment-edge or reinforcement-point tiles on every map (reinforcement points are
  already planned), and the host merging two players' units onto one map.

**H2. Support from afar.** A player who has finished (won or lost) can act on teammates' maps
without units: use their own runes there, or pick one small team buff per partner phase.

- Cheaper than H1 and keeps every player engaged, including the one who lost.
- Weaker co-op feel than H1; it's a side panel, not fighting together.

### Losing a map

**L1. The team wins if anyone wins.** The combat counts as won for the team when at least one
player wins. A player who lost their map gets no gold, XP or MVP for it, and their fallen units are
fallen (revive at a Camp). Simple, and keeps the run moving.

**L2. Retreat.** Before losing, a player can retreat from their map: surviving units escape, the
player forfeits that combat's rewards, and nothing else is lost. Gives a controlled exit instead of
a wipe. Can combine with L1.

**L3. Overflow battle.** Units that fall on any map aren't dead yet: they are captured. After the
combat, the whole team fights a short shared **overflow** skirmish (a small rescue map, with every
player's surviving units) to free them; units not freed are lost for good. The idea from games with
an overflow area where units fight again.

- Turns a loss into a team event and a second chance, which is very co-op.
- Adds a combat (pacing) and needs a shared battle mode, which the MVP doesn't have; it fits once
  Option D's shared mode exists.
- Decide: whether it happens every time units fall, or only when a whole map is lost.

### When a commander falls

**C1. Downed, not dead (co-op only).** A commander that falls in co-op is **downed**: the player's
map is lost (L1), but the commander returns after the combat at low HP, with a cost (e.g. lose
gold, or a random heirloom). The run ends only if every player's commander falls in the same
combat.

**C2. Eliminated.** As in solo: that player is out of the run. They can still watch, and use H2
support if chosen. Harsh in a game meant to be played together.

**C3. Team loss.** Any commander falling ends the run for everyone. The most punishing; makes every
commander everyone's problem.

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

For the MVP: **H1 (reinforce) + L1 (team wins if anyone wins) + C1 (downed commander)**, with
**L2 (retreat)** as a cheap extra. **Decided October 17, 2026**; recorded in game-vision.md.

- H1 prevents most losses before they happen and is the most co-op answer that parallel maps can
  give without new map work.
- L1 and C1 keep everyone in the run; the cost of losing is rewards and units, which permadeath
  already makes painful.
- **L3 (overflow)** is the natural follow-up once shared battles exist for Option D.

## Recovering from a lost map (open)

**The problem.** In co-op a player can lose a map and stay in the run (downed commander). But a
lost map usually means most of their army fell, and permadeath keeps them dead. The next combat is
often not a Guildhall, so they arrive with a commander and one or two units, and lose again. The
strong player carries; the weak player has no army and no impact. Solo never hits this, because a
fallen commander ends a solo run.

The spiral has four links. Each strategy below cuts a different one:

| Link | Strategy |
|------|----------|
| A lost map kills most of the army | **S1. Fall back:** stop the wipe early |
| Fallen units are gone for good | **S2. Captured, not dead:** let the team undo it |
| Nothing refills the army before the next fight | **S3. Levies:** refill to a floor |
| The weakened player fights alone at full difficulty | **S4. Join a teammate:** fight together until rebuilt |

**S1. Fall back.** When a player's commander is downed, their map ends at once: every surviving
unit retreats with it instead of fighting on. Losses stop at the moment the map is lost. Retreat
(already decided) lets a player do this earlier by choice.

**S2. Captured, not dead.** Units that fall on a *lost* map are captured. If the team wins the
combat, they can be freed, at a cost that keeps losing painful:

- **Ransom:** pay gold at the next Guildhall to free each one (any teammate can pay).
- **Rescue:** the overflow skirmish, once shared battles exist.
- Either way they return wounded (e.g. half HP).
- Catch: a unit that falls on a map its player *wins* is still dead, so losing a map can look
  kinder than winning with casualties. Ransom's cost and the lost rewards are what keep that fair.

**S3. Levies.** Before each combat, any player whose deployable army is below a floor (e.g. 3
units) gets temporary **levies** to fill up to it: plain units of a basic type, no prefix, at the
army's average level, with simple weapons. Levies leave after the combat, unless the player keeps
one by paying its recruit price at the next Guildhall. A downed commander also returns at full HP.
This directly answers "no army".

**S4. Join a teammate.** A player below the floor can choose to deploy onto a teammate's map for
the next combat instead of their own. Both armies fight together on one map, with enemies scaled to
the combined army. It reuses the reinforcement machinery (two players' units on one map), and it is
the most co-op answer, but the weakened player depends on a partner.

**Also on the table** from the earlier round:

- Shared XP still goes to a losing player's surviving units, so levels don't drift apart.
- Each player's copy of a map scales its enemy count to that player's army (the vision already
  aims standard combats at "a similar number to the player").
- No extra cost for a downed commander.

**Recommendation:** **S1 + S3**, with **S4** as an option for the weakened player, plus the three
points above. Permadeath stays intact: units that fall stay dead, and losing still costs rewards
and units. But a lost map never leaves a player with nothing: they are refilled to a playable
army, at full commander HP, and can choose to fight beside a teammate while they rebuild. **S2**
(ransom) is the alternative if permadeath in co-op should be softer.

## Questions any option raises

- **Commander death and losing a map:** see [When one player loses](#when-one-player-loses).
- **Gold and loot:** per player, shared, or split? (The save shape already holds one record per
  player.)
- **Enemy scaling** for shared fights: more enemies, stronger enemies, or both.
- **Turn timers:** whether shared phases need a timer so one slow player can't stall the others.
