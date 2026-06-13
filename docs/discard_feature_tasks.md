# Discard Feature — Implementation Plan

Implements `docs/discard_feature_design.md`. Read that for the *why*;
this file is the *what, in what order*. Built for a less-sophisticated
agent (haiku): each slice is small, leaves the game compiling and
playable, and gives exact code or precise steps.

## How to work this file

- Do slices **in order**; commit after each. One commit per slice,
  `feat:`/`fix:` headline + 2–5 lines.
- Conventions (CLAUDE.md): tabs in GDScript; snake_case; log state
  transitions with the `[Discard]` prefix; the project theme is the
  default (use `theme_type_variation`, don't set `theme`); no comments
  that restate code; if you change discard/draw/modifier logic that the
  sim mirrors, update `game_core.gd` in the SAME slice.
- **No `godot` binary here** — the human runs the game and the sim
  tests. After a sim slice, the human runs:
  `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
- **Don't touch** scoring, progression, or the upgrade system except
  where stated.

## Confirmed code facts

- `RACK_SIZE = 7`. Rack tiles are `Tile` nodes in `%Rack`
  (`HBoxContainer`), tracked in `rack.tiles_in_hand`. `Tile.location` is
  `"rack"`/`"board"`. Modifier pass is `rack.refill()` lines 21–25.
- `main.gd` keyboard cursor = Godot focus on a `BoardCell`; arrows are
  handled in `_unhandled_input`; `_move_cursor` clamps to the board;
  letter keys place at the cursor. A pending board tile is
  `cell.current_tile != null` (locked = `null` + `locked_letter`).
- Board placement reparents the tile to `main` and hides it
  (`_place_tile_on_cell`); the cell shows the letter via its label.
- `main` is in group `"main"`; drop targets route through it
  (`on_tile_dropped_on_cell`, `on_tile_returned_to_rack`).
- Sim: `game_core.gd` mirrors everything; `simulator.gd::_run_game`
  calls `strategy.pick_moves(core)` each turn; tests auto-discover
  `test_*` methods in `scripts/sim/tests/test_game_core.gd`.

---

## Slice 1 — `RunState` discard budget

**File:** `scripts/run_state.gd`.

Add the constant and signal near the others (after line 12 / line 7),
and a state var after `is_upgrading`:

```gdscript
const DISCARDS_PER_ROUND: int = 3
```
```gdscript
signal discards_left_changed(discards_left: int)
```
```gdscript
var discards_left: int = DISCARDS_PER_ROUND
```

Add a method:

```gdscript
func use_discard() -> void:
	discards_left -= 1
	print("[Discard] used — %d left" % discards_left)
	discards_left_changed.emit(discards_left)
```

In `reset()` (after `is_upgrading = false`) and at the end of
`_advance_round()` (after `tiles_per_turn += 1` block, before the prints
are fine), set and announce the budget:

```gdscript
	discards_left = DISCARDS_PER_ROUND
	discards_left_changed.emit(discards_left)
```

**Verify:** game still boots and plays unchanged.

---

## Slice 2 — Rack discard mechanic (instant, no UI yet)

**File:** `scripts/rack.gd`.

1. **Factor the modifier pass.** Replace the body of `refill()` lines
   21–25 (the two `for` loops) with a call:

```gdscript
func refill() -> void:
	while tiles_in_hand.size() < RACK_SIZE:
		var letter := _draw_random_letter()
		var tile := TILE_SCENE.instantiate() as Tile
		tile.letter = letter
		add_child(tile)
		tiles_in_hand.append(tile)
	_apply_modifiers()

func _apply_modifiers() -> void:
	for tile in tiles_in_hand:
		if RunState.letter_modifiers.has(tile.letter):
			tile.set_modifier(RunState.letter_modifiers[tile.letter])
	for mod in RunState.modifier_build.keys():
		_ensure_modifier_count_in_rack(mod, RunState.modifier_build[mod])
```

2. **Add the excluding draw:**

```gdscript
func _draw_random_letter_excluding(excluded: String) -> String:
	var bag: Array[String] = []
	for letter in GameData.LETTER_DISTRIBUTION.keys():
		if letter == excluded:
			continue
		for i in GameData.LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[randi() % bag.size()]
```

3. **Add the swap.** Removes the old tile from the rack data + HBox
   (does NOT free it — the caller animates/frees it), draws a
   replacement in the same slot, re-applies modifiers, returns both
   tiles so the caller can animate:

```gdscript
func discard_replace(old_tile: Tile) -> Dictionary:
	var idx := tiles_in_hand.find(old_tile)
	if idx == -1:
		return {}
	var old_letter := old_tile.letter
	tiles_in_hand.remove_at(idx)
	if old_tile.get_parent() == self:
		remove_child(old_tile)
	var new_tile := TILE_SCENE.instantiate() as Tile
	new_tile.letter = _draw_random_letter_excluding(old_letter)
	add_child(new_tile)
	move_child(new_tile, idx)
	tiles_in_hand.insert(idx, new_tile)
	_apply_modifiers()
	return {"old_tile": old_tile, "new_tile": new_tile, "slot": idx}
```

**Verify:** game compiles and plays unchanged (nothing calls
`discard_replace` yet).

---

## Slice 3 — Recycle Bin + mouse discard (instant) + indicator

**Goal:** drag a rack tile onto the bin → it's discarded, a replacement
appears, the count drops, the bin grays at 0. No animation yet.

### 3a. New `scripts/recycle_bin.gd`

```gdscript
class_name RecycleBin
extends Control

const BIN_SIZE := Vector2(52.0, 60.0)
const C_LIGHT := Color("#FFFFFF")
const C_DARK  := Color("#0A0A0A")
const C_BODY  := Color("#C0C0C0")
const C_GRAY  := Color("#808080")
const C_NAVY  := Color(0, 0, 0.5019, 1.0)

func _ready() -> void:
	custom_minimum_size = BIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	RunState.discards_left_changed.connect(func(_n: int) -> void: queue_redraw())
	queue_redraw()

func _enabled() -> bool:
	if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading:
		return false
	return RunState.discards_left > 0

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _enabled() and data is Tile and (data as Tile).location == "rack"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("discard_rack_tile"):
		main.discard_rack_tile(data as Tile)

func _draw() -> void:
	var enabled := RunState.discards_left > 0
	var body := C_BODY if enabled else C_GRAY
	# Simple Win95 bin: lid + trapezoid body with ribs.
	var w := 28.0
	var x := (size.x - w) * 0.5
	# lid
	draw_rect(Rect2(x - 3.0, 6.0, w + 6.0, 5.0), body)
	draw_rect(Rect2(x - 3.0, 6.0, w + 6.0, 5.0), C_DARK, false, 1.0)
	# body
	var body_rect := Rect2(x, 12.0, w, 30.0)
	draw_rect(body_rect, body)
	draw_rect(body_rect, C_DARK, false, 1.0)
	for i in 3:
		var rx := x + 6.0 + i * 8.0
		draw_line(Vector2(rx, 15.0), Vector2(rx, 39.0), C_DARK)
	# count
	var font := get_theme_default_font()
	if font:
		var t := str(RunState.discards_left)
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, Vector2((size.x - ts.x) * 0.5, 56.0), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_NAVY if enabled else C_GRAY)
```

### 3b. Add the bin to `scenes/main.tscn`

Replace the `[node name="Rack" ...]` block (lines 141–148) with a
`RackRow` HBox that holds the rack and the bin side by side. `%Rack`
keeps working because it's a unique name (path-independent). Append at
the end of the file:

```
[node name="RackRow" type="HBoxContainer" parent="WinFrame/InnerVBox/GameArea"]
layout_mode = 2
size_flags_horizontal = 4
alignment = 1
theme_override_constants/separation = 16

