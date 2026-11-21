# Effect Text

Every item, heirloom, curse, rune and prefix, with the effect text the game shows today. The game
builds this text from each effect's blocks (`EffectCarrierDefinition.describe()`), one sentence per
effect in the style of [effect-triggers.md](effect-triggers.md); an effect with
`EffectDefinition.written_text` shows that instead. Dumped from the catalog on November 21, 2026,
after TX1, by `tools/dump_effect_text.gd`, for the user's wording pass (RF-036).

**How to use it:** write your wording in the **New wording** column, leave it blank to keep the
current text, and add notes where a rule reads wrong. TX2 then makes the game show your wording,
as written text where the generator can't say it. Keep keywords (Block, Stance, HP, Gold and the
rest in `EffectTerms.KEYWORDS`) spelled and capitalized as they are: TX3 colours them and gives
each a tooltip. The intended rules are in [items.md](items.md) and [heirlooms.md](heirlooms.md);
where this text and those docs disagree, the docs say what the item should do.


## Weapon

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Abyss Typhoon | `abyss_typhoon` | +5 MGT. | |
| All-Seeing Hands | `all_seeing_hands` | *(no text)* | |
| Arming Sword | `arming_sword` | *(no text)* | |
| Armorbreaker | `armorbreaker` | *(no text)* | |
| Ash Spear | `ash_spear` | *(no text)* | |
| Bearded Axe | `bearded_axe` | *(no text)* | |
| Boar Spear | `boar_spear` | *(no text)* | |
| Brass Knuckles | `brass_knuckles` | *(no text)* | |
| Butcher's Knife | `butchers_knife` | *(no text)* | |
| Cestus | `cestus` | *(no text)* | |
| Colossus | `colossus` | +20 HP, +5 DEF and +5 CON. | |
| Dark Sword | `dark_sword` | Whenever this unit deals damage, heal for 50% of the damage dealt to HP. | |
| Deliverance | `deliverance` | *(no text)* | |
| Dragonslayer Bow | `dragonslayer_bow` | *(no text)* | |
| Earthsplitter | `earthsplitter` | *(no text)* | |
| Ebonflight | `ebonflight` | +5 SPD. | |
| Everbloom | `everbloom` | *(no text)* | |
| Everwall | `everwall` | *(no text)* | |
| Fangs | `fangs` | *(no text)* | |
| Far Ward | `far_ward` | *(no text)* | |
| Fiend Fire | `fiend_fire` | *(no text)* | |
| Gladius | `gladius` | *(no text)* | |
| Halberd | `halberd` | *(no text)* | |
| Hand Axe | `hand_axe` | *(no text)* | |
| Harm | `harm` | *(no text)* | |
| Headsman's Axe | `headsmans_axe` | *(no text)* | |
| Heartseeker | `heartseeker` | *(no text)* | |
| Heavy Lance | `heavy_lance` | *(no text)* | |
| Hunter's Bow | `hunters_bow` | *(no text)* | |
| Javelin | `javelin` | *(no text)* | |
| Kukri | `kukri` | Whenever this unit lands a crit, that hit skips Mitigation. | |
| Life Tap | `life_tap` | Whenever this unit lands a hit, that hit gains lifesteal. | |
| Lumen | `lumen` | *(no text)* | |
| Mage Blade | `mage_blade` | *(no text)* | |
| Mandate | `mandate` | *(no text)* | |
| Minor Heal | `minor_heal` | *(no text)* | |
| Ogre Knuckles | `ogre_knuckles` | *(no text)* | |
| Rampart | `rampart` | *(no text)* | |
| Rapier | `rapier` | *(no text)* | |
| Recover | `recover` | *(no text)* | |
| Recurve Bow | `recurve_bow` | *(no text)* | |
| Rondel | `rondel` | *(no text)* | |
| Ruin | `ruin` | *(no text)* | |
| Sabre | `sabre` | *(no text)* | |
| Sanctuary | `sanctuary` | *(no text)* | |
| Sanguis | `sanguis` | *(no text)* | |
| Shelter | `shelter` | *(no text)* | |
| Shieldmace | `shieldmace` | *(no text)* | |
| Short Bow | `short_bow` | *(no text)* | |
| Fire | `simple_anima` | *(no text)* | |
| Simple Axe | `simple_axe` | *(no text)* | |
| Simple Bow | `simple_bow` | *(no text)* | |
| Simple Dagger | `simple_dagger` | *(no text)* | |
| Shade | `simple_dark` | *(no text)* | |
| Simple Gauntlets | `simple_gauntlets` | *(no text)* | |
| Smite | `simple_holy` | *(no text)* | |
| Simple Lance | `simple_lance` | *(no text)* | |
| Simple Sword | `simple_sword` | *(no text)* | |
| Spear | `spear` | *(no text)* | |
| Starforged Blade | `starforged_blade` | *(no text)* | |
| Steppe Hornbow | `steppe_hornbow` | *(no text)* | |
| Stiletto | `stiletto` | *(no text)* | |
| Throwing Hatchet | `throwing_hatchet` | *(no text)* | |
| Titan's Will | `titans_will` | +17 HP, +5 MGT, +9 SPD, +4 DEF and +14 RES. | |
| Tomahawk | `tomahawk` | *(no text)* | |
| Torrent | `torrent` | *(no text)* | |
| Twin Fang | `twin_fang` | *(no text)* | |
| Whisperknife | `whisperknife` | *(no text)* | |
| Wind | `wind` | *(no text)* | |
| Woodsman's Axe | `woodsmans_axe` | *(no text)* | |
| Wyvern Pike | `wyvern_pike` | *(no text)* | |
| Zweihander | `zweihander` | +4 MGT and +2 SPD. | |

