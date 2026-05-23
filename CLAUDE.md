# CLAUDE.md

Guidance for coding agents working in this repo.

## Project

Godot 4 word game in the spirit of Scrabble, dressed in a Windows 95 skin.
Players place tiles on a board, form words, and try to reach an escalating
target score before they run out of turns. Beating a round wipes the board,
raises the target, and grants one extra tile per turn. Missing the target
ends the run.

## Layout

- `scenes/` — `.tscn` files (one per scene, snake_case).
- `scripts/` — `.gd` files paired with scenes (snake_case).
- `themes/win95.tres` — the **default project theme**, set via
  `gui/theme/custom` in `project.godot`. Every Control inherits it.
- `fonts/w95fa.otf` — the only font. Use it for any custom-styled text.
- `data/words.txt` — dictionary lookup for word validation.
- `shaders/` — visual FX (CRT overlay, holographic score, etc.).

## Conventions

- **snake_case** for file names, node names in scripts, variables, and
  functions. PascalCase only for class names and node types.
- **Structured logging** at every state transition:
  `print("[RunState] reset — round 1, target %d" % target_score)`. Prefixes
  in use: `[RunState]`, `[Turn]`, `[GameOverDialog]`. Add new prefixes for
  new subsystems rather than dumping into an existing one.
- **No comments that restate the code.** Only add a comment when the *why*
  is non-obvious — a hidden constraint, a Godot quirk, a workaround.
- **No new files unless needed.** Prefer editing existing scenes/scripts.

## Tile modifiers

**MOD_2X mechanic:** Each refill guarantees exactly one 2x letter-score modifier in the rack via `_ensure_modifier_in_rack()` (deterministic; always promotes the lowest-value tile). Letter score doubles when a tile with MOD_2X sits in a >=2-letter line at end-of-turn; the word bonus (2× when applicable) stacks on top.

**Visual implementation:** Tile modifier visuals (the Win98 navy-to-sky-blue gradient body) are drawn in `tile.gd::_draw` and `board_cell.gd::_draw`, not as a theme variation, because the gradient body can't be expressed as a `StyleBoxFlat`. Label colors are hardcoded constants (navy for letter, dark-gray for point value) — `get_theme_color_override` does not exist in Godot 4.6.1. Use the hardcoded constants matching scene file values in `_refresh_visual` / `_sync_label_color`.

**Sim parity:** `game_core.gd` mirrors the live game's modifier system via `board_modifiers[x][y]` parallel array and `MOD_NONE` / `MOD_2X` constants. If `_ensure_modifier_in_rack`, board modifier logic, or color constants change in `rack.gd`, `board_cell.gd`, `tile.gd`, or `game_data.gd`, update `game_core.gd` immediately. Test coverage: TC9–TC14 (guarantee, promotion, scoring), TS5–TS6 (sim parity), TSM1–TSM6 (modifier-specific tests).

## Godot quirks worth remembering

- **Theme inheritance does not cross `CanvasLayer` boundaries.** A dialog
  parented to a `CanvasLayer` will render unstyled unless you assign
  `win95.tres` (or rely on the project default) explicitly on its root.
- **`Control.size` is `(0, 0)` before the first layout pass.** When
  centering a freshly instantiated dialog in `_ready`, use
  `custom_minimum_size` for math, not `size`.
- **`HBoxContainer` steals focus when a child is removed.** After mutating
  the rack (placing/returning a tile), re-anchor focus with
  `board.focus_cell(cursor)` or arrow-key navigation breaks.
- **Reserve space for containers that can become empty.** An empty
  `HBoxContainer` collapses to zero height and shifts the layout. Set
  `custom_minimum_size.y` to the expected row height (see the rack at
  `scenes/main.tscn`).
- **CanvasLayer ordering** in this project:
  - `100` — CRT overlay (draws over everything, including dialogs)
  - `60`  — round transition overlay
  - `50`  — game over dialog
  Pick a layer that places new overlays below the CRT.

## Win95 style

- Title-bar navy: `Color(0, 0, 0.5019, 1)`. Reuse this for any "system"
  text (round transitions, headings).
- Dialog chrome: `WindowFrame` Panel → `InnerVBox` (2px inset) → `TitleBar`
  Panel (`theme_type_variation = "TitleBar"`, white title text) with
  Min/Max/Close (`-` / `O` / `X`) decoration buttons → `BodyArea` VBox.
  Mirror `scenes/game_over_dialog.tscn` for any new dialog.
- The `X` button closes the window in spirit — wire it to the same action
  as the dialog's primary "cancel" path (e.g. quit / dismiss).

## Game state

`RunState` is an autoload (`scripts/run_state.gd`). It owns:

- `current_round`, `round_score`, `target_score`, `turns_left`,
  `tiles_per_turn`, `is_game_over`, `is_transitioning`.
- Signals: `round_started`, `round_score_changed`, `turns_left_changed`,
  `round_won`, `game_over`.