[node name="Rack" type="HBoxContainer" parent="WinFrame/InnerVBox/GameArea/RackRow"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 56)
layout_mode = 2
alignment = 1
script = ExtResource("3_rack")

[node name="RecycleBin" type="Control" parent="WinFrame/InnerVBox/GameArea/RackRow"]
unique_name_in_owner = true
layout_mode = 2
script = ExtResource("7_bin")
```

Add the script ext_resource near the top (with the others, line ~5):

```
[ext_resource type="Script" path="res://scripts/recycle_bin.gd" id="7_bin"]
```

(Leave the `Board` node and everything else untouched. The old `Rack`
block is gone — it now lives under `RackRow`.)

### 3c. `main.gd` — the discard entry point

Add `@onready var recycle_bin: RecycleBin = %RecycleBin` near the other
`@onready`s. Add the method (instant version for now):

```gdscript
func discard_rack_tile(tile: Tile) -> void:
	if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading:
		return
	if RunState.discards_left <= 0:
		return
	if not rack.tiles_in_hand.has(tile):
		return
	var result := rack.discard_replace(tile)
	if result.is_empty():
		return
	(result["old_tile"] as Tile).queue_free()
	RunState.use_discard()
	print("[Discard] rack discard — %s, %d left" % [tile.letter, RunState.discards_left])
