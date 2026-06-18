# Cursor Navigation Model — Implementation Tasks

Slices `docs/navigation_model_spec.md` into small, ordered, vertical
deliverables. Implement **in order**. Each task compiles on its own, keeps
the game playable, and improves behavior monotonically. Do not start a task
until the previous one is done.

**Conventions (from `CLAUDE.md`):** snake_case names; structured logging at
state transitions with subsystem prefixes; no comments that restate code;
edit existing files, add new ones only when the task says so. This project
targets Godot 4.6.

---

## Task 1 — Pure navigation model + headless tests

**Goal:** Create the scene-free position model and its regression tests.
After this task the game behaves exactly as before (the model is not wired
in yet), but `run_tests.gd` proves the model logic — including the
"right-at-right-edge stays put" case.

### 1a. New file `scripts/navigation.gd`

Create it with **exactly** this content:

```gdscript
# res://scripts/navigation.gd
class_name Navigation
extends RefCounted

enum Region { BOARD, RACK }

const BOARD_SIZE: int = 8

var region:     int      = Region.BOARD    # where keyboard input currently goes
var board_pos:  Vector2i = Vector2i(3, 3)  # persistent board anchor
var rack_index: int      = 0

# Single transition function. dir is a unit Vector2i: (-1,0)/(1,0)/(0,-1)/(0,1).
# rack_size is passed in because the rack is dynamic.
func move(dir: Vector2i, rack_size: int) -> void:
	if region == Region.BOARD:
		if dir == Vector2i(0, 1) and board_pos.y >= BOARD_SIZE - 1:
			region = Region.RACK
			rack_index = clampi(board_pos.x, 0, max(0, rack_size - 1))
		else:
			board_pos.x = clampi(board_pos.x + dir.x, 0, BOARD_SIZE - 1)
			board_pos.y = clampi(board_pos.y + dir.y, 0, BOARD_SIZE - 1)
	else: # Region.RACK
		if dir == Vector2i(0, -1):
			region = Region.BOARD                # board_pos retained as the anchor
		elif dir.y == 0:
			rack_index = clampi(rack_index + dir.x, 0, max(0, rack_size - 1))
		# dir down in the rack is a deliberate no-op.

# Feed the model from mouse click / focus. Single writer, many triggers.
func set_board(pos: Vector2i) -> void:
	region = Region.BOARD
	board_pos = pos

func set_rack(idx: int) -> void:
	region = Region.RACK
	rack_index = idx
```

### 1b. New file `scripts/sim/tests/test_navigation.gd`

Create it with **exactly** this content (matches the existing test style:
`RefCounted`, `test_*` methods returning `bool`, `push_error` on failure):

