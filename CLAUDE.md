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
- `data/words.txt` — dictionary lookup for word validation (UPPERCASE,
  length 2..8 after filtering).
- `shaders/` — visual FX (CRT overlay, holographic score, etc.).

## Conventions

- **snake_case** for file names, node names in scripts, variables, and
  functions. PascalCase only for class names and node types.
- **Structured logging** at every state transition:
  `print("[RunState] reset — round 1, target %d" % target_score)`. Prefixes
  in use: `[RunState]`, `[Turn]`, `[Move]`, `[Discard]`, `[GameOverDialog]`,
  `[Sim]`, `[GameCore]`. Add a new prefix for a new subsystem rather than
  dumping into an existing one.
- **No comments that restate the code.** Only add a comment when the *why*
  is non-obvious — a hidden constraint, a Godot quirk, a workaround.
- **No new files unless needed.** Prefer editing existing scenes/scripts.

## Scoring & word highlight

> The one invariant that governs both: **score and highlight are computed
> from a single shared helper, so they can never disagree.** If a tile
> contributes to the score it glows, and vice-versa. Never add a code path
> that scores something it doesn't highlight (or highlights something it
> doesn't score).

**Whole-board model.** Scoring is *not* scoped to the tiles placed this
turn. At end-of-turn (PLAY) the game scans **every row and column**, takes
each maximal contiguous letter run (length >= 2), and scores **every** valid
length-2..8 substring of that run — each with the word bonus
(`WORD_BONUS_MULTIPLIER`, 2×). Consequences to keep in mind:

- **Locked and pending tiles count identically.** `pending_cells` no longer
  scopes scoring; the `pending_positions` argument on
  `game_core.gd::_calculate_turn_score` is vestigial (kept for call-site
  compatibility). Words re-score every turn — extending `CAT` to `CATS`
  re-banks `CAT`.
- **Nested/overlapping words double-count shared letters by design**
  (`HELLO` = `HE` + `HELL` + `HELLO`).
- **A run with no valid word scores 0.** There is no consolation
  bare-letter scoring — gibberish neither glows nor scores.
- **Per-letter modifier (2×/3×) applies first, then the word bonus** — same
  order in live and sim.

**Shared source of truth.** In `main.gd`:

- `_board_runs()` → maximal runs across all rows/columns.
- `_collect_scoring_words()` → every valid substring of every run.
- `_calculate_turn_score()` sums them; `_refresh_highlights()` lights their
  cells. `game_core.gd` mirrors `_board_runs` / `_collect_scoring_words` /
  `_score_word_sim` exactly. **Change one, change both.**

**Highlight rendering (`board_cell.gd`).** A glowing tile draws an animated
**rainbow outline** in `_draw` — not a StyleBox or material, because a
per-tile animated rainbow can't be expressed as either.

- `set_highlighted(bool)` flips a flag + `queue_redraw`; while lit,
  `_process` redraws every frame to animate. The flag is set for *every*
  cell each `_update_hud()` (it early-returns when unchanged).