```

**Verify (human):** drag a rack tile onto the bin → tile is replaced by
a different letter (never the same), count drops 3→2→1→0, bin grays out
and rejects drops at 0. Resets to 3 each new round.

---

## Slice 4 — Unified board+rack cursor (navigation only)

**Goal:** keyboard focus can move between board and rack. No discard via
keyboard yet.

### 4a. `scripts/tile.gd` — make tiles focusable + cyan highlight

In `_ready()` add:

```gdscript
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
```

At the very end of `_draw()` add the cursor ring:

```gdscript
	if has_focus():
		draw_rect(Rect2(0, 0, w, h), Color("#00FFFF"), false, 2.0)
```

(The upgrade wizard sets its embedded tiles to `FOCUS_NONE`, so they
never show this — no conflict.)

### 4b. `main.gd` — navigation (derived from the focus owner)

**No zone state is kept.** The active zone is simply whatever holds
focus right now (`get_viewport().gui_get_focus_owner()`). This avoids a
desync where a mouse-click focuses a rack tile while a `_focus_zone`
var still says `"board"`. `cursor` already holds the last focused board
cell (set in `_on_cell_focused` — leave that function as-is), so
returning to the board is just `board.focus_cell(cursor)`.

Rewrite the arrow-handling part of `_unhandled_input` (keep the gating
early-return at the top). Replace the
`if event.is_action_pressed("ui_left") …` chain with:

```gdscript
	var focused = get_viewport().gui_get_focus_owner()
	var rack_idx := rack.tiles_in_hand.find(focused)

	if rack_idx != -1:
		# --- in the rack ---
		if event.is_action_pressed("ui_left"):
			_focus_rack_index(rack_idx - 1); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_focus_rack_index(rack_idx + 1); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			board.focus_cell(cursor); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			get_viewport().set_input_as_handled()
		return

	# --- on the board ---
	if event.is_action_pressed("ui_left"):
		_move_cursor(Vector2i(-1, 0)); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_cursor(Vector2i(1, 0)); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_cursor(Vector2i(0, -1)); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if cursor.y >= Board.BOARD_SIZE - 1:
			_enter_rack(); get_viewport().set_input_as_handled()
		else:
			_move_cursor(Vector2i(0, 1)); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm_turn"):
		_on_end_turn_pressed()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode >= KEY_A and key_event.keycode <= KEY_Z:
			_try_place_letter_on_cursor(char(key_event.keycode))
```

Add the helpers (stateless — they read/grab focus directly):

```gdscript
func _enter_rack() -> void:
	_focus_rack_index(clampi(cursor.x, 0, rack.tiles_in_hand.size() - 1))

func _focus_rack_index(idx: int) -> void:
	if rack.tiles_in_hand.is_empty():
		return
	rack.tiles_in_hand[clampi(idx, 0, rack.tiles_in_hand.size() - 1)].grab_focus()
