# Start Screen Design — ScrabbleRabble 95

Agreed design for the title/start screen, including the "frozen window"
launch glitch. Decisions below were settled in design review (2026-06-12).

## Goal

A Windows 95–styled title screen shown on boot: a fake desktop with a
floating title dialog. Pressing Start triggers a once-per-launch
"hung window" ghost-smear effect, then launches the game.

## Scene flow

- **New standalone scene** `scenes/start_screen.tscn` + `scripts/start_screen.gd`,
  set as the project main scene in `project.godot` (replacing `main.tscn`).
- Start → `get_tree().change_scene_to_file("res://scenes/main.tscn")`.
- The in-game restart flow (`RunState.reset()` + `reload_current_scene()`)
  is unchanged — reloading `main.tscn` never resurrects the start screen.
- **`--autoplay` runs drive the menu like a user** — see
  "Simulation / autoplay mode" below.

## Composition

```
StartScreen (Control, 800x600)
  ├─ Desktop (ColorRect, Win95 desktop teal — Color(0, 0.5, 0.5))
  ├─ GhostLayer (Control, behind the dialog — holds stamped ghost frames)
  ├─ TitleDialog (Panel, theme_type_variation = "WindowFrame")
  │   └─ InnerVBox (2px inset)
  │       ├─ TitleBar (theme_type_variation = "TitleBar", text "ScrabbleRabble 95",
  │       │            Min/Max/Close "-" / "O" / "X" decoration buttons)
  │       └─ BodyArea (VBoxContainer)
  │           ├─ Big title: "ScrabbleRabble 95" — navy Color(0, 0, 0.5019), ~36px
  │           ├─ Subtitle: "A word game for Windows® 95" — black, 14px
  │           └─ ButtonRow: [Start] [Quit] — 88x24px each
  └─ CRTOverlay (CanvasLayer, layer 100 — shared scene, see below)
```

Mirrors the `scenes/game_over_dialog.tscn` chrome pattern exactly.
No taskbar, no desktop icons — desktop + dialog only.

## Buttons & input

- **Start** — grabs focus on ready (Enter/Space works immediately);
  launches the glitch transition.
- **Quit** — `get_tree().quit()`. Title-bar **X** wires to the same quit
  action (per CLAUDE.md convention).
- Keyboard: focus-based only (Tab/arrows between Start and Quit). No
  Esc-to-quit binding. Mouse works via normal Button behavior.
- **Input gating:** on Start press, set a `_launching` flag and disable
  both buttons immediately. The Start button stays visually pressed —
  this sells the "freeze". Same philosophy as `main.gd`'s
  `is_transitioning` guard.

## Launch glitch (frozen-window ghost smear)

Plays exactly once, on Start press, as the transition into the game.

Implementation: **node stamping** (no shaders, no viewport captures).

Timeline:
1. **Stutter** (~400 ms): everything freezes; Start stays sunken; no
   hover/focus changes.
2. **Staircase drag** (~700 ms): a tween moves `TitleDialog` along a
   staircase path — alternating right-then-down steps of ~16–24 px
   (discrete steps, NOT a smooth diagonal; the steps are what produce
   the staircase look). At each step, stamp a ghost:
   `TitleDialog.duplicate()` placed at the pre-step position inside
   `GhostLayer`, with `mouse_filter = MOUSE_FILTER_IGNORE` and
   processing disabled. Newer ghosts overlap older ones (authentic —
   the real artifact was stale unrepainted window regions).
   Expect ~10–15 ghosts total.
3. **Hold** (~300 ms) on the frozen mess.
4. **Hard cut** to `main.tscn` (no fade).

Tuning constants (step size, step count, durations) live as plain
script constants in `start_screen.gd`.

## CRT overlay

The start screen uses the **same CRT overlay** (scanlines + vignette +
chromatic aberration, CanvasLayer 100) as the game. It already exists
as a shared scene — `scenes/crt_overlay.tscn`, instanced by
`scenes/main.tscn` (line 35) — so the start screen just instances it
too. Ghost stamps render under it and get scanlined for free.