- The outline is inset `C_HL_INSET` **past the cyan focus ring** so both
  survive when the cursor sits on a glowing word (nest, don't replace).
- Hue is a board-coherent diagonal sweep:
  `fposmod((grid_pos.x + grid_pos.y) * 0.12 + t * 0.2, 1.0)` fed through
  `_hue_to_rgb`, which **duplicates `hue2rgb()` in
  `shaders/holographic.gdshader`** (the score's rainbow). Change the shader
  ramp → change `_hue_to_rgb`, or tile glow and score drift apart.
- Recomputed from `_update_hud()` (runs after every board/rack mutation), so
  the glow is a **live preview**; locked words stay lit until
  `board.clear_all()` on round win.

**Retuning is an open follow-up.** Whole-board re-scoring inflates turn
scores hard. `INITIAL_TARGET_SCORE` and the difficulty curve likely need
retuning — measure with the simulator before picking numbers, and mirror any
constant change into `game_core.gd`.

## Tile modifiers

**MOD_2X / MOD_3X mechanic:** Each refill guarantees a fixed count of letter
modifiers in the rack via `_ensure_modifier_in_rack()` /
`_ensure_modifier_count_in_rack()` (deterministic; always promotes the
lowest-value tile). A modified tile multiplies its letter's contribution
(×2 / ×3) wherever it sits in a scored word; the word bonus stacks on top.
See **Scoring & word highlight** for how words are found.

**Visual implementation:** Modifier visuals (Win98 navy→sky-blue gradient for
2×, green gradient for 3×) are drawn in `tile.gd::_draw` and
`board_cell.gd::_draw`, not as a theme variation, because the gradient body
can't be a `StyleBoxFlat`. Label colors are hardcoded constants
(`C_LABEL_*`) — `get_theme_color_override` does not exist in Godot 4.6.1, so
match the scene-file values in `_refresh_visual` / `_sync_label_color`.

**Sim parity:** `game_core.gd` mirrors the modifier system via
`board_modifiers[x][y]` and the `MOD_NONE` / `MOD_2X` / `MOD_3X` constants.
If `_ensure_modifier*`, board-modifier logic, scoring, or color constants
change in `rack.gd`, `board_cell.gd`, `tile.gd`, or `game_data.gd`, update
`game_core.gd` immediately. Modifier tests: `TC9`–`TC14`, `TSM7`–`TSM11` in
`scripts/sim/tests/test_game_core.gd`.

## Controls (place / move / return tiles)

- **Place:** drag a rack tile onto an empty cell, or keyboard-place at the
  cursor. Hard-capped at `tiles_per_turn` via `can_place_pending_tile()`.
- **Move / swap:** drag an **unlocked** board tile to another cell (empty =
  move, occupied-unlocked = swap). Locked targets are rejected.
- **Return to rack — four routes, all unlocked-only:** drag board→rack,
  **right-click** the board tile, the Delete key, or drop onto the rack /
  any rack tile.
- **Locked tiles NEVER move** — they hold until round's end. The gate
  everywhere is `current_tile != null` (a pending cell sets `current_tile`; a
  locked cell sets `locked_letter` / `locked_modifier` with
  `current_tile == null`). Honor it in every new tile-return path.
- **Commit is explicit.** The **PLAY** button (or the `confirm_turn` key)
  resolves the turn; placing never auto-ends it. PLAY stays disabled until
  >= 1 tile is pending (and during transitions/upgrades/discard).
- **Cross-node calls** go through
  `get_tree().get_first_node_in_group("main")` + a `has_method(...)` guard.
  `main` adds itself to group `"main"` in `_ready`. The drag-drop target
  callbacks (`board_cell.gd`, `tile.gd`, `rack.gd`) all reach `main` this way.

## Godot quirks worth remembering

- **`_can_drop_data` fires only on the Control directly under the cursor.**
  A child that covers a container blocks the container's own drop handling
  unless the child *also* implements `_can_drop_data` / `_drop_data`. That's
  why both `rack.gd` and `tile.gd` forward board-tile drops to the rack.
- **Theme inheritance does not cross `CanvasLayer` boundaries.** A dialog
  parented to a `CanvasLayer` renders unstyled unless you assign `win95.tres`
  (or rely on the project default) explicitly on its root.
- **`Control.size` is `(0, 0)` before the first layout pass.** When centering
  a freshly instantiated dialog in `_ready`, use `custom_minimum_size` for
  math, not `size`.
- **Child `_ready` runs before the parent's.** `board.cells` is populated
  before `main._ready` calls `_update_hud()`, so a whole-board scan there is
  safe.
- **`HBoxContainer` steals focus when a child is removed.** After mutating the
  rack (placing/returning a tile), re-anchor focus with
  `board.focus_cell(cursor)` or arrow-key navigation breaks.
- **Reserve space for containers that can become empty.** An empty
  `HBoxContainer` collapses to zero height and shifts the layout. Set
  `custom_minimum_size.y` to the expected row height (see the rack in
  `scenes/main.tscn`).
- **Dictionaries support dot-access** (`w.text`) and **Nodes/Vector2i can be
  dict keys** — `_refresh_highlights` uses cell nodes as keys to dedup lit
  cells.
- **`fposmod` for a positive modulo; `Time.get_ticks_msec()` for a shared
  animation clock.** A shared clock keeps every tile's rainbow in phase
  without per-cell timers.
- **`draw_rect(rect, color, false, width)`** draws an outline of the given
  width — prefer it for procedural bevels/rings/glow over nine-patch
  styleboxes.
- **CanvasLayer ordering** in this project:
  - `100` — CRT overlay (draws over everything, including dialogs)
  - `60`  — round transition overlay
  - `50`  — game over dialog
  - `40`  — particle/anim layer (glitter, return tweens)
  Pick a layer that places new overlays below the CRT.

## Win95 style

- Title-bar navy: `Color(0, 0, 0.5019, 1)`. Reuse this for any "system"
  text (round transitions, headings).
- Dialog chrome: `WindowFrame` Panel → `InnerVBox` (2px inset) → `TitleBar`
  Panel (`theme_type_variation = "TitleBar"`, white title text) with
  Min/Max/Close (`-` / `O` / `X`) decoration buttons → `BodyArea` VBox.
  Mirror `scenes/game_over_dialog.tscn` for any new dialog.
- The `X` button closes the window in spirit — wire it to the same action as
  the dialog's primary "cancel" path (e.g. quit / dismiss).
- Primary actions use the `PlayButton` theme-type-variation (larger font +
  default-button outline), not color — Win95 never colored push buttons.

## Game state

`RunState` is an autoload (`scripts/run_state.gd`). It owns:

- `current_round`, `round_score`, `target_score`, `turns_left`,
  `tiles_per_turn`, `is_game_over`, `is_transitioning`, `is_upgrading`.
- Signals: `round_started`, `round_score_changed`, `turns_left_changed`,
  `round_won`, `game_over`.
- `reset()` returns the run to round 1. Call it before starting a fresh game
  (e.g. after the game over dialog's Restart).

**Per-round score resets to 0.** The escalating target and growing
`tiles_per_turn` carry the difficulty curve — there is no accumulated total
score.

**`_advance_round` resets round state *before* emitting `round_won`** so
signal handlers see the new round number.

## Input gating

`main.gd::_unhandled_input` must early-return when
`RunState.is_game_over or RunState.is_transitioning`. Drag-drop and
tile-return entry points (`on_tile_dropped_on_cell`,
`on_tile_returned_to_rack`, `_return_pending_tile`) need the same guard (plus
`is_upgrading` / `_discard_busy`) or the player can mutate the board while an
overlay is up.

## Restart flow

`RunState.reset()` then `get_tree().reload_current_scene()`. Do not manually
tear down nodes — the scene reload handles it.

## Simulation harness (`scripts/sim/`)

A headless simulator for batch-evaluating strategies without the UI. Layout:

- `game_core.gd` — **duplicate** of game logic from `main.gd`,
  `run_state.gd`, `board.gd`, `rack.gd`. If you change scoring (`_board_runs`,
  `_collect_scoring_words`, `_score_word_sim`), progression, tile draw,
  modifiers, or any related constant (`TURNS_PER_ROUND`,
  `INITIAL_TILES_PER_TURN`, `INITIAL_TARGET_SCORE`, `WORD_BONUS_MULTIPLIER`,
  `BOARD_SIZE`, `RACK_SIZE`, `LETTER_DISTRIBUTION`, `LETTER_POINTS`) in the
  live game, mirror it here or sim parity silently drifts. See
  `scripts/sim/README.md`. `_extract_word_in_direction` is retained **only**
  for `TC5`'s extraction test — the scorer no longer uses it.
  Also owns the sim's dictionary cache: `GameCore.is_valid_word(text)` loads
  `res://data/words.txt` once, mirroring `GameData._load_dictionary`'s
  length 2..8 filter. If that filter changes in `game_data.gd`, mirror it
  here too.
- `strategy.gd` — base class. New strategies go in `strategies/` and extend it
  (see `random_strategy.gd`, `greedy_strategy.gd`, `word_search_strategy.gd`,
  `diagonal_cluster_strategy.gd`). Respect the 50ms-per-turn budget.
- `simulator.gd` — `run_batch(strategies, runs, base_seed)` runs N games with
  seeded RNG (deterministic; same seed → same result).
- `results_writer.gd` — writes CSV + JSONL to `./sim_results/` (relative path;
  `user://` is unreliable headless).
- `sim_runner.gd` — CLI entry point (`extends SceneTree`).
- `tests/run_tests.gd` — auto-discovers `test_*` methods across
  `test_game_core.gd`, `test_strategies.gd`, `test_simulator.gd`,
  `test_navigation.gd`. `smoke.gd` runs 3 games end-to-end. Prefix sim logs
  `[Sim]` / `[GameCore]`, not `[RunState]`.

### Running the simulator

```
godot --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy,word_search --seed 42
```

Everything after `--` is parsed via `OS.get_cmdline_user_args()` (NOT
`OS.get_cmdline_args()` — that returns engine args). Both `--key=value` and
`--key value` forms work. Output dirs are created with
`DirAccess.make_dir_absolute()`.

### Headless-mode pitfalls

- **Autoloads may not initialize** under `--script`. `GameData` in particular
  is unreliable — strategies fall back to a built-in letter table and
  simplified dictionary when it's missing. Don't assume any autoload exists
  inside `scripts/sim/`.
- **`user://` paths can be empty or unwritable.** Use relative paths
  (`./sim_results/`).
- **Don't import scene-coupled scripts** (anything touching `_ready`,
  `$NodePath`, signals on UI nodes) from sim code. `game_core.gd` exists
  precisely so the sim stays scene-free.

## Working on a task

1. Read the relevant scene + script together; Godot behavior often lives half
   in each.
2. Prefer the smallest possible change. A bug fix doesn't need a surrounding
   refactor.
3. Commit messages explain the *why* in 1–3 sentences and match recent commit
   style (`feat:` / `fix:` / `sim:`, short headline + 2–5 body lines naming
   the test cases or behavior touched). Do not open PRs unless asked.
4. Develop on the branch the user names; push when complete.
5. If your change touches logic duplicated in `scripts/sim/game_core.gd`,
   update both — and run `scripts/sim/tests/run_tests.gd` to confirm parity.

## Harness for coding agents (lessons from prior work)

Recurring traps. Read before editing.

- **You often can't run Godot in the agent environment.** There may be no
  `godot` binary, so you cannot execute `run_tests.gd` or launch the game.
  When that's the case: verify scoring math **by hand** against
  `data/words.txt`, hand-trace the affected `TC*` expectations, **state
  plainly that tests were not executed**, and ask the user to run the harness.
  Do not claim tests pass when you couldn't run them.
- **Score == highlight.** Both come from `_collect_scoring_words`. Any change
  to one must keep the other consistent.
- **Scoring changes ripple into the tests.** Expected values in
  `test_game_core.gd` (`TC4` sub-word sums, `TC11` modifier sums, `TC12`
  invalid-run → 0, `TC13` valid cross) are hand-computed from the dictionary —
  recompute them, don't relax assertions. Determinism/structure tests
  (`TSM1`/`TSM3`–`TSM6`, `smoke`) are scoring-agnostic and should stay green.
- **Verify autoload availability before calling it.** Headless `--script`
  entry points skip autoload init. Guard with `Engine.has_singleton(...)` or
  pass dependencies explicitly.
- **Check Godot 4 vs 4.6 API differences.** Targets Godot 4.6. Notable:
  `OS.get_cmdline_user_args()`, `DirAccess.make_dir_absolute()`, no
  `get_theme_color_override`. Grep for an existing usage before inventing one.
- **Determinism matters in the sim.** Thread the seed through any new RNG;
  never call `randi()` / `randf()` directly inside sim code — use the seeded
  `RandomNumberGenerator` from `GameCore`.
- **Don't introduce new top-level dirs.** `scenes/`, `scripts/`,
  `scripts/sim/`, `themes/`, `fonts/`, `data/`, `shaders/`, `docs/`,
  `sim_results/` (gitignored) are the canonical set.
- **Don't paper over a failure.** If a sim test fails because a constant
  drifted, fix the drift. If headless can't resolve an autoload, add a
  fallback or guard — don't silently swallow the error.