```

Do NOT add any `_focus_zone` / `_rack_cursor` / `_last_board_cursor`
state, and do NOT modify `_on_cell_focused`.

**Verify (human):** from the board, Down at the bottom row jumps into the
rack (cyan ring on a tile); Left/Right move along the rack and clamp at
the ends; Up returns to the board where you left it. Clicking a rack
tile with the mouse and then pressing arrows also navigates the rack
(no desync). Typing a letter while in the rack does nothing.

---

## Slice 5 — Delete/Backspace (discard + return to hand), instant

**Goal:** context-sensitive Delete. Rack tile → discard; board pending
tile → return to hand (instant; animation in Slice 6).

In `_unhandled_input`, **right after the gating early-return**, add the
Delete handler (so it works in either zone):

```gdscript
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
		_handle_delete()
		get_viewport().set_input_as_handled()
		return
```

Add the handler — it uses the *actual* focus owner so it's robust:

```gdscript
func _handle_delete() -> void:
	var focused = get_viewport().gui_get_focus_owner()
	var rack_idx := rack.tiles_in_hand.find(focused)
	if rack_idx != -1:
		discard_rack_tile(focused as Tile)
		_focus_rack_index(rack_idx)   # focus the replacement in the same slot
	elif focused is BoardCell:
		var cell := focused as BoardCell
		if cell.current_tile != null:
			_return_pending_tile(cell.current_tile)

func _return_pending_tile(tile: Tile) -> void:
	print("[Discard] board tile returned — %s" % tile.letter)
	on_tile_returned_to_rack(tile)
	board.focus_cell(cursor)
```

**Verify (human):** Delete/Backspace on a focused rack tile discards it
(respects the 3-limit and gray bin); Delete on a board cell holding an
unlocked pending tile sends it back to the rack; Delete on a locked or
empty cell does nothing.

---

## Slice 6 — Animations + re-entrancy lock

**Goal:** discard flies to the bin, replacement pops in, board returns
fly back. Lock against overlapping animations.

### 6a. Animation overlay + full input lock

In `main.gd`, add `var _discard_busy: bool = false` and
`var _anim_layer: CanvasLayer` near the top, and create the overlay in
`_ready()` (after `add_to_group("main")`):

```gdscript
	_anim_layer = CanvasLayer.new()
	_anim_layer.layer = 40
	add_child(_anim_layer)
```

`_discard_busy` is a **full input gate** for the ~0.25s an animation
runs — this is what prevents the fly-back limbo bug (turn-end mid-flight
over-filling the rack) and double-spends. Wire it into the existing
guards:

- `_unhandled_input` early-return becomes
  `if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading or _discard_busy: return`
- `on_tile_dropped_on_cell` and `on_tile_returned_to_rack`: add
  `or _discard_busy` to their guard conditions.
- `discard_rack_tile` and `_return_pending_tile` each begin with
  `if _discard_busy: return` (shown below) — the backstop for both
  mouse and keyboard.

Autoplay (Slice 9) calls game functions directly, not through
`_unhandled_input`, so it must poll-wait on `_discard_busy` itself.

### 6b. Discard flies to the bin

Change `discard_rack_tile` so it animates the old tile instead of
`queue_free()`-ing it immediately:

```gdscript
func discard_rack_tile(tile: Tile) -> void:
	if _discard_busy: return
	if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading: return
	if RunState.discards_left <= 0: return
	if not rack.tiles_in_hand.has(tile): return
	var start := tile.global_position
	var result := rack.discard_replace(tile)
	if result.is_empty(): return
	RunState.use_discard()
	print("[Discard] rack discard — %s, %d left" % [tile.letter, RunState.discards_left])
	_discard_busy = true
	var old_tile := result["old_tile"] as Tile
	var new_tile := result["new_tile"] as Tile
	_anim_layer.add_child(old_tile)
	old_tile.global_position = start
	old_tile.pivot_offset = old_tile.size * 0.5
	var bin_centre := recycle_bin.global_position + recycle_bin.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old_tile, "global_position", bin_centre - old_tile.size * 0.1, 0.25)
	tw.tween_property(old_tile, "scale", Vector2(0.2, 0.2), 0.25)
	tw.tween_property(old_tile, "modulate:a", 0.0, 0.25)
	# new tile pop-in
	new_tile.pivot_offset = new_tile.size * 0.5
	new_tile.scale = Vector2(0.1, 0.1)
	create_tween().tween_property(new_tile, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		old_tile.queue_free()
		_discard_busy = false
	)
