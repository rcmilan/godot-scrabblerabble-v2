# Discard Feature — Design Specification

Lets the player throw away individual rack tiles to draw replacements,
a limited number of times per round. Settled in design review
(2026-06-13). This is the **design spec**; a separate task doc will
break it into implementation slices for the coding agent.

## Summary

- The player can **discard one rack tile at a time**; each discard
  **immediately draws one replacement tile**, so the rack stays full.
- A discard is a **free action** — it does NOT consume a turn.
- Limited to **`DISCARDS_PER_ROUND` (default 3) per round**, resetting
  each round. The limit is a single configurable constant.
- Triggered by **mouse** (drag a tile onto a Recycle Bin) or
  **keyboard** (Delete/Backspace on a focused rack tile).
- Keyboard gains a **unified board+rack cursor**; Delete/Backspace is
  context-sensitive (rack tile → discard; board pending tile → return
  to hand).
- Every discard/return is **animated**.
- The **simulator** can model strategic discards via a new strategy
  hook, with full `game_core.gd` parity.

## 1. Core rules

- **Discard target:** only tiles currently in the rack
  (`Tile.location == "rack"`). A tile already placed on the board
  (pending) must be returned to the rack first (see §4.3 — Delete on a
  board tile does exactly this).
- **Modifier tiles (2x/3x) are discardable** with no special
  restriction. Note the consequence: because `refill()`'s modifier pass
  re-applies `letter_modifiers` and re-runs the `modifier_build`
  "guarantee one 2x" promotion, discarding a modifier tile often won't
  actually shed the modifier — it reappears on the replacement or via
  re-promotion. This is intended, not a bug.
- **Discarding is allowed while pending tiles sit on the board** — it's
  independent of in-progress placements.
- **Free action:** no turn is consumed; `turns_left` and pending
  placements are untouched.
- **Per-round budget:** `DISCARDS_PER_ROUND` (default 3), resets every
  round.

> The player is separately considering a turn-mechanics rebalance after
> this feature. Keep the discard budget fully decoupled from the turn
> system so that rebalance stays independent.

## 2. Replacement draw

On discard: remove the tile, then draw **one** replacement.

- **Same weighted distribution** as a normal draw
  (`rack._draw_random_letter` / `GameData.LETTER_DISTRIBUTION`).
- **"Cannot redraw the same letter":** the replacement draw **excludes
  the discarded tile's letter** from the weighted bag for that single
  draw (avoids the frustration of discarding a letter and immediately
  getting it back; widens play options). Only that one letter is
  excluded — other duplicates in the rack are still allowed.
