# PLAY Button + Explicit Commit — Implementation Tasks

Slices `docs/play_button_spec.md` into ordered, vertical deliverables.
Implement **in order**. Each task compiles on its own and keeps the game
playable. Do not start a task until the previous one is done.

**Conventions (from `CLAUDE.md`):** snake_case names; structured logging at
state transitions with subsystem prefixes; no comments that restate code;
edit existing files only — no new files. Targets Godot 4.6.

Files: `scripts/main.gd`, `scripts/board_cell.gd` (Task 1);
`scenes/main.tscn`, `themes/win95.tres`, `scripts/main.gd` (Task 2).
Do **not** touch `tile.gd`, `rack.gd`, or anything under `scripts/sim/`
(`game_core.gd` already models explicit end-turn; see spec §7). No headless
test — verify by running the game.

---

## Task 1 — Make the turn end only on explicit commit (decouple placement)

**Goal:** Placing tiles stops auto-ending the turn. The player can place up to
`tiles_per_turn` tiles (the cap is now a hard limit on placement) and the turn
resolves only via the existing `END TURN` button / `confirm_turn` key. The
button's rename/restyle comes in Task 2 — this task is pure logic.

### 1a. `scripts/main.gd` — remove the auto-end

In `_place_tile_on_cell`, delete the trailing two lines:

```gdscript
	board.focus_cell(cursor)
	_update_hud()
	if pending_cells.size() >= RunState.tiles_per_turn:
		_on_end_turn_pressed()
```

so the function now ends:

```gdscript
	board.focus_cell(cursor)
	_update_hud()
```

### 1b. `scripts/main.gd` — placement-cap helper

Add next to `can_move_board_tile` (in the drag-and-drop section):

```gdscript
func can_place_pending_tile() -> bool:
	return pending_cells.size() < RunState.tiles_per_turn
```

### 1c. `scripts/board_cell.gd` — refuse rack drops at the cap

Replace the final `return is_empty()` line of `_can_drop_data`:

```gdscript
	return is_empty()              # rack-tile placement, unchanged
```

with:

```gdscript
	# rack-tile placement: empty cell AND under the per-turn placement cap
	if not is_empty():
		return false
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("can_place_pending_tile") and not main.can_place_pending_tile():
		return false
	return true
```

(The board-tile move/swap branch above is unchanged — moves don't touch the
count, so they stay free even at the cap.)

### 1d. `scripts/main.gd` — defensive cap guard on the drop route

In `on_tile_dropped_on_cell`, the rack branch currently reads:

```gdscript
	if not cell.is_empty():
		return
	_place_tile_on_cell(tile, cell)
```

Change to:

```gdscript
	if not cell.is_empty():
		return
	if not can_place_pending_tile():
		return
	_place_tile_on_cell(tile, cell)
```

### 1e. `scripts/main.gd` — same cap on the keyboard-place path

In `_try_place_letter_on_cursor`, after the empty-cell check:

```gdscript
	var cell := board.get_cell(cursor)
	if cell == null or not cell.is_empty():
		return
	if not can_place_pending_tile():
		return
	var tile := rack.find_tile_with_letter(letter)
```

### Verify
- Run the game. Place `tiles_per_turn` tiles — the turn does **not** auto-end;
  `Placed` reads e.g. `4 / 4`. Try to place another (drag or keyboard) → it's
  refused / snaps back. Return one to the rack → you can place again. Move /
  swap placed tiles freely. Press `END TURN` (or the confirm key) → the turn
  resolves exactly as before. Pressing it with nothing placed → still a no-op.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green (no sim/game-core change).

### App state after Task 1
Explicit commit works: placement is a hard cap, the turn ends only on the
button/key. The button still says `END TURN` and looks unchanged.

---

## Task 2 — The `PLAY` button: rename, enlarge, inset, emphasize, gray-out

**Goal:** Turn the cramped `END TURN` control into a clear, prominent `PLAY`
button with the Win95 default-button look, inset from the window edge, that
grays out until there's something to commit.

### 2a. `themes/win95.tres` — `PlayButton` variation

Add a new StyleBoxFlat sub-resource (alongside the other `SB_*` blocks):

```
[sub_resource type="StyleBoxFlat" id="SB_PlayNormal"]
content_margin_left = 6.0
content_margin_top = 3.0
content_margin_right = 6.0
content_margin_bottom = 3.0
bg_color = Color(0.7529, 0.7529, 0.7529, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.039, 0.039, 0.039, 1)
anti_aliasing = false
```