```

Re-focus is owned by `_handle_delete` (keyboard): it calls
`_focus_rack_index(rack_idx)` right after `discard_rack_tile`, and the
replacement is already in the rack at that slot. A mouse (bin) discard
leaves focus where it was. No focus state is involved.

### 6c. Board return flies back

Rewrite `_return_pending_tile` to animate from the board cell to the
rack slot, then finalize via the existing reparent logic:

```gdscript
func _return_pending_tile(tile: Tile) -> void:
	if _discard_busy: return
	_discard_busy = true
	print("[Discard] board tile returned — %s" % tile.letter)
	var prev_cell := board.get_cell(tile.board_pos)
	var start := prev_cell.global_position if prev_cell else tile.global_position
	if prev_cell:
		prev_cell.clear_pending()
		pending_cells.erase(prev_cell)
	tile.location = "rack"
	tile.board_pos = Vector2i(-1, -1)
	tile.visible = true
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	_anim_layer.add_child(tile)
	tile.global_position = start
	# Target: where the tile will sit after joining the rack (approx the
	# rack's right edge). Tween there, then hand off to the rack.
	var target := rack.global_position + Vector2(rack.size.x, 0)
	var tw := create_tween()
	tw.tween_property(tile, "global_position", target, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_anim_layer.remove_child(tile)
		rack.add_child(tile)
		rack.tiles_in_hand.append(tile)
		_update_hud()
		_discard_busy = false
		board.focus_cell(cursor)
	)
```

(This replaces the Slice 5 instant version. Note it inlines the
`on_tile_returned_to_rack` finalize so the tile joins the rack only when
the tween lands.)

**Verify (human):** discard animates the tile shrinking into the bin
with the replacement popping into the same slot; Delete on a board
pending tile flies it back to the rack; you can't start a second
discard/return while one is animating.

---

## Slice 7 — `game_core.gd` sim parity

**File:** `scripts/sim/game_core.gd`. Mirror the live mechanic exactly,
deterministically (seeded `rng`, never `randi()`).

1. Add constants/state near the others:

```gdscript
const DISCARDS_PER_ROUND: int = 3
```
```gdscript
var discards_left: int = DISCARDS_PER_ROUND
```

2. Factor the modifier pass like the live rack. Replace the two `for`
   loops in `refill_rack()` (lines 136–140) with `_apply_rack_modifiers()`
   and add:

```gdscript
func _apply_rack_modifiers() -> void:
	for i in range(rack.size()):
		if letter_modifiers.has(rack[i]["letter"]):
			rack[i]["modifier"] = letter_modifiers[rack[i]["letter"]]
	for mod in modifier_build.keys():
		_ensure_modifier_count_in_rack(mod, modifier_build[mod])
```

3. Add the excluding draw + discard:

```gdscript
func _draw_letter_raw_excluding(excluded: String) -> String:
	var bag: Array[String] = []
	for letter in LETTER_DISTRIBUTION.keys():
		if letter == excluded:
			continue
		for _i in LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[rng.randi() % bag.size()]

func discard_tile(letter: String) -> bool:
	if discards_left <= 0:
		return false
	for i in rack.size():
		if rack[i]["letter"] == letter:
			rack.remove_at(i)
			var new_letter := _draw_letter_raw_excluding(letter)
			rack.insert(i, {"letter": new_letter, "modifier": MOD_NONE})
			_apply_rack_modifiers()
			discards_left -= 1
			return true
	return false