## Staff

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Everbloom | `everbloom` | *(no text)* | |
| Everwall | `everwall` | *(no text)* | |
| Far Ward | `far_ward` | *(no text)* | |
| Harm | `harm` | *(no text)* | |
| Minor Heal | `minor_heal` | *(no text)* | |
| Rampart | `rampart` | *(no text)* | |
| Recover | `recover` | *(no text)* | |
| Ruin | `ruin` | *(no text)* | |
| Sanctuary | `sanctuary` | *(no text)* | |
| Shelter | `shelter` | *(no text)* | |

## Equipment

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Buckler | `buckler` | +1 DEF and +1 RES. / Before each exchange, gain 1 Block. | |
| Enshrouding Sash | `enshrouding_sash` | +20 Avoid, +1 SPD and -1 DEF. | |
| Eye Shield | `eye_shield` | +4 HP, -3 SPD, +4 DEF, +2 RES and +1 Parry. | |
| Fancy Cloak | `fancy_cloak` | +6 HP. | |
| Iron Greatshield | `iron_greatshield` | +2 DEF and +1 max Stance. | |
| Iron Shield | `iron_shield` | +2 DEF. / Before each exchange, gain 1 Block. | |
| Knight Shield | `knight_shield` | +2 DEF and +2 RES. / Before each exchange, gain 1 Block. | |
| Magi Robes | `magi_robes` | +2 MGT and +1 RES. | |
| Old Soldier's Band | `old_soldiers_band` | +1 MGT, +1 DEF and +10 Hit. | |
| Power Band | `power_band` | +2 Attack. | |
| Quick Soles | `quick_soles` | +1 Movement. | |
| Short Quiver | `short_quiver` | While holding a bow, Range becomes 1-2. | |
| Silver Greatshield | `silver_greatshield` | +4 DEF, +1 RES and +1 max Stance. | |
| Silver Shield | `silver_shield` | +4 DEF. / Before each exchange, gain 2 Block. | |
| Simple Coating | `simple_coating` | While the opponent is Exposed, +2 Attack. | |
| Simple Quiver | `simple_quiver` | While at range 2 or more, +1 Attack. | |
| Spirit Coating | `spirit_coating` | Attacks deal Magic damage. | |
| Steel Greatshield | `steel_greatshield` | +3 DEF and +1 max Stance. | |
| Steel Shield | `steel_shield` | +3 DEF. / Before each exchange, gain 1 Block. | |
| Sunshard Band | `sunshard_band` | +4 HP. / At Phase End, heal for 10% of this unit's HP. | |
| Training Weights | `training_weights` | -2 SPD, SPD can't grow and +1 MGT per level-up. | |
| Tungsten Ooze | `tungsten_ooze` | +4 DEF and -1 Movement. | |
| Vitality Cloak | `vitality_cloak` | +4 HP. / At Phase Start, heal 1 HP. | |

