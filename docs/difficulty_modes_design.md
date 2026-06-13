# Difficulty Modes & High Scores — Design Specification

Adds three fixed-length difficulty modes (Easy / Medium / Hard) alongside
the existing Endless mode, each ending after 5 rounds with a high-score
popup. Settled in design review (2026-06-13). This is the **design
spec**; a separate task doc will slice it for implementation.

## Summary

- Today the game is **Endless**: an escalating target curve with no round
  limit, ending only when you miss a target. Endless is kept as a
  selectable mode, unchanged.
- Add **Easy / Medium / Hard**: each has its own fixed per-round target
  table and **ends after 5 rounds**.
- The start screen gains **5 options**: Easy, Medium, Hard, Endless, Quit.
- A run now tracks an **accumulated total score**; difficulty runs end on
  a popup showing that total and the **session high score** for the mode.
- **High scores are in-memory only this version** (per-difficulty,
  not written to disk).
- **Simulations stay Endless-only** — `game_core.gd` and the sim are
  untouched.

## 1. Mode model (`RunState`)

`RunState` (the autoload that already owns progression) gains:

```gdscript
enum Mode { EASY, MEDIUM, HARD, ENDLESS }
var mode: int = Mode.ENDLESS   # default = today's behaviour
```

- The **start screen sets `RunState.mode`** before
  `change_scene_to_file("res://scenes/main.tscn")`.
- `main.gd::_ready` still calls `RunState.reset()`, which **reads `mode`**
  to pick the round-1 target and round limit, and **must NOT clear
  `mode`** (like `autoplay_run_completed`, it survives `reset()`).
- **`ENDLESS` is the default**, so a fresh boot, the simulator, and any
  path that skips the start screen behave exactly as today.

Helper: `func is_difficulty_mode() -> bool: return mode != Mode.ENDLESS`.

## 2. Score model — accumulated total

The game currently has no run total (`round_score` resets each round).
Add:

```gdscript
var total_score: int = 0
```

- Accumulate **every point**: `total_score += points` at the top of
  `register_turn_score`. Points scored in a *failing* final round still
  count.
- `reset()` sets `total_score = 0` (each run starts fresh).
- This is the metric the high score tracks and the HUD/popup display.

## 3. Target curves

- **Easy / Medium / Hard:** an explicit 5-value table per mode.
- **Endless:** keeps its existing Fibonacci-ish curve **unchanged**
  (R1–5 = 20, 30, 40, 55, 75, then 102, 139, … past round 5).
- Ordering at every round is **Easy < Medium < Endless < Hard**, so
  Endless sits "between Medium and Hard" as required.

```gdscript
const ROUNDS_PER_DIFFICULTY: int = 5
const DIFFICULTY_TARGETS := {
	Mode.EASY:   [12, 18, 26, 34, 44],
	Mode.MEDIUM: [16, 24, 34, 46, 60],
	Mode.HARD:   [25, 38, 52, 70, 92],
}
```

(Numbers are **tunable** starting points; the structure is fixed.)

- `reset()`: difficulty → `target_score = DIFFICULTY_TARGETS[mode][0]`;
  endless → the existing init (`target_score = INITIAL_TARGET_SCORE`,
  `_t_prev/_t_curr` seeded as today).
- `_advance_round()`: difficulty →
  `target_score = DIFFICULTY_TARGETS[mode][current_round - 1]`; endless →
  the existing Fib computation (left byte-identical).

**Only the targets differ between modes.** Turns-per-round (3),
`tiles_per_turn` growth (+1/round from 4), discards (3/round), and
upgrades (every 3 rounds → one upgrade entering round 4) are **identical
in all four modes**.

## 4. End conditions & win/lose

Pass/fail gating is preserved; difficulty modes add a 5-round cap.

- **Clear a round's target** (round_score ≥ target): `_advance_round`.
  - Difficulty **and the round just cleared is round 5** → the run ends
    as a **win**: fire `run_finished(true, 5, total_score)`, do NOT
    advance to round 6.
  - Otherwise advance normally (difficulty rounds 1–4 and all endless
    rounds still emit `round_won` + `round_started`, so the round
    transition plays as today).
- **Miss the target** (turns run out below it):
  - Difficulty → **loss**: `is_game_over = true`, fire
    `run_finished(false, current_round, total_score)`.
  - Endless → unchanged: `is_game_over = true`, `game_over.emit(...)`.

New signal:

```gdscript
signal run_finished(won: bool, final_round: int, total: int)
```

- **Endless never fires `run_finished`; difficulty never fires
  `game_over`.** Clean separation: `main.gd` shows the existing
  `game_over_dialog` on `game_over` (endless) and the new
  `difficulty_end_dialog` on `run_finished` (difficulty).
- On a round-5 win the inter-round transition is skipped — the popup is
  the celebration (the handler may still clear the board / spawn glitter
  for flourish; minimal version just shows the popup).

## 5. High scores (in-memory, per difficulty)

**No disk persistence this version.** `RunState` holds a session-only
best per difficulty:

```gdscript
var session_high_scores := { Mode.EASY: 0, Mode.MEDIUM: 0, Mode.HARD: 0 }
```

- Survives scene reloads within the session (RunState is an autoload) and
  is **NOT cleared by `reset()`** (Play Again must not wipe it). Lost on
  app exit.
- On `run_finished`, before showing the popup, compare and update:
  `prev = session_high_scores[mode]`; `is_new = total_score > prev`;
  if `is_new`, `session_high_scores[mode] = total_score`. Pass
  `total`, `best = session_high_scores[mode]`, and `is_new` to the popup.
