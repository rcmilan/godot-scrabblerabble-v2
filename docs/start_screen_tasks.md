# Start Screen — Implementation Tasks

Implementation plan for `docs/start_screen_design.md`. Read that file
first; this file tells you *what to build in what order*, the design
doc tells you *why*.

## How to work through this file

- Do the slices **in order**. Each slice leaves the game fully working
  (boots, plays, and the autoplay run still completes), so you can
  commit and push after every slice.
- Run the **verification steps at the end of each slice** before
  moving on. If a verification fails, fix the slice — do not start the
  next one.
- One commit per slice. Commit message style: short headline
  (`feat: ...` / `fix: ...`) + 2–5 body lines, like recent commits.
- Conventions that apply to every slice (from `CLAUDE.md`):
  - snake_case for files, node names in scripts, variables, functions.
  - Log every state transition with the `[StartScreen]` prefix, e.g.
    `print("[StartScreen] launching main scene")`.
  - The project theme `res://themes/win95.tres` is the default for all
    Controls — do NOT set `theme` on nodes; use
    `theme_type_variation` where named (exception: a root node parented
    to a `CanvasLayer` would need the theme set explicitly, but nothing
    in this plan does that).
  - No comments that restate code.

## Facts you need (verified against the codebase)

- `scenes/crt_overlay.tscn` **already exists** as a shared scene —
  `main.tscn` instances it (`scenes/main.tscn` line 35). Just instance
  it; do not create or extract anything.
- `project.godot` line 18 sets the main scene by UID:
  `run/main_scene="uid://cao1bxd4y4usx"`. Replace the value with the
  plain path string `"res://scenes/start_screen.tscn"` — paths are
  valid here.
- Copy dialog chrome structure from `scenes/game_over_dialog.tscn` and
  button wiring style from `scripts/game_over_dialog.gd`.
- Autoplay arg parsing to mirror: `main.gd::_autoplay_strategy_arg`
  (lines 414–420) — checks `OS.get_cmdline_user_args()` for
  `--autoplay` or `--autoplay=<strategy>`.
- Window is 800×600. Win95 navy is `Color(0, 0, 0.5019)`. Desktop teal
  is `Color(0, 0.5, 0.5)` (new to this feature; hardcode it in the
  scene, it is not in the theme).
- `Control.size` is `(0, 0)` before the first layout pass — center the
  dialog using `custom_minimum_size`, exactly like `main.gd` lines
  396–399 do for the game-over dialog.

---

## Slice 1 — Boot into a working start screen

**Goal:** the game boots to a Win95 desktop with a title dialog. Start
launches the game (instant scene change, no glitch yet). Quit and the
title-bar X exit the app. Autoplay runs still work end-to-end.

### 1a. Create `scenes/start_screen.tscn`

