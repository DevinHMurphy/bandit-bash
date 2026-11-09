---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "bandit-bash/project.godot"
---

# GDScript Standards — Bandit Bash, Godot 4.7.1

The rules for every script, scene and resource in `bandit-bash/`. Workflow rules are in `CLAUDE.md`. New code follows this guide even where the surrounding file doesn't. `Godot_FE/` and `steam_multiplayer_kit/` are read-only references that predate it: never copy their code or style.

**Read the detail only when the task needs it.** Section numbers match the citations in code and plans.

| Doing this | Read, in `docs/standards/gdscript/` |
|---|---|
| Writing `@export`s, setters, markers, state or input blocks, long comments (§3) | `documentation.md` |
| Edge cases of the engine notes, file order, header or formatting (§1, §2, §8) | `basics.md` |
| Unsure about a type rule or a Godot 3 name (§4, §5) | `typing.md` |
| A rename, or a scene or `.uid` change beyond a property value (§6, §7) | `names-and-scenes.md` |
| Per-frame code, allocation, or a performance claim (§9, §11) | `performance.md` |
| Anything networked (§10) | `multiplayer.md` |

## 1. Engine

Godot **4.7.1**. If a signature or default matters, check the 4.7 class reference, and say so if you couldn't. Mouse and keyboard events report `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD`: never test `event.device == 0`.

## 2. File layout

**Where files go:** a UI element's `.tscn` and `.gd` sit side by side in `ui/<feature>/`. Game logic with no scene is in `scripts/<system>/`. Content is in `data/`. Tests mirror the code in `tests/`.

**Order in a file:** header · `@tool`/`@icon` · `class_name` · `extends` · class doc · input map block · signals · enums (state block above the state enum) · constants and preloads · static vars · `@export`s · public vars · private vars · `@onready` · virtual callbacks (`_init`, `_enter_tree`, `_ready`, `_exit_tree`, `_input`, `_unhandled_input`, `_process`, `_physics_process`, `_notification`, others) · public methods · private methods and `_on_*` handlers · static methods (`_static_init` first) · inner classes.

**Every `.gd` starts with:**

```gdscript
# ==============================================================================
# Bandit Bash
# Copyright (c) [Year] Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     [file_name].gd
# Author:
# Created:  [Month Day, Year]
# Modified: [Month Day, Year]
# ==============================================================================
```

`Author:` stays blank. `[Year]` is the creation year. Dates come from `date "+%B %-d, %Y"`. Update `Modified:` on every edit, except a pure file move. For a header added later, `Created:` is the date git first saw the file, or `[unknown]`.

The class doc follows `extends` directly, with no blank line.

## 3. Documentation

- A `##` doc sits directly above its member or the member's annotations, with no gap, or Godot won't attach it. Use `[br]` for line breaks and `[ClassName]`, `[member x]`, `[method x]` for links.
- **Every `@export` is documented** for someone tuning it without the code: units, and what 0 and 1 mean. Use `@export_range` when bounds are known. Setters guard with `if not is_node_ready(): return`, and `_ready()` applies the value.
- **Say what the code does now and why.** Keep invariants, cross-file coupling, what breaks if it changes, and why the obvious alternative was rejected. Present tense.
- **Don't write:** dates, past versions, which step or refactor made a change, restatements of the next line, or plan and question numbers ("question 34"). State the rule itself. One `@tutorial` link to the plan or design doc is fine.
- **Budget:** member 4 lines, function 8, class 12 (excluding `@todo` lines). Longer rationale goes in `docs/design/`.
- **Existing comments:** bring a member's docs to budget when you change that member. Leave everything else alone.
- **Markers:** `TODO`, `FIXME` and `HACK` carry a per-file ID with a matching class-doc line: `# TODO(TOD-004): ...` and `## @todo: TOD-004 - ...`. `NOTE` needs no ID. `# ASSUMPTION:` is per `CLAUDE.md` §1. Report every marker you add or meet.
- **Required blocks:** a state machine overview above any state enum, and an input map overview below the class doc of any script reading input actions. Update them in the same edit as the behaviour; check bindings against `project.godot`. See `documentation.md` §3.8.

## 4. Typing

