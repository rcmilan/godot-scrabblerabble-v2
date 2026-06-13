# Simulation System

This directory contains the headless game simulator for scrabblerabble.

## Duplication Notice

**`game_core.gd` is a deliberate duplicate of game logic from `main.gd` and `run_state.gd`.**

This was a conscious architectural choice to ship the simulator faster without refactoring the main game. The tradeoff is that scoring, progression, and tile-draw logic must be kept in sync across files.

### Duplicated Logic

The following constants and functions were copied verbatim:

**From `run_state.gd`:**
- `TURNS_PER_ROUND = 3`
- `INITIAL_TILES_PER_TURN = 4`
- `INITIAL_TARGET_SCORE = 20`
- Progression state: `current_round`, `round_score`, `target_score`, `turns_left`, `tiles_per_turn`
- Target curve calculation in `_advance_round()`

**From `main.gd`:**
- `WORD_BONUS_MULTIPLIER = 2`
- Scoring logic from `_calculate_turn_score()`
- Word extraction from `_extract_word_in_direction()`

**From `board.gd`:**
- `BOARD_SIZE = 8`
- Board indexing convention: `board[x][y]`

**From `rack.gd`:**
- `RACK_SIZE = 7`
- Weighted letter draw algorithm in `_draw_random_letter()`

**From `game_data.gd`:**
- `LETTER_DISTRIBUTION` for weighted random draws
- `LETTER_POINTS` for scoring
- `is_valid_word()` for dictionary validation
- `MOD_NONE` and `MOD_2X` constants for tile modifiers

**From `rack.gd` and `board_cell.gd`:**
- `_ensure_modifier_in_rack()` logic (deterministic promotion of lowest-value tile)
- Tile modifier visual rendering (via `board_modifiers` array)

### Future Refactoring

Once the simulator is proven useful, refactor `main.gd` and `run_state.gd` to delegate to `GameCore`, eliminating the duplication. At that point, `game_core.gd` becomes the single source of truth for all game logic.

## Difficulty Modes (Live-only)

Easy/Medium/Hard difficulty modes (with target tables, 5-round cap, `run_finished` signal, `total_score` tracking, and session high scores) are **live game only** and intentionally **NOT modeled in `game_core.gd`**. The simulator always runs Endless mode. This keeps the simulator focused on strategy evaluation under the classic unbounded curve and avoids duplicating high-score infrastructure.

## Modifiers

`game_core.gd` tracks a parallel board array `board_modifiers[x][y]` (same shape as `board`) alongside the letter grid. Each cell stores `MOD_NONE` (`""`) or `MOD_2X` (`"2x"`).

**Constants:** `MOD_NONE` and `MOD_2X` are defined directly in `game_core.gd` (mirrored from `game_data.gd`; keep both in sync).

**Rack shape:** `rack` is now `Array` of `{"letter": String, "modifier": String}` dicts instead of `Array[String]`. Use `rack_letters()` wherever strategies or tests need plain letter strings. The helper `draw_tile()` always produces `MOD_NONE`; `_ensure_modifier_in_rack(MOD_2X)` promotes one tile per refill.

**Scoring:** `_calculate_turn_score` reads `board_modifiers` per cell when summing letter points. Letter modifier applies first, then the word bonus — the same order as the live game. Tie scoring changes in `main.gd` and `game_core.gd` together; they are the same calculation in both files.

**Drift risk:** If `_ensure_modifier_in_rack`, `board_modifiers`, or the modifier constants change in either `game_core.gd` or the live files (`rack.gd`, `board_cell.gd`, `game_data.gd`), update the counterpart immediately or sim parity will silently diverge. Test coverage: TSM1–TSM6 verify modifier guarantee, promotion ordering, scoring with modifiers, and determinism.

## Running the Simulator

See `sim_runner.gd` for the CLI interface. Typical usage:

```
<godot_binary> --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy,word_search --seed 42
```

Results are written to `user://sim/` as CSV and JSONL.

## Start Screen & the Autoplay Loop

The project boots to a Win95-styled start screen (`scenes/start_screen.tscn`).
Autoplay runs pass through the menu like a user (full glitch animation,
deterministic) and close the loop by exiting cleanly with code 0.

### Canonical Autoplay Command

```
godot --headless --path . -- --autoplay=word_search
```

### Log Contract

A healthy headless autoplay run emits these log lines in order:

