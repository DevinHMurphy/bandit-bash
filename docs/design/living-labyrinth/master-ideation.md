> **Frozen source document, kept verbatim.** Exported from the Living Labyrinth Master Ideation
> Document (Google Docs, April–May 2026). Only the embedded images were changed: they are now files
> in `images/`. [`../game-vision.md`](../game-vision.md) is the master design document and wins
> wherever the two differ. Read it first; use this file for detail and intent.

# Living Labyrinth Master Ideation Document

**Version:** April 2026   
**Created On:** April 2026   
**Updated On :** May 2026

1. # **Overview**

This document outlines the systems, data architecture, and gameplay features of Living Labyrinth. It is to be used as an overview and grounding document for future design decisions and gameplay direction.

1. ## **Theme/Setting/Genre**

   2. **Core Gameplay Mechanics**  
   3. **Game Description**  
   4. **Influences**

2. **Gameplay**  
   1. **Overview**  
   2. **Game Flow**  
   3. **Campaigns**  
      1. **Difficulty**  
      2. **Settings**  
      3. **Map**  
   4. **Commander Selection**  
   5. **Army Selection**  
   6. **Battle Preparation**  
   7. **Combat Exchange**

3. # **Units**

   1. **Overview**  
   2. **Unit Types**

      1. ### **Statistics**

      2. **Inventory**  
      3. **Experience & Leveling**  
      4. **Promotions & Tiers**  
   3. **Player Army**  
      1. **Commanders**  
         1. **Overview**  
         2. **Examples**  
      2. **Regular Units**  
         1. **Overview**  
         2. **Examples**  
   4. **Enemy Units**  
      1. **Overview**  
      2. **Bosses**  
         

4. # **Items**

   1. **Item Types Overview**  
   2. **Usable Items**  
      1. **Overview**  
      2. **Examples**  
   3. **Held Items**  
      1. **Overview**  
      2. **Examples**  
   4. **Weapons**  
      1. **Overview**  
      2. **Weapon Type Table**  
      3. **Examples**

5. # **Combat**

   1. **Overview**  
   2. **Calculations**  
      1. **Damage**  
      2. **Block**  
      3. **Attack Speed**  
   3. **Statuses**

      

6. # **Meta Progression**

   1. **Overview**  
   2. **Unlock Methods**  
   3. **Unlockables**  
      1. **Units**  
      2. **Items**  
      3. **Campaigns**

   

   

   

   

   

   

   

   

   

   

7. # **Game Flow**

The Game Flow begins when the player selects start from the home screen

1. ## **Game Flow Priorities**

Gameplay Goal : The goal of the game is to create an experience that allows the user to make in 

Thesis Pillars

| Pillar | Rational |
| :---- | :---- |
| Reduce Player Cognitive Burden | Feedback received from playtesters indicated that the wealth of options, flexibility, and information provided to the player actually caused mental strain.  |
| Decrease Run Speed | Reducing run speed for roguelite games will make outcomes feel less punishing and allow players to take more risks, without fears of losing hours of progress. |
| Incentivize Proactive Players | Turn based strategy games systems can lead the player to playing slow and “boring” \-- not taking risks or controlling space on the map. We want players who make calculated proactive moves trading resources and being rewarded. Players should think, I can trade xyz for this position because it will be beneficial in the long run and allow my unit to succeed. |
| Remove “Hurry up and wait” tactical decisions |  |

2. ## **Commander Selection**

The player must select which faction they are taking on the campaign.   
![][image1]

Before embarking on a campaign the player must select their initial campaign army, spearheaded by a **commander**. An initial campaign army consists of a commander unit and a few generic starter units. 

The Faction guides the player to faction locked Heirlooms, weapons, and unit types. Each commander has a unique faction aligned relic that benefits the player and helps to shape gameplay outcomes. **Commander Heirlooms** should lead to unique gameplay experiences and synergize with faction units and heirlooms. Commanders and factions dictate base army size.

**Commander Unit**  
\*\*The commander’s unit type → “Bash” good, and a place to build from, shouldn't be cut but not run winning  
\*\* Starting units \*\* → Strikes and Defends → Simple, and Bad, waiting to be replaced but fills a role  
\*\* Starting equipment \*\* → Strikes and Defends → Bad and should always be replaced for more value

