# Move Unlocked Board Tiles — Implementation Tasks

Slices `docs/board_tile_move_spec.md` into small, ordered, vertical
deliverables. Implement **in order**. Each task compiles on its own, keeps
the game playable, and improves behavior monotonically. Do not start a task
until the previous one is done.

**Conventions (from `CLAUDE.md`):** snake_case names; structured logging at
state transitions with subsystem prefixes; no comments that restate code;
edit existing files only — no new files. This project targets Godot 4.6.

Only two files change: `scripts/board_cell.gd` and `scripts/main.gd`.
Do **not** touch `tile.gd`, `rack.gd`, or anything under `scripts/sim/`.
There are no headless tests for this feature (drag-and-drop is scene-coupled);
verification is by running the game.

---

## Task 1 — Move an unlocked tile to an empty cell, and back to the rack

**Goal:** Make `BoardCell` a drag source for its unlocked tile. Dropping on
an **empty** cell moves it; dropping on the **rack** returns it to hand;
dropping on an occupied or locked cell is rejected (snaps back). Swapping
onto another unlocked tile comes in Task 2.

### 1a. `scripts/main.gd` — gating helper

Add this method in the `# ---------- Drag and drop ----------` section
(e.g. right after `on_tile_returned_to_rack`):

```gdscript
func can_move_board_tile() -> bool:
	return not (RunState.is_game_over or RunState.is_transitioning \
		or RunState.is_upgrading or _discard_busy)
```

### 1b. `scripts/board_cell.gd` — become a drag source

Add a `_get_drag_data` method in the `# --- Drag and drop target ---`
section (put it just above `_can_drop_data`). The hidden placed-tile node is
`current_tile`; only unlocked cells have one.

```gdscript
func _get_drag_data(_at_position: Vector2) -> Variant:
	if current_tile == null:
		return null  # empty or locked cell — nothing to pick up
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("can_move_board_tile") and not main.can_move_board_tile():
		return null
	var preview_root := Control.new()
	var preview := current_tile.duplicate() as Control
	preview.visible = true  # the source node is invisible; duplicate inherits that
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.position = -current_tile.size / 2.0
	preview_root.add_child(preview)
	set_drag_preview(preview_root)
	return current_tile
```

### 1c. `scripts/board_cell.gd` — accept board tiles on empty cells

Replace the existing `_can_drop_data`:

```gdscript
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Tile and is_empty()
```

with:

```gdscript
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Tile):
		return false
	var t := data as Tile
	if t.location == "board":
		if t.board_pos == grid_pos:
			return false        # dropping on its own cell — no-op
		return is_empty()       # Task 1: empty cells only (swap added in Task 2)
	return is_empty()           # rack-tile placement, unchanged
```

Leave `_drop_data` as-is — it already calls
`main.on_tile_dropped_on_cell(tile, self)`.

### 1d. `scripts/main.gd` — route board tiles and move them

Replace the existing `on_tile_dropped_on_cell`:

```gdscript
func on_tile_dropped_on_cell(tile: Tile, cell: BoardCell) -> void:
	if RunState.is_transitioning or RunState.is_upgrading or _discard_busy or not cell.is_empty():
		return
	_place_tile_on_cell(tile, cell)
```

with (the `not cell.is_empty()` check moves into the rack branch so a future
swap can target an occupied cell):

```gdscript
func on_tile_dropped_on_cell(tile: Tile, cell: BoardCell) -> void:
	if RunState.is_transitioning or RunState.is_upgrading or _discard_busy:
		return
	if tile.location == "board":
		_move_board_tile(tile, cell)
		return
	if not cell.is_empty():
		return
	_place_tile_on_cell(tile, cell)
```

Add the move handler nearby (e.g. right after `_place_tile_on_cell`):

```gdscript
func _move_board_tile(tile: Tile, dest: BoardCell) -> void:
	var src := board.get_cell(tile.board_pos)
	if src == null or src == dest:
		return
	if not dest.is_empty():
		return  # Task 1: empty destinations only; swap added in Task 2
	src.clear_pending()
	pending_cells.erase(src)
	dest.place_tile(tile)
	pending_cells.append(dest)
	print("[Move] %s %s -> %s" % [tile.letter, src.grid_pos, dest.grid_pos])
	board.focus_cell(dest.grid_pos)
	_update_hud()
```

### 1e. `scripts/main.gd` — guard + focus the rack-return path

`on_tile_returned_to_rack` is already wired from `Rack._can_drop_data` but was
unreachable; the drag source now activates it. Two edits to that method:

- Add as the **first** line of the function body:

```gdscript
	if RunState.is_transitioning or RunState.is_upgrading or _discard_busy:
		return
```

