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

### Future Refactoring

Once the simulator is proven useful, refactor `main.gd` and `run_state.gd` to delegate to `GameCore`, eliminating the duplication. At that point, `game_core.gd` becomes the single source of truth for all game logic.

## Running the Simulator

See `sim_runner.gd` for the CLI interface. Typical usage:

```
<godot_binary> --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy,word_search --seed 42
```

Results are written to `user://sim/` as CSV and JSONL.
