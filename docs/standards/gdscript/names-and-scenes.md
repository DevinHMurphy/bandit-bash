# GDScript standards: names, renames and scenes

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans.

## 6. Naming, renames and breaking changes

### 6.1 Naming

| Element | Convention | Example |
|---------|------------|---------|
| Files (`.gd`, `.tscn`, `.tres`) | snake_case | `unit_token.gd` |
| Classes | PascalCase | `UnitToken` |
| Nodes in a scene | PascalCase | `HpBar` |
| Functions / variables | snake_case | `get_move_speed()` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_STRIKES` |
| Preloaded script used as a type | PascalCase | `const BoardModel = preload("res://ui/battle/board/board_view_model.gd")` |
| Preloaded scene or resource | SCREAMING_SNAKE_CASE | `const TOKEN_SCENE: PackedScene = preload("res://ui/battle/unit/unit_token.tscn")` |
| Enums | PascalCase, singular | `Stage` |
| Enum values | SCREAMING_SNAKE_CASE | `MOVE` |
| Private members | `_snake_case` | `_tile_size` |
| Signals | past-tense snake_case | `unit_defeated` |
| Signal handlers | `_on_<emitter>_<signal>` | `_on_hp_bar_value_changed` |
| Booleans | `is_` / `has_` / `can_` / `should_` | `is_active` |

snake_case file names also avoid case-sensitivity failures when exporting from Windows or macOS.

### 6.2 Never rename without explicit approval

`class_name`, signals, public functions, public variables, `@export` variables, enum names or values,
constants, file and folder paths, **and any method connected from a scene** — including private
`_on_*` handlers.

### 6.3 Where names are stored (check all of them before suggesting a rename)

- **Scene signal connections** store method names in `.tscn` (`[connection ... method="_on_x"]`).
- **Exported property values** are stored by name in `.tscn`/`.tres`. Renaming an `@export`
  silently drops every saved value, with no error.
- **AnimationPlayer tracks** reference properties and methods by string.
- **String-based calls:** `call()`, `call_deferred()`, `set()`, `get()`, `has_method()`, `connect()`
  with string names, and `Callable(obj, "name")`.
- **RPC methods** must have the same name on every peer.
- **`project.godot`**: autoload names and paths, input action names, global groups.
- **Groups** referenced as strings.
- **Doc links:** `[member old_name]`, `[method old_name]`, `[ClassName]`.
- **Paths** (`res://...`) in scenes, resources and `preload()` calls.

Search only the new project:
`grep -rn --include='*.gd' --include='*.tscn' --include='*.tres' --include='project.godot' "old_name" bandit-bash/`.
Binary `.scn`/`.res` files can't be searched; if the project has any, say so in the summary.

### 6.4 Breaking Changes table

Suggest a rename; don't apply it. Every summary and every plan ends with this table, or the line
`No breaking changes.`

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| Typo + convention | Constant | `tile_nieghbor_index` | `TILE_NEIGHBOR_INDEX` | Suggested | `.gd`, `.tscn`, `.tres` | 🟡 |

`Status` is `Suggested` or `Applied`. Risk uses the legend in `CLAUDE.md` §2.

---

## 7. Scenes, resources and UID files

- **Prefer the editor.** Wiring that the editor does safely (adding nodes, connecting signals,
  assigning resources) is better done there. When a task needs it, describe the change and ask the
  user to make it, or do it in code.
- **A structural scene/resource change** is any of: adding, removing, renaming or reparenting a
  node; attaching or swapping a script; adding or removing a signal connection; adding or removing
  an `ext_resource`/`sub_resource`. Changing a property value is not structural, but can still
  change gameplay feel (`CLAUDE.md` §1).
- **When hand-editing `.tscn`/`.tres`:**
  - Never change or invent a `uid="uid://..."` value.
  - Keep `ext_resource`/`sub_resource` `id`s unique within the file, and update every reference to
    an id you change.
  - Never duplicate a node block by copy and paste; its identifiers come along with it.
  - Never edit binary `.scn`/`.res` files.
- **`.uid` sidecar files:** every script has a `<name>.gd.uid` beside it.
  - Move or rename the script and its `.uid` together (`git mv` both).
  - Delete them together.
  - Never create a `.uid` file by hand; the editor generates one for a new script.
  - Commit `.uid` files.
- After moving or renaming a script or scene, grep for its old `res://` path (§6.3).