- Add as the **last** line of the function (after `_update_hud()`):

```gdscript
	tile.grab_focus()  # drives _nav.set_rack via the rack's tile_focused relay
```

### Verify
- Run the game. Drag an unlocked tile onto an **empty** cell → it moves
  (source clears, destination pops). Drag onto the **rack** → returns to hand
  and the returned tile is focused; arrows resume from the rack. Drag onto an
  **occupied** or **locked** cell, or onto its **own** cell → nothing happens
  (snaps back). Start a round transition / upgrade dialog → a drag won't begin.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green.

### App state after Task 1
Unlocked board tiles can be moved to empty cells or returned to the rack by
mouse. Dropping onto another tile is still rejected.

---

## Task 2 — Swap two unlocked tiles

**Goal:** Dropping an unlocked tile onto **another unlocked tile** exchanges
their positions. Locked targets and same-cell drops stay rejected.

### 2a. `scripts/board_cell.gd` — accept unlocked targets

In `_can_drop_data`, change the board-tile branch so an occupied **unlocked**
cell is accepted while **locked** cells are still rejected. Replace:

```gdscript
	if t.location == "board":
		if t.board_pos == grid_pos:
			return false        # dropping on its own cell — no-op
		return is_empty()       # Task 1: empty cells only (swap added in Task 2)
	return is_empty()           # rack-tile placement, unchanged
```

with:

```gdscript
	if t.location == "board":
		if t.board_pos == grid_pos:
			return false           # dropping on its own cell — no-op
		return locked_letter == "" # empty -> move, unlocked -> swap, locked -> reject
	return is_empty()              # rack-tile placement, unchanged
```

### 2b. `scripts/main.gd` — add the swap branch

Replace the body of `_move_board_tile` (from Task 1d):

```gdscript
func _move_board_tile(tile: Tile, dest: BoardCell) -> void:
	var src := board.get_cell(tile.board_pos)
	if src == null or src == dest:
		return
	if not dest.is_empty():
		return  # Task 1: empty destinations only; swap added in Task 2
	src.clear_pending()
	pending_cells.erase(src)
	dest.place_tile(tile)
	pending_cells.append(dest)
	print("[Move] %s %s -> %s" % [tile.letter, src.grid_pos, dest.grid_pos])
	board.focus_cell(dest.grid_pos)
	_update_hud()
```

with:

```gdscript
func _move_board_tile(tile: Tile, dest: BoardCell) -> void:
	var src := board.get_cell(tile.board_pos)
	if src == null or src == dest:
		return
	if dest.is_empty():
		# MOVE into an empty cell
		src.clear_pending()
		pending_cells.erase(src)
		dest.place_tile(tile)
		pending_cells.append(dest)
		print("[Move] %s %s -> %s" % [tile.letter, src.grid_pos, dest.grid_pos])
	else:
		# SWAP with another unlocked tile (locked targets were rejected upstream)
		var other := dest.current_tile
		if other == null:
			return
		src.clear_pending()
		dest.clear_pending()
		src.place_tile(other)   # other.board_pos -> src.grid_pos
		dest.place_tile(tile)   # tile.board_pos  -> dest.grid_pos
		# pending_cells membership is unchanged: both cells stay pending.
		print("[Move] swap %s@%s <-> %s@%s" % [tile.letter, dest.grid_pos, other.letter, src.grid_pos])
	board.focus_cell(dest.grid_pos)
	_update_hud()
```

### Verify
- Run the game. Drag an unlocked tile onto **another unlocked** tile → the two
  swap (both cells pop, both letters/modifiers move). Drag onto a **locked**
  tile → still rejected. Empty-cell move and rack-return from Task 1 still
  work. End the turn after a swap → scoring reflects the new positions.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green.

### App state after Task 2
Full feature: unlocked board tiles can be moved to empty cells, swapped with
other unlocked tiles, or returned to the rack — all by mouse, with locked
tiles immovable.

---

## Done criteria (all tasks)

- Dragging an unlocked board tile moves it to an empty cell, swaps it with
  another unlocked tile, or returns it to the rack.
- Locked tiles never move; dropping onto a locked tile or onto the source's
  own cell is a no-op.
- A drag never starts during a transition, upgrade dialog, game over, or
  mid-animation.
- After every drop the cursor/keyboard nav resumes from the right place
  (destination cell, or the returned rack tile).
- `pending_cells` stays correct (move re-points src→dest; swap unchanged), so
  the `tiles_per_turn` auto-end-turn is never falsely triggered by a move.
- `run_tests.gd` stays green; `game_core.gd` and `scripts/sim/` are untouched.