- `reset()` returns the run to round 1. Call it before starting a fresh
  game (e.g. after the game over dialog's Restart).

**Per-round score resets to 0.** The escalating target and growing
`tiles_per_turn` carry the difficulty curve — there is no accumulated
total score.

**`_advance_round` resets round state *before* emitting `round_won`** so
signal handlers see the new round number.

## Input gating

`main.gd::_unhandled_input` must early-return when
`RunState.is_game_over or RunState.is_transitioning`. Drag-drop entry
points (`on_tile_dropped_on_cell`, `on_tile_returned_to_rack`) need the
same guard or the player can mutate the board while an overlay is up.

## Restart flow

`RunState.reset()` then `get_tree().reload_current_scene()`. Do not try to
manually tear down nodes — the scene reload handles it.

## Simulation harness (`scripts/sim/`)

A headless simulator lives under `scripts/sim/` for batch-evaluating
strategies without launching the UI. Layout:

- `game_core.gd` — **duplicate** of game logic from `main.gd`,
  `run_state.gd`, `board.gd`, `rack.gd`. If you change scoring,
  progression, tile draw, word extraction, or any related constant
  (`TURNS_PER_ROUND`, `INITIAL_TILES_PER_TURN`, `INITIAL_TARGET_SCORE`,
  `WORD_BONUS_MULTIPLIER`, `BOARD_SIZE`, `RACK_SIZE`, `LETTER_DISTRIBUTION`,
  `LETTER_POINTS`) in the main game, mirror the change in `game_core.gd`
  or sim parity will silently drift. See `scripts/sim/README.md`.
  Also owns the sim's dictionary cache: `GameCore.is_valid_word(text)`
  loads `res://data/words.txt` once, mirroring `GameData._load_dictionary`'s
  length 2..8 filter. If that filter changes in `game_data.gd`, mirror it
  here too — otherwise the 2× word bonus diverges between live and sim.
- `strategy.gd` — base class. New strategies go in `strategies/` and
  extend it (see `random_strategy.gd`, `greedy_strategy.gd`,
  `word_search_strategy.gd`, `diagonal_cluster_strategy.gd`). Respect
  the 50ms-per-turn time budget.
- `simulator.gd` — `run_batch(strategies, runs, base_seed)` runs N games
  with seeded RNG (deterministic; same seed → same result).
- `results_writer.gd` — writes CSV + JSONL to `./sim_results/`
  (relative path; `user://` paths are unreliable in headless mode).
- `sim_runner.gd` — CLI entry point (`extends SceneTree`).
- `tests/run_tests.gd` — test harness. `smoke.gd` runs 3 games end-to-end.
  Prefix sim logs with `[Sim]` / `[GameCore]`, not `[RunState]`.

### Running the simulator

```
godot --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy,word_search --seed 42
```

Everything after `--` is parsed via `OS.get_cmdline_user_args()` (NOT
`OS.get_cmdline_args()` — that returns engine args). Both `--key=value`
and `--key value` forms are supported. Output dirs are created with
`DirAccess.make_dir_absolute()`.

### Headless-mode pitfalls

- **Autoloads may not initialize** when invoked via `--script`. `GameData`
  in particular is unreliable — strategies fall back to a built-in
  Scrabble letter table and a simplified dictionary when it's missing.
  Do not assume any autoload is available inside `scripts/sim/`.
- **`user://` paths can be empty or unwritable.** Use relative paths
  (`./sim_results/`) for sim output.
- **Don't import scene-coupled scripts** (anything that touches
  `_ready`, `$NodePath`, signals on UI nodes) from sim code. `game_core.gd`
  exists precisely so the sim can stay scene-free.

## Working on a task

1. Read the relevant scene + script together; Godot behavior often lives
   half in each.
2. Prefer the smallest possible change. A bug fix doesn't need a
   surrounding refactor.
3. Commit messages should explain the *why* in 1–3 sentences. Match the
   style of recent commits on the current branch.
4. Develop on the branch the user names. Push when the change is complete.
   Do not open PRs unless asked.
5. If your change touches game logic that is duplicated in
   `scripts/sim/game_core.gd`, update both — and run
   `scripts/sim/tests/run_tests.gd` to confirm parity.

## Harness for coding agents (lessons from prior PRs)

These are recurring traps. Read before editing.

- **Verify autoload availability before calling it.** Headless entry
  points (`--script`) skip autoload init. Guard with
  `if Engine.has_singleton(...)` or pass dependencies explicitly.
- **Check Godot 4 vs 4.6 API differences.** This project targets Godot
  4.6. Notable: `OS.get_cmdline_user_args()` for args after `--`,
  `DirAccess.make_dir_absolute()` for directory creation. If unsure,
  grep the codebase for an existing usage before inventing one.
- **Determinism matters in the sim.** Always thread the seed through any
  new RNG. Never call `randi()` / `randf()` directly inside sim code —
  use the seeded `RandomNumberGenerator` instance from `GameCore`.
- **Don't introduce new top-level dirs.** `scenes/`, `scripts/`,
  `scripts/sim/`, `themes/`, `fonts/`, `data/`, `shaders/`,
  `sim_results/` (gitignored) are the canonical set.
- **Run the tests you touched.** For sim work, run
  `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  and confirm the existing TC1–TC14 / TS1–TS6 / TSM1–TSM6 cases still
  pass before pushing.
- **Don't paper over a failure.** If a sim test fails because a constant
  drifted, fix the drift — don't relax the test. If headless can't
  resolve an autoload, add a fallback or guard, don't silently swallow
  the error.
- **Match the commit-message style** of recent commits (`sim: ...`,
  `fix: ...`, short headline + 2–5 body lines naming the test cases or
  behavior touched).