| Faction | Unit Type | Max Army Size | Funds | Starting Army |
| :---- | :---- | :---- | :---- | :---- |
| Mercenary | Drengr | 6 | 1000 G | Hakkapel, Archer, Battle Medic |
| Mage Tower | Mage Knight | 4 | 2500G | Tower guard,  |

Commander Army 

Neutral Units

*Example Hierlooms, balance and effects are not final*

| Commander Heirloom | Faction | Commander | Effect |
| :---- | :---- | :---- | :---- |
| Iron Heart | RED | Drengr | Every 7th attack gains lifesteal |
| Iron Blood | RED | Horse Unit | After defeating an enemy gain 4 armor |
| Seeking Kunai | GREEN | Viper | Every dodge increases crit chance by 1%, resets on critical hit. |

3. ## **Starting Heirloom**

![][image2]  
*Design Mock for Starting Heirloom Selection \<PLACEHOLDER\>*  
After the player selects their faction and commander they select a starting heirloom, starting heirlooms can only be received at the start for the run and provide variation to runs without forcing a particular build. 

| Starting Heirloom | Gameplay Outcome |
| :---- | :---- |
| Abundance | Give the player \+ 1 army size, add two common unit picks. |
| Ancestral Weapon | Give the player starts with a rare weapon selection. |
| Tactician’s XYZ | Double the effect of the weapon profile triangle |

![][image3]

4. ## **Army Overview**

![][image4]  
![][image5]

8. # **Campaign**

   1. ## **Map Structure & Node generation**

   2. ## **Node Types**

      1. ### **Combat Map**

         1. #### **Standard Combat (skirimish)**

A standard combat should take the player 2-5 minutes maximum. These maps should contain a few enemies (3-5, always below 10 aiming for a similar number to the player) and stay simple. They should not have “boss units” and can have some simple rewards.  
![][image6]  
*A simple map from FE heroes*  
One of the main rewards for combat is the experience they provide. Also, combat maps provide the player with rewards. Rewards can be 

2. #### **Key Combat**

Key combats are normal small scale fire emblem style maps. These should have simple interactions and have mini-boss units. The target playtime of one of these maps should be 5-10 minutes. The player should do about 2-4 these maximum runs. On completing a key combat the player is rewarded with a heirloom.

3. #### **Boss Combat** 

A large-scale combat map with a boss unit that directly affects the combat map.

2. ### **Shop**

The shop node is a safe encounter with a couple different variations. In the shop players can spend accumulated gold to buy weapons, equipment, trinkets, runes, and new units to help strengthen their army. 

At the shop the player can buy upgrades to army size and sell items from their convoy.

3. ### **Event**

The event node, represented by a question mark on the map, triggers a random narrative encounter presenting players with choice driven tradeoffs. These choices often offer powerful rewards such as heirlooms, upgrading units, gold, weapons and unique units. Often in exchange for taking damage, acquiring curses, or risking surprise combat encounters.

4. ### **Camp**

The camp provides the user with multiple options and a place to recover the ground during their campaign. Players should weigh the effect of camping nodes and training vs resting. Unless heirlooms give camps more value they should not be the main node a player paths to. The player should hit 2-4 rest nodes per 18-node run with a maximum possibility of 5 if they are the main focus.

| Choice | Effect |
| :---- | :---- |
| **Rest** | Heal the party 35% of each unit’s HP |
| **Train** | Upgrade a unit. Unless specified units can only be upgraded once.  |
| **Revive** | Resurrect one fallen unit at 30-40% HP (only available if someone is dead) |

5. ### **Treasure**

The treasure node is a guaranteed non-combat room that awards the player a free chest containing a relic to boost their run. Depending on the size of the chest, it yields a relic of varying rarity and occasionally includes bonus gold or extra loot. The minimum number of treasure nodes per run is constant at 2(3?).

3. ## **Acts and Gameplay scaling**

In v0 we are targeting one Act, or campaign map for the player to traverse.

9. # **Army**

The player's army is a roster of distinct individual units, each possessing unique weapons, equipment, inventories, stats, and character profiles. Rather than generic troops, players command these individual characters on turn-based grid maps, leveling them up through combat while risking their permanent loss under classic permadeath settings. The player’s army is fronted by a commander, the commander falling in battle prompts an instant loss. Commander stat spreads and names are constant and persist across runs whilst all other non event units are randomized.

