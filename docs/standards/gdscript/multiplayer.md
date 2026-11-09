# GDScript standards: multiplayer

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans.

## 10. Multiplayer

- **Read `steam_multiplayer_kit/` first.** Before any networked change, read the relevant parts of
  the kit and follow its API for Steam and peer setup (`CLAUDE.md`, Multiplayer). The rules below
  still govern the code you write.
- **Gate all decision logic behind `is_multiplayer_authority()`.** Clients render; they don't decide.
- **Set authority identically on every peer** (`set_multiplayer_authority()`) before the node
  replicates; a mismatch drops or rejects updates.
- **Validate every `@rpc("any_peer")` handler on the receiver:** check
  `multiplayer.get_remote_sender_id()` is allowed to make that call, and range-check every
  argument. Never trust client input.
- **Throttle network updates independently of simulation.** Simulate at full rate on the authority;
  broadcast at 10–20 Hz; interpolate on the receiver so the low rate doesn't look choppy.
- **Randomize each instance's broadcast phase**, or every instance spawned in one batch sends on the
  same frame forever.
- **Batch.** Each RPC carries its own target, method and encoding overhead, multiplied by instance
  count. Send many instances' state through one replicator using Packed arrays.
- **Dirty-check before sending.** An idle object shouldn't broadcast an unchanged value forever.
- **`unreliable`** for continuously updated values; **`reliable`** for discrete one-off events. Getting
  this backwards either floods the channel or loses state permanently. Put high-rate traffic on its
  own `transfer_channel`.
- **Consider `MultiplayerSynchronizer`** (with its replication and delta intervals) before writing a
  hand-rolled replicator, and say why if you don't use it.
