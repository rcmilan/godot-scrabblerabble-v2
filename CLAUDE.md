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

## Working on a task

1. Read the relevant scene + script together; Godot behavior often lives
   half in each.
2. Prefer the smallest possible change. A bug fix doesn't need a
   surrounding refactor.
3. Commit messages should explain the *why* in 1–3 sentences. Match the
   style of recent commits on `progression`.
4. Develop on the branch the user names. Push when the change is complete.
   Do not open PRs unless asked.