Maximum army size is a vital component as more units give the player more actions per turn and more storage (Think of army size as a mixture between card draw and mana inside a game like slay the spire). Maximum army size is limited by progression, heirlooms, and starting commander. The maximum size of the player’s army is 10 but on average the player’s army will range from 3-6 units. The player's entire army is deployed in every combat and combat 

## **Army Additions & Replacements**

Throughout a campaign the player will have the ability to recruit new units to their army. If a newly recruited unit would put the army size over its maximum that unit instead has to replace an existing army unit. Replaced unit’s inventories are sent to the convoy. 

## **Death & Resurrection**

On death units do not leave the army list however they cannot be used in combat. Deceased units keep their inventories items that can be taken from them in the army management and preparation screen.

10. # **Units**

    1. ## **Types**

A unit type is a class of unit that defines a unit’s mobility, weapon access, and combat role on the battlefield. Unit types

1. ### **Characteristics**

   2. ### **Movement Types**

      3. ### **Traits**

   2. ## **Stats**

      1. ### **Attack Speed (AS)**

**Attack Speed** is a vital combat statistic, it dictates the number of combat turns a unit can have during a combat exchange.

**Attack Speed Formula** A Unit's attack speed is calculated as follows

Calculate the net weight of the unit’s equipment

${Unit}_{NetWeight}\ ={\ }$${WeaponMainHand}_{Weight\ }+\ {{WeaponOffHand}_{Weight}}_{}+\ {Effect}_{Weight}$  
Unit Attack speed formula  
${Unit}_{AttackSpeed}\ =\ {Unit}_{Speed\ }-\ max(0,\ ({Unit}_{NetWeight}\ -\ {Unit}_{Constitution}{\ }$))

**Design Note:** Speed should be a marker of a unit’s maximum speed when not weighed down, units should have large cons that dictate their equipment load and builds. Speed penalties will increase with severity the more overloaded a unit is.

3. ## **Tiers**

   4. ## **Promotions**

   5. ## **Experience & Leveling**

Keeping the excitement of a great level up, and the relationship a player gains from training a unit is vital. However, preventing funneling and 1 beats all gameplay is more important. 

This poses a vital question: how do you keep leveling balanced, fun but keep unit stat spreads expectable, and all player units on level?

1. Ensure no cheerleader units

   Often units that have niche uses, low movement, or support units that lack function. These units take less actions, get less kills and therefore fall behind. If the player is pressed to use all the units at their disposal, experience distribution will be more even.

2. Give rewards for non-combat activities. Looting houses, closing reinforcement routes,   
3. Create experience decay, to stop the player from farming reinforcements and boss units.

${Unit}_{Value}=\ {UnitTier}_{Value}+\ {Unit}_{Level}$ 

$UnitValueDifference\ =\ {EnemyUnit}_{Value}-\ {PlayerUnit}_{Value}$

${Experience}_{Hit}=\ clamp(BaseHitValue\ +\ HitConstant\ \times \ tanh(\frac{UnitValueDifference}{HitSpreadConstant}),\ 1,\ 25)$

${Experience}_{Defeated}=\ clamp(BaseDefeatValue\ +\ DefeatConstant\ \times \ tanh(\frac{UnitValueDifference}{DefeatSpreadConstant}),\ 2,\ 100)$

## **Inventory**

| Slot | Function |
| :---- | :---- |
| **Main-Hand** | Main weapon or tool a unit has equipped. |
| **Equipment** | Passive stat bonuses and utility, this can only be changed by using a full action in combat. It should realistically be configured in army management & unit prep. |
| **Pouch** | A single slot for consumable items, or very minor buffing items. Limits potion spam. |
| **Stash** | Reserve Main-Hand, or equipment items. The Limit can be expanded by heirlooms and unit type traits, by default it is 2 slots (back & hip). |

# **Weapons**

## **Weapon Overview**

Weapons and Equipment are items that units use to perform combat exchanges and turn the tides in battle.

The overall weapon data model can be overwhelming, to make it more digestible its been divided into sections for this document.

### **1.1.1  Weapon Equippability Data Architecture Overview**

The first of which is equipability data. These fields indicate what units can use the weapon, and where it can be equipped. 