```gdscript
class_name TestNavigation
extends RefCounted

const Navigation = preload("res://scripts/navigation.gd")

# TN1 - The reported bug: right at the right edge (top row) must NOT move up.
func test_tn1_right_edge_top_row_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 0))
	nav.move(Vector2i(1, 0), 7)
	if nav.board_pos != Vector2i(7, 0):
		push_error("TN1: expected (7,0), got %s" % nav.board_pos); return false
	if nav.region != Navigation.Region.BOARD:
		push_error("TN1: expected region BOARD"); return false
	return true

# TN2 - Right at the right edge (bottom row) also clamps, no y change.
func test_tn2_right_edge_bottom_row_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 7))
	nav.move(Vector2i(1, 0), 7)
	if nav.board_pos != Vector2i(7, 7):
		push_error("TN2: expected (7,7), got %s" % nav.board_pos); return false
	return true

# TN3 - Down on the bottom row enters the rack at the matching column.
func test_tn3_bottom_down_enters_rack() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(4, 7))
	nav.move(Vector2i(0, 1), 7)
	if nav.region != Navigation.Region.RACK:
		push_error("TN3: expected region RACK"); return false
	if nav.rack_index != 4:
		push_error("TN3: expected rack_index 4, got %d" % nav.rack_index); return false
	return true

# TN4 - Entering a narrower rack clamps the index.
func test_tn4_bottom_down_clamps_to_rack_size() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 7))
	nav.move(Vector2i(0, 1), 3)
	if nav.rack_index != 2:
		push_error("TN4: expected rack_index 2, got %d" % nav.rack_index); return false
	return true

# TN5 - Up from the rack returns to the board, anchor unchanged.
func test_tn5_rack_up_returns_to_anchor() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(2, 7))
	nav.move(Vector2i(0, 1), 7)        # into rack
	nav.move(Vector2i(0, -1), 7)       # back up
	if nav.region != Navigation.Region.BOARD:
		push_error("TN5: expected region BOARD"); return false
	if nav.board_pos != Vector2i(2, 7):
		push_error("TN5: expected anchor (2,7), got %s" % nav.board_pos); return false
	return true

# TN6 - Down in the rack is a no-op.
func test_tn6_rack_down_noop() -> bool:
	var nav = Navigation.new()
	nav.set_rack(3)
	nav.move(Vector2i(0, 1), 7)
	if nav.region != Navigation.Region.RACK or nav.rack_index != 3:
		push_error("TN6: expected RACK index 3, got region %d index %d" % [nav.region, nav.rack_index]); return false
	return true

# TN7 - Rack left/right clamps within [0, rack_size-1].
func test_tn7_rack_left_right_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_rack(0)
	nav.move(Vector2i(-1, 0), 7)       # cannot go below 0
	if nav.rack_index != 0:
		push_error("TN7: expected 0, got %d" % nav.rack_index); return false
	nav.set_rack(6)
	nav.move(Vector2i(1, 0), 7)        # cannot exceed 6
	if nav.rack_index != 6:
		push_error("TN7: expected 6, got %d" % nav.rack_index); return false
	return true

# TN8 - Interior moves shift board_pos by one without changing region.
func test_tn8_interior_moves() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(3, 3))
	nav.move(Vector2i(1, 0), 7)
	nav.move(Vector2i(0, 1), 7)
	if nav.board_pos != Vector2i(4, 4):
		push_error("TN8: expected (4,4), got %s" % nav.board_pos); return false
	if nav.region != Navigation.Region.BOARD:
		push_error("TN8: expected region BOARD"); return false
	return true
```

### 1c. Register the test file in `scripts/sim/tests/run_tests.gd`

In `_initialize()`, after the existing `_run_test_file(...)` calls, add:

```gdscript
	_run_test_file("res://scripts/sim/tests/test_navigation.gd")
```

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → all existing tests still pass **and** TN1–TN8 pass.

### App state after Task 1
Unchanged gameplay; model exists and is tested but not used by the game.

---

## Task 2 — Board keyboard navigation through the model (fixes the board)

**Goal:** Make board arrow keys flow through the model via `_gui_input`
interception, killing Godot's built-in geometric nav on the board. After
this task the "press right at the right edge → cursor jumps up" bug is gone
on the board. The rack still uses the old path (fixed in Task 3).

### 2a. `scripts/board_cell.gd` — intercept directional keys

Add this signal near the top, beside the existing `signal cell_clicked(...)`:

```gdscript
signal move_requested(dir: Vector2i)
```

The existing `_on_gui_input(event)` is connected in `_ready` via
`gui_input.connect(_on_gui_input)`. Extend that method so it also handles
the four directional actions. Append, after the existing mouse-button
`if` block:

```gdscript
	if event.is_action_pressed("ui_left"):
		move_requested.emit(Vector2i(-1, 0)); accept_event()
	elif event.is_action_pressed("ui_right"):
		move_requested.emit(Vector2i(1, 0)); accept_event()
	elif event.is_action_pressed("ui_up"):
		move_requested.emit(Vector2i(0, -1)); accept_event()
	elif event.is_action_pressed("ui_down"):
		move_requested.emit(Vector2i(0, 1)); accept_event()
```

`accept_event()` is what stops Godot's built-in focus navigation from also
firing. Do not touch the mouse-button handling.

### 2b. `scripts/board.gd` — relay the signal

Add a board-level signal beside `signal cell_focused(cell: BoardCell)`:

