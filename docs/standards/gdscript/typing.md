# GDScript standards: typing and banned syntax

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans.

## 4. Typing

**Every declaration carries an explicit type.** Godot's inference is literal: it silently locks in
`int` where you meant `float`, and it infers `Node` where you meant your class.

```gdscript
# ❌ Inferred int. A later `speed = 1.5` truncates to 1 with only a warning.
var speed := 1

# ❌ Inferred int. `timer += delta` truncates back to 0 every frame.
var timer := 0

# ❌ Integer division. The annotation doesn't help: this is 0.0, not 0.5.
var half: float = 1 / 2

# ❌ Inferred Node, not UnitToken.
var token := TOKEN_SCENE.instantiate()

# ❌ Parse error: min() returns Variant, so there is no type to infer.
var step := min(speed * delta, dist)

# ✅
var speed: float = 1.0
var timer: float = 0.0
var half: float = 1.0 / 2.0
var token: UnitToken = TOKEN_SCENE.instantiate()
var step: float = minf(speed * delta, dist)
```

Rules:

- **Write `: Type` on every `var`, `const`, parameter and return**, including `-> void`. Type loop
  variables over untyped collections: `for token: UnitToken in nearby:`.
- **Avoid `:=`.** Use it only when the static type can't be written by name at that point. When you
  do, add a short comment saying why.
- **A value that can legitimately hold more than one type is declared `: Variant`**, with a comment
  listing the allowed types. `:=` can't express this: it locks the variable to the type of the first
  value, or fails to compile when that value has no static type.
- **Float literals always carry a decimal point:** `1.0`, `0.0`, `15.0` — never `1`, `0`, `15`, even
  as an `@export` default.
- **Division:** at least one operand must be a float when you want a fractional result. An
  annotation on the result doesn't change integer division.
- **Use the typed math functions.** `min`, `max`, `clamp`, `lerp`, `abs`, `sign`, `round`, `floor`
  and `ceil` take and return `Variant`.
  - Floats: `minf`, `maxf`, `clampf`, `lerpf`, `absf`, `signf`, `roundf`, `floorf`, `ceilf`, `snappedf`.
  - Ints: `mini`, `maxi`, `clampi`, `absi`, `signi`, `roundi`, `floori`, `ceili`, `snappedi`.
  - The Variant versions are only for vectors and other non-scalar types.
- **Type collections:** `Array[Node3D]`, `Dictionary[int, UnitToken]`, and `Packed*Array` for bulk
  numerics. Typed collections can't nest (`Array[Array[int]]` is invalid); use an inner class or a
  Packed array as the element.
- **Downcasts:** prefer a typed declaration (`var token: UnitToken = node`), which errors loudly on a
  mismatch. `node as UnitToken` silently returns `null` on a mismatch; if you use `as`, null-check the
  result on the next line. Cast once into a typed local rather than repeating `as`.
- **Overrides of typed-return methods** need an explicit `return` on every path (4.7).
- **Spacing:** `var name: Type` — one space after the colon, none before.

**Expected project warning settings** (Project Settings → Debug → GDScript): `untyped_declaration`,
`unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`, `integer_division` and
`narrowing_conversion` set to **Error**. If `project.godot` doesn't have them, tell the user once;
don't change `project.godot` without asking.

Before finishing, re-read new code for numeric declarations and division and confirm each is
correct. This is the most common source of errors in this project.

---

## 5. Godot 3 syntax is banned

Never write Godot 3 syntax. The common traps:

| Godot 3 (never) | Godot 4 |
|-----------------|---------|
| `onready var`, `export var`, `tool` | `@onready var`, `@export var`, `@tool` |
| `yield(obj, "signal")` | `await obj.signal` |
| `connect("sig", self, "_method")` | `sig.connect(_method)` |
| `emit_signal("sig", a)` | `sig.emit(a)` |
| `var x setget set_x, get_x` | `var x: int:` with `set(value):` / `get:` blocks |
| `scene.instance()` | `scene.instantiate()` |
| `Spatial`, `KinematicBody`, `KinematicBody2D` | `Node3D`, `CharacterBody3D`, `CharacterBody2D` |
| `move_and_slide(velocity, Vector3.UP)` | set `velocity` and `up_direction`, then `move_and_slide()` |
| `PoolVector3Array`, `PoolStringArray` | `PackedVector3Array`, `PackedStringArray` |
| `rand_range()`, `deg2rad()`, `stepify()` | `randf_range()`, `deg_to_rad()`, `snappedf()` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `funcref(obj, "m")` | `obj.m` (a `Callable`) |
| `master`, `puppet`, `remote` keywords | `@rpc(...)` annotation |

If you're unsure whether an API is Godot 3 or 4, check the 4.7 class reference before writing it.
