# Enemy Roster

The enemy classes in Bandit Bash. It expands the [Enemies](game-vision.md#enemies) section of
game-vision.md, which wins where the two differ.

**Status:** first pass, October 22, 2026. Stats are carried over from `Godot_FE/` as a starting
point and have not been rebalanced. Every number is to be tuned in playtesting.

## The short version

- **10 enemy classes** for the MVP's single act, in one working faction, the **Brigands** (a
  placeholder name; faction themes are flavor, decided later).
- Built on [Model 1](game-vision.md#enemy-unit-types): each class has stats and growths, a movement
  type, tags, Stance, a weapon (so every attack has a profile) and a trait in effect text, and
  fights by exactly the player's rules.
- Each class has an **AI behavior** that sets its intent icon and target rule.
- Classes are designed to be **fielded in packs**: a healer with a brute it keeps alive, a hexer
  that strips Stance for a cutthroat that crits, a shield wall in front of crossbows.
- Several traits are **side-agnostic** (they help or hurt whoever is in the right place), and the
  **AI is ruthless**: it chases kills and ignores friendly fire, so the player can turn enemy tools
  against them.
- **Elites** are ordinary classes plus a [prefix](unit-roster.md#prefixes) and, often, a signature
  move; they are not separate classes.

## Classes

Stats from `Godot_FE/resources/definitions/unit_types/units/<key>/`, mapped to the new stat list the
same way as the [player roster](unit-roster.md#mvp-roster): Might is the old Strength, or the old
Magic for casters.

| Class | Role | `Godot_FE` basis | Weapon (profile) | Movement | Tags | Stance | Base HP/MGT/SPD/DEF/RES/MOV/CON | Growths % HP/MGT/SPD/DEF/RES |
|-------|------|------------------|------------------|----------|------|--------|---------------------------------|------------------------------|
| Cutthroat | Striker | `cutthroat` | Simple Dagger (Nimble) | Mobile | — | 1 | 21/5/5/3/2/5/8 | 90/40/45/22/20 |
| Brute | Heavy hitter | `vandal` | Simple Axe (Power) | Default | — | 2 | 23/7/4/2/2/5/12 | 115/60/35/20/15 |
| Duelist | Counter-fighter | `corsair` | Simple Sword (Nimble) | Mobile | — | 2 | 16/4/9/3/1/5/5 | 75/30/50/15/20 |
| Crossbowman | Ranged | `crossbowman` | Heavy Crossbow (Power) | Default | — | 1 | 19/6/5/4/1/5/10 | 75/40/35/22/18 |
| Shieldbearer | Tank | `ward` | Simple Lance (Balance) + Iron Shield | Heavy | Armored | 3 | 25/2/2/7/1/5/14 | 70/25/28/45/10 |
| Hedge Healer | Healer | `healer` | Minor Heal staff (None) | Default | — | 1 | 12/8/5/1/7/5/5 | 50/40/30/8/35 |
| Hexer | Debuffer | `shaman` | Dark (Shade) (Power, Magic) | Default | — | 1 | 17/8/3/3/4/5/12 | 75/65/22/18/30 |
| Warcaller | Buffer | `sanctioner` | Simple Lance (Balance) | Default | — | 2 | 22/6/3/2/4/5/12 | 65/45/29/18/22 |
| Raider | Trampler | `axe_cavalier` | Javelin (Balance) | Mounted | Mounted | 2 | 21/6/4/5/1/7/12 | 85/40/27/25/10 |
| Hound | Pack beast | `flesh_prowler` | Fangs (Nimble) | Mobile | — | 1 | 20/4/6/1/0/7/10 | 70/30/45/5/8 |

Profiles are spread evenly across the triangle: Nimble 3, Balance 3, Power 3, None 1 (the healer,
whose staff never attacks).

## Traits, behavior and intent

| Class | Trait | AI behavior | Target rule (shown with its intent) |
|-------|-------|-------------|-------------------------------------|
| Cutthroat | **Backstab:** +2 damage against Exposed foes | Aggressive | Exposed foes first, then lowest HP. The only enemy that loots: with no attack worth taking, it opens a chest or searches a searchable to deny it, and drops what it took when defeated ([map-objects.md](map-objects.md#enemy-ai)) |
| Brute | **Cleave:** Hit dealt: every other unit adjacent to the Brute, friend or foe, takes 2 splash damage | Aggressive | Nearest foe it can hit; swings even with its own allies beside it |
| Duelist | **Riposte:** Before Combat, while it is the defender: gain 3 Block | Guard | Holds its ground; attacks only foes that come within reach |
| Crossbowman | **Steady Aim:** while it hasn't moved this turn: +10 Hit | Hold | Lowest Defense in range; moves only if nothing is in range |
| Shieldbearer | **Shield Wall:** Phase Start: every unit adjacent to it, friend or foe, gains 2 Block | Guard | Stays next to its pack's back-line ally |
| Hedge Healer | **Field Dressing:** Healed an ally: that ally gains 1 Stance | Support | Heals the most wounded ally; keeps away from your units |
| Hexer | **Curse:** Hit dealt: the target and every unit adjacent to it, friend or foe, lose 1 Stance | Skirmisher | The foe whose curse catches the most player units, even if allies are caught too |
| Warcaller | **War Horn** (signature move): every 2nd Phase Start this combat: every unit within 2 tiles, friend or foe, gains +2 damage until the end of the next phase | Support | Stays within 2 tiles of the most allies |
| Raider | **Trample:** while it moved 3+ tiles this turn, Hit dealt: every other unit adjacent to the target, friend or foe, takes 3 splash damage | Skirmisher | Any foe it can defeat this turn, splash included; otherwise back-line foes, whoever stands next to them |
| Hound | **Pack:** +2 damage per adjacent ally | Aggressive | Lowest HP; moves with its pack |

- The Warcaller is the one regular enemy with a signature move, telegraphed as its intent on the
  turn it will fire. Signature moves are otherwise for elites and mini-bosses.
- No trait uses status effects, matching the player's MVP traits.
- Debuffs work through Stance and Block, which already exist: the Hexer strips Stance so crits can
  land, and Exposed is the debuff.
- The Raider was reworked from "Hit and Run" (a copy of the player Freewing's Skirmisher) into a
  trampler whose charge splashes everyone near its target.

## Side-agnostic effects

Four enemy traits help or hurt **whoever is in the right place**, friend or foe (the
[Any Unit](effect-triggers.md#scopes) scope). The AI uses them at full strength regardless of who
else is caught, so a player who reads the board can turn them around:

| Trait | What the enemy wants | How the player outplays it |
|-------|----------------------|----------------------------|
| Brute's **Cleave** | Splash every unit around the Brute | Fight the Brute where its own allies stand next to it; they take the splash |
| Shieldbearer's **Shield Wall** | Block for its pack | Put your own units next to it: they get the Block too, then attack its neighbors |
| Hexer's **Curse** | Strip Stance from a clump of your units | Keep its allies next to your target, so the curse makes them Exposed for your crits |
| Warcaller's **War Horn** | +2 damage for its pack's charge | Step into range before it sounds: your units keep the bonus through your next phase |
| Raider's **Trample** | Splash around its target after a charge | Make it charge a target with its own allies beside it |

Every one of these is telegraphed: the intent shows which effect is coming, and the danger zone
shows splash and aura areas, so outplaying the AI is a matter of reading, not luck.

**Splash damage** is flat damage to everyone in an area. It isn't an attack: there is no hit roll,
no Mitigation and no crit, and it never costs Stance. Block absorbs it, so Shield Wall and other
Block protect against Cleave and Trample (see [effect-triggers.md](effect-triggers.md)).

## Ruthless AI

Enemies play to kill:

- **Kills first:** an enemy that can defeat a player unit this turn (with its attack, its splash, or
  both) does so, ahead of its behavior's normal target rule.
- **No fear of friendly fire:** collateral damage to its own side never stops an enemy. It will
  Cleave, Trample or Curse through its allies if that gets a kill or the best value.
- **No self-preservation tricks:** enemies don't hold back to protect each other's Block, Stance or
  auras; only the Hedge Healer keeps its distance, because that is its job.
- **Readable:** intents always reflect this. When a kill is available, the intent shows the kill
  target, so the player can see the threat coming and deny it.

## Enemy-only weapons

| Weapon | Dmg | AtkX | Profile | Range | Hit | Crit | CritX | Weight | Note |
|--------|-----|------|---------|-------|-----|------|-------|--------|------|
| Heavy Crossbow | 7 | 1 | Power | 2 | 85 | 0 | 3 | 10 | A bow: effective against Fliers, like every bow. Unlike player bows (profile None), heavy bolts are Power |
| Javelin | 5 | 1 | Balance | 1–2 | 75 | 0 | 3 | 10 | Thrown lance |
| Fangs | 3 | 2 | Nimble | 1 | 90 | 0 | 2 | 0 | Natural weapon, like gauntlets |

No `Godot_FE` basis; first-pass values sized against the simple weapons. The other classes carry the
player's simple weapons, so player knowledge transfers. Enemies don't drop loot in the MVP.

## Packs

Standard combats field 3–5 enemies. Classes are meant to appear in packs whose parts cover each
other:

| Pack | Units | How it works |
|------|-------|--------------|
| Shield and Bolt | Shieldbearer, 2 Crossbowmen | Shield Wall gives the crossbows Block; they stand still for Steady Aim |
| Hex and Knife | Hexer, 2 Cutthroats | The Hexer strips Stance; Cutthroats crit the Exposed target with Backstab |
| Field Hospital | Hedge Healer, Brute, Shieldbearer | The healer keeps the Brute fighting; the Shieldbearer guards the healer, and Shield Wall's Block protects the pack from the Brute's own Cleave |
| War Band | Warcaller, Brute, 2 Hounds | War Horn turns the pack's charge into a spike every other turn |
| Hunting Party | Raider, 2–3 Hounds | The Hounds swarm a target; the Raider charges in and Tramples it, Hounds and all |

The player's counterplay is built in: kill the healer or the Hexer first, break up a pack so Pack
and Shield Wall fall off, bait the Duelist with a unit that out-ranges it, and turn the
[side-agnostic effects](#side-agnostic-effects) against the pack that brought them. Packs that
cluster (War Band, Hunting Party) are the most exposed to their own Cleave and Trample.

## Elites

An elite is any class plus a prefix (rolled per [difficulty](game-vision.md#run-structure); on
Normal, elites and bosses only) and usually a signature move. A Defeat the Leader map's leader is
an elite. Examples, first pass:

- **Brigand Captain:** an elite Brute with "every 3rd Phase Start this combat: Command, every ally
  gains 1 Stance".
- **Bloodhound:** an elite Hound with "Defeated an enemy: may move again".

## Mini-bosses and the boss

Decided October 23, 2026. All are elites built on the classes above (Model 1): no new rules
engine, just a prefix, a signature move and a role.

**Mini-bosses.** Every key combat fields one, drawn from these four by the run's seed, never
repeating in a run. Four mini-bosses for 2–4 key combats is deliberate variety: each is a different
puzzle, to learn which are fun.

| Mini-boss | Built on | Signature move (telegraphed as its intent) | The puzzle |
|-----------|----------|---------------------------------------------|------------|
| Brigand Captain | Brute | Every 3rd Phase Start this combat: Command, every ally gains 1 Stance | Break its pack's Stance before Command restores it |
| Bloodhound | Hound | Defeated an enemy: may move again | Never leave a wounded unit in its reach |
| Hex Matron | Hexer | Every 3rd Phase Start this combat: Hex Storm, every unit within 2 tiles of its target, friend or foe, loses 1 Stance | Bait it into catching its own pack, then crit them |
| Iron Wall | Shieldbearer | Every 2nd Phase Start this combat: Fortify, adjacent units, friend or foe, gain 4 Block and +1 Parry until Phase End | Break the formation, or stand in the wall and share it |

**The boss: the Powder Baron.** The MVP's one boss. The boss map is fully scripted (fixed enemies, placement
and scripted beats), a developed level of 15–20 minutes; key maps field their step's standard count
+1 to +3 enemies plus the mini-boss.

- **Unit:** an elite Brute at level 8 with a +2 prefix and the **Unshovable** trait. It holds the
  throne (Guard behavior) and fights by every normal rule, Cleave included.
- **Signature, Keg Barrage:** every 2nd enemy phase, the Baron throws a powder keg onto a tile within
  5 tiles, shown as its intent one phase ahead. It picks the tile that would catch the most player
  units, whatever its own side loses (ruthless AI).
- **The kegs** are normal [Powder Kegs](map-objects.md#new-objects) (10 HP; 5 splash within 1 tile;
  they chain) with a lit fuse: each explodes at the end of the 2nd enemy phase after it lands, or
  sooner if anything hits it, splash or the darkness included. Either side can detonate one early.
- **How it changes the map:** the arena fills with hazards both sides can use. Throwing the
  Baron's own kegs back at its guards is the intended outplay.
- **The darkness:** the boss's tile is the drain. Once the throne floods, it stops healing the Baron
  and the darkness wears it down, so outlasting it is a valid, slow plan.
- **First pass:** the 2-phase cadence, 5-tile reach and 2-phase fuse are starting values to tune.

## Open questions

- **Faction:** the Brigands' real name and theme, and later factions.
- **Balance:** none of these stats have been tested against the new combat rules.