```
[StartScreen] ready — menu shown
[StartScreen] autoplay detected — launching Endless
[StartScreen] mode selected — Endless
[StartScreen] launch glitch — 12 ghosts stamped
[StartScreen] launching main scene
[Autoplay] starting with strategy=<strategy>, step=200ms
[RunState] ... gameplay logs ...
[Autoplay] game over — quitting to title
[GameOverDialog] quit — returning to title
[StartScreen] ready — menu shown
[StartScreen] run complete — quitting
```

The process must exit with code 0 on its own (NOT timeout). The ghost
count (12) is a regression check: if stamping breaks, it reads 0 while
the transition still appears to "work".

### Loop Guard: `RunState.autoplay_run_completed`

This flag prevents an infinite loop when the `--autoplay` CLI arg
persists across scene changes. It is **NOT** cleared by `RunState.reset()`
so it survives the return to the title screen. Set exactly once (in
`main.gd::_on_game_over`) and checked exactly once (in
`start_screen.gd::_maybe_autoplay`).

The pattern: first run sets the flag and presses Start; second pass at
the title (after game over) sees the flag and quits the app.

## Upgrade Wizard Parity

At the upgrade rounds the game offers letter-modifier upgrades. The offer
generation and auto-pick are duplicated live/sim and must stay in sync.

- **Offers:** 3 distinct, distribution-weighted, unowned letters with
  independent 67/33 `2x`/`3x` rolls. The generator is duplicated in
  `main.gd` and `game_core.gd::_generate_upgrade_offers` — **change both
  together.**
- **Auto-pick heuristic** (autoplay + sim):
  `LETTER_DISTRIBUTION × LETTER_POINTS × multiplier`, ties broken by offer
  order. Mirrored as `_offer_value` in both files.
- **Test coverage:** TSM10 (`test_upgrade_auto_pick_at_intervals` — offers
  appear at the right rounds), TSM11
  (`test_upgrade_offers_distinct_unowned_deterministic` — offers are
  distinct, exclude owned letters, and are reproducible under a fixed seed).
- **Expected autoplay log lines** at upgrade rounds:
  `[UpgradeWizard] autoplay pick — ...` followed by
  `[RunState] letter modifier set — ...`.

## Discard Parity

The live game and simulator both support tile discarding — a free action that swaps a rack tile for a replacement from the bag, with a per-round budget.

### Core Mechanics (both live and sim)

- **Constants:** `DISCARDS_PER_ROUND = 3` (mirrors `RunState` and `GameCore`)
- **State:** `discards_left` tracks the remaining budget each round; reset in `_advance_round()` (live) and `_advance_round()` (sim)
- **Draw:** `discard_tile(letter)` removes the tile from the rack and draws a **replacement excluding that letter** (prevents frustration of immediately redrawing the same tile). The replacement gets modifiers re-applied (same pass as refill).
- **Determinism:** Seeded `rng` in `GameCore`, never global `randi()`. Under fixed seed, same discard produces same replacement.

### Simulator Integration

- **Strategy hook:** `Strategy.pick_discards(core)` returns letters to discard (default empty; existing strategies never discard).
- **Execution:** `Simulator._run_game` calls `pick_discards` at the **start of each turn**, before `pick_moves`. Each discard is routed through `core.discard_tile()`.
- **Demo strategy:** `DiscardWordSearchStrategy` extends `WordSearchStrategy` with "discard when stuck" logic:
  - Calls `pick_moves` to check if the rack can form a valid word (≥2-tile placement signals success, 1-tile random fallback signals "stuck").
  - If stuck: ditch the least-useful tile by vowel balance (drop surplus vowels if flooded, drop rare consonants if starved).
  - Only spends discards when genuinely stuck, conserving the 3-per-round budget.

### Test Coverage

Three parity tests confirm discard mechanics:

- `test_discard_excludes_same_letter`: replacement draw never returns the discarded letter.
- `test_discard_budget_resets_each_round`: `discards_left` resets to `DISCARDS_PER_ROUND` after round advance.
- `test_discard_deterministic_under_seed`: same seed produces identical replacement tiles.

### Live Autoplay

Live autoplay also executes discards: `_run_autoplay` calls `pick_discards` before placement, routes each through the animated `discard_rack_tile`, and poll-waits on `_discard_busy` between actions. The `DiscardWordSearchStrategy` is registered for both headless batch (sim) and live autoplay (`--autoplay=discard_word_search`), so the same strategy drives both paths.