## Trinket

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Band of Fortune | `band_of_fortune` | +5 Crit and +5 Hit. | |
| Cleansed Goblet | `cleansed_goblet` | +20% healing received. | |
| Family Ring | `family_ring` | +25% XP. | |
| Heavy Brick | `heavy_brick` | +2 CON. | |
| Jester Mask | `jester_mask` | Crits skip Mitigation. | |
| Knight's Token | `knights_token` | +1 MGT, +1 DEF and -1 SPD. | |
| Loaded Die | `loaded_die` | +30 Crit and -1 CritX. | |
| Lucky Coin | `lucky_coin` | +10 Crit. | |
| Mystifying Incense | `mystifying_incense` | +5 Avoid. | |
| Null Sigil | `null_sigil` | +1 max Stance. | |
| Oak Wood Charm | `oak_wood_charm` | +10 Avoid. | |
| Old Pendant | `old_pendant` | +1 RES. | |
| Resonant Ore | `resonant_ore` | -2 SPD and +1 random stat point per level-up. | |
| Ring of Favor | `ring_of_favor` | +2 HP, +1 DEF and +1 RES. | |
| Royal Crest | `royal_crest` | At least 3 stats raised per level-up. | |
| Scholar's Optics | `scholars_optics` | +10 Hit. | |
| Traveler's Ring | `travelers_ring` | +2 SPD and -1 DEF. | |

## Consumable

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Adept Anchovy | `adept_anchovy` | Permanently give the target +5 Hit. | |
| Ancient Anchor | `ancient_anchor` | Permanently give the target +2 RES. | |
| Bastion Crab | `bastion_crab` | When eaten, heal the target for 5 HP and permanently give the target +5% DEF growth. | |
| Boost Bread | `boost_bread` | Permanently give the target +1 MGT, +1 SPD, +1 DEF and +1 RES. | |
| Brawn Prawn | `brawn_prawn` | When eaten, heal the target for 10 HP and permanently give the target +10% MGT growth. | |
| Brutvine Heartroot | `brutvine_heartroot` | When eaten, heal the target for 10 HP and permanently give the target +10% MGT growth. | |
| Brutvine Sap | `brutvine_sap` | When eaten, heal the target for 5 HP and permanently give the target +5% MGT growth. | |
| Bull's Draught | `bulls_draught` | Permanently give the target +1 MGT. | |
| Cave Carrot | `cave_carrot` | When eaten, heal the target for 5 HP and permanently give the target +5% RES growth. | |
| Century Cheese | `century_cheese` | When eaten, heal the target for 10 HP and permanently give the target +10% HP growth. | |
| Elixir | `elixir` | Heal the target for HP equal to the target's HP. | |
| Emberglass Vial | `emberglass_vial` | Heal the target for 12 HP. | |
| Finesse Filet | `finesse_filet` | When eaten, heal the target for 10 HP and permanently give the target +5 Hit. | |
| Giant's Brew | `giants_brew` | Permanently give the target +2 MGT. | |
| Godseed Oil | `godseed_oil` | Permanently give the target +7 HP. | |
| Guard Tonic | `guard_tonic` | Give the target 6 Block. | |
| Guard Tonic+ | `guard_tonic_plus` | Give the target 10 Block. | |
| Hastehawk Feather | `hastehawk_feather` | When eaten, heal the target for 10 HP and permanently give the target +10% SPD growth. | |
| Hawkweed | `hawkweed` | When eaten, heal the target for 5 HP and permanently give the target +3 Hit. | |
| Heartbeet | `heartbeet` | When eaten, heal the target for 5 HP and permanently give the target +5% HP growth. | |
| Infused Obsidian | `infused_obsidian` | Permanently give the target +1 DEF. | |
| Key | `key` | Open a chest or door. | |
| Large Potion | `large_potion` | Heal the target for 8 HP. | |
| Large Potion+ | `large_potion_plus` | Heal the target for 12 HP. | |
| Lockpick | `lockpick` | Open a chest or door. Lock pickers only. | |
| Martial Scroll | `martial_scroll` | Permanently give the target +10 Hit. | |
| Moonclam Pearl | `moonclam_pearl` | When eaten, heal the target for 10 HP and permanently give the target +10% MGT growth. | |
| Potion | `potion` | Heal the target for 8 HP. | |
| Potion+ | `potion_plus` | Heal the target for 12 HP. | |
| Precise Pepper | `precise_pepper` | When eaten, heal the target for 5 HP and permanently give the target +3 Hit. | |
| Runewart | `runewart` | When eaten, heal the target for 5 HP and permanently give the target +5% MGT growth. | |
| Rushraddish | `rushraddish` | When eaten, heal the target for 5 HP and permanently give the target +5% SPD growth. | |
| Sanctree Branch | `sanctree_branch` | When eaten, heal the target for 10 HP and permanently give the target +10% RES growth. | |
| Sanctuary Shell | `sanctuary_shell` | When eaten, heal the target for 5 HP and permanently give the target +5% RES growth. | |
| Soul Dust | `soul_dust` | Permanently give the target +2 MGT. | |
| Spirit Ink | `spirit_ink` | Permanently give the target +1 MGT. | |
| Stonebark Blossom | `stonebark_blossom` | When eaten, heal the target for 5 HP and permanently give the target +5% DEF growth. | |
| Stonebark Essence | `stonebark_essence` | When eaten, heal the target for 10 HP and permanently give the target +10% DEF growth. | |
| Stonedragon Tail | `stonedragon_tail` | Permanently give the target +2 DEF. | |
| Swift Shellfish | `swift_shellfish` | When eaten, heal the target for 10 HP and permanently give the target +10% SPD growth. | |
| Tempo Tonic | `tempo_tonic` | Permanently give the target +1 SPD. | |
| Titan Trout | `titan_trout` | When eaten, heal the target for 10 HP and permanently give the target +10% HP growth. | |
| Vermillion Tonic | `vermillion_tonic` | Permanently give the target +3 HP. | |
| Warding Worm | `warding_worm` | Permanently give the target +1 RES. | |
| Wisdom Wine | `wisdom_wine` | When eaten, heal the target for 5 HP and permanently give the target +5% MGT growth. | |
| Wyvern Wingdust | `wyvern_wingdust` | Permanently give the target +2 SPD. | |