- **Explicit types on every `var`, `const`, parameter and return,** including `-> void` and loop variables over untyped collections.
- Avoid `:=`; use it only when the type can't be named, with a comment saying why.
- Float literals have a decimal point. Division needs a float operand for a fractional result.
- Use `minf`/`mini`, `maxf`/`maxi`, `clampf`/`clampi`, `lerpf`, `absf`/`absi`, and the like, not the Variant versions.
- Type collections: `Array[Node2D]`, `Dictionary[int, Unit]`. They can't nest.
- Prefer a typed declaration to `as`; if you use `as`, null-check on the next line.

Re-read new numeric declarations and divisions before finishing: this is the most common error here.

## 5. No Godot 3 syntax

`@onready`, `@export`, `await`, `signal.connect(callable)`, `signal.emit()`, `instantiate()`, `Node2D`, `Packed*Array`, `Time.get_ticks_msec()`, `@rpc`. The full table is in `typing.md`.

## 6. Names and renames

`snake_case` files, functions and variables · `PascalCase` classes, nodes and enums · `SCREAMING_SNAKE_CASE` constants and enum values · `_private` · past-tense signals · `_on_<emitter>_<signal>` handlers · `is_`/`has_`/`can_`/`should_` booleans.

**Never rename without approval:** `class_name`s, signals, public members, `@export`s, enums, constants, paths, or any method connected from a scene. Check `names-and-scenes.md` §6.3 first. Every summary ends with the Breaking Changes table (§6.4) or `No breaking changes.`

## 7. Scenes and UIDs

A **structural change** is adding, removing, renaming or reparenting a node; attaching or swapping a script; changing a signal connection; or adding or removing an `ext_resource`/`sub_resource`. Never invent a `uid`, duplicate a node block, or edit binary `.scn`/`.res`. Move a script with its `.uid` (`git mv` both), never create a `.uid` by hand, and grep for the old `res://` path afterwards.

## 8. Code quality

**Formatting:** tabs, LF, UTF-8, lines under 100 characters, two blank lines around functions, `and`/`or`/`not`, double quotes, a trailing comma on multiline collections, no commented-out code.

**Errors:** guard clauses and early returns. `push_error("ClassName: detail - %s" % [value])`, never `print()`. Always wrap format arguments in an array. Never put side effects in `assert()`. Check `Error` returns and nulls from loads and file access. `@warning_ignore` only with a reason.

**Lifetime and signals:** use `is_instance_valid()` for anything freeable, and re-check after every `await`. Static registries remove themselves in `_exit_tree()`. Connect signals in `_ready()`, and don't connect lambdas you must later disconnect. Call `super()` when overriding a parent script's virtual, unless replacing it on purpose.

**Dead code and constants:** delete dead code only inside members you're changing; report the rest. No magic numbers: name them, and don't invent the value (`CLAUDE.md` §1).

### 8.5 Event bus and effects

For combat, the campaign layer, effects, content definitions and their presentation. The design is in `docs/plans/2026-10-23-event-bus-and-effects.md`.

- **Rules code is pure.** It never touches nodes, the scene tree, autoloads (except `NetLog`, on the main thread only), a bus, the global RNG or disk.
- **Rules never `await`.** Commands resolve completely, then presentation plays the resulting facts. Presentation never drives rules.
- **Effects react through the engine's trigger dispatch,** never through `Signal.connect` on a bus. Bus signals are for presentation and observers only.
- **Every state change emits a fact.** Facts are past tense and carry ids, never objects or Resources.
- **Content definitions are read-only at runtime.** Changes live on instances (deltas, granted effects), never on the shared `.tres`.
- **Read values through `session.stats(unit_id)`,** never by assembling definition, deltas and effects in the caller.
- **Randomness:** gameplay randomness comes only from an `RngStream` or roll source handed to the code, never `randf()`, `randi()` or `pick_random()`. Cosmetic randomness uses its own unsaved generator in presentation.
- **Instance ids come only from `InstanceIdAllocator`** and are never parsed; use the session's `describe(id)` for log and error text.
- **Code that may run in a sandbox on a worker thread** follows the first rule strictly and doesn't log; it returns diagnostics for the main thread to log.

## 9–11. Performance, multiplayer, measuring

Never claim a speedup you didn't measure; label it **unmeasured** otherwise (`performance.md`). Before any networked change, read the relevant parts of `steam_multiplayer_kit/` and `multiplayer.md`.