```

4. Reset the budget per round: in `_advance_round()` (after
   `tiles_per_turn += 1`) add `discards_left = DISCARDS_PER_ROUND`.

**Verify:** human runs `run_tests.gd` — existing TC/TS/TSM all pass.

---

## Slice 8 — Strategy hook, simulator wiring, demo strategy, tests

1. **`scripts/sim/strategy.gd`** — add the non-breaking hook:

```gdscript
func pick_discards(core) -> Array:
	return []
```

2. **`scripts/sim/simulator.gd`** — in `_run_game`, at the **start of
   the while loop** (before `strategy.pick_moves`):

```gdscript
		var discards = strategy.pick_discards(core)
		for d in discards:
			if core.discards_left <= 0:
				break
			core.discard_tile(d)
```

3. **New `scripts/sim/strategies/discard_word_search.gd`** — extends the
   word_search baseline. Heuristic = **discard-when-stuck (C), with
   vowel-balance (B) choosing which tile**: only spend a discard when the
   rack can't form any valid word this turn, then ditch the least-useful
   tile by vowel balance.

```gdscript
extends "res://scripts/sim/strategies/word_search_strategy.gd"

const VOWELS := {"A": true, "E": true, "I": true, "O": true, "U": true}

func get_name() -> String:
	return "discard_word_search"

func pick_discards(core) -> Array:
	if core.discards_left <= 0:
		return []
	# (C) Only discard when stuck. word_search returns a multi-tile
	# placement only when it matched the dictionary; a 1-tile random
	# fallback is the "no word found" signal. (pick_moves is read-only.)
	if pick_moves(core).size() >= 2:
		return []
	# (B) Stuck -> ditch one least-useful tile to fish for a better hand.
	var letter := _least_useful_letter(core)
	return [letter] if letter != "" else []

func _least_useful_letter(core) -> String:
	var letters: Array = core.rack_letters()
	if letters.is_empty():
		return ""
	var vowels := 0
	for l in letters:
		if VOWELS.has(l):
			vowels += 1
	var want_drop_vowel := vowels >= 5     # vowel-flooded
	var want_keep_vowel := vowels <= 1     # vowel-starved
	var best := ""
	var best_freq := 999
	for l in letters:
		var is_vowel: bool = VOWELS.has(l)
		if want_keep_vowel and is_vowel:
			continue
		if want_drop_vowel and not is_vowel:
			continue
		var freq: int = core.LETTER_DISTRIBUTION.get(l, 0)
		if freq < best_freq:
			best_freq = freq
			best = l
	return best if best != "" else letters[0]
```

   Notes: the `pick_moves(core).size() >= 2` check is the "real word vs
   random fallback" signal. If it proves too coarse in testing, the
   approved fallback is pure vowel-balance (B): drop the stuck-gate and
   always rebalance when `discards_left > 0`. Heuristic is tunable; what
   matters is it exercises the hook so a batch run can compare it to
   `word_search`. (Costs one extra read-only `pick_moves` per turn,
   within the strategy's existing 50ms budget.)

4. **Register the strategy** in `scripts/sim/sim_runner.gd` (mirror an
   existing case like `word_search`) **and** in `main.gd::_build_strategy`
   — live autoplay drives discards too (Slice 9), so
   `--autoplay=discard_word_search` will visibly use the bin.

5. **Tests** — append to `scripts/sim/tests/test_game_core.gd` (they're
   auto-discovered by the `test_` prefix). Cover the three key cases:

```gdscript
func test_discard_excludes_same_letter() -> bool:
	var core = GameCore.new(123)
	var before: String = core.rack[0]["letter"]
	if not core.discard_tile(before):
		push_error("discard_excludes: discard failed"); return false
	# the replacement at the same slot must not be the discarded letter
	if core.rack[0]["letter"] == before:
		push_error("discard_excludes: redrew the same letter"); return false
	return true

