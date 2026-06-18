# Cursor Navigation Model — Design Specification

Replaces the implicit, dual-authority keyboard navigation with a single
scene-free **navigation model** that owns cursor position. Fixes the
"press right → cursor moves up" bug at its root. Settled in design review
(2026-06-18). This is the **design spec**; implementation follows on
branch `claude/clever-carson-pat4yi`.

## Summary

- **The bug.** Board cells and rack tiles are `FOCUS_ALL` controls in
  containers with **no explicit focus neighbors**. Godot's built-in
  *geometric* focus navigation fires during the GUI input phase — *before*
  `main.gd::_unhandled_input` — and at edges picks a non-grid-aligned
  neighbor (e.g. right edge → a cell in the row above). `_on_cell_focused`
  then mirrors `cursor` to wherever focus wrongly landed. `main.gd`'s real
  grid logic only runs at edges where the geometric search finds nothing,
  so two systems fight over one cursor.
- **Root cause, not symptom.** The deeper smell is *two representations of
  position* kept in sync — the `cursor: Vector2i` variable and the Godot
  focus owner — plus navigation rules split across two `if`-branches keyed
  off the focus owner's type. "right → up" is one symptom of that disease.
- **The fix.** Introduce one **pure, scene-free navigation model**
  (`scripts/navigation.gd`) that is the single source of truth for cursor
  position across **both** the board and the rack. Keyboard input is
  intercepted in the focused control's `_gui_input` and fed to the model;
  Godot's built-in nav is decisively suppressed via `accept_event()`.
  Focus becomes a pure *render* of the model. The existing `cursor` name
  survives as a read-only accessor over the model's board anchor.
- **Why this shape.** It mirrors the project's own established pattern:
  `game_core.gd` exists so game logic can live scene-free and be tested by
  `run_tests.gd`. The navigation model applies the same idea to input,
  making the "right → up" class of bug a one-line regression test instead
  of a manual click-walk.
- **Sim untouched.** `game_core.gd` and the strategies have no cursor or
  input concept. No sim parity is involved.

## 1. The navigation model (`scripts/navigation.gd`)

A new pure `RefCounted` class. **No `$NodePath`, no `grab_focus`, no UI
types** — only `Vector2i` and enums. This is what makes it unit-testable
headlessly.

### State

```gdscript
class_name Navigation
extends RefCounted

enum Region { BOARD, RACK }

var region:     int     = Region.BOARD   # where keyboard input currently goes
var board_pos:  Vector2i = Vector2i(3, 3) # persistent board anchor
var rack_index: int      = 0
```

- **`region`** — the active input region. Selects whether arrow keys move
  on the board or within the rack.
- **`board_pos`** — the cursor's board coordinate. **Persists while
  `region == RACK`**: it is the anchor the cursor returns to when leaving
  the rack, *and* the cell letter-placement targets. This persistence is a
  hard requirement — placement (`_try_place_letter_on_cursor`) and the
  eight `board.focus_cell(cursor)` re-anchor calls all depend on a board
  coordinate that survives a rack excursion.
- **`rack_index`** — the focused rack slot while `region == RACK`.

### Transition — `move(dir, rack_size)`

The single place every adjacency and boundary rule lives. `rack_size` is
passed in because the rack is dynamic (grows/shrinks). `dir` is a unit
`Vector2i` (`(-1,0)`, `(1,0)`, `(0,-1)`, `(0,1)`). Rules are a **verbatim
relocation** of today's behavior in `main.gd` (lines 73–94), not a
rewrite:

| Region | Direction   | Effect                                                                                 |
|--------|-------------|----------------------------------------------------------------------------------------|
| BOARD  | left/right/up | `board_pos += dir`, clamp each axis to `[0, BOARD_SIZE-1]`. Region unchanged.        |
| BOARD  | down (interior) | `board_pos.y += 1` (not yet at bottom row).                                        |
| BOARD  | down (bottom row) | `region = RACK`; `rack_index = clamp(board_pos.x, 0, rack_size-1)`.              |
| RACK   | left/right  | `rack_index = clamp(rack_index + dir.x, 0, rack_size-1)`.                              |
| RACK   | up          | `region = BOARD`. `board_pos` retained → cursor returns to the anchor.                 |
| RACK   | down        | **no-op** (consumed, nothing moves).                                                   |

`BOARD_SIZE` is mirrored as a model constant (8), matching `Board.BOARD_SIZE`.

### Setters (feeding the model from clicks / focus)

