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
- **`--autoplay` passthrough:** `main.gd::_maybe_start_autoplay` checks a
  CLI flag in `_ready`. The start screen must detect the same flag and skip
  straight to `main.tscn` (no menu, no glitch) so headless/autoplay runs
  keep working.

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
chromatic aberration, CanvasLayer 100) as the game. The overlay is
currently built inline in `scenes/main.tscn`; extract it to
`scenes/crt_overlay.tscn` and instance it in both scenes so the two
copies can't drift. Ghost stamps render under it and get scanlined for
free.

## Game-over dialog change

`game_over_dialog.gd`: **Quit (and X) now return to the title screen**
instead of quitting the app — `RunState.reset()` +
`change_scene_to_file("res://scenes/start_screen.tscn")`. Label stays
"Quit" (it quits the run). Restart remains the fast play-again path.
App exit lives only on the title screen.

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
- No sim impact: nothing here touches scoring/progression, so
  `scripts/sim/game_core.gd` needs no changes.
