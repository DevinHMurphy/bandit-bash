# P13 decisions: RNG streams

The answered questions of [the plan](../2026-10-26-rng-streams.md), moved here unchanged on November 9, 2026. Numbers are stable: code and plans cite them. To read one question: `grep -n "^| 34 |" P13-rng-streams.md`.

## Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | Who owns the streams | Plain object owned by the run / a new `Rng` autoload | Plain object | **Answered October 26, 2026:** a plain `RngStreams` object held by `CampaignSession` and handed down; its save sections are registered by whichever autoload owns `CampaignSession` (P08 question 1). No new autoload. |
| 2 | How values are derived | Keyed per node, running within / running named streams / one stream | Keyed per node | **Answered:** every node and combat gets streams seeded from a **key** (run seed, purpose, floor, node, seat, index), not from earlier draws; inside one node a stream runs normally. |
| 3 | Co-op layout | Shared world, personal rewards / everything per player | Shared world | **Answered:** the world is shared; every reward and every random outcome for a player rolls per seat (see [Co-op layout](../2026-10-26-rng-streams.md#co-op-layout)). In a shared event, each player's random reward is their own. |
| 3b | Chest and house loot on parallel map copies | Per player / shared | Per player | **Answered:** per player. Same chest, same tile, different contents per seat. |
| 4 | Run seed | Random, shown, debug entry / random hidden / player-entered | Random, shown, debug entry | **Answered:** random at run start; shown on the pause and results screens and in repro dumps; typing a seed is a debug option in the MVP. |
| 5 | Generator and derivation | Godot RNG + own key hash / own generator too | Godot RNG + own hash | **Answered:** Godot's `RandomNumberGenerator` (PCG32) per stream; keyed seeds from our own SplitMix64 mixer, never `hash()`; golden tests pin both. |
| 6 | Determinism across game updates | Same build only / pinned across updates | Same build only | **Answered:** guaranteed within one build. After an update that changes content, future rolls in a resumed run may differ; past results are never rerolled. |

No open questions remain.