- Endless has no high score (keeps its plain game-over).
- Disk persistence (`ConfigFile` at `user://`) is a clean **future add**;
  the in-memory dict drops straight into a save later.

## 6. End popup — `difficulty_end_dialog`

New `scenes/difficulty_end_dialog.tscn` + script, mirroring the
`game_over_dialog` Win95 chrome (`WindowFrame`/`TitleBar`, instanced on a
**layer-50 `CanvasLayer` with a full-rect `mouse_filter = STOP`
blocker**, like the other modals).

- **Adaptive result line:** win → "You cleared all 5 rounds!"; loss →
  "Failed at round N of 5."
- **`Score: <total>`** (this run's accumulated total).
- **`Best (<difficulty>): <best>`**, plus a **"NEW HIGH SCORE!"** line
  shown only when `is_new`.
- **Buttons:** `Play Again` (`RunState.reset()` keeping the same `mode` →
  `reload_current_scene()` / load `main.tscn`) and `Menu`
  (`RunState.reset()` → `change_scene_to_file` to the start screen). The
  title-bar **`X` = Menu**.
- `setup(won, final_round, total, best, is_new)` mirrors
  `game_over_dialog.setup`'s style.

Endless's `game_over_dialog` is unchanged.

## 7. Start screen (5 options)

Current: a horizontal `Start`/`Quit` `ButtonRow` in `TitleDialog`, launch
glitch on Start. Changes:

- **Vertical button stack** in the body: **Easy, Medium, Hard, Endless**,
  a small gap, then **Quit**. The `TitleDialog` grows taller to fit
  (raise `custom_minimum_size` / offsets). The subtitle (random words)
  and the big title stay.
- **Each mode button** → `_on_mode_selected(Mode.X)`: set
  `RunState.mode`, run the existing launch glitch, then load
  `main.tscn`. **Quit** quits. The `_launching` gate disables **all**
  buttons during the glitch.
- **Keyboard:** Up/Down move through the buttons (Easy grabs focus on
  ready), Enter activates; mouse clicks work. Ensure the buttons are
  focusable and ordered (rely on Godot focus neighbours within the
  VBox; set them explicitly if auto-nav misbehaves).
- **Autoplay → Endless:** `_maybe_autoplay` selects Endless (the
  sim-relevant mode) instead of a generic Start.
- **No high scores on the menu** this version (they're empty at boot;
  shown on the popup). Easy to add beside each mode button once
  persistence exists.

`_on_start_pressed` / `_launch` generalise to take a target mode; the
glitch (`_play_launch_glitch`) is unchanged.

## 8. HUD (mode-aware)

`main.gd::_update_hud` gains the total and a mode-aware round display:

- Show **`Total: <total_score>`** (the number the player optimises).
- Round reads **`Round N / 5`** in difficulty modes, **`Round N`** in
  endless (same field, branch on `RunState.is_difficulty_mode()`).
- Keep the per-round **`<round_score> / <target>`**, `Turns left`, and
  `Tiles/turn` as-is.

Example: `Total: 142 | Round 3 / 5 | 24 / 40` and
`Turns left: 2 | Tiles/turn: 6`. Endless: `Round 3` (no `/ 5`).

## 9. Simulator (Endless-only, untouched)

- **No changes** to `game_core.gd`, `simulator.gd`, the strategies, or
  the sim tests. Difficulty modes (target tables, 5-round cap,
  `run_finished`, `total_score`, high scores) are **live-only**, never
  mirrored into the sim.
- **Hard constraint:** the `RunState` refactor must keep the **Endless
  path byte-identical** to today — don't change shared constants
  (`INITIAL_TARGET_SCORE`, `TURNS_PER_ROUND`, the Fib curve, the
  `tiles_per_turn`/discard/upgrade logic); only *add* a difficulty branch
  alongside the endless one.
- **Regression check:** run `scripts/sim/tests/run_tests.gd` after the
  refactor — the existing TC/TS/TSM cases exercise `game_core` (unchanged)
  and confirm no shared-constant drift. No new difficulty sim tests.
- **Doc note:** add a one-liner to `scripts/sim/README.md` that
  difficulty modes are live-only and intentionally NOT modeled in
  `game_core`, so a future agent doesn't try to mirror them.

## 10. Files touched / added

- **Edit:** `scripts/run_state.gd` (Mode enum, `mode`, `total_score`,
  `session_high_scores`, target tables, `run_finished`, 5-round cap,
  reset/advance/register branches), `scripts/main.gd` (HUD, `run_finished`
  handler → end popup, autoplay→Endless awareness), `scripts/start_screen.gd`
  + `scenes/start_screen.tscn` (5-option vertical menu), `scripts/sim/README.md`
  (live-only note).
- **Add:** `scripts/difficulty_end_dialog.gd` + `scenes/difficulty_end_dialog.tscn`.
- No new top-level dirs.

## 11. Out of scope (possible follow-ups)

- **Disk persistence** of high scores (`ConfigFile` at `user://`) — the
  in-memory dict is designed to drop into a save later.
- **Endless high score** / "rounds reached" tracking and popup.
- **High scores shown on the start screen** beside each mode.
- **Simulating difficulty modes** in `game_core` (per-difficulty strategy
  evaluation).
- **Per-mode tuning of other params** (turns, tiles, discards) — this
  version differs only by target numbers.
- Player name entry for high scores.