func test_discard_budget_resets_each_round() -> bool:
	var core = GameCore.new(7)
	core.discards_left = 0
	# force a round advance
	core.round_score = core.target_score
	core.end_turn([])
	if core.discards_left != GameCore.DISCARDS_PER_ROUND:
		push_error("discard_reset: expected %d, got %d" % [GameCore.DISCARDS_PER_ROUND, core.discards_left]); return false
	return true

func test_discard_deterministic_under_seed() -> bool:
	var a = GameCore.new(999)
	var b = GameCore.new(999)
	var la: String = a.rack[0]["letter"]
	a.discard_tile(la)
	b.discard_tile(b.rack[0]["letter"])
	if a.rack[0]["letter"] != b.rack[0]["letter"]:
		push_error("discard_determinism: same seed diverged"); return false
	return true
```

**Verify:** human runs `run_tests.gd` — all pass including the three new
cases. Optionally run a batch comparing `word_search` vs
`discard_word_search` to confirm discards change scores.

---

## Slice 9 — Live autoplay discards

**Goal:** the bot uses the Recycle Bin in the real game, so the whole
feature gets end-to-end coverage. The headless batch (Slice 8) stays the
*measurement*; this adds the *visible* layer.

1. **`_AutoplayAdapter` gains `discards_left`.** Add the field and set it
   in `refresh()` from `RunState.discards_left`:

```gdscript
	var discards_left: int = 0
	# inside refresh():
	discards_left = RunState.discards_left
```

   Everything else `pick_discards` needs — `rack`, `rack_letters`,
   `board`, `is_cell_empty`, `rng`, `tiles_per_turn`, `BOARD_SIZE`,
   `LETTER_DISTRIBUTION` — the strategy reads via the adapter or its own
   consts; the inherited `pick_moves` is unchanged. (Note: the adapter
   does not need `LETTER_DISTRIBUTION` if the strategy reads it from
   `GameCore`/its own table — keep the strategy's `core.LETTER_DISTRIBUTION`
   access working by exposing it on the adapter as a const/getter, or
   switch the strategy to a local table; pick whichever is simpler.)

2. **Discard phase in `_run_autoplay`.** Each turn, after
   `adapter.refresh(...)` and before placing, run discards through the
   real animated path and poll-wait the lock:

```gdscript
		adapter.refresh(RunState.tiles_per_turn)
		for letter in strategy.pick_discards(adapter):
			if RunState.discards_left <= 0:
				break
			var t := rack.find_tile_with_letter(letter)
			if t == null:
				continue
			discard_rack_tile(t)
			while _discard_busy:
				await get_tree().create_timer(0.05).timeout
			await get_tree().create_timer(AUTOPLAY_STEP_MS / 1000.0).timeout
		adapter.refresh(RunState.tiles_per_turn)
```

   (Place this just before the existing `var moves = strategy.pick_moves(...)`
   line, inside the same `_autoplay_active`/`is_*` guarded loop body.
   Strategies that don't override `pick_discards` return `[]`, so this is
   a no-op for them.)

3. **Verify (human):** run `--autoplay=discard_word_search` in the real
   game — when the bot's hand is stuck it drags a tile to the bin (fly
   animation, count drops), then plays. Other strategies are unaffected.

---

## Slice 10 — Docs

Append a short "Discard parity" section to `scripts/sim/README.md`:
- `discard_tile(letter)` mirrors live: weighted draw excluding the
  discarded letter, modifiers re-applied, deterministic via seeded
  `rng`; `discards_left` + `DISCARDS_PER_ROUND` reset each round.
- The `pick_discards(core)` strategy hook (default empty) is applied at
  the start of each turn in `simulator.gd`, capped by `discards_left`.
- New strategy `discard_word_search`; new tests
  `test_discard_excludes_same_letter`,
  `test_discard_budget_resets_each_round`,
  `test_discard_deterministic_under_seed`.

**Verify:** `run_tests.gd` green; commit and push the branch.

---

## Out of scope (do NOT build)

Discarding board-pending tiles directly, right-click-to-discard, audio,
turn-mechanics rebalance, multi-tile discard. See the design doc's
"Out of scope" section.