```gdscript
signal cell_move_requested(dir: Vector2i)
```

In `_ready()`, inside the cell-creation loop, right after the existing
`cell.focus_entered.connect(...)` line, add a relay (a cell forwards its
own direction up to the board):

```gdscript
		cell.move_requested.connect(func(dir): cell_move_requested.emit(dir))
```

### 2c. `scripts/main.gd` — own the model, shim `cursor`, handle board moves

1. **Replace the `cursor` field.** Change line 35 from
   `var cursor: Vector2i = Vector2i(0, 0)` to:

```gdscript
var _nav := Navigation.new()

var cursor: Vector2i:
	get: return _nav.board_pos
```

2. **Fix the two remaining `cursor` writes** (it is now read-only):
   - In `_ready()`, change `cursor = Vector2i(3, 3)` to
     `_nav.set_board(Vector2i(3, 3))`.
   - In `_on_cell_focused`, change `cursor = cell.grid_pos` to
     `_nav.set_board(cell.grid_pos)`.

3. **Connect the new board signal.** In `_ready()`, next to
   `board.cell_focused.connect(_on_cell_focused)`, add:

```gdscript
	board.cell_move_requested.connect(_on_cell_move_requested)
```

4. **Add the board move handler and the focus applier** (place them near
   the input handlers):

```gdscript
func _on_cell_move_requested(dir: Vector2i) -> void:
	_nav.move(dir, rack.tiles_in_hand.size())
	_apply_nav_focus()

func _apply_nav_focus() -> void:
	if _nav.region == Navigation.Region.BOARD:
		board.focus_cell(_nav.board_pos)
	else:
		_focus_rack_index(_nav.rack_index)
```

5. **Remove the board branch from `_unhandled_input`.** Delete the
   `# --- on the board ---` block (the `if event.is_action_pressed("ui_left")`
   … through the `ui_down`/`_enter_rack` `else`). **Keep** the
   `confirm_turn` branch and the A–Z letter branch — re-attach them so they
   still run on the board. The rack branch (`if rack_idx != -1:`) stays
   untouched for now.

6. **Delete the now-unused helpers** `_move_cursor(...)` and `_enter_rack()`
   (their logic now lives in `Navigation`). Keep `_focus_rack_index(...)`.

> After step 5, `_unhandled_input` should still: early-return on game
> state; handle Delete/Backspace; handle the rack branch
> (`if rack_idx != -1`); and handle `confirm_turn` + A–Z letters. Only the
> board directional block and `_move_cursor`/`_enter_rack` are gone.

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green (this task does not touch sim/game logic).
- Run the game. On the board: arrows move one cell; at the **right edge,
  top and bottom rows**, right no longer jumps up — it stays put. Down on
  the bottom row drops focus into the rack at the matching column. Clicking
  a cell then using arrows continues from the clicked cell.

### App state after Task 2
Board navigation is fully model-driven and bug-free. Rack navigation still
runs through the old `_unhandled_input` rack branch (unchanged behavior).

---

## Task 3 — Rack keyboard navigation through the model (fixes the rack)

**Goal:** Apply the same interception to rack tiles so the rack↔board
crossing and rack internal moves go through the model. After this task
Godot's built-in nav is fully suppressed and the whole navigation surface
is model-driven.

### 3a. `scripts/tile.gd` — intercept directional keys

Add near the top of the script:

```gdscript
signal move_requested(dir: Vector2i)
```

`tile.gd` has no `_gui_input` yet. Add one (Godot calls `_gui_input`
automatically on a `Control`; no manual connect needed):

```gdscript
func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		move_requested.emit(Vector2i(-1, 0)); accept_event()
	elif event.is_action_pressed("ui_right"):
		move_requested.emit(Vector2i(1, 0)); accept_event()
	elif event.is_action_pressed("ui_up"):
		move_requested.emit(Vector2i(0, -1)); accept_event()
	elif event.is_action_pressed("ui_down"):
		move_requested.emit(Vector2i(0, 1)); accept_event()
```

Do not change the drag-and-drop (`_get_drag_data`) code.