- **Modifiers re-applied exactly like a refill:** after drawing, apply
  `letter_modifiers` to the new tile (if its letter is modified) and
  re-run the `modifier_build` guarantee. Examples: discard a modified
  **A** → may draw an unmodified **B** or a modified **C**; discard an
  unmodified **D** → may draw a modified **E** or an unmodified **F**;
  never another **A**/**D** on that draw.
- Because of the no-repeat rule, discard **cannot** simply call
  `refill()` (which could redraw the letter). It needs a parameterized
  draw helper, e.g. `_draw_random_letter_excluding(letter)`, followed by
  the same modifier-application pass `refill()` uses (rack.gd lines
  21–25). Factor that modifier pass into a shared method so discard and
  refill stay identical.

## 3. State & configuration (`RunState`)

Mirror the `turns_left` pattern:

- `const DISCARDS_PER_ROUND: int = 3` — the single configurable knob.
- `var discards_left: int = DISCARDS_PER_ROUND`
- `signal discards_left_changed(discards_left: int)`
- `func use_discard()` — decrements `discards_left`, emits
  `discards_left_changed`. (Callers check availability first.)
- Reset `discards_left = DISCARDS_PER_ROUND` in **both** `reset()` and
  `_advance_round()` (same lifecycle as turns).

## 4. Interaction

### 4.1 Mouse — the Recycle Bin

- A **Win95 Recycle Bin** drop zone lives near the rack. Drag a rack
  tile onto it to discard.
- Reuses the existing drag-drop system: rack `Tile`s are already drag
  sources (`Tile._get_drag_data`). The bin is a new drop target
  implementing `_can_drop_data` (accept a `Tile` with
  `location == "rack"`, and `discards_left > 0`, and not gated) and
  `_drop_data` (trigger the discard, routed through `main` like board
  cells / rack do).
- The bin **doubles as the discards-remaining indicator** (§6).
- New node/script: `scripts/recycle_bin.gd` on a node added to
  `scenes/main.tscn` near the rack. The bin glyph is **custom-drawn**
  (no image assets exist) in a Win95 style; the exact art is an
  implementation detail. Right-click-to-discard is **out of scope** for
  v1 (trivial future add).

### 4.2 Keyboard — unified board+rack cursor

The keyboard cursor today is Godot focus on a `BoardCell`
(`main.gd::_unhandled_input` moves it). This feature extends it to span
the rack:

- **Rack tiles become focusable** (`focus_mode = FOCUS_ALL`) with a
  **cyan cursor highlight** matching the board cell cursor
  (`C_CURSOR = #00FFFF`), so it reads as the same cursor in both zones.
  Add the focus highlight to `tile.gd::_draw` gated on `has_focus()` —
  safe for the upgrade-wizard's embedded tiles, which are
  `focus_mode = NONE` and never focus.
- **Enter the rack:** pressing **Down** on the **bottom board row**
  moves focus into the rack (today Down clamps there and is a no-op, so
  it's free). Lands on the rack tile nearest the cursor's column:
  `index = min(cursor.x, rack_size - 1)`. If the rack is empty (only
  possible when `tiles_per_turn` is large enough to empty it), Down does
  nothing.
- **Return to the board:** **Up** from any rack tile returns focus to
  the **last board cell the cursor was on** (remembered).
- **Within the rack:** **Left/Right** move between tiles, **clamped at
  the ends** (no wrap).
- **Letter placement stays board-only** — typing a letter while focused
  in the rack does nothing (placement needs a board target).
- **No zone state is kept.** `main.gd` derives the active zone from the
  current focus owner (`get_viewport().gui_get_focus_owner()`): a focused
  rack tile means the rack, otherwise the board. This avoids a desync
  where a mouse click focuses a rack tile while a tracked zone still says
  "board". `cursor` already holds the last board cell, so Up from the
  rack is just `board.focus_cell(cursor)`.

### 4.3 Delete/Backspace — context-sensitive

Both **Delete** and **Backspace** act on the focused element:

- **Focused rack tile → discard** it (if `discards_left > 0` and not
  gated). Plays the discard animation (§5.1).
- **Focused board cell holding a pending (unlocked) tile**
  (`cell.current_tile != null`) → **return that tile to the rack**,
  playing the fly-back animation (§5.3). Locked cells
  (`current_tile == null`, `locked_letter != ""`) and empty cells →
  no-op.

> The board-return path is a keyboard counterpart to the existing
> drag-return (`rack._drop_data` + `main.on_tile_returned_to_rack`),
> plus the new fly-back animation.

## 5. Animations

All tween-based (no shaders), consistent with existing animation code
(`board_cell._play_place_animation`, round transition, etc.). Crucial
shared technique: **animate on an overlay so the rack `HBoxContainer`
never visibly shifts mid-animation** (the documented HBox
collapse/focus-steal quirk). Suggested overlay: a `CanvasLayer` below
the dialogs (e.g. layer ~40 — under game-over 50 / transition 60 / CRT
100) used as the animation stage; tiles reparent to it, animate in
screen space, then finalize.

### 5.1 Discard → Recycle Bin
The discarded tile reparents to the overlay at its current global
position and **flies toward the bin while shrinking and fading**
(tween position → bin global position, scale → ~0.2, alpha → 0,
~0.25s), then frees. Same animation for the mouse and keyboard paths.

### 5.2 Replacement tile — in the same slot
The replacement is inserted **at the discarded tile's slot index** in
the rack HBox (not appended at the end), so the rack shows no
gap-collapse. It **pops in** (scale 0→1, `TRANS_BACK` ease-out, reusing
the place-animation style). To avoid a gap during 5.1, insert the new
tile synchronously while the outgoing tile animates on the overlay.

### 5.3 Fly-back (board pending tile → rack)
The pending tile (currently invisible, parented to `main`, tracked by
`cell.current_tile`) is made visible on the overlay at the board cell's
global position and **flies to its rack slot** (tween global position,
~0.25s, ease-out), then joins the rack HBox via the existing
`on_tile_returned_to_rack` finalize logic.

## 6. Indicator & exhausted state

- The Recycle Bin **shows the remaining count** (`discards_left`),
  bound to the `discards_left_changed` signal.
- At **0 left**, the bin renders in a **Win95 disabled (grayed) look**
  and **rejects discards**: `_can_drop_data` returns false, and
  Delete-on-rack-tile becomes a no-op.
- **Feedback is visual only — no audio.** The project has no audio
  assets or sound system; there is no error beep. "Out of discards" is
  the grayed bin + no-op.

## 7. Input gating & re-entrancy

- Both discard paths and the keyboard return are blocked when
  `RunState.is_game_over or is_transitioning or is_upgrading` (mirror
  the `_unhandled_input` early-return and the drag-drop guards). The
  bin's `_drop_data`/`_can_drop_data` need the same guard.
- Blocked when `discards_left == 0` (discard only; the board-return is
  not limited).
- **Animation lock (full input gate):** a `_discard_busy` flag freezes
  ALL game input (cursor, placement, turn-end, further discards/returns)
  for the ~0.25s an animation runs — added to the `_unhandled_input`
  early-return and the drag-drop guards. This prevents the fly-back limbo
  bug (ending the turn while a returned tile is still in-flight, which
  would over-fill the rack) and any double-spend. Autoplay calls game
  functions directly, so it poll-waits on `_discard_busy` instead.
- Structured logging with a new prefix, e.g.
  `print("[Discard] rack discard — %s, %d left" % [letter, RunState.discards_left])`,
  `[Discard] board tile returned — %s` for the fly-back.

## 8. Simulation parity & strategy

The sim must model strategic discards (requirement: discards should let
a strategy score more).

### 8.1 `game_core.gd` parity
Mirror the live mechanics exactly:
- `const DISCARDS_PER_ROUND` + `var discards_left`, reset per round
  (in the sim's round-advance, matching `_advance_round`).
- `func discard_tile(letter) -> bool` — find a rack entry with that
  letter, remove it, draw a replacement from the **seeded** weighted bag
  **excluding that letter**, re-apply modifiers (same pass as the sim's
  refill), decrement `discards_left`. Deterministic via the existing
  seeded `rng` — never global `randi()`.
- Honor the same **no-repeat-letter** rule as live.

### 8.2 Strategy hook (non-breaking)
- Add to `strategy.gd`: `func pick_discards(core) -> Array: return []`
  (returns letters to discard). Default empty → existing strategies
  never discard → **all current baselines unchanged**.
- In `simulator.gd::_run_game`, at the **start of each turn**: call
  `strategy.pick_discards(core)`, apply each via `core.discard_tile()`
  while `core.discards_left > 0`, **then** run the existing
  `pick_moves` flow.
- Optionally record discard counts in `turn_log` for analysis.

### 8.3 Demonstrator strategy
- Add a **new** discard-aware strategy (e.g.
  `scripts/sim/strategies/discard_word_search.gd`) rather than editing
  an existing one — the existing strategies stay as controls so a batch
  run answers "do strategic discards score more?". Heuristic =
  **discard-when-stuck, vowel-balance which-tile**: only spend a discard
  when the rack can't form any valid word this turn (detected by reusing
  the parent word-search — a 1-tile random fallback is the "stuck"
  signal), then ditch the least-useful tile by vowel balance (drop a
  surplus vowel if flooded, a rare consonant if vowel-starved). This
  conserves the scarce 3-per-round budget instead of spending it
  reflexively. Tunable; the approved fallback if the stuck-detection is
  too coarse is pure vowel-balance every turn.

### 8.4 Tests
Add parity test cases (mirroring TC/TS/TSM style): the no-repeat-letter
rule, the per-round reset of `discards_left`, determinism under a fixed
seed, and modifier re-application on the replacement. Run
`scripts/sim/tests/run_tests.gd` and confirm existing cases still pass.

### 8.5 Live autoplay discards
Live autoplay also drives discards (so the bot visibly uses the bin and
the whole feature gets end-to-end coverage). The `_AutoplayAdapter`
gains a `discards_left` field (from `RunState`); `_run_autoplay` runs
`strategy.pick_discards(adapter)` each turn before placing, routing each
through the real animated `discard_rack_tile` and **poll-waiting on
`_discard_busy`** between actions. `discard_word_search` is registered in
both `sim_runner.gd` and `main.gd::_build_strategy`. The headless
`simulator.gd` batch remains the fast, animation-free *measurement*; live
autoplay is the *visual* demo.

## 9. Files touched / added

- **Edit:** `scripts/run_state.gd` (state, const, signal, resets),
  `scripts/rack.gd` (discard + excluding-draw helper, shared modifier
  pass), `scripts/tile.gd` (focusable + cyan focus highlight),
  `scripts/main.gd` (unified cursor, Delete routing, discard/return
  orchestration, animations, gating), `scenes/main.tscn` (Recycle Bin
  node + animation overlay), `scripts/sim/game_core.gd`,
  `scripts/sim/strategy.gd`, `scripts/sim/simulator.gd`,
  `scripts/sim/tests/run_tests.gd`, `scripts/sim/README.md`.
- **Add:** `scripts/recycle_bin.gd` (+ its node), one new sim strategy
  under `scripts/sim/strategies/`. No new top-level dirs.

## 10. Out of scope (possible follow-ups)

- Discarding board-pending tiles directly (must return-then-discard).
- Right-click-to-discard shortcut.
- Audio / sound effects (no audio system exists).
- Turn-mechanics rebalance (the player is considering it separately).
- Discarding more than one tile at once (individual only, by design).
