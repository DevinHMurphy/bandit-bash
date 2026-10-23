# Brief: recovering from a lost map in co-op

> **Superseded October 20, 2026. Don't use this brief.** The decision it asks for has been made:
> there is no retreat or recovery mechanic, in solo or co-op. Permadeath applies to every unit (a
> rare revive event is the only way back), and the negative feedback loop is accepted. A fallen
> commander ends a solo run; in co-op it returns after the combat at critical health. See
> `docs/design/game-vision.md` and `docs/design/multiplayer-combat-options.md`.

I'm designing a co-op roguelite tactics game and need help working through one system. Everything
you need is below; you don't need any other files. Please read it all, then work through the
problem with me. At the end, give me the decision summary in the format under
[What I need back](#what-i-need-back).

## The game in brief

**Bandit Bash** (design document title: *Living Labyrinth*) is a roguelite tactics game: Fire
Emblem–style turn-based grid combat inside a Slay the Spire–style run.

- **A run** is one campaign map of 18 nodes: about 9 combats (5 standard, 3 key, 1 boss) and 9
  other nodes (Camps, Treasure, shops, random "?" events).
- **The army** is a small roster of individual units led by a **commander**. Typical size 3–6,
  hard maximum 10. Army size works like energy in Slay the Spire: more units means more actions
  per turn. It is never sold in shops; it comes from progression, heirlooms and the commander.
- **The whole army deploys in every combat.**
- **Permadeath:** units that fall in combat stay dead. They stay on the roster and can be revived
  at a Camp (one unit, at 30–40% HP; a Camp offers one choice from Feast, Train or Revive).
- **In solo, if the commander falls, the run is lost.**
- **Combats are short:** standard combats take 2–5 minutes on small maps (about 8×6 to 10×8 tiles)
  against 3–5 enemies, aiming for "a similar number to the player". Key combats are larger (about
  12×10) with a mini-boss; boss combats are larger still.
- **Recruits are cheap** (about 40 gold, when a run earns about 610 gold in total) so permadeath
  losses can be replaced, but only at a **Guildhall** shop node. A typical path passes through one
  Guildhall; it is not guaranteed to come before the next combat.
- **New recruits join at the army's average level**, rounded down.
- **Experience:** most XP is shared: when a combat ends, every deployed, surviving unit gets the same
  XP by combat type. A small capped personal bonus rewards actions; the unit with the most actions is
  the combat's MVP. A typical unit gains 4–6 levels a run.
- **Gold** comes mainly from combat, with grade bonuses (+25% for beating the map's turn par, +25%
  for losing no units).

## The darkness (turn-par pressure)

Every map has a **turn par**: beating it earns the +25% grade bonus. On maps with a par, the
**darkness** arrives at par. It matters here because it is what makes slow maps dangerous, and
slow maps are where players lose.

- **Arrival:** at turn par, darkness flows into the map from authored openings (hallways off the
  map, stairs, wells) toward a drain set by the objective (e.g. the boss, the seize tile, the far
  end of the map). Players who beat par never see it. Survive and Defend maps have none.
- **Waves:** a new wave pours out every few turns and creeps along paths. Each wave that crosses a
  tile deepens it: **Dusk → Gloom → Abyss**. The tiles near a source get deepest first, so the
  darkness comes from behind and pushes the army forward.
- **Damage:** only a unit that **ends its side's phase** on a dark tile takes damage; moving
  through is free. First pass: 10% / 25% / 50% of max HP for Dusk / Gloom / Abyss. The damage model
  is still to be playtested (it could become a stacking status, or flat damage that grows the
  longer a unit stays), and whether it counts as an attack (Block, Stance) is open.
- **No unit is immune**, bosses included. Enemies follow the same rules.
- **When it arrives,** enemies turn aggressive and enemy reinforcements stop.
- **It floods the whole map eventually,** so every map is guaranteed to end. But it never ends a
  map early: like fatigue in Hearthstone, both sides play against the clock, and outlasting it with
  sturdy, healing units can be a deliberate plan.
- **In co-op,** each parallel map gets the darkness at its own par, on its own turn counter. A
  player who wins before a teammate's par can reinforce them before it arrives: speed is rewarded.
  Each map's status (used to choose whom to reinforce) shows turns to par, or how much of the map
  is dark. Reinforcements land on dry tiles where possible. A map shared by two players has one
  darkness.

**Design pillars** (these should guide your answer):

1. Reduce player cognitive burden: fewer, clearer decisions.
2. Shorter runs: losses feel less punishing, so players take risks.
3. Reward proactive players: calculated, aggressive trades over slow, safe play.
4. Remove "hurry up and wait" moments.

## How co-op works (decided)

- **1–4 players**, fixed when a campaign starts. Each player has **their own army** and commander.
- The team travels **one shared campaign map**. Each player votes on the next node; the node is
  drawn at random weighted by votes.
- **Combat uses parallel maps:** each player fights their own copy of the same combat (same map,
  same seed, their own army) at the same time. The combat ends when every player has finished.
  Maps are authored once at solo size and keep their solo balance.
- **Later target (not MVP):** a hybrid where standard combats stay parallel but key and boss
  combats are one shared battle.
- **The host resolves everything**; clients send commands and replay results.
- Each player has their own combat MVP and their own rewards.

**Already decided for when players finish their maps differently:**

- **Reinforce:** a player who wins their map can send some of their surviving units onto a
  teammate's map that is still being fought. They arrive at the start of that map's next player
  phase, controlled by their owner, and can die there. With 3–4 players, the sender picks which
  map to help, guided by each map's status (turn, units left, enemies left) and any **call for
  aid** a struggling player has raised. All of a sender's units go to one map; several senders can
  help one map.
- **Retreat:** a player can retreat from their map before losing. Surviving units escape, and the
  player forfeits that combat's rewards.
- **The team wins the combat if anyone wins.** A player who lost their map gets no gold, XP or MVP
  for it, and their fallen units stay fallen.
- **Downed commanders (co-op only):** a commander that falls in co-op is downed, not killed. That
  player's map is lost, and the commander comes back after the combat. The run ends only if every
  player's commander falls in the same combat.

## The problem

A player who loses a map stays in the run, but usually most of their army has fallen, and
permadeath keeps it dead. The next node is often a combat, not a Guildhall, so they arrive with a
commander and one or two units, at the same difficulty as everyone else, and lose again. The strong
player carries; the weak player has no army and no impact. Solo never hits this, because a fallen
commander ends a solo run.

**The darkness sharpens this.** A struggling player is usually a slow one, so their map runs past
turn par and floods. They now lose units to the darkness as well as to enemies, and every turn they
hold on costs more. It also gives teammates a deadline: reinforcements are most useful before the
darkness arrives, and less so once the map is in Gloom or Abyss. On the other hand, retreating
before the Abyss becomes a natural way out.

The spiral has four links:

1. A lost map kills most of the army (to enemies and, past par, to the darkness).
2. Fallen units are gone for good.
3. Nothing refills the army before the next fight.
4. The weakened player fights alone at full difficulty.

## Options so far

Each strategy cuts a different link. These are starting points, not a closed list.

- **S1. Fall back.** When a player's commander is downed, their map ends at once and every
  surviving unit retreats with it. Losses stop the moment the map is lost. (This is the commander
  falling ending the map, not the darkness: the darkness itself never ends a map early.)
- **S2. Captured, not dead.** Units that fall on a *lost* map are captured. If the team wins the
  combat, they can be freed by paying a ransom at the next Guildhall (any teammate can pay), or
  later by a team "overflow" rescue skirmish once shared battles exist. They return wounded.
  Known oddity: a unit that falls on a map its player *wins* is still dead, so losing a map can
  look kinder than winning with casualties.
- **S3. Levies.** Before each combat, any player below an army floor (e.g. 3 units) gets temporary
  plain units at the army's average level to fill up to it. They leave after the combat unless the
  player buys one at a Guildhall. A downed commander returns at full HP.
- **S4. Join a teammate.** A player below the floor can deploy onto a teammate's map for the next
  combat instead of their own. Both armies fight together; enemies scale to the combined army. This
  reuses the reinforcement mechanism (two players' units on one map).

Also proposed:

- A losing player's surviving units still get the combat's shared XP, so levels don't drift apart.
- Each player's copy of a map scales its enemy count to that player's army.
- No extra penalty (gold, heirloom) for a downed commander.

**My current lean:** S1 + S3, with S4 as a choice for the weakened player, plus the three points
above. S2 is the alternative if co-op permadeath should be softer. I haven't committed.

## What I want to work through

1. **Is permadeath right for co-op at all**, or should co-op soften it in a consistent way
   (one rule that applies whether a map is won or lost)?
2. **What does losing a map cost?** It has to hurt enough that losing isn't a free choice, but
   never leave a player unable to play the next combat.
3. **What is the floor** a player is always rebuilt to, and what fills it (levies, a teammate's
   help, something else)?
4. **Exploits:** could a player lose on purpose to gain something (e.g. keep units alive via
   capture, get free levies)? Could a strong player farm anything from a weak one?
5. **Scenarios to test any proposal against:**
   - 2 players: one wins, one is wiped down to the commander; the next node is a combat.
   - 4 players: one player loses three combats in a row.
   - A player loses a map, the next node is a Camp: what do they choose?
   - Every player is struggling at once (no one can reinforce).
   - A slow player passes turn par; their map floods into Gloom while their teammate has already
     won. Is reinforcing into the darkness worth it, or should they retreat?
   - A player deliberately plays slow to let the darkness wear down a boss, while a teammate
     waits for the combat to end.
6. **The darkness:** does it change which options are best? For example, does it make retreat
   (and S1) more important, change what a fair floor is, or create a new exploit (a slow player
   stalling the team, or "losing" to the darkness to trigger recovery help)?
7. **Fit with the pillars**, especially "reduce cognitive burden" and "no hurry up and wait":
   what does the losing player do while others play, and how many new rules does the answer add?

Please challenge my lean if you think it's wrong, and suggest options I haven't listed.

## What I need back

When we're done, give me a summary in this format so I can paste it into my design docs:

```
## Decision: recovering from a lost map

Chosen strategies: <list>
Rejected (and why): <list>

Rules:
- <each rule, one line, precise enough to implement>

Values (first pass, to tune in playtesting):
- <each number and what it controls>

Open questions left:
- <anything still undecided>
```