Node tree (build by hand-writing the `.tscn` mirroring
`game_over_dialog.tscn`'s syntax, or via the editor):

```
StartScreen (Control)                      ← anchors full rect, script: start_screen.gd
├─ Desktop (ColorRect)                     ← anchors full rect, color Color(0, 0.5, 0.5, 1)
├─ GhostLayer (Control)                    ← anchors full rect, mouse_filter = 2 (IGNORE)
├─ TitleDialog (Panel)                     ← theme_type_variation "WindowFrame",
│  │                                          custom_minimum_size Vector2(360, 220),
│  │                                          NO script on this node (important: it gets
│  │                                          duplicate()d in slice 4; a script on it
│  │                                          would be duplicated too)
│  └─ InnerVBox (VBoxContainer)            ← anchors full rect, 2px offsets on all sides
│     │                                       (offset_left/top = 2, right/bottom = -2)
│     ├─ TitleBar (Panel)                  ← custom_minimum_size (0, 22),
│     │  │                                    theme_type_variation "TitleBar"
│     │  └─ TitleContent (HBoxContainer)   ← anchors full rect, offset_left 4, offset_right -2
│     │     ├─ TitleLabel (Label)          ← text "ScrabbleRabble 95", white font color,
│     │     │                                 size_flags_horizontal = 3
│     │     └─ WinButtons (HBoxContainer)  ← separation 2; three Buttons "-" / "O" / "X",
│     │                                       each 16×14, focus_mode = 0
│     │                                       (copy MinBtn/MaxBtn/CloseBtn verbatim from
│     │                                        game_over_dialog.tscn)
│     └─ BodyArea (VBoxContainer)          ← size_flags_vertical = 3, alignment = 1 (center)
│        ├─ BigTitle (Label)               ← text "ScrabbleRabble 95",
│        │                                    horizontal_alignment = 1,
│        │                                    theme_override_font_sizes/font_size = 36,
│        │                                    theme_override_colors/font_color = Color(0, 0, 0.5019, 1)
│        ├─ Subtitle (Label)               ← text "A word game for Windows® 95",
│        │                                    horizontal_alignment = 1
│        ├─ MidSpacer (Control)            ← custom_minimum_size (0, 12)
│        └─ ButtonRow (HBoxContainer)      ← alignment = 1
│           ├─ StartButton (Button)        ← text "Start", custom_minimum_size (88, 24)
│           ├─ Gap (Control)               ← custom_minimum_size (12, 0)
│           └─ QuitButton (Button)         ← text "Quit", custom_minimum_size (88, 24)
└─ CRTOverlay                              ← instance of res://scenes/crt_overlay.tscn
```

Order matters: `Desktop` first, then `GhostLayer`, then `TitleDialog`,
so ghosts (slice 4) render between desktop and dialog. `CRTOverlay` is
a CanvasLayer (layer 100) so its position in the list doesn't matter,
but keep it last for readability.

### 1b. Create `scripts/start_screen.gd`

```gdscript
extends Control

@onready var title_dialog: Panel  = $TitleDialog
@onready var start_button: Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/StartButton
@onready var quit_button:  Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/QuitButton
@onready var close_btn:    Button = $TitleDialog/InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _launching: bool = false

func _ready() -> void:
    var vp_size := Vector2(get_viewport_rect().size)
    title_dialog.position = (vp_size - title_dialog.custom_minimum_size) / 2.0
    start_button.pressed.connect(_on_start_pressed)
    quit_button.pressed.connect(_on_quit_pressed)
    close_btn.pressed.connect(_on_quit_pressed)
    start_button.grab_focus()
    print("[StartScreen] ready — menu shown")
    _maybe_autoplay()

func _on_start_pressed() -> void:
    if _launching:
        return
    _launching = true
    start_button.disabled = true
    quit_button.disabled = true
    _launch()

func _launch() -> void:
    print("[StartScreen] launching main scene")
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
    if _launching:
        return
    print("[StartScreen] quit")
    get_tree().quit()

func _has_autoplay_arg() -> bool:
    for raw in OS.get_cmdline_user_args():
        if raw == "--autoplay" or raw.begins_with("--autoplay="):
            return true
    return false

func _maybe_autoplay() -> void:
    if not _has_autoplay_arg():
        return
    print("[StartScreen] autoplay detected — pressing Start")
    await get_tree().create_timer(0.3).timeout
    _on_start_pressed()
```

### 1c. Point the project at the new scene

In `project.godot`, change line 18 to:

```
run/main_scene="res://scenes/start_screen.tscn"
```

### Verify slice 1

1. Sim tests still pass (they never load scenes, but always check):
   `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
   → all TC/TS/TSM cases pass.
2. Autoplay still reaches gameplay:
   `timeout 60 godot --headless --path . -- --autoplay=word_search`
   (it will NOT exit on its own yet — the timeout is expected to kill
   it; that is today's pre-existing behavior, fixed in slice 3).
   The log must contain, in order: `[StartScreen] ready — menu shown`,
   `[StartScreen] autoplay detected — pressing Start`,
   `[StartScreen] launching main scene`, then `[Autoplay] starting`
   and `[RunState]` / `[Turn]` gameplay lines.
3. If you can run with a window: boot the game, see teal desktop +
   dialog, press Enter (Start has focus) → game starts; relaunch and
   click Quit and X → app exits.

Commit slice 1.

---

## Slice 2 — Game-over Quit returns to the title screen

**Goal:** the game-over dialog's Quit button and title-bar X go back to
the start screen instead of killing the app. Restart is unchanged.

Edit `scripts/game_over_dialog.gd` only — change `_on_quit`:

```gdscript
func _on_quit() -> void:
    print("[GameOverDialog] quit — returning to title")
    RunState.reset()
    get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
```

Do NOT touch `_on_restart`, the button labels, or the scene file. The
X button already routes to `_on_quit` (line 18), so it follows along.

### Verify slice 2

1. Sim tests:
   `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd` → pass.
2. Autoplay run with timeout as in slice 1 → unchanged behavior
   (stops at the game-over dialog; killed by timeout).
3. With a window: play until game over (or force it: lose round 1 by
   placing nothing and pressing END TURN 3 times), click Quit on the
   game-over dialog → you land on the start screen; click Start →
   a fresh game begins at round 1.

Commit slice 2.

---

## Slice 3 — Autoplay closes the loop and exits cleanly

**Goal:** a headless `--autoplay` run finishes by itself with exit
code 0: game over → auto-press Quit → back at title → quit. Without
the guard flag this slice adds, the run would loop forever — read
carefully.

### 3a. Add the guard flag to `scripts/run_state.gd`

Add one variable near the other flags (around line 21):

```gdscript
var autoplay_run_completed: bool = false
```

Do NOT reset it inside `reset()` — it must survive the return to the
title screen. It is set in exactly one place (3b) and read in exactly
one place (3c).

### 3b. Auto-press Quit at game over, in `scripts/main.gd`

`_on_game_over` (line 386) already sets `_autoplay_active = false` and
builds the dialog. The dialog variable is `dialog`. At the end of
`_on_game_over`, add — keyed on whether this run was an autoplay run:

```gdscript
if _autoplay_strategy_arg() != "":
    RunState.autoplay_run_completed = true
    _autoplay_quit_game_over(dialog)
```

And add the helper (place it near the other `_autoplay_*` helpers,
mirroring `_autoplay_pick_upgrade_dialog` at line 381):

```gdscript
func _autoplay_quit_game_over(dialog: Panel) -> void:
    await get_tree().create_timer(1.0).timeout
    if is_instance_valid(dialog):
        print("[Autoplay] game over — quitting to title")
        dialog._on_quit()
```

Note: key on `_autoplay_strategy_arg() != ""` (the CLI arg), not on
`_autoplay_active` — `_on_game_over` has already set that to false by
this point, and autoplay can also stop itself mid-run when no
placement is found.

### 3c. Quit at the title after a completed run, in `scripts/start_screen.gd`

Replace `_maybe_autoplay` with:

```gdscript
func _maybe_autoplay() -> void:
    if not _has_autoplay_arg():
        return
    if RunState.autoplay_run_completed:
        print("[StartScreen] run complete — quitting")
        get_tree().quit()
        return
    print("[StartScreen] autoplay detected — pressing Start")
    await get_tree().create_timer(0.3).timeout
    _on_start_pressed()
```

### Verify slice 3

1. Sim tests → pass.
2. The full loop now self-terminates:
   `timeout 120 godot --headless --path . -- --autoplay=word_search; echo "exit: $?"`
   → exit code 0 (NOT 124 — 124 means the timeout killed it, i.e. the
   loop did not close; re-check 3a–3c). The log must show, in order:
   `[StartScreen] ready — menu shown` →
   `[StartScreen] autoplay detected — pressing Start` →
   `[StartScreen] launching main scene` → gameplay logs →
   `[Autoplay] game over — quitting to title` →
   `[GameOverDialog] quit — returning to title` →
   `[StartScreen] ready — menu shown` (second time) →
   `[StartScreen] run complete — quitting`.
3. Run it twice with different strategies (`greedy`, `random`) to be
   sure the exit isn't a fluke of one game's length.

Commit slice 3.

---

## Slice 4 — The launch glitch (frozen-window ghost smear)

**Goal:** pressing Start no longer cuts straight to the game. Instead:
~0.4 s freeze → ~0.7 s staircase drag stamping ghost copies of the
dialog → ~0.3 s hold → cut to `main.tscn`. Plays identically in normal
and autoplay runs (this is deliberate — see the design doc).

All changes in `scripts/start_screen.gd`.

### 4a. Constants

```gdscript
const GLITCH_FREEZE_SEC: float = 0.4
const GLITCH_HOLD_SEC:   float = 0.3
const GHOST_STEP_PX:     float = 20.0
const GHOST_STEPS:       int   = 12
const GHOST_STEP_SEC:    float = 0.06   # 12 steps ≈ 0.7 s
```

### 4b. Replace the body of `_on_start_pressed`'s launch path

`_on_start_pressed` stays as-is (gate, disable buttons) but instead of
calling `_launch()` directly it calls `_play_launch_glitch()`:

```gdscript
func _play_launch_glitch() -> void:
    await get_tree().create_timer(GLITCH_FREEZE_SEC).timeout
    var ghost_count := 0
    for i in GHOST_STEPS:
        var ghost := title_dialog.duplicate() as Panel
        ghost.position = title_dialog.position
        ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ghost.set_process(false)
        ghost.set_process_input(false)
        $GhostLayer.add_child(ghost)
        ghost_count += 1
        # Alternate right / down steps — discrete jumps, no tween,
        # so the trail reads as stamped frames (the staircase look).
        if i % 2 == 0:
            title_dialog.position.x += GHOST_STEP_PX
        else:
            title_dialog.position.y += GHOST_STEP_PX
        await get_tree().create_timer(GHOST_STEP_SEC).timeout
    print("[StartScreen] launch glitch — %d ghosts stamped" % ghost_count)
    await get_tree().create_timer(GLITCH_HOLD_SEC).timeout
    _launch()
```

Notes for this step:

- `duplicate()` on `TitleDialog` is safe because it carries no script
  (slice 1 made sure of that). The duplicated buttons are disabled
  already (we disabled the originals before the first stamp), and the
  ghost layer ignores mouse anyway.
- The ghosts are stamped BEFORE the dialog moves each step, so the
  trail starts at the original position — matching the real artifact.
- Do not add randomness. No `randi()`/`randf()` anywhere (CLAUDE.md
  rule), and determinism keeps the autoplay log stable.
- The hard cut to `main.tscn` is intentional. No fade.

### Verify slice 4

1. Sim tests → pass.
2. Full autoplay loop:
   `timeout 120 godot --headless --path . -- --autoplay=word_search; echo "exit: $?"`
   → exit 0, and the log now includes
   `[StartScreen] launch glitch — 12 ghosts stamped` between
   `pressing Start` and `launching main scene`. (Tweens/timers and
   `duplicate()` work headless; nothing renders but everything runs.)
3. With a window: press Start → button stays sunken, brief freeze,
   dialog staircases down-right leaving overlapping window copies,
   short hold, then the game appears. During the smear, clicking
   buttons and pressing Enter must do nothing.
4. Press Quit instead of Start on a fresh boot → still exits
   immediately (the gate in `_on_quit_pressed` only blocks during a
   launch).

Commit slice 4.

---

## Slice 5 — Document the contract

**Goal:** future agents can find the autoplay log contract where sim
documentation lives.

Append a short section to `scripts/sim/README.md` titled
"Start screen & the autoplay loop" containing:

- The canonical command:
  `godot --headless --path . -- --autoplay=word_search`
- The ordered log lines a healthy run emits (copy the list from
  "Log contract" in `docs/start_screen_design.md`) and that the
  process must exit 0 on its own.
- One line noting `RunState.autoplay_run_completed` is the loop guard
  and is intentionally NOT cleared by `RunState.reset()`.

### Verify slice 5

1. Sim tests one final time → pass.
2. One final full autoplay run → exit 0, all contract lines present
   in order.

Commit slice 5. Push the branch.

---

## Out of scope — do NOT build these

Taskbar, desktop icons, "How to play", options, high scores, a
draggable dialog, idle-time ghosting, audio, a `--skip-glitch` flag.
If something seems missing, check `docs/start_screen_design.md`
"Explicitly out of scope" before adding anything.