## Heirloom

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Abundance | `abundance` | +1 max army size. / At the start of the run, recruit 1 of 2 units with no prefix. | |
| Ancestral Mail | `ancestral_mail` | +1 max Stance. | |
| Ancestral Weapon | `ancestral_weapon` | At the start of the run, take 1 of 3 Rare weapons the army can use. | |
| Bloodhound's Collar | `bloodhounds_collar` | Whenever one of your units defeats an enemy, that unit may move after acting until Phase End. | |
| Bloodied Banner | `bloodied_banner` | Whenever one of your units defeats an enemy, give that unit +3 Attack on its next attack this combat. | |
| Bounty Ledger | `bounty_ledger` | +8 Gold per won combat. | |
| Breaker's Maul | `breakers_maul` | Every 5th time one of your units lands a hit each combat, the target loses 1 extra Stance. | |
| Brittle Guard | `brittle_guard` | Whenever one of your units gains Block, -1 to that Block gain. | |
| Brothers in Arms | `brothers_in_arms` | At each allied Phase Start, give every ally adjacent to a unit of another player 2 Block. | |
| Burglar's Roll | `burglars_roll` | Once per combat, one of your units can open a chest or door without a Key or Lockpick (still its action). | |
| Champion's Belt | `champions_belt` | Whenever one of your units defeats an enemy, give that unit +1 Attack this combat. | |
| Clouded Sight | `clouded_sight` | Enemy intents are hidden. | |
| Commander's Standard | `commanders_standard` | At Phase Start, give your commander and allies within 2 tiles of your commander 2 Block. | |
| Cursed Blood | `cursed_blood` | ×0.5 healing received. | |
| Drillmaster's Baton | `drillmasters_baton` | While holding a Balance weapon, +1 Attack and +1 DEF. | |
| Dueling Manual | `dueling_manual` | While holding a Nimble weapon, +2 Attack Speed. | |
| Executioner's Brand | `executioners_brand` | While the opponent is Exposed, +3 Attack. | |
| Family Relic | `family_relic` | At the start of the run, gain a random Uncommon heirloom. | |
| Fletcher's Kit | `fletchers_kit` | While at range 2 or more, +1 Attack. | |
| Gilded Purse | `gilded_purse` | +25% grade bonus. | |
| Grandfather's Whetstone | `grandfathers_whetstone` | While holding a Power weapon, +2 Attack. | |
| Grave Candle | `grave_candle` | Whenever one of your units is defeated, give your units 4 Block. | |
| Guild Charter | `guild_charter` | +1 Guildhall recruit. | |
| Hammerhead Charm | `hammerhead_charm` | Against Armored units, +3 Attack. | |
| Haunted | `haunted` | At Phase Start, a random one of your units can't gain Block until the end of the next phase. | |
| Heavy Pack | `heavy_pack` | +2 weight per Pouch item. | |
| Horsebane Charm | `horsebane_charm` | Against Mounted units, +3 Attack. | |
| Hunted | `hunted` | +1 enemy per combat. | |
| Hunter's Horn | `hunters_horn` | Whenever one of your units enters an exchange, while it is the initiator, give that unit +5 Hit this exchange. | |
| Ill Omen | `ill_omen` | While it is the commander, -1 max Stance. | |
| Iron Heart | `iron_heart` | Every 7th time one of your units attacks each combat, that attack gains lifesteal. | |
| Iron Rations | `iron_rations` | At the first Phase Start each combat, give your units 3 Block. | |
| Lantern Oil | `lantern_oil` | Whenever one of your units takes darkness damage, ×0.5 to that darkness damage. | |
| Leaden Boots | `leaden_boots` | -1 SPD. | |
| Membership Seal | `membership_seal` | -20% shop prices. | |
| Mercenary Contract | `mercenary_contract` | At the start of the run, recruit 1 of 3 units with a +1 or +2 prefix, replacing a unit (not the commander). | |
| Merchant's Ledger | `merchants_ledger` | +1 Armory item. | |
| Muster Roll | `muster_roll` | +1 max army size. | |
| Overflowing Cup | `overflowing_cup` | Whenever one of your units is healed, give that unit Block equal to 100% of that overheal. | |
| Sapper's Fuse | `sappers_fuse` | Whenever one of your units uses an object, give that unit 3 Block. | |
| Scrapper's Tongs | `scrappers_tongs` | +20% of the price when scrapping. | |
| Shaken Footing | `shaken_footing` | At the first Phase Start each combat, remove 1 Stance from your units. | |
| Short Wick | `short_wick` | -1 turn before the darkness arrives. | |
| Shoving Pole | `shoving_pole` | Whenever one of your units shoves a unit, give that unit 2 Block. | |
| Tactical Map | `tactical_map` | At the first Phase Start each combat, give your units +1 Movement until Phase End. | |
| Tactician's Manual | `tacticians_manual` | +1 Attack × its triangle damage change and +1 Hit × its triangle Hit change. | |
| Tinker's Token | `tinkers_token` | +1 free reroll. | |
| Veteran Company | `veteran_company` | At the start of the run, upgrade one unit (not the commander) for free. | |
| Veteran's Medal | `veterans_medal` | +20% shared XP. | |
| War Chest | `war_chest` | At the start of the run, gain 100 Gold. | |
| War Ledger | `war_ledger` | Every 10th time one of your units attacks this run, ×2 damage for that attack. | |
| Warhorse Lineage | `warhorse_lineage` | +1 Movement. | |
| Warlord's Spoils | `warlords_spoils` | Whenever one of your units defeats an enemy, heal that unit for 3 HP. | |