| Attribute | Description |
| :---- | :---- |
| Weapon Type | Dictates units can equip the weapon  |

### **1.1.2  Weapon Combat Exchange Data Architecture Overview**

| Attribute | Description |
| :---- | :---- |
| Hit | Base hit chance of the weapon, added to units hit in combat calculations |
| Profile | Dictates the weapon profile triangle |
| Damage | The weapon's base damage |
| Damage Type | What defense does this weapon target |
| Scaling Type | What stats does this weapon benefit from |
| Scaling Modifier | At what multiplier does this weapon benefit from the unit's stat targeted in the scaling type |
| Critical Chance | Base critical hit chance of the weapon, added to units critical in combat calculations |
| Critical Multiplier (CritX) | The multiplier used when a critical hit is scored to calculate total attack damage |
| Combat Exchange Turn Attacks (AtkX) | How many times the weapon will strike during a units combat exchange turn |
| Weight | The weight of the weapon, used in calculating a unit's attack speed. Weight is used as a soft cap for what weapons a unit can and should use. |
| Weapon Effectiveness Trait | Does the weapon do effective damage against a particular unit trait? |
| Weapon Effectiveness Weapon Type | Does the weapon do effective damage against a particular weapon type? |
| Weapon Effectiveness Weapon Profile | Does the weapon do effective damage against a particular weapon profile? |

#### **Weapon Attack**

### **1.1.3 Weapon Targeting Data Architecture Overview**

**Weapon Targeting Data** 

| Attribute | Description |
| :---- | :---- |
| Attack Range | The range in tiles the weapon can attack. |
| Item Target Faction | Does the weapon target allies, enemies, or can it target anyone. |

### **1.1.4 Weapon Block Data Architecture Overview**

| Attribute | Description |
| :---- | :---- |
| End of Turn Block | Block added when the unit’s turn ends |
| Before Combat Exchange Block | Block added before combat exchange |
| Beginning of Turn Block | Block added at the beginning of a unit’s turn |
| Bonus Block | Additive bonus to whenever block is generated |

### **1.1.5 Weapon Skills Data Architecture Overview**

| Attribute | Description |
| :---- | :---- |
| Charges | The amount of times a weapon/tool’s special ability can be used (healing on staff etc.) |
| Skill | The skills attached to the Weapon/Tool. |

### **1.2 Weapon Profiles**

Weapon Profiles should align with the theme and flavor of a weapon. Swords are typically nimble weapons however  
*Example (Sword):* 

- *A Zweihander is a power weapon*  
- *A Long Sword is a nimble weapon*  
- *A Claymore is balanced*

### **1.4 Weapon Types**

#### **1.4.1 Swords**

Sword is a primary combat weapon built for the philosophy of control. It sacrifices peak damage for a predictable, low-variance exchange — a weapon for units that want to know how a fight ends before it starts.