### 3b. `scripts/rack.gd` — relay the signal

Add a rack-level signal near the top:

```gdscript
signal tile_move_requested(dir: Vector2i)
```

Tiles are created in **two** places — `refill()` and `discard_replace()`.
In **both**, immediately after the tile is created and before/after it is
appended, connect its signal:

```gdscript
	tile.move_requested.connect(func(dir): tile_move_requested.emit(dir))
```

(In `discard_replace()` the variable is `new_tile`, so use
`new_tile.move_requested.connect(...)`.)

### 3c. `scripts/main.gd` — handle rack moves, finalize `_unhandled_input`

1. **Connect the rack signal.** In `_ready()`, beside the board connection
   from Task 2, add:

```gdscript
	rack.tile_move_requested.connect(_on_rack_move_requested)
```

2. **Add the rack move handler** (next to `_on_cell_move_requested`):

```gdscript
func _on_rack_move_requested(dir: Vector2i) -> void:
	_nav.move(dir, rack.tiles_in_hand.size())
	_apply_nav_focus()
```

3. **Remove the rack branch from `_unhandled_input`.** Delete the
   `var focused = ...`, `var rack_idx := ...`, and the whole
   `if rack_idx != -1:` block.

4. **Add the focus-lost fallback.** In `_unhandled_input`, after the
   Delete/Backspace block and before `confirm_turn`/letters, add: a
   directional key only reaches `_unhandled_input` if no cell/tile consumed
   it (focus was lost), so re-anchor on the board cursor.

```gdscript
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
			or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		board.focus_cell(cursor)
		get_viewport().set_input_as_handled()
		return
```

> Final `_unhandled_input` shape: game-state early return → Delete/Backspace
> → focus-lost directional fallback → `confirm_turn` → A–Z letters. No
> per-region branching remains.

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green.
- Run the game. Full keyboard walk: interior arrows; all four edges;
  bottom row down → rack at matching column; rack left/right clamps; rack
  up → returns to the board anchor; rack down → nothing.

### App state after Task 3
Entire keyboard navigation is model-driven; built-in geometric nav is
suppressed everywhere; the original bug class is closed.

---

## Task 4 — Track mouse focus on rack tiles (consistency polish)

**Goal:** Clicking/focusing a rack tile with the mouse should set the model
to the rack region, so a subsequent keypress behaves correctly instead of
acting as if focus were still on the board.

### 4a. `scripts/rack.gd` — relay tile focus with its index

Add a signal:

```gdscript
signal tile_focused(index: int)
```

Where each tile is created (same two spots as Task 3b: `refill()` and
`discard_replace()`), also connect its `focus_entered`, emitting the tile's
current rack index at focus time:

```gdscript
	tile.focus_entered.connect(func(): tile_focused.emit(tiles_in_hand.find(tile)))
```

(Use `new_tile` in `discard_replace()`. Looking up the index at emit time
keeps it correct even after the rack is mutated.)

### 4b. `scripts/main.gd` — feed the model

In `_ready()`, beside the other rack connection, add:

```gdscript
	rack.tile_focused.connect(_on_tile_focused)
```

Add the handler:

```gdscript
func _on_tile_focused(index: int) -> void:
	if index >= 0:
		_nav.set_rack(index)
```

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green.
- Run the game. Click a rack tile, then press **up**: focus returns to the
  board anchor (proving the model knew it was in the rack). Click a board
  cell, then arrow: continues from that cell.

### App state after Task 4
Mouse and keyboard both feed one model. Navigation is fully consistent.

---

## Done criteria (all tasks)

- `run_tests.gd` reports all existing groups plus TN1–TN8 passing.
- Pressing **right** never moves the cursor up, at any board position.
- Board↔rack crossings (bottom-row-down, rack-up) land on the intended
  target every time, by keyboard and after a mouse click.
- `scripts/main.gd` has no `_move_cursor`/`_enter_rack`, no per-region
  directional branches in `_unhandled_input`, and `cursor` is a read-only
  accessor over `_nav.board_pos`.
- `game_core.gd`, scoring, progression, and non-directional input are
  untouched.