Then, in the `[resource]` block, add the variation entries (the
`SubResource` ids `SB_RaisedPressed`, `SB_Disabled`, `SB_Focus` already exist):

```
PlayButton/base_type = &"Button"
PlayButton/colors/font_color = Color(0, 0, 0, 1)
PlayButton/colors/font_disabled_color = Color(0.5019, 0.5019, 0.5019, 1)
PlayButton/colors/font_hover_color = Color(0, 0, 0, 1)
PlayButton/colors/font_pressed_color = Color(0, 0, 0, 1)
PlayButton/font_sizes/font_size = 16
PlayButton/styles/normal = SubResource("SB_PlayNormal")
PlayButton/styles/hover = SubResource("SB_PlayNormal")
PlayButton/styles/pressed = SubResource("SB_RaisedPressed")
PlayButton/styles/disabled = SubResource("SB_Disabled")
PlayButton/styles/focus = SubResource("SB_Focus")
```

### 2b. `scenes/main.tscn` — rename, size, variation

On the `EndTurnButton` node:

```
[node name="EndTurnButton" type="Button" parent="WinFrame/InnerVBox/GameArea/HUD" unique_id=532300904]
unique_name_in_owner = true
layout_mode = 2
text = "END TURN"
```

becomes:

```
[node name="EndTurnButton" type="Button" parent="WinFrame/InnerVBox/GameArea/HUD" unique_id=532300904]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 32)
layout_mode = 2
theme_type_variation = &"PlayButton"
text = "PLAY"
```

Keep the node **name** `EndTurnButton` and `unique_id` — only `text` and the
styling change, so `%EndTurnButton` in `main.gd` still resolves.

### 2c. `scenes/main.tscn` — inset the HUD row + separation

Wrap the existing `HUD` HBox in a `MarginContainer` so the row sits off the
window border, and add inter-item separation.

1. Insert a `MarginContainer` as a child of `GameArea`, **before** `Board`,
   with the four `theme_override_constants/margin_*` set to inset the row:

```
[node name="HudMargin" type="MarginContainer" parent="WinFrame/InnerVBox/GameArea"]
layout_mode = 2
theme_override_constants/margin_left = 10
theme_override_constants/margin_right = 10
```

2. Reparent `HUD` under it: change the `HUD` node's `parent` from
   `WinFrame/InnerVBox/GameArea` to `WinFrame/InnerVBox/GameArea/HudMargin`,
   and update every descendant's `parent` path the same way
   (`ScoreLabel`, `TilesLeftLabel`, `EndTurnButton`:
   `…/GameArea/HUD` → `…/GameArea/HudMargin/HUD`).

3. On the `HUD` node, add separation:

```
theme_override_constants/separation = 12
```

Node order under `GameArea` must stay `HudMargin` → `Board` → `RackRow`
(the HUD reads above the board). The labels/button keep
`unique_name_in_owner`, so `%ScoreLabel` / `%TilesLeftLabel` /
`%EndTurnButton` in `main.gd` still resolve after the reparent.

### 2d. `scripts/main.gd` — gray out until actionable

At the **end** of `_update_hud`, add:

```gdscript
	end_turn_button.disabled = pending_cells.is_empty() \
		or RunState.is_transitioning or RunState.is_upgrading or _discard_busy
```

### Verify
- Run the game. The HUD reads `… | PLAY`, with `PLAY` clearly larger, framed
  with the thin black default-button outline, and sitting ~10px off the right
  window border (not glued to it). With nothing placed it's grayed/disabled;
  place a tile and it lights up; pressing it commits the turn. During a round
  transition / upgrade dialog it's disabled. Score labels still read correctly
  and the board/rack layout is unchanged.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → still green.

### App state after Task 2
Full feature: a prominent, period-correct `PLAY` button that only enables when
there's a move to commit, paired with the explicit-commit flow from Task 1.

---

## Done criteria (all tasks)

- Placing tiles never auto-ends the turn; the turn resolves only via the
  `PLAY` button or the `confirm_turn` key.
- The per-turn placement quota is a hard cap: drops/keys past it are refused
  (snap back); returning a tile frees a slot. Move/swap of placed tiles stays
  unrestricted.
- `PLAY` is rename + ~120×32 + Win95 default-button outline + 16px font, inset
  ~10px from the window edge, and disabled (gray) when nothing is pending or
  during a transition/upgrade/discard.
- Committing with no valid word still locks/scores-0/spends the turn
  (unchanged). The debug autoplay still ends turns (explicit calls).
- `run_tests.gd` stays green; `game_core.gd` and `scripts/sim/` untouched.