**Simple Sword (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 5 | 1 | Versatile | Nimble | 1 | 80 | 0 | 3 | 8 |

**Gameplay Takeaways**

* **Role:** An intelligent Frontline trader. The sword's high hit and consistency leads it to low variance. Its low base damage and weight values encourage sword users to pick battles with profile advantages to fully maximize their speed advantage and potential extra combat turns.  
* **Strengths:** High hit rate means damage output is consistent and predictable — ideal for scenarios where a miss would be punishing. Low weight and Pre-Combat Block provides consistent defensive value in every situation.  
* **Weaknesses:** Poor base damage means swords often lose out on 1:1 trades when having the speed advantage doubling. Their multi-hit approach often becomes fruitless against defense specialists.  
* **Matchups:** Excels against high-evasion targets where other weapons might lose trades to miss rates. The Versatile equip tag opens pairing with an Off Hand item, making build flexibility the sword's secondary strength. Is poor against units with high defense or expect to trade hits directly.  
* **Differentiator:** Engagement consistency. Swords often don’t miss the mark and thanks to 2RN they rarely subvert expectations. 

#### **1.4.2 Axes**

The axe is a primary combat weapon that demands commitment.  Built around a Power profile and the highest base damage in the melee roster, axes reward aggressive play and punish passivity. A low hit rate means swings will go wide, but when the axe connects the damage dealt is among the highest available to physical attackers. Heavy weight is the second tax, constraining the builds that can carry an axe effectively. The axe exists for players who are willing to accept volatility in exchange for the threat of overwhelming force.

**Simple Axe (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 10 | 1 | Versatile | Power | 1 | 65 | 0 | 3 | 15 |

**Gameplay Takeaways**

* **Role:** Aggressive frontliner and high-value target removal. The axe belongs to units built to absorb the cost of a miss — those with the bulk, positioning, or movement to get out of a pinch.  
* **Strengths:** Base damage output is class-leading at melee range, making successful hits disproportionately impactful. When a large hit lands on a target with low defense the tides of battle can be turned instantly. Turn Start block timing provides defensive coverage before the action phase opens, giving axe users a defensive buffer going into high-risk trades.  
* **Weaknesses:** A low hit rate is the axe's defining liability. Missed attacks compound across a campaign, affecting survivability, and kill threshold reliability, and forcing contingency plans. High weight places meaningful constraints on unit builds and often limits axe units from attacking multiple times.  
* **Matchups:** Most effective against low-evasion, high-HP targets where the hit rate disadvantage is minimized and the damage premium is fully realized. Pairs well with support that improves accuracy or suppresses enemy evasion. Struggles against fast or evasive units where the miss rate becomes a consistent drain. Targets units who are defeated after the first engaging attack, you don’t have to dodge or block if there is nothing left that can attack back.  
* **Differentiator:** Consequence. The axe is the only melee weapon that actively punishes overcommitment — a miss isn't just lost damage, its potential exposure. That tension is the axe's mechanical identity, and it makes every swing a deliberate decision rather than a routine one.

#### **1.4.3 Lances**

Lances are balanced primary combat physical weapons. They are solid without excelling in any particular area. Their slightly above average weight, solid hit rates, substantial damage make Lances effective in all situations. 

**Simple Lance (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 7 | 1 | Main Hand | Balanced | 1 | 80 | 0 | 3 | 12 |

#### **1.4.4 Bows & Marksman Weapons**

Primary combat physical weapons focused solely on doing damage from afar and not about self preservation, these often come with little defensive upside and versatility, but reward the player for good positioning by packing a punch.

**Simple Bow (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 6 | 1 | TwoHanded | None | 2-3 | 100 | 0 | 3 | 5 |

#### **1.4.5 Hand to Hand**

Hand to hand weapons focus on speed and overwhelming number of attacks to expose their foe and destroy stance. With a multitude of precise and rapid strikes, with low base damage. Their low critX shows they are less about defeating enemies who are already exposed and more focused on initiating combat themselves.

**Simple Gauntlets (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 2 | 2 | Versatile | None | 1 | 100 | 0 | 2 | 1 |

#### **1.4.6 Daggers**

Daggers are hybrid support and damage weapons. Their critical damage bonus allows them to capitalize on exposed enemies. Dagger’s low stat totals mean they are often out performed by weapons with less versatility.  
**Simple Dagger (Main Hand)**

| Dmg | Atk X | EquipType | Profile | Range | Hit | Crit | Crit X | Weight |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 2 | 1 | Two | Any | 1-2 | 100 | 0 | 5 | 3 |

#### **1.4.7 Dark Magic**

#### **1.4.8 Anima Magic**

#### **1.4.9 Holy Magic**

#### **1.4.10 Support Weapons**

Whips, instruments, banners, staves 

#### **1.4.10 Misc. Weapons**

### **1.4 Weapon Durability**

Some weapons have per map durability; this is a balancing function for powerful tools like \- heal stalves, and more. It challenges the player to face a prioritization of resources instead of planning for a single optimal setup and outcome.  
pass

# **Equipment**

Equipment in your game are **high‑impact, build‑defining items** that can dramatically shape a unit’s combat role, ranging from offensive enhancers like magic‑infused quivers to defensive options like shields that bolster stance and resilience. Each unit can equip only one piece at a time, and its **weight contributes to attack speed**, making equipment choice a strategic commitment that cannot be changed mid‑combat. 

## **Quivers**

Quivers are equipment that only aid units striking from range. Specializing on attack rather quivers provide no defensive bonus fir 

## **Coatings**

Coating focuses on providing bonuses against exposed enemies and adding debuffs to weapons attacks. Often lightweight and providing small bonuses, coatings are perfect for fast multi-attacking units with low constitution.  

## **Shields**

Shields are defensive pieces of equipment that provide the user with stance and block.

## **Armor**

## **Cloaks**

## **Bands**

## **Uniques**

# **Pouch Items**

## **Consumables**

Consumables are **pouch items** that units can carry and activate to restore HP, cure status effects, boost stats, illuminate fog, or unlock doors and chests. They typically have **limited uses** and are expended upon activation, making them essential tactical resources for survival and utility in battle 

## **Trinkets**

Trinkets are **pouch items** that grant small, often situational bonuses and occupy the pouch slot, meaning only one can normally be held at a time, and a unit with a trinket cannot carry a consumable. The bonuses provided by trinkets only affect the holder. They are generally **less powerful and more subtle** than equipment, but can meaningfully influence a run through effects like improved drop rates, stat tweaks, or special interactions. 

# **Combat**

## **Combat Exchange**

A combat exchange is what takes place when a unit targets another unit with the combat action. Combat exchanges are the core combat gameplay interaction. The combat exchange action immediately if either unit participating is defeated. 

A combat exchange is broken up into turns.Turn order is typically as follows: the initiator gets the first turn and the defender gets the second. With any other turns calculated from AS being compounded on the end. 

| Combat Exchange |  |  |
| ----- | :---- | :---- |
| Turn Owner | Initiator | Defender |

When a unit has excess attack speed when compared to another unit in a combat exchange the faster unit may get multiple turns. The formula for combat turns is as follows:

With extra turns being added to the end of the flows:

$\ {AttackSpeedDifference(ASDiff)}_{}\ =\ {Initiator}_{AS}-\ {Defender}_{AS}$  
$ExtraTurnConstant\ =\ 4$  
$BonusTurns$ \=

| Combat Exchange |  |  |  |
| ----- | :---- | :---- | :---- |
| Turn Owner | Initiator | Defender | …. |

### **Combat Exchange Turn**

The combat exchange turn is when a unit attempts to attack another unit. A combat exchange turn can a  
Combat Exchange Attack(s)  
$\ {Attacker}_{AtkX}\ \ =\ {Weapon}_{AtkX}+\ {Equipment}_{AtkX}+\ {Heirloom}_{AtkX}\ +\ \ {Status}_{AtkX}{\ }$  
${Turn}_{AttackCount}=\ {Attacker}_{AtkX}\ -{Attacker}_{Mitigation}{\ }$   
1\. Calculate Damage  
2\. Roll for hit if it is a hit continue  
3\. Crit Check — only rolls if defender's Stance \== 0 entering this hit   
4\. Apply Block to incoming damage  
5\. Reduce HP by remaining incoming damage   
6\.  0, defender's Stance is reduced by 1

### **Damage**

${Attack}_{Damage}=\ {Attacker}_{Attack}\ -\ \ {Defender}_{Mitigation}{\ }$ 

### **Attack**

Attack is the maximum outgoing damage a unit does per combat exchange turn in a combat turn.  
The base attack formula for a unit is below: 

${Unit}_{Attack}\ ={Weapon}_{Attack}+\ {Weapon}_{ScalingModifier}({Unit}_{TargetStat})\ \ +\ {Status}_{AttackBonus}\ +\ {Equipment}_{Attack}$ 

#### **Effective Attacks**

Specific attacks are considered effective, this is often when an attacking unit’s weapon is super effective against a defending unit. 

$BaseEffectiveModifier$ \= 3

$EffectiveModifier\ =\ BaseEffectiveModifier\ +\ {Status}_{EffectiveBonus}+\ {Equipment}_{EffectiveBonus\ }+\ {Heirloom}_{EffectiveBonus}$ 

${Unit}_{EffectiveAttack}\ ={(EffectiveModifier*Weapon}_{Attack})+\ {(Weapon}_{ScalingModifier}{*\ Unit}_{TargetStat})\ \ +\ {Status}_{AttackBonus}\ +\ {Equipment}_{Attack}$ 

### **Mitigation**

During combat a unit mitigates incoming damage via stats and equipment. Mitigated damage is based on the incoming damage type. If the incoming damage is pure no mitigation will ever take place.

| Incoming Damage Type | Mitigation Source |
| :---- | :---- |
| Physical | Defense |
| Magic | Resistance |
| Split | ½ (Defense \+ Resistance) |
| Pure | None |

${Unit}_{Mitigation}\ ={Weapon}_{MitigationSource}+\ {Unit}_{MitigationSource}\ \ +\ {Status}_{MitigationSource}\ +\ {Equipment}_{MitigationSource}$

## **Block**

**The Goal**: Block allows the player more flexibility in tactics, builds, and compositions. Block gives the player more of a buffer allowing them to trade health as a resource more comfortably and reduces the pain of mistakes. Block is a key resource in the larger game flow, it allows mistakes to compound and removes the need to heal player units between combats.

Block is a resource that mitigates a unit’s damage taken. Block absorbs damage before a unit's health is reduced. Block expires at the beginning of the unit’s next player phase. Block from multiple sources compound additively.

### **Block Phases**

**Block is typically generated at three different phases:**

| Timing | Trigger | How Block Mirrors a Stat |
| :---- | :---- | :---- |
| Beginning of Turn | Player Phase starts | Temp HP |
| End of Turn | Player Turn ends | Temp HP |
| Before Combat | Combat Exchange initiates, before damage | Temp Def |
| After Combat | Combat Exchange resolves, after damage | Conditional Defense |

Beginning of Turn \- Prioritizes trades and gives player agency to make moves & trades on player turn

Before Combat Exchange \- the most valuable time to generate block as it always gets value

After Combat Exchange \- Defensive survive enemy turn \--\> attack with defensive stance, or for units that poke \--\> aggressive plays with squishy units is rewarded

## **Stance, Exposure, & Critical Hits**

Stance is a unit's resistance to being caught in an exposed state and hit by a critical strike. The goal of stance is twofold to protect the player from frustrating RNG based critical strikes destroying runs and to incentivize attacking. 

Stance is a counter, a small integer value stored on each unit representing hits-of-margin before Exposure. When a unit’s stance reaches zero, they become **exposed**. A unit that is not Exposed cannot be critically struck, regardless of the attacker's equipment or bonuses. 

Stance only decrements on hits that clear DEF/RES for real damage either to a units block or hp pool. A fully-countered attack (net damage 0\) costs the defender nothing on either axis for a simple reason : why would a unit become exposed if they are impervious to the strike? This also lets high defense tanks maintain their speciality of defeating high volume attacking low damage foes.

Stance refreshes at the beginning phase of every player’s turn. 

When a unit is **exposed** they are able to be hit by a critical strike. A critical strike multiplies an attack by CritX damage.

In combat a unit’s critical strike chance is calculated

${Attack}_{Critical}=\ {ExposureConstant}_{Value}+\ {Equipment}_{Critical}+\ {Status}_{Critical}{\ }$ 

${Equipment}_{Critical}=\ {Weapon}_{Critical}+\ {Offhand}_{Critical}{\ }$ 

${Status}_{Critical}=\ {Rune}_{Critical}+\ {StatusEffect}_{Critical}+\ {UnitTrait}_{Critical}\ \ {\ }$ 

Where the $ExposureConstant$ is an arbitrary value and equals 25\.

## **Weapon Profile Triangle (WPT)**

There exist **three** weapon profiles:  **Nimble**, **Balance** and **Power**. See weapon profile in section XXX

When units enter combat exchanges the weapon profile triangle can have three outcomes : **Advantage**, **Disadvantage**, and **Standoff**

|  |  | Friendly Profile |  |  |
| ----- | ----- | ----- | :---- | :---- |
|  |  | **Nimble**  | **Balance**  | **Power**  |
| Enemy Profile | **Nimble**  | Standoff | **Advantage** | Disadvantage |
|  | **Balance**  | Disadvantage | Standoff | **Advantage** |
|  | **Power**  | **Advantage** | Disadvantage | Standoff |

*Table outcomes oriented for friendly unit*

**Weapon Profile Triangle Attack Effect (WPTAE)** is the value added to attack damage in the case of advantage or subtracted in the case of disadvantage. WPTAE is rounded to the closest integer and is calculated directly from the weapon’s damage.

Some parameters need to be defined before calculating the WPTAE**.** The first is the **WPT scaling constant**, this is the scaling modifier applied to a weapon when it is affected by the WPT.  
${WPT}_{ScalingRatioConstant}\ \ \ ={\ }$${\frac{1}{4}}_{}$   
The **WPT soft cap** sets a maximum value to the damage modifier created by the WPT. It is estimated by using the damage stat on the most powerful weapons and estimating the effect of the scaling ratio.  
${WPT}_{Minimum}\ =\ 1$  
${WPT}_{SoftCap}\ \approx \ 10$   
${WPT}_{SoftCap}\ ={\ }$${WeaponConstants}_{DamageMaximum}\ \times \ {WPT}_{ScalingRatio}$ 

$WPTAE\ \ ={\ }$${{WPT}_{ScalingRatio}\ \ \times \ Weapon}_{Attack}\ \ \ \ \ \ \ \ where,\ WPTAE\ \ {≥\ \ WPT}_{Minimum}{\ }$${\ }$  

| Outcome | Total Attack | Hit |
| :---- | :---- | :---- |
| Standoff | 0 | 0 |
| Advantage | ${Weapon}_{Damage}+\ WPTAE$ | \+15 Hit |
| Disadvantage | ${Weapon}_{Damage}-\ WPTAE$ | \-15 Hit |

### 

## **Status Effects \*\*WIP**

Status Effects are temporary conditions that units get during combat and effect Combat, Movement, Unit Statistics, Growths and more.   
Status effects can stack in three different ways, duration, effect weight, and both. 

| Effect | Total Attack | Hit |
| :---- | :---- | :---- |
| Bleed | Effect weight | When bleed stacks are applied to a unit, it compounds and is cleansed after the unit takes bleed damage at the end of the turn. |
| Garrison | Duration | Garrison allows a unit to preserve its block after ending its turn. If a unit gains another stack of garrison those stacks combine and at the end of the unit’s turn it will lose one stack of garrison and no block. Effectively the power of garrison doesn’t increase but its duration does. |
| Poison (Slay the spire example) | Both | Poison stacking compounds, at the end each turn the poisoned unit takes x (stacks) of damage and a single stack is removed effectively reducing duration. |

## **Terrain**

## **Interactables**

## **Objectives**

# **Runes**

**Runes** are single use abilities that affect units and the combat map and are available to the player during the player turn.

Runes do not partake in the action economy. Runes have their own inventory slots and are not unit dependent. Units and heirlooms can generate Runes.

### **8.1 Obtaining Runes**

Can be purchased at shops Can be obtained from rewards Can be obtained from rune generating relics Can be obtained from rune generating Units

**Gameplay Takeaways**

* **Availability:** Runes should not be so rare the player does not use them. They are a resource just like other pieces of the gameplay loop. The player  
* **Effectiveness :** Runes should give the player the upper hand in a combat but should not single handedly carry a combat. When used to align with a unit’s synergies they should really shine. The player should not have to use runes to overcome combat and challenges, combats should be designed around the player not having a rune in effect.  
* **Design:** Fun and exciting a player should be rewarded for using runes intelligently and be excited to come up with creative solutions for them to be used most effectively in combat.

# **Convoy**

Shared storage for weapons and items not currently equipped

- **Size: 1 slot per max army size**   
- Items in convoy can be sold at shops  
- Loot decisions happen at pickup  
- small convoy prevents hoarding and deferred optimization

Temporary space is added to the convoy when a unit is removed from the active army.

# **Hierlooms**

- **Army-wide passives**, not per-unit  
- One shared collection, no assignment or shuffling  
- Cap at 8-12 relics by end of run  
- Acquisition rate: roughly 1 per 2-3 nodes (6-9 per run)

**Some Relic Examples**

| Type | Examples | Purpose |
| :---- | :---- | :---- |
| **Profile** | "Power weapons deal \+2 damage" | Reward committing to a profile identity |
| **Behavior** | "Units that defeat an enemy gain \+3 damage next attack" | Reward a playstyle |
| **Economy** | "Shops offer one additional item", "+1 potion capacity" | Modify run structure |

[image1]: images/commander-selection-sketch.png
[image2]: images/starting-heirloom-mock.png
[image3]: images/ref-loot-reward-screen.png
[image4]: images/ref-deck-overview-screen.png
[image5]: images/ref-roster-screen.png
[image6]: images/ref-fe-heroes-map.png