## Curse

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Brittle Guard | `brittle_guard` | Whenever one of your units gains Block, -1 to that Block gain. | |
| Clouded Sight | `clouded_sight` | Enemy intents are hidden. | |
| Cursed Blood | `cursed_blood` | ×0.5 healing received. | |
| Haunted | `haunted` | At Phase Start, a random one of your units can't gain Block until the end of the next phase. | |
| Heavy Pack | `heavy_pack` | +2 weight per Pouch item. | |
| Hunted | `hunted` | +1 enemy per combat. | |
| Ill Omen | `ill_omen` | While it is the commander, -1 max Stance. | |
| Leaden Boots | `leaden_boots` | -1 SPD. | |
| Shaken Footing | `shaken_footing` | At the first Phase Start each combat, remove 1 Stance from your units. | |
| Short Wick | `short_wick` | -1 turn before the darkness arrives. | |

## Rune

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Aegis | `aegis` | Give an ally 6 Block. | |
| Clarity | `clarity` | Give an ally +20 Hit and +2 Attack on its next attack until Phase End. | |
| Haste | `haste` | Give an ally that hasn't acted +2 Movement until Phase End. | |
| Mend | `mend` | Heal an ally for 10 HP. | |
| Recall | `recall` | Two of your units swap positions. | |
| Shatter | `shatter` | Remove 2 Stance from an enemy. | |
| Spark | `spark` | A powder keg anywhere on the map explodes. | |

## Weapon prefix

| Name | Id | Text now | New wording |
|------|----|----------|-------------|

## Unit prefix

| Name | Id | Text now | New wording |
|------|----|----------|-------------|
| Feeble | `feeble` | *(no text)* | |
| Frail | `frail` | *(no text)* | |
| Hasty | `hasty` | *(no text)* | |
| Heroic | `heroic` | *(no text)* | |
| Keen | `keen` | *(no text)* | |
| Mighty | `mighty` | *(no text)* | |
| Reckless | `reckless` | *(no text)* | |
| Sluggish | `sluggish` | *(no text)* | |
| Stalwart | `stalwart` | *(no text)* | |
| Sturdy | `sturdy` | *(no text)* | |
| Swift | `swift` | *(no text)* | |
| Warded | `warded` | *(no text)* | |