```gdscript
func set_board(pos: Vector2i) -> void   # region = BOARD; board_pos = pos
func set_rack(idx: int) -> void         # region = RACK;  rack_index = idx
```

These make mouse interaction an **input into** the single model rather than
a rival writer. Clicking a board cell calls `set_board`; clicking/focusing
a rack tile calls `set_rack`.

## 2. Input interception (`board_cell.gd`, `tile.gd`)

Both already use `focus_mode = FOCUS_ALL`. Add:

```gdscript
signal move_requested(dir: Vector2i)

func _gui_input(event: InputEvent) -> void:
    # ... existing mouse-button handling stays ...
    if   event.is_action_pressed("ui_left"):  _emit_move(Vector2i(-1, 0)); accept_event()
    elif event.is_action_pressed("ui_right"): _emit_move(Vector2i( 1, 0)); accept_event()
    elif event.is_action_pressed("ui_up"):    _emit_move(Vector2i( 0,-1)); accept_event()
    elif event.is_action_pressed("ui_down"):  _emit_move(Vector2i( 0, 1)); accept_event()
```

- **`_gui_input` runs before** Godot's built-in directional navigation in
  the GUI phase. `accept_event()` stops the default nav from also firing —
  this is the documented, scoped way to override focus navigation, and it
  only triggers when a cell/tile genuinely has focus.
- `is_action_pressed` defaults to **no echo**, so holding an arrow moves
  one cell per press — matching today's behavior.
- **Only the four directional actions** are intercepted. Letters (A–Z),
  Delete/Backspace, and `confirm_turn` are *not* directional, are not
  touched by built-in nav, and stay in `main.gd::_unhandled_input`
  unchanged.

`board_cell.gd` already reaches `main` via group lookup in `_drop_data`,
but navigation uses the **signal-relay** pattern (below) to match the
existing `cell_focused` / `cell_clicked` architecture and keep leaf nodes
ignorant of `main`'s concrete type.

## 3. Signal relays (`board.gd`, `rack.gd`)

Mirror the existing `cell_focused` relay:

- **`board.gd`** — add `signal cell_move_requested(dir: Vector2i)`. In the
  cell-creation loop, connect each cell's `move_requested` to re-emit
  `cell_move_requested`. (Symmetric to the existing
  `cell.focus_entered.connect(...)` line.)
- **`rack.gd`** — add `signal tile_move_requested(dir: Vector2i)`. Wire
  each tile's `move_requested` where tiles are created — in **both**
  `refill()` and `discard_replace()` — so newly drawn tiles are connected.

## 4. Controller wiring (`main.gd`)

### Ownership & the `cursor` shim

```gdscript
var _nav := Navigation.new()

var cursor: Vector2i:
    get: return _nav.board_pos
```

- `_nav.board_pos` initialized to `Vector2i(3, 3)` at startup (today's
  start position).
- **`cursor` becomes a read-only accessor.** All existing reads keep
  working verbatim: the eight `board.focus_cell(cursor)` re-anchor calls,
  `board.get_cell(cursor)` in placement (line 118), and the edge checks.
  `board_pos`-as-anchor is a real concept the model owns, so this alias is
  accurate, not a hack.

### `_ready` connections

```gdscript
board.cell_focused.connect(_on_cell_focused)          # existing
board.cell_move_requested.connect(_on_cell_move_requested)
rack.tile_move_requested.connect(_on_rack_move_requested)
```

### Handlers

```gdscript
func _on_cell_move_requested(dir: Vector2i) -> void:
    _nav.move(dir, rack.tiles_in_hand.size())
    _apply_nav_focus()

func _on_rack_move_requested(dir: Vector2i) -> void:
    _nav.move(dir, rack.tiles_in_hand.size())
    _apply_nav_focus()

func _apply_nav_focus() -> void:
    if _nav.region == Navigation.Region.BOARD:
        board.focus_cell(_nav.board_pos)
    else:
        _focus_rack_index(_nav.rack_index)
```

Both handlers are identical thin wrappers; they stay as two distinct
entry points (board vs rack context) rather than one focus-owner-sniffing
method, keeping the two concerns cleanly separable.

### `_on_cell_focused` feeds the model

```gdscript
func _on_cell_focused(cell: BoardCell) -> void:
    _nav.set_board(cell.grid_pos)   # was: cursor = cell.grid_pos
```

Mouse click / focus is now a single writer *into* the model.

### `_unhandled_input` changes

- **Delete** the four directional branches (board lines 84–94 and rack
  lines 73–81 move into the model + handlers).