## Game-over dialog change

`game_over_dialog.gd`: **Quit (and X) now return to the title screen**
instead of quitting the app — `RunState.reset()` +
`change_scene_to_file("res://scenes/start_screen.tscn")`. Label stays
"Quit" (it quits the run). Restart remains the fast play-again path.
App exit lives only on the title screen.

## Simulation / autoplay mode

The project's "simulation mode" serves as informal end-to-end coverage
(there is no formal assert harness on the process). Three entry points,
affected differently:

### 1. `sim_runner.gd` / `tests/run_tests.gd` (`--script`) — unaffected

Both extend `SceneTree` and never load the main scene, so the start
screen cannot affect them. `game_core.gd` needs no changes: nothing in
this design touches scoring, progression, tile draw, or any mirrored
constant. No new sim test cases.

### 2. `--autoplay=<strategy>` — drives the start screen like a user

The main scene is now `start_screen.tscn`, so autoplay runs pass
through it. Decision: autoplay exercises the full menu path rather
than bypassing it.

- `start_screen.gd::_ready` checks `OS.get_cmdline_user_args()` for
  `--autoplay` / `--autoplay=` (same parsing as
  `main.gd::_autoplay_strategy_arg`). If present, it waits a short
  beat, then programmatically presses Start via the same handler a
  user would hit.
- **The launch glitch plays in full, unmodified** — no skip flag, no
  speed-up. A hung tween shows up as a missing "launching main scene"
  log line and a run that never reaches gameplay, which is the signal
  we want. Cost: ~1.4 s once per run.
- Tweens and `duplicate()` work under `--headless` (the SceneTree
  still processes; nothing is rendered), so this runs in CI.

### 3. End of an autoplay run — close the loop

Today an autoplay run stops at the game-over dialog and sits until the
process is killed. New behavior, in autoplay mode only:

- When the game-over dialog appears, auto-press **Quit** after a short
  delay (same pattern as `_autoplay_pick_upgrade_dialog`). This
  exercises the new game-over → title transition.
- Back at the start screen, the run terminates cleanly with
  `get_tree().quit()` (exit code 0).
- **Loop guard (required):** the `--autoplay` arg is still in the
  command line when the title screen is re-entered after a finished
  run. Without a guard, the start screen would press Start forever.
  Add a session flag on the autoload — `RunState.autoplay_run_completed`
  — set when an autoplay game ends (autoloads survive
  `change_scene_to_file`). Start screen logic:
  - autoplay arg present, flag false → press Start
  - autoplay arg present, flag true → log final summary, `quit()`

### Log contract

Structured logs are the observable contract for autoplay runs (grep
them ad hoc or from CI; no formal asserts exist). The canonical run:

```
godot --headless --path . -- --autoplay=word_search
```

must emit, in order:

```
[StartScreen] ready — menu shown
[StartScreen] autoplay detected — pressing Start
[StartScreen] launch glitch — N ghosts stamped   (N > 0)
[StartScreen] launching main scene
... existing [RunState] / [Turn] / [Autoplay] gameplay logs ...
[StartScreen] run complete — quitting
```

and exit with code 0. The ghost count doubles as a cheap regression
check: a stamping refactor that breaks the effect reads `0 ghosts`
while the transition still "works". Also document this command and
contract in `scripts/sim/README.md` when implementing.

## Explicitly out of scope (possible follow-ups)

- Taskbar / Start button / desktop icons
- "How to play" dialog, options, high scores (no persistence exists)
- Draggable title dialog (easter egg; ~15 lines if wanted later)
- Idle-time ambient ghosting (the gag lands best once, on launch)
- Audio (project has no audio assets)

## Conventions to honor (from CLAUDE.md)

- Structured logging with a new prefix, e.g.
  `print("[StartScreen] launch glitch — %d ghosts" % ghost_count)`.
- snake_case files/nodes; theme via `themes/win95.tres` (project default).
- `Control.size` is (0,0) before first layout — center the dialog with
  `custom_minimum_size`, as `main.gd` does for the game-over dialog.
