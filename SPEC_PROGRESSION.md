# Progression System & Game Over — Implementation Spec

## Context

ScrabbleRabble 95 is a Godot 4 scrabble-like game with a Windows 95 visual style.
The player places letter tiles on an 8×8 board, scores words, and presses END TURN.

**Branch:** `progression`

### Existing relevant files

| File | Role |
|---|---|
| `scripts/run_state.gd` | Autoload singleton — tracks round, score, target, turns |
| `scripts/main.gd` | Root scene script — HUD, input, turn logic |
| `scripts/board.gd` | 8×8 GridContainer of BoardCell nodes |
| `scripts/board_cell.gd` | Single cell — holds a tile, can be locked or pending |
| `scripts/rack.gd` | Player's hand of tiles |
| `scenes/GameOverDialog.tscn` | Already exists, Win95-styled modal panel |
| `scripts/game_over_dialog.gd` | Already exists, has `setup(rounds, score)`, Restart/Quit buttons |
| `theme/win95.tres` | Win95 theme — use `WindowFrame` and `TitleBar` theme variations |

### Existing constants & signals you must not break

- `Board.BOARD_SIZE = 8`
- `main.gd: TILES_PER_TURN = 4` (will become dynamic — see below)
- `main.gd: WORD_BONUS_MULTIPLIER = 2`
- `RunState` signals: `round_won(round_num, round_score, target)`, `game_over(final_round, total_score)`, `round_started(round_num, target, turns_left)`

---

## Gameplay rules to implement

1. **Turn:** the player places up to `tiles_per_turn` tiles. When the limit is reached or END TURN is pressed, the turn score is computed and registered.
2. **Round:** each round has `turns_per_round` turns and a `target_score`. If `round_score >= target_score` before turns run out → **round won**. If turns run out without hitting target → **game over**.
3. **On round won:**
   - Clear the board (remove all locked letters).
   - Refill the rack.
   - `tiles_per_turn` increases by 1 for the next round.
   - `RunState` already advances the round and generates the next target via Fibonacci-like growth.
4. **On game over:**
   - Show the `GameOverDialog` (already instantiated in `main.gd:_on_game_over`).
   - Dialog shows rounds survived and final score with Restart / Quit buttons.
5. **Starting values:** `tiles_per_turn = 4`, `turns_per_round = 3`, `target_score = 20` (already set in `RunState`).

---

## Changes required

### 1. `scripts/board.gd` — add `clear_all()`

Add a public method that resets every cell on the board to empty:

```gdscript
func clear_all() -> void:
    for x in BOARD_SIZE:
        for y in BOARD_SIZE:
            var cell: BoardCell = cells[x][y]
            cell.locked_letter = ""
            cell.current_tile  = null
            cell.label.text    = ""
            cell.queue_redraw()
```

### 2. `scripts/run_state.gd` — expose `tiles_per_turn`

Add a variable `tiles_per_turn: int = 4` to `RunState`.
In `reset()` set it back to `4`.
In `_advance_round()` increment it by 1: `tiles_per_turn += 1`.

Keep the existing `TURNS_PER_ROUND` constant (do not make turns dynamic — only tiles grow).

### 3. `scripts/main.gd` — wire board clear and dynamic tile limit

**a) Remove the `const TILES_PER_TURN`** — the limit now comes from `RunState.tiles_per_turn`.

**b) Update `_place_tile_on_cell()`** — change the auto-submit guard:
```gdscript
if pending_cells.size() >= RunState.tiles_per_turn:
    _on_end_turn_pressed()
```

**c) Update `_on_round_won()`** — clear the board and pending list, then refill:
```gdscript
func _on_round_won(_round_num: int, _round_score: int, _target: int) -> void:
    pending_cells.clear()
    board.clear_all()
    rack.refill()
    var emitter: GPUParticles2D = GLITTER_SCENE.instantiate()
    add_child(emitter)
    emitter.global_position = board.global_position + board.size * 0.5
    _update_hud()
```

**d) Update `_update_hud()`** — show tiles-per-turn so the player always knows their budget:
```gdscript
func _update_hud() -> void:
    score_label.text      = "Score: %d | Round %d | Goal: %d" % [RunState.total_score, RunState.current_round, RunState.target_score]
    tiles_left_label.text = "This round: %d / %d | Turns left: %d | Tiles/turn: %d" % [RunState.round_score, RunState.target_score, RunState.turns_left, RunState.tiles_per_turn]
```

**e) `_on_game_over` is already implemented** — verify it instantiates `GameOverDialog`, wraps it in a `CanvasLayer` at layer 200, and calls `dialog.setup(final_round, final_score)`. No changes needed if already correct.

### 4. `scenes/GameOverDialog.tscn` — verify it is complete

The scene already exists with this structure:
```
GameOverDialog (Panel, theme_type_variation=WindowFrame)
└── VBox (VBoxContainer)
    ├── TitleBar (Panel, theme_type_variation=TitleBar)
    │   └── TitleLabel (Label, text="GAME OVER", centered)
    └── BodyVBox (VBoxContainer, centered)
        ├── RoundLabel (Label)
        ├── ScoreLabel (Label)
        └── ButtonRow (HBoxContainer, centered)
            ├── RestartButton (Button, text="RESTART")
            └── QuitButton   (Button, text="QUIT")
```

The script `game_over_dialog.gd` already calls `RunState.reset()` then `get_tree().reload_current_scene()` on Restart, and `get_tree().quit()` on Quit.

**No changes to the dialog are required** unless the scene file is missing nodes referenced by the script — verify node paths match.

---

## What NOT to do

- Do not add a "board full" detection or softlock prevention — that is out of scope.
- Do not change `TURNS_PER_ROUND` to be dynamic.
- Do not touch the CRT overlay, shaders, holographic material, or Win95 theme file.
- Do not refactor unrelated code.
- Do not add sound effects or animations beyond the existing glitter emitter.

---

## Acceptance checklist

- [ ] Placing `tiles_per_turn` tiles auto-submits the turn (no hang).
- [ ] After a failed turn that exhausts `turns_left`, the Game Over dialog appears with correct round and score values.
- [ ] Clicking RESTART resets the game and returns to a fresh board.
- [ ] Clicking QUIT exits the application.
- [ ] After a round is won, the board clears, the rack is refilled, and the HUD shows the incremented `tiles_per_turn`.
- [ ] `tiles_per_turn` starts at 4 on a fresh game and increases by 1 per round won.
- [ ] The HUD always shows: total score, current round number, round goal, round progress, turns left, and tiles per turn.
- [ ] The Game Over dialog respects the Win95 theme (`WindowFrame` / `TitleBar` variations).