- **Keep** letters, Delete/Backspace, `confirm_turn` exactly as-is.
- **Keep the focus-lost fallback:** if a `ui_*` arrow still reaches
  `_unhandled_input` (no control consumed it → focus was lost), re-grab
  focus via `board.focus_cell(cursor)` and consume. Three-line safety net
  against the `HBoxContainer`-steals-focus quirk noted in `CLAUDE.md`.

### Removed / retained helpers

- **Remove** `_move_cursor` (movement now lives in the model).
- **Remove** `_enter_rack`'s body (its bottom-edge → rack logic is now in
  `Navigation.move`); the rack-index focus is handled by
  `_focus_rack_index`.
- **Keep** `_focus_rack_index` (used by `_apply_nav_focus`).

## 5. Mouse interaction with rack tiles (decision: track it)

For a genuinely consistent system, **clicking/focusing a rack tile sets
`region = RACK`**. Add a `tile.focus_entered` relay through `rack.gd` to
`main`, which calls `_nav.set_rack(index)`. Without this, mouse-focusing a
tile leaves the model believing it is on the board until the next keypress.

- Programmatic focus from `_focus_rack_index` would re-fire `set_rack`
  with the same index — harmless (idempotent).
- This is a small, deliberate extension beyond today's looser behavior
  (which never tracked rack focus in `cursor` at all). It is included
  because the goal is a consistent model, not a minimal patch.

## 6. Tests (`scripts/sim/tests/run_tests.gd`)

Because `Navigation` is pure and scene-free, navigation becomes
**headless-testable** — the payoff of the model. Add a new `TN` group to
the project's existing single test harness (importing `navigation.gd` is
safe: no scene coupling). Minimum cases:

- **TN1 — the reported bug.** `move((1,0))` at `board_pos = (7, 0)` (right
  edge, top row) leaves `board_pos == (7, 0)`, `region == BOARD`. Pressing
  right at the edge clamps; it must **never** change `y`.
- **TN2 — right edge, bottom row.** Same clamp at `(7, 7)`.
- **TN3 — bottom-row down → rack.** From `board_pos = (4, 7)`, `move((0,1))`
  with `rack_size = 7` → `region == RACK`, `rack_index == 4`.
- **TN4 — bottom-row down with narrow rack.** From `board_pos = (7, 7)`,
  `rack_size = 3` → `rack_index == 2` (clamped).
- **TN5 — rack up → board anchor.** From `region == RACK`, `move((0,-1))`
  → `region == BOARD`, `board_pos` unchanged.
- **TN6 — rack down no-op.** `region`/`rack_index` unchanged.
- **TN7 — rack left/right clamp.** `rack_index` stays within
  `[0, rack_size-1]`.
- **TN8 — interior moves.** Plain up/down/left/right shift `board_pos` by
  one without changing region.

## 7. Verification (run locally — no Godot in the agent environment)

- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → existing TC/TS/TSM groups still green **and** new TN cases pass.
- Manual walk in the running game:
  - interior arrows move one cell in the pressed direction;
  - all four **edges**, especially the **right edge on the top and bottom
    rows** (the original "right → up");
  - bottom board row **down** → drops into the rack at the matching column;
  - rack **left/right** clamps; rack **up** → returns to the board anchor;
    rack **down** → no-op;
  - click a board cell, then keyboard — movement continues from the
    clicked cell;
  - (per §5) click a rack tile, then press **up** → returns to the board.

## Files touched

- `scripts/navigation.gd` — **new** pure model.
- `scripts/board_cell.gd` — `move_requested` signal + `_gui_input`
  interception.
- `scripts/tile.gd` — `move_requested` signal + `_gui_input` interception;
  `focus_entered` relay for §5.
- `scripts/board.gd` — `cell_move_requested` relay.
- `scripts/rack.gd` — `tile_move_requested` relay (in `refill` and
  `discard_replace`); `tile` focus relay for §5.
- `scripts/main.gd` — `_nav` ownership, `cursor` accessor, handlers,
  `_apply_nav_focus`, `_on_cell_focused` feeds model, `_unhandled_input`
  trimmed to non-directional + fallback, `_move_cursor`/`_enter_rack`
  removed.
- `scripts/sim/tests/run_tests.gd` — `TN1–TN8` navigation cases.

## Out of scope

- `game_core.gd` and the simulator (no input/cursor concept).
- Scoring, progression, tile draw, modifiers.
- Any non-directional input (letters, Delete/Backspace, `confirm_turn`).
- Persisting focus neighbors / using Godot's built-in nav (deliberately
  suppressed).
