# Move Unlocked Board Tiles — Design Spec

## Summary

Let the player relocate an **unlocked** tile already on the board to another
cell with the mouse (drag-and-drop). Dropping on an empty cell **moves** the
tile; dropping on another unlocked tile **swaps** the two; dropping on a
**locked** tile is rejected; dropping on the rack **returns** the tile to
hand. Locked tiles are immovable for the round, by construction.

This reuses the existing Godot drag-and-drop plumbing
(`_get_drag_data` / `_can_drop_data` / `_drop_data`) and the existing
`on_tile_dropped_on_cell` / `on_tile_returned_to_rack` entry points. Two
files change: `scripts/board_cell.gd` and `scripts/main.gd`.

## Background — why it works the way it does

When a tile is placed on the board (`main.gd::_place_tile_on_cell`), its
`Tile` node is **reparented to `main` and set `visible = false`**; the cell
renders the letter through its own `Label`. The live node is kept as
`BoardCell.current_tile`. So:

- An **unlocked** board tile ⇔ a cell with `current_tile != null`.
- A **locked** tile is just `locked_letter` (the node was `queue_free`'d in
  `lock_pending`); there is no node to drag.
- The visible thing on the board is the **`BoardCell`**, not the tile node.

Therefore the drag must originate from the `BoardCell`, and move/swap only
reassign `current_tile` pointers and `board_pos` — **no reparenting is
needed**, because placed tile nodes already live under `main` invisibly and
the cell label is what's drawn.

Modifiers travel with the tile: `BoardCell.get_modifier()` returns
`current_tile.modifier`. There is no positional board modifier in the live
game, so move/swap carry modifiers automatically with no extra work.

## 1. Drag source — `BoardCell._get_drag_data`

New method. Returns `current_tile` so the existing drop targets (which all
accept a `Tile`) work unchanged.

- Returns `null` when `current_tile == null` (empty or locked cell → not
  draggable).
- Returns `null` when the game is in an overlay/animation state — gated via
  a new `main` helper so the rule lives in one place
  (`is_game_over`, `is_transitioning`, `is_upgrading`, `_discard_busy`).
- Preview: duplicate `current_tile`, force `visible = true` (the original is
  invisible, and `duplicate()` inherits that), `modulate.a = 0.85`, centered
  under the cursor — identical treatment to `tile.gd::_get_drag_data`.

A **failed** drop mutates nothing (we never change state in
`_get_drag_data`), so the source cell simply keeps its tile.

## 2. Drop acceptance — `BoardCell._can_drop_data`

Extend the current `data is Tile and is_empty()` to distinguish the payload's
origin (`tile.location`):

- **Rack tile** (`location == "rack"`): accept iff `is_empty()` (unchanged
  placement behavior).
- **Board tile** (`location == "board"`):
  - reject if dropping on **its own cell** (`tile.board_pos == grid_pos`),
  - reject if the target is **locked** (`locked_letter != ""`),
  - otherwise accept (empty → move; unlocked → swap).

## 3. Drop routing — `main.gd::on_tile_dropped_on_cell`

Branch on `tile.location`:

- `"board"` → new `_move_board_tile(tile, dest)`. **Must not** call
  `_place_tile_on_cell` (that does `rack.remove_tile`, appends to
  `pending_cells`, and can trip the `tiles_per_turn` auto-end-turn — all
  wrong for an already-placed tile).
- `"rack"` → existing path: reject if `not cell.is_empty()`, else
  `_place_tile_on_cell`.

Keep the `is_transitioning / is_upgrading / _discard_busy` early-return; only
the `not cell.is_empty()` part moves into the rack-tile branch (a swap needs
an occupied target).

## 4. Move / swap — `main.gd::_move_board_tile`

```
src := board.get_cell(tile.board_pos)
guard: src == null or src == dest → return
if dest.is_empty():
    # MOVE
    src.clear_pending(); pending_cells.erase(src)
    dest.place_tile(tile); pending_cells.append(dest)
else:
    # SWAP (dest holds an unlocked tile; locked was rejected in _can_drop_data)
    other := dest.current_tile
    guard: other == null → return
    src.clear_pending(); dest.clear_pending()
    src.place_tile(other)   # other.board_pos -> src.grid_pos
    dest.place_tile(tile)   # tile.board_pos  -> dest.grid_pos
# pending_cells membership: MOVE swaps src→dest; SWAP unchanged (both already in)
board.focus_cell(dest.grid_pos)   # re-anchors _nav via _on_cell_focused
_update_hud()
```

`BoardCell.place_tile` already updates the label, sets `tile.board_pos`,
re-syncs the modifier color, and plays the "pop" — so move pops the
destination and swap pops both cells. Tile nodes stay parented to `main`,
invisible.

Add a `[Move]` structured-log line at each transition (move and swap),
per the project's logging convention.

## 5. Return to rack — `main.gd::on_tile_returned_to_rack`

Already wired (`Rack._can_drop_data` accepts board tiles → this method) but
currently unreachable. Making `BoardCell` a drag source activates it. Two
small additions:

- Add the same overlay-state guard at the top (defensive: state may change
  mid-drag).
- After the tile is appended to the rack, `tile.grab_focus()` so focus lands
  on the returned tile, which drives `_nav.set_rack` via the existing
  `tile_focused` relay (Question 7).

Return is **instant** (no tween) — the drag itself was the motion.

## 6. Gating helper — `main.gd`

```
func can_move_board_tile() -> bool:
    return not (RunState.is_game_over or RunState.is_transitioning
        or RunState.is_upgrading or _discard_busy)
```

Single source for "can the player pick up a board tile right now." Used by
`BoardCell._get_drag_data`.

## 7. Focus / navigation consistency

All drop outcomes leave the `Navigation` model (`_nav`) consistent:

- move / swap → `board.focus_cell(dest)` → `_on_cell_focused` →
  `_nav.set_board(dest)`.
- return-to-rack → `tile.grab_focus()` → `tile_focused` → `_nav.set_rack`.

## 8. Verification

Drag-and-drop is scene-coupled (it touches `_gui_input`, node reparenting,
focus, signals on UI nodes), so it is **not** mirrored in `scripts/sim/` and
has **no headless test** — consistent with CLAUDE.md ("don't import
scene-coupled scripts into sim code"). `game_core.gd` is untouched. Verify by
running the game:

- Drag an unlocked tile to an empty cell → it moves; source clears; dest pops.
- Drag an unlocked tile onto another unlocked tile → they swap; both pop.
- Drag onto a **locked** tile → rejected, snaps back.
- Drag a tile onto its **own** cell → no-op.
- Drag a tile onto the **rack** → returns to hand; rack tile is focused.
- After each drop, arrow keys resume from the expected place (dest cell or
  rack tile).
- Try all of the above during a round transition / upgrade dialog → the drag
  never starts.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  still green (this change does not touch sim/game logic).

## Files touched

- `scripts/board_cell.gd` — add `_get_drag_data`; extend `_can_drop_data`.
- `scripts/main.gd` — `can_move_board_tile`; route board tiles in
  `on_tile_dropped_on_cell`; add `_move_board_tile`; guard + focus in
  `on_tile_returned_to_rack`.

## Out of scope

- Moving **locked** tiles (forbidden for the round).
- Keyboard-driven move (this is a mouse feature; Backspace-return stays).
- Swap visual distinct from a plain move (reuse the existing pop).
- Any sim / `game_core.gd` change.
