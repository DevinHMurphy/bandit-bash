# GDScript standards: performance and measuring

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans.

## 9. Performance

Ordered by how often each dominates a profile. Assume **many instances of the same script run
concurrently**, so per-instance costs multiply.

### 9.1 Per-frame cost × instance count

Anything in `_process` / `_physics_process` runs instances × frames per second.

- **Prefer manager loops over per-node callbacks.** 200 nodes each with `_physics_process` is 200
  script calls per frame; one manager iterating an array is one. Turn off unused callbacks with
  `set_process(false)` / `set_physics_process(false)`.
- **Stagger expensive work across frames.** Assign each instance a bucket at spawn and do heavy work
  every Nth frame. Assign buckets from an explicit counter; instance IDs aren't evenly distributed
  modulo N.
- **Never build strings you might not use.** `_log.debug("x=%s" % [value])` formats before the call
  whatever the log level. Gate on a level check first. Don't name a variable `log`: it shadows the
  built-in `log()` function.
- **Guard property writes that trigger work.** Many engine setters have no equality check and queue
  a redraw or server update on every assignment: `if sprite.flip_h != v: sprite.flip_h = v`.

### 9.2 Physics

- **Don't query outward for a small, known set.** An `intersect_shape` sphere per instance per tick
  to find a handful of objects is backwards. Keep a registry (§8.3) and compare with
  `distance_squared_to()`. Query cost grows with the number of candidates inside the volume.
- `intersect_shape()` returns a fresh `Array[Dictionary]`; `intersect_ray()` returns a fresh
  `Dictionary`. Reusing the query parameters doesn't avoid the result allocation.
- `intersect_shape(query, max_results)` silently truncates at `max_results` (default 32). If
  unrelated bodies share the mask, real targets get dropped. Keep collision layers narrow.
- Reuse `PhysicsShapeQueryParameters3D` / `PhysicsRayQueryParameters3D`: build once, then change
  `transform` or `from`/`to` per call.
- On an `Area3D`, `monitoring = false` stops it detecting others; `monitorable = false` stops other
  areas detecting it. Turn off whichever direction nothing uses.
- **Jolt specifics** (when §1 confirms Jolt): collision margins shrink shapes and can produce odd
  normals in shape queries, which matters for small colliders; ray results report `face_index = -1`
  unless enabled in project settings. Prefer resizing shapes over scaling nodes.

### 9.3 Allocation

- No `Object.new()`, Array or Dictionary construction in hot paths. Hoist to `_ready()` or pool.
  Value types (`Vector3`, `Transform3D`) are fine.
- Call `duplicate()` before mutating a shape or material shared across scene instances — Godot shares
  sub-resources by default, so an in-place change affects every instance. For editor-assigned
  resources, `resource_local_to_scene = true` does this without code. `duplicate()` is shallow by
  default; nested sub-resources stay shared.
- Each evaluation of a lambda creates a new `Callable`. Don't create them inside loops.
- `Packed*Array` types avoid per-element Variant boxing. Use them for bulk numeric data, especially
  over the network.
- `await` allocates coroutine state. Fine for setup, not for per-frame logic.

### 9.4 Lookups and dispatch

- `has_method("name")` and `call("name")` are string lookups. Cache the `has_method` result (it only
  changes if the script changes), or hold a `Callable`.
- Typed code compiles to faster typed instructions; untyped variables force dynamic dispatch (§4).
- No `get_node()` per frame: cache in `@onready` with an explicit type. Use `^"Path"` NodePath and
  `&"name"` StringName literals to avoid runtime conversion.
- `Array.has()` is O(n); `Dictionary.has()` is O(1). With frequent lookups in more than about 20
  elements, use a Dictionary. A recursive tree search is fine at small N — say so in a comment, and
  add a registry when N grows.

### 9.5 Scene tree and rendering

- Writing a node's transform marks every descendant dirty and notifies those that listen, including
  physics bodies and areas. Don't write a transform whose only consumer is a distance check; compute
  the point arithmetically.
- Node count is itself a cost. Prefer a baked composite over a multi-node assembly.
- `MultiMeshInstance3D` for large numbers of identical visuals.
- `queue_free()` + re-instantiate in a loop is churn. Pool anything spawned more than a few times per
  second.
- Visibility and processing are independent. `visible = false` stops drawing but scripts still run;
  `set_process(false)` affects one node only. To freeze a whole subtree, set
  `process_mode = Node.PROCESS_MODE_DISABLED` on its root (children inherit it). To fully idle a
  subtree, hide it **and** disable it.

### 9.6 Misc

- Vector types are valid Dictionary keys; never `dict[str(vec)]`. For grid coordinates use
  `Vector2i`/`Vector3i`: float keys need exact equality.
- Iterate with `for item in array` or `for i in count`; both evaluate the size once. In a `while`
  loop, cache `array.size()` if the array doesn't change.
- Build strings with `PackedStringArray` and `", ".join(parts)`, not `+=` in a loop.

---

## 11. Measuring

Never claim a speedup you didn't measure.

- Claude Code can't drive the editor profiler. Measure with a **headless benchmark scene** under
  `bandit-bash/tests/bench/`. It spawns a fixed, seeded workload, records `Time.get_ticks_usec()`
  around the code under test (or reads `Performance.get_monitor()`), prints the median and 95th
  percentile, and quits:
  `godot --headless --path bandit-bash res://tests/bench/<name>.tscn --quit-after <frames>`
- If no benchmark exists for the system, ask before creating one (`CLAUDE.md` §1).
- Measure before and after, one change at a time, on the same machine, and report both numbers.
- If you can't measure, label the improvement **unmeasured** in the summary.
